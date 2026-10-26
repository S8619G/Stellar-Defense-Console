extends Control
## Gear-icon Settings panel: Effects and RADAR volume with mute switches,
## difficulty, auto options, Remember Settings, Defaults and QUIT. The version text at the
## bottom is a link to the project's GitHub page (1.08); the small round "!" beside it
## opens the app data folder with the session logs (1.08). Built in code so it
## needs no extra scene file. The console pauses the battle while it is open.

signal changed(settings: Dictionary)
signal close_requested
signal new_battle_requested
signal effects_preview
signal quit_requested
signal open_logs_requested
signal open_github_requested
## 1.0.0: CONTROLLER opens the controller button panel.
signal controller_requested

const GameSettings = preload("res://scripts/GameSettings.gd")
const EDGE := Color("#77324f")
const TEXT := Color("#ede0e8")
const MUTED := Color("#b9a8b2")
const ACCENT := Color(1.0, 0.6, 0.78)
const AMBER := Color("#ffe28b")
## 1.0.8: one row taller for SCREEN EFFECTS (922 to 988 px).
## 1.1.0: one row taller again for FRAME RATE (988 to 1054 px).
const PANEL_SIZE := Vector2(860, 1054)
## QUIT asks once more; the confirmation lapses after this many seconds.
const QUIT_CONFIRM_SECONDS := 3.0

var settings: Dictionary = GameSettings.DEFAULTS.duplicate()
var active_difficulty: int = 1
var contacts: Node
var panel: Panel
var effects_slider: HSlider
var radar_slider: HSlider
var effects_value: Label
var radar_value: Label
var effects_mute: Button
var radar_mute: Button
var difficulty_buttons: Array[Button] = []
var auto_battery_button: Button
var auto_firewall_button: Button
var auto_interceptors_button: Button
var auto_gunships_button: Button
var auto_jump_button: Button
## 1.0.8: SCREEN EFFECTS ON/OFF (screen scramble when the ship is hit or destroyed).
var screen_effects_button: Button
var auto_repair_button: Button
## 1.1.0: FRAME RATE, one button that switches between STANDARD (at most 60 frames a
## second, the default) and SMOOTH (the screen's refresh rate). Stephen 2026-10-25.
var frame_rate_button: Button
var remember_button: Button
var reset_button: Button
var reset_armed: bool = false
var reset_armed_serial: int = 0
## Defaults used by RESET TO DEFAULTS (the console passes in its starting volumes).
var defaults: Dictionary = GameSettings.DEFAULTS.duplicate()
var quit_button: Button
## Hover help text on buttons (the console's Show Hover Tooltips switch; off from 1.06).
var show_tooltips: bool = false
## Small dim build text centered at the bottom, for example "RADAR BATTLE CONSOLE 1.06"
## (set by the console from the project version). Clicking it opens the GitHub page (1.08).
var version_text: String = "":
	set(value):
		version_text = value
		if version_label:
			version_label.text = value
