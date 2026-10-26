extends SceneTree
## 1.1.1 in-game captures of each change. CAP_DIR = output folder, CAP_W / CAP_H = window.
## Run with a display (for example xvfb-run with a screen larger than the window).
## The update screens use a made-up 1.1.2 release (nothing goes online here; the real
## end-to-end run is verification/e2e_update_linux.py).
const UC := preload("res://scripts/UpdateCore.gd")
var console: Control
var c: Control
var dir := ""
var tag := ""
var work := ""

func _initialize() -> void:
	call_deferred("_run")

func frames(n: int = 4) -> void:
	for i in range(n):
		await process_frame

func save(name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [dir, name, tag])
	print("saved ", name, " ", img.get_size())

func fresh(force_startup := false) -> void:
	if console != null:
		console.queue_free()
		await frames(2)
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://cap111_%s.cfg" % tag
	console.high_score_file = "user://cap111_%s.json" % tag
	console.quit_dry_run = true
	console.shell_dry_run = true
	console.startup_force = force_startup
	if force_startup:
		console.startup_splash_seconds = 3.0
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	c.auto_spawn = false
	root.add_child(console)
	var u: Node = console.updater
	u.work_dir = work.path_join("updates")
	u.backup_dir = work.path_join("backup")
	u.state_file = work.path_join("updates/update_state.cfg")
	u.platform_override = "Windows_x64"
	u.api_url = "http://127.0.0.1:9/api/latest"
	if force_startup and OS.get_environment("CAP_API") != "":
		u.api_url = OS.get_environment("CAP_API")  # slow stand-in, so the hold is real
	DirAccess.make_dir_recursive_absolute(u.work_dir)
	u.load_state()
	await frames(3)
	DisplayServer.window_set_size(Vector2i(int(OS.get_environment("CAP_W")), int(OS.get_environment("CAP_H"))))
	await frames(2)
	c.rng.seed = 111
	c.reset_battle()

func release() -> Dictionary:
	return {"ok": true, "newer": true, "version": "1.1.2", "date": "2026-11-02", "size": 32505856,
		"asset_name": "Stellar_Defense_Console_1.1.2_Windows_x64.exe.zip", "asset_url": "x", "sums_url": "y",
		"notes": PackedStringArray(["Example line one for the next version", "Example line two"])}

func carrier(pos: Vector3) -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	b.position = pos
	b.drone_timer = 999.0
	b.missile_timer = 999.0
	b.heavy_timer = 999.0
	return b

