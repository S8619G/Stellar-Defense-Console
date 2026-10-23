extends Control
## 1.0.0 Controller panel, opened from Settings > CONTROLLER. Layout follows the
## approved reference (design/controller-1.3.1/mock_controller_layout_131.png): the
## controller drawing with two-line tags and pointer lines on the left, and the
## BUTTON / ACTION table with CHANGE on the right, then DEFAULTS and CLOSE.
## Built in code, in the same style as the Settings panel. The battle stays paused.
##
## 1.0.4: one row per controller button. CHANGE opens a list of every battle action
## (mouse, touch or controller); picking one closes the list and updates the row.
## When the action is already on another button, the player chooses SWAP, USE BOTH,
## MOVE IT HERE or CANCEL. TEST BUTTONS is unchanged.

signal bindings_changed(bindings: Dictionary)
signal close_requested

const ControllerBindings = preload("res://scripts/ControllerBindings.gd")
const OUTLINE := preload("res://assets/controller/controller_outline.png")
const EDGE := Color("#77324f")
const TEXT := Color("#ede0e8")
const MUTED := Color("#b9a8b2")
const ACCENT := Color(1.0, 0.6, 0.78)
const AMBER := Color("#ffe28b")
const PANEL_SIZE := Vector2(1300, 870)
## 1.0.3: size of the small round "!" that copies the controller check.
const CHECK_ICON_SIZE := 22.0
## Drawing: the prepared outline (483 x 360, white on transparent) at 70%.
const DRAWING_AT := Vector2(225, 262)
const DRAWING_SCALE := 0.7
## Button points in the outline image (source points minus the crop at 76, 93).
const POINTS := {
	"y": Vector2(366, 79), "x": Vector2(333, 116), "b": Vector2(400, 116), "a": Vector2(366, 153),
	"menu": Vector2(274, 120), "stick": Vector2(113, 116), "dpad": Vector2(179, 197),
	"lb": Vector2(70, 47), "rb": Vector2(413, 47), "lt": Vector2(129, 8), "rt": Vector2(354, 8),
}
## Tag anchors (panel coordinates): left tags end at x 200, right tags start at x 590.
const TAGS := {
	"lt": Vector2(200, 196), "lb": Vector2(200, 258), "dpad": Vector2(200, 400),
	"rt": Vector2(590, 196), "rb": Vector2(590, 258), "y": Vector2(590, 320),
	"b": Vector2(590, 382), "a": Vector2(590, 444), "menu": Vector2(417, 138), "x": Vector2(458, 566),
}
const ROW_TOP := 134.0
const ROW_STEP := 52.0
## 1.0.4 table columns: BUTTON, ACTION, then CHANGE at x 1144.
const BUTTON_COLUMN_X := 770.0
const BUTTON_COLUMN_W := 116.0
const ACTION_COLUMN_X := 892.0
const ACTION_COLUMN_W := 244.0
## 1.0.4 action list (pop-up) size and rows.
const PICKER_WIDTH := 620.0
const PICKER_ITEM_TOP := 92.0
const PICKER_ITEM_STEP := 56.0
const PICKER_ITEM_HEIGHT := 48.0
const CHOICE_ITEM_STEP := 84.0
const CHOICE_ITEM_HEIGHT := 72.0
const CONFIRM_SECONDS := 3.0
## 1.0.2: TEST BUTTONS ends by itself after this long without a press.
const TEST_IDLE_SECONDS := 20.0
## A lit button stays lit at least this long, so a quick tap is still visible.
const LIGHT_MIN_SECONDS := 0.35
## The connection status is checked again this often while the panel is open.
const STATUS_POLL_SECONDS := 0.5
const GREEN := Color("#7ee08a")
const TEST_START_TEXT := "TEST BUTTONS: press any controller button. Its action lights up here."
const LIGHT_BG := Color(1.0, 0.89, 0.55, 0.22)

