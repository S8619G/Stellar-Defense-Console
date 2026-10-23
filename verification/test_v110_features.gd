extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.1.0: destroyed-totals battle readout, landing pauses,
## Attack Drones focus fire on a revealed Stealth Interceptor, random nuke speed and all
## Gunships on auto against several nukes.
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

func nuke_at(b: Dictionary) -> Dictionary:
	b.nuclear_launched = false
	return c.find_contact(c._launch_nuclear(b))

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://v110_test_settings.cfg"
	console.high_score_file = "user://v110_test_scores.json"
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
	c.random_seed = 1110
	root.add_child(console)
	c.set_process(false)
	console.get_node("TuningPanel").visible = false
	clean()
	var events: Array[String] = []
	c.battle_event.connect(func(m: String) -> void: events.append(m))

	# --- Version 1.1.0 ---
	check(ProjectSettings.get_setting("application/config/version") == "1.0.8", "Project version is 1.1.1")
	check(not console.test_build and console.version_text() == "STELLAR DEFENSE CONSOLE 1.0.8", "Version text reads STELLAR DEFENSE CONSOLE 1.0.8")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.0.8_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.0.8_Mac.zip")
		and presets.get_value("preset.1.options", "application/short_version", "") == "1.0.8"
		and presets.get_value("preset.1.options", "application/version", "") == "1.0.8", "Export presets name 1.1.1 files and the Mac version is 1.1.1")
	check(int(presets.get_value("preset.0.options", "application/export_angle", 0)) == 1, "Windows export still includes the ANGLE files")

	# --- 1. Battle readout: destroyed totals, losses, EMP in EMP blue ---
	console._process(0.0)
	var lines: PackedStringArray = console.battle_readout.text.split("\n")
	var names: Array[String] = []
	for l in lines:
		names.append(l.rsplit("  ", true, 1)[0])
	check(names == ["ATTACK DRONES DESTROYED", "BREACHERS DESTROYED", "MISSILES DESTROYED", "NUKES DESTROYED", "ENEMY CARRIERS DESTROYED",
		"SIEGE SHIPS DESTROYED", "INTERCEPTORS LOST", "GUNSHIPS LOST", "STEALTH INTERCEPTORS LOST"], "Readout rows in the approved order: %s" % [names])
	var text: String = console.battle_readout.text
	check(not text.contains("RETURNING") and not text.contains("INCOMING") and not text.contains("EMP"), "No returning, active or EMP rows in the main readout")
	check(console.emp_readout != null and console.emp_readout.text == "EMP CHARGES  0", "EMP CHARGES is its own last line")
	check(console.emp_readout.get_theme_color("font_color") == c.emp_color, "EMP CHARGES uses the EMP blast color")
	var old_emp: Color = c.emp_color
	c.emp_color = Color(0.2, 0.4, 1.0)
	console._process(0.0)
	check(console.emp_readout.get_theme_color("font_color") == Color(0.2, 0.4, 1.0), "Changing Emp Color in the Inspector changes the EMP CHARGES line too")
	c.emp_color = old_emp
	check(console.battle_readout.get_theme_color("font_color") == Color(0.72, 0.66, 0.70, 1), "The other lines keep their color")
	await frames(2)
	var r: Rect2 = console.battle_readout.get_global_rect()
	var e: Rect2 = console.emp_readout.get_global_rect()
	var repair_info: Label = null
	for n in console.find_children("*", "Label", true, false):
		if n.text.begins_with("NEXT BONUS"):
			repair_info = n
	var buttons: Rect2 = console.get_node("BottomButtons").get_global_rect()
	var used_bottom: float = r.position.y + console.battle_readout.get_line_height() * lines.size()
	check(e.position.y >= used_bottom - 1.0 and e.end.y < buttons.position.y - 40.0, "EMP line sits under the readout, clear of the buttons (%.0f / %.0f)" % [e.end.y, buttons.position.y])
	check(repair_info == null or r.position.y >= repair_info.get_global_rect().end.y, "Readout does not crowd RAPID REPAIR above it")
	var font: Font = console.battle_readout.get_theme_font("font")
	var widest := 0.0
	for l in (text + "\n" + console.emp_readout.text).split("\n"):
		widest = maxf(widest, font.get_string_size(l.replace("  0", "  999"), HORIZONTAL_ALIGNMENT_LEFT, -1, console.readout_font_size).x)
	check(r.position.x + widest < 420.0, "The longest row with 3 digits fits the left panel (%.0f px)" % widest)
	# Totals count every source.
	var b := base()
	var drone := drone_at(b, Vector3(0.0, -0.3, 0.0))
	var v := interceptor_at(drone.position)
	run(0.1)
	check(int(c.kills.get("drone", 0)) == 1, "A Interceptor kill counts in ATTACK DRONES DESTROYED")
	c.prox_active = true
	c.prox_success_chance = 0.95
	var m: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	m.position = c.own_ship_position + Vector3(0.0, 0.05, 0.0)
	var before_missiles: int = int(c.kills.get("missile", 0))
	for i in range(30):
		c._resolve_missiles()
		c.battle_time += 0.11
	c.prox_active = false
	check(int(c.kills.get("missile", 0)) == before_missiles + 1, "A Defense Shield kill counts in MISSILES DESTROYED")
	c._remove_contact(v.id)
	b.hits_remaining = 1.0
	c._hit_carrier(b, 1.0)
	check(int(c.kills.get("carrier", 0)) == 1 and c.count_kind("carrier") == 0, "A Enemy Carrier kill counts in ENEMY CARRIERS DESTROYED")
	c.stealth_lost = 2
	c.interceptors_lost = 3
	c.gunships_lost = 1
	c.emp_charges = 2
	console._process(0.0)
	text = console.battle_readout.text
	check(text.contains("ATTACK DRONES DESTROYED  1") and text.contains("ENEMY CARRIERS DESTROYED  1") and text.contains("INTERCEPTORS LOST  3") and text.contains("GUNSHIPS LOST  1") and text.contains("STEALTH INTERCEPTORS LOST  2") and console.emp_readout.text == "EMP CHARGES  2", "Readout shows the battle totals and losses")
	clean()
	console._process(0.0)
	check(console.battle_readout.text.contains("ATTACK DRONES DESTROYED  0") and console.battle_readout.text.contains("STEALTH INTERCEPTORS LOST  0"), "Retry clears the readout")

	# --- 2. Recovery pause after landing ---
	check(c.interceptor_recovery_seconds == 3.0 and c.gunship_recovery_seconds == 5.0 and c.launch_cooldown_seconds == 4.0 and c.gunship_launch_cooldown == 8.0, "Inspector: Interceptor 3 s and Gunship 5 s landing pause; launch cooldowns unchanged")
	var v1: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	var v2: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	for x in [v1, v2]:
		x.phase = "return"
		x.age = c.sortie_seconds + 1.0
	v1.position = c.launch_origin(v1.lane)
	v2.position = c.launch_origin(v2.lane) + Vector3(0.0, 1.2, 0.0)
	c._update_interceptors(0.0)
	# 1.0.5: each ship has its own ready timer; a landing never restarts another's wait.
	check(c.interceptors_returned == 1 and c.interceptor_waits.size() == 1 and absf(c.interceptor_waits[0].left - 3.0) < 0.01, "An Interceptor landing gives that Interceptor a 3 s wait")
	console._process(0.0)
	check(not console.launch_button.disabled and c.interceptors_ready() == 4 and console.launch_button.text.ends_with("2 READY"), "The other Interceptors stay ready (1.0.6: the button shows the 2 one press sends): %s" % console.launch_button.text.replace("\n", " / "))
	run(2.0)
	v2.position = c.launch_origin(v2.lane)
	c._update_interceptors(0.0)
	check(c.interceptors_returned == 2 and c.interceptor_waits.size() == 2 and absf(c.interceptor_waits[0].left - 1.0) < 0.06 and absf(c.interceptor_waits[1].left - 3.0) < 0.01, "A second landing does not restart the first one's wait")
	check(c.interceptors_ready() == 4 and c.launch_interceptors() == 2, "Ready Interceptors launch while the landed ones wait")
	check(c.interceptors_ready() == 0 and c.interceptor_waits.size() == 4, "The 2 ready ones left behind wait the 4 s launch cooldown")
	run(1.1)
	check(c.interceptors_ready() == 1 and c.launch_interceptors() == 1, "The first landed Interceptor is ready 3 s after its own landing and launches alone")
	run(2.0)
	check(c.interceptors_ready() == 1 and c.launch_interceptors() == 1, "The second is ready 3 s after its landing; the next press sends it too")
	clean()
	var rp: Dictionary = c.find_contact(c._spawn_gunship())
	rp.phase = "return"
	rp.position = c.launch_origin(rp.lane)
	c._update_gunships(0.0)
	check(c.gunships_returned == 1 and c.gunship_waits.size() == 1 and absf(c.gunship_waits[0].left - 5.0) < 0.01, "A Gunship landing gives that Gunship a 5 s wait")
	console._process(0.0)
	check(not console.gunship_button.disabled and console.gunship_button.text.ends_with("1 READY"), "The other Gunship stays ready: %s" % console.gunship_button.text.replace("\n", " / "))
	check(c.launch_gunship() == 1 and c.gunships_ready() == 0 and absf(c.gunship_ready_in() - 5.0) < 0.01, "It launches; the landed one is next in 5 s")
	console._process(0.0)
	check(console.gunship_button.disabled and console.gunship_button.text.ends_with("READY IN 5s"), "LAUNCH GUNSHIP shows READY IN 5s")
	run(5.05)
	check(c.launch_gunship() == 1, "Ready 5 s after its landing")
	console._process(0.0)
	check(console.gunship_button.disabled and console.gunship_button.text.ends_with("ALL DEPLOYED"), "Both out: ALL DEPLOYED at once")
	clean()
	# Auto Launch follows the same per-ship rules.
	c.auto_launch_interceptors = true
	var b2 := base()
	drone_at(b2, Vector3(0.2, 0.3, 0.0))
	for i in range(5):
		interceptor_at(Vector3(0.0, 0.9, 0.0)).phase = "return"
	c._hold_after_landing("interceptor")
	var auto_before: int = c.auto_interceptor_launches
	c._update_auto_launch()
	check(c.count_interceptors() == 5 and c.auto_interceptor_launches == auto_before, "Auto Launch Interceptors waits for the one waiting Interceptor")
	run(3.1)
	check(c.auto_interceptor_launches == auto_before + 1 and c.interceptors_returned == 0, "Auto Launch Interceptors launches it when its own wait ends")
	clean()
	c.interceptor_recovery_seconds = 0.0
	c._hold_after_landing("interceptor")
	check(c.interceptor_ready_in() == 0.0 and c.interceptor_waits.is_empty(), "Interceptor Recovery Seconds 0 turns the pause off")
	c.interceptor_recovery_seconds = 3.0

	# --- 4. Random nuke speed ---
	check(absf(c.nuke_speed_random_max - 0.08) < 0.0001 and c.hard_nuke_speed_lean and c.auto_all_gunships_nukes == 2, "Inspector: 8% random nuke speed, Hard lean on, all Gunships at 2 nukes")
	var means := []
	for level in [0, 1, 2]:
		clean(level)
		var total := 0.0
		var low := 1.0
		var high := 0.0
		for i in range(4000):
			var s: float = c.nuke_speed_bonus()
			total += s
			low = minf(low, s)
			high = maxf(high, s)
		means.append(total / 4000.0)
		check(low >= 0.0 and high <= 0.08 and high > 0.075, "Level %d bonus stays within 0 to 8%% (%.4f to %.4f)" % [level, low, high])
	check(absf(means[0] - 0.04) < 0.003 and absf(means[1] - 0.04) < 0.003, "Easy and Normal spread evenly (mean %.4f, %.4f)" % [means[0], means[1]])
	check(absf(means[2] - 0.0533) < 0.003, "Hard leans to the top end (mean %.4f, about 5.3%%)" % means[2])
	clean(2)
	c.hard_nuke_speed_lean = false
	var plain := 0.0
	for i in range(4000):
		plain += c.nuke_speed_bonus()
	check(absf(plain / 4000.0 - 0.04) < 0.003, "Hard lean off: even spread")
	c.hard_nuke_speed_lean = true
	clean(1)
	c.nuclear_weapons_enabled = true
	var b3 := base()
	events.clear()
	var n1 := nuke_at(b3)
	check(n1.has("speed_bonus") and n1.speed_bonus >= 0.0 and n1.speed_bonus <= 0.08, "Each nuke stores its own bonus (%.3f)" % n1.speed_bonus)
	check(events.size() == 1 and events[0].begins_with("nuke %s launched | speed bonus +" % n1.id), "The bonus is logged: %s" % [events])
	n1.speed_bonus = 0.08
	var start: Vector3 = n1.position
	c._update_special_projectiles(0.5)
	var moved: float = start.distance_to(n1.position)
	var expected: float = c.nuclear_speed * c.nuke_speed_factor() * 1.08 * c.movement_speed * 0.5
	check(absf(moved - expected) < 0.00001, "An 8%% bonus flies 8%% faster (%.5f vs %.5f)" % [moved, expected])
	n1.speed_bonus = 0.0
	start = n1.position
	c._update_special_projectiles(0.5)
	check(absf(start.distance_to(n1.position) - c.nuclear_speed * c.nuke_speed_factor() * c.movement_speed * 0.5) < 0.00001, "A 0% bonus keeps the usual speed (Normal 1.1x)")
	c.nuke_speed_random_max = 0.0
	var n0 := nuke_at(b3)
	check(n0.speed_bonus == 0.0, "Nuke Speed Random Max 0 turns the bonus off")
	c.nuke_speed_random_max = 0.08
	check(is_equal_approx(c.hard_nuke_speed, 1.45) and is_equal_approx(c.normal_nuke_speed, 1.25) and is_equal_approx(c.easy_nuke_speed, 1.1), "Difficulty nuke speeds (1.2.7): 1.1 / 1.25 / 1.45")

	# --- 4. Auto Gunships: all at once for several nukes ---
	clean(1)
	c.nuclear_weapons_enabled = true
	c.auto_launch_gunships = true
	var b4 := base()
	var b5 := base()
	nuke_at(b4)
	c._update_auto_launch()
	check(c.count_kind("gunship") == 1 and c.gunships_ready() == 0 and c.gunship_ready_in() > 7.0, "One nuke: one Gunship and the normal cooldown for the other")
	nuke_at(b5)
	c._update_auto_launch()
	check(c.count_kind("gunship") == 2 and c.auto_all_gunship_launches == 1, "Two nukes: every available Gunship launches at once, skipping the cooldown")
	clean(1)
	c.nuclear_weapons_enabled = true
	c.auto_launch_gunships = true
	b4 = base()
	b5 = base()
	nuke_at(b4)
	nuke_at(b5)
	events.clear()
	c._update_auto_launch()
	check(c.count_kind("gunship") == 2 and c.gunships_in_hangar() == 0, "Two nukes from a standing start: both Gunships leave together")
	check(events.any(func(m: String) -> bool: return m.begins_with("auto launch: all Gunships (2)")), "The all-Gunship launch is logged")
	clean(1)
	c.nuclear_weapons_enabled = true
	c.auto_launch_gunships = true
	c.max_gunships = 3
	b4 = base()
	b5 = base()
	nuke_at(b4)
	nuke_at(b5)
	c._update_auto_launch()
	check(c.count_kind("gunship") == 3, "With Max Gunships 3 all three launch")
	c.max_gunships = 2
	clean(1)
	c.nuclear_weapons_enabled = true
	c.auto_launch_gunships = true
	b4 = base()
	b5 = base()
	nuke_at(b4)
	nuke_at(b5)
	c._hold_after_landing("gunship")
	c._update_auto_launch()
	check(c.count_kind("gunship") == 1 and c.gunship_waits.size() == 1, "1.0.5: every ready Gunship goes; the one in its landing wait stays")
	run(5.1)
	check(c.count_kind("gunship") == 2, "It follows when its own 5 s ends")
	clean(1)
	c.nuclear_weapons_enabled = true
	b4 = base()
	b5 = base()
	nuke_at(b4)
	nuke_at(b5)
	check(c.launch_gunship() == 1 and c.launch_gunship() == 0, "Manual LAUNCH GUNSHIP unchanged: one per press with the cooldown")
	clean(1)
	c.nuclear_weapons_enabled = true
	c.auto_launch_gunships = true
	c.auto_all_gunships_nukes = 0
	b4 = base()
	b5 = base()
	nuke_at(b4)
	nuke_at(b5)
	c._update_auto_launch()
	check(c.count_kind("gunship") == 1, "Auto All Gunships Nukes 0 restores one-at-a-time launches")
	c.auto_all_gunships_nukes = 2

	# --- 3. Attack Drones focus fire on a revealed Stealth Interceptor ---
	clean(1)
	check(absf(c.stealth_hit_chance - 0.045) < 0.0001 and absf(c.stealth_focus_range - 0.40) < 0.001 and absf(c.stealth_pursuit_distance - 0.25) < 0.001 and absf(c.stealth_shot_range - 0.30) < 0.001 and absf(c.stealth_shot_interval - 1.5) < 0.001, "Inspector: hit chance 0.045, focus range 0.40, pursuit 0.25, shot range 0.30, one shot per 1.5 s")
	var bs := [base(), base(), base()]
	check(c.launch_stealth(), "Stealth Interceptor launches with 3 Enemy Carriers")
	var sv: Dictionary = c.find_contact("")
	for x in c.contacts:
		if x.kind == "stealth_interceptor":
			sv = x
	var hunter := drone_at(bs[0], sv.position + Vector3(0.2, 0.0, 0.0))
	hunter.phase = "harass"
	var far := drone_at(bs[0], sv.position + Vector3(0.0, 0.6, 0.0))
	far.phase = "harass"
	c.stealth_hit_chance = 1.0
	c._update_drone(hunter, 0.05)
	check(c.stealth_shots_taken == 0 and not hunter.has("stealth_chasing"), "Hidden: Attack Drones ignore it")
	sv.revealed = true
	sv.phase = "return"
	c.stealth_hit_chance = 0.0
	c._update_drone(hunter, 0.05)
	c._update_drone(far, 0.05)
	check(hunter.get("stealth_chasing", "") == sv.id and not far.has("stealth_chasing"), "Revealed: a Attack Drone within 0.40 turns on it; one further away does not")
	check(c.stealth_shots_taken == 1, "In range it takes a ranged shot (no touch needed)")
	c._update_drone(hunter, 0.5)
	check(c.stealth_shots_taken == 1, "One shot per 1.5 s per Attack Drone")
	c._update_drone(hunter, 1.1)
	check(c.stealth_shots_taken == 2, "Next shot after 1.5 s")
	for i in range(400):
		sv.position = hunter.position + Vector3(0.1, 0.0, 0.0)
		c._update_drone(hunter, 0.05)
		if hunter.has("stealth_done"):
			break
	check(hunter.get("stealth_done", "") == sv.id and hunter.stealth_chased >= 0.25 - 0.001, "It gives up after chasing 0.25 (%.3f)" % hunter.get("stealth_chased", 0.0))
	var shots_after: int = c.stealth_shots_taken
	c._update_drone(hunter, 2.0)
	check(c.stealth_shots_taken == shots_after, "After giving up it goes back to its job")
	var hunter2 := drone_at(bs[1], sv.position + Vector3(-0.1, 0.0, 0.0))
	hunter2.phase = "harass"
	c.stealth_hit_chance = 1.0
	c._update_drone(hunter2, 0.05)
	check(c.stealth_lost == 1 and c.count_kind("stealth_interceptor") == 0 and c.stealth_cooldown_remaining > 170.0, "One hit destroys it and the rebuild starts")
	check(c.drone_hit_chance == 0.5, "Attack Drone hit chance on other fighters unchanged")

	# --- Preserved ---
	check(not console.development_build and absf(console.sweep_volume_db + 20.0) < 0.01 and not console.show_hover_tooltips, "Development Build and hover pop-ups off; sweep still -20 dB")
	check(c.emp_points_per_charge == 5000 and c.siege_hit_points == 10 and c.carrier_hits_to_destroy == 6 and c.jump_recharge_seconds == 45.0 and c.stealth_speed_factor == 2.2, "EMP, Siege Ship, Enemy Carrier, JUMP and Stealth Interceptor speed unchanged")
	check(ship.FILL != null and ship.OUTLINE != null and absf(ship.fill_opacity - 0.34) < 0.001, "Approved ship art and fill unchanged")

	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("V110_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
