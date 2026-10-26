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
##   Action list: (1.0.4, CHANGE in the Controller panel) the D-pad or left stick
##                moves the highlight, A picks, B goes back one step.
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
## 1.1.0: while a PULSE BOMB charge is held, the STEALTH WEAPON controller
## button fires NUKES on a short press, or the PULSE BOMB when held this long.
@export_range(0.5, 3.0) var stealth_pulse_hold_seconds: float = 1.0
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
## 1.1.0: STEALTH WEAPON hold in progress ("" = none).
var stealth_hold_button: String = ""
var stealth_hold_elapsed: float = 0.0
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
## 1.0.2: the last controller button seen (for the controller check) and how many
## controller events arrived in total, from any device.
var last_button_seen: String = ""
var events_seen: int = 0
## 1.0.2: battle flash on the console button a controller press used.
@export_range(0.1, 1.0) var press_flash_seconds: float = 0.3
var flash_control: Control
var flash_left: float = 0.0
## Godot's own log, read to find out whether the controller system started.
var engine_log_file: String = "user://logs/godot.log"
const DRIVER_FAILED_TEXT := "Couldn't initialize SDL joypad input driver"
## The engine log is read again at most this often for the status line.
const DRIVER_RECHECK_MSEC := 10000
var _driver_cached: String = ""
var _driver_checked_msec: int = -1

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
	# 1.1.1: the update pop-up is in front of everything.
	if "update_popup" in console and is_instance_valid(console.update_popup) and console.update_popup.visible:
		return "update"
	var panel: Control = console.controller_panel
	if is_instance_valid(panel) and panel.visible:
		if panel.is_picking():
			return "picker"
		return "test" if panel.is_testing() else "controller"
	if console.settings_open:
		return "settings"
	if console.bonus_pick_open:
		return "bonus"
	if console.game_over_panel.visible:
		return "initials" if console.entry_active else "game_over"
	return "battle"

func is_menu_context(name: String) -> bool:
	return name in ["controller", "picker", "settings", "bonus", "game_over", "update"]

## Controls the highlight can move between on the current screen.
func targets() -> Array[Control]:
	var found: Array[Control] = []
	match context():
		"controller", "picker":
			found = console.controller_panel.focus_targets()
		"update":
			found = console.update_popup.focus_targets()
		"settings":
			for node in console.settings_panel.panel.find_children("*", "", true, false):
				if (node is BaseButton or node is HSlider) and node.is_visible_in_tree() and node.focus_mode != Control.FOCUS_NONE:
					found.append(node)
		"bonus":
			# 1.0.5: the two cards are the pick buttons (YOU HAVE NOW first, highlighted).
			for card in console.bonus_pick_panel.cards:
				found.append(card)
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
		events_seen += 1
		_on_button_event(event.device, event.button_index, event.pressed)
	elif event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		events_seen += 1
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
	if pressed:
		last_button_seen = id
	_light(id, pressed)
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
			last_button_seen = "stick"
			_direction_pressed(dir)
			repeat_timer = repeat_delay
		stick_direction = dir
		_light("stick", dir != Vector2i.ZERO)

func _on_trigger(id: String, pressed: bool) -> void:
	_light(id, pressed)
	if pressed:
		last_button_seen = id
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

## 1.0.5: any controller button, trigger or stick/D-pad move stops the bonus pick
## countdown; the pop-up then waits for a pick.
func _note_bonus_input() -> void:
	if is_instance_valid(console) and context() == "bonus":
		console.bonus_pick_panel.stop_countdown("controller")

func _press(id: String) -> void:
	_note_bonus_input()
	presses += 1
	if is_instance_valid(console) and is_instance_valid(console.session_log) and console.session_log.has_method("count_controller_press"):
		console.session_log.count_controller_press()
	var where := context()
	if where == "test":
		# TEST BUTTONS: presses only light up their assignment; MENU ends the test.
		if id == "menu":
			console.controller_panel.stop_test()
			_after_context_change()
		return
	if id == "menu":
		_on_menu(where)
		return
	match where:
		"controller", "picker", "settings", "bonus", "game_over", "update":
			if id == "a":
				activate(current_target())
			elif id == "b":
				_back(where)
			elif where == "settings" and (id == "lb" or id == "rb"):
				# 1.1.1: LB / RB switch the Settings tabs.
				console.settings_panel.step_tab(-1 if id == "lb" else 1)
				_after_context_change()
		"initials":
			if id == "a":
				console.submit_initials()
		"battle":
			if id == "a" and battle_highlight_visible:
				var chosen := current_target()
				if chosen == console.jump_button:
					# Jump keeps its one-second hold, even from the highlight.
					start_jump(id)
				elif _stealth_ship() != null and chosen == _stealth_ship().stealth_button and _pulse_choice_offered():
					_start_stealth_hold(id)
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
	if id == stealth_hold_button:
		# Let go before the hold time: NUKES (the PULSE BOMB charge is kept).
		_end_stealth_hold()
		_fire_stealth(false)