## Inspector-style tint for the drawing and pointer lines (reference: #8c3a61).
var line_tint := Color("#8c3a61")
var bindings: Dictionary = ControllerBindings.defaults()
var playstation_names: bool = false
var device_text: String = "NO CONTROLLER CONNECTED"
var panel: Panel
var drawing: Control
var header_label: Label
var hint_label: Label
var defaults_button: Button
var close_button: Button
var rows: Array[Dictionary] = []
var row_layer: Control
## 1.0.4 action list: the button being changed ("" = list closed), the step
## ("list" or "choice") and, on the choice step, the action picked.
var picking_button: String = ""
var picker_step: String = "list"
var pending_action: String = ""
var picker_layer: Control
var picker_box: Panel
var picker_title: Label
var picker_subtitle: Label
var picker_items: Array[Button] = []
## Action (list step) or choice (choice step) of each item, in order.
var picker_values: Array[String] = []
var picker_cancel: Button
var defaults_armed: bool = false
var defaults_serial: int = 0
var notice: String = ""
## 1.0.2 connection status (from ControllerInput.status()) and its source.
var status: Dictionary = {}
var controller_input: Node
var status_label: Label
var status_poll: float = 0.0
## 1.0.2 lit buttons: key ("a", "lt", "dpad", "menu"...) -> {"down": bool, "left": seconds}.
var lit: Dictionary = {}
var glow_layer: Control
var testing: bool = false
var test_idle: float = 0.0
var test_presses: int = 0
var last_test_text: String = ""
var test_button: Button
var copy_button: Button
var copied_text: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	panel = Panel.new()
	panel.name = "Panel"
	panel.size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.015, 0.03, 0.98)
	style.border_color = Color(0.55, 0.23, 0.38)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_label("CONTROLLER", Vector2(44, 26), Vector2(400, 40), 30, ACCENT)
	header_label = _label("", Vector2(PANEL_SIZE.x - 744 - CHECK_ICON_SIZE - 14, 34), Vector2(700, 30), 18, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_divider(84)
	status_label = _label("", Vector2(44, 96), Vector2(700, 28), 18, MUTED)
	status_label.name = "Status"
	status_label.clip_text = true
	drawing = Control.new()
	drawing.name = "Drawing"
	drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawing.size = PANEL_SIZE
	drawing.draw.connect(_draw_controller)
	panel.add_child(drawing)
	glow_layer = Control.new()
	glow_layer.name = "Glow"
	glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_layer.size = PANEL_SIZE
	glow_layer.draw.connect(_draw_glow)
	panel.add_child(glow_layer)
	_label("BUTTON", Vector2(BUTTON_COLUMN_X, 100), Vector2(BUTTON_COLUMN_W, 24), 15, MUTED)
	_label("ACTION", Vector2(ACTION_COLUMN_X, 100), Vector2(ACTION_COLUMN_W, 24), 15, MUTED)
	row_layer = Control.new()
	row_layer.name = "Rows"
	row_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row_layer)
	hint_label = _label("", Vector2(44, 676), Vector2(PANEL_SIZE.x - 88, 80), 16, MUTED)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_divider(770)
	defaults_button = _button("DEFAULTS", Vector2(44, 790), Vector2(200, 56))
	defaults_button.name = "Defaults"
	defaults_button.pressed.connect(_on_defaults_pressed)
	test_button = _button("TEST BUTTONS", Vector2(318, 790), Vector2(250, 56))
	test_button.name = "TestButtons"
	test_button.pressed.connect(_on_test_pressed)
	# 1.0.3: the controller check is a small round "!" in the top-right corner
	# instead of a full-size COPY CONTROLLER CHECK button.
	copy_button = _check_icon()
	copy_button.position = Vector2(PANEL_SIZE.x - 44 - CHECK_ICON_SIZE, 38)
	copy_button.pressed.connect(_on_copy_pressed)
	close_button = _button("CLOSE", Vector2(PANEL_SIZE.x - 244, 790), Vector2(200, 56))
	close_button.name = "Close"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	_build_picker()
	resized.connect(_center_panel)
	_center_panel()

func _center_panel() -> void:
	if panel:
		panel.position = ((size - PANEL_SIZE) * 0.5).round()
		# Very small windows: shrink the panel to fit rather than clipping it.
		var fit := minf(1.0, minf(size.x / (PANEL_SIZE.x + 16.0), size.y / (PANEL_SIZE.y + 16.0)))
		panel.scale = Vector2.ONE * (fit if fit > 0.0 else 1.0)
		panel.position = ((size - PANEL_SIZE * panel.scale) * 0.5).round()

func open(current: Dictionary) -> void:
	bindings = ControllerBindings.clean(current)
	_hide_picker()
	defaults_armed = false
	notice = ""
	testing = false
	lit.clear()
	visible = true
	set_process(true)
	_center_panel()
	update_status()
	refresh()
	if not rows.is_empty():
		rows[0].button.grab_focus()

func close() -> void:
	_hide_picker()
	testing = false
	lit.clear()
	visible = false
	set_process(false)

## 1.0.4: the action list is open.
func is_picking() -> bool:
	return picking_button != ""

func is_testing() -> bool:
	return testing

# ------------------------------------------------------------------
# 1.0.2 connection status, TEST BUTTONS and the lights
# ------------------------------------------------------------------
## Reads the status again from the controller code (when known) and shows it.
func update_status() -> void:
	if is_instance_valid(controller_input) and controller_input.has_method("status"):
		status = controller_input.status()
		playstation_names = controller_input.uses_playstation_names()
	_show_status()

