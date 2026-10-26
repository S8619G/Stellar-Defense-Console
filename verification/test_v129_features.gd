extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.2.9: Protect the fleet round sounds, damaged-ship hull bars
## and flashes, the round counter, the random challenge mix, dogfights, Interceptors staying
## out, smarter civilian ships, the bonus repair Gunship, label spacing, the GUNSHIPS
## readout, and the three-ring RADAR look. Also checks that every new switch is off
## outside the round (the main game is unchanged).
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

func fresh(c: Control, level: int) -> void:
	c.difficulty = level
	c.auto_defense_battery = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.auto_firewall = false
	c.auto_jump = false
	c.auto_rapid_repair = false
	c.auto_spawn = false
	c.reset_battle()
	c.pending.clear()
	c.contacts.clear()

func start_protect(c: Control, level: int, sets: int, seed_value: int = 7) -> void:
	fresh(c, level)
	c.auto_spawn = true
	c.waves_enabled = true
	c.rng.seed = seed_value
	c.wave = sets * 5
	c.sets_completed = sets
	c.wave_phase = "rest"
	c.wave_next_phase = "protect"
	c.safe_remaining = 0.0
	c._start_protect()

func civilians(c: Control) -> Array:
	var list: Array = []
	for x in c.contacts:
		if x.get("faction", "") == "civilian":
			list.append(x)
	return list

func round_drones(c: Control) -> Array:
	var list: Array = []
	for x in c.contacts:
		if x.get("phase", "") == "protect":
			list.append(x)
	return list

func step(c: Control, seconds: float) -> void:
	var t := 0.0
	while t < seconds and c.wave_phase == "protect":
		c._process(1.0 / 30.0)
		t += 1.0 / 30.0

## A Attack Drone placed by hand (already past its jump-in hold).
func drone_at(c: Control, at: Vector3) -> Dictionary:
	c._spawn_protect_drone(false)
	var r: Dictionary = c.contacts[c.contacts.size() - 1]
	r.position = at
	r.hold = 0.0
	return r

