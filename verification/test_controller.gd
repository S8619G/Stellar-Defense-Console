extends SceneTree
## 1.0.0 controller support. These are SYNTHETIC checks: Godot joypad events are
## generated in software. They prove the game logic, not a physical controller,
## driver or platform (see VERIFICATION.md for the real-device acceptance list).
const ControllerBindings = preload("res://scripts/ControllerBindings.gd")
const ControllerInput = preload("res://scripts/ControllerInput.gd")
const LegacyNames = preload("res://scripts/LegacyNames.gd")
const ControllerPanel = preload("res://scripts/ControllerPanel.gd")

var checks := 0
var failures := 0
var console: Control
var c: Control
var pad: Node
var panel: Control
var counts := {}
const BINDINGS_FILE := "user://verify_controller_bindings.cfg"
const SETTINGS_FILE := "user://verify_controller_settings.cfg"
const SCORES_FILE := "user://verify_controller_scores.json"

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

func tap(index: int, device: int = 0) -> void:
	button(index, true, device)
	button(index, false, device)

func axis(which: int, value: float, device: int = 0) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = which
	event.axis_value = value
	root.push_input(event)

func count(name: String) -> int:
	return int(counts.get(name, 0))

func watch(node: BaseButton, name: String) -> void:
	counts[name] = 0
	node.pressed.connect(func() -> void: counts[name] = int(counts[name]) + 1)
	if node.toggle_mode:
		counts[name + "_toggled"] = 0
		node.toggled.connect(func(_on: bool) -> void: counts[name + "_toggled"] = int(counts[name + "_toggled"]) + 1)

func all_enabled() -> void:
	for b in [console.launch_button, console.prox_button, console.gunship_button, console.firewall_button, console.repair_button, console.jump_button]:
		b.disabled = false

func step(seconds: float, slice: float = 0.05) -> void:
	var left := seconds
	while left > 0.0001:
		var d := minf(slice, left)
		pad._process(d)
		left -= d

