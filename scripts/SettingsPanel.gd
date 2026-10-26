extends Control
## Gear-icon Settings panel. 1.1.1: three tabs (Stephen 2026-10-25, mockup
## mockups/settings_redesign_1.1.0): GAME (difficulty, the six auto options, score
## multiplier), SYSTEM (volumes, SCREEN EFFECTS, FRAME RATE, CONTROLLER, REMEMBER
## SETTINGS and DEFAULTS) and ABOUT (the version panel with CHECK NOW, CHECK AT STARTUP and
## GO BACK, what's new, GITHUB PAGE and DATA FOLDER). QUIT, NEW BATTLE and CLOSE are on
## every tab. Settings always opens on GAME; LB / RB (or the tab buttons) switch tabs.
## Built in code so it needs no extra scene file. The console pauses the battle while it is open.

signal changed(settings: Dictionary)
signal close_requested
signal new_battle_requested
signal effects_preview
signal quit_requested
signal open_logs_requested
signal open_github_requested
## 1.0.0: CONTROLLER opens the controller button panel.
signal controller_requested
## 1.1.1: ABOUT tab.
signal check_now_requested
signal check_at_startup_changed(on: bool)
signal go_back_requested

const GameSettings = preload("res://scripts/GameSettings.gd")
const EDGE := Color("#77324f")
const TEXT := Color("#ede0e8")
const MUTED := Color("#b9a8b2")
const ACCENT := Color(1.0, 0.6, 0.78)
const AMBER := Color("#ffe28b")
const GOOD := Color("#8fe3a8")
## 1.1.1: tabs make the panel shorter (1.1.0 was 1054 px tall), so it fits a
## 1280 x 720 window again.
const PANEL_SIZE := Vector2(860, 800)
## QUIT asks once more; the confirmation lapses after this many seconds.
const QUIT_CONFIRM_SECONDS := 3.0
const TAB_NAMES := ["GAME", "SYSTEM", "ABOUT"]

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
## Product title and version, for example "STELLAR DEFENSE CONSOLE 1.1.1" (set by the console).
var version_text: String = ""
var quit_armed: bool = false
var quit_armed_serial: int = 0
var multiplier_label: Label
var multiplier_detail: Label
var note_label: Label
var new_battle_button: Button
var close_button: Button
var controller_button: Button
## 1.1.1: tabs.
var target: Control
var pages: Array[Control] = []
var tab_buttons: Array[Button] = []
var tab_index: int = 0
var paused_label: Label
## 1.1.1: ABOUT tab (filled in by set_about()).
var about_name: Label
var about_version: Label
var about_build: Label
var about_status: Label
var about_status_note: Label
var check_button: Button
var startup_label: Label
var startup_note: Label
var startup_button: Button
var go_back_button: Button
var go_back_note: Label
var news_head: Label
var news_lines: Array[Label] = []
var github_button: Button
var data_button: Button
var about_info: Dictionary = {}

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
	target = panel
	_label("SETTINGS", Vector2(44, 26), Vector2(400, 40), 30, ACCENT)
	paused_label = _label("BATTLE PAUSED", Vector2(PANEL_SIZE.x - 344, 34), Vector2(300, 30), 18, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var tabs_group := ButtonGroup.new()
	for i in range(3):
		var tb := _button(TAB_NAMES[i], Vector2(44 + i * 196, 92), Vector2(184, 52), true)
		tb.name = "Tab" + TAB_NAMES[i]
		tb.button_group = tabs_group
		tb.add_theme_font_size_override("font_size", 20)
		tb.pressed.connect(show_tab.bind(i))
		tab_buttons.append(tb)
	_label("LB / RB", Vector2(PANEL_SIZE.x - 204, 106), Vector2(160, 26), 15, Color(MUTED, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	_divider(160)
	for i in range(3):
		var page := Control.new()
		page.name = "Page" + TAB_NAMES[i]
		page.position = Vector2.ZERO
		page.size = PANEL_SIZE
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(page)
		pages.append(page)
	# ---- GAME ----
	target = pages[0]
	_row_text(176, "DIFFICULTY", "Enemy toughness, attacks and speed", 270)
	var group := ButtonGroup.new()
	for index in range(3):
		var b := _button(GameSettings.DIFFICULTY_NAMES[index], Vector2(320 + index * 168, 176), Vector2(160, 56), true)
		b.button_group = group
		b.pressed.connect(_on_difficulty.bind(index))
		difficulty_buttons.append(b)
	_row_text(242, "AUTO DEFENSE SHIELD", "Fires by itself as missiles near the flak arc", 560)
	auto_battery_button = _button("OFF", Vector2(656, 242), Vector2(160, 56), true)
	_row_text(308, "AUTO FIREWALL", "Raised by itself when a Breacher starts hacking", 560)
	auto_firewall_button = _button("OFF", Vector2(656, 308), Vector2(160, 56), true)
	_row_text(374, "AUTO LAUNCH", "Fighters / nukes and carriers", 420)
	auto_interceptors_button = _button("INTERCEPTORS OFF", Vector2(488, 374), Vector2(160, 56), true)
	auto_gunships_button = _button("GUNSHIPS OFF", Vector2(656, 374), Vector2(160, 56), true)
	auto_interceptors_button.add_theme_font_size_override("font_size", 16)
	auto_gunships_button.add_theme_font_size_override("font_size", 16)
	_tip(auto_interceptors_button, "Automatically launch Interceptors against enemy fighters")
	_tip(auto_gunships_button, "Automatically launch Gunships against nukes and Enemy Carriers")
	_row_text(440, "AUTO RAPID REPAIR", "Uses a repair charge by itself when the hull is at 50% or less", 580)
	auto_repair_button = _button("OFF", Vector2(656, 440), Vector2(160, 56), true)
	_row_text(506, "AUTO JUMP", "Jumps by itself when the hull drops below 10% (usual JUMP cost)", 580)
	auto_jump_button = _button("OFF", Vector2(656, 506), Vector2(160, 56), true)
	_divider(578)
	multiplier_label = _label("", Vector2(44, 594), Vector2(500, 34), 24, ACCENT)
	multiplier_detail = _label("", Vector2(44, 628), Vector2(780, 24), 16, MUTED)
	note_label = _label("", Vector2(44, 654), Vector2(780, 24), 16, AMBER)
	# ---- SYSTEM ----
	target = pages[1]
	_row_text(176, "EFFECTS VOLUME", "Alerts, weapons and battle sounds", 270)
	effects_slider = _slider(Vector2(320, 184))
	effects_value = _label("", Vector2(586, 186), Vector2(70, 30), 20, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	effects_mute = _button("MUTE", Vector2(680, 176), Vector2(136, 56), true)
	_row_text(242, "RADAR VOLUME", "Background radar sweep", 270)
	radar_slider = _slider(Vector2(320, 250))
	radar_value = _label("", Vector2(586, 252), Vector2(70, 30), 20, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	radar_mute = _button("MUTE", Vector2(680, 242), Vector2(136, 56), true)
	_divider(312)
	_row_text(328, "SCREEN EFFECTS", "Screen scramble when a nuke hits or the ship is destroyed", 580)
	screen_effects_button = _button("ON", Vector2(656, 328), Vector2(160, 56), true)
	screen_effects_button.name = "ScreenEffectsButton"
	_tip(screen_effects_button, "OFF: no screen scramble or flicker. The red SYSTEMS OFFLINE screen still shows.")
	_row_text(394, "FRAME RATE", "SMOOTH matches the screen, but uses more power", 580)
	frame_rate_button = _button("STANDARD", Vector2(656, 394), Vector2(160, 56), true)
	frame_rate_button.name = "FrameRateButton"
	_tip(frame_rate_button, "STANDARD: at most 60 frames a second, for quieter fans and longer battery life. SMOOTH: matches the screen's refresh rate, for example 144 on a 144 Hz screen.")
	_divider(464)
	_row_text(480, "CONTROLLER", "See and change what each controller button does", 580)
	controller_button = _button("OPEN", Vector2(656, 480), Vector2(160, 56), false)
	controller_button.name = "ControllerButton"
	_tip(controller_button, "Controller buttons: see and change what each button does")
	_row_text(546, "REMEMBER SETTINGS", "OFF: next start uses NORMAL, autos off", 350)
	reset_button = _button("DEFAULTS", Vector2(488, 546), Vector2(160, 56), false)
	_tip(reset_button, "Put every setting back to its default (press twice to confirm). High scores are not affected.")
	remember_button = _button("ON", Vector2(656, 546), Vector2(160, 56), true)
	# ---- ABOUT ----
	target = pages[2]
	_card(Vector2(44, 176), Vector2(772, 262))
	about_name = _label("STELLAR DEFENSE CONSOLE", Vector2(68, 190), Vector2(540, 36), 26, ACCENT)
	about_version = _label("VERSION", Vector2(68, 228), Vector2(400, 32), 22, TEXT)
	about_build = _label("", Vector2(68, 262), Vector2(560, 24), 16, MUTED)
	go_back_button = _button("GO BACK", Vector2(632, 190), Vector2(160, 52), false)
	go_back_button.name = "GoBackButton"
	_tip(go_back_button, "Swap back to the version kept from before the last update (asks first)")
	go_back_note = _label("", Vector2(600, 246), Vector2(192, 22), 14, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var line := ColorRect.new()
	line.color = Color(EDGE, 0.8)
	line.position = Vector2(68, 298)
	line.size = Vector2(724, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(line)
	about_status = _label("", Vector2(68, 316), Vector2(548, 26), 17, GOOD)
	about_status.clip_text = true
	about_status_note = _label("Asks the GitHub releases page for a newer version", Vector2(68, 340), Vector2(548, 22), 14, MUTED)
	check_button = _button("CHECK NOW", Vector2(632, 310), Vector2(160, 52), false)
	check_button.name = "CheckNowButton"
	_tip(check_button, "Look for a newer version on the GitHub releases page now")
	startup_label = _label("CHECK AT STARTUP", Vector2(68, 378), Vector2(400, 26), 17, TEXT)
	startup_note = _label("Looks quietly each time the game starts", Vector2(68, 402), Vector2(548, 22), 14, MUTED)
	startup_button = _button("ON", Vector2(632, 374), Vector2(160, 52), true)
	startup_button.name = "CheckAtStartupButton"
	_tip(startup_button, "ON: look for a newer version each time the game starts (only offers it; nothing changes without UPDATE NOW)")
	news_head = _label("WHAT'S NEW", Vector2(44, 452), Vector2(500, 30), 20, TEXT)
	for i in range(4):
		news_lines.append(_label("", Vector2(56, 484 + i * 26), Vector2(760, 26), 16, MUTED))
	_divider(594)
	_row_text(606, "LINKS", "Project page and the folder with settings, scores and logs", 420)
	github_button = _button("GITHUB PAGE", Vector2(488, 606), Vector2(160, 56), false)
	github_button.name = "GitHubPageButton"
	_tip(github_button, "Open the project's GitHub page in the browser")
	data_button = _button("DATA FOLDER", Vector2(656, 606), Vector2(160, 56), false)
	data_button.name = "DataFolderButton"
	_tip(data_button, "Open the app data folder (settings, high scores and session logs)")
	# ---- bottom bar (every tab) ----
	target = panel
	_divider(690)
	quit_button = _button("QUIT", Vector2(44, 712), Vector2(200, 56), false)
	_tip(quit_button, "Close Stellar Defense Console (press twice to confirm)")
	new_battle_button = _button("NEW BATTLE", Vector2(400, 712), Vector2(220, 56), false)
	close_button = _button("CLOSE", Vector2(656, 712), Vector2(160, 56), false)
	show_tab(0)
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
	new_battle_button.pressed.connect(func() -> void: new_battle_requested.emit())
	close_button.pressed.connect(func() -> void: close_requested.emit())
	controller_button.pressed.connect(func() -> void: controller_requested.emit())
	github_button.pressed.connect(func() -> void: open_github_requested.emit())
	data_button.pressed.connect(func() -> void: open_logs_requested.emit())
	check_button.pressed.connect(func() -> void: check_now_requested.emit())
	startup_button.toggled.connect(func(on: bool) -> void:
		about_info.check_at_startup = on
		_refresh_about()
		check_at_startup_changed.emit(on))
	go_back_button.pressed.connect(func() -> void: go_back_requested.emit())
	resized.connect(_center_panel)
	_center_panel()

func _center_panel() -> void:
	if panel:
		panel.position = ((size - PANEL_SIZE) * 0.5).round()

## Settings always opens on GAME (Stephen 2026-10-25).
func open(current: Dictionary, battle_difficulty: int) -> void:
	settings = GameSettings.clean(current)
	active_difficulty = battle_difficulty
	visible = true
	quit_armed = false
	reset_armed = false
	_center_panel()
	show_tab(0)
	refresh()
	close_button.grab_focus()

## LB / RB: step to the next or previous tab (wraps around).
func step_tab(direction: int) -> void:
	show_tab(posmod(tab_index + direction, TAB_NAMES.size()))

func show_tab(i: int) -> void:
	tab_index = clampi(i, 0, pages.size() - 1)
	for k in range(pages.size()):
		pages[k].visible = k == tab_index
		tab_buttons[k].set_pressed_no_signal(k == tab_index)

## "BATTLE PAUSED" normally; the console sets other words between battles.
func set_paused_text(text: String) -> void:
	paused_label.text = text

## ABOUT tab contents. Keys: version, build, date, status, status_good, checking,
## check_at_startup, backup_version, updates (false: Steam or no update support),
## updates_note, news (Array of lines), github (bool).
func set_about(info: Dictionary) -> void:
	about_info = info.duplicate()
	_refresh_about()

func _refresh_about() -> void:
	if about_version == null:
		return
	var info := about_info
	about_version.text = "VERSION %s" % info.get("version", "?")
	var bits := [str(info.get("build", ""))]
	if str(info.get("date", "")) != "":
		bits.append("RELEASED %s" % info.date)
	about_build.text = "   |   ".join(PackedStringArray(bits))
	var updates := bool(info.get("updates", true))
	about_status.text = str(info.get("status", ""))
	about_status.add_theme_color_override("font_color", GOOD if bool(info.get("status_good", false)) else MUTED)
	about_status_note.text = str(info.get("updates_note", "Asks the GitHub releases page for a newer version"))
	check_button.visible = updates
	check_button.disabled = bool(info.get("checking", false))
	check_button.text = "CHECKING" if bool(info.get("checking", false)) else "CHECK NOW"
	for n in [startup_label, startup_note, startup_button]:
		n.visible = updates
	var on := bool(info.get("check_at_startup", true))
	startup_button.set_pressed_no_signal(on)
	startup_button.text = "ON" if on else "OFF"
	var back := str(info.get("backup_version", ""))
	go_back_button.visible = updates and back != ""
	go_back_note.visible = go_back_button.visible
	go_back_note.text = "to version %s" % back
	var lines: Array = info.get("news", [])
	news_head.text = "WHAT'S NEW IN %s" % info.get("version", "")
	for i in news_lines.size():
		news_lines[i].visible = i < lines.size()
		if i < lines.size():
			news_lines[i].text = "-  " + str(lines[i])
	github_button.disabled = not bool(info.get("github", true))

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
	target.add_child(label)
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
	target.add_child(button)
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
	target.add_child(slider)
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
	target.add_child(line)

func _card(at: Vector2, box: Vector2) -> Panel:
	var card := Panel.new()
	card.position = at
	card.size = box
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.09, 0.035, 0.07, 0.95)
	st.border_color = Color(0.55, 0.23, 0.38)
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	card.add_theme_stylebox_override("panel", st)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(card)
	return card