func interceptor_at(c: Control, at: Vector3, target_id: String) -> Dictionary:
	var id: String = c._spawn_interceptor("interceptor", false)
	var v: Dictionary = c.find_contact(id)
	v.position = at
	v.phase = "intercept"
	v.target_id = target_id
	v.drone_fire_remaining = 0.0
	return v

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://v129_scores.json"
	console.settings_file = "user://v129_settings.cfg"
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	# 1.0.7: these checks cover the 1.2.9 tender and the TIME row; the 1.0.7 tender and
	# round end are checked in test_protect_convoy.
	c.protect_tender_smart = false
	# 1.0.7.2 tender rules are covered in test_protect_convoy.
	c.protect_tender_launch_when_hit = false
	c.protect_tender_stay_near = false
	c.protect_tender_hull = false
	c.protect_tender_lands = false
	c.protect_timer_end = true
	c.protect_interceptors_lost_end = false
	var dome: Control = console.get_node("CenterContainer/Dome")
	var frame: Control = console.get_node("ConsoleFrame")
	c.auto_spawn = false
	root.add_child(console)
	c.set_process(false)
	for i in range(4):
		await process_frame
	c.klaxon_enabled = false

	# ---------------- Version ----------------
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 0.1.2")
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.1", "Version text reads STELLAR DEFENSE CONSOLE 1.1.1")
	check(not console.version_text().to_lower().contains("test"), "No Test label in the version text")
	var presets := ConfigFile.new()
	check(presets.load("res://export_presets.cfg") == OK, "Export presets load")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Mac.zip")
		and presets.get_value("preset.1.options", "application/version", "") == "1.1.1"
		and presets.get_value("preset.1.options", "application/short_version", "") == "1.1.1", "Export presets name 0.1.2 files")

	# ---------------- Defaults: script off (1.2.8 round), scene on ----------------
	var plain: Control = load("res://scripts/RadarContacts.gd").new()
	for key in ["protect_round_sounds", "civilian_hull_bar", "protect_round_counter", "protect_challenge_mix", "protect_dogfights",
			"protect_interceptors_stay_out", "protect_label_declutter", "civilian_self_repair", "protect_repair_tender"]:
		check(plain.get(key) == false, "Script default: %s off (1.2.8 round)" % key)
		check(c.get(key) == true, "Scene: %s on" % key)
	check(is_equal_approx(plain.civilian_large_evade_speed, 0.0) and is_equal_approx(c.civilian_large_evade_speed, 0.02), "Large ships drift: script 0, scene 0.02")
	check(plain.protect_extra_drones == 0 and is_equal_approx(plain.protect_later_kill_time_factor, 1.0), "Script default: no extra Attack Drones, kill time as 1.2.8")
	check(c.protect_extra_drones == 1 and is_equal_approx(c.protect_later_kill_time_factor, 0.75) and c.protect_extra_drones_from_set == 3, "Scene: from set 3, 1 extra Attack Drone and kill time x0.75 (Normal; Hard off)")
	check(plain.protect_more_danger_on_hard == false and c.protect_more_danger_on_hard == false, "More Danger On Hard off")
	var keep_diff: int = c.active_difficulty
	var keep_sets: int = c.sets_completed
	for row in [[0, 3, 20.8, 6], [1, 2, 18.0, 6], [1, 3, 12.0, 9], [1, 4, 10.5, 11], [2, 3, 11.2, 10]]:
		c.active_difficulty = row[0]
		c.sets_completed = row[1]
		check(is_equal_approx(c.civilian_kill_seconds(), row[2]) and c.protect_drone_count() == row[3],
			"Level %d after set %d: kill time %.1f s, %d Attack Drones (got %.2f s, %d)" % [row[0], row[1], row[2], row[3], c.civilian_kill_seconds(), c.protect_drone_count()])
	c.protect_more_danger_on_hard = true
	c.active_difficulty = 2
	c.sets_completed = 3
	check(is_equal_approx(c.civilian_kill_seconds(), 8.4) and c.protect_drone_count() == 11, "More Danger On Hard ticked: Hard set 3 kill time 8.4 s, 11 Attack Drones")
	c.protect_more_danger_on_hard = false
	c.active_difficulty = keep_diff
	c.sets_completed = keep_sets
	var want := {"protect_interceptor_hit_volume_db": -22.0, "protect_drone_kill_volume_db": -13.0, "protect_ship_attacked_volume_db": -14.0,
		"protect_ship_critical_volume_db": -12.0, "protect_small_ship_lost_volume_db": -14.0, "protect_medium_ship_lost_volume_db": -11.0,
		"protect_large_ship_lost_volume_db": -8.0, "protect_interceptor_lost_volume_db": -15.0, "civilian_hit_flash_seconds": 0.15,
		"protect_wave_gap_min": 6.0, "protect_wave_gap_max": 10.0, "protect_breakoff_chance": 0.6, "protect_help_chance": 0.3,
		"protect_help_range": 0.28, "protect_tail_range": 0.07, "protect_tail_cos": 0.35, "protect_interceptor_loss_chance": 0.07,
		"protect_drone_shot_gap": 0.7, "civilian_repair_delay": 3.0, "civilian_repair_rate": 0.02, "civilian_repair_cap": 0.75,
		"protect_gunship_chance": 0.5, "protect_gunship_repair_rate": 0.1}  # 1.0.7.2: repairs 25% faster
	for key in want:
		check(is_equal_approx(float(c.get(key)), float(want[key])), "%s = %s" % [key, want[key]])
	check(c.protect_wave_groups_min == 2 and c.protect_wave_groups_max == 3, "Waves: 2 to 3 groups")
	check(c.protect_fewer_interceptors_min == 1 and c.protect_fewer_interceptors_max == 2, "Fewer Interceptors: 1 to 2")
	check(c.protect_challenge_max == 3 and c.easy_protect_challenge_change == -1 and c.hard_protect_challenge_change == 1, "Challenges: up to 3, Easy -1, Hard +1")
	check(c.protect_gunship_from_set == 3 and c.protect_gunship_min_challenges == 2, "Repair Tender: set 3+, 2+ challenges")
	plain.free()

	# ---------------- Challenge count ----------------
	var table := {0: [0, 1, 2, 3], 1: [1, 2, 3, 3], 2: [2, 3, 3, 3]}
	for level in table:
		for sets in range(1, 5):
			fresh(c, level)
			c.sets_completed = sets
			c.active_difficulty = level
			check(c.protect_challenge_count() == table[level][sets - 1], "Difficulty %d set %d: %d challenges" % [level, sets, table[level][sets - 1]])

	# ---------------- Challenge roll ----------------
	var seen := {"waves": 0, "fewer": 0, "gang": 0}
	var ok_groups := true
	var ok_gap := true
	var ok_short := true
	var gaps: Array = []
	for n in range(60):
		start_protect(c, 1, 2, 100 + n)
		if n < 5:
			check(c.protect_challenges.size() == 2, "Normal set 2 round %d: 2 challenges (%s)" % [n, c.protect_challenge_names()])
		for item in c.protect_challenges:
			seen[item] += 1
		if c.protect_challenges.has("waves"):
			ok_groups = ok_groups and c.protect_wave_groups >= 2 and c.protect_wave_groups <= 3
			ok_gap = ok_gap and c.protect_wave_gap >= 6.0 and c.protect_wave_gap <= 10.0
			gaps.append(c.protect_wave_gap)
		else:
			ok_groups = ok_groups and c.protect_wave_groups == 1
		if c.protect_challenges.has("fewer"):
			ok_short = ok_short and c.protect_short_interceptors >= 1 and c.protect_short_interceptors <= 2 and c.protect_short_interceptors <= floori(c.protect_drones_total / 3.0)
		else:
			ok_short = ok_short and c.protect_short_interceptors == 0
	check(seen.waves > 10 and seen.fewer > 10 and seen.gang > 10, "Each challenge is picked at random (%s)" % seen)
	check(ok_groups, "Waves: 2 or 3 groups, otherwise one")
	check(ok_gap and gaps.size() > 3 and gaps.max() - gaps.min() > 1.0, "Waves: gap random within 6-10 s")
	check(ok_short, "Fewer Interceptors: 1-2 fewer, at most a third of the Attack Drones")
	start_protect(c, 0, 1, 5)
	check(c.protect_challenges.is_empty() and c.protect_wave_groups == 1 and c.protect_short_interceptors == 0, "Easy set 1: no challenges (the 1.2.8 round)")
	start_protect(c, 2, 4, 5)
	check(c.protect_challenges.size() == 3, "Hard set 4: all three challenges")
	c.protect_challenge_mix = false
	start_protect(c, 2, 4, 5)
	check(c.protect_challenges.is_empty() and c.protect_wave_groups == 1, "Challenge Mix off: no challenges")
	c.protect_challenge_mix = true

	# ---------------- Waves arrive without waiting ----------------
	var found := false
	for n in range(40):
		start_protect(c, 1, 3, 300 + n)
		if c.protect_wave_groups == 3 and not c.repair_tender().size():
			found = true
			break
	check(found, "Found a three-group waves round")
	var first_end: int = c._protect_group_end(0)
	check(first_end == ceili(c.protect_drones_total / 3.0) and c._protect_group_end(2) == c.protect_drones_total, "Groups split the Attack Drones evenly (%d of %d first)" % [first_end, c.protect_drones_total])
	c.civilian_kill_seconds()
	var t := 0.0
	var group1_done := -1.0
	var group2_start := -1.0
	var on_scope_at_group2 := 0
	while t < 40.0 and c.wave_phase == "protect":
		var before: int = c.protect_drones_spawned
		c._process(1.0 / 30.0)
		t += 1.0 / 30.0
		if group1_done < 0.0 and c.protect_drones_spawned >= first_end:
			group1_done = t
		if group2_start < 0.0 and before == first_end and c.protect_drones_spawned > first_end:
			group2_start = t
			on_scope_at_group2 = round_drones(c).size() - (c.protect_drones_spawned - first_end)
	check(group1_done >= 0.0 and group2_start > 0.0, "Second group arrives (first done %.1f s, second %.1f s)" % [group1_done, group2_start])
	check(group2_start - group1_done >= c.protect_wave_gap - 0.05 and group2_start - group1_done <= c.protect_wave_gap + 0.5, "Second group comes Wave Gap (%.1f s) after the first" % c.protect_wave_gap)
	check(on_scope_at_group2 > 0, "Second group jumps in while %d Attack Drones of the first are still on the scope" % on_scope_at_group2)

	# ---------------- Fewer Interceptors ----------------
	start_protect(c, 1, 3, 11)
	c.protect_short_interceptors = 2
	check(c.interceptor_limit() == c.protect_drones_total - 2, "Fewer Interceptors: launches = Attack Drones - 2 (%d)" % c.interceptor_limit())
	c.protect_short_interceptors = 0
	check(c.interceptor_limit() == c.protect_drones_total, "No Fewer Interceptors: launches = Attack Drones")

	# ---------------- Gang up ----------------
	start_protect(c, 1, 2, 12)
	c.contacts = c.contacts.filter(func(x): return x.get("faction", "") == "civilian")
	var ships := civilians(c)
	if ships.size() >= 2:
		var near_ship: Dictionary = ships[0]
		var hurt_ship: Dictionary = ships[1]
		near_ship.hull = 1.0
		hurt_ship.hull = 0.3
		var r := drone_at(c, near_ship.position + Vector3(0.05, 0.0, 0.0))
		var other := drone_at(c, hurt_ship.position + Vector3(0.02, 0.0, 0.0))
		other.civ_target = hurt_ship.id
		var gap_near: float = r.position.distance_to(near_ship.position)
		var gap_hurt: float = r.position.distance_to(hurt_ship.position)
		c.protect_challenges.clear()
		var plain_pick: Dictionary = c._protect_pick_civilian(r)
		c.protect_challenges.append("gang")
		var gang_pick: Dictionary = c._protect_pick_civilian(r)
		var gang_wins: bool = gap_hurt - 0.5 - 0.3 * 0.7 < gap_near
		check(plain_pick.id == near_ship.id, "Without Gang Up the Attack Drone takes the nearest free ship")
		check(gang_pick.id == (hurt_ship.id if gang_wins else near_ship.id), "Gang Up: the Attack Drone joins the damaged ship already under attack")
	else:
		check(false, "Gang Up needs two ships")
		check(false, "Gang Up needs two ships")

	# ---------------- Dogfights ----------------
	start_protect(c, 1, 2, 13)
	c.contacts = c.contacts.filter(func(x): return x.get("faction", "") == "civilian")
	c.protect_drones_total = 999
	var broke := 0
	var trials := 400
	c.rng.seed = 99
	for n in range(trials):
		var r := drone_at(c, Vector3(0.0, 0.5, 0.1))
		var v := interceptor_at(c, Vector3(0.0, 0.42, 0.1), r.id)
		c._protect_drone_dogfight(r, 1.0 / 30.0)
		if r.dog_target == v.id:
			broke += 1
		c.contacts.erase(r)
		c.contacts.erase(v)
	check(absf(float(broke) / trials - 0.6) < 0.07, "About 60%% of Attack Drones break off to fight (%d of %d)" % [broke, trials])
	# Behind / in front.
	var target := drone_at(c, Vector3(0.0, 0.5, 0.1))
	target.velocity = Vector3(1.0, 0.0, 0.0)
	var chaser := interceptor_at(c, Vector3(-0.05, 0.5, 0.1), target.id)
	var front := interceptor_at(c, Vector3(0.05, 0.5, 0.1), target.id)
	check(c._protect_on_tail(chaser, target), "A Interceptor 0.05 behind a Attack Drone is on its tail")
	check(not c._protect_on_tail(front, target), "A Interceptor in front of a Attack Drone is not on its tail")
	check(not c._protect_on_tail(interceptor_at(c, Vector3(-0.09, 0.5, 0.1), target.id), target), "A Interceptor 0.09 behind is out of Tail Range (0.07)")
	# Hits only from behind.
	var hits_before: int = target.interceptor_hits
	var removed: Array[String] = []
	front.drone_fire_remaining = 0.0
	c._protect_interceptor_dogfight(front, target, 0.0, removed)
	check(target.interceptor_hits == hits_before, "No hit from in front")
	c._play_protect_sound("interceptor_hit")
	var ticks: int = int(c.protect_sound_counts.get("interceptor_hit", 0))
	target.interceptor_hits = 3
	chaser.drone_fire_remaining = 0.0
	c._protect_interceptor_dogfight(chaser, target, 0.0, removed)
	check(target.interceptor_hits == 2, "A hit from behind")
	check(int(c.protect_sound_counts.get("interceptor_hit", 0)) == ticks + 1, "Each Interceptor hit plays the tick")
	check(chaser.drone_fire_remaining > 0.0, "Then the Interceptor waits its fire interval")
	c.contacts = c.contacts.filter(func(x): return x.get("faction", "") == "civilian")
	# Attack Drone shots down a Interceptor; counted in INTERCEPTORS LOST and the readout.
	var hunter := drone_at(c, Vector3(-0.05, 0.5, 0.1))
	var prey := interceptor_at(c, Vector3(0.0, 0.5, 0.1), "")
	prey.velocity = Vector3(1.0, 0.0, 0.0)
	hunter.dog_target = prey.id
	hunter.dog_decided = true
	hunter.shot_timer = 0.0
	c.protect_interceptor_loss_chance = 1.0
	var lost_before: int = c.interceptors_lost
	var fire_before: int = c.protect_interceptors_lost_to_fire
	c._protect_drone_dogfight(hunter, 0.0)
	check(c.find_contact(prey.id).is_empty(), "A Attack Drone behind a Interceptor can shoot it down")
	check(c.interceptors_lost == lost_before + 1, "Dogfight loss counts in INTERCEPTORS LOST at once")
	check(console.readout_text().contains("INTERCEPTORS LOST  %d" % c.interceptors_lost), "Battle readout shows INTERCEPTORS LOST %d" % c.interceptors_lost)
	check(c.protect_interceptors_lost_to_fire == fire_before + 1 and c.protect_dogfight_interceptors_lost >= 1, "Counted as a Interceptor lost to Attack Drone fire this round")
	check(not hunter.return_fire_done, "The 1.2.3 return-fire roll is not used with dogfights")
	check(int(c.protect_sound_counts.get("interceptor_lost", 0)) >= 1, "Interceptor lost in a dogfight plays the fighter-lost boom")
	c.protect_interceptor_loss_chance = 0.07
	# A Attack Drone that presses on keeps attacking the ship.
	var presser := drone_at(c, Vector3(0.0, 0.5, 0.1))
	presser.dog_decided = true
	presser.presses = true
	interceptor_at(c, Vector3(0.0, 0.45, 0.1), presser.id)
	check(c._protect_drone_dogfight(presser, 1.0 / 30.0) == false and presser.dog_target == "", "A Attack Drone that presses on keeps attacking the ship")
	# Help.
	c.contacts = c.contacts.filter(func(x): return x.get("faction", "") == "civilian")
	c.protect_help_chance = 1.0
	var fighter_r := drone_at(c, Vector3(0.0, 0.5, 0.1))
	var wing := drone_at(c, Vector3(0.1, 0.5, 0.1))
	var hunter_v := interceptor_at(c, Vector3(0.0, 0.45, 0.1), fighter_r.id)
	wing.help_t = 0.0
	c._protect_drone_dogfight(wing, 0.0)
	check(wing.dog_target == hunter_v.id, "Attack Drone wingman help: a nearby Attack Drone goes after the Interceptor")
	c.protect_help_chance = 0.3
	c.protect_help_chance = 0.3

	# ---------------- Interceptors stay out all round ----------------
	start_protect(c, 1, 2, 14)
	c.launch_interceptors()
	var out := []
	for x in c.contacts:
		if x.kind == "interceptor":
			out.append(x)
	for v in out:
		v.age = c.sortie_seconds + 5.0
	c._update_interceptors(1.0 / 30.0)
	var all_out := not out.is_empty()
	for v in out:
		all_out = all_out and v.phase != "return"
	check(all_out, "In the round Interceptors stay out past their sortie time")
	c._end_protect("TIME")
	var all_home := true
	var leftovers := 0
	for x in c.contacts:
		if x.kind == "interceptor":
			all_home = all_home and x.phase == "return"
		else:
			leftovers += 1
	check(all_home, "When the round ends the Interceptors fly home")
	check(leftovers == 0, "Nothing else is left after the round (no ships, Attack Drones or repair Gunship)")
	fresh(c, 1)
	var main_interceptor := interceptor_at(c, Vector3(0.0, 0.3, 0.1), "")
	main_interceptor.age = c.sortie_seconds + 1.0
	c._update_interceptors(1.0 / 30.0)
	check(main_interceptor.phase == "return", "Main game: Interceptors still return after their sortie time")

	# ---------------- Smarter ships ----------------
	start_protect(c, 1, 2, 15)
	c.contacts = c.contacts.filter(func(x): return x.get("faction", "") == "civilian")
	c.protect_drones_total = 999
	c.protect_drones_spawned = 999
	ships = civilians(c)
	var ship: Dictionary = ships[0]
	ship.hull = 0.4
	for i in range(int(2.9 * 30)):
		c._update_protect_extras(1.0 / 30.0)
	check(is_equal_approx(ship.hull, 0.4), "No repair in the first 3 s without an attacker")
	for i in range(30 * 2):
		c._update_protect_extras(1.0 / 30.0)
	check(ship.hull > 0.4 and ship.hull < 0.4 + 0.04 * 2.2, "Self-repair at about 4%%/s (%.3f)" % ship.hull)
	for i in range(30 * 20):
		c._update_protect_extras(1.0 / 30.0)
	check(is_equal_approx(ship.hull, 0.75), "Self-repair stops at 75%% (%.3f)" % ship.hull)
	ship.hull = 0.4
	ship.calm = 10.0
	var biter := drone_at(c, ship.position + Vector3(0.02, 0.0, 0.0))
	biter.civ_target = ship.id
	c._update_protect_extras(1.0 / 30.0)
	check(is_equal_approx(ship.hull, 0.4) and ship.calm == 0.0, "No self-repair while a Attack Drone attacks")
	c.contacts.erase(biter)
	var large: Dictionary = {}
	for x in civilians(c):
		if c.civilian_size_class(x.kind) == "large":
			large = x
	if large.is_empty():
		large = ship
		large.kind = "civilian_c"
	var was: Vector3 = large.position
	drone_at(c, large.position + Vector3(0.05, 0.05, 0.0))
	c._update_civilian_evasion(0.5)
	check(large.position.distance_to(was) > 0.005 and large.position.distance_to(was) < 0.02, "Large ships drift slowly away (%.4f in 0.5 s)" % large.position.distance_to(was))

	# ---------------- Repair Tender ----------------
	c.protect_gunship_chance = 1.0
	c.protect_hard_gunship_chance = 1.0  # 0.1.2: Hard has its own chance
	start_protect(c, 1, 3, 16)
	check(not c.repair_tender().is_empty(), "Normal set 3 (3 challenges): repair Gunship launched at chance 1")
	start_protect(c, 1, 2, 16)
	check(c.repair_tender().is_empty(), "Normal set 2: no repair Gunship")
	start_protect(c, 2, 1, 16)
	check(not c.repair_tender().is_empty(), "Hard set 1 (2 challenges): repair Gunship")
	start_protect(c, 0, 3, 16)
	check(not c.repair_tender().is_empty(), "Easy set 3 (2 challenges): repair Gunship")
	start_protect(c, 0, 2, 16)
	check(c.repair_tender().is_empty(), "Easy set 2 (1 challenge): no repair Gunship")
	c.protect_gunship_chance = 0.5
	c.protect_hard_gunship_chance = 0.5  # 0.1.2: Hard has its own chance
	var got := 0
	for n in range(100):
		start_protect(c, 1, 3, 500 + n)
		if not c.repair_tender().is_empty():
			got += 1
	check(got > 35 and got < 65, "Repair Tender in about half of eligible rounds (%d of 100)" % got)
	c.protect_gunship_chance = 1.0
	c.protect_hard_gunship_chance = 1.0  # 0.1.2: Hard has its own chance
	start_protect(c, 1, 3, 17)
	c.contacts = c.contacts.filter(func(x): return x.get("faction", "") == "civilian" or x.get("phase", "") == "protect_repair")
	c.protect_drones_total = 999
	c.protect_drones_spawned = 999
	c.civilian_self_repair = false
	ships = civilians(c)
	ships[0].hull = 0.3
	ships[1].hull = 0.6
	var gunship: Dictionary = c.repair_tender()
	var gunships_lost_before: int = c.gunships_lost
	console._process(0.0)
	var header: Label = console.get_node("HeaderMetrics/Gunships/Value")
	check(header.text == "0 / 0", "GUNSHIPS readout shows 0 / 0 with the repair Gunship out (%s)" % header.text)
	check(c.count_kind("gunship") == 1 and c.player_gunship_count() == 0, "The repair Gunship is not one of the player's Gunships")
	var first_target := ""
	for i in range(30 * 40):
		c._update_protect_extras(1.0 / 30.0)
		c._update_gunships(1.0 / 30.0)
		if first_target.is_empty() and not String(gunship.get("target_id", "")).is_empty():
			first_target = gunship.target_id
	check(first_target == ships[0].id, "The Gunship goes to the most damaged ship first")
	check(ships[0].hull >= 0.98 and ships[1].hull >= 0.98, "It repairs ships up to 100%%, then the next (%.2f, %.2f)" % [ships[0].hull, ships[1].hull])
	check(c.gunships_lost == gunships_lost_before and not c.find_contact(gunship.id).is_empty(), "Normal Gunship code leaves it alone")
	c._end_protect("TIME")
	check(c.repair_tender().is_empty() and c.count_kind("gunship") == 0, "The repair Gunship leaves when the round ends")
	c.civilian_self_repair = true
	c.protect_gunship_chance = 0.5
	c.protect_hard_gunship_chance = 0.5  # 0.1.2: Hard has its own chance

	# ---------------- Damaged ships: colour, flash, hull bar ----------------
	start_protect(c, 1, 1, 18)
	ships = civilians(c)
	ship = ships[0]
	ship.hull = 0.5
	ship.flash_t = 0.0
	check(c.civilian_display_color(ship).is_equal_approx(c.civilian_color), "A damaged ship keeps Civilian Color")
	ship.flash_t = 0.15
	var flash_col: Color = c.civilian_display_color(ship)
	check(flash_col.r > c.civilian_color.r and flash_col.g >= c.civilian_color.g and flash_col.b >= c.civilian_color.b - 0.001, "A hit flashes the ship white")
	c._update_protect_extras(0.2)
	check(ship.flash_t == 0.0, "The flash is over after 0.15 s")
	c.civilian_hull_bar = false
	ship.flash_t = 0.0
	check(c.civilian_display_color(ship).is_equal_approx(c.civilian_damaged_color.lerp(c.civilian_color, 0.5)), "Hull Bar off: the 1.2.8 fade to Damaged Color")
	c.civilian_hull_bar = true
	var bar: Rect2 = c._civilian_hull_bar_rect(1.0, Vector2(100, 200), Vector2(40, 12))
	check(is_equal_approx(bar.size.x, c.civilian_hull_bar_width) and bar.position.y > 200.0, "The hull bar sits under the label")
	check(is_equal_approx(bar.get_center().x, 120.0), "The hull bar is centred on the label")
	var r_hit := drone_at(c, ship.position + Vector3(0.01, 0.0, 0.0))
	r_hit.civ_target = ship.id
	r_hit.attack_cooldown = 0.0
	ship.flash_t = 0.0
	c._update_protect_drone(r_hit, 1.0 / 30.0)
	check(ship.flash_t > 0.0, "A Attack Drone hit starts the flash")

	# ---------------- Round counter ----------------
	start_protect(c, 1, 2, 19)
	var rows: Array = frame.protect_counter_rows()
	check(rows.size() == (4 if c.protect_breachers_total > 0 else 3), "Round counter has three rows (four with a Breacher)")
	check(rows[0][0] == "SHIPS" and rows[0][1] == "%d OF %d" % [c.civilians_left(), c.protect_civilians_total], "SHIPS n OF m (%s)" % rows[0][1])
	check(rows[1][0] == "DRONES" and rows[1][1] == "%d LEFT" % c.protect_drones_total, "DRONES n LEFT (%s)" % rows[1][1])
	var secs := ceili(c.protect_round_seconds)
	check(rows[2][0] == "TIME" and rows[2][1] == "%d:%02d" % [floori(secs / 60.0), secs % 60], "TIME m:ss (%s)" % rows[2][1])
	check(rows[0][2] == c.civilian_color, "SHIPS in Civilian Color")
	check(rows[1][2].r > 0.9 and rows[1][2].g < 0.5, "ATTACK DRONES in red")
	c.protect_elapsed = c.protect_round_seconds - 61.2
	check(frame.protect_counter_rows()[2][1] == "1:02", "TIME counts down (1:02)")

	# ---------------- Round sounds ----------------
	start_protect(c, 1, 3, 20)
	check(is_instance_valid(c.protect_tick_player) and is_instance_valid(c.protect_attacked_player)
		and is_instance_valid(c.protect_critical_player) and is_instance_valid(c.protect_medium_boom_player), "Round sound players are made")
	c.protect_sound_counts.clear()
	ships = civilians(c)
	ship = ships[0]
	var attacker := drone_at(c, ship.position + Vector3(0.01, 0.0, 0.0))
	attacker.civ_target = ship.id
	attacker.attack_cooldown = 0.0
	c._update_protect_drone(attacker, 1.0 / 30.0)
	attacker.attack_cooldown = 0.0
	c._update_protect_drone(attacker, 1.0 / 30.0)
	check(int(c.protect_sound_counts.get("ship_attacked", 0)) == 1, "Ship attacked plays once, on the first attack")
	check(is_equal_approx(c.protect_attacked_player.volume_db, -14.0), "Ship attacked at -14 dB")
	ship.hull = 0.27
	c._damage_civilian(ship, 0.03)
	c._damage_civilian(ship, 0.01)
	check(int(c.protect_sound_counts.get("ship_critical", 0)) == 1, "Ship critical plays once at 25%")
	check(is_equal_approx(c.protect_critical_player.volume_db, -12.0), "Ship critical at -12 dB")
	var sizes := {"civilian_b": ["small_ship_lost", c.heavy_boom_player, -14.0], "civilian_a": ["medium_ship_lost", c.protect_medium_boom_player, -11.0],
		"civilian_c": ["large_ship_lost", c.capital_boom_player, -8.0]}
	for kind in sizes:
		start_protect(c, 1, 3, 21)
		c.protect_sound_counts.clear()
		c.last_boom.clear()
		var victim: Dictionary = civilians(c)[0]
		victim.kind = kind
		c._damage_civilian(victim, 2.0)
		check(int(c.protect_sound_counts.get(sizes[kind][0], 0)) == 1, "%s lost plays the %s" % [kind, sizes[kind][0]])
		check(is_equal_approx(sizes[kind][1].volume_db, sizes[kind][2]), "%s at %d dB" % [sizes[kind][0], sizes[kind][2]])
	start_protect(c, 1, 3, 22)
	c.protect_sound_counts.clear()
	c.last_boom.clear()
	var kill := drone_at(c, Vector3(0.0, 0.5, 0.1))
	c._award_destroyed(kill)
	check(int(c.protect_sound_counts.get("drone_kill", 0)) == 1 and is_equal_approx(c.craft_boom_player.volume_db, -13.0), "Attack Drone kill: craft boom at -13 dB")
	c.protect_round_sounds = false
	c.protect_sound_counts.clear()
	c.last_boom.clear()
	c._award_destroyed(drone_at(c, Vector3(0.1, 0.5, 0.1)))
	check(c.protect_sound_counts.is_empty() and is_equal_approx(c.craft_boom_player.volume_db, c.craft_boom_volume_db), "Round Sounds off: the 1.2.8 craft boom")
	c.protect_round_sounds = true
	fresh(c, 1)
	c.protect_sound_counts.clear()
	c._play_protect_sound("interceptor_hit")
	check(c.protect_sound_counts.is_empty() and not c._play_protect_boom("craft"), "Main game: no round sounds")
	var PA = load("res://scripts/ProtectAudio.gd")
	for maker in ["make_interceptor_hit_tick", "make_ship_attacked", "make_ship_critical", "make_medium_ship_boom"]:
		var s1: AudioStreamWAV = PA.call(maker)
		var s2: AudioStreamWAV = PA.call(maker)
		check(s1.data.size() > 1000 and s1.data == s2.data, "%s: original PCM, the same every time (%d bytes)" % [maker, s1.data.size()])

	# ---------------- Labels ----------------
	start_protect(c, 1, 2, 23)
	c._protect_label_rects.clear()
	var first: Vector2 = c._protect_place_label(Vector2(100, 100), Vector2(40, 12))
	var second: Vector2 = c._protect_place_label(Vector2(105, 100), Vector2(40, 12))
	check(first == Vector2(100, 100), "First label stays put")
	check(second.y > 100.0 and is_equal_approx(second.x, 105.0), "An overlapping label moves down a line")
	c._protect_place_label(Vector2(105, 100), Vector2(40, 12))
	var fourth: Vector2 = c._protect_place_label(Vector2(105, 100), Vector2(40, 12))
	check(not fourth.is_finite(), "With no clear place the label is left out")
	var font := ThemeDB.fallback_font
	c._protect_reserve_labels(font)
	check(c._protect_label_rects.size() == civilians(c).size(), "Civilian labels and hull bars are reserved first")
	fresh(c, 1)
	c._protect_reserve_labels(font)
	check(c._protect_label_rects.is_empty(), "Main game: labels are not moved")

	# ---------------- Main game untouched by the switches ----------------
	fresh(c, 1)
	check(c.player_gunship_count() == c.count_kind("gunship"), "Main game: GUNSHIPS readout counts every Gunship")
	check(c.protect_challenges.is_empty() and c.protect_short_interceptors == 0, "Main game: no challenge state")

	# ---------------- Full rounds run cleanly ----------------
	for level in [0, 1, 2]:
		for sets in [1, 3]:
			start_protect(c, level, sets, 40 + level * 3 + sets)
			var tt := 0.0
			var press := 0.0
			while c.wave_phase == "protect" and tt < 80.0:
				press -= 1.0 / 30.0
				if press <= 0.0:
					c.launch_interceptors()
					press = 2.0
				c._process(1.0 / 30.0)
				tt += 1.0 / 30.0
			check(c.wave_phase != "protect", "Difficulty %d set %d: round ends (%s, %.0f s, saved %d of %d)" % [level, sets, c.protect_end_reason, tt, c.protect_saved, c.protect_civilians_total])
			var left_over := 0
			for x in c.contacts:
				if not (Icons_is_interceptor(x.kind) and x.phase == "return"):
					left_over += 1
			check(left_over == 0, "Difficulty %d set %d: only Interceptors heading home remain" % [level, sets])

	# 0.1.2 replaces the former three-ring display; combat assertions above stay.
	# Detailed motion, hinge and audio assertions now live in test_rebrand.gd.
	check(not dome.three_rings_enabled and dome.ring_count == 2, "Two-ring rebrand, no legacy three-ring mode")
	check(is_equal_approx(dome.STELLAR_CYCLE, 3.25), "Approved 3.25-second ring cycle")
	check(is_equal_approx(dome.STELLAR_SWEEP, 1.2), "Approved 1.20-second sweeps")
	check(is_equal_approx(dome.STELLAR_SECOND_START, 0.672), "Second starts at 56% of the first sweep (1.0.3)")
	check(is_equal_approx(dome.ripple_period_seconds, 6.0) and dome.ripple_count == 3, "Background ripples unchanged")
	check(dome.ring_color.is_equal_approx(Color(0.3254902, 0.34117648, 1, 1)) and is_equal_approx(dome.ring_thickness, 0.4), "Thin quiet ring core colour and width retained")

	print("V129_RESULT checks=%d failures=%d" % [checks, failures])
	for p in console.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	console.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)

func Icons_is_interceptor(kind: String) -> bool:
	return kind in ["interceptor", "interceptor_squadron", "stealth_interceptor"]