func _run() -> void:
	for path in [BINDINGS_FILE, SETTINGS_FILE, SCORES_FILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
	check(pad != null and pad.get_parent() == console, "Controller input is part of the console")
	check(panel != null and panel.get_parent() == console, "Controller panel is part of the console")
	check(pad.overlay.get_index() > console.settings_panel.get_index() and pad.overlay.get_index() > panel.get_index(), "Controller highlight draws above Settings and the controller panel")
	# The test drives timing itself.
	pad.set_process(false)
	console.set_process(false)

	_defaults()
	await _battle_actions()
	await _jump_hold()
	await _dead_zone_and_repeat()
	await _settings_and_panel()
	await _remapping_and_persistence()
	await _stealth_and_emp_triggers()
	await _bonus_pick()
	await _battle_highlight()
	await _game_over()
	await _hotplug()
	_session_log()
	print("CONTROLLER_RESULT checks=%d failures=%d" % [checks, failures])
	for path in [BINDINGS_FILE, BINDINGS_FILE + ".tmp", SETTINGS_FILE, SCORES_FILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(1 if failures > 0 else 0)

func _defaults() -> void:
	var d := ControllerBindings.defaults()
	check(d.a == "launch_interceptors" and d.b == "defense_shield" and d.x == "launch_gunship" and d.y == "firewall", "Default A/B/X/Y: Interceptors, Defense Shield, Gunship, Firewall")
	check(d.rb == "rapid_repair" and d.lb == "jump" and d.lt == "launch_stealth" and d.rt == "emp", "Default RB Rapid Repair, LB Jump, LT Stealth Interceptor, RT EMP (1.0.4)")
	check(ControllerBindings.ACTIONS.size() == 8 and "launch_stealth" in ControllerBindings.ACTIONS and "emp" in ControllerBindings.ACTIONS, "Stealth Interceptor and EMP are battle actions (1.0.4)")
	check(ControllerBindings.ACTION_NAMES.launch_stealth == "LAUNCH STEALTH INTERCEPTOR" and ControllerBindings.ACTION_NAMES.emp == "USE EMP", "Stealth and EMP action names")
	check(ControllerBindings.unassigned_actions(d).is_empty() and ControllerBindings.unassigned_buttons(d).is_empty(), "Defaults: every button has an action and every action a button")
	check(pad.bindings == d, "First run starts with the default controller buttons")
	check(ControllerBindings.ACTION_NAMES.launch_interceptors.to_upper().contains("INTERCEPTOR") and ControllerBindings.ACTION_NAMES.launch_gunship.to_upper().contains("GUNSHIP") and ControllerBindings.ACTION_NAMES.defense_shield.to_upper().contains("SHIELD"), "Action names use the rebranded names")
	var all_names := " ".join(PackedStringArray(ControllerBindings.ACTION_NAMES.values())).to_upper()
	var retired_found := []
	for old in LegacyNames.retired_words():
		if all_names.contains(old):
			retired_found.append(old.length())
	check(retired_found.is_empty(), "No retired name in controller action names")
	check(ControllerBindings.label_for(d, "jump").contains("hold 1 s"), "Jump row says hold 1 s")
	check(ControllerBindings.label_for(d, "jump", true).begins_with("L1") and ControllerBindings.label_for(d, "launch_interceptors", true) == "CROSS", "PlayStation names: L1, Cross")
	check(ControllerInput.button_id(JOY_BUTTON_A) == "a" and ControllerInput.button_id(JOY_BUTTON_START) == "menu" and ControllerInput.button_id(JOY_BUTTON_LEFT_SHOULDER) == "lb", "Standard joypad buttons map to A, MENU, LB")

func _battle_actions() -> void:
	check(pad.context() == "battle", "Battle context while nothing is open")
	watch(console.launch_button, "launch")
	watch(console.gunship_button, "gunship")
	watch(console.repair_button, "repair")
	watch(console.jump_button, "jump")
	watch(console.prox_button, "shield")
	watch(console.firewall_button, "firewall")
	all_enabled()
	tap(JOY_BUTTON_A)
	check(count("launch") == 1, "A launches Interceptors through the console button")
	tap(JOY_BUTTON_X)
	check(count("gunship") == 1, "X launches the Gunship")
	tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(count("repair") == 1, "RB is Rapid Repair")
	var shield_before: bool = console.prox_button.button_pressed
	tap(JOY_BUTTON_B)
	check(console.prox_button.button_pressed != shield_before and count("shield_toggled") == 1, "B switches Defense Shield like a click")
	tap(JOY_BUTTON_B)
	check(console.prox_button.button_pressed == shield_before, "B again switches it back")
	var fw_before: bool = console.firewall_button.button_pressed
	tap(JOY_BUTTON_Y)
	check(console.firewall_button.button_pressed != fw_before, "Y switches Firewall")
	tap(JOY_BUTTON_Y)
	# One press = one action (holding A does not repeat).
	button(JOY_BUTTON_A, true)
	button(JOY_BUTTON_A, true)
	button(JOY_BUTTON_A, true)
	button(JOY_BUTTON_A, false)
	check(count("launch") == 2, "Holding A launches once, no repeats")
	console.launch_button.disabled = true
	tap(JOY_BUTTON_A)
	check(count("launch") == 2, "Greyed-out Launch Interceptors is not pressed by the controller")
	console.launch_button.disabled = false
	tap(JOY_BUTTON_START)
	tap(JOY_BUTTON_START)
	check(count("launch") == 2 and not console.settings_open, "MENU twice: Settings opens and closes without launching")
	# Unassigned LT/RT do nothing.
	var trigger_bindings: Dictionary = pad.bindings.duplicate()
	pad.bindings.lt = ""
	pad.bindings.rt = ""
	var before := count("launch") + count("gunship") + count("repair") + count("jump")
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(count("launch") + count("gunship") + count("repair") + count("jump") == before, "Unassigned LT and RT do nothing")
	pad.bindings = trigger_bindings
	# Controller events are consumed, so Godot's menu focus cannot act a second time.
	console.launch_button.grab_focus()
	tap(JOY_BUTTON_A)
	check(count("launch") == 3, "A with Launch focused still presses it only once")
	console.launch_button.release_focus()
	await frames(1)

func _jump_hold() -> void:
	all_enabled()
	var fired := count("jump")
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	check(count("jump") == fired and pad.jump_hold_button == "lb", "LB press starts a Jump hold, nothing jumps yet")
	step(0.5)
	check(count("jump") == fired and pad.jump_progress() > 0.4 and pad.jump_progress() < 0.6, "Half a second: still holding, progress about half")
	step(0.55)
	check(count("jump") == fired + 1, "Held one second: Jump fires once")
	step(2.0)
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	check(count("jump") == fired + 1, "Keeping LB held does not jump again")
	# Early release cancels.
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	step(0.6)
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	step(1.5)
	check(count("jump") == fired + 1 and pad.last_cancel_reason == "released early", "Released early: no Jump")
	# Settings opened during the hold cancels it, and nothing jumps after it closes.
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	step(0.5)
	console.open_settings()
	step(0.2)
	check(pad.jump_hold_button == "" and pad.last_cancel_reason == "screen changed", "Settings opening cancels a Jump hold")
	console.close_settings()
	step(1.5)
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	check(count("jump") == fired + 1, "No delayed Jump after Settings closes, even with LB still down")
	# MENU during a hold.
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	step(0.4)
	tap(JOY_BUTTON_START)
	check(pad.jump_hold_button == "", "MENU cancels a Jump hold")
	tap(JOY_BUTTON_START)
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	step(1.5)
	check(count("jump") == fired + 1 and not console.settings_open, "No Jump after MENU open and close")
	# Missile bonus pick opening during the hold.
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	step(0.5)
	console.open_bonus_pick("rapid", "double", false)
	step(0.1)
	check(pad.jump_hold_button == "" and pad.context() == "bonus", "Bonus pick opening cancels a Jump hold")
	console.bonus_pick_panel.cards[0].pressed.emit()
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	step(1.5)
	check(count("jump") == fired + 1 and not console.bonus_pick_open, "No Jump after the bonus pick closes")
	# Jump becoming unavailable (greyed out) cancels.
	all_enabled()
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	step(0.5)
	console.jump_button.disabled = true
	step(0.6)
	console.jump_button.disabled = false
	step(1.0)
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	check(count("jump") == fired + 1 and pad.last_cancel_reason == "jump not available", "Jump greyed out during the hold: cancelled")
	# Greyed out from the start: no hold.
	console.jump_button.disabled = true
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	check(pad.jump_hold_button == "", "Greyed-out Jump does not start a hold")
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	console.jump_button.disabled = false
	# Window focus lost.
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	step(0.5)
	console._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	step(1.0)
	check(count("jump") == fired + 1 and pad.last_cancel_reason == "window lost focus", "Window focus lost cancels a Jump hold")
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	# Another controller takes over.
	button(JOY_BUTTON_LEFT_SHOULDER, true, 0)
	step(0.5)
	button(JOY_BUTTON_A, true, 1)
	button(JOY_BUTTON_A, false, 1)
	step(1.0)
	check(count("jump") == fired + 1 and pad.last_cancel_reason == "controller changed", "Second controller pressing a button cancels the first one's hold")
	button(JOY_BUTTON_LEFT_SHOULDER, false, 0)
	check(pad.active_device == 1, "The controller that pressed last is followed")
	# Disconnect.
	button(JOY_BUTTON_LEFT_SHOULDER, true, 1)
	step(0.5)
	pad._on_joy_connection_changed(1, false)
	step(1.0)
	check(count("jump") == fired + 1 and pad.jump_hold_button == "" and pad.held.is_empty(), "Controller disconnected mid-hold: no Jump, held buttons forgotten")
	# Defeat during a hold.
	all_enabled()
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	step(0.3)
	var saved_hull: float = c.hull
	c.hull = 0.0
	step(1.0)
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	check(count("jump") == fired + 1, "Hull gone during the hold: no Jump")
	c.hull = saved_hull
	pad.cancel_jump("test")
	await frames(1)

func _dead_zone_and_repeat() -> void:
	check(ControllerInput.stick_to_direction(Vector2(0.3, 0.2), 0.5) == Vector2i.ZERO, "Small stick drift is ignored")
	check(ControllerInput.stick_to_direction(Vector2(0.8, 0.1), 0.5) == Vector2i.RIGHT, "Stick right")
	check(ControllerInput.stick_to_direction(Vector2(-0.2, -0.9), 0.5) == Vector2i.UP, "Stick up")
	check(ControllerInput.stick_to_direction(Vector2(-0.7, 0.3), 0.5) == Vector2i.LEFT, "Stick left")
	pad.hide_battle_highlight()
	axis(JOY_AXIS_LEFT_X, 0.3)
	axis(JOY_AXIS_LEFT_X, -0.35)
	axis(JOY_AXIS_LEFT_Y, 0.2)
	check(not pad.battle_highlight_visible, "Drift inside the dead zone shows no highlight")
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	# Right stick has no action.
	axis(JOY_AXIS_RIGHT_X, 1.0)
	axis(JOY_AXIS_RIGHT_X, 0.0)
	check(not pad.battle_highlight_visible, "Right stick does nothing")
	# Trigger hysteresis: LT temporarily set to Gunship.
	pad.bindings = ControllerBindings.choose(pad.bindings, "lt", "launch_gunship", "both")
	all_enabled()
	var g := count("gunship")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.5)
	check(count("gunship") == g, "Light trigger touch (0.5) does not press")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.7)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.5)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.65)
	check(count("gunship") == g + 1, "Trigger presses once and does not chatter between 0.3 and 0.6")
	axis(JOY_AXIS_TRIGGER_LEFT, 0.1)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.9)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(count("gunship") == g + 2, "Released and pressed again: second press")
	pad.bindings = ControllerBindings.defaults()
	# Repeat in a menu: bounded by delay and interval.
	console.open_settings()
	pad._after_context_change()
	var moves := [0]
	var first: Control = pad.current_target()
	var on_move := func() -> void: moves[0] += 1
	var original_target: Control = first
	check(first == console.settings_panel.close_button, "Settings highlight starts on CLOSE (its keyboard focus)")
	button(JOY_BUTTON_DPAD_UP, true)
	var after_one: Control = pad.target
	check(after_one != original_target, "D-pad up moves the Settings highlight")
	var seen := {}
	seen[after_one] = true
	var changes := 1
	var last: Control = after_one
	for i in range(20):  # 1.0 s held
		pad._process(0.05)
		if pad.target != last:
			changes += 1
			last = pad.target
	button(JOY_BUTTON_DPAD_UP, false)
	# 1 immediate + repeats at 0.4, 0.53, 0.66, 0.79, 0.92 = at most 6
	check(changes >= 3 and changes <= 6, "Held D-pad repeats after a delay at a steady rate (%d moves in 1 s)" % changes)
	var held_target: Control = pad.target
	step(1.0)
	check(pad.target == held_target, "Released D-pad stops repeating")
	console.close_settings()
	await frames(1)