var version_label: LinkButton
## 1.08: small round "!" just right of the version text; opens the app data folder.
var log_icon_button: Button
var quit_armed: bool = false
var quit_armed_serial: int = 0
var multiplier_label: Label
var multiplier_detail: Label
var note_label: Label
var new_battle_button: Button
var close_button: Button
var controller_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	panel = Panel.new()
	panel.name = "Panel"
	panel.size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.015, 0.03, 0.97)
	style.border_color = Color(0.55, 0.23, 0.38)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_label("SETTINGS", Vector2(44, 26), Vector2(400, 40), 30, ACCENT)
	_label("BATTLE PAUSED", Vector2(PANEL_SIZE.x - 544, 34), Vector2(300, 30), 18, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	# 1.0.0: controller buttons and the controller drawing are on their own panel.
	controller_button = _button("CONTROLLER", Vector2(PANEL_SIZE.x - 224, 22), Vector2(180, 48), false)
	controller_button.name = "ControllerButton"
	_tip(controller_button, "Controller buttons: see and change what each button does")
	_divider(84)
	# Rows are 66 pixels apart: name on the left, short note under it, controls on the right.
	_row_text(100, "EFFECTS VOLUME", "Alerts, weapons and battle sounds", 270)
	effects_slider = _slider(Vector2(320, 108))
	effects_value = _label("", Vector2(586, 110), Vector2(70, 30), 20, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	effects_mute = _button("MUTE", Vector2(680, 100), Vector2(136, 56), true)
	_row_text(166, "RADAR VOLUME", "Background radar sweep", 270)
	radar_slider = _slider(Vector2(320, 174))
	radar_value = _label("", Vector2(586, 176), Vector2(70, 30), 20, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	radar_mute = _button("MUTE", Vector2(680, 166), Vector2(136, 56), true)
	_divider(236)
	_row_text(252, "DIFFICULTY", "Enemy toughness, attacks and speed", 270)
	var group := ButtonGroup.new()
	for index in range(3):
		var b := _button(GameSettings.DIFFICULTY_NAMES[index], Vector2(320 + index * 168, 252), Vector2(160, 56), true)
		b.button_group = group
		b.pressed.connect(_on_difficulty.bind(index))
		difficulty_buttons.append(b)
	_row_text(318, "AUTO DEFENSE SHIELD", "Fires by itself as missiles near the flak arc", 560)
	auto_battery_button = _button("OFF", Vector2(656, 318), Vector2(160, 56), true)
	_row_text(384, "AUTO FIREWALL", "Raised by itself when a Breacher starts hacking", 560)
	auto_firewall_button = _button("OFF", Vector2(656, 384), Vector2(160, 56), true)
	_row_text(450, "AUTO LAUNCH", "Fighters / nukes and carriers", 420)
	auto_interceptors_button = _button("INTERCEPTORS OFF", Vector2(488, 450), Vector2(160, 56), true)
	auto_gunships_button = _button("GUNSHIPS OFF", Vector2(656, 450), Vector2(160, 56), true)
	auto_interceptors_button.add_theme_font_size_override("font_size", 16)
	auto_gunships_button.add_theme_font_size_override("font_size", 16)
	_tip(auto_interceptors_button, "Automatically launch Interceptors against enemy fighters")
	_tip(auto_gunships_button, "Automatically launch Gunships against nukes and Enemy Carriers")
	_row_text(516, "AUTO RAPID REPAIR", "Uses a repair charge by itself when the hull is at 50% or less", 580)
	auto_repair_button = _button("OFF", Vector2(656, 516), Vector2(160, 56), true)
	_row_text(582, "AUTO JUMP", "Jumps by itself when the hull drops below 10% (usual JUMP cost)", 580)
	auto_jump_button = _button("OFF", Vector2(656, 582), Vector2(160, 56), true)
	_row_text(648, "SCREEN EFFECTS", "Screen scramble when a nuke hits or the ship is destroyed", 580)
	screen_effects_button = _button("ON", Vector2(656, 648), Vector2(160, 56), true)
	screen_effects_button.name = "ScreenEffectsButton"
	_tip(screen_effects_button, "OFF: no screen scramble or flicker. The red SYSTEMS OFFLINE screen still shows.")
	_row_text(714, "FRAME RATE", "SMOOTH matches the screen, but uses more power", 580)
	frame_rate_button = _button("STANDARD", Vector2(656, 714), Vector2(160, 56), true)
	frame_rate_button.name = "FrameRateButton"
	_tip(frame_rate_button, "STANDARD: at most 60 frames a second, for quieter fans and longer battery life. SMOOTH: matches the screen's refresh rate, for example 144 on a 144 Hz screen.")
	_row_text(780, "REMEMBER SETTINGS", "OFF: next start uses NORMAL, autos off", 350)
	reset_button = _button("DEFAULTS", Vector2(488, 780), Vector2(160, 56), false)
	_tip(reset_button, "Put every setting back to its default (press twice to confirm). High scores are not affected.")
	remember_button = _button("ON", Vector2(656, 780), Vector2(160, 56), true)
	_divider(850)
	multiplier_label = _label("", Vector2(44, 864), Vector2(500, 34), 24, ACCENT)
	multiplier_detail = _label("", Vector2(44, 898), Vector2(780, 24), 16, MUTED)
	note_label = _label("", Vector2(44, 926), Vector2(780, 24), 16, AMBER)
	quit_button = _button("QUIT", Vector2(44, 960), Vector2(200, 56), false)
	_tip(quit_button, "Close Stellar Defense Console (press twice to confirm)")
	new_battle_button = _button("NEW BATTLE", Vector2(400, 960), Vector2(220, 56), false)
	close_button = _button("CLOSE", Vector2(656, 960), Vector2(160, 56), false)
	# Version text, centered at the bottom; a quiet link to the GitHub page (1.08).
	var version_row := HBoxContainer.new()
	version_row.name = "VersionRow"
	version_row.alignment = BoxContainer.ALIGNMENT_CENTER
	version_row.position = Vector2(44, 1024)
	version_row.size = Vector2(PANEL_SIZE.x - 88, 22)
	version_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(version_row)
	version_label = LinkButton.new()
	version_label.name = "VersionLabel"
	version_label.text = version_text
	version_label.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	version_label.focus_mode = Control.FOCUS_NONE
	version_label.add_theme_font_size_override("font_size", 15)
	version_label.add_theme_color_override("font_color", Color(MUTED, 0.6))
	version_label.add_theme_color_override("font_hover_color", Color(TEXT, 0.9))
	version_label.add_theme_color_override("font_pressed_color", ACCENT)
	version_label.disabled = true
	version_label.add_theme_color_override("font_disabled_color", Color(MUTED, 0.6))
	_tip(version_label, "Private pre-release build. No public release page.")
	version_row.add_child(version_label)
	log_icon_button = _log_icon()
	_tip(log_icon_button, "Open the app data folder (session logs)")
	version_row.add_child(log_icon_button)
	effects_slider.value_changed.connect(_on_volume.bind("effects_volume"))
	radar_slider.value_changed.connect(_on_volume.bind("radar_volume"))
	effects_slider.drag_ended.connect(func(_changed: bool) -> void: effects_preview.emit())
	effects_mute.toggled.connect(_on_toggle.bind("effects_muted"))
	radar_mute.toggled.connect(_on_toggle.bind("radar_muted"))
	auto_battery_button.toggled.connect(_on_toggle.bind("auto_battery"))
	auto_firewall_button.toggled.connect(_on_toggle.bind("auto_firewall"))
	auto_interceptors_button.toggled.connect(_on_toggle.bind("auto_interceptors"))
	auto_gunships_button.toggled.connect(_on_toggle.bind("auto_gunships"))
	auto_jump_button.toggled.connect(_on_toggle.bind("auto_jump"))
	auto_repair_button.toggled.connect(_on_toggle.bind("auto_repair"))
	remember_button.toggled.connect(_on_toggle.bind("remember_settings"))
	screen_effects_button.toggled.connect(_on_toggle.bind("screen_effects"))
	frame_rate_button.toggled.connect(_on_toggle.bind("smooth_frame_rate"))
	reset_button.pressed.connect(_on_reset_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	version_label.pressed.connect(func() -> void: open_github_requested.emit())
	log_icon_button.pressed.connect(func() -> void: open_logs_requested.emit())
	new_battle_button.pressed.connect(func() -> void: new_battle_requested.emit())
	close_button.pressed.connect(func() -> void: close_requested.emit())
	controller_button.pressed.connect(func() -> void: controller_requested.emit())
	resized.connect(_center_panel)
	_center_panel()

func _center_panel() -> void:
	if panel:
		panel.position = ((size - PANEL_SIZE) * 0.5).round()

func open(current: Dictionary, battle_difficulty: int) -> void:
	settings = GameSettings.clean(current)
	active_difficulty = battle_difficulty
	visible = true
	quit_armed = false
	reset_armed = false
	_center_panel()
	refresh()
	close_button.grab_focus()

func refresh() -> void:
	effects_slider.set_value_no_signal(settings.effects_volume)
	radar_slider.set_value_no_signal(settings.radar_volume)
	effects_value.text = "%d%%" % settings.effects_volume
	radar_value.text = "%d%%" % settings.radar_volume
	effects_mute.set_pressed_no_signal(settings.effects_muted)
	radar_mute.set_pressed_no_signal(settings.radar_muted)
	effects_mute.text = "MUTED" if settings.effects_muted else "MUTE"
	radar_mute.text = "MUTED" if settings.radar_muted else "MUTE"
	for index in range(3):
		difficulty_buttons[index].set_pressed_no_signal(index == settings.difficulty)
	auto_battery_button.set_pressed_no_signal(settings.auto_battery)
	auto_firewall_button.set_pressed_no_signal(settings.auto_firewall)
	auto_battery_button.text = "ON" if settings.auto_battery else "OFF"
	auto_firewall_button.text = "ON" if settings.auto_firewall else "OFF"
	auto_interceptors_button.set_pressed_no_signal(settings.auto_interceptors)
	auto_gunships_button.set_pressed_no_signal(settings.auto_gunships)
	auto_jump_button.set_pressed_no_signal(settings.auto_jump)
	auto_interceptors_button.text = "INTERCEPTORS ON" if settings.auto_interceptors else "INTERCEPTORS OFF"
	auto_gunships_button.text = "GUNSHIPS ON" if settings.auto_gunships else "GUNSHIPS OFF"
	auto_jump_button.text = "ON" if settings.auto_jump else "OFF"
	auto_repair_button.set_pressed_no_signal(settings.auto_repair)
	auto_repair_button.text = "ON" if settings.auto_repair else "OFF"
	remember_button.set_pressed_no_signal(settings.remember_settings)
	remember_button.text = "ON" if settings.remember_settings else "OFF"
	screen_effects_button.set_pressed_no_signal(settings.screen_effects)
	screen_effects_button.text = "ON" if settings.screen_effects else "OFF"
	frame_rate_button.set_pressed_no_signal(settings.smooth_frame_rate)
	frame_rate_button.text = "SMOOTH" if settings.smooth_frame_rate else "STANDARD"
	reset_button.text = "CONFIRM" if reset_armed else "DEFAULTS"
	quit_button.text = "CONFIRM QUIT" if quit_armed else "QUIT"
	var autos := int(settings.auto_battery) + int(settings.auto_firewall) + int(settings.auto_interceptors) + int(settings.auto_gunships) + int(settings.auto_jump) + int(settings.auto_repair)
	var multiplier := 1.0
	var level_factor := 1.0
	var penalty := 0.10
	if contacts:
		multiplier = contacts.score_multiplier_for(settings.difficulty, autos)
		level_factor = contacts.score_multiplier_for(settings.difficulty, 0)
		penalty = contacts.auto_score_penalty
	multiplier_label.text = "SCORE MULTIPLIER  x%.2f" % multiplier
	var detail := "%s x%.2f" % [GameSettings.DIFFICULTY_NAMES[settings.difficulty], level_factor]
	if autos > 0:
		detail += "   |   %d AUTO OPTION%s  -%d%%" % [autos, "" if autos == 1 else "S", roundi(penalty * 100.0 * autos)]
	multiplier_detail.text = detail
	var pending: bool = settings.difficulty != active_difficulty
	note_label.visible = pending
	note_label.text = "%s STARTS WITH THE NEXT BATTLE" % GameSettings.DIFFICULTY_NAMES[settings.difficulty]
	new_battle_button.visible = pending

## First press asks for confirmation; a second press within 3 seconds quits.
func _on_quit_pressed() -> void:
	if quit_armed:
		quit_armed = false
		refresh()
		quit_requested.emit()
		return
	quit_armed = true
	quit_armed_serial += 1
	var serial := quit_armed_serial
	refresh()
	if is_inside_tree():
		get_tree().create_timer(QUIT_CONFIRM_SECONDS).timeout.connect(func() -> void:
			if serial == quit_armed_serial and quit_armed:
				quit_armed = false
				refresh())

## First press asks for confirmation; a second press within 3 seconds resets.
func _on_reset_pressed() -> void:
	if reset_armed:
		reset_armed = false
		settings = GameSettings.reset_all(settings, defaults)
		refresh()
		changed.emit(settings.duplicate())
		return
	reset_armed = true
	reset_armed_serial += 1
	var serial := reset_armed_serial
	refresh()
	if is_inside_tree():
		get_tree().create_timer(QUIT_CONFIRM_SECONDS).timeout.connect(func() -> void:
			if serial == reset_armed_serial and reset_armed:
				reset_armed = false
				refresh())

func _on_volume(value: float, key: String) -> void:
	settings[key] = int(value)
	refresh()
	changed.emit(settings.duplicate())

func _on_toggle(pressed: bool, key: String) -> void:
	settings[key] = pressed
	refresh()
	changed.emit(settings.duplicate())

func _on_difficulty(index: int) -> void:
	settings.difficulty = index
	refresh()
	changed.emit(settings.duplicate())

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

func _row_text(y: float, title: String, note: String, note_width: float) -> void:
	_label(title, Vector2(44, y + 4), Vector2(400, 30), 20, TEXT)
	_label(note, Vector2(44, y + 32), Vector2(note_width, 24), 15, MUTED)

func _tip(control: Control, text: String) -> void:
	control.set_meta("hover_tip", text)
	control.tooltip_text = text if show_tooltips else ""

func _button(text: String, at: Vector2, box: Vector2, toggle: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = box
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_ALL
	panel.add_child(button)
	return button

## 1.08: the small circular "!" icon (same quiet colors as the version text).
func _log_icon() -> Button:
	var button := Button.new()
	button.name = "LogFolderIcon"
	button.text = "!"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(22, 22)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(MUTED, 0.6))
	button.add_theme_color_override("font_hover_color", Color(TEXT, 0.9))
	button.add_theme_color_override("font_pressed_color", ACCENT)
	for state in ["normal", "hover", "pressed", "focus"]:
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color(0, 0, 0, 0) if state != "pressed" else Color(ACCENT, 0.15)
		ring.border_color = Color(MUTED, 0.6) if state == "normal" else (Color(TEXT, 0.9) if state == "hover" else ACCENT)
		if state == "focus":
			ring.draw_center = false
			ring.border_color = Color(0, 0, 0, 0)
		ring.set_border_width_all(1)
		ring.set_corner_radius_all(11)
		ring.content_margin_left = 0
		ring.content_margin_right = 0
		ring.content_margin_top = 0
		ring.content_margin_bottom = 0
		button.add_theme_stylebox_override(state, ring)
	return button

func _slider(at: Vector2) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.position = at
	slider.size = Vector2(250, 40)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.09, 0.16)
	track.set_corner_radius_all(3)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.72, 0.36, 0.53)
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob(Color(1.0, 0.72, 0.86))
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", _knob(Color(1.0, 0.9, 0.95)))
	panel.add_child(slider)
	return slider

func _knob(color: Color) -> Texture2D:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26"><circle cx="13" cy="13" r="11" fill="#%s" stroke="#2a0f1e" stroke-width="2"/></svg>' % color.to_html(false)
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.0) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _divider(y: float) -> void:
	var line := ColorRect.new()
	line.color = EDGE
	line.position = Vector2(44, y)
	line.size = Vector2(PANEL_SIZE.x - 88, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
