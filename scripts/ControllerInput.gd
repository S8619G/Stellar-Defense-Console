extends Node
## 1.0.0 controller support for the console (Xbox-style and PlayStation-style pads
## through Godot's standard joypad mapping).
##
## Every controller event is handled here first and marked as handled, so Godot's
## built-in menu navigation never acts on it a second time. What a button does
## depends on what is on screen:
##   Battle:      the assigned battle actions (ControllerBindings.gd). The D-pad or
##                left stick shows a highlight on the console buttons, the center
##                special weapon and the EMP; while it shows, A presses it.
##   Menus:       Settings, Controller, missile bonus pick, game over. The D-pad or
##                left stick moves the highlight, A presses it and B goes back.
##                Left/right adjusts a highlighted volume slider.
##   Initials:    up/down changes the letter, left/right moves, A saves.
##   CHANGE:      the next button pressed is given to the action.
## MENU (Options) always opens or closes Settings and cancels a CHANGE.
##
## Battle actions go through the console's own buttons and handlers, so cooldowns,
## costs, eligibility and automatic options stay exactly as they are for the mouse.

const ControllerBindings = preload("res://scripts/ControllerBindings.gd")

## Stick movement smaller than this is ignored (stick drift).
@export_range(0.1, 0.9) var stick_dead_zone: float = 0.5
## A trigger counts as pressed above this and released below Trigger Release.
@export_range(0.2, 0.95) var trigger_press: float = 0.6
@export_range(0.05, 0.9) var trigger_release: float = 0.3
## Holding a direction repeats after this delay, then at this interval.
@export_range(0.1, 1.5) var repeat_delay: float = 0.4
@export_range(0.05, 0.5) var repeat_interval: float = 0.13
## Jump needs the button held this long.
@export_range(0.5, 3.0) var jump_hold_seconds: float = 1.0
## The battle highlight hides after this long without a direction; A then launches again.
@export_range(2.0, 30.0) var battle_highlight_seconds: float = 6.0
@export var highlight_color := Color(1.0, 0.89, 0.55, 0.9)

var console: Control
var bindings: Dictionary = ControllerBindings.defaults()
var bindings_file: String = "user://controller_bindings.cfg"
var bindings_saved: bool = true
## Device whose input is followed (-1 = none yet). Another pad takes over on a press.
var active_device: int = -1
## Buttons currently held on the active device (button id -> true).
var held: Dictionary = {}
var trigger_down := {"lt": false, "rt": false}
var stick_direction := Vector2i.ZERO
var dpad_direction := Vector2i.ZERO
var repeat_timer: float = 0.0
## Jump hold in progress ("" = none).
var jump_hold_button: String = ""
var jump_elapsed: float = 0.0
var jumps_fired: int = 0
var jump_holds_cancelled: int = 0
var last_cancel_reason: String = ""
## Battle highlight.
var battle_highlight_visible: bool = false
var battle_highlight_idle: float = 0.0
var target: Control
var overlay: Control
var presses: int = 0
## Any controller input seen (menus show the highlight only after that).
var used_controller: bool = false
var connection_events: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = Control.new()
	overlay.name = "ControllerHighlight"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)
	if console:
		console.add_child(overlay)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		active_device = pads[0]

func load_saved() -> void:
	bindings = ControllerBindings.load_bindings(bindings_file)

func set_bindings(new_bindings: Dictionary) -> void:
	bindings = ControllerBindings.clean(new_bindings)
	cancel_jump("bindings changed")
	bindings_saved = ControllerBindings.save_bindings(bindings_file, bindings)
	if not bindings_saved:
		_log("controller buttons could not be saved")

# ------------------------------------------------------------------
# Context
# ------------------------------------------------------------------
## Which screen receives controller input now.
func context() -> String:
	if not is_instance_valid(console):
		return "none"
	var panel: Control = console.controller_panel
	if is_instance_valid(panel) and panel.visible:
		return "capture" if panel.is_capturing() else "controller"
	if console.settings_open:
		return "settings"
	if console.bonus_pick_open:
		return "bonus"
	if console.game_over_panel.visible:
		return "initials" if console.entry_active else "game_over"
	return "battle"

func is_menu_context(name: String) -> bool:
	return name in ["controller", "settings", "bonus", "game_over"]