func _settings_and_panel() -> void:
	var launches := count("launch")
	var jumps := count("jump")
	tap(JOY_BUTTON_START)
	check(console.settings_open and pad.context() == "settings", "MENU opens Settings")
	check(pad.highlight_shown() and pad.current_target() != null, "Settings shows a controller highlight")
	# 1.1.1: Settings opens on the GAME tab; RB steps to SYSTEM, where CONTROLLER now is.
	check(console.settings_panel.tab_index == 0, "Settings opens on the GAME tab (1.1.1)")
	tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(console.settings_panel.tab_index == 1 and console.settings_panel.controller_button.is_visible_in_tree(), "RB steps to the SYSTEM tab (1.1.1)")
	check(pad.current_target() != null and pad.current_target().is_visible_in_tree(), "Highlight moves onto the SYSTEM tab")
	tap(JOY_BUTTON_LEFT_SHOULDER)
	check(console.settings_panel.tab_index == 0, "LB steps back to the GAME tab (1.1.1)")
	tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(count("launch") == launches and count("jump") == jumps and c.is_processing() == false, "LB / RB in Settings never jump or launch")
	# A in Settings presses the highlighted control, never Launch Interceptors.
	pad.target = console.settings_panel.controller_button
	tap(JOY_BUTTON_A)
	check(panel.visible and pad.context() == "controller", "A on CONTROLLER opens the controller panel")
	check(count("launch") == launches, "A in menus never launches Interceptors")
	check(panel.header_label.text.contains("BATTLE PAUSED") and panel.status_label.text.contains("NO CONTROLLER FOUND"), "Panel header shows paused; the status line shows the controller status")
	check(not c.is_processing(), "Battle stays paused under the controller panel")
	var labels := []
	for row in panel.rows:
		labels.append(row.name_label.text)
	var keys := []
	for row in panel.rows:
		keys.append(row.keys_label.text)
	check(panel.rows.size() == 10, "Panel lists the 8 controller buttons and the 2 fixed rows (1.0.4)")
	check(keys.slice(0, 8) == ["A", "B", "X", "Y", "LB", "RB", "LT", "RT"], "One row per button, A to RT, in the BUTTON column")
	check(labels[0] == ControllerBindings.ACTION_NAMES.launch_interceptors and labels[4] == "JUMP  (hold 1 s)" and labels[6] == "LAUNCH STEALTH INTERCEPTOR" and labels[7] == "USE EMP", "ACTION column: A Launch Interceptors, LB Jump (hold 1 s), LT Stealth, RT EMP")
	var all_change := true
	for i in range(8):
		if panel.rows[i].button.text != "CHANGE" or panel.rows[i].button.disabled:
			all_change = false
	check(all_change, "Every button row has a CHANGE button (no SET rows)")
	check(panel.rows[8].button.disabled and panel.rows[9].button.disabled and panel.rows[8].keys_label.text == "MENU", "MENU and D-pad/stick rows are fixed")
	var targets: Array = pad.targets()
	check(targets.size() == 11 and targets[-1] == panel.close_button and targets[-2] == panel.test_button and targets[-3] == panel.defaults_button and not targets.has(panel.copy_button), "Highlight reaches each CHANGE button, DEFAULTS, TEST BUTTONS and CLOSE (fixed rows and the small ! skipped)")
	# Navigation by D-pad through the column.
	pad.target = panel.rows[0].button
	tap(JOY_BUTTON_DPAD_DOWN)
	check(pad.target == panel.rows[1].button, "D-pad down moves to the next row")
	tap(JOY_BUTTON_DPAD_UP)
	check(pad.target == panel.rows[0].button, "D-pad up moves back")
	# B goes back to Settings, then closes Settings.
	tap(JOY_BUTTON_B)
	check(not panel.visible and console.settings_open, "B closes the controller panel and returns to Settings")
	check(pad.current_target() == console.settings_panel.controller_button, "Highlight returns to CONTROLLER")
	tap(JOY_BUTTON_B)
	check(not console.settings_open and pad.context() == "battle", "B in Settings closes it")
	check(count("launch") == launches, "Closing menus with B did not launch anything")
	# Keyboard Esc still works for both.
	console.open_settings()
	console.open_controller_panel()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	check(not panel.visible and console.settings_open, "Keyboard Esc closes the controller panel first")
	root.push_input(esc)
	check(not console.settings_open, "Keyboard Esc then closes Settings as before")
	# MENU from the controller panel closes everything.
	console.open_settings()
	console.open_controller_panel()
	tap(JOY_BUTTON_START)
	check(not panel.visible and not console.settings_open, "MENU on the controller panel returns to the battle")
	# Mouse/touch path: the Settings CONTROLLER button works with a plain click signal.
	console.open_settings()
	console.settings_panel.controller_button.pressed.emit()
	check(panel.visible, "CONTROLLER button works with the mouse")
	panel.close_button.pressed.emit()
	check(not panel.visible and console.settings_open, "CLOSE returns to Settings")
	console.close_settings()
	check(not panel.visible, "Closing Settings never leaves the controller panel open")
	await frames(1)

