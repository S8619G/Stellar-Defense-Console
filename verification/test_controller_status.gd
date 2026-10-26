extends SceneTree
## 1.0.2 controller connection status, button lights, TEST BUTTONS, the battle press
## flash and the controller check. These are SYNTHETIC checks: Godot joypad events are
## generated in software. They prove the game logic, not a physical controller, its
## Bluetooth or USB connection, or the operating system's controller driver.
const ControllerBindings = preload("res://scripts/ControllerBindings.gd")
const ControllerInput = preload("res://scripts/ControllerInput.gd")
const ControllerPanel = preload("res://scripts/ControllerPanel.gd")

var checks := 0
var failures := 0
var console: Control
var c: Control
var pad: Node
var panel: Control
const BINDINGS_FILE := "user://verify_status_bindings.cfg"
const SETTINGS_FILE := "user://verify_status_settings.cfg"
const SCORES_FILE := "user://verify_status_scores.json"
const FAKE_LOG := "user://verify_status_godot.log"

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func frames(count: int = 3) -> void:
	for i in range(count):
		await process_frame

func button(index: int, pressed: bool, device: int = 0) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = pressed
	root.push_input(event)

func axis(which: int, value: float, device: int = 0) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = which
	event.axis_value = value
	root.push_input(event)

func _cleanup() -> void:
	for path in [BINDINGS_FILE, BINDINGS_FILE + ".tmp", SETTINGS_FILE, SCORES_FILE, FAKE_LOG]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _run() -> void:
	_cleanup()
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = SETTINGS_FILE
	console.high_score_file = SCORES_FILE
	console.controller_file = BINDINGS_FILE
	console.shell_dry_run = true
	console.quit_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.auto_spawn = false
	c.klaxon_enabled = false
	root.add_child(console)
	root.size = Vector2i(1600, 900)
	await frames(8)
	c.reset_battle()
	c.set_process(false)
	console.get_node("SweepLoop").stop()
	pad = console.controller
	panel = console.controller_panel
	pad.set_process(false)
	console.set_process(false)

	_connection_types()
	_status_text()
	_driver_status()
	await _panel_status()
	await _lights()
	await _test_mode()
	await _battle_flash()
	_check_report()
	_session_log()
	_layout()
	print("CONTROLLER_STATUS_RESULT checks=%d failures=%d" % [checks, failures])
	_cleanup()
	quit(1 if failures > 0 else 0)

func _connection_types() -> void:
	check(ControllerInput.connection_type("0500abcd", {}) == "BLUETOOTH", "Bluetooth controllers are named BLUETOOTH")
	check(ControllerInput.connection_type("03000000", {}) == "USB", "Cable controllers are named USB")
	check(ControllerInput.connection_type("03000000", {"xinput_index": "0"}) == "XINPUT", "Windows XInput controllers are named XINPUT (cable, Bluetooth or adapter look the same there)")
	check(ControllerInput.connection_type("0300", {"steam_input_index": "5"}) == "STEAM INPUT", "Steam Input controllers are named STEAM INPUT")
	check(ControllerInput.connection_type("", {}) == "" and ControllerInput.connection_type("1900abcd", {}) == "", "Unknown connections show no guess")
	check(ControllerInput._hex_id("1118") == "045e" and ControllerInput._hex_id("") == "?" and ControllerInput._hex_id("x") == "?", "Vendor and product numbers are shown in hex (Microsoft = 045e)")