func status_text() -> String:
	if status.is_empty():
		return device_text
	if not status.get("connected", false):
		if status.get("driver", "") == "failed":
			return "NO CONTROLLER  |  CONTROLLER SYSTEM DID NOT START"
		return "NO CONTROLLER FOUND"
	var parts := PackedStringArray(["CONNECTED: %s" % str(status.name)])
	parts.append("COMPATIBLE" if status.get("compatible", false) else "NOT IN THE CONTROLLER LIST")
	if str(status.get("connection", "")) != "":
		parts.append(str(status.connection))
	if int(status.get("count", 1)) > 1:
		parts.append("%d CONTROLLERS" % int(status.count))
	return "  |  ".join(parts)

func _show_status() -> void:
	if not is_instance_valid(status_label):
		return
	var text := status_text()
	status_label.text = text
	status_label.add_theme_font_size_override("font_size", _fit(status_label.text, 18, 696.0))
	var color := MUTED
	if is_connected_pad():
		color = GREEN if status.get("compatible", false) or status.is_empty() else AMBER
	else:
		color = AMBER
	status_label.add_theme_color_override("font_color", color)
	device_text = text

func is_connected_pad() -> bool:
	if status.is_empty():
		return device_text != "NO CONTROLLER CONNECTED"
	return bool(status.get("connected", false))

## A controller button went down or up (from ControllerInput.gd).
func light(id: String, down: bool) -> void:
	var key := light_key(id)
	if key == "":
		return
	if down:
		lit[key] = {"down": true, "left": LIGHT_MIN_SECONDS}
		if testing:
			test_idle = 0.0
			test_presses += 1
			last_test_text = test_result(key)
			notice = last_test_text
			refresh()
	elif lit.has(key):
		lit[key].down = false
	_apply_lights()

## The panel key for a controller button id ("dpad_up" and "stick" -> "dpad").
static func light_key(id: String) -> String:
	if id.begins_with("dpad") or id == "stick":
		return "dpad"
	if id in ["a", "b", "x", "y", "lb", "rb", "lt", "rt", "menu"]:
		return id
	return ""

## What a pressed button does, in words, for TEST BUTTONS.
func test_result(key: String) -> String:
	var names := ControllerBindings.PLAYSTATION_NAMES if playstation_names else ControllerBindings.BUTTON_NAMES
	if key == "dpad":
		return "D-PAD / STICK works: it moves the highlight."
	if key == "menu":
		return "%s works: it opens Settings." % names.menu
	var action := ControllerBindings.action_for(bindings, key)
	if action == "":
		return "%s works. It has no battle action (use CHANGE to give it one)." % names[key]
	return "%s works: %s." % [names[key], ControllerBindings.action_name(action)]

func is_lit(key: String) -> bool:
	return lit.has(key)

## Row keys that light for the buttons now lit.
func lit_row_keys() -> Array[String]:
	var found: Array[String] = []
	for row in rows:
		if _row_lit(row):
			found.append(row.key)
	return found

func _row_lit(row: Dictionary) -> bool:
	var spec: Dictionary = row.spec
	match spec.kind:
		"button":
			return lit.has(spec.button)
		_:
			if spec.name == "SETTINGS / PAUSE":
				return lit.has("menu")
			if spec.name == "MOVE HIGHLIGHT":
				return lit.has("dpad")
	return false

func _apply_lights() -> void:
	for row in rows:
		var on := _row_lit(row)
		if not is_instance_valid(row.name_label):
			continue
		var spec: Dictionary = row.spec
		var name_color := TEXT
		if spec.kind == "button" and ControllerBindings.action_for(bindings, spec.button) == "":
			name_color = MUTED
		row.name_label.add_theme_color_override("font_color", AMBER if on else name_color)
		var keys_color := AMBER if (on or picking_button == spec.get("button", "-")) else ACCENT
		row.keys_label.add_theme_color_override("font_color", keys_color)
	if is_instance_valid(glow_layer):
		glow_layer.queue_redraw()
	if is_instance_valid(drawing):
		drawing.queue_redraw()

func _draw_glow() -> void:
	for i in range(rows.size()):
		if _row_lit(rows[i]):
			var y := ROW_TOP + i * ROW_STEP
			var box := StyleBoxFlat.new()
			box.bg_color = LIGHT_BG
			box.border_color = AMBER
			box.set_border_width_all(2)
			box.set_corner_radius_all(8)
			box.anti_aliasing = true
			box.draw(glow_layer.get_canvas_item(), Rect2(760, y - 2, 506, 48))

func start_test() -> void:
	_hide_picker()
	testing = true
	test_idle = 0.0
	test_presses = 0
	lit.clear()
	notice = TEST_START_TEXT
	refresh()

func stop_test() -> void:
	if not testing:
		return
	testing = false
	lit.clear()
	notice = "Test finished. %d button press%s seen." % [test_presses, "" if test_presses == 1 else "es"]
	refresh()

func _on_test_pressed() -> void:
	if testing:
		stop_test()
	else:
		start_test()