## Controls the highlight can move between on the current screen.
func targets() -> Array[Control]:
	var found: Array[Control] = []
	match context():
		"controller":
			found = console.controller_panel.focus_targets()
		"settings":
			for node in console.settings_panel.panel.find_children("*", "", true, false):
				if (node is BaseButton or node is HSlider) and node.is_visible_in_tree() and node.focus_mode != Control.FOCUS_NONE:
					found.append(node)
		"bonus":
			found = [console.bonus_pick_panel.keep_button, console.bonus_pick_panel.take_button]
		"game_over":
			found = [console.restart_button, console.game_over_quit_button]
		"battle":
			for button in [console.repair_button, console.jump_button, console.prox_button, console.firewall_button, console.launch_button, console.gunship_button, console.gear_button]:
				found.append(button)
			var ship: Control = console.get_node("ShipStatus")
			for special in [ship.stealth_button, ship.emp_button, console.emp_split_button]:
				if is_instance_valid(special) and special.is_visible_in_tree():
					found.append(special)
	var usable: Array[Control] = []
	for control in found:
		if is_instance_valid(control) and control.is_visible_in_tree():
			usable.append(control)
	return usable

# ------------------------------------------------------------------
# Input
# ------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		used_controller = true
		_on_button_event(event.device, event.button_index, event.pressed)
	elif event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		_on_motion_event(event.device, event.axis, event.axis_value)
	elif event is InputEventMouseButton and event.pressed and battle_highlight_visible:
		# Back to the mouse: the battle highlight steps aside.
		hide_battle_highlight()

func _take_device(device: int) -> void:
	if device == active_device:
		return
	if active_device != -1:
		cancel_jump("controller changed")
	active_device = device
	held.clear()
	trigger_down = {"lt": false, "rt": false}
	stick_direction = Vector2i.ZERO
	dpad_direction = Vector2i.ZERO

func _on_button_event(device: int, index: int, pressed: bool) -> void:
	if pressed:
		_take_device(device)
	elif device != active_device:
		return
	var id := button_id(index)
	if id.begins_with("dpad"):
		var dir: Vector2i = {"dpad_up": Vector2i.UP, "dpad_down": Vector2i.DOWN, "dpad_left": Vector2i.LEFT, "dpad_right": Vector2i.RIGHT}[id]
		if pressed and not held.get(id, false):
			held[id] = true
			dpad_direction = dir
			_direction_pressed(dir)
			repeat_timer = repeat_delay
		elif not pressed:
			held.erase(id)
			if dpad_direction == dir:
				dpad_direction = Vector2i.ZERO
		return
	if pressed:
		if held.get(id, false):
			return  # already down: no repeated action from one press
		held[id] = true
		_press(id)
	else:
		held.erase(id)
		_release(id)

func _on_motion_event(device: int, axis: int, value: float) -> void:
	if axis == JOY_AXIS_TRIGGER_LEFT or axis == JOY_AXIS_TRIGGER_RIGHT:
		var id := "lt" if axis == JOY_AXIS_TRIGGER_LEFT else "rt"
		if not trigger_down[id] and value >= trigger_press:
			_take_device(device)
			trigger_down[id] = true
			_on_trigger(id, true)
		elif trigger_down[id] and value <= trigger_release and device == active_device:
			trigger_down[id] = false
			_on_trigger(id, false)
		return
	if axis != JOY_AXIS_LEFT_X and axis != JOY_AXIS_LEFT_Y:
		return  # right stick has no action
	if device != active_device and absf(value) < stick_dead_zone:
		return
	var x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var y := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	# Synthetic or very fresh events may not be in Input yet; trust the event itself.
	if axis == JOY_AXIS_LEFT_X:
		x = value
	else:
		y = value
	var dir := stick_to_direction(Vector2(x, y), stick_dead_zone)
	if dir != stick_direction:
		if dir != Vector2i.ZERO:
			_take_device(device)
			used_controller = true
			_direction_pressed(dir)
			repeat_timer = repeat_delay
		stick_direction = dir

func _on_trigger(id: String, pressed: bool) -> void:
	if pressed:
		held[id] = true
		_press(id)
	else:
		held.erase(id)
		_release(id)

## Stick position to one of four directions, or none inside the dead zone.
static func stick_to_direction(stick: Vector2, dead_zone: float) -> Vector2i:
	if stick.length() < dead_zone:
		return Vector2i.ZERO
	if absf(stick.x) >= absf(stick.y):
		return Vector2i(int(signf(stick.x)), 0)
	return Vector2i(0, int(signf(stick.y)))