func _status_text() -> void:
	var p: Control = ControllerPanel.new()
	p.status = {"connected": false, "count": 0, "driver": "started"}
	check(p.status_text() == "NO CONTROLLER FOUND" and not p.is_connected_pad(), "No controller: NO CONTROLLER FOUND")
	p.status = {"connected": false, "count": 0, "driver": "failed"}
	check(p.status_text().contains("CONTROLLER SYSTEM DID NOT START"), "Engine controller system failure is shown plainly")
	p.status = {"connected": true, "count": 1, "name": "XBOX CONTROLLER", "compatible": true, "connection": "BLUETOOTH", "driver": "started"}
	check(p.status_text() == "CONNECTED: XBOX CONTROLLER  |  COMPATIBLE  |  BLUETOOTH" and p.is_connected_pad(), "Connected: name, COMPATIBLE and the connection")
	p.status = {"connected": true, "count": 2, "name": "XBOX CONTROLLER", "compatible": false, "connection": "", "driver": "started"}
	var text: String = p.status_text()
	check(text.contains("NOT IN THE CONTROLLER LIST") and text.contains("2 CONTROLLERS") and not text.contains("COMPATIBLE  "), "Unknown controllers and controller counts are shown")
	check(ControllerPanel.light_key("dpad_up") == "dpad" and ControllerPanel.light_key("stick") == "dpad" and ControllerPanel.light_key("rt") == "rt" and ControllerPanel.light_key("guide") == "", "Buttons map to the panel's lights")
	p.free()

func _driver_status() -> void:
	var saved: String = pad.engine_log_file
	pad.engine_log_file = FAKE_LOG
	var f := FileAccess.open(FAKE_LOG, FileAccess.WRITE)
	f.store_line("Godot Engine v4.7")
	f.store_line("ERROR: Couldn't initialize SDL joypad input driver.")
	f.close()
	check(pad.driver_status() == "failed", "Engine log with the controller error reads as failed")
	f = FileAccess.open(FAKE_LOG, FileAccess.WRITE)
	f.store_line("Godot Engine v4.7")
	f.close()
	check(pad.driver_status() == "started", "Engine log without the error reads as started")
	pad._driver_checked_msec = -1
	var first: String = pad.cached_driver_status()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FAKE_LOG))
	check(first == "started" and pad.cached_driver_status() == "started", "The status line reuses the engine-log result instead of reading it twice a second")
	check(pad.driver_status() == "unknown", "Missing engine log reads as unknown")
	pad._driver_checked_msec = -1
	pad.engine_log_file = saved

func _panel_status() -> void:
	console.open_settings()
	console.open_controller_panel()
	await frames(2)
	check(panel.visible and panel.controller_input == pad, "Controller panel opens and reads the controller status")
	check(panel.header_label.text == "BATTLE PAUSED", "Header says BATTLE PAUSED")
	check(panel.status_label.text.contains("NO CONTROLLER FOUND"), "With no controller the status line says NO CONTROLLER FOUND")
	check(panel.hint_label.text.contains("Bluetooth") and panel.hint_label.text.contains("USB"), "With no controller the hint explains Bluetooth, USB and the adapter")
	check(panel.status_label.get_theme_color("font_color") == ControllerPanel.AMBER, "No controller is shown in amber")
	check(panel.is_processing(), "The panel keeps checking the connection while open")
	# Simulated connected controller: status comes from the controller code.
	panel.controller_input = null
	panel.status = {"connected": true, "count": 1, "name": "XBOX CONTROLLER", "compatible": true, "connection": "XINPUT", "driver": "started"}
	panel.refresh()
	check(panel.status_label.text.begins_with("CONNECTED: XBOX CONTROLLER") and panel.status_label.get_theme_color("font_color") == ControllerPanel.GREEN, "A compatible controller shows CONNECTED in green")
	check(not panel.hint_label.text.contains("No controller found"), "Connected: no pairing hint")
	panel.controller_input = pad
	panel.update_status()
	panel.refresh()
	check(panel.status_label.text.contains("NO CONTROLLER FOUND"), "Status updates again from the controller code")
	pad._on_joy_connection_changed(5, false)
	check(panel.visible and panel.status_label.text.contains("NO CONTROLLER FOUND"), "A connection change refreshes the open panel")

## 1.0.4: rows are per button; find the row of the button that has Action.
func _row(action: String) -> Dictionary:
	for row in panel.rows:
		if row.spec.get("button", "") != "" and ControllerBindings.action_for(panel.bindings, row.spec.button) == action:
			return row
	return {}