func _on_copy_pressed() -> void:
	var text := ""
	if is_instance_valid(controller_input) and controller_input.has_method("check_report"):
		var version := ""
		if is_instance_valid(controller_input.console) and controller_input.console.has_method("version_text"):
			version = controller_input.console.version_text()
		text = controller_input.check_report(version)
	else:
		text = "CONTROLLER CHECK\n" + status_text()
	copied_text = text
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
		notice = "Controller check copied. Paste it into a message to share what the game sees."
	else:
		notice = "Controller check written to the session log (Settings > ! opens the folder)."
	if is_instance_valid(controller_input) and controller_input.has_method("_log"):
		for line in text.split("\n"):
			controller_input._log("check | " + line.strip_edges())
	refresh()

## Rows (1.0.4): one per controller button (A, B, X, Y, LB, RB, LT, RT), then the
## two fixed rows.
func row_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for button in ControllerBindings.BUTTONS:
		specs.append({"kind": "button", "button": button})
	specs.append({"kind": "fixed", "name": "SETTINGS / PAUSE", "keys": "OPTIONS" if playstation_names else "MENU"})
	specs.append({"kind": "fixed", "name": "MOVE HIGHLIGHT", "keys": "D-PAD / STICK"})
	return specs

## Text in a button row's ACTION column.
func row_action_text(button: String) -> String:
	var action := ControllerBindings.action_for(bindings, button)
	var text := ControllerBindings.action_name(action)
	if action == "jump":
		text += "  (hold 1 s)"
	return text

## Row index of a controller button (-1 if none).
func row_index(button: String) -> int:
	for i in range(rows.size()):
		if rows[i].spec.get("button", "") == button:
			return i
	return -1

func refresh() -> void:
	var focused_key := ""
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for row in rows:
		if row.button == owner:
			focused_key = row.key
	for row in rows:
		row.button.queue_free()
		row.name_label.queue_free()
		row.keys_label.queue_free()
	rows.clear()
	var index := 0
	for spec in row_specs():
		var y := ROW_TOP + index * ROW_STEP
		var row := {"spec": spec}
		# name_label = the ACTION column, keys_label = the BUTTON column.
		match spec.kind:
			"button":
				row.key = "button:" + spec.button
				var button_text := ControllerBindings.button_name(spec.button, playstation_names)
				row.keys_label = _row_label(button_text, Vector2(BUTTON_COLUMN_X, y + 8), Vector2(BUTTON_COLUMN_W, 30), _fit(button_text, 18, BUTTON_COLUMN_W - 4.0), ACCENT)
				var action_text := row_action_text(spec.button)
				var unset := ControllerBindings.action_for(bindings, spec.button) == ""
				row.name_label = _row_label(action_text, Vector2(ACTION_COLUMN_X, y + 8), Vector2(ACTION_COLUMN_W, 30), _fit(action_text, 18, ACTION_COLUMN_W - 4.0), MUTED if unset else TEXT)
				row.button = _row_button("CHANGE", Vector2(1144, y), open_picker.bind(spec.button))
			_:
				row.key = "fixed:" + spec.name
				row.keys_label = _row_label(spec.keys, Vector2(BUTTON_COLUMN_X, y + 8), Vector2(BUTTON_COLUMN_W, 30), _fit(spec.keys, 18, BUTTON_COLUMN_W - 4.0), ACCENT)
				row.name_label = _row_label(spec.name, Vector2(ACTION_COLUMN_X, y + 8), Vector2(ACTION_COLUMN_W, 30), _fit(spec.name, 18, ACTION_COLUMN_W - 4.0), TEXT)
				row.button = _row_button("FIXED", Vector2(1144, y), Callable())
				row.button.disabled = true
				row.button.focus_mode = Control.FOCUS_NONE
		row.button.name = "Row%d" % index
		rows.append(row)
		index += 1
	if not is_picking():
		for row in rows:
			if row.key == focused_key and row.button.focus_mode != Control.FOCUS_NONE:
				row.button.grab_focus()
	_show_status()
	header_label.text = "BATTLE PAUSED"
	defaults_button.text = "CONFIRM" if defaults_armed else "DEFAULTS"
	test_button.text = "STOP TEST" if testing else "TEST BUTTONS"
	var lines := PackedStringArray()
	if testing:
		lines.append(notice if not notice.is_empty() else TEST_START_TEXT)
		lines.append("Press MENU (Options), Esc or STOP TEST to finish the test.")
	elif not notice.is_empty():
		lines.append(notice)
	elif not is_connected_pad():
		lines.append("No controller found. Turn the controller on, then pair it in the computer's Bluetooth settings, plug it in with a USB cable, or use an Xbox Wireless Adapter. This line updates by itself within a second.")
	else:
		lines.append("Press CHANGE next to a button, then pick its action from the list. A (Cross) presses the highlighted button in menus; B (Circle) goes back.")
	lines.append("In battle, the D-pad or left stick shows a highlight; A then presses it.")
	lines.append("PlayStation names: A = Cross, B = Circle, X = Square, Y = Triangle, RB/LB = R1/L1, RT/LT = R2/L2, MENU = Options.")
	hint_label.text = "\n".join(lines)
	_apply_lights()

