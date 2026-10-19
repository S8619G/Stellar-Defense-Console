extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.03: slower Defense Shield recharge scaled by
## difficulty, auto launch for Interceptors and Gunships, auto JUMP below 10% hull,
## the JUMP blue-white flash, QUIT buttons, and the window sized to the screen.
const GameSettings = preload("res://scripts/GameSettings.gd")
const HighScores = preload("res://scripts/HighScores.gd")
var console: Control
var c: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)
func clean() -> void:
	c.auto_spawn = false
	c.breachers_enabled = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.nuclear_weapons_enabled = false
	c.siege_enabled = false
	c.auto_defense_battery = false
	c.auto_firewall = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.auto_jump = false
	c.reset_battle()
func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
	return b
func step(seconds: float) -> void:
	for i in range(roundi(seconds * 60.0)):
		c._process(1.0 / 60.0)
func near(a: float, b: float, tolerance := 0.02) -> bool:
	return absf(a - b) <= tolerance
func recharge_seconds(level: int) -> float:
	c.difficulty = level
	clean()
	c.prox_burst_remaining = 0.0
	c.battery_idle = 0.0
	var t := 0.0
	while c.battery_percent() < 100.0 and t < 120.0:
		c._process(1.0 / 60.0)
		t += 1.0 / 60.0
	return t