func _picker_texts() -> Array:
	var out := []
	for item in panel.picker_items:
		out.append(panel.item_text(item))
	return out

func _row_of(button_id: String) -> Dictionary:
	return panel.rows[panel.row_index(button_id)]

func _remapping_and_persistence() -> void:
	console.open_settings()
	console.open_controller_panel()
	# 1.0.4: CHANGE on A opens the list of every action.
	pad.target = panel.rows[0].button
	tap(JOY_BUTTON_A)
	check(panel.is_picking() and pad.context() == "picker" and panel.picker_layer.visible, "A on CHANGE opens the action list")
	check(panel.picker_title.text == "CHOOSE AN ACTION FOR A", "The list says which button it is for")
	var names := []
	for action in ControllerBindings.ACTIONS:
		names.append(ControllerBindings.ACTION_NAMES[action])
	check(_picker_texts() == names, "The list shows all 8 actions, Stealth Interceptor and EMP included")
	check(panel.picker_cancel.visible and pad.targets().size() == 9 and pad.targets()[-1] == panel.picker_cancel, "Highlight reaches the 8 actions and CANCEL, nothing behind the list")
	check(pad.current_target() == panel.picker_items[0], "Highlight starts on the button's current action")
	var note := panel.picker_items[0].get_node("Note") as Label
	check(note != null and note.text == "CURRENT", "Current action is marked CURRENT")
	var emp_note := panel.picker_items[7].get_node_or_null("Note") as Label
	check(emp_note != null and emp_note.text == "ON RT", "Actions on other buttons show where they are (USE EMP: ON RT)")
	tap(JOY_BUTTON_DPAD_DOWN)
	check(pad.target == panel.picker_items[1], "D-pad down moves through the list")
	tap(JOY_BUTTON_DPAD_UP)
	# B closes the list with no change; the panel stays open.
	tap(JOY_BUTTON_B)
	check(not panel.is_picking() and panel.visible and pad.bindings == ControllerBindings.defaults(), "B closes the list without a change; the panel stays open")
	check(pad.current_target() == panel.rows[0].button, "Highlight returns to A's CHANGE")
	# MENU closes the list only.
	panel.open_picker("a")
	tap(JOY_BUTTON_START)
	check(not panel.is_picking() and panel.visible and console.settings_open, "MENU closes the list without a change; the panel stays open")
	# Esc / back and CANCEL.
	panel.open_picker("a")
	panel.back()
	check(not panel.is_picking() and panel.visible, "Esc closes the list first")
	panel.open_picker("a")
	panel.picker_cancel.pressed.emit()
	check(not panel.is_picking() and pad.bindings == ControllerBindings.defaults() and panel.notice.contains("Nothing was changed"), "CANCEL closes the list: nothing changed")
	# Picking the current action changes nothing.
	panel.open_picker("a")
	panel.picker_items[0].pressed.emit()
	check(not panel.is_picking() and pad.bindings == ControllerBindings.defaults(), "Picking the current action closes the list with no change")
	# Picking an action no other button has: applied at once. (Clear RT first.)
	var free := ControllerBindings.defaults()
	free.rt = ""
	pad.set_bindings(free)
	panel.open(pad.bindings)
	panel.open_picker("b")
	panel.picker_items[ControllerBindings.ACTIONS.find("emp")].pressed.emit()
	check(not panel.is_picking() and pad.bindings.b == "emp" and pad.bindings.rt == "", "A free action is applied straight away; the list closes")
	check(_row_of("b").name_label.text == "USE EMP", "The B row shows its new action")
	check(panel.notice.contains("B is now USE EMP") and panel.notice.contains("DEFENSE SHIELD has no button now"), "Panel says what changed and that Defense Shield has no button now")
	check(ControllerBindings.load_bindings(BINDINGS_FILE) == pad.bindings, "Change is saved to the controller file")
	check(not FileAccess.file_exists(BINDINGS_FILE + ".tmp"), "No temporary file left after saving")
	# Picking an action another button has: the choice step.
	pad.set_bindings(ControllerBindings.defaults())
	panel.open(pad.bindings)
	panel.open_picker("a")
	pad._after_context_change()
	pad.target = panel.picker_items[ControllerBindings.ACTIONS.find("emp")]
	tap(JOY_BUTTON_A)
	check(panel.is_picking() and panel.picker_step == "choice" and pad.context() == "picker", "Picking an action on another button asks what to do")
	check(panel.picker_title.text == "USE EMP IS ALREADY ON RT" and panel.picker_subtitle.text == "What would you like to do?", "The question names the action and the other button")
	check(_picker_texts() == ["SWAP THE TWO BUTTONS", "USE BOTH BUTTONS", "MOVE IT HERE", "CANCEL"], "Choices: swap, use both, move it here, cancel")
	var details := []
	for item in panel.picker_items:
		details.append((item.get_node("Detail") as Label).text)
	check(details == ["RT gets LAUNCH INTERCEPTORS.", "A and RT will both do USE EMP.", "RT becomes (not set).", "Nothing changes."], "Each choice says what will happen")
	check(pad.targets().size() == 4 and not panel.picker_cancel.visible, "Highlight reaches the four choices")
	# B on the choice step goes back to the list.
	tap(JOY_BUTTON_B)
	check(panel.is_picking() and panel.picker_step == "list" and _picker_texts().size() == 8, "B on the choice goes back to the list")
	panel.pick("emp")
	# CANCEL on the choice: nothing changes.
	panel.picker_items[3].pressed.emit()
	check(not panel.is_picking() and pad.bindings == ControllerBindings.defaults(), "CANCEL choice: nothing changes, the list closes")
	# SWAP.
	panel.open_picker("a")
	panel.pick("emp")
	pad._after_context_change()
	check(pad.current_target() == panel.picker_items[0], "Highlight starts on SWAP")
	tap(JOY_BUTTON_A)
	check(not panel.is_picking() and pad.bindings.a == "emp" and pad.bindings.rt == "launch_interceptors", "SWAP: A uses the EMP, RT launches Interceptors")
	check(_row_of("a").name_label.text == "USE EMP" and _row_of("rt").name_label.text == "LAUNCH INTERCEPTORS", "Both rows update")
	check(panel.notice == "A is now USE EMP. RT is now LAUNCH INTERCEPTORS.", "Panel says what swapped")
	check(ControllerBindings.load_bindings(BINDINGS_FILE) == pad.bindings, "Swap is saved")
	check(pad.current_target() == _row_of("a").button, "Highlight returns to A's CHANGE")
	# USE BOTH.
	pad.set_bindings(ControllerBindings.defaults())
	panel.open(pad.bindings)
	panel.open_picker("y")
	panel.pick("jump")
	panel.picker_items[1].pressed.emit()
	check(pad.bindings.y == "jump" and pad.bindings.lb == "jump", "USE BOTH: Y and LB both Jump")
	check(ControllerBindings.buttons_for(pad.bindings, "firewall").is_empty() and panel.notice.contains("FIREWALL has no button now"), "Firewall has no button now, and the panel says so")
	check(_row_of("y").name_label.text == "JUMP  (hold 1 s)", "Y row shows Jump (hold 1 s)")
	# Jump on two buttons keeps the hold on both (back in the battle).
	console.close_settings()
	all_enabled()
	var j := count("jump")
	button(JOY_BUTTON_Y, true)
	step(0.4)
	check(count("jump") == j, "Jump on Y does not jump at once")
	step(0.7)
	button(JOY_BUTTON_Y, false)
	check(count("jump") == j + 1, "Jump on Y still needs the one-second hold")
	console.open_settings()
	console.open_controller_panel()
	# MOVE IT HERE.
	panel.open_picker("x")
	panel.pick("rapid_repair")
	panel.picker_items[2].pressed.emit()
	check(pad.bindings.x == "rapid_repair" and pad.bindings.rb == "", "MOVE IT HERE: X Rapid Repair, RB (not set)")
	check(_row_of("rb").name_label.text == "(not set)" and _row_of("rb").name_label.get_theme_color("font_color") == ControllerPanel.MUTED, "RB row shows (not set) in grey")
	check(panel.notice.contains("RB is now (not set)") and panel.notice.contains("LAUNCH GUNSHIP has no button now"), "Panel says RB is not set and Gunship has no button")
	# The (not set) button can be given an action from the list.
	panel.open_picker("rb")
	check(panel.picker_title.text == "CHOOSE AN ACTION FOR RB" and panel.picker_items[ControllerBindings.ACTIONS.find("launch_gunship")].get_node_or_null("Note") == null, "An action with no button has no ON note")
	panel.pick("launch_gunship")
	check(pad.bindings.rb == "launch_gunship" and not panel.is_picking(), "A (not set) button takes a free action")
	# Mouse/touch path: CHANGE and list items are plain buttons.
	panel.rows[panel.row_index("lt")].button.pressed.emit()
	check(panel.is_picking() and panel.picking_button == "lt", "CHANGE works with the mouse")
	panel.picker_items[0].pressed.emit()
	check(panel.picker_step == "choice", "List items work with the mouse")
	panel.picker_items[3].pressed.emit()
	check(not panel.is_picking() and pad.bindings.lt == "launch_stealth", "CANCEL works with the mouse")
	# PlayStation names in the list.
	panel.playstation_names = true
	panel.open_picker("a")
	panel.pick("emp")
	check(panel.picker_title.text == "USE EMP IS ALREADY ON R2", "PlayStation names in the question (R2)")
	panel.cancel_picker()
	panel.playstation_names = false
	# TEST BUTTONS closes the list.
	panel.open_picker("a")
	panel.start_test()
	check(not panel.is_picking() and panel.is_testing(), "TEST BUTTONS closes the list")
	panel.stop_test()
	# Closing the panel closes the list.
	panel.open_picker("a")
	panel.close_button.pressed.emit()
	check(not panel.is_picking() and not panel.picker_layer.visible, "CLOSE never leaves the list open")
	console.open_controller_panel()
	# DEFAULTS needs a second press.
	panel._on_defaults_pressed()
	check(panel.defaults_button.text == "CONFIRM" and pad.bindings.y == "jump", "DEFAULTS asks to confirm first")
	panel._on_defaults_pressed()
	check(pad.bindings == ControllerBindings.defaults(), "CONFIRM restores the default buttons (LT Stealth, RT EMP)")
	check(ControllerBindings.load_bindings(BINDINGS_FILE) == ControllerBindings.defaults(), "Defaults are saved")
	# Settings DEFAULTS and the settings file are separate.
	pad.set_bindings(ControllerBindings.choose(pad.bindings, "rt", "firewall", "move"))
	var settings_text := FileAccess.get_file_as_string(SETTINGS_FILE) if FileAccess.file_exists(SETTINGS_FILE) else ""
	check(not settings_text.contains("controller") and not settings_text.contains("launch_interceptors"), "Controller buttons are not stored in the settings file")
	# Restart: a new console reads the same file.
	var reread := ControllerBindings.load_bindings(BINDINGS_FILE)
	check(reread.rt == "firewall" and reread.y == "", "Saved buttons come back after a restart, blanks included")
	var saved_text := FileAccess.get_file_as_string(BINDINGS_FILE)
	check(saved_text.contains("format=2"), "Saved file is format 2")
	# 1.0.4 upgrade: a 1.0.0-1.0.3 file with blank LT/RT gets Stealth and EMP.
	var f := FileAccess.open(BINDINGS_FILE, FileAccess.WRITE)
	f.store_string("[controller]\nformat=1\na=\"launch_gunship\"\nb=\"defense_shield\"\nx=\"launch_interceptors\"\ny=\"firewall\"\nlb=\"jump\"\nrb=\"rapid_repair\"\nlt=\"\"\nrt=\"\"\n")
	f.close()
	var upgraded := ControllerBindings.load_bindings(BINDINGS_FILE)
	check(upgraded.lt == "launch_stealth" and upgraded.rt == "emp", "Older saved setup: blank LT and RT get Stealth and EMP")
	check(upgraded.a == "launch_gunship" and upgraded.x == "launch_interceptors", "Older saved setup: the player's own buttons are kept")
	f = FileAccess.open(BINDINGS_FILE, FileAccess.WRITE)
	f.store_string("[controller]\nformat=1\na=\"launch_interceptors\"\nb=\"defense_shield\"\nx=\"launch_gunship\"\ny=\"\"\nlb=\"jump\"\nrb=\"rapid_repair\"\nlt=\"firewall\"\nrt=\"\"\n")
	f.close()
	upgraded = ControllerBindings.load_bindings(BINDINGS_FILE)
	check(upgraded.lt == "firewall" and upgraded.rt == "emp" and upgraded.y == "", "Older saved setup: a trigger the player set is kept; only the blank one is filled")
	var migrated := ControllerBindings.migrate({"a": "launch_interceptors"}, 2)
	check(migrated.lt == "launch_stealth", "Missing keys use the defaults")
	check(ControllerBindings.migrate({"lt": "", "rt": ""}, 2).lt == "", "Format 2 blanks stay blank (the player's choice)")
	# Damaged file: defaults, no crash.
	f = FileAccess.open(BINDINGS_FILE, FileAccess.WRITE)
	f.store_string("[controller]\na=\"warp_drive\"\nb=42\nx=7.5\nlb=[1, 2]\n")
	f.close()
	var damaged := ControllerBindings.load_bindings(BINDINGS_FILE)
	check(damaged == ControllerBindings.defaults(), "Damaged controller file falls back to the defaults")
	var partial := ControllerBindings.clean({"a": "warp_drive", "b": 7})
	check(partial.a == "launch_interceptors" and partial.b == "defense_shield", "Unknown values are replaced with the default")
	# Every button can take every action, with each choice.
	var all_ok := true
	for b in ControllerBindings.BUTTONS:
		for action in ControllerBindings.ACTIONS:
			for choice in ["swap", "both", "move"]:
				var d := ControllerBindings.defaults()
				var out := ControllerBindings.choose(d, b, action, choice)
				if out[b] != action:
					all_ok = false
				var others := ControllerBindings.conflicts(d, b, action)
				for other in others:
					var expect: String = d[b] if choice == "swap" else (action if choice == "both" else "")
					if out[other] != expect:
						all_ok = false
				for rest in ControllerBindings.BUTTONS:
					if rest != b and not rest in others and out[rest] != d[rest]:
						all_ok = false
	check(all_ok, "Every button can take every action; swap/both/move touch only the buttons involved (192 cases)")
	var swap_ok := true
	for b in ControllerBindings.BUTTONS:
		for action in ControllerBindings.ACTIONS:
			if not ControllerBindings.unassigned_actions(ControllerBindings.choose(ControllerBindings.defaults(), b, action, "swap")).is_empty():
				swap_ok = false
	check(swap_ok, "SWAP from the defaults never leaves an action without a button")
	check(ControllerBindings.choose(ControllerBindings.defaults(), "a", "emp", "") == ControllerBindings.defaults(), "No choice given for a used action: nothing changes")
	check(ControllerBindings.choose(ControllerBindings.defaults(), "menu", "emp", "swap") == ControllerBindings.defaults(), "MENU is never given an action")
	pad.set_bindings(ControllerBindings.defaults())
	console.close_settings()
	await frames(1)