func step(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		c._process(1.0 / 30.0)
		t += 1.0 / 30.0
	await frames(2)

func _run() -> void:
	dir = OS.get_environment("CAP_DIR")
	var w := int(OS.get_environment("CAP_W"))
	var h := int(OS.get_environment("CAP_H"))
	tag = "%dx%d" % [w, h]
	work = ProjectSettings.globalize_path("user://cap111_work_%s" % tag)
	OS.execute("rm", ["-rf", work])
	DisplayServer.window_set_size(Vector2i(w, h))
	await frames(4)
	# --- Settings tabs ---
	await fresh()
	var ini := ConfigFile.new()
	ini.set_value("updates", "check_at_startup", true)
	ini.set_value("updates", "last_check_unix", int(Time.get_unix_time_from_system()) - 600)
	ini.set_value("updates", "last_check_ok", true)
	ini.set_value("updates", "last_check_text", "Up to date.")
	ini.save(work.path_join("updates/update_state.cfg"))
	console.updater.load_state()
	console.open_settings()
	var p: Control = console.settings_panel
	p.show_tab(0)
	await save("01_settings_game")
	p.show_tab(1)
	await save("02_settings_system")
	p.show_tab(2)
	console.refresh_about()
	await save("03_settings_about")
	# ABOUT after an update: note, GO BACK.
	ini.set_value("updates", "note", "Updated from 1.1.0 today at 3:10 PM.")
	ini.set_value("updates", "note_version", "1.1.1")
	ini.set_value("backup", "version", "1.1.0")
	ini.set_value("backup", "item", "Stellar_Defense_Console_1.1.0_Windows_x64.exe")
	ini.save(work.path_join("updates/update_state.cfg"))
	DirAccess.make_dir_recursive_absolute(work.path_join("backup"))
	FileAccess.open(work.path_join("backup/Stellar_Defense_Console_1.1.0_Windows_x64.exe"), FileAccess.WRITE).store_string("x")
	console.updater.load_state()
	console.refresh_about()
	await save("04_settings_about_after_update_go_back")
	# GO BACK confirm (Game Over, so it is allowed).
	c.hull = 0.0
	await step(0.1)
	console._on_go_back_requested()
	await save("05_go_back_confirm")
	console.update_popup.back()
	# Mid-battle: newer version shown, UPDATE NOW greyed out.
	c.hull = c.max_hull
	await step(0.1)
	console.update_popup.show_found(release(), "1.1.1", UC.build_label("Windows_x64"), false)
	await save("06_update_found_mid_battle_greyed")
	console.update_popup.close()
	console.close_settings()
	# --- Startup ---
	await fresh(true)
	await frames(10)
	await save("07_startup_splash")
	# After the splash, the battle stays held while the check finishes (up to 3 seconds).
	while console.startup_splash.visible:
		await process_frame
	await create_timer(0.4).timeout
	print("hold during check: ", console.startup_hold, " line ", console.startup_line.visible)
	await save("08_startup_checking_for_updates")
	await create_timer(3.0).timeout
	if is_instance_valid(console.startup_splash):
		console.startup_splash.visible = false
	if is_instance_valid(console.startup_line):
		console.startup_line.visible = false
	console.update_popup.show_found(release(), "1.1.1", UC.build_label("Windows_x64"), true)
	await save("09_startup_update_found")
	console.update_popup.show_working("1.1.2", release(), "1.1.1", UC.build_label("Windows_x64"))
	console.update_popup.set_progress(12058624, 32505856)
	await save("10_downloading")
	console.update_popup.set_stage("STARTING", "1.1.2")
	await save("11_starting_new_version")
	var msgs := [["no_start", "12_new_version_did_not_start"], ["checksum", "13_download_did_not_check_out"],
		["download", "14_download_stopped"], ["protected_refused", "15_permission_not_given"],
		["mac_translocated", "16_mac_move_game_first"]]
	for m in msgs:
		var t: Dictionary = console.updater.failure_text(m[0], "1.1.2")
		console.update_popup.show_message(t.title, t.text)
		await save(m[1])
	# The game's own CHECK NOW failure path.
	console.check_now_running = true
	console._on_check_done({"ok": false, "error": "no answer"})
	await save("17_could_not_check")
	console.update_popup.close()
	# --- Stealth Interceptor: 1.1.0 values next to 1.1.1 values ---
	for cfg in ["old", "new"]:
		await stealth_scene(cfg)
	quit(0)

func stealth_scene(cfg: String) -> void:
	await fresh()
	# Only the steps below move the battle on, so the timings are exact.
	c.set_process(false)
	if console.startup_hold:
		console.release_startup_hold()
	if cfg == "old":
		c.stealth_fire_range = 0.35
		c.stealth_shot_seconds = 4.0
		c.stealth_home_turn = 1.0
	c.waves_enabled = false
	c.carrier_weapons_enabled = false
	c.siege_enabled = false
	c.max_carriers = 3
	c.safe_remaining = 0.0
	var b1 := carrier(Vector3(-0.35, 0.62, 0.0))
	var b2 := carrier(Vector3(0.05, 0.78, 0.0))
	var b3 := carrier(Vector3(0.45, 0.60, 0.0))
	c.safe_remaining = 0.0
	c.stealth_cooldown_remaining = 0.0
	c.pulse_charges = 0
	for k in [b1, b2, b3]:
		for i in 3:
			var dr: Dictionary = c.find_contact(c.spawn_from_carrier("drone", k.id))
			dr.position = k.position + Vector3(-0.12 + 0.12 * i, -0.15, 0.0)
			dr.phase = "attack"
	await step(0.2)
	print("%s launch: %s (large ships %d)" % [cfg, c.launch_stealth(false), c.large_ship_count()])
	var ship: Dictionary = {}
	for k in c.contacts:
		if k.kind == "stealth_interceptor":
			ship = k
	var label := "1.1.0" if cfg == "old" else "1.1.1"
	var t := 0.0
	var fired := 0
	var fire_t := 0.0
	while t < 40.0 and not ship.is_empty() and c.contacts.has(ship):
		c._process(1.0 / 30.0)
		t += 1.0 / 30.0
		var left := int(ship.get("nukes_left", 2))
		if 2 - left > fired:
			fired = 2 - left
			if fired == 1:
				fire_t = t
				await frames(2)
				await save("2%s_stealth_%s_first_nuke" % ["0" if cfg == "old" else "3", label])
			elif fired == 2:
				print("%s: second nuke %.2f s after the first" % [label, t - fire_t])
				await frames(2)
				await save("2%s_stealth_%s_second_nuke" % ["1" if cfg == "old" else "4", label])
				# Two seconds into the turn home.
				var tt := 0.0
				while tt < 2.0 and c.contacts.has(ship):
					c._process(1.0 / 30.0)
					tt += 1.0 / 30.0
				await save("2%s_stealth_%s_turning_home" % ["2" if cfg == "old" else "5", label])
				break