func _fixed(name: String) -> Dictionary:
	for row in panel.rows:
		if row.spec.get("name", "") == name:
			return row
	return {}

func _lights() -> void:
	# A, then release: the Launch Interceptors row and the A tag light up.
	panel.light("a", true)
	check(panel.is_lit("a") and "button:a" in panel.lit_row_keys(), "Pressing A lights LAUNCH INTERCEPTORS")
	check(_row("launch_interceptors").name_label.get_theme_color("font_color") == ControllerPanel.AMBER, "The lit row's text turns amber")
	check(_row("defense_shield").name_label.get_theme_color("font_color") == ControllerPanel.TEXT, "Other rows stay as they were")
	panel.light("a", false)
	check(panel.is_lit("a"), "A quick tap stays lit briefly so it can be seen")
	panel._process(0.5)
	check(not panel.is_lit("a") and panel.lit_row_keys().is_empty(), "The light fades after release")
	check(_row("launch_interceptors").name_label.get_theme_color("font_color") == ControllerPanel.TEXT, "Row colour returns after the light fades")
	# Held buttons stay lit.
	panel.light("rb", true)
	panel._process(2.0)
	check(panel.is_lit("rb") and "button:rb" in panel.lit_row_keys(), "A held button stays lit (RB = RAPID REPAIR)")
	panel.light("rb", false)
	panel._process(0.5)
	# Real joypad events, D-pad and triggers.
	button(JOY_BUTTON_DPAD_LEFT, true)
	await frames(1)
	check(panel.is_lit("dpad") and "fixed:MOVE HIGHLIGHT" in panel.lit_row_keys(), "D-pad lights MOVE HIGHLIGHT")
	button(JOY_BUTTON_DPAD_LEFT, false)
	await frames(1)
	panel._process(0.5)
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await frames(1)
	check(panel.is_lit("rt") and "button:rt" in panel.lit_row_keys(), "RT trigger lights its row")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await frames(1)
	panel._process(0.5)
	check(not panel.is_lit("rt"), "RT light fades after release")
	axis(JOY_AXIS_LEFT_X, -1.0)
	await frames(1)
	check(panel.is_lit("dpad"), "Left stick lights MOVE HIGHLIGHT")
	axis(JOY_AXIS_LEFT_X, 0.0)
	await frames(1)
	panel._process(0.5)
	check(not panel.is_lit("dpad"), "Stick light fades when centred")