## 1.0.4: LT launches the Stealth Interceptor and RT uses the EMP (defaults).
func _stealth_and_emp_triggers() -> void:
	all_enabled()
	pad.hide_battle_highlight()
	pad.set_bindings(ControllerBindings.defaults())
	var ship: Control = console.get_node("ShipStatus")
	ship.set_process(false)
	var stealth := [0]
	ship.stealth_button.pressed.connect(func() -> void: stealth[0] += 1)
	var was_visible: bool = ship.stealth_button.visible
	var was_disabled: bool = ship.stealth_button.disabled
	ship.stealth_button.visible = false
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(stealth[0] == 0, "LT does nothing while the Stealth Interceptor is not offered")
	ship.stealth_button.visible = true
	ship.stealth_button.disabled = false
	await frames(1)
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(stealth[0] == 1, "LT launches the Stealth Interceptor through its own button")
	check(pad.flash_control == ship.stealth_button, "LT lights the special weapon it pressed")
	ship.stealth_button.disabled = true
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(stealth[0] == 1, "Greyed-out Stealth Interceptor is not fired by LT")
	ship.stealth_button.visible = was_visible
	ship.stealth_button.disabled = was_disabled
	var emp := [0]
	var ship_emp := [0]
	console.emp_split_button.pressed.connect(func() -> void: emp[0] += 1)
	ship.emp_button.pressed.connect(func() -> void: ship_emp[0] += 1)
	var vis: bool = console.emp_split_button.visible
	var dis: bool = console.emp_split_button.disabled
	var svis: bool = ship.emp_button.visible
	console.emp_split_button.visible = false
	ship.emp_button.visible = false
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(emp[0] == 0 and ship_emp[0] == 0, "RT does nothing while no EMP is offered")
	console.emp_split_button.visible = true
	console.emp_split_button.disabled = false
	await frames(1)
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(emp[0] == 1 and ship_emp[0] == 0, "RT uses the EMP through the EMP half of FIREWALL")
	console.emp_split_button.visible = false
	ship.emp_button.visible = true
	ship.emp_button.disabled = false
	await frames(1)
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(ship_emp[0] == 1, "RT uses the EMP on the ship when that is the one shown")
	console.emp_split_button.visible = vis
	console.emp_split_button.disabled = dis
	ship.emp_button.visible = svis
	# Stealth on a face button works the same way.
	pad.set_bindings(ControllerBindings.choose(ControllerBindings.defaults(), "a", "launch_stealth", "swap"))
	ship.stealth_button.visible = true
	ship.stealth_button.disabled = false
	await frames(1)
	var l := count("launch")
	tap(JOY_BUTTON_A)
	check(stealth[0] == 2 and count("launch") == l, "Stealth Interceptor moved to A: A launches it, not Interceptors")
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(count("launch") == l + 1, "After the swap, LT launches Interceptors")
	ship.stealth_button.visible = was_visible
	ship.stealth_button.disabled = was_disabled
	pad.set_bindings(ControllerBindings.defaults())
	ship.set_process(true)
	pad._process(0.5)
	await frames(1)