# ------------------------------------------------------------------
# 1.0.4 action list (pop-up)
# ------------------------------------------------------------------
func _build_picker() -> void:
	picker_layer = Control.new()
	picker_layer.name = "ActionList"
	picker_layer.size = PANEL_SIZE
	picker_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	picker_layer.visible = false
	panel.add_child(picker_layer)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.6)
	shade.size = PANEL_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	picker_layer.add_child(shade)
	picker_box = Panel.new()
	picker_box.name = "Box"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.02, 0.045, 0.99)
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.anti_aliasing = true
	picker_box.add_theme_stylebox_override("panel", style)
	picker_layer.add_child(picker_box)
	picker_title = Label.new()
	picker_title.name = "Title"
	picker_title.position = Vector2(32, 22)
	picker_title.size = Vector2(PICKER_WIDTH - 64, 32)
	picker_title.clip_text = true
	picker_title.add_theme_font_size_override("font_size", 22)
	picker_title.add_theme_color_override("font_color", ACCENT)
	picker_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picker_box.add_child(picker_title)
	picker_subtitle = Label.new()
	picker_subtitle.name = "Subtitle"
	picker_subtitle.position = Vector2(32, 56)
	picker_subtitle.size = Vector2(PICKER_WIDTH - 64, 26)
	picker_subtitle.clip_text = true
	picker_subtitle.add_theme_font_size_override("font_size", 16)
	picker_subtitle.add_theme_color_override("font_color", MUTED)
	picker_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picker_box.add_child(picker_subtitle)
	picker_cancel = Button.new()
	picker_cancel.name = "Cancel"
	picker_cancel.text = "CANCEL"
	picker_cancel.focus_mode = Control.FOCUS_ALL
	picker_cancel.size = Vector2(200, 48)
	picker_cancel.pressed.connect(func() -> void: cancel_picker())
	picker_box.add_child(picker_cancel)

## CHANGE on a button row: show every action. The button's current action is marked.
func open_picker(button: String) -> void:
	if not button in ControllerBindings.BUTTONS:
		return
	testing = false
	lit.clear()
	defaults_armed = false
	notice = ""
	picking_button = button
	pending_action = ""
	_show_list_step()
	if visible:
		refresh()

func _show_list_step() -> void:
	picker_step = "list"
	var name := ControllerBindings.button_name(picking_button, playstation_names)
	picker_title.text = "CHOOSE AN ACTION FOR %s" % name
	picker_subtitle.text = "Pick one. B (Circle), Esc or CANCEL closes the list without a change."
	_clear_picker_items()
	var current := ControllerBindings.action_for(bindings, picking_button)
	var focus_index := 0
	for i in range(ControllerBindings.ACTIONS.size()):
		var action: String = ControllerBindings.ACTIONS[i]
		var note := ""
		var holders := ControllerBindings.conflicts(bindings, picking_button, action)
		if action == current:
			note = "CURRENT"
			focus_index = i
		elif not holders.is_empty():
			note = "ON " + _button_list(holders)
		var item := _picker_item(ControllerBindings.action_name(action), note, Vector2(32, PICKER_ITEM_TOP + i * PICKER_ITEM_STEP), PICKER_ITEM_HEIGHT, action == current)
		item.name = "Action_" + action
		item.pressed.connect(pick.bind(action))
		picker_items.append(item)
		picker_values.append(action)
	var bottom := PICKER_ITEM_TOP + ControllerBindings.ACTIONS.size() * PICKER_ITEM_STEP
	picker_cancel.visible = true
	picker_cancel.position = Vector2((PICKER_WIDTH - picker_cancel.size.x) * 0.5, bottom + 4.0)
	_place_picker_box(bottom + 4.0 + picker_cancel.size.y + 24.0)
	picker_layer.visible = true
	if picker_items[focus_index].is_inside_tree():
		picker_items[focus_index].grab_focus()

## An action was picked from the list.
func pick(action: String) -> void:
	if not is_picking() or not action in ControllerBindings.ACTIONS:
		return
	var button := picking_button
	if ControllerBindings.action_for(bindings, button) == action:
		_finish_picker("%s already does %s. Nothing was changed." % [ControllerBindings.button_name(button, playstation_names), ControllerBindings.action_name(action)])
		return
	if ControllerBindings.conflicts(bindings, button, action).is_empty():
		apply_choice(action, "")
		return
	pending_action = action
	_show_choice_step()

