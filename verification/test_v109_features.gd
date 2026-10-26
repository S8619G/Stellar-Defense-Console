extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.09: Stealth Interceptor (STEALTH WEAPON on the top nacelle),
## ANGLE on Qualcomm GPUs, no Breacher RTB tag, full difficulty names on the
## score table and window focus logging.
var console: Control
var c: Control
var ship: Control
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
	c.breachers_enabled = true
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
	c.firewall_enabled = true
	c.jump_offline_on_breach = true
	c.reset_battle()
	c.waves_enabled = false
	c.wave = 5  # room for up to four Enemy Carriers
func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
		b.drone_timer = 999.0
		b.missile_timer = 999.0
		b.heavy_timer = 999.0
	return b
func hacker(b: Dictionary) -> Dictionary:
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	if not h.is_empty():
		h.position = h.hack_point
		c._update_breachers(0.0)
	return h
func run(seconds: float, step: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		c._process(step)
		t += step
func interceptor_at(pos: Vector3) -> Dictionary:
	var v: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.position = pos
	v.phase = "intercept"
	return v
func drone_at(b: Dictionary, pos: Vector3) -> Dictionary:
	var r: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	r.position = pos
	r.phase = "attack"
	return r
func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://v109_test_settings.cfg"
	console.high_score_file = "user://v109_test_scores.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
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
	ship = console.get_node("ShipStatus")
	c.auto_spawn = false
	c.random_seed = 1009
	root.add_child(console)
	c.set_process(false)
	console.get_node("TuningPanel").visible = false
	clean()
	var events: Array[String] = []
	c.stealth_event.connect(func(m: String) -> void: events.append(m))

	# --- Full build 1.09 ---
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 1.09")
	check(not console.test_build and console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.1", "Version text reads STELLAR DEFENSE CONSOLE 1.1.1")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Mac.zip")
		and presets.get_value("preset.1.options", "application/version", "") == "1.1.1"
		and presets.get_value("preset.1.options", "binary_format/architecture", "") == "universal", "Export presets name 1.09 files; Mac stays Universal")

	# --- ANGLE on Qualcomm only ---
	check(int(presets.get_value("preset.0.options", "application/export_angle", 0)) == 1, "Windows export always includes the ANGLE files")
	var devices: Array = ProjectSettings.get_setting("rendering/gl_compatibility/force_angle_on_devices", [])
	var has_ms := false
	var has_qc := false
	for d in devices:
		if d.get("vendor", "") == "Microsoft" and d.get("name", "") == "Qualcomm":
			has_ms = true
		if d.get("vendor", "") == "Qualcomm" and d.get("name", "") == "*":
			has_qc = true
	check(has_ms and has_qc, "Qualcomm GPUs (direct and through Microsoft D3D12) are switched to ANGLE")
	check(devices.size() == 56 and devices[0].get("vendor", "") == "ATI", "Godot's own ANGLE device list is kept (54 entries plus the 2 Qualcomm ones)")
	check(not ProjectSettings.has_setting("rendering/gl_compatibility/driver.windows") or ProjectSettings.get_setting("rendering/gl_compatibility/driver.windows") == "opengl3", "Every other Windows PC keeps the native OpenGL driver")
	var field_vendor := "Microsoft"
	var field_name := "D3D12 (Qualcomm(R) Adreno(TM) X1-85 GPU)"
	var matched := false
	for d in devices:
		if field_vendor.containsn(d.vendor) and (d.name == "*" or field_name.containsn(d.name)):
			matched = true
	check(matched, "The Surface Pro GPU from the freeze logs matches the list")
	var nvidia_match := false
	for d in devices:
		if "NVIDIA Corporation".containsn(d.vendor) and (d.name == "*" or "NVIDIA GeForce RTX 3060".containsn(d.name)):
			nvidia_match = true
	check(not nvidia_match, "A typical NVIDIA PC is not switched")
	check(console.has_method("_notification") and FileAccess.get_file_as_string("res://scripts/RadarConsole.gd").contains("window lost focus"), "Window focus changes are written to the session log")

	# --- Breacher tags ---
	var hb := base()
	var hr := hacker(hb)
	hr.phase = "emp_return"
	check(c.contact_tag(hr) == "BREACHER", "Returning Breacher after an EMP: plain BREACHER tag, no RTB")
	hr.phase = "emp"
	check(c.contact_tag(hr) == "EMP OVERLOAD", "EMP OVERLOAD tag kept")
	check(FileAccess.get_file_as_string("res://scripts/RadarContacts.gd").contains("-24.0 * marker_scale"), "A parked Breacher's tag sits above it, clear of the ship console")
	clean()

	# --- High-score rows ---
	console.board.scores = [{"initials": "AAA", "score": 900, "wave": 3, "difficulty": "H"}, {"initials": "BBB", "score": 800, "wave": 10, "difficulty": "N"}, {"initials": "CCC", "score": 700, "wave": 1, "difficulty": "E"}]
	console._refresh_high_score_panel()
	check(console.score_rows[0][3].text == "HARD" and console.score_rows[1][3].text == "NORMAL" and console.score_rows[2][3].text == "EASY", "Score rows show EASY, NORMAL or HARD in full, no wave")
	check(console.score_stats_text(console.board.scores[1]).contains("WAVE 10"), "The wave is still in the hover box")

	# --- Stealth Interceptor: when it is offered ---
	clean(0)
	for i in range(3):
		base()
	check(c.large_ship_count() == 3 and not c.can_launch_stealth(), "Easy: never offered, even with 3 Enemy Carriers")
	clean(1)
	var b1 := base()
	var b2 := base()
	check(not c.can_launch_stealth(), "Normal with 2 large ships: not offered")
	c._update_stealth(0.0)
	check(c.stealth_ready_sounds == 0, "No ready sound while it is not offered")
	var b3 := base()
	check(c.can_launch_stealth(), "Normal with 3 Enemy Carriers: offered")
	c._update_stealth(0.0)
	c._update_stealth(0.0)
	check(c.stealth_ready_sounds == 1 and c.stealth_ready_player.stream is AudioStreamWAV, "Bright ready sound plays once when it becomes available")
	check(c.stealth_ready_player.bus == "Effects" and absf(c.stealth_ready_volume_db + 12.0) < 0.01, "Ready sound has its own volume and follows the Effects slider")
	c._remove_contact(b3.id)
	c.siege_enabled = true
	var rs: Dictionary = c.find_contact(c.spawn_siege_ship())
	check(c.large_ship_count() == 3 and c.can_launch_stealth(), "The Siege Ship counts as a large ship")
	c._remove_contact(rs.id)
	b3 = base()

	# --- 0.1.2: The center-inset button ---
	ship._process(0.0)
	ship.queue_redraw()
	await frames(3)
	ship._process(0.0)
	check(ship.stealth_button.visible and ship.stealth_box.size.x > 40.0, "STEALTH WEAPON button covers the center inset while it can launch")
	var hull_rect := ship.get_global_rect()
	check(ship.stealth_box.position.y < hull_rect.size.y * 0.5 and ship.stealth_box.end.y > hull_rect.size.y * 0.5, "The button spans the ship centerline, not the top flight pod")
	check(ship.stealth_label == "STEALTH WEAPON", "Label reads STEALTH WEAPON")
	var p1 := 0.0
	var p2 := 0.0
	c.battle_time = 0.0
	p1 = ship.stealth_pulse()
	c.battle_time = 0.625
	p2 = ship.stealth_pulse()
	check(p1 > 0.95 and p2 < 0.05 and ship.stealth_pulse_hz <= 1.0, "Gentle pulse (under 1 per second), not a flash")
	var launched := [0]
	ship.stealth_launched.connect(func() -> void: launched[0] += 1)
	ship.stealth_button.pressed.emit()
	var sv: Dictionary = {}
	for k in c.contacts:
		if k.kind == "stealth_interceptor":
			sv = k
	check(launched[0] == 1 and not sv.is_empty(), "Pressing the button launches the Stealth Interceptor")
	ship._process(0.0)
	check(not c.can_launch_stealth() and not ship.stealth_button.visible, "Once launched the center inset goes back to normal (no button)")
	check(c.contact_tag(sv) == "STEALTH" and not sv.revealed, "Its tag reads STEALTH and it starts hidden")
	c.battle_time = 0.0
	var a1: float = c.display_color(sv).a
	c.battle_time = 1.0 / (c.stealth_blink_hz * 2.0) + 0.001
	var a2: float = c.display_color(sv).a
	check(absf(a1 - a2) > 0.5, "It blinks rapidly while hidden")
	check(c.count_interceptors() == 0 and c.speed_for_kind("interceptor") * c.stealth_speed_factor > c.speed_for_kind("interceptor") * 1.5, "Not counted as a normal Interceptor; much faster than one")
	# A Attack Drone next to it cannot see it yet.
	var r1 := drone_at(b1, sv.position)
	r1.phase = "harass"
	r1.attack_cooldown = 0.0
	c.drone_hit_chance = 1.0
	c._update_drone(r1, 0.05)
	check(not c.find_contact(sv.id).is_empty() and c.stealth_lost == 0, "Attack Drones cannot attack it before it fires")
	c._remove_contact(r1.id)
	# Fly the run.
	var target_id := ""
	var full := 0.0
	var t := 0.0
	var first_shot := -1.0
	var second_shot := -1.0
	while t < 40.0 and not c.find_contact(sv.id).is_empty():
		c._process(0.05)
		t += 0.05
		if first_shot < 0.0 and c.stealth_nukes_fired == 1:
			first_shot = t
			target_id = sv.target_id
			full = c.find_contact(target_id).max_hits
			check(sv.revealed and c.contact_tag(sv) == "STEALTH", "After firing it is visible to the enemy (no more blinking)")
		if second_shot < 0.0 and c.stealth_nukes_fired == 2:
			second_shot = t
	check(first_shot > 0.0 and second_shot - first_shot >= c.stealth_shot_seconds - 0.05, "Two nukes, %.0f seconds apart (%.2f s)" % [c.stealth_shot_seconds, second_shot - first_shot])
	check(c.stealth_nuke_hits == 2 and c.find_contact(target_id).is_empty() and c.carriers_destroyed == 1, "Two nukes destroy a Enemy Carrier (3 hits each)")
	check(c.find_contact(sv.id).is_empty() and c.stealth_recovered == 1 and absf(c.stealth_cooldown_remaining - 60.0) < 0.2, "It returns and rearms for 60 seconds")
	check(not c.status_message.contains("REBUILD") and not c.status_message.contains("REARM"), "No rearm message or countdown on screen")
	check(not c.can_launch_stealth(), "Not offered while rearming")
	c.stealth_cooldown_remaining = 0.0
	c.wave = 5  # the run advanced the wave clock
	var tries := 0
	while c.large_ship_count() < 3 and tries < 8:
		base()
		tries += 1
	var sounds_before: int = c.stealth_ready_sounds
	c._update_stealth(0.0)
	check(c.can_launch_stealth() and c.stealth_ready_sounds == sounds_before + 1, "When it is ready again the sound plays again")
	check(events.size() >= 4 and events.any(func(e: String) -> bool: return e.begins_with("Stealth Interceptor launched")), "Its launch, shots and return are written to the session log")

	# --- One nuke takes 3 of 6 Enemy Carrier hits; 5 of 10 Siege hits ---
	clean(1)
	var nb := base()
	var nbx := base()
	var nby := base()
	var sv2: Dictionary = {}
	c.launch_stealth()
	for k in c.contacts:
		if k.kind == "stealth_interceptor":
			sv2 = k
	c._fire_stealth_nuke(sv2, nb)
	t = 0.0
	while t < 10.0 and c.stealth_nuke_hits == 0:
		c._update_stealth(0.05)
		t += 0.05
	check(absf(nb.hits_remaining - (nb.max_hits - 3.0)) < 0.01 and nb.max_hits == 6.0, "One nuke = 3 Enemy Carrier hits")
	clean(1)
	c.siege_enabled = true
	var rsx: Dictionary = c.find_contact(c.spawn_siege_ship())
	base()
	base()
	c.launch_stealth()
	for k in c.contacts:
		if k.kind == "stealth_interceptor":
			sv2 = k
	c._fire_stealth_nuke(sv2, rsx)
	t = 0.0
	while t < 10.0 and c.stealth_nuke_hits == 0:
		c._update_stealth(0.05)
		t += 0.05
	check(absf(rsx.hits_remaining - 5.0) < 0.01, "One nuke = 5 of the Siege Ship's 10 hits")

	# --- Fewer large ships: it finishes its run ---
	clean(1)
	var fa := base()
	var fb := base()
	var fc := base()
	c.launch_stealth()
	for k in c.contacts:
		if k.kind == "stealth_interceptor":
			sv2 = k
	c._remove_contact(fb.id)
	c._remove_contact(fc.id)
	c._update_stealth(0.05)
	check(sv2.phase == "attack" and c.large_ship_count() == 1, "With fewer than 3 large ships it keeps going")
	c._remove_contact(fa.id)
	c._update_stealth(0.05)
	check(sv2.phase == "return", "With no large ship left it heads home with its nukes")

	# --- Loss and rebuild (silent) ---
	for level in [1, 2]:
		clean(level)
		var la := base()
		base()
		base()
		c.launch_stealth()
		for k in c.contacts:
			if k.kind == "stealth_interceptor":
				sv2 = k
		c._fire_stealth_nuke(sv2, la)
		var lr := drone_at(la, sv2.position)
		lr.phase = "harass"
		lr.attack_cooldown = 0.0
		# 1.1.0: Attack Drones shoot at it from range with Stealth Hit Chance (was the touch hit).
		c.stealth_hit_chance = 1.0
		c._update_drone(lr, 0.0)
		check(c.find_contact(sv2.id).is_empty() and c.stealth_lost == 1, "%s: once seen, one Attack Drone hit destroys it" % ["", "Normal", "Hard"][level])
		check(absf(c.stealth_cooldown_remaining - (180.0 if level == 1 else 240.0)) < 0.01, "%s: rebuild takes %d minutes" % [["", "Normal", "Hard"][level], 3 if level == 1 else 4])
		check(not c.status_message.contains("REBUILD") and not c.status_message.contains(":"), "No rebuild timer on screen")
		c.stealth_hit_chance = 0.045

	# --- JUMP jump while it is out ---
	clean(1)
	base()
	base()
	base()
	c.jump_recharge_remaining = 0.0
	c.launch_stealth()
	check(c.request_jump() and c.count_kind("stealth_interceptor") == 0 and absf(c.stealth_cooldown_remaining - 60.0) < 0.01, "JUMP jump brings it home and it rearms")
	clean(1)
	check(c.stealth_cooldown_remaining == 0.0 and c.stealth_launches == 0, "A new battle starts with it ready")

	# --- Preserved ---
	check(not console.development_build and absf(console.sweep_volume_db + 20.0) < 0.01 and not console.show_hover_tooltips, "Development Build and hover pop-ups off; sweep still -20 dB")
	check(c.emp_points_per_charge == 5000 and is_equal_approx(c.hard_nuke_speed, 1.45) and c.siege_hit_points == 10 and c.carrier_hits_to_destroy == 6 and c.jump_recharge_seconds == 45.0, "EMP, Siege Ship, Enemy Carrier and JUMP values unchanged; Hard nuke speed 1.45 (1.2.7)")
	check(ship.FILL != null and ship.OUTLINE != null and absf(ship.fill_opacity - 0.34) < 0.001, "Approved ship art and fill unchanged")

	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("V109_RESULT checks=%d failures=%d" % [checks, failures])
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