func _bonus_pick() -> void:
	var launches := count("launch")
	console.open_bonus_pick("rapid", "double", false)
	await frames(1)
	check(pad.context() == "bonus", "Bonus pick is its own controller screen")
	check(not console.bonus_pick_panel.waiting, "1.0.5: the countdown runs until the player does something")
	tap(JOY_BUTTON_START)
	check(console.bonus_pick_open and not console.settings_open, "MENU cannot skip the bonus pick")
	check(console.bonus_pick_panel.waiting and console.bonus_pick_panel.stopped_by == "controller" and console.bonus_pick_panel.timeout_label.text == "Pick a bonus", "1.0.5: using the controller stops the countdown")
	tap(JOY_BUTTON_B)
	check(console.bonus_pick_open, "B does not dismiss the bonus pick")
	pad._after_context_change()
	check(pad.current_target() == console.bonus_pick_panel.cards[0] and console.bonus_pick_panel.highlighted == 0, "Highlight starts on the current bonus card")
	tap(JOY_BUTTON_DPAD_RIGHT)
	check(pad.target == console.bonus_pick_panel.cards[1] and console.bonus_pick_panel.highlighted == 1, "Right moves to the other card")
	tap(JOY_BUTTON_A)
	check(not console.bonus_pick_open and count("launch") == launches, "A takes the highlighted choice and launches nothing")
	console.open_bonus_pick("rapid", "double", false)
	pad._after_context_change()
	tap(JOY_BUTTON_A)
	check(not console.bonus_pick_open, "A on the current card keeps the bonus")
	await frames(1)

