extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.2.1: tougher, fewer enemies; tougher nukes;
## last-ditch ship missiles; fewer Breacher launches.
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
func base(c: Control) -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	b.drone_timer = 99.0
	b.missile_timer = 99.0
	b.heavy_timer = 99.0
	b.flak_timer = 99.0
	b.nuclear_timer = 99.0
	return b
func fresh(c: Control, level: int) -> void:
	c.difficulty = level
	c.reset_battle()
	c.pending.clear()
	c.contacts.clear()

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://test_v121_scores.json"
	console.settings_file = "user://test_v121.cfg"
	console.quit_dry_run = true
	console.shell_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	root.add_child(console)
	c.set_process(false)
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false

	# --- Version 1.2.1 ---
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 1.2.1")
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.1", "Version text reads STELLAR DEFENSE CONSOLE 1.1.1")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Mac.zip")
		and presets.get_value("preset.1.options", "application/short_version", "") == "1.1.1"
		and presets.get_value("preset.1.options", "application/version", "") == "1.1.1", "Export presets name 1.2.1 files")

	# --- Approved values ---
	# 1.2.2: Enemy Carrier hits 10 -> 11 and Gunship Nuke Hit Interval 0.6 -> 0.7 (test_v122_features).
	check(c.carrier_hits_to_destroy == 11, "Enemy Carriers take 11 hits (1.2.1: 10)")
	check(c.breacher_hit_points == 5, "Breachers take 5 hits (was 3)")
	check(c.drone_interceptor_hits == 2 and is_equal_approx(c.drone_interceptor_hit_interval, 0.5), "Attack Drones take 2 Interceptor hits, 0.5 s apart")
	check(c.nuclear_hit_points == 6 and is_equal_approx(c.gunship_nuke_hit_interval, 0.7), "Nukes take 6 hits; Gunship Nuke Hit Interval 0.7 s (1.2.2)")
	check(is_equal_approx(c.ship_nuke_target_fraction, 0.75), "Ship missiles go for nukes only in the last quarter")
	check(is_equal_approx(c.ship_missile_heavy_range, 0.15), "Ship missiles go for Breachers only at half the old range")
	check(is_equal_approx(c.own_missile_interval, 8.0), "Ship missile reload is 8 s (was 6)")
	check(is_equal_approx(c.heavy_launch_interval, 28.0), "Breachers launch every 28 s (was 22)")
	check(c.easy_wave_force == [2, 2, 2, 2, 2] and c.normal_wave_force == [2, 3, 2, 3, 3] and c.hard_wave_force == [2, 3, 3, 3, 3],
		"Waves 3 to 5 bring one Enemy Carrier fewer")
	check(c.wave_onscreen_carriers == [2, 2, 3, 3, 4] and c.defined_waves, "On-screen limits and defined waves unchanged")

	# --- Toughness by difficulty ---
	var expect := {0: [7, 3, 4], 1: [11, 5, 6], 2: [15, 7, 8]}
	for level in [0, 1, 2]:
		fresh(c, level)
		var b := base(c)
		var heavy: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
		var nuke: Dictionary = c.find_contact(c._launch_nuclear(b))
		check(int(b.hits_remaining) == expect[level][0], "Level %d: Enemy Carrier takes %d hits" % [level, expect[level][0]])
		check(int(heavy.health) == expect[level][1], "Level %d: Breacher takes %d hits" % [level, expect[level][1]])
		check(c.nuke_hits_left(nuke) == expect[level][2], "Level %d: nuke takes %d hits" % [level, expect[level][2]])

	# --- Attack Drones take two Interceptor hits ---
	fresh(c, 1)
	var b2 := base(c)
	var drone: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b2.id))
	drone.position = Vector3(0.0, 0.0, 0.0)
	c.interceptors_per_launch = 1
	c.launch_interceptors()
	var interceptor: Dictionary = {}
	for ship in c.contacts:
		if ship.kind == "interceptor":
			interceptor = ship
	interceptor.phase = "intercept"
	interceptor.position = drone.position
	var score_before: int = c.score
	c._update_interceptors(0.0)
	check(not c.find_contact(drone.id).is_empty() and int(drone.interceptor_hits) == 1 and c.score == score_before, "First Interceptor hit damages the Attack Drone; no points yet")
	interceptor.position = drone.position
	c._update_interceptors(0.2)
	check(not c.find_contact(drone.id).is_empty(), "The Interceptor must wait 0.5 s before hitting again")
	interceptor.position = drone.position
	c._update_interceptors(0.35)
	check(c.find_contact(drone.id).is_empty() and c.score > score_before, "Second hit destroys the Attack Drone and scores once")
	c.drone_interceptor_hits = 1
	var drone2: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b2.id))
	drone2.position = Vector3(0.05, 0.0, 0.0)
	interceptor.position = drone2.position
	interceptor.drone_fire_remaining = 0.0
	c._update_interceptors(0.0)
	check(c.find_contact(drone2.id).is_empty(), "Attack Drone Interceptor Hits 1 restores the one-pass kill")
	c.drone_interceptor_hits = 2
	c.interceptors_per_launch = 2

	# --- Last-ditch ship missiles ---
	fresh(c, 1)
	var b3 := base(c)
	var n2: Dictionary = c.find_contact(c._launch_nuclear(b3))
	var total: float = n2.launch_distance
	var dir: Vector3 = (n2.position - c.own_ship_position).normalized()
	n2.position = c.own_ship_position + dir * total * 0.4
	check(c.ship_nuke_target().is_empty(), "A nuke 60% of the way in is not a ship-missile target")
	n2.position = c.own_ship_position + dir * total * 0.2
	check(c.ship_nuke_target().get("id", "") == n2.id, "A nuke 80% of the way in is a ship-missile target")
	c.contacts.erase(n2)
	var h2: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b3.id))
	h2.position = c.own_ship_position + Vector3(0.2, 0.0, 0.0)
	c._fire_ship_missile()
	var aimed := ""
	for x in c.contacts:
		if x.kind == "own_missile":
			aimed = x.target_id
	check(aimed == b3.id, "A Breacher 0.2 away is not targeted; the missile goes to the Enemy Carrier")
	for i in range(c.contacts.size() - 1, -1, -1):
		if c.contacts[i].kind == "own_missile":
			c.contacts.remove_at(i)
	h2.position = c.own_ship_position + Vector3(0.1, 0.0, 0.0)
	c._fire_ship_missile()
	aimed = ""
	for x in c.contacts:
		if x.kind == "own_missile":
			aimed = x.target_id
	check(aimed == h2.id, "A Breacher 0.1 away is targeted first")

	print("V121_RESULT checks=", checks, " failures=", failures)
	# Stop every player first so no playback is left running at exit.
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await process_frame
	console.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