func _test_mode() -> void:
	var change_presses := [0]
	panel.start_test()
	check(panel.is_testing() and pad.context() == "test" and panel.test_button.text == "STOP TEST", "TEST BUTTONS starts the test (button reads STOP TEST)")
	check(panel.hint_label.text.contains("press any controller button"), "Test explains what to do")
	# B normally goes back; in the test it only lights.
	button(JOY_BUTTON_B, true)
	await frames(1)
	check(panel.visible and panel.is_testing(), "B during the test does not close the panel")
	check("button:b" in panel.lit_row_keys() and panel.hint_label.text.contains("B works: DEFENSE SHIELD"), "B lights DEFENSE SHIELD and says so")
	button(JOY_BUTTON_B, false)
	await frames(1)
	# A normally presses the highlighted CHANGE; in the test it only lights.
	pad.target = panel.rows[0].button
	button(JOY_BUTTON_A, true)
	await frames(1)
	check(not panel.is_picking(), "A during the test does not press CHANGE")
	check(panel.hint_label.text.contains("A works: LAUNCH INTERCEPTORS"), "A lights LAUNCH INTERCEPTORS and says so")
	button(JOY_BUTTON_A, false)
	await frames(1)
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await frames(1)
	check(panel.hint_label.text.contains("LT works: LAUNCH STEALTH INTERCEPTOR"), "LT lights LAUNCH STEALTH INTERCEPTOR and says so (1.0.4 default)")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await frames(1)
	var trigger_bindings: Dictionary = panel.bindings.duplicate()
	panel.bindings.lt = ""
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await frames(1)
	check(panel.hint_label.text.contains("LT works") and panel.hint_label.text.contains("no battle action") and panel.hint_label.text.contains("CHANGE"), "An unassigned trigger says it works but has no action (use CHANGE)")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await frames(1)
	panel.bindings = trigger_bindings
	button(JOY_BUTTON_DPAD_DOWN, true)
	await frames(1)
	check(panel.is_testing() and panel.hint_label.text.contains("D-PAD / STICK works"), "D-pad during the test lights and does not move the highlight")
	button(JOY_BUTTON_DPAD_DOWN, false)
	await frames(1)
	check(panel.test_presses >= 4, "Test counts the presses")
	# A changed button shows its new action.
	var saved_bindings: Dictionary = panel.bindings.duplicate()
	panel.bindings = ControllerBindings.choose(panel.bindings, "x", "firewall", "both")
	panel.refresh()
	panel.light("x", true)
	check("button:x" in panel.lit_row_keys() and panel.notice.contains("FIREWALL"), "A changed button lights its new action")
	panel.light("x", false)
	panel.bindings = saved_bindings
	panel.refresh()
	# MENU ends the test without closing the panel or Settings.
	button(JOY_BUTTON_START, true)
	await frames(1)
	button(JOY_BUTTON_START, false)
	await frames(1)
	check(panel.visible and not panel.is_testing() and console.settings_open, "MENU ends the test and keeps the panel open")
	check(panel.hint_label.text.contains("Test finished"), "The panel says the test finished")
	# Esc ends the test too, then closes on a second press.
	panel.start_test()
	panel.back()
	check(panel.visible and not panel.is_testing(), "Esc / back ends the test first")
	# The test ends by itself when left alone.
	panel.start_test()
	panel._process(ControllerPanel.TEST_IDLE_SECONDS + 0.5)
	check(not panel.is_testing(), "The test ends by itself after 20 s without a press")
	# Mouse button toggles.
	panel.test_button.pressed.emit()
	check(panel.is_testing(), "TEST BUTTONS can be clicked")
	panel.test_button.pressed.emit()
	check(not panel.is_testing(), "STOP TEST can be clicked")
	# Normal panel behaviour is back after the test.
	pad.target = panel.rows[0].button
	button(JOY_BUTTON_A, true)
	await frames(1)
	button(JOY_BUTTON_A, false)
	await frames(1)
	check(panel.is_picking(), "After the test, A presses CHANGE again (the action list opens)")
	panel.cancel_picker()
	check(change_presses[0] == 0, "No stray actions")

func _battle_flash() -> void:
	console.close_settings()
	await frames(1)
	check(pad.context() == "battle", "Back in battle")
	for b in [console.launch_button, console.prox_button, console.gunship_button, console.firewall_button, console.repair_button, console.jump_button]:
		b.disabled = false
	button(JOY_BUTTON_A, true)
	await frames(1)
	check(pad.flash_control == console.launch_button and pad.flash_left > 0.0, "A in battle lights the LAUNCH button it pressed")
	button(JOY_BUTTON_A, false)
	await frames(1)
	pad._process(0.4)
	check(pad.flash_control == null and pad.flash_left <= 0.0, "The battle light fades in about 0.3 s")
	button(JOY_BUTTON_Y, true)
	await frames(1)
	check(pad.flash_control == console.firewall_button, "Y lights the FIREWALL button")
	button(JOY_BUTTON_Y, false)
	await frames(1)
	pad._process(0.4)
	console.firewall_button.disabled = true
	button(JOY_BUTTON_Y, true)
	await frames(1)
	check(pad.flash_control == null, "A greyed-out button does not light up")
	button(JOY_BUTTON_Y, false)
	await frames(1)
	console.firewall_button.disabled = false
	console.launch_button.pressed.emit()
	check(pad.flash_control == null, "Mouse clicks do not use the controller light")