func _battle_highlight() -> void:
	all_enabled()
	pad.hide_battle_highlight()
	var ship: Control = console.get_node("ShipStatus")
	# Make the special weapon show (it appears only when ready).
	ship.set_process(false)
	ship.stealth_button.visible = true
	await frames(1)
	tap(JOY_BUTTON_DPAD_LEFT)
	check(pad.battle_highlight_visible and pad.target == console.launch_button, "First D-pad press shows the battle highlight on Launch Interceptors")
	var reached := {}
	for dir in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP]:
		tap(dir)
		reached[pad.target] = true
	var bottom := [console.repair_button, console.jump_button, console.prox_button, console.firewall_button, console.launch_button, console.gunship_button]
	var bottom_ok := true
	for b in bottom:
		if not reached.has(b):
			bottom_ok = false
	check(bottom_ok, "Battle highlight reaches all six bottom buttons")
	# Every target is reachable from every other by some path (graph check).
	var options: Array = pad.targets()
	var unreachable := []
	for start in options:
		var seen := {start: true}
		var queue := [start]
		while not queue.is_empty():
			var at: Control = queue.pop_front()
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var next: Control = pad.neighbour(at, d)
				if next != null and not seen.has(next):
					seen[next] = true
					queue.append(next)
		if seen.size() != options.size():
			unreachable.append(start.name)
	check(unreachable.is_empty(), "Every battle target can reach every other with the D-pad (%d targets) %s" % [options.size(), str(unreachable)])
	check(ship.stealth_button in options, "Special weapon (center) is a battle target")
	check(console.gear_button in options, "Settings gear is a battle target")
	var emp_visible: bool = is_instance_valid(console.emp_split_button) and console.emp_split_button.is_visible_in_tree()
	check(not emp_visible or console.emp_split_button in options, "EMP split button is a target whenever it shows")
	# A on the special weapon goes through its normal eligibility.
	var stealth_presses := [0]
	ship.stealth_button.pressed.connect(func() -> void: stealth_presses[0] += 1)
	pad.target = ship.stealth_button
	var was_disabled: bool = ship.stealth_button.disabled
	ship.stealth_button.disabled = true
	tap(JOY_BUTTON_A)
	check(stealth_presses[0] == 0, "Greyed-out special weapon is not fired by A")
	ship.stealth_button.disabled = false
	pad.target = ship.stealth_button
	tap(JOY_BUTTON_A)
	check(stealth_presses[0] == 1, "A fires the highlighted special weapon through its own button")
	ship.stealth_button.disabled = was_disabled
	# EMP split (make it show for the check).
	if is_instance_valid(console.emp_split_button):
		var emp_presses := [0]
		console.emp_split_button.pressed.connect(func() -> void: emp_presses[0] += 1)
		var vis: bool = console.emp_split_button.visible
		var dis: bool = console.emp_split_button.disabled
		console.emp_split_button.visible = true
		console.emp_split_button.disabled = false
		await frames(1)
		check(console.emp_split_button in pad.targets(), "EMP split joins the highlight when shown")
		pad.target = console.emp_split_button
		pad.battle_highlight_visible = true
		tap(JOY_BUTTON_A)
		check(emp_presses[0] == 1, "A presses the highlighted EMP button")
		console.emp_split_button.visible = vis
		console.emp_split_button.disabled = dis
	# A on highlighted Jump still needs the one-second hold.
	var j := count("jump")
	pad.battle_highlight_visible = true
	pad.target = console.jump_button
	button(JOY_BUTTON_A, true)
	step(0.3)
	check(count("jump") == j, "A on highlighted Jump does not jump at once")
	step(0.8)
	button(JOY_BUTTON_A, false)
	check(count("jump") == j + 1, "A on highlighted Jump held for one second jumps")
	pad.battle_highlight_visible = true
	pad.target = console.jump_button
	button(JOY_BUTTON_A, true)
	step(0.4)
	button(JOY_BUTTON_A, false)
	step(1.0)
	check(count("jump") == j + 1, "A released early on highlighted Jump: no Jump")
	# A on the gear opens Settings (battle pauses).
	pad.battle_highlight_visible = true
	pad.battle_highlight_idle = 0.0
	pad.target = console.gear_button
	tap(JOY_BUTTON_A)
	check(console.settings_open, "A on the highlighted gear opens Settings")
	console.close_settings()
	# Idle hides; A launches again.
	pad.battle_highlight_visible = true
	pad.battle_highlight_idle = 0.0
	pad.target = console.gunship_button
	step(6.2)
	check(not pad.battle_highlight_visible, "Battle highlight hides after 6 seconds without a direction")
	var l := count("launch")
	var g := count("gunship")
	tap(JOY_BUTTON_A)
	check(count("launch") == l + 1 and count("gunship") == g, "After it hides, A is Launch Interceptors again")
	# Mouse click hides it.
	tap(JOY_BUTTON_DPAD_UP)
	check(pad.battle_highlight_visible, "Direction shows the highlight again")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(5, 5)
	root.push_input(click)
	var release := click.duplicate()
	release.pressed = false
	root.push_input(release)
	check(not pad.battle_highlight_visible, "A mouse click hides the battle highlight")
	# Draws without errors with the highlight on the special weapon.
	pad.battle_highlight_visible = true
	pad.battle_highlight_idle = 0.0
	pad.target = ship.stealth_button
	pad.overlay.queue_redraw()
	await frames(2)
	await RenderingServer.frame_post_draw
	check(pad.highlight_shown(), "Special weapon highlight drawn")
	pad.hide_battle_highlight()
	ship.set_process(true)
	await frames(1)