## The picked action is already on another button: ask what to do.
func _show_choice_step() -> void:
	picker_step = "choice"
	var holders := ControllerBindings.conflicts(bindings, picking_button, pending_action)
	var here := ControllerBindings.button_name(picking_button, playstation_names)
	var there := _button_list(holders)
	var previous := ControllerBindings.action_for(bindings, picking_button)
	picker_title.text = "%s IS ALREADY ON %s" % [ControllerBindings.action_name(pending_action), there]
	picker_subtitle.text = "What would you like to do?"
	_clear_picker_items()
	var several := holders.size() > 1
	var choices := [
		["swap", "SWAP THE BUTTONS" if several else "SWAP THE TWO BUTTONS", "%s gets %s." % [there, ControllerBindings.action_name(previous)] if previous != "" else "%s becomes (not set)." % there],
		["both", "USE BOTH BUTTONS", "%s and %s will both do %s." % [here, there, ControllerBindings.action_name(pending_action)]],
		["move", "MOVE IT HERE", "%s becomes (not set)." % there],
		["cancel", "CANCEL", "Nothing changes."],
	]
	for i in range(choices.size()):
		var entry: Array = choices[i]
		var item := _picker_item(entry[1], "", Vector2(32, PICKER_ITEM_TOP + i * CHOICE_ITEM_STEP), CHOICE_ITEM_HEIGHT, false, entry[2])
		item.name = "Choice_" + entry[0]
		if entry[0] == "cancel":
			item.pressed.connect(func() -> void: cancel_picker())
		else:
			item.pressed.connect(apply_choice.bind(pending_action, entry[0]))
		picker_items.append(item)
		picker_values.append(entry[0])
	picker_cancel.visible = false
	_place_picker_box(PICKER_ITEM_TOP + choices.size() * CHOICE_ITEM_STEP + 12.0)
	if picker_items[0].is_inside_tree():
		picker_items[0].grab_focus()

## Give the button being changed the Action (Choice: "swap", "both", "move" or "").
func apply_choice(action: String, choice: String) -> void:
	if not is_picking():
		return
	var button := picking_button
	var before := bindings.duplicate()
	var holders := ControllerBindings.conflicts(bindings, button, action)
	var changed := ControllerBindings.choose(bindings, button, action, choice)
	if changed == ControllerBindings.clean(before):
		_finish_picker("Nothing was changed.")
		return
	bindings = changed
	var parts := PackedStringArray()
	parts.append("%s is now %s." % [ControllerBindings.button_name(button, playstation_names), ControllerBindings.action_name(action)])
	if not holders.is_empty():
		var there := _button_list(holders)
		match choice:
			"swap":
				parts.append("%s is now %s." % [there, ControllerBindings.action_name(ControllerBindings.action_for(bindings, holders[0]))])
			"both":
				parts.append("%s does it too." % there)
			"move":
				parts.append("%s is now (not set)." % there)
	var previous := ControllerBindings.action_for(before, button)
	if previous != "" and ControllerBindings.buttons_for(bindings, previous).is_empty():
		parts.append("%s has no button now (the mouse and highlight still work)." % ControllerBindings.action_name(previous))
	_finish_picker(" ".join(parts))
	bindings_changed.emit(bindings.duplicate())

## B (Circle) / Esc in the list: from the choice step back to the list, else close.
func picker_back() -> void:
	if not is_picking():
		return
	if picker_step == "choice":
		pending_action = ""
		_show_list_step()
	else:
		cancel_picker()

## CANCEL, MENU or closing the panel: no change.
func cancel_picker() -> void:
	if not is_picking():
		return
	_finish_picker("Nothing was changed.")

func _finish_picker(message: String) -> void:
	var button := picking_button
	_hide_picker()
	notice = message
	if visible:
		refresh()
		var index := row_index(button)
		if index != -1 and rows[index].button.is_inside_tree():
			rows[index].button.grab_focus()

func _hide_picker() -> void:
	picking_button = ""
	pending_action = ""
	picker_step = "list"
	if is_instance_valid(picker_layer):
		picker_layer.visible = false
	_clear_picker_items()

func _clear_picker_items() -> void:
	for item in picker_items:
		if is_instance_valid(item):
			item.visible = false
			item.focus_mode = Control.FOCUS_NONE
			item.queue_free()
	picker_items.clear()
	picker_values.clear()

func _place_picker_box(height: float) -> void:
	picker_box.size = Vector2(PICKER_WIDTH, height)
	picker_box.position = ((PANEL_SIZE - picker_box.size) * 0.5).round()

## "RT", "RT AND LB" or "A, B AND X".
func _button_list(buttons: Array[String]) -> String:
	var names := PackedStringArray()
	for button in buttons:
		names.append(ControllerBindings.button_name(button, playstation_names))
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " AND " + names[names.size() - 1]