static func button_id(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "a"
		JOY_BUTTON_B: return "b"
		JOY_BUTTON_X: return "x"
		JOY_BUTTON_Y: return "y"
		JOY_BUTTON_LEFT_SHOULDER: return "lb"
		JOY_BUTTON_RIGHT_SHOULDER: return "rb"
		JOY_BUTTON_START: return "menu"
		JOY_BUTTON_BACK: return "view"
		JOY_BUTTON_GUIDE: return "guide"
		JOY_BUTTON_LEFT_STICK: return "l3"
		JOY_BUTTON_RIGHT_STICK: return "r3"
		JOY_BUTTON_DPAD_UP: return "dpad_up"
		JOY_BUTTON_DPAD_DOWN: return "dpad_down"
		JOY_BUTTON_DPAD_LEFT: return "dpad_left"
		JOY_BUTTON_DPAD_RIGHT: return "dpad_right"
	return "other%d" % index

func _press(id: String) -> void:
	presses += 1
	if is_instance_valid(console) and is_instance_valid(console.session_log) and console.session_log.has_method("count_controller_press"):
		console.session_log.count_controller_press()
	var where := context()
	if id == "menu":
		_on_menu(where)
		return
	match where:
		"capture":
			console.controller_panel.capture(id)
		"controller", "settings", "bonus", "game_over":
			if id == "a":
				activate(current_target())
			elif id == "b":
				_back(where)
		"initials":
			if id == "a":
				console.submit_initials()
		"battle":
			if id == "a" and battle_highlight_visible:
				var chosen := current_target()
				if chosen == console.jump_button:
					# Jump keeps its one-second hold, even from the highlight.
					start_jump(id)
				else:
					activate(chosen)
				battle_highlight_idle = 0.0
				return
			var action := ControllerBindings.action_for(bindings, id)
			if action != "":
				perform(action, id)

func _release(id: String) -> void:
	if id == jump_hold_button:
		cancel_jump("released early")

func _on_menu(where: String) -> void:
	cancel_jump("menu")
	match where:
		"capture":
			console.controller_panel.cancel_capture()
		"controller":
			console.close_controller_panel()
			console.close_settings()
		"bonus":
			pass  # the pick must be answered (or times out); Settings stays closed
		_:
			console.toggle_settings()
	_after_context_change()

func _back(where: String) -> void:
	match where:
		"controller":
			console.controller_panel.back()
		"settings":
			console.close_settings()
	_after_context_change()

func _after_context_change() -> void:
	target = null
	if is_menu_context(context()):
		current_target()
	overlay.queue_redraw()

# ------------------------------------------------------------------
# Battle actions (through the console's own buttons)
# ------------------------------------------------------------------
func perform(action: String, from_button: String = "") -> bool:
	if context() != "battle":
		return false
	match action:
		"launch_interceptors":
			return _press_button(console.launch_button)
		"defense_shield":
			return _press_button(console.prox_button)
		"launch_gunship":
			return _press_button(console.gunship_button)
		"firewall":
			return _press_button(console.firewall_button)
		"rapid_repair":
			return _press_button(console.repair_button)
		"jump":
			return start_jump(from_button)
	return false

## Press a console button the way a click would: nothing happens while it is greyed out.
func _press_button(button: BaseButton) -> bool:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		return false
	if button.toggle_mode:
		if button.button_group != null:
			if not button.button_pressed:
				button.button_pressed = true
			button.pressed.emit()
		else:
			button.button_pressed = not button.button_pressed
	else:
		button.pressed.emit()
	return true

func start_jump(from_button: String) -> bool:
	if console.jump_button.disabled:
		return false
	jump_hold_button = from_button if from_button != "" else "jump"
	jump_elapsed = 0.0
	overlay.queue_redraw()
	return true

func cancel_jump(reason: String) -> void:
	if jump_hold_button == "":
		return
	jump_hold_button = ""
	jump_elapsed = 0.0
	jump_holds_cancelled += 1
	last_cancel_reason = reason
	overlay.queue_redraw()

func jump_progress() -> float:
	return clampf(jump_elapsed / maxf(0.01, jump_hold_seconds), 0.0, 1.0) if jump_hold_button != "" else 0.0

func _update_jump(delta: float) -> void:
	if jump_hold_button == "":
		return
	if context() != "battle":
		cancel_jump("screen changed")
		return
	if console.jump_button.disabled or console.contacts.is_defeated():
		cancel_jump("jump not available")
		return
	if jump_hold_button != "jump" and not held.get(jump_hold_button, false):
		cancel_jump("released early")
		return
	jump_elapsed += delta
	overlay.queue_redraw()
	if jump_elapsed >= jump_hold_seconds:
		jump_hold_button = ""
		jump_elapsed = 0.0
		jumps_fired += 1
		_press_button(console.jump_button)

## Window focus lost, controller unplugged and similar: forget held buttons.
func release_all(reason: String) -> void:
	cancel_jump(reason)
	held.clear()
	trigger_down = {"lt": false, "rt": false}
	stick_direction = Vector2i.ZERO
	dpad_direction = Vector2i.ZERO

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var name := Input.get_joy_name(device) if connected else ""
	var line := "controller %s%s" % ["connected" if connected else "disconnected", (" | " + name.substr(0, 40)) if not name.is_empty() else ""]
	connection_events.append(line)
	_log(line)
	if connected:
		if active_device == -1:
			active_device = device
	elif device == active_device:
		release_all("controller disconnected")
		hide_battle_highlight()
		active_device = -1
		var pads := Input.get_connected_joypads()
		for pad in pads:
			if pad != device:
				active_device = pad
				break
	if is_instance_valid(console) and console.has_method("_on_controller_connection"):
		console._on_controller_connection()

func device_label() -> String:
	if active_device == -1 or not active_device in Input.get_connected_joypads():
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			return "NO CONTROLLER CONNECTED"
		return _pad_label(pads[0])
	return _pad_label(active_device)

func _pad_label(device: int) -> String:
	var name := Input.get_joy_name(device).to_upper()
	if name.is_empty():
		return "CONTROLLER CONNECTED"
	if is_playstation_name(name):
		return "PLAYSTATION CONTROLLER"
	if name.contains("XBOX") or name.contains("XINPUT"):
		return "XBOX CONTROLLER"
	return name.substr(0, 28)

static func is_playstation_name(name: String) -> bool:
	var upper := name.to_upper()
	return upper.contains("PS4") or upper.contains("PS5") or upper.contains("DUALSHOCK") or upper.contains("DUALSENSE") or upper.contains("SONY") or upper.contains("PLAYSTATION")

func uses_playstation_names() -> bool:
	var pads := Input.get_connected_joypads()
	var device := active_device if active_device in pads else (pads[0] if not pads.is_empty() else -1)
	return device != -1 and is_playstation_name(Input.get_joy_name(device))

func _log(text: String) -> void:
	if is_instance_valid(console) and console.has_method("log_event"):
		console.log_event(text)

# ------------------------------------------------------------------
# Highlight and navigation
# ------------------------------------------------------------------
func current_target() -> Control:
	var options := targets()
	if options.is_empty():
		target = null
		return null
	if is_instance_valid(target) and target in options:
		return target
	var owner := console.get_viewport().gui_get_focus_owner()
	if owner in options:
		target = owner
	elif context() == "battle":
		target = console.launch_button if console.launch_button in options else options[0]
	else:
		target = options[0]
	_focus(target)
	return target

func _direction_pressed(dir: Vector2i) -> void:
	var where := context()
	match where:
		"capture":
			return
		"initials":
			if dir == Vector2i.UP:
				console.change_letter(console.entry_slot, 1)
			elif dir == Vector2i.DOWN:
				console.change_letter(console.entry_slot, -1)
			elif dir == Vector2i.LEFT:
				console.entry_slot = maxi(0, console.entry_slot - 1)
				console._refresh_high_score_panel()
			else:
				console.entry_slot = mini(2, console.entry_slot + 1)
				console._refresh_high_score_panel()
			return
		"battle":
			battle_highlight_idle = 0.0
			if not battle_highlight_visible:
				battle_highlight_visible = true
				target = null
				current_target()
				overlay.queue_redraw()
				return
	var from := current_target()
	if from is HSlider and dir.x != 0:
		var slider := from as HSlider
		slider.value = clampf(slider.value + slider.step * dir.x, slider.min_value, slider.max_value)
		if slider == console.settings_panel.effects_slider:
			console.settings_panel.effects_preview.emit()
		return
	var next := neighbour(from, dir)
	if next != null:
		target = next
		_focus(next)
	overlay.queue_redraw()

## The nearest target in the pressed direction (screen geometry, not Godot's focus
## graph, so buttons that never take keyboard focus can still be reached).
func neighbour(from: Control, dir: Vector2i) -> Control:
	var options := targets()
	if from == null or not from in options:
		return options[0] if not options.is_empty() else null
	var origin := target_rect(from).get_center()
	var d := Vector2(dir)
	var best: Control = null
	var best_score := INF
	for option in options:
		if option == from:
			continue
		var rect := target_rect(option)
		var offset := rect.get_center() - origin
		var along := offset.dot(d)
		if along <= 4.0:
			continue
		var across := absf(offset.cross(d))
		var score := along + across * 2.5
		if score < best_score:
			best_score = score
			best = option
	return best

func target_rect(control: Control) -> Rect2:
	var xform := control.get_global_transform_with_canvas()
	return Rect2(xform.origin, control.size * xform.get_scale())

func _focus(control: Control) -> void:
	if control != null and control.focus_mode != Control.FOCUS_NONE and context() != "battle":
		control.grab_focus()

## Press the highlighted control (A).
func activate(control: Control) -> bool:
	if control == null:
		return false
	if control is BaseButton:
		var ok := _press_button(control)
		_after_activate()
		return ok
	return false

func _after_activate() -> void:
	# The screen may have changed (for example CLOSE or a bonus pick).
	if not is_instance_valid(target) or not target in targets():
		target = null
		if is_menu_context(context()):
			current_target()
	overlay.queue_redraw()

func hide_battle_highlight() -> void:
	if battle_highlight_visible:
		battle_highlight_visible = false
		overlay.queue_redraw()

func _process(delta: float) -> void:
	_update_jump(delta)
	var where := context()
	if where != "battle" and battle_highlight_visible:
		battle_highlight_visible = false
	if battle_highlight_visible:
		battle_highlight_idle += delta
		if battle_highlight_idle >= battle_highlight_seconds:
			hide_battle_highlight()
	var dir := dpad_direction if dpad_direction != Vector2i.ZERO else stick_direction
	if dir != Vector2i.ZERO:
		repeat_timer -= delta
		if repeat_timer <= 0.0:
			repeat_timer = repeat_interval
			_direction_pressed(dir)
	if is_menu_context(where) or battle_highlight_visible or jump_hold_button != "":
		overlay.queue_redraw()
	elif overlay.visible:
		overlay.queue_redraw()

func highlight_shown() -> bool:
	var where := context()
	return (is_menu_context(where) and active_device != -1 and used_controller) or (where == "battle" and battle_highlight_visible)

func _draw_overlay() -> void:
	if not is_instance_valid(console):
		return
	if jump_hold_button != "" and is_instance_valid(console.jump_button):
		var r := target_rect(console.jump_button)
		var bar := Rect2(r.position + Vector2(8, r.size.y - 9), Vector2((r.size.x - 16) * jump_progress(), 4))
		overlay.draw_rect(Rect2(bar.position, Vector2(r.size.x - 16, 4)), Color(0.2, 0.08, 0.14, 0.9))
		overlay.draw_rect(bar, Color(0.7, 0.86, 1.0, 0.95))
	if not highlight_shown():
		return
	var control := target if is_instance_valid(target) and target in targets() else null
	if control == null:
		return
	var inv := overlay.get_global_transform_with_canvas().affine_inverse()
	var ship: Control = console.get_node("ShipStatus")
	if control == ship.stealth_button:
		# Follow the special weapon's own outline, not its bounding box.
		var poly: PackedVector2Array = ship.center_weapon_points(ship.stealth_box)
		var closed := PackedVector2Array()
		var to_overlay := inv * ship.get_global_transform_with_canvas()
		for point in poly:
			closed.append(to_overlay * point)
		closed.append(closed[0])
		overlay.draw_polyline(closed, highlight_color, 3.0, true)
		return
	var rect := target_rect(control)
	rect = Rect2(inv * rect.position, rect.size / overlay.get_global_transform_with_canvas().get_scale())
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = highlight_color
	box.set_border_width_all(3)
	box.set_corner_radius_all(10)
	box.anti_aliasing = true
	box.draw(overlay.get_canvas_item(), rect.grow(4.0))
