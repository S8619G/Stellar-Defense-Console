extends Control
## 1.0.0 Controller panel, opened from Settings > CONTROLLER. Layout follows the
## approved reference (design/controller-1.3.1/mock_controller_layout_131.png): the
## controller drawing with two-line tags and pointer lines on the left, and the
## ACTION / BUTTON table with CHANGE or SET on the right, then DEFAULTS and CLOSE.
## Built in code, in the same style as the Settings panel. The battle stays paused.

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
## CHANGE waits this long for the new button before giving up.
const CAPTURE_SECONDS := 6.0
const CONFIRM_SECONDS := 3.0

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
## CHANGE in progress: the action waiting for a button ("" = none).
var capture_action: String = ""
var capture_remaining: float = 0.0
var defaults_armed: bool = false
var defaults_serial: int = 0
var notice: String = ""

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
	header_label = _label("", Vector2(PANEL_SIZE.x - 744, 34), Vector2(700, 30), 18, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_divider(84)
	drawing = Control.new()
	drawing.name = "Drawing"
	drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawing.size = PANEL_SIZE
	drawing.draw.connect(_draw_controller)
	panel.add_child(drawing)
	_label("ACTION", Vector2(770, 100), Vector2(220, 24), 15, MUTED)
	_label("BUTTON", Vector2(1002, 100), Vector2(130, 24), 15, MUTED)
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
	close_button = _button("CLOSE", Vector2(PANEL_SIZE.x - 244, 790), Vector2(200, 56))
	close_button.name = "Close"
	close_button.pressed.connect(func() -> void: close_requested.emit())
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
	capture_action = ""
	defaults_armed = false
	notice = ""
	visible = true
	_center_panel()
	refresh()
	if not rows.is_empty():
		rows[0].button.grab_focus()

func close() -> void:
	cancel_capture()
	visible = false
	set_process(false)

func is_capturing() -> bool:
	return capture_action != ""

## Rows: six actions, spare/extra buttons (SET), then the two fixed rows.
func row_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var primary := {}
	for action in ControllerBindings.ACTIONS:
		var found := ControllerBindings.buttons_for(bindings, action)
		if not found.is_empty():
			primary[found[0]] = true
		specs.append({"kind": "action", "action": action})
	for button in ControllerBindings.BUTTONS:
		if not primary.has(button):
			specs.append({"kind": "extra", "button": button})
	specs.append({"kind": "fixed", "name": "SETTINGS / PAUSE", "keys": "OPTIONS" if playstation_names else "MENU"})
	specs.append({"kind": "fixed", "name": "MOVE HIGHLIGHT", "keys": "D-PAD / STICK"})
	return specs

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
		var names := ControllerBindings.PLAYSTATION_NAMES if playstation_names else ControllerBindings.BUTTON_NAMES
		match spec.kind:
			"action":
				row.key = "action:" + spec.action
				row.name_label = _row_label(ControllerBindings.ACTION_NAMES[spec.action], Vector2(770, y + 8), Vector2(226, 30), _fit(ControllerBindings.ACTION_NAMES[spec.action], 18, 222.0), TEXT)
				var keys := ControllerBindings.label_for(bindings, spec.action, playstation_names)
				if capture_action == spec.action:
					keys = "PRESS A BUTTON"
				row.keys_label = _row_label(keys, Vector2(1002, y + 8), Vector2(138, 30), _fit(keys, 17, 136.0), AMBER if capture_action == spec.action else ACCENT)
				row.button = _row_button("CHANGE", Vector2(1144, y), _on_change.bind(spec.action))
			"extra":
				row.key = "button:" + spec.button
				var action := ControllerBindings.action_for(bindings, spec.button)
				row.name_label = _row_label(ControllerBindings.ACTION_NAMES.get(action, "(not set)"), Vector2(770, y + 8), Vector2(226, 30), 18, TEXT if action != "" else MUTED)
				row.keys_label = _row_label(names[spec.button], Vector2(1002, y + 8), Vector2(138, 30), _fit(names[spec.button], 17, 136.0), ACCENT)
				row.button = _row_button("SET", Vector2(1144, y), _on_set.bind(spec.button))
			_:
				row.key = "fixed:" + spec.name
				row.name_label = _row_label(spec.name, Vector2(770, y + 8), Vector2(226, 30), 18, TEXT)
				row.keys_label = _row_label(spec.keys, Vector2(1002, y + 8), Vector2(138, 30), _fit(spec.keys, 17, 136.0), ACCENT)
				row.button = _row_button("FIXED", Vector2(1144, y), Callable())
				row.button.disabled = true
				row.button.focus_mode = Control.FOCUS_NONE
		row.button.name = "Row%d" % index
		rows.append(row)
		index += 1
	for row in rows:
		if row.key == focused_key and row.button.focus_mode != Control.FOCUS_NONE:
			row.button.grab_focus()
	header_label.text = "BATTLE PAUSED  |  %s" % device_text
	defaults_button.text = "CONFIRM" if defaults_armed else "DEFAULTS"
	var lines := PackedStringArray()
	if capture_action != "":
		lines.append("Press the new button for %s now (%ds). MENU or Esc cancels." % [ControllerBindings.ACTION_NAMES[capture_action], ceili(capture_remaining)])
	elif not notice.is_empty():
		lines.append(notice)
	else:
		lines.append("Press CHANGE, then the new button. SET gives a spare button an action. A (Cross) presses the highlighted button in menus; B (Circle) goes back.")
	lines.append("In battle, the D-pad or left stick shows a highlight; A then presses it (use it for the special weapon and EMP).")
	lines.append("PlayStation names: A = Cross, B = Circle, X = Square, Y = Triangle, RB/LB = R1/L1, RT/LT = R2/L2, MENU = Options.")
	hint_label.text = "\n".join(lines)
	if is_instance_valid(drawing):
		drawing.queue_redraw()

func _on_change(action: String) -> void:
	notice = ""
	capture_action = action
	capture_remaining = CAPTURE_SECONDS
	set_process(true)
	refresh()

func cancel_capture() -> void:
	if capture_action == "":
		return
	capture_action = ""
	set_process(false)
	notice = "CHANGE cancelled. No button was changed."
	if visible:
		refresh()

## A button pressed while CHANGE waits (from ControllerInput.gd). Returns true when used.
func capture(button: String) -> bool:
	if capture_action == "":
		return false
	if not button in ControllerBindings.BUTTONS:
		notice = "That button cannot be assigned. Use A, B, X, Y, LB, RB, LT or RT."
		refresh()
		return true
	var action := capture_action
	capture_action = ""
	set_process(false)
	var before := ControllerBindings.action_for(bindings, button)
	bindings = ControllerBindings.assign(bindings, action, button)
	var names := ControllerBindings.PLAYSTATION_NAMES if playstation_names else ControllerBindings.BUTTON_NAMES
	notice = "%s is now %s." % [ControllerBindings.ACTION_NAMES[action], names[button]]
	if before != "" and before != action:
		notice += " %s moved to %s." % [ControllerBindings.ACTION_NAMES[before], ControllerBindings.label_for(bindings, before, playstation_names)]
	refresh()
	bindings_changed.emit(bindings.duplicate())
	return true

## SET: each press gives the spare button the next action, then back to (not set).
func _on_set(button: String) -> void:
	var order: Array = [""] + ControllerBindings.ACTIONS
	var current := ControllerBindings.action_for(bindings, button)
	var at := order.find(current)
	for step in range(1, order.size() + 1):
		var next: String = order[(at + step) % order.size()]
		var changed := ControllerBindings.set_extra(bindings, button, next)
		if changed[button] == next:
			bindings = changed
			break
	notice = ""
	refresh()
	bindings_changed.emit(bindings.duplicate())

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
	if capture_action == "":
		set_process(false)
		return
	var shown := ceili(capture_remaining)
	capture_remaining -= delta
	if capture_remaining <= 0.0:
		cancel_capture()
	elif ceili(capture_remaining) != shown:
		refresh()

## Keyboard Esc / controller B or MENU while open: cancel CHANGE first, then close.
func back() -> void:
	if capture_action != "":
		cancel_capture()
	else:
		close_requested.emit()

func focus_targets() -> Array[Control]:
	var found: Array[Control] = []
	for row in rows:
		if row.button.focus_mode != Control.FOCUS_NONE:
			found.append(row.button)
	found.append(defaults_button)
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
				detail = ControllerBindings.ACTION_NAMES.get(action, "(not set)")
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
		drawing.draw_string(font, Vector2(tx, anchor.y + 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ACCENT)
		drawing.draw_string(font, Vector2(dx, anchor.y + 37), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, detail_color)
		var target: Vector2 = DRAWING_AT + POINTS["stick" if key == "dpad" else key] * DRAWING_SCALE
		var start := Vector2(anchor.x + 6.0, anchor.y + 12.0) if left_side else Vector2(anchor.x - 6.0, anchor.y + 12.0)
		if key == "menu":
			start = Vector2(anchor.x, anchor.y + 44.0)
		elif key == "x":
			start = Vector2(anchor.x, anchor.y - 4.0)
		drawing.draw_line(start, target, Color(line_tint, 0.95), 1.5, true)
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