## One list item: the main text on the left, an optional note on the right and an
## optional second line underneath.
func _picker_item(text: String, note: String, at: Vector2, height: float, current: bool, detail := "") -> Button:
	var item := Button.new()
	item.text = ""
	item.position = at
	item.size = Vector2(PICKER_WIDTH - 64, height)
	item.focus_mode = Control.FOCUS_ALL
	item.clip_contents = true
	var main := Label.new()
	main.name = "Text"
	main.text = text
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.position = Vector2(18, 8 if detail != "" else (height - 28) * 0.5)
	main.size = Vector2(item.size.x - 150, 28)
	main.clip_text = true
	main.add_theme_font_size_override("font_size", _fit(text, 19, item.size.x - 154))
	main.add_theme_color_override("font_color", AMBER if current else TEXT)
	item.add_child(main)
	if detail != "":
		var second := Label.new()
		second.name = "Detail"
		second.text = detail
		second.mouse_filter = Control.MOUSE_FILTER_IGNORE
		second.position = Vector2(18, 38)
		second.size = Vector2(item.size.x - 36, 24)
		second.clip_text = true
		second.add_theme_font_size_override("font_size", _fit(detail, 16, item.size.x - 40))
		second.add_theme_color_override("font_color", MUTED)
		item.add_child(second)
	if note != "":
		var side := Label.new()
		side.name = "Note"
		side.text = note
		side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		side.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		side.position = Vector2(item.size.x - 150, (height - 26) * 0.5)
		side.size = Vector2(132, 26)
		side.clip_text = true
		side.add_theme_font_size_override("font_size", _fit(note, 15, 130))
		side.add_theme_color_override("font_color", AMBER if current else MUTED)
		item.add_child(side)
	picker_box.add_child(item)
	return item

## Text on a list item (for tests and the controller check).
static func item_text(item: Button) -> String:
	var main := item.get_node_or_null("Text") as Label
	return main.text if main else item.text

func _on_defaults_pressed() -> void:
	if defaults_armed:
		defaults_armed = false
		bindings = ControllerBindings.defaults()
		notice = "Controller buttons are back to their defaults."
		refresh()
		bindings_changed.emit(bindings.duplicate())
		return
	defaults_armed = true
	defaults_serial += 1
	var serial := defaults_serial
	notice = "Press CONFIRM to put every controller button back to its default. Other settings are not affected."
	refresh()
	if is_inside_tree():
		get_tree().create_timer(CONFIRM_SECONDS).timeout.connect(func() -> void:
			if serial == defaults_serial and defaults_armed:
				defaults_armed = false
				notice = ""
				refresh())

func _process(delta: float) -> void:
	if not visible:
		set_process(false)
		return
	status_poll -= delta
	if status_poll <= 0.0:
		status_poll = STATUS_POLL_SECONDS
		var before := status_text()
		update_status()
		if status_text() != before:
			refresh()
	var faded := false
	for key in lit.keys():
		var entry: Dictionary = lit[key]
		entry.left -= delta
		if not entry.down and entry.left <= 0.0:
			lit.erase(key)
			faded = true
	if faded:
		_apply_lights()
	if testing:
		test_idle += delta
		if test_idle >= TEST_IDLE_SECONDS:
			stop_test()

## Keyboard Esc / controller B while open: the action list first, then the test,
## then close.
func back() -> void:
	if is_picking():
		picker_back()
	elif testing:
		stop_test()
	else:
		close_requested.emit()

func focus_targets() -> Array[Control]:
	var found: Array[Control] = []
	if is_picking():
		for item in picker_items:
			if is_instance_valid(item):
				found.append(item)
		if picker_cancel.visible:
			found.append(picker_cancel)
		return found
	for row in rows:
		if row.button.focus_mode != Control.FOCUS_NONE:
			found.append(row.button)
	found.append(defaults_button)
	found.append(test_button)
	found.append(close_button)
	return found