func rect_of(control: Control) -> Rect2:
	return Rect2(control.position, control.size)

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://v103_test_settings.cfg"
	console.high_score_file = "user://v103_test_scores.json"
	console.quit_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	c.auto_spawn = false
	root.add_child(console)
	c.set_process(false)
	console.set_process(false)
	await process_frame
	await process_frame
	clean()

	# --- 1. Defense Shield recharge: slower, scaled by difficulty ---
	check(c.battery_recharge_seconds == 24.0 and c.prox_burst_seconds == 6.0, "Normal recharge is 24 s (was 18 s); a full battery still fires for 6 s")
	check(c.easy_battery_recharge == 0.8 and c.hard_battery_recharge == 1.3, "Easy recharges 0.8x as long, Hard 1.3x (Inspector values)")
	var easy := recharge_seconds(0)
	var normal := recharge_seconds(1)
	var hard := recharge_seconds(2)
	print("BATTERY_RECHARGE easy=%.1f normal=%.1f hard=%.1f (includes the %.1f s pause)" % [easy, normal, hard, c.battery_recharge_delay])
	check(near(normal, 25.0, 0.1), "Normal: empty to full in 24 s after the 1 s pause")
	check(near(easy, 20.2, 0.1) and near(hard, 32.2, 0.1), "Easy 19.2 s and Hard 31.2 s after the pause")
	check(easy > 19.0 and normal > easy and hard > normal, "Every level recharges slower than 1.02's 18 s, and Hard is slowest")
	c.difficulty = 1
	c.active_difficulty = 1
	check(near(c.battery_recharge_time(), 24.0, 0.001), "Recharge follows the battle's difficulty")
	clean()
	c.prox_burst_remaining = c.prox_burst_seconds * 0.10
	check(not c.can_fire_battery(), "15% restart rule unchanged")

	# --- 2. Settings: new switches, saved, applied, score multiplier ---
	for key in ["auto_interceptors", "auto_gunships", "auto_jump"]:
		check(GameSettings.DEFAULTS.has(key) and GameSettings.DEFAULTS[key] == false, "Setting %s exists and starts OFF" % key)
	var old_file := ConfigFile.new()
	old_file.set_value("settings", "difficulty", 2)
	old_file.set_value("settings", "auto_battery", true)
	old_file.save("user://v103_old_settings.cfg")
	var loaded := GameSettings.load_settings("user://v103_old_settings.cfg")
	check(loaded.difficulty == 2 and loaded.auto_battery and not loaded.auto_interceptors and not loaded.auto_gunships and not loaded.auto_jump, "A 1.02 settings file keeps its choices; new switches start OFF")
	var all_on := loaded.duplicate()
	all_on.auto_interceptors = true
	all_on.auto_gunships = true
	all_on.auto_jump = true
	check(GameSettings.save_settings("user://v103_old_settings.cfg", all_on), "Settings with the new switches save with a verified write")
	var again := GameSettings.load_settings("user://v103_old_settings.cfg")
	check(again.auto_interceptors and again.auto_gunships and again.auto_jump and again.difficulty == 2, "New switches are remembered")
	check(GameSettings.clean({"auto_jump": "yes", "auto_interceptors": 1}).auto_jump == false and GameSettings.clean({"auto_interceptors": 1}).auto_interceptors == false, "Damaged values fall back to OFF")
	var panel = console.settings_panel
	console.open_settings()
	check(panel.visible and panel.auto_interceptors_button.text == "INTERCEPTORS OFF" and panel.auto_gunships_button.text == "GUNSHIPS OFF" and panel.auto_jump_button.text == "OFF", "Panel shows AUTO LAUNCH (Interceptors, Gunships) and AUTO JUMP, all OFF")
	panel.auto_interceptors_button.button_pressed = true
	panel.auto_gunships_button.button_pressed = true
	panel.auto_jump_button.button_pressed = true
	check(c.auto_launch_interceptors and c.auto_launch_gunships and c.auto_jump, "Turning them on reaches the game straight away")
	check(panel.auto_interceptors_button.text == "INTERCEPTORS ON" and panel.auto_jump_button.text == "ON", "Buttons read ON")
	check(GameSettings.load_settings(console.settings_file).auto_jump, "Choice saved to the settings file")
	panel.auto_battery_button.button_pressed = true
	panel.auto_firewall_button.button_pressed = true
	check(near(c.score_multiplier_for(1, 5), 0.5, 0.001) and panel.multiplier_label.text.contains("x0.50") and panel.multiplier_detail.text.contains("5 AUTO OPTIONS"), "Each auto option is -10%: all five on gives x0.50")
	# Layout: everything inside the panel, nothing overlapping, panel fits the 1920 x 1080 layout.
	check(panel.PANEL_SIZE.y <= 1000 and panel.PANEL_SIZE.x <= 1800, "Taller panel still fits the screen")
	var controls: Array = []
	for child in panel.panel.get_children():
		if child is Button or child is HSlider:
			controls.append(child)
	var inside := true
	var overlap := false
	var whole := Rect2(Vector2.ZERO, panel.PANEL_SIZE)
	for i in range(controls.size()):
		var a: Rect2 = rect_of(controls[i])
		if not whole.encloses(a):
			inside = false
		for j in range(i + 1, controls.size()):
			if a.intersects(rect_of(controls[j])):
				overlap = true
	check(inside and not overlap, "All %d buttons and sliders sit inside the panel without overlapping" % controls.size())
	check(panel.quit_button.position.y == panel.close_button.position.y and panel.quit_button.position.y == panel.new_battle_button.position.y, "QUIT sits on the bottom row with NEW BATTLE and CLOSE")
	for key in ["auto_battery", "auto_firewall", "auto_interceptors", "auto_gunships", "auto_jump"]:
		console.settings[key] = false
	console._on_settings_changed(console.settings)
	panel.open(console.settings, c.active_difficulty)
	check(not c.auto_launch_interceptors and not c.auto_jump and panel.auto_jump_button.text == "OFF", "Switching off works the same way")

	# --- 3. QUIT in Settings (asks once more) ---
	panel.quit_button.pressed.emit()
	check(console.quit_requests == 0 and panel.quit_button.text == "CONFIRM QUIT", "First QUIT press asks for confirmation and does not close")
	panel.quit_button.pressed.emit()
	check(console.quit_requests == 1 and panel.quit_button.text == "QUIT", "Second press quits")
	panel.quit_button.pressed.emit()
	check(panel.quit_armed, "Armed again for the timeout check")
	await create_timer(3.3).timeout
	check(not panel.quit_armed and panel.quit_button.text == "QUIT" and console.quit_requests == 1, "Confirmation lapses after 3 seconds without quitting")
	panel.quit_button.pressed.emit()
	console.close_settings()
	console.open_settings()
	check(not panel.quit_armed, "Reopening Settings clears a pending confirmation")
	console.close_settings()

	# --- 4. QUIT beside Retry on Game Over, keeping a high score ---
	var retry: Button = console.restart_button
	var quit: Button = console.game_over_quit_button
	check(quit != null and quit.get_parent() == console.game_over_panel and quit.text == "Quit", "Game Over panel has a Quit button")
	check(quit.position.y == retry.position.y and quit.size == retry.size and not rect_of(quit).intersects(rect_of(retry)) and quit.position.x > retry.position.x, "Quit sits beside Retry, same size, not overlapping")
	var panel_rect := Rect2(Vector2.ZERO, console.game_over_panel.size)
	check(panel_rect.encloses(rect_of(quit)) and panel_rect.encloses(rect_of(retry)), "Both buttons stay inside the Game Over panel")
	check(quit.get_signal_connection_list("pressed").size() == 1, "Quit is wired only to quitting (not a second Retry)")
	if FileAccess.file_exists(console.high_score_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(console.high_score_file))
	clean()
	c.score = 4321
	c.hull = 0.0
	console.begin_game_over()
	check(console.entry_active, "A top-10 score is waiting for initials")
	quit.pressed.emit()
	var saved := HighScores.load_board(console.high_score_file, 10)
	check(console.quit_requests == 2 and not saved.scores.is_empty() and int(saved.scores[0].score) == 4321, "Quit at Game Over saves the high score first, as Retry does")
	clean()

	# --- 5. Auto launch ---
	clean()
	c.auto_launch_interceptors = true
	step(0.2)
	var vb := base()
	step(0.2)
	check(c.count_interceptors() == 0, "No enemy fighters: no Interceptors launched")
	c.spawn_from_carrier("drone", vb.id)
	while c.enemy_fighters() == 0 and c.battle_time < 10.0:
		step(1.0 / 60.0)
	step(0.1)
	check(c.count_interceptors() == 2 and c.auto_interceptor_launches == 1, "A Attack Drone appears: Interceptors launch by themselves (2 per launch)")
	for i in range(3):
		c.spawn_from_carrier("drone", vb.id)
	step(0.5)
	print("AUTO_INTERCEPTOR_RAID fighters=", c.enemy_fighters(), " interceptors=", c.count_interceptors())
	check(c.count_interceptors() == 2, "The normal launch cooldown still applies")
	step(c.launch_cooldown_seconds + 0.2)
	check(c.count_interceptors() == 4, "After the cooldown, more Interceptors launch for the larger raid (one per fighter)")
	clean()
	c.auto_launch_interceptors = false
	var ob := base()
	c.spawn_from_carrier("drone", ob.id)
	step(1.5)
	check(c.count_interceptors() == 0, "Auto launch OFF: nothing launches by itself")
	clean()
	c.auto_launch_gunships = true
	step(0.2)
	check(c.count_kind("gunship") == 0, "No Enemy Carrier or nuke: no Gunship launched")
	var b := base()
	step(0.1)
	check(c.count_kind("gunship") == 1 and c.auto_gunship_launches == 1, "Identified Enemy Carrier: one Gunship launches")
	step(c.gunship_launch_cooldown + 0.5)
	check(c.count_kind("gunship") == 1, "Only one Gunship is kept out against Enemy Carriers")
	c.nuclear_weapons_enabled = true
	c._launch_nuclear(b)
	var b2 := base()
	c._launch_nuclear(b2)
	step(0.1)
	check(c.count_kind("gunship") == 2, "Two nukes inbound: a second Gunship launches (cooldown permitting)")
	clean()
	c.auto_launch_gunships = true
	c.request_jump()
	base()
	step(0.2)
	check(c.count_kind("gunship") == 0, "No auto launches during the post-jump safe period")
	clean()

	# --- 6. Auto JUMP below 10% hull ---
	clean()
	c.auto_jump = true
	c.score = 5000
	c.spawn_contact("unknown", "unknown")
	c.hull = c.max_hull * 0.105
	step(0.1)
	check(c.jumps_used == 0, "Hull at 10.5%: no jump")
	c.hull = c.max_hull * 0.095
	step(1.0 / 60.0)
	check(c.jumps_used == 1 and c.auto_jumps == 1 and c.score == 2000 and c.contacts.is_empty(), "Hull below 10%: JUMP engages by itself, normal cost, enemies left behind")
	check(c.status_message.contains("AUTO JUMP"), "Status line says AUTO JUMP")
	check(near(c.hull, c.max_hull * 0.095, 0.001), "Damage is retained, as with a manual jump")
	step(5.0)
	check(c.jumps_used == 1, "No repeat jump while JUMP recharges")
	step(c.jump_recharge_seconds - 6.0)
	c.hull = c.max_hull * 0.095  # slow repairs may have lifted it; still below 10%
	step(1.5)
	check(c.jumps_used == 2, "Still below 10% once JUMP is charged again: jumps again")
	clean()
	c.auto_jump = false
	c.hull = c.max_hull * 0.05
	step(0.2)
	check(c.jumps_used == 0, "Auto JUMP OFF: no jump")
	clean()
	c.auto_jump = true
	c.hull = 0.0
	step(0.2)
	check(c.jumps_used == 0, "No jump after the ship is lost")
	clean()
	c.auto_jump = true
	c.jump_recharge_remaining = 10.0
	c.hull = c.max_hull * 0.05
	step(0.2)
	check(c.jumps_used == 0, "No jump while JUMP is still charging")
	clean()

	# --- 7. JUMP flash ---
	clean()
	check(c.jump_flash_progress() < 0.0 and c.jump_screen_alpha() == 0.0, "No flash before a jump")
	c.request_jump()
	check(near(c.jump_flash_progress(), 0.0) and near(c.jump_screen_alpha(), 0.35, 0.001), "Jump starts the blue-white flash at full strength (0.35)")
	console._process(0.0)
	var flash: ColorRect = console.screen_flash
	check(flash.color.b > flash.color.r and near(flash.color.a, 0.35, 0.01), "Screen flash is blue-white during a jump (nuke flash stays warm)")
	var positions: Array = []
	var monotonic := true
	var last := -10.0
	for i in range(int(c.jump_flash_seconds * 60.0) + 2):
		var p: float = c.jump_band_position()
		if p > -2.0:
			positions.append(p)
			if p < last:
				monotonic = false
			last = p
		step(1.0 / 60.0)
	check(monotonic and positions.size() > 30 and positions[0] < -1.0 and positions[-1] > 0.9, "The band sweeps left to right across the whole scope")
	check(c.jump_flash_progress() < 0.0 and c.jump_screen_alpha() == 0.0, "Flash finished within %.1f s" % c.jump_flash_seconds)
	clean()
	c.request_jump()
	step(c.jump_flash_seconds * 0.46)
	check(c.jump_screen_alpha() == 0.0 and c.jump_flash_progress() > 0.0, "Screen flash is gone before the band finishes (single short flash, no strobe)")
	clean()
	c.jump_flash_enabled = false
	c.request_jump()
	check(c.jump_flash_progress() < 0.0, "JUMP Flash Enabled OFF: no flash")
	c.jump_flash_enabled = true
	clean()
	c.screen_flash_enabled = false
	c.request_jump()
	check(c.jump_flash_progress() >= 0.0 and c.jump_screen_alpha() == 0.0, "Screen Flash Enabled OFF: wipe only, no full-screen flash")
	c.screen_flash_enabled = true
	clean()
	c.request_jump()
	c.reset_battle()
	check(c.jump_flash_progress() < 0.0, "Retry clears the flash")
	clean()

	# --- 8. Window sized to the screen ---
	var cases := {
		Vector2i(3840, 2100): Vector2i(3173, 1785), # 4K with taskbar
		Vector2i(2560, 1400): Vector2i(2116, 1190),
		Vector2i(1920, 1040): Vector2i(1572, 884),  # same as before, within a few pixels
		Vector2i(1366, 728): Vector2i(1100, 619),   # small laptop: now fits
		Vector2i(2880, 1762): Vector2i(2448, 1377), # Retina MacBook (pixels)
	}
	var all_fit := true
	for usable in cases:
		var got: Vector2i = console.window_size_for(usable, 0.85)
		var fits: bool = got.x <= usable.x and got.y <= usable.y
		var shape: bool = absf(float(got.x) / got.y - 16.0 / 9.0) < 0.01
		if not fits or not shape or (got - cases[usable]).length() > 2.5:
			all_fit = false
			print("WINDOW_CASE usable=", usable, " got=", got, " expected=", cases[usable])
	check(all_fit, "Window size: 85% of the usable screen, 16:9, for 4K, 1440p, 1080p, laptop and Retina screens")
	print("WINDOW_SIZES 4K=%s 1440p=%s 1080p=%s laptop=%s retina=%s" % [console.window_size_for(Vector2i(3840, 2100), 0.85), console.window_size_for(Vector2i(2560, 1400), 0.85), console.window_size_for(Vector2i(1920, 1040), 0.85), console.window_size_for(Vector2i(1366, 728), 0.85), console.window_size_for(Vector2i(2880, 1762), 0.85)])
	check(console.fitted_window_size == Vector2i.ZERO and DisplayServer.window_get_size() == Vector2i(1600, 900), "Inside a test script the window is left alone (only the real game resizes)")
	var usable_now := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var fitted: Vector2i = console.fit_window()
	await process_frame
	await process_frame
	var size_now := DisplayServer.window_get_size()
	print("WINDOW_FIT usable=", usable_now.size, " fitted=", fitted, " actual=", size_now, " position=", DisplayServer.window_get_position())
	check(fitted != Vector2i.ZERO and fitted == console.window_size_for(usable_now.size, 0.85), "On this screen the window is fitted to 85% of the usable area")
	check(size_now.x <= usable_now.size.x and size_now.y <= usable_now.size.y, "The window fits on the screen")
	console.fit_window_to_screen = false
	check(console.fit_window() == Vector2i.ZERO, "Fit Window To Screen OFF keeps the project window size")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame

	# --- 9. Full battle with every auto option ---
	clean()
	c.auto_spawn = true
	c.breachers_enabled = true
	c.carrier_weapons_enabled = true
	c.own_weapons_enabled = true
	c.nuclear_weapons_enabled = true
	c.siege_enabled = true
	c.auto_defense_battery = true
	c.auto_firewall = true
	c.auto_launch_interceptors = true
	c.auto_launch_gunships = true
	c.auto_jump = true
	c.rng.seed = 1031
	c.reset_battle()
	step(600.0)
	print("AUTO_SIMULATION seconds=600 interceptor_launches=%d gunship_launches=%d auto_jump=%d jumps=%d hull=%d score=%d defeated=%s" % [c.auto_interceptor_launches, c.auto_gunship_launches, c.auto_jumps, c.jumps_used, c.hull_percent(), c.score, str(c.is_defeated())])
	check(c.auto_interceptor_launches > 0 and c.auto_gunship_launches > 0, "In a 10-minute battle the auto options launch Interceptors and Gunships")
	check(c.count_interceptors() <= c.interceptor_limit() and c.count_kind("gunship") <= c.gunship_limit(), "Limits are never exceeded")
	c.auto_spawn = false
	clean()

	print("V103_RESULT checks=", checks, " failures=", failures)
	for p in console.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	for f in ["user://v103_test_settings.cfg", "user://v103_test_scores.json", "user://v103_old_settings.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	console.free()
	await create_timer(0.3).timeout
	call_deferred("quit", 0 if failures == 0 else 1)
