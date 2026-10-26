extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.05: Defense Shield kill points, ship missiles that
## target nukes past halfway, the Double Missile bonus (chime, status and the
## label under SCORE), diagnostic session logging with the freeze watcher and
## OPEN LOG FOLDER, the version label in Settings and the shorter DEFAULTS button.
const GameSettings = preload("res://scripts/GameSettings.gd")
const BattleAudio = preload("res://scripts/BattleAudio.gd")
const SessionLog = preload("res://scripts/SessionLog.gd")
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
func clean(level: int = 1) -> void:
	c.difficulty = level
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
	c.auto_rapid_repair = false
	c.reset_battle()
func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
		b.drone_timer = 999.0
		b.missile_timer = 999.0
		b.heavy_timer = 999.0
	return b
func near(a: float, b: float, tolerance := 0.002) -> bool:
	return absf(a - b) <= tolerance
func rect_of(control: Control) -> Rect2:
	return Rect2(control.position, control.size)
func text_rect(label: Label) -> Rect2:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := label.position.x
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = label.position.x + label.size.x - width
	return Rect2(Vector2(x, label.position.y), Vector2(width, font.get_height(font_size)))
func peak(stream: AudioStreamWAV, from_s := 0.0, to_s := 99.0) -> float:
	var top := 0
	var start := int(from_s * stream.mix_rate) * 2
	var stop := mini(stream.data.size(), int(to_s * stream.mix_rate) * 2)
	for i in range(start, stop, 2):
		top = maxi(top, absi(stream.data.decode_s16(i)))
	return top / 32767.0
## Rising-edge zero crossings per second in a window: a rough pitch measure.
func pitch(stream: AudioStreamWAV, from_s: float, to_s: float) -> float:
	var crossings := 0
	var previous := 0
	for i in range(int(from_s * stream.mix_rate), int(to_s * stream.mix_rate)):
		var v := stream.data.decode_s16(i * 2)
		if previous < 0 and v >= 0:
			crossings += 1
		previous = v
	return crossings / (to_s - from_s)
## A missile the battery is certain to hit inside the kill zone.
func battery_kill(b: Dictionary) -> bool:
	var m: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	if m.is_empty():
		return false
	m.position = c.own_ship_position + Vector3(0.0, 0.1, 0.0)
	m.next_battery_shot = 0.0
	var kills: int = c.prox_kills
	var saved_chance: float = c.prox_success_chance
	c.prox_success_chance = 0.95
	c.prox_active = true
	var guard := 0
	while c.prox_kills == kills and guard < 200:
		m.next_battery_shot = 0.0
		c._resolve_missiles()
		guard += 1
	c.prox_active = false
	c.prox_success_chance = saved_chance
	return c.prox_kills > kills
## A nuke from a Enemy Carrier, placed at the given share of its flight to the ship.
func nuke_at(b: Dictionary, progress: float) -> Dictionary:
	b.nuclear_launched = false
	var n: Dictionary = c.find_contact(c._launch_nuclear(b))
	if n.is_empty():
		return n
	var start: Vector3 = n.position
	n.position = start.lerp(c.own_ship_position, progress)
	return n
func ship_missiles_at(id: String) -> int:
	return c._missiles_at(id)
func fire_volley() -> void:
	c.own_fire_remaining = 0.0
	c._update_own_weapons(0.0)
## Flies every ship missile until none is left (each frame 1/60 s).
func fly_missiles(max_frames := 900) -> void:
	for frame in range(max_frames):
		if c.count_kind("own_missile") == 0:
			return
		c.own_fire_remaining = 99.0
		c._update_own_weapons(1.0 / 60.0)