func _on_menu(where: String) -> void:
	cancel_jump("menu")
	_end_stealth_hold()
	match where:
		"picker":
			# MENU closes the action list without a change; the panel stays open.
			console.controller_panel.cancel_picker()
		"controller":
			console.close_controller_panel()
			console.close_settings()
		"bonus":
			pass  # the pick must be answered (or times out); Settings stays closed
		"update":
			pass  # 1.1.1: the update pop-up must be answered first
		_:
			console.toggle_settings()
	_after_context_change()

func _back(where: String) -> void:
	match where:
		"controller", "picker":
			console.controller_panel.back()
		"settings":
			console.close_settings()
		"update":
			console.update_popup.back()
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
		"launch_stealth":
			# 1.0.4: the center special weapon, only while it is offered.
			var ship: Control = console.get_node_or_null("ShipStatus")
			if _pulse_choice_offered() and from_button != "":
				# 1.1.0: short press NUKES, hold 1 second PULSE BOMB.
				return _start_stealth_hold(from_button)
			if is_instance_valid(ship) and ship.stealth_button.is_visible_in_tree():
				return _fire_stealth(false) if _pulse_choice_offered() else _press_button(ship.stealth_button)
			return false
		"emp":
			# 1.0.4: the EMP half of the FIREWALL button, else the EMP on the ship.
			if is_instance_valid(console.emp_split_button) and console.emp_split_button.is_visible_in_tree():
				return _press_button(console.emp_split_button)
			var ship: Control = console.get_node_or_null("ShipStatus")
			return is_instance_valid(ship) and _press_button(ship.emp_button)
	return false

## Press a console button the way a click would: nothing happens while it is greyed out.
func _press_button(button: BaseButton) -> bool:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		return false
	if context() == "battle":
		# 1.0.2: the button the controller used lights up briefly.
		flash_control = button
		flash_left = press_flash_seconds
		if is_instance_valid(overlay):
			overlay.queue_redraw()
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

# ------------------------------------------------------------------
# 1.1.0: controller choice between NUKES and PULSE BOMB
# ------------------------------------------------------------------
func _stealth_ship() -> Control:
	if not is_instance_valid(console):
		return null
	var ship: Control = console.get_node_or_null("ShipStatus")
	return ship if is_instance_valid(ship) and ship.has_method("fire_stealth") else null

## Both weapons offered: the STEALTH WEAPON button is up and a PULSE BOMB charge is held.
func _pulse_choice_offered() -> bool:
	var ship := _stealth_ship()
	return ship != null and ship.stealth_button.is_visible_in_tree() and int(console.contacts.get("pulse_charges")) > 0

func _start_stealth_hold(from_button: String) -> bool:
	if stealth_hold_button != "":
		return true
	stealth_hold_button = from_button
	stealth_hold_elapsed = 0.0
	_set_hold_progress(0.0)
	return true

func _end_stealth_hold() -> void:
	stealth_hold_button = ""
	stealth_hold_elapsed = 0.0
	_set_hold_progress(-1.0)

func _set_hold_progress(value: float) -> void:
	var ship := _stealth_ship()
	if ship != null:
		ship.pulse_hold_progress = value

func _fire_stealth(use_pulse: bool) -> bool:
	var ship := _stealth_ship()
	if ship == null or not ship.stealth_button.is_visible_in_tree():
		return false
	flash_control = ship.stealth_button
	flash_left = press_flash_seconds
	if is_instance_valid(overlay):
		overlay.queue_redraw()
	return ship.fire_stealth(use_pulse)

func _update_stealth_hold(delta: float) -> void:
	if stealth_hold_button == "":
		return
	if context() != "battle" or not _pulse_choice_offered():
		_end_stealth_hold()
		return
	if not held.get(stealth_hold_button, false):
		_end_stealth_hold()
		_fire_stealth(false)
		return
	stealth_hold_elapsed += delta
	_set_hold_progress(clampf(stealth_hold_elapsed / maxf(0.01, stealth_pulse_hold_seconds), 0.0, 1.0))
	if stealth_hold_elapsed >= stealth_pulse_hold_seconds:
		_end_stealth_hold()
		_fire_stealth(true)

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
	_end_stealth_hold()
	held.clear()
	trigger_down = {"lt": false, "rt": false}
	stick_direction = Vector2i.ZERO
	dpad_direction = Vector2i.ZERO

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var name := Input.get_joy_name(device) if connected else ""
	var line := "controller %s%s" % ["connected" if connected else "disconnected", (" | " + name.substr(0, 40)) if not name.is_empty() else ""]
	connection_events.append(line)
	if connection_events.size() > 20:
		connection_events.remove_at(0)
	_log(line)
	if connected:
		_log("controller details | " + pad_summary(device))
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

# ------------------------------------------------------------------
# 1.0.2 connection status and controller check
# ------------------------------------------------------------------
## The controller the panel describes: the one in use, else the first connected.
func shown_device() -> int:
	var pads := Input.get_connected_joypads()
	if active_device in pads:
		return active_device
	return pads[0] if not pads.is_empty() else -1