func _draw_controller() -> void:
	var size_px := OUTLINE.get_size() * DRAWING_SCALE
	drawing.draw_texture_rect(OUTLINE, Rect2(DRAWING_AT, size_px), false, line_tint)
	var font := ThemeDB.fallback_font
	var names := ControllerBindings.PLAYSTATION_NAMES if playstation_names else ControllerBindings.BUTTON_NAMES
	for key in TAGS:
		var title := ""
		var detail := ""
		var detail_color := TEXT
		match key:
			"dpad":
				title = "D-PAD / STICK"
				detail = "MOVE HIGHLIGHT"
			"menu":
				title = names.menu
				detail = "SETTINGS"
			_:
				title = names[key]
				var action := ControllerBindings.action_for(bindings, key)
				detail = ControllerBindings.action_name(action, true)
				if action == "jump":
					detail += " (hold 1 s)"
				if action == "":
					detail_color = MUTED
		var anchor: Vector2 = TAGS[key]
		var title_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var detail_w := font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var left_side: bool = anchor.x <= 200.0
		var centred: bool = key in ["menu", "x"]
		var tx := anchor.x
		var dx := anchor.x
		if centred:
			tx = anchor.x - title_w * 0.5
			dx = anchor.x - detail_w * 0.5
		elif left_side:
			tx = anchor.x - title_w
			dx = anchor.x - detail_w
		var on := lit.has(key)
		var target: Vector2 = DRAWING_AT + POINTS["stick" if key == "dpad" else key] * DRAWING_SCALE
		if on:
			var tag_w := maxf(title_w, detail_w)
			var tag_x := minf(tx, dx)
			drawing.draw_rect(Rect2(tag_x - 6, anchor.y - 2, tag_w + 12, 46), LIGHT_BG)
			drawing.draw_circle(target, 13.0, Color(AMBER, 0.35))
			drawing.draw_circle(target, 7.0, AMBER)
			if key == "dpad":
				drawing.draw_circle(DRAWING_AT + POINTS.dpad * DRAWING_SCALE, 13.0, Color(AMBER, 0.35))
				drawing.draw_circle(DRAWING_AT + POINTS.dpad * DRAWING_SCALE, 7.0, AMBER)
		drawing.draw_string(font, Vector2(tx, anchor.y + 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, AMBER if on else ACCENT)
		drawing.draw_string(font, Vector2(dx, anchor.y + 37), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, AMBER if on else detail_color)
		var start := Vector2(anchor.x + 6.0, anchor.y + 12.0) if left_side else Vector2(anchor.x - 6.0, anchor.y + 12.0)
		if key == "menu":
			start = Vector2(anchor.x, anchor.y + 44.0)
		elif key == "x":
			start = Vector2(anchor.x, anchor.y - 4.0)
		drawing.draw_line(start, target, AMBER if on else Color(line_tint, 0.95), 2.5 if on else 1.5, true)
		drawing.draw_circle(target, 2.5, ACCENT)
		if key == "dpad":
			var pad: Vector2 = DRAWING_AT + POINTS.dpad * DRAWING_SCALE
			drawing.draw_line(start, pad, Color(line_tint, 0.95), 1.5, true)
			drawing.draw_circle(pad, 2.5, ACCENT)

## Largest font size (down to 12) that fits Text in Room pixels.
func _fit(text: String, font_size: int, room: float) -> int:
	var font := ThemeDB.fallback_font
	var fs := font_size
	while fs > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	return fs

func _label(text: String, at: Vector2, box: Vector2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = box
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return label

func _row_label(text: String, at: Vector2, box: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = box
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_layer.add_child(label)
	return label

func _row_button(text: String, at: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = Vector2(112, 44)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 15)
	if action.is_valid():
		button.pressed.connect(action)
	row_layer.add_child(button)
	return button

## 1.0.3: small round "!" (same look as the one in Settings). Copies the controller
## check for support; mouse or touch only, so the controller highlight skips it.
func _check_icon() -> Button:
	var button := Button.new()
	button.name = "CopyCheck"
	# The "!" is a child label: as button text the font's line height would make
	# the button taller than wide and the ring would not be round.
	button.text = ""
	button.clip_contents = false
	button.tooltip_text = "Copy controller check (for support)"
	button.focus_mode = Control.FOCUS_NONE
	button.size = Vector2(CHECK_ICON_SIZE, CHECK_ICON_SIZE)
	button.custom_minimum_size = button.size
	for state in ["normal", "hover", "pressed", "focus"]:
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(0, 0, 0, 0) if state != "pressed" else Color(ACCENT, 0.15)
		ring.border_color = Color(MUTED, 0.6) if state == "normal" else (Color(TEXT, 0.9) if state == "hover" else ACCENT)
		if state == "focus":
			ring.draw_center = false
			ring.border_color = Color(0, 0, 0, 0)
		ring.set_border_width_all(1)
		ring.set_corner_radius_all(int(CHECK_ICON_SIZE / 2.0))
		ring.anti_aliasing = true
		ring.content_margin_left = 0
		ring.content_margin_right = 0
		ring.content_margin_top = 0
		ring.content_margin_bottom = 0
		button.add_theme_stylebox_override(state, ring)
	var mark := Label.new()
	mark.name = "Mark"
	mark.text = "!"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 14)
	mark.add_theme_color_override("font_color", Color(MUTED, 0.75))
	mark.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mark.grow_vertical = Control.GROW_DIRECTION_BOTH
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(mark)
	button.mouse_entered.connect(func() -> void: mark.add_theme_color_override("font_color", Color(TEXT, 0.9)))
	button.mouse_exited.connect(func() -> void: mark.add_theme_color_override("font_color", Color(MUTED, 0.75)))
	panel.add_child(button)
	button.size = Vector2(CHECK_ICON_SIZE, CHECK_ICON_SIZE)
	return button

func _button(text: String, at: Vector2, box: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = box
	button.focus_mode = Control.FOCUS_ALL
	panel.add_child(button)
	return button

func _divider(y: float) -> void:
	var line := ColorRect.new()
	line.color = EDGE
	line.position = Vector2(44, y)
	line.size = Vector2(PANEL_SIZE.x - 88, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