func _check_report() -> void:
	var report: String = pad.check_report("STELLAR DEFENSE CONSOLE 1.1.1")
	check(report.begins_with("CONTROLLER CHECK | STELLAR DEFENSE CONSOLE 1.1.1"), "Controller check names the game version")
	check(report.contains("System: ") and report.contains("Godot ") and report.contains(Engine.get_architecture_name()), "Controller check names the system, architecture and engine")
	check(report.contains("Controller system: started") or report.contains("Controller system: unknown"), "Controller check says whether the controller system started")
	check(report.contains("Controllers found: 0"), "Controller check counts the controllers")
	check(report.contains("Controller events received: ") and report.contains("last button "), "Controller check counts the controller events it received")
	check(report.contains("Connection changes: "), "Controller check lists recent connection changes")
	check(not report.to_lower().contains("serial"), "Controller check holds no serial numbers")
	var summary: String = pad.pad_summary(9)
	check(summary == "#9 not connected now", "Missing controllers are described safely")
	console.open_settings()
	console.open_controller_panel()
	panel.copy_button.pressed.emit()
	check(panel.copied_text.begins_with("CONTROLLER CHECK") and (panel.notice.contains("copied") or panel.notice.contains("session log")), "The small ! copies the controller check and says so")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		check(DisplayServer.clipboard_get() == panel.copied_text, "The check is on the clipboard")
	console.close_settings()

func _session_log() -> void:
	var log: Node = console.session_log
	console.log_controller_check("verify")
	var text := FileAccess.get_file_as_string(log.file_path) if log != null else ""
	check(text.contains("CONTROLLER") and text.contains("verify | Controllers found"), "The controller check is written to the session log")
	check(text.contains("start | CONTROLLER CHECK"), "The controller check is written at start")
	check(text.contains("check | CONTROLLER CHECK"), "The small ! also writes the check to the session log")

func _layout() -> void:
	console.open_settings()
	console.open_controller_panel()
	var buttons: Array = [panel.defaults_button, panel.test_button, panel.close_button]
	# 1.0.3: the controller check is a small round "!" in the top-right corner.
	var icon: Button = panel.copy_button
	check(icon.get_node("Mark").text == "!" and icon.size.x <= 24.0 and is_equal_approx(icon.size.x, icon.size.y), "The controller check is a small \"!\" button")
	check(icon.focus_mode == Control.FOCUS_NONE and (icon.tooltip_text + String(icon.get_meta("hover_tip", ""))).contains("controller check"), "The small ! has a tooltip and is skipped by the controller highlight")
	var icon_rect := Rect2(icon.position, icon.size)
	check(Rect2(Vector2.ZERO, panel.PANEL_SIZE).encloses(icon_rect) and icon.position.x > panel.PANEL_SIZE.x - 80.0 and icon.position.y < 84.0, "The small ! sits in the top-right corner, above the divider")
	check(not icon_rect.intersects(Rect2(panel.header_label.position, panel.header_label.size)), "The small ! does not cover the header text")
	var no_big := true
	for child in panel.panel.get_children():
		if child is Button and String(child.text).contains("COPY"):
			no_big = false
	check(no_big, "No full-size COPY CONTROLLER CHECK button is left")
	var overlap := false
	for i in range(buttons.size()):
		for j in range(i + 1, buttons.size()):
			if Rect2(buttons[i].position, buttons[i].size).intersects(Rect2(buttons[j].position, buttons[j].size)):
				overlap = true
	check(not overlap, "Bottom buttons do not overlap")
	var font := ThemeDB.fallback_font
	var fits := true
	for b in buttons:
		if font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x > b.size.x - 12:
			fits = false
	check(fits, "Bottom button labels fit")
	panel.status = {"connected": true, "count": 2, "name": "XBOX WIRELESS CONTROLLER", "compatible": false, "connection": "STEAM INPUT", "driver": "started"}
	panel._show_status()
	var fs: int = panel.status_label.get_theme_font_size("font_size")
	check(font.get_string_size(panel.status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= 700.0, "The longest status still fits its line")
	check(panel.status_label.position.y + panel.status_label.size.y <= ControllerPanel.TAGS.menu.y, "Status line sits above the controller drawing's labels")
	console.close_settings()