func file_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://v105_test_settings.cfg"
	console.high_score_file = "user://v105_test_scores.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	if FileAccess.file_exists(console.settings_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(console.settings_file))
	c = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	# 1.2.1: this test checks the 1.2.0 combat rules, so it uses the 1.2.0 combat values
	# (test_v121_features checks the new 1.2.1 defaults).
	# 1.2.2: Nuclear Speed and Gunship Nuke Hit Interval are pinned to their 1.2.1 values too.
	for classic in [["carrier_hits_to_destroy", 6], ["breacher_hit_points", 3], ["nuclear_hit_points", 3],
			["nuclear_speed", 0.055], ["gunship_nuke_hit_interval", 0.6],
			["drone_interceptor_hits", 1], ["ship_nuke_target_fraction", 0.5], ["ship_missile_heavy_range", 0.3],
			["own_missile_interval", 6.0], ["heavy_launch_interval", 22.0]]:
		c.set(classic[0], classic[1])
	c.auto_spawn = false
	c.random_seed = 1005
	root.add_child(console)
	c.set_process(false)
	console.get_node("TuningPanel").visible = false
	clean()

	# --- 6. Version from the project setting ---
	# 1.06: full builds; Test Build is off by default and the number is 1.06.
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 1.08")
	check(not console.test_build and console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.1", "Version text reads STELLAR DEFENSE CONSOLE 1.1.1")
	console.test_build = true
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.1 TEST", "With Test Build it reads STELLAR DEFENSE CONSOLE 1.1.1 TEST")
	console.test_build = false
	check(int(ProjectSettings.get_setting("debug/file_logging/max_log_files", 0)) == 10, "Godot keeps its last 10 log files (was 5)")

	# --- 1. Points for Defense Shield kills ---
	check(c.battery_kill_points == 10, "Battery kill points default to 10")
	var b := base()
	var before: int = c.score
	check(battery_kill(b) and c.score - before == 10 and c.earned_points == 10 and c.battery_kill_score == 10, "Normal: each battery kill scores 10 points and counts as earned")
	clean(2)
	b = base()
	check(battery_kill(b) and c.score == 15, "Hard: a battery kill scores 15 (x1.5 multiplier)")
	clean(0)
	b = base()
	check(battery_kill(b) and c.score == 8, "Easy: a battery kill scores 8 (x0.75, rounded)")
	clean(1)
	c.auto_defense_battery = true
	c.auto_firewall = true
	b = base()
	check(battery_kill(b) and c.score == 8, "Two auto options (-20%) also reduce battery points: 8")
	clean(1)
	b = base()
	c.earned_points = 9995
	c.score = 9995
	var charges: int = c.repair_charges
	battery_kill(b)
	check(c.earned_points == 10005 and c.repair_charges == charges + 1, "Battery points count toward the bonus rapid repair at 10,000")
	var frame_source := FileAccess.get_file_as_string("res://scripts/ConsoleFrame.gd")
	check(frame_source.contains("\"MISSILE\"") and frame_source.contains("battle.points_for(battle.battery_kill_points)"), "TARGET VALUES lists MISSILE with its multiplied value")

	# --- 2. Ship missiles target nukes past 50% ---
	clean(1)
	c.own_weapons_enabled = true
	c.double_missile_bonus = false
	check(c.ship_missiles_target_nukes and near(c.ship_nuke_target_fraction, 0.5), "Nuke targeting is on, at 50% of the flight")
	b = base()
	var n := nuke_at(b, 0.4)
	fire_volley()
	check(ship_missiles_at(n.id) == 0 and ship_missiles_at(b.id) == 1, "A nuke at 40% is not targeted; the missile goes to the Enemy Carrier")
	clean(1)
	c.own_weapons_enabled = true
	c.double_missile_bonus = false
	c.breachers_enabled = true
	b = base()
	n = nuke_at(b, 0.6)
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	if not h.is_empty():
		h.position = c.own_ship_position + Vector3(0.1, 0.15, 0.0)
	check(not h.is_empty() and h.position.distance_to(c.own_ship_position) <= c.ship_missile_heavy_range, "Setup: a Breacher is inside the close range")
	fire_volley()
	check(ship_missiles_at(n.id) == 1 and ship_missiles_at(h.id) == 0, "A nuke past 50% comes first, ahead of the close Breacher")
	c.breachers_enabled = false
	# Each ship missile is one nuke hit; Easy 2, Normal 3, Hard 4.
	for level in [0, 1, 2]:
		clean(level)
		c.own_weapons_enabled = true
		c.double_missile_bonus = false
		c.max_own_missiles = 8
		b = base()
		n = nuke_at(b, 0.7)
		var needed: int = c.scaled_hits(c.nuclear_hit_points)
		var volleys := 0
		var points_before: int = c.score
		while not c.find_contact(n.id).is_empty() and volleys < 10:
			fire_volley()
			fly_missiles()
			volleys += 1
		check(c.find_contact(n.id).is_empty() and c.ship_nuke_hits == needed and volleys == needed and c.ship_nuke_kills == 1 and c.nuclear_intercepts == 1,
			"%s: ship missiles destroy a nuke in %d hits, one per missile" % [["Easy", "Normal", "Hard"][level], needed])
		check(c.score - points_before == c.points_for(c.nuclear_points), "%s: a nuke destroyed by ship missiles scores like a Gunship kill" % ["Easy", "Normal", "Hard"][level])
	check([2, 3, 4] == [roundi(3 * c.easy_toughness), 3, roundi(3 * c.hard_toughness)], "Nuke hits by level are 2 / 3 / 4")
	# No over-commitment: never more missiles than hits left.
	clean(1)
	c.own_weapons_enabled = true
	c.double_missile_bonus = true
	c.double_missile_unlocked_at = 0.0
	c.max_own_missiles = 8
	b = base()
	n = nuke_at(b, 0.6)
	n.nuke_hits = 1
	n.nuke_max_hits = 3
	fire_volley()
	check(ship_missiles_at(n.id) == 1 and ship_missiles_at(b.id) == 1, "Nuke with 1 hit left: one missile at it, the second of the volley goes to the Enemy Carrier")
	fire_volley()
	check(ship_missiles_at(n.id) == 1, "No extra missiles while enough are already in flight")
	clean(1)
	c.own_weapons_enabled = true
	c.ship_missiles_target_nukes = false
	b = base()
	n = nuke_at(b, 0.8)
	fire_volley()
	check(ship_missiles_at(n.id) == 0, "Switching nuke targeting off in the Inspector restores the old targets")
	c.ship_missiles_target_nukes = true
	c.max_own_missiles = 4

	# --- 3. Double Missile bonus ---
	check(c.double_missile_bonus and c.easy_double_missile_points == 15000 and c.normal_double_missile_points == 17500 and c.hard_double_missile_points == 20000, "Bonus thresholds 15,000 / 17,500 / 20,000")
	for level in [0, 1, 2]:
		clean(level)
		check(c.double_missile_threshold() == [15000, 17500, 20000][level], "%s threshold is %d" % [["Easy", "Normal", "Hard"][level], [15000, 17500, 20000][level]])
	clean(1)
	c.own_weapons_enabled = true
	b = base()
	c.earned_points = 17400
	c.score = 17400
	check(not c.double_missile_active() and c.missiles_per_volley() == 1 and c.active_bonus_names().is_empty(), "Below the threshold: one missile per volley, no bonus line")
	c._add_points(99)
	check(not c.double_missile_active(), "17,499 earned: still locked")
	c._add_points(1)
	check(c.double_missile_active() and c.bonus_chimes == 1 and c.status_message == "DOUBLE MISSILE BONUS ACTIVE", "17,500 earned: bonus unlocks with the chime and the status message")
	check(c.bonus_chime_player.playing or c.bonus_chime_player.stream != null, "Chime player started")
	c._add_points(5000)
	check(c.bonus_chimes == 1, "The chime plays once per battle")
	check(c.active_bonus_names() == ["DOUBLE MISSILE BONUS"], "Bonus line DOUBLE MISSILE BONUS is shown while active")
	fire_volley()
	check(c.count_kind("own_missile") == 2, "Bonus active: two ship missiles per volley")
	await process_frame
	check(c.status_message == "DOUBLE MISSILE BONUS ACTIVE", "Status message is shown again after the frame (not hidden by the kill message)")
	c.score = 20000
	c.jump_recharge_remaining = 0.0
	c.request_jump()
	check(c.double_missile_active() and c.earned_points >= 17500, "An JUMP jump cost does not take the bonus away")
	c.reset_battle()
	check(not c.double_missile_active() and c.active_bonus_names().is_empty() and c.bonus_chimes == 0, "Retry / new battle clears the bonus and its line")
	c.double_missile_bonus = false
	c.earned_points = 30000
	c._add_points(10)
	check(not c.double_missile_active(), "The bonus can be switched off in the Inspector")
	c.double_missile_bonus = true
	# Chime sound
	var chime := BattleAudio.make_bonus_chime()
	var seconds := chime.data.size() / 96000.0
	check(near(seconds, 1.0, 0.01) and chime.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Chime is about 1 second and does not loop")
	check(peak(chime) <= 0.81 and peak(chime) > 0.25, "Chime stays below clipping")
	var low_pitch := pitch(chime, 0.02, 0.28)
	var high_pitch := pitch(chime, 0.45, 0.85)
	check(high_pitch > low_pitch * 1.3, "Chime rises: second tone higher (%.0f Hz to %.0f Hz)" % [low_pitch, high_pitch])
	check(c.bonus_chime_player.bus == "Effects", "Chime follows the Effects volume and mute")
	check(c.bonus_chime_volume_db < c.klaxon_volume_db and c.bonus_chime_volume_db < c.nuclear_alert_volume_db and c.bonus_chime_volume_db < c.siege_alert_volume_db, "Chime sits below the alert levels")
	# Label position: under SCORE, above TARGET VALUES, steady.
	c.double_missile_unlocked_at = 1.0
	var frame: Control = console.get_node("ConsoleFrame")
	var spots: Array[Vector2] = frame.bonus_line_positions()
	var score_label: Label = console.get_node("ScoreValue")
	var font := ThemeDB.fallback_font
	var width := font.get_string_size("DOUBLE MISSILE BONUS", HORIZONTAL_ALIGNMENT_LEFT, -1, frame.BONUS_FONT_SIZE).x
	var top := spots[0].y - font.get_ascent(frame.BONUS_FONT_SIZE)
	check(spots.size() == 1 and top > 124.0 and spots[0].y + font.get_descent(frame.BONUS_FONT_SIZE) < 208.0 - font.get_ascent(19), "Bonus line sits between the SCORE box and TARGET VALUES")
	check(near(spots[0].x + width, frame.size.x - 82.0, 1.0) and spots[0].x > frame.size.x * 0.5 + 492.0, "Bonus line is right-aligned with SCORE and clear of the scope")
	check(frame.BONUS_FONT_SIZE <= 18 and frame.BONUS_LINE_STEP * 2.0 + top < 208.0 - font.get_ascent(19), "Small text, with room for a second bonus line")
	var bonus_code := frame_source.substr(frame_source.find("func bonus_line_positions"), 900)
	check(bonus_code.find("battle_time") == -1 and bonus_code.find("blink") == -1, "Bonus line does not flash (no timing in its drawing code)")
	c.double_missile_unlocked_at = -1.0
	check(frame.bonus_line_positions().is_empty(), "No bonus line while no bonus is active")

	# --- 4. Hard nuke speed unchanged (review only) ---
	check(near(c.hard_nuke_speed, 1.45) and near(c.normal_nuke_speed, 1.25) and near(c.easy_nuke_speed, 1.1), "Nuke speeds (1.2.7): Easy 1.1, Normal 1.25, Hard 1.45")

	# --- 5. Diagnostic session log ---
	var log: Node = console.session_log
	check(is_instance_valid(log) and log.enabled and FileAccess.file_exists(log.file_path), "A session log file is created at start")
	check(log.file_path.begins_with("user://logs/radar_session_") and log.file_path.ends_with(".log"), "File is user://logs/radar_session_<timestamp>.log")
	var text := file_text(log.file_path)
	check(text.contains("START") and text.contains("STELLAR DEFENSE CONSOLE 1.1.1") and text.contains("Godot ") and text.contains("CPU ") and text.contains("screen "), "Start-up line: version, Godot, system, CPU and screen")
	check(text.contains("graphics driver ") and text.contains("GPU ") and text.contains("difficulty NORMAL") and text.contains("auto options") and text.contains("effects ") and text.contains("radar "), "Start-up line: graphics driver and GPU, difficulty, autos and volumes")
	var lines_before: int = log.lines_written
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	log._input(click)
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	log._input(tap)
	log._next_heartbeat_msec = 0
	log._process(0.25)
	text = file_text(log.file_path)
	check(log.lines_written == lines_before + 1 and text.contains("HEARTBEAT") and text.contains("fps ") and text.contains("slowest frame 250 ms") and text.contains("input clicks 1, taps 1"), "Heartbeat line: FPS, slowest frame and clicks and taps since the last one")
	check(text.contains("paused ") and text.contains("settings closed") and text.contains("contacts "), "Heartbeat line: paused, Settings and contact count")
	check(near(log.heartbeat_seconds, 10.0) and near(log.stall_seconds, 2.0) and log.keep_files == 10 and log.max_file_bytes == 1000000, "Heartbeat every 10 s, STALL at 2 s, 10 files of about 1 MB")
	console.open_settings()
	console.settings_panel.difficulty_buttons[2].pressed.emit()
	console.close_settings()
	c.wave_changed.emit(3)
	c.jump_completed.emit()
	c.hull = 0.0
	console.begin_game_over()
	console._on_restart_pressed()
	console.quit_game()
	text = file_text(log.file_path)
	for word in ["settings opened", "difficulty HARD", "settings closed", "wave 3", "JUMP jump", "game over", "retry", "quit"]:
		check(text.contains("EVENT") and text.contains(word), "Event logged: %s" % word)
	console.open_settings()
	console.settings_panel.difficulty_buttons[1].pressed.emit()
	console.close_settings()
	# Freeze watcher: block the main thread for 2.6 s, so no frame is drawn.
	await process_frame
	await RenderingServer.frame_post_draw
	OS.delay_msec(2600)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	text = file_text(log.file_path)
	check(log.stalls_logged == 1 and text.contains("STALL") and text.contains("no frame drawn for"), "Freeze watcher logs a STALL after 2 s without a frame")
	check(text.contains("RECOVERED") and text.contains("frames resumed after"), "Freeze watcher logs the recovery")
	check(text.find("STALL") < text.find("RECOVERED"), "STALL comes before RECOVERED")
	# Every line reaches the disk at once (read back while the game still runs).
	log.event("flush check")
	check(file_text(log.file_path).contains("flush check"), "Each line is flushed to disk straight away")
	# Errors: copied on Godot 4.5 and newer; 4.4 notes it and keeps running.
	if ClassDB.class_exists("Logger"):
		push_warning("LOG v105 warning copy check")
		await process_frame
		check(file_text(log.file_path).contains("v105 warning copy check"), "Godot 4.5+: script warnings are copied into the session log")
	else:
		check(file_text(log.file_path).contains("script error copying needs Godot 4.5"), "Godot 4.4: no Logger API; the log notes it and the game still runs")
	# No personal data: no home or app-data folder paths.
	var home := OS.get_environment("HOME")
	var user_dir := OS.get_user_data_dir()
	text = file_text(log.file_path)
	check((home.length() < 4 or not text.contains(home)) and not text.contains(user_dir), "Log holds no folder paths (no personal data)")
	check(not text.contains("ERROR:"), "Log lines never use the error prefix the test gate looks for")
	# Housekeeping: oldest files removed so 10 remain; size cap.
	var folder := "user://v105_log_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var helper := DirAccess.open(folder)
	for name in helper.get_files():
		helper.remove(name)
	for i in range(12):
		var f := FileAccess.open("%s/radar_session_2000-01-01_00-00-%02d.log" % [folder, i], FileAccess.WRITE)
		f.store_line("old")
		f.close()
	var extra: Node = SessionLog.new()
	extra.log_folder = folder
	extra.max_file_bytes = 2000
	root.add_child(extra)
	extra.start(console)
	var files: PackedStringArray = extra.session_files()
	check(files.size() == 10 and not files.has("radar_session_2000-01-01_00-00-00.log") and files.has(extra.file_path.get_file()), "Only the last 10 session files are kept (oldest deleted)")
	for i in range(200):
		extra.write("TEST", "line %d of the size check" % i)
	var size := FileAccess.open(extra.file_path, FileAccess.READ).get_length()
	check(extra.limit_reached and size <= 2000 and file_text(extra.file_path).contains("file size limit reached"), "Each file stops at its size limit (%d bytes)" % size)
	extra.stop("test")
	extra.free()
	helper = DirAccess.open(folder)
	for name in helper.get_files():
		helper.remove(name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	var off: Node = SessionLog.new()
	off.enabled = false
	root.add_child(off)
	off.start(console)
	check(off.file_path == "" and off._thread == null, "Logging can be switched off in the Inspector")
	off.free()

	# --- 6 and 7. Settings panel: OPEN LOG FOLDER, version label, DEFAULTS ---
	console.open_settings()
	var panel = console.settings_panel
	# 1.1.1: DATA FOLDER on the ABOUT tab opens the log folder; the version is on the ABOUT tab.
	panel.data_button.pressed.emit()
	check(console.log_folder_opens == 1 and DirAccess.dir_exists_absolute(log.folder_path()), "DATA FOLDER opens the log folder (dry run in tests)")
	check(FileAccess.get_file_as_string("res://scripts/RadarConsole.gd").contains("OS.shell_open(path)"), "The log folder opens in the system file browser (OS.shell_open)")
	check(panel.about_version.text == "VERSION 1.1.1", "ABOUT tab shows VERSION 1.1.1")
	check(panel.about_build.get_theme_font_size("font_size") <= 18, "Build line is small")
	check(panel.reset_button.text == "DEFAULTS" and panel.reset_button.size == panel.remember_button.size and panel.reset_button.size == panel.auto_jump_button.size, "RESET TO DEFAULTS is now DEFAULTS, sized like the switch buttons")
	check(panel.reset_button.position.y == panel.remember_button.position.y, "DEFAULTS stays on the REMEMBER SETTINGS row")
	panel.auto_battery_button.button_pressed = true
	panel.remember_button.button_pressed = false
	panel.effects_slider.value = 25
	panel.reset_button.pressed.emit()
	check(panel.reset_button.text == "CONFIRM" and console.settings.auto_battery and console.settings.effects_volume == 25, "First press shows CONFIRM and changes nothing")
	panel.reset_button.pressed.emit()
	check(panel.reset_button.text == "DEFAULTS" and not console.settings.auto_battery and console.settings.effects_volume == 50 and not console.settings.remember_settings, "Second press resets everything except REMEMBER SETTINGS")
	panel.reset_button.pressed.emit()
	check(panel.reset_button.text == "CONFIRM", "Pressed again: CONFIRM")
	await create_timer(3.3).timeout
	check(panel.reset_button.text == "DEFAULTS", "CONFIRM lapses after 3 seconds")
	panel.remember_button.button_pressed = true
	# Layout: nothing overlaps, panel fits the 1080-pixel layout.
	var buttons: Array[Button] = []
	var labels: Array[Label] = []
	for child in panel.panel.get_children():
		if child is Button and child.visible:
			buttons.append(child)
		elif child is Label:
			labels.append(child)
	var overlaps := 0
	for i in range(buttons.size()):
		for j in range(i + 1, buttons.size()):
			if rect_of(buttons[i]).intersects(rect_of(buttons[j])):
				overlaps += 1
	for label in labels:
		if label.text == "" or not label.visible:
			continue
		for button in buttons:
			if text_rect(label).intersects(rect_of(button)):
				overlaps += 1
	var inside := true
	for button in buttons:
		inside = inside and Rect2(Vector2.ZERO, panel.PANEL_SIZE).encloses(rect_of(button))
	check(overlaps == 0, "Settings panel: no overlapping buttons or text (%d buttons)" % buttons.size())
	check(inside and panel.PANEL_SIZE.y <= 1060.0 and panel.panel.position.y >= 0.0, "Settings panel fits the 1080-pixel layout (%d px tall)" % int(panel.PANEL_SIZE.y))
	console.close_settings()

	# --- Preserved ---
	check(not console.development_build and near(console.sweep_volume_db, -20.0), "Development Build off by default; sweep still -20 dB")

	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("V105_RESULT checks=%d failures=%d" % [checks, failures])
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
