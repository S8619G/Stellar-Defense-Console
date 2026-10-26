extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.2.3: tougher Protect the fleet Attack Drones (more Interceptor hits by
## set, return fire at Interceptors, faster arrival, faster civilian kills by set) and ship
## missiles that go after hacking Breachers right after incoming nukes.
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
func near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps
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
	c.auto_defense_battery = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.reset_battle()
	c.pending.clear()
	c.contacts.clear()
	c.safe_remaining = 0.0
## Start of a Protect the fleet round after `sets` completed sets.
func start_protect(c: Control, level: int, sets: int = 1, seed_value: int = 7) -> void:
	fresh(c, level)
	c.rng.seed = seed_value
	c.sets_completed = sets
	c.wave = sets * 5
	c.wave_phase = "rest"
	c.wave_next_phase = "protect"
	c.safe_remaining = 0.0
	c._start_protect()
func protect_drones(c: Control) -> Array:
	var list: Array = []
	for x in c.contacts:
		if x.get("phase", "") == "protect":
			list.append(x)
	return list
func civilians(c: Control) -> Array:
	var list: Array = []
	for x in c.contacts:
		if x.get("faction", "") == "civilian":
			list.append(x)
	return list
## One Interceptor parked on a Attack Drone; returns the number of Interceptor hits until it is destroyed (-1 = Interceptor lost).
func hits_to_kill(c: Control, drone: Dictionary) -> int:
	c.interceptor_waits.clear()
	c.interceptor_waits.clear()
	# Interceptors hold a central screen (they ignore Attack Drones high on the scope): meet it low.
	drone.position = Vector3(clampf(drone.position.x, -0.3, 0.3), -0.1, 0.0)
	var v: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.phase = "intercept"
	var hits := 0
	for step in range(40):
		if c.find_contact(drone.id).is_empty():
			return hits
		if c.find_contact(v.id).is_empty():
			return -1
		v.position = drone.position
		v.target_id = drone.id
		v.age = 0.0
		v.drone_fire_remaining = 0.0
		var before := int(drone.get("interceptor_hits", c.drone_interceptor_hits))
		c._update_interceptors(0.05)
		if c.find_contact(drone.id).is_empty() or int(drone.get("interceptor_hits", c.drone_interceptor_hits)) < before:
			hits += 1
	return hits
func hacking_heavy(c: Control, b: Dictionary) -> Dictionary:
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	h.position = h.hack_point
	c._update_breachers(0.0)
	return h

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://test_v123_scores.json"
	console.settings_file = "user://test_v123.cfg"
	console.quit_dry_run = true
	console.shell_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	# 1.2.9: this test checks the 1.2.8 Protect the fleet round, so the 1.2.9 round
	# switches the scene turns on are set back to their script defaults (the 1.2.8 round).
	# test_v129_features.gd checks the 1.2.9 values.
	for key in ["protect_round_sounds", "civilian_hull_bar", "protect_round_counter", "protect_challenge_mix", "protect_dogfights",
			"protect_interceptors_stay_out", "protect_label_declutter", "civilian_self_repair", "protect_repair_tender"]:
		c.set(key, false)
	c.civilian_large_evade_speed = 0.0
	c.protect_extra_drones = 0
	c.protect_later_kill_time_factor = 1.0
	root.add_child(console)
	# 1.2.5: these checks pin the 1.2.4 round, which the four 1.2.5 switches (off) still give.
	# test_v125_features checks the round with the switches on.
	c.civilian_size_toughness = false
	c.civilian_evasion = false
	c.protect_patrol_interceptors = 0
	c.protect_jump_in_hold = 0.0
	c.set_process(false)
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	c.auto_spawn = true

	# --- Version ---
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 0.1.2")
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.1", "Version text reads STELLAR DEFENSE CONSOLE 1.1.1")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Mac.zip")
		and presets.get_value("preset.1.options", "application/version", "") == "1.1.1", "Export presets name 0.1.2 files")

	# --- Defaults ---
	check(c.protect_drone_interceptor_hits == 4 and c.protect_drone_hits_step == 1 and c.protect_drone_hits_cap == 6, "Round Attack Drones: 4 Interceptor hits, +1 per set, cap 6")
	check(near(c.protect_return_fire_chance, 0.1667), "Return fire: about 1 in 6 engagements")
	check(c.protect_drone_group_size == 3 and near(c.protect_drone_group_gap, 1.0), "Attack Drones arrive 3 at a time, 1 s apart (was 2, 1.5 s)")
	check(near(c.protect_kill_time_step, 0.1) and near(c.protect_kill_time_floor, 10.0), "Kill time 10% shorter per set, 10 s floor")
	check(c.ship_missiles_target_hacking, "Ship missiles target hacking Breachers")
	check(c.drone_interceptor_hits == 2, "Normal-wave Attack Drones still take 2 Interceptor hits")
	check(c.max_interceptors == 6 and c.protect_drones_cap == 12, "Interceptor cap rule unchanged (one launch per Attack Drone)")

	# --- Attack Drone toughness by set ---
	var by_set: Array[int] = []
	for sets in range(1, 7):
		c.sets_completed = sets
		by_set.append(c.protect_drone_hits())
	check(by_set == [4, 5, 6, 6, 6, 6], "Interceptor hits by set: %s" % str(by_set))
	for level in [0, 1, 2]:
		start_protect(c, level, 2)
		c._update_protect(0.0)
		var r: Dictionary = protect_drones(c)[0]
		check(int(r.interceptor_hits) == 5, "Level %d, after set 2: a round Attack Drone takes 5 hits" % level)
	c.protect_return_fire_chance = 0.0
	start_protect(c, 1, 1)
	c._update_protect(0.0)
	check(hits_to_kill(c, protect_drones(c)[0]) == 4, "After set 1: 4 Interceptor hits destroy a round Attack Drone")
	start_protect(c, 1, 3)
	c._update_protect(0.0)
	check(hits_to_kill(c, protect_drones(c)[0]) == 6, "After set 3: 6 Interceptor hits")
	start_protect(c, 1, 1)
	c._update_protect(0.0)
	var score0: int = c.score
	hits_to_kill(c, protect_drones(c)[0])
	check(c.protect_drones_destroyed == 1 and c.score - score0 == c.points_for(c.fighter_points), "A round Attack Drone scores once, at the last hit")
	# Normal waves keep 2 hits, even with the round values raised.
	c.auto_spawn = false
	fresh(c, 1)
	var b := base(c)
	var wr: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	c.auto_spawn = true
	var wr_hits := hits_to_kill(c, wr)
	check(wr_hits == 2, "A normal-wave Attack Drone still takes 2 Interceptor hits")
	c.drone_interceptor_hits = 1
	start_protect(c, 1, 1)
	c._update_protect(0.0)
	check(hits_to_kill(c, protect_drones(c)[0]) == 4, "Round Attack Drones keep their own hits when Attack Drone Interceptor Hits is 1")
	c.drone_interceptor_hits = 2

	# --- Return fire ---
	c.protect_return_fire_chance = 1.0
	start_protect(c, 1, 1)
	c._update_protect(0.0)
	var target: Dictionary = protect_drones(c)[0]
	var lost0: int = c.interceptors_lost
	check(hits_to_kill(c, target) == -1, "Return fire on: the engaging Interceptor is lost")
	check(c.interceptors_lost == lost0 + 1 and c.protect_interceptors_lost_to_fire == 1 and c.fighter_losses_by.drone >= 1, "Counted as a Interceptor lost to a Attack Drone")
	check(int(target.interceptor_hits) == 4 and not c.find_contact(target.id).is_empty(), "The Attack Drone is undamaged")
	check(c.status_message.begins_with("INTERCEPTOR LOST TO ATTACK DRONE RETURN FIRE"), "Status names the return fire")
	# One roll per Attack Drone: a second Interceptor on the same Attack Drone is never fired on.
	c.protect_return_fire_chance = 0.0
	start_protect(c, 1, 1)
	c._update_protect(0.0)
	var pr: Dictionary = protect_drones(c)[0]
	pr.position = Vector3(0.0, -0.1, 0.0)
	var v1: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	v1.phase = "intercept"
	v1.position = pr.position
	v1.target_id = pr.id
	c._update_interceptors(0.05)
	c.protect_return_fire_chance = 1.0
	for i in range(3):
		v1.position = pr.position
		v1.drone_fire_remaining = 0.0
		c._update_interceptors(0.05)
	check(not c.find_contact(v1.id).is_empty() and int(pr.interceptor_hits) <= 1, "Rolled once per Attack Drone: a Interceptor that survived the roll keeps fighting that Attack Drone")
	start_protect(c, 1, 1)
	c._update_protect(0.0)
	c.protect_return_fire_chance = 0.0
	var pr2: Dictionary = protect_drones(c)[0]
	pr2.position = Vector3(0.0, -0.1, 0.0)
	var va: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	va.phase = "intercept"
	va.position = pr2.position
	c._update_interceptors(0.05)
	c._remove_contact(va.id)
	c.protect_return_fire_chance = 1.0
	var vb: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	vb.phase = "intercept"
	vb.position = pr2.position
	c._update_interceptors(0.05)
	check(not c.find_contact(vb.id).is_empty() and c.protect_interceptors_lost_to_fire == 0, "A second Interceptor on an already-rolled Attack Drone is not fired on")
	# Rate over many pairs.
	c.protect_return_fire_chance = 0.1667
	var pairs := 0
	var losses := 0
	for n in range(40):
		start_protect(c, 1, 1, 100 + n)
		c._update_protect(0.0)
		for drone in protect_drones(c):
			var lost_before: int = c.protect_interceptors_lost_to_fire
			hits_to_kill(c, drone)
			pairs += 1
			losses += c.protect_interceptors_lost_to_fire - lost_before
	var rate := float(losses) / float(pairs)
	check(rate > 0.10 and rate < 0.24, "About 1 Interceptor lost per 6 Attack Drones engaged (%d of %d, %.3f)" % [losses, pairs, rate])
	# No return fire outside the round.
	c.protect_return_fire_chance = 1.0
	c.auto_spawn = false
	fresh(c, 1)
	b = base(c)
	wr = c.find_contact(c.spawn_from_carrier("drone", b.id))
	c.auto_spawn = true
	check(hits_to_kill(c, wr) == 2 and c.interceptors_lost == 0, "No return fire from normal-wave Attack Drones")
	c.protect_return_fire_chance = 0.0
	start_protect(c, 1, 1)
	c._update_protect(0.0)
	check(hits_to_kill(c, protect_drones(c)[0]) == 4 and c.interceptors_lost == 0, "Return Fire Chance 0 turns it off")
	c.protect_return_fire_chance = 0.1667

	# --- Faster arrival ---
	start_protect(c, 1, 2)
	check(c.protect_drones_total == 6, "Normal, after set 2: 6 Attack Drones")
	c._update_protect(0.0)
	check(c.protect_drones_spawned == 3 and protect_drones(c).size() == 3, "Attack Drones arrive 3 at a time")
	c._update_protect(0.9)
	check(c.protect_drones_spawned == 3, "No second group before 1 s")
	c._update_protect(0.11)
	check(c.protect_drones_spawned == 6, "Second group 1 s later: all 6 in")

	# --- Faster civilian kills by set ---
	var expect := {0: [26.0, 23.4, 20.8, 18.2, 15.6, 13.0, 10.4, 10.0], 1: [20.0, 18.0, 16.0, 14.0, 12.0, 10.0, 10.0, 10.0], 2: [14.0, 12.6, 11.2, 10.0, 10.0, 10.0, 10.0, 10.0]}
	for level in [0, 1, 2]:
		var got: Array[float] = []
		var ok := true
		for sets in range(1, 9):
			start_protect(c, level, sets)
			got.append(snappedf(c.civilian_kill_seconds(), 0.1))
			ok = ok and near(c.civilian_kill_seconds(), expect[level][sets - 1], 0.01)
		check(ok, "Level %d kill seconds by set: %s" % [level, str(got)])
	c.hard_civilian_kill_seconds = 8.0
	start_protect(c, 2, 3)
	check(near(c.civilian_kill_seconds(), 8.0), "A kill time already below the floor is not raised")
	c.hard_civilian_kill_seconds = 14.0
	c.protect_kill_time_step = 0.0
	start_protect(c, 1, 4)
	check(near(c.civilian_kill_seconds(), 20.0), "Kill Time Step 0: the 1.2.2 kill time")
	c.protect_kill_time_step = 0.1
	# Real damage after set 3 on Normal: 16 s.
	start_protect(c, 1, 3)
	c._spawn_protect_drone(false)
	var r3: Dictionary = protect_drones(c)[0]
	var ship: Dictionary = civilians(c)[0]
	r3.civ_target = ship.id
	var t := 0.0
	while not c.find_contact(ship.id).is_empty() and t < 40.0:
		r3.position = ship.position
		c._update_protect_drone(r3, 0.1)
		t += 0.1
	check(t > 15.8 and t < 16.3, "Normal, after set 3: one Attack Drone destroys a ship in 16 s (%.1f s)" % t)

	# --- Ship missiles: nukes first, then hacking Breachers ---
	c.auto_spawn = false  # no defined-wave Breacher cap for these placements
	fresh(c, 1)
	c.own_weapons_enabled = true
	b = base(c)
	var h: Dictionary = hacking_heavy(c, b)
	var dist: float = h.position.distance_to(c.own_ship_position)
	check(h.phase == "hacking" and dist > c.ship_missile_heavy_range, "A hacking Breacher parks outside Ship Missile Heavy Range (%.3f > %.2f)" % [dist, c.ship_missile_heavy_range])
	c.ship_missiles_target_hacking = false
	c._fire_ship_missile()
	var first: Dictionary = c.find_contact(c.contacts[-1].target_id)
	check(first.kind == "carrier", "Switch off (1.2.2 behavior): the missile goes to the Enemy Carrier")
	c.contacts.pop_back()
	c.ship_missiles_target_hacking = true
	c._fire_ship_missile()
	check(c.contacts[-1].kind == "own_missile" and c.contacts[-1].target_id == h.id, "Switch on: the missile goes to the hacking Breacher")
	# One missile per remaining hit point, then the Enemy Carrier.
	var sent := 1
	while sent < int(h.health):
		c._fire_ship_missile()
		sent += 1
	c._fire_ship_missile()
	check(c._missiles_at(h.id) == int(h.health) and c.find_contact(c.contacts[-1].target_id).kind == "carrier", "One missile per remaining hit, then the Enemy Carrier")
	for x in c.contacts.duplicate():
		if x.kind == "own_missile":
			c._remove_contact(x.id)
	# Nukes in their last quarter come first.
	var nid: String = c._launch_nuclear(b)
	var nuke: Dictionary = c.find_contact(nid)
	var origin: Vector3 = nuke.position
	nuke.position = origin.lerp(c.own_ship_position, 0.5)
	c._fire_ship_missile()
	check(c.contacts[-1].target_id == h.id, "A nuke halfway in: the hacking Breacher still comes first")
	c._remove_contact(c.contacts[-1].id)
	nuke.position = origin.lerp(c.own_ship_position, 0.85)
	c._fire_ship_missile()
	check(c.contacts[-1].target_id == nid, "A nuke in its last quarter: the nuke comes first")
	for x in c.contacts.duplicate():
		if x.kind in ["own_missile", "nuke"]:
			c._remove_contact(x.id)
	# Draining before hacking; then the one closest to finishing its hack.
	var h2: Dictionary = hacking_heavy(c, base(c))
	h.hack_remaining = 4.0
	h2.hack_remaining = 1.0
	c._fire_ship_missile()
	check(c.contacts[-1].target_id == h2.id, "Two hacking: the one closest to finishing comes first")
	c._remove_contact(c.contacts[-1].id)
	h.phase = "draining"
	c._fire_ship_missile()
	check(c.contacts[-1].target_id == h.id, "A draining Breacher comes before a hacking one")
	for x in c.contacts.duplicate():
		if x.kind == "own_missile":
			c._remove_contact(x.id)
	# An approaching Breacher at the same distance is not a hacking target.
	fresh(c, 1)
	b = base(c)
	var ha: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	ha.position = ha.hack_point + Vector3(0.0, 0.02, 0.0)
	c._fire_ship_missile()
	check(ha.phase == "approach" and c.find_contact(c.contacts[-1].target_id).kind == "carrier", "An approaching Breacher outside range is not targeted (last-ditch rule kept)")
	# Full loop: the ship fires and the missile hits the hacking Breacher.
	fresh(c, 1)
	c.own_weapons_enabled = true
	b = base(c)
	h = hacking_heavy(c, b)
	var hp0 := int(h.health)
	c.own_fire_remaining = 0.0
	for step in range(240):
		c._update_own_weapons(1.0 / 30.0)
		c._update_breachers(0.0)
		if int(h.get("health", hp0)) < hp0 or c.find_contact(h.id).is_empty():
			break
	check(c.find_contact(h.id).is_empty() or int(h.health) == hp0 - 1, "In play the ship's missile reaches and hits the hacking Breacher")
	# Still no ship missiles in the round.
	c.auto_spawn = true
	start_protect(c, 1, 1)
	c._update_protect(0.0)
	c.own_fire_remaining = 0.0
	c._update_own_weapons(0.1)
	check(c.count_kind("own_missile") == 0, "No ship missiles during Protect the fleet")

	# --- A played round (Interceptors launched whenever allowed) ---
	for sets in [1, 3]:
		var durations: Array[float] = []
		var saved := 0
		var total := 0
		var fire_losses := 0
		var check_fire_ok := true
		for n in range(6):
			start_protect(c, 1, sets, 300 + n)
			var tt := 0.0
			while c.wave_phase == "protect" and tt < 70.0:
				c.launch_interceptors()
				c._process(1.0 / 30.0)
				tt += 1.0 / 30.0
			durations.append(snappedf(tt, 0.1))
			saved += c.protect_saved
			total += c.protect_civilians_total
			fire_losses += c.protect_interceptors_lost_to_fire
			check_fire_ok = check_fire_ok and c.protect_interceptors_lost_to_fire <= c.protect_drones_total
		durations.sort()
		print("V123_ROUND normal sets=%d seconds=%s saved=%d/%d interceptors_lost_to_fire=%d" % [sets, str(durations), saved, total, fire_losses])
		check(durations[-1] <= 61.0, "Normal after set %d: every played round ends by the 60 s limit" % sets)
		check(check_fire_ok, "Normal after set %d: return fire never costs more Interceptors than there are Attack Drones" % sets)

	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	print("V123_RESULT checks=%d failures=%d" % [checks, failures])
	console.free()
	await create_timer(0.3).timeout
	quit()