## What the Controller panel shows: connected or not, name, compatible, connection.
func status() -> Dictionary:
	var pads := Input.get_connected_joypads()
	var device := shown_device()
	var out := {"connected": device != -1, "count": pads.size(), "name": "", "compatible": false,
		"connection": "", "driver": cached_driver_status()}
	if device != -1:
		out.name = _pad_label(device)
		out.compatible = Input.is_joy_known(device)
		out.connection = connection_type(Input.get_joy_guid(device), Input.get_joy_info(device))
	return out

## How the controller is attached, read from what Godot reports. On Windows, Xbox
## controllers usually arrive through XInput, which looks the same for a cable,
## Bluetooth and the Xbox Wireless Adapter.
static func connection_type(guid: String, info: Dictionary) -> String:
	if info.has("steam_input_index"):
		return "STEAM INPUT"
	if info.has("xinput_index"):
		return "XINPUT"
	var bus := guid.substr(0, 4).to_lower()
	if bus == "0500":
		return "BLUETOOTH"
	if bus == "0300":
		return "USB"
	return ""

## driver_status(), read again at most every 10 s (the panel asks twice a second).
func cached_driver_status() -> String:
	var now := Time.get_ticks_msec()
	if _driver_checked_msec < 0 or now - _driver_checked_msec >= DRIVER_RECHECK_MSEC:
		_driver_cached = driver_status()
		_driver_checked_msec = now
	return _driver_cached

## Whether the engine's controller system started: "started", "failed", "no window"
## (headless runs have no controller system) or "unknown" (log not readable).
func driver_status() -> String:
	if DisplayServer.get_name() == "headless":
		return "no window"
	var text := FileAccess.get_file_as_string(engine_log_file)
	if text.contains(DRIVER_FAILED_TEXT):
		return "failed"
	if text.is_empty():
		return "unknown"
	return "started"

## One line about one controller, for the log and the controller check. No serial
## numbers or other personal data.
func pad_summary(device: int) -> String:
	if not device in Input.get_connected_joypads():
		return "#%d not connected now" % device
	var info := Input.get_joy_info(device)
	var guid := Input.get_joy_guid(device)
	var connection := connection_type(guid, info)
	return "#%d %s | %s | connection %s | vendor %s product %s | GUID %s" % [
		device, Input.get_joy_name(device).substr(0, 60),
		"compatible" if Input.is_joy_known(device) else "not in the controller list",
		connection if connection != "" else "unknown",
		_hex_id(info.get("vendor_id", "")), _hex_id(info.get("product_id", "")), guid]

static func _hex_id(value) -> String:
	var text := str(value)
	if text.is_empty() or not text.is_valid_int():
		return "?"
	return "%04x" % int(text)

## Plain text the player can copy and send: what the game sees right now.
func check_report(version_text: String = "") -> String:
	var lines := PackedStringArray()
	lines.append("CONTROLLER CHECK%s" % ((" | " + version_text) if version_text != "" else ""))
	lines.append("System: %s %s | %s | Godot %s" % [OS.get_name(), OS.get_version(), Engine.get_architecture_name(), Engine.get_version_info().string])
	var driver := driver_status()
	lines.append("Controller system: %s" % {"started": "started", "failed": "DID NOT START (engine error)", "no window": "not used (no window)", "unknown": "unknown (log not readable)"}.get(driver, driver))
	var pads := Input.get_connected_joypads()
	lines.append("Controllers found: %d" % pads.size())
	for device in pads:
		lines.append("  " + pad_summary(device))
	lines.append("Controller events received: %d%s" % [events_seen, (" | last button " + last_button_seen.to_upper()) if last_button_seen != "" else ""])
	if connection_events.is_empty():
		lines.append("Connection changes: none")
	else:
		lines.append("Connection changes: " + "; ".join(connection_events.slice(-5)))
	return "\n".join(lines)

## Light up a pressed button in the Controller panel (any screen with it open).
func _light(id: String, pressed: bool) -> void:
	if not is_instance_valid(console):
		return
	var panel: Control = console.controller_panel
	if is_instance_valid(panel) and panel.visible:
		panel.light(id, pressed)

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
	_note_bonus_input()
	var where := context()
	match where:
		"test":
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
	_update_stealth_hold(delta)
	if flash_left > 0.0:
		flash_left -= delta
		if flash_left <= 0.0:
			flash_control = null
		overlay.queue_redraw()
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
	if flash_left > 0.0 and is_instance_valid(flash_control) and flash_control.is_visible_in_tree() and context() == "battle":
		var inv_f := overlay.get_global_transform_with_canvas().affine_inverse()
		var fr := target_rect(flash_control)
		fr = Rect2(inv_f * fr.position, fr.size / overlay.get_global_transform_with_canvas().get_scale())
		var strength := clampf(flash_left / maxf(0.01, press_flash_seconds), 0.0, 1.0)
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(highlight_color, 0.28 * strength)
		glow.border_color = Color(highlight_color, strength)
		glow.set_border_width_all(4)
		glow.set_corner_radius_all(10)
		glow.anti_aliasing = true
		glow.draw(overlay.get_canvas_item(), fr.grow(5.0))
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