func _game_over() -> void:
	console.set_process(true)
	all_enabled()
	c.score = 900
	c.apply_damage(100000.0)
	console._process(0.016)
	# 1.0.8: the score screen comes in front 3 s after the ship is destroyed (SYSTEMS OFFLINE first).
	console.damage_effects.skip_to_score_screen()
	console._process(0.016)
	await frames(2)
	console.set_process(false)
	check(console.game_over_panel.visible and console.entry_active and pad.context() == "initials", "Game over with a high score asks for initials")
	var first: String = console.entry_initials()
	tap(JOY_BUTTON_DPAD_UP)
	var after_up: String = console.entry_initials()
	check(after_up != first and after_up.substr(1) == first.substr(1), "D-pad up changes the first letter")
	tap(JOY_BUTTON_DPAD_DOWN)
	check(console.entry_initials() == first, "D-pad down changes it back")
	tap(JOY_BUTTON_DPAD_RIGHT)
	check(console.entry_slot == 1, "Right moves to the second letter")
	tap(JOY_BUTTON_DPAD_UP)
	check(console.entry_initials()[1] != first[1], "Up changes the second letter")
	tap(JOY_BUTTON_DPAD_LEFT)
	check(console.entry_slot == 0, "Left moves back")
	var l := count("launch")
	tap(JOY_BUTTON_A)
	check(not console.entry_active and pad.context() == "game_over", "A saves the initials")
	check(count("launch") == l, "A at game over launches nothing")
	pad._after_context_change()
	check(pad.current_target() == console.restart_button or pad.current_target() == console.game_over_quit_button, "Highlight is on RETRY or QUIT")
	pad.target = console.restart_button
	tap(JOY_BUTTON_DPAD_RIGHT)
	var moved_to: Control = pad.target
	check(moved_to == console.game_over_quit_button or moved_to == console.restart_button, "D-pad moves between RETRY and QUIT")
	pad.target = console.game_over_quit_button
	tap(JOY_BUTTON_A)
	check(console.game_over_panel.visible, "QUIT test mode does not close the game")
	pad.target = console.restart_button
	tap(JOY_BUTTON_A)
	console.set_process(true)
	console._process(0.016)
	console.set_process(false)
	check(not console.game_over_panel.visible and pad.context() == "battle", "A on RETRY starts a new battle")
	c.set_process(false)
	await frames(1)

func _hotplug() -> void:
	pad._on_joy_connection_changed(3, true)
	check(pad.connection_events[-1].begins_with("controller connected"), "Connecting a controller is noted in the session log")
	pad._on_joy_connection_changed(3, false)
	check(pad.connection_events[-1] == "controller disconnected", "Disconnecting is noted")
	console.open_settings()
	console.open_controller_panel()
	pad._on_joy_connection_changed(4, false)
	check(panel.visible and panel.status_label.text.contains("NO CONTROLLER FOUND"), "Status line refreshes when a controller goes away")
	console.close_settings()
	# Long names are cut.
	check(ControllerInput.is_playstation_name("DualSense Wireless Controller") and ControllerInput.is_playstation_name("PS4 Controller") and not ControllerInput.is_playstation_name("Xbox Series X Controller"), "PlayStation controllers recognised by name")
	# Mouse/keyboard still drive the buttons with no controller.
	var l := count("launch")
	all_enabled()
	console.launch_button.pressed.emit()
	check(count("launch") == l + 1, "Mouse/touch path unchanged")
	await frames(1)

func _session_log() -> void:
	var log: Node = console.session_log
	check(log != null and log.has_method("count_controller_press"), "Session log counts controller presses")
	if log != null:
		var line: String = log.heartbeat_text() if log.has_method("heartbeat_text") else ""
		if line == "":
			check(int(log.get("_pads")) > 0, "Controller presses were counted")
		else:
			check(line.contains("controller "), "Heartbeat line includes the controller count")
