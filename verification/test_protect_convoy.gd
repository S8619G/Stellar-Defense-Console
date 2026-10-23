extends SceneTree
## Stellar Defense Console 1.0.7: Protect the convoy. The round and its ships are renamed
## (Support Fleet), Attack Drones spread out and fight back when chased, a Breacher latches
## on a support ship and drains it, gunfire lines and new round sounds, the round box rows
## no longer overlap, and the Convoy Test start screen stays out of the normal builds.
const ProtectAudio = preload("res://scripts/ProtectAudio.gd")
const Picker = preload("res://scripts/ConvoyTestPicker.gd")
var failures := 0
var checks := 0
var console: Control
var c: Control
var frame: Control

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func clean(level: int) -> void:
	c.difficulty = level
	c.auto_spawn = false
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.auto_jump = false
	c.auto_rapid_repair = false
	c.reset_battle()
	c.pending.clear()
	c.contacts.clear()
	c.safe_remaining = 0.0
	c.auto_spawn = true
	c.waves_enabled = true
	c.set_process(false)

func start_protect(level: int, sets: int, seed: int) -> void:
	clean(level)
	c.rng.seed = seed
	c.sets_completed = sets
	c.wave = sets * 5
	c._start_protect()

func ships() -> Array:
	var out := []
	for k in c.contacts:
		if k.get("faction", "") == "civilian":
			out.append(k)
	return out

func drones() -> Array:
	var out := []
	for k in c.contacts:
		if k.kind == "drone" and k.get("phase", "") == "protect":
			out.append(k)
	return out

func breachers() -> Array:
	var out := []
	for k in c.contacts:
		if k.get("phase", "") == "protect_breacher":
			out.append(k)
	return out

func interceptor_at(pos: Vector3) -> Dictionary:
	var f := {"id": c._new_id("F"), "kind": "interceptor", "faction": "friendly", "position": pos,
		"start": pos, "finish": pos, "age": 0.0, "progress": 0.0, "origin_id": "", "origin_position": pos,
		"target_position": pos, "defense_checked": false, "phase": "attack", "velocity": Vector3.ZERO,
		"target_id": "", "heavy_fire_remaining": 0.0}
	c.contacts.append(f)
	return f

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://test_convoy.cfg"
	console.high_score_file = "user://test_convoy_scores.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	root.add_child(console)
	await process_frame
	console.set_process(false)
	frame = console.get_node("ConsoleFrame")

	# ---------------- Switches ----------------
	var plain = load("res://scripts/RadarContacts.gd").new()
	for name in ["protect_smart_drones", "protect_breachers", "protect_tracers", "protect_convoy_sounds", "protect_tender_smart", "protect_interceptors_lost_end"]:
		check(plain.get(name) == false, "Script default off: %s" % name)
		check(c.get(name) == true, "Console scene turns on: %s" % name)
	check(plain.get("protect_timer_end") == true and c.protect_timer_end == false, "Console scene turns off the 60 s time limit")
	plain.free()
	check(is_equal_approx(c.protect_tender_speed, 0.0805), "1.0.7.2: repair tender flies 15%% faster (%.4f)" % c.protect_tender_speed)
	check(is_equal_approx(c.protect_gunship_repair_rate, 0.1), "1.0.7.2: repairs 25%% faster (%.3f a second)" % c.protect_gunship_repair_rate)
	check(c.protect_tender_jump_in == false, "Repair tender starts beside Aegis")
	check(c.protect_breacher_count == 1 and c.hard_protect_breacher_extra == 1, "One Breacher a round, Hard adds one from set 2")
	check(is_equal_approx(c.protect_burst_loss_chance, 0.06), "Drone burst downs a chasing Interceptor 6% of the time")

	# ---------------- Names ----------------
	start_protect(1, 1, 3)
	check(c.status_message.begins_with("PROTECT THE CONVOY |") and c.status_message.contains("SUPPORT SHIPS"), "Round start line: PROTECT THE CONVOY | n SUPPORT SHIPS (%s)" % c.status_message)
	var ship: Dictionary = ships()[0]
	check(c.contact_tag(ship).begins_with("SUPPORT "), "Ship label: SUPPORT n%% (%s)" % c.contact_tag(ship))
	var all_text := FileAccess.get_file_as_string("res://scripts/RadarContacts.gd") + FileAccess.get_file_as_string("res://scripts/ConsoleFrame.gd") + FileAccess.get_file_as_string("res://scripts/RadarConsole.gd")
	check(not all_text.contains("\"PROTECT THE FLEET") and not all_text.contains("CIVILIAN %d") and not all_text.contains("\"CIVILIANS"), "No player-facing PROTECT THE FLEET or CIVILIAN text is left")
	check(all_text.contains("\"JUMP\\nHELD | PROTECT THE CONVOY\""), "Jump button: HELD | PROTECT THE CONVOY")
	check(c._end_protect.get_argument_count() >= 1, "End of round still takes a reason")

	# ---------------- Round box rows ----------------
	if frame != null:
		var rows: Array = frame.protect_counter_rows()
		check(rows.size() == 4 and rows[1][0] == "DRONES" and rows[3][0] == "BREACHER", "Round box: SHIPS, DRONES, INTERCEPTORS, BREACHER")
		check(rows[2][0] == "INTERCEPTORS" and rows[2][1] == "%d LEFT" % c.protect_interceptors_left(), "Third row: INTERCEPTORS n LEFT (%s)" % rows[2][1])
		check(rows[3][1] == "SOON", "Breacher row: SOON before it jumps in (%s)" % rows[3][1])
		var font := ThemeDB.fallback_font
		var widest := 0.0
		for row in rows:
			widest = maxf(widest, font.get_string_size(row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
		check(widest + 10.0 <= maxf(70.0, widest + 10.0), "Values start after the widest label (no overlap)")
		c.protect_breachers = false
		start_protect(1, 1, 3)
		check(frame.protect_counter_rows().size() == 3, "No Breacher in the round: three rows")
		c.protect_breachers = true
	else:
		check(false, "Round box found")

	# ---------------- Smart drones split up ----------------
	start_protect(1, 2, 21)
	c.protect_challenges.clear()
	for i in range(4):
		c._spawn_protect_drone(false)
	for d in drones():
		d.hold = 0.0
	for step in range(3):
		for d in drones():
			c._update_protect_drone(d, 1.0 / 30.0)
	var targets := {}
	for d in drones():
		targets[d.civ_target] = true
	check(targets.size() >= mini(3, ships().size()), "Four drones spread over the ships (%d different ships)" % targets.size())
	var angles := []
	for d in drones():
		angles.append(snappedf(atan2(d.start.y, d.start.x), 0.01))
	var spread_ok := true
	for i in range(angles.size()):
		for j in range(i + 1, angles.size()):
			if absf(angles[i] - angles[j]) < 0.05:
				spread_ok = false
	check(spread_ok, "Drones jump in at different points on the scope edge")

	# ---------------- Chased drone evades and fires back ----------------
	start_protect(1, 2, 22)
	c.protect_challenges.clear()
	c._spawn_protect_drone(false)
	var drone: Dictionary = drones()[0]
	drone.hold = 0.0
	var target_ship: Dictionary = ships()[0]
	drone.position = target_ship.position + Vector3(0.02, 0.0, 0.0)
	drone.civ_target = target_ship.id
	var chaser := interceptor_at(drone.position + Vector3(0.0, -0.06, 0.0))
	chaser.target_id = drone.id
	c.protect_burst_loss_chance = 0.0
	drone.burst_t = 0.0
	var hull_before: float = target_ship.hull
	c._update_protect_drone(drone, 1.0 / 30.0)
	check(drone.get("evading", false) and c.protect_evasions == 1, "A chased drone starts evading")
	check(c.protect_bursts == 1 and c.tracers.size() >= c.protect_burst_rounds, "It fires a burst back with gunfire lines (%d lines)" % c.tracers.size())
	check(not c.find_contact(chaser.id).is_empty(), "Burst Loss Chance 0: the Interceptor survives")
	var ship_now: Dictionary = c.find_contact(target_ship.id)
	check(not ship_now.is_empty() and ship_now.hull < hull_before, "While evading it still hurts the ship")
	c.protect_burst_loss_chance = 1.0
	drone.burst_t = 0.0
	chaser = c.find_contact(chaser.id)
	chaser.position = drone.position + Vector3(0.0, -0.06, 0.0)
	c._update_protect_drone(drone, 1.0 / 30.0)
	check(c.protect_burst_losses == 1 and c.find_contact(chaser.id).is_empty(), "Burst Loss Chance 1: the burst downs the Interceptor")
	c.protect_burst_loss_chance = 0.06
	c._update_tracers(0.5)
	check(c.tracers.is_empty(), "Gunfire lines fade within a fraction of a second")

	# ---------------- Breacher ----------------
	start_protect(1, 1, 30)
	check(c.protect_breachers_total == 1 and c.protect_breacher_times.size() == 1, "Normal: one Breacher in the round")
	var due: float = c.protect_breacher_times[0]
	check(due >= c.protect_breacher_delay_min and due <= c.protect_breacher_delay_max, "It jumps in %.1f s into the round" % due)
	start_protect(2, 2, 31)
	check(c.protect_breachers_total == 2, "Hard from set 2: two Breachers")
	start_protect(1, 1, 32)
	c._spawn_convoy_breacher()
	var b: Dictionary = breachers()[0]
	check(b.kind == "convoy_breacher" and b.faction == "hostile" and c.status_message.begins_with("BREACHER INBOUND"), "Breacher jumps in: BREACHER INBOUND")
	check(c.contact_tag(b) == "BREACHER", "Its label reads BREACHER")
	b.hold = 0.0
	var latched := false
	for step in range(30 * 40):
		c._update_convoy_breachers(1.0 / 30.0)
		if b.breach_state == "latched":
			latched = true
			break
	check(latched and c.protect_breacher_latches == 1, "It flies to a ship and latches on")
	check(c.status_message.begins_with("BREACHER LATCHED ON A SUPPORT SHIP"), "Status line: BREACHER LATCHED ON A SUPPORT SHIP")
	check(c.contact_tag(b) == "HULL DRAIN", "Latched label reads HULL DRAIN")
	check(int(c.protect_sound_counts.get("breacher_latch", 0)) == 1, "The latch clank plays")
	var held: Dictionary = c.find_contact(b.civ_target)
	var hull0: float = held.hull
	for step in range(30):
		c._update_convoy_breachers(1.0 / 30.0)
	held = c.find_contact(b.civ_target)
	check(held.hull < hull0 and b.position.distance_to(held.position) < 0.05, "It stays on the ship and drains its hull (%.3f -> %.3f)" % [hull0, held.hull])
	check(int(c.protect_sound_counts.get("breacher_drain", 0)) >= 1, "The drain hum plays while it is latched")
	if frame != null:
		check(frame.protect_counter_rows()[3][1] == "LATCHED", "Round box: BREACHER LATCHED")
	var expected: float = 1.0 / c.convoy_breacher_drain_seconds() * c.civilian_damage_factor(held)
	check(absf((hull0 - held.hull) - expected) < 0.02, "Drain rate: a full ship in about %d s on Normal" % int(c.convoy_breacher_drain_seconds()))
	c.difficulty = 0
	c.active_difficulty = 0
	check(is_equal_approx(c.convoy_breacher_drain_seconds(), c.protect_breacher_drain_seconds * 1.3), "Easy drains slower")
	c.active_difficulty = 2
	check(is_equal_approx(c.convoy_breacher_drain_seconds(), c.protect_breacher_drain_seconds * 0.75), "Hard drains faster")
	c.active_difficulty = 1
	# Interceptors go after it and destroy it with several hits.
	for k in c.contacts:
		if k.kind == "drone":
			k.phase = "gone"
	var hunter := interceptor_at(b.position + Vector3(0.0, -0.3, 0.0))
	var none: Array[String] = []
	var picked: Dictionary = c._hostile_target(hunter, none)
	check(not picked.is_empty() and picked.id == b.id, "An Interceptor targets the latched Breacher")
	var score0: int = c.score
	var kills0: int = int(c.kills.get("breacher", 0))
	var hits := 0
	while not c.find_contact(b.id).is_empty() and hits < 20:
		hits += 1
		if c._hit_convoy_breacher(hunter, b):
			c.contacts.erase(c.find_contact(b.id))
	check(hits == c.protect_breacher_hits, "It takes %d Interceptor hits" % c.protect_breacher_hits)
	check(c.protect_breachers_destroyed == 1 and c.score > score0 and int(c.kills.get("breacher", 0)) == kills0 + 1, "Destroyed: scored and counted as a Breacher")
	check(c.status_message == "BREACHER DESTROYED | SUPPORT SHIP FREED", "Status line: BREACHER DESTROYED | SUPPORT SHIP FREED")
	c._update_convoy_breachers(1.0 / 30.0)
	check(int(c.protect_sound_counts.get("breacher_drain", 0)) >= 1 and (not is_instance_valid(c.protect_drain_player) or not c.protect_drain_player.playing), "The drain hum stops")

	# ---------------- Round end waits for the Breacher ----------------
	start_protect(1, 1, 40)
	c.protect_drones_spawned = c.protect_drones_total
	for k in drones():
		c.contacts.erase(k)
	c.protect_elapsed = 1.0
	c._update_protect(1.0 / 30.0)
	check(c.wave_phase == "protect" and c.protect_breachers_spawned == 1, "All drones gone: the Breacher comes at once and the round goes on")
	for k in breachers():
		k.hold = 99.0
	c._update_protect(1.0 / 30.0)
	check(c.wave_phase == "protect", "The round goes on while the Breacher is here")
	for k in breachers():
		c.contacts.erase(k)
	c._update_protect(1.0 / 30.0)
	check(c.wave_phase != "protect", "Breacher destroyed too: the round ends")
	start_protect(1, 1, 41)
	c._spawn_convoy_breacher()
	c.tracers.append({"from": Vector3.ZERO, "to": Vector3.ONE, "age": 0.0, "hostile": true})
	c._end_protect("TIME")
	check(breachers().is_empty() and c.tracers.is_empty(), "Round end clears the Breacher and gunfire lines")

	# ---------------- Round end: no time limit ----------------
	start_protect(1, 1, 70)
	c._update_protect(0.0)
	c.protect_elapsed = c.protect_round_seconds + 5.0
	c._update_protect(0.01)
	check(c.wave_phase == "protect", "Past 60 s the round goes on (no time limit)")
	c.protect_elapsed = c.protect_safety_seconds
	c._update_protect(0.01)
	check(c.wave_phase != "protect" and c.protect_end_reason == "TIME", "Hidden safety limit still ends a stuck round")
	# Every Interceptor lost, none left to launch: total loss, no bonus.
	start_protect(1, 1, 71)
	c._update_protect(0.0)
	var ship_count := ships().size()
	c.protect_interceptors_launched = c.protect_interceptor_total()
	for k in c.contacts.duplicate():
		if c.Icons.is_interceptor(k.kind):
			c._remove_contact(k.id)
	check(c.protect_interceptors_left() == 0 and ship_count > 0 and c.protect_drones_left() > 0, "Set-up: no Interceptors left, ships and drones still there")
	var score_mid: int = c.score
	c._update_protect(0.01)
	check(c.wave_phase != "protect" and c.protect_end_reason == "INTERCEPTORS LOST", "All Interceptors lost: the round ends")
	check(c.protect_saved == 0 and c.protect_lost == c.protect_civilians_total and c.last_protect_bonus == 0 and c.score == score_mid, "All Interceptors lost: every support ship lost, no bonus")
	check(ships().is_empty() and c.protect_result_title() == "ALL INTERCEPTORS LOST" and c.rest_tally_lines()[1].begins_with("SUPPORT FLEET LOST"), "1.0.7.2: result reads ALL INTERCEPTORS LOST | SUPPORT FLEET LOST")
	check(c.rest_tally_lines().has("NO CONVOY BONUS"), "Result shows NO CONVOY BONUS")
	# 1.0.7.2: kills made before the total loss keep their points, and the result says so.
	start_protect(1, 1, 73)
	c._update_protect(0.0)
	c._spawn_protect_drone(false)
	var kill_score: int = c.score
	var victim: Dictionary = drones()[0]
	c._award_destroyed(victim)
	c._remove_contact(victim.id)
	var earned: int = c.score - kill_score
	check(earned > 0 and c.protect_kill_points == earned, "Drone kill in the round scores and is counted (%d)" % earned)
	c.protect_interceptors_launched = c.protect_interceptor_total()
	for k in c.contacts.duplicate():
		if c.Icons.is_interceptor(k.kind):
			c._remove_contact(k.id)
	var before_end: int = c.score
	c._update_protect(0.01)
	check(c.protect_end_reason == "INTERCEPTORS LOST" and c.score == before_end and c.last_protect_bonus == 0, "Total loss keeps the kill points, adds no bonus")
	check(c.rest_tally_lines().has("ENEMY KILLS +%d  |  NO CONVOY BONUS" % earned), "Result shows ENEMY KILLS +n | NO CONVOY BONUS")
	check(is_equal_approx(c.civilian_repair_rate, 0.02), "Support ships self-repair at 2%% a second (half the old speed)")
	# Interceptors still to launch: the round goes on.
	start_protect(1, 1, 72)
	c._update_protect(0.0)
	for k in c.contacts.duplicate():
		if c.Icons.is_interceptor(k.kind):
			c._remove_contact(k.id)
	c._update_protect(0.01)
	check(c.wave_phase == "protect" and c.protect_interceptors_left() > 0, "Interceptors still to launch: the round goes on")
	# All enemies destroyed still ends the round (with the bonus).
	c.protect_drones_spawned = c.protect_drones_total
	c.protect_breachers_spawned = c.protect_breachers_total
	for k in drones() + breachers():
		c.contacts.erase(k)
	c._update_protect(0.01)
	check(c.wave_phase != "protect" and c.protect_end_reason == "ATTACK DRONES DESTROYED" and c.last_protect_bonus > 0, "All enemies destroyed: the round ends with the bonus")

	# ---------------- Smart repair tender ----------------
	start_protect(1, 2, 80)
	var list := ships()
	check(list.size() >= 2, "Tender test: at least two ships")
	c._spawn_repair_tender()
	var tender: Dictionary = {}
	for k in c.contacts:
		if k.get("phase", "") == "protect_repair":
			tender = k
	check(tender.position.distance_to(c.own_ship_position) < 0.2, "Tender starts beside Aegis")
	var far: Dictionary = list[0]
	var hit: Dictionary = list[1]
	for k in list:
		k.hull = 1.0
	far.hull = 0.6
	hit.hull = 0.95
	tender.target_id = far.id
	tender.retarget_t = 0.0
	check(c._tender_need(tender, hit) < 0.0, "Calm ship above 90%% hull is left alone")
	# A drone attacks the other ship: the tender switches to it while flying.
	c._spawn_protect_drone(false)
	var d: Dictionary = drones()[0]
	d.hold = 0.0
	d.civ_target = hit.id
	d.position = hit.position + Vector3(0.02, 0.0, 0.0)
	hit.hull = 0.55
	far.hull = 0.9
	var pick: Dictionary = c._tender_pick(tender, far)
	check(pick.get("id", "") == hit.id, "Tender switches to the ship under attack")
	d.position = Vector3(5, 5, 0)
	hit.hull = 0.6
	far.hull = 0.55
	pick = c._tender_pick(tender, far)
	check(pick.get("id", "") == far.id, "Close call: tender keeps its ship (no flip-flop)")

	# ---------------- 1.0.7.2 repair tender ----------------
	var plain2 = load("res://scripts/RadarContacts.gd").new()
	for name in ["protect_tender_launch_when_hit", "protect_tender_stay_near", "protect_tender_hull", "protect_tender_lands"]:
		check(plain2.get(name) == false, "Script default off: %s" % name)
		check(c.get(name) == true, "Console scene turns on: %s" % name)
	check(is_equal_approx(plain2.protect_result_offset, 0.22), "Script default keeps the old result box place")
	plain2.free()
	check(is_equal_approx(c.protect_tender_launch_damage, 0.04), "Tender launches at more than 4% damage")
	var seed_found := -1
	for sd in range(200, 260):
		start_protect(2, 3, sd)
		if c.protect_tender_waiting:
			seed_found = sd
			break
	check(seed_found >= 0, "Hard round with a tender found")
	check(c.repair_tender().is_empty(), "Tender waits on your ship at the round start")
	var tlist := ships()
	for k in tlist:
		k.hull = 0.97
	c._update_protect_extras(1.0 / 60.0)
	check(c.repair_tender().is_empty() and c.protect_tender_waiting, "3% damage: tender stays home")
	tlist[0].hull = 0.95
	c._update_protect_extras(1.0 / 60.0)
	var t: Dictionary = c.repair_tender()
	check(not t.is_empty() and not c.protect_tender_waiting and c.protect_tender_launches == 1, "5% damage: tender launches")
	check(not t.is_empty() and t.position.distance_to(c.launch_origin(0.0)) < 0.05, "It launches from your ship like a Gunship")
	check(c.player_gunship_count() == 0, "The tender is not one of your Gunships")
	check(c.contact_tag(t) == "REPAIR TENDER", "Label: REPAIR TENDER (%s)" % c.contact_tag(t))
	# Idle: no ship needs repair, it stays near the fight.
	for k in tlist:
		k.hull = 1.0
	t.target_id = ""
	t.retarget_t = 0.0
	for i in 1800:
		c._update_protect_extras(1.0 / 60.0)
	var home: Vector3 = c.own_ship_position + Vector3(0.0, 0.12, 0.0)
	var wait_at: Vector3 = c._tender_wait_point(t)
	check(t.position.distance_to(wait_at) < 0.12 and t.position.distance_to(home) > 0.15, "Idle tender stays near the convoy, not by your ship (%.2f from wait point)" % t.position.distance_to(wait_at))
	# Drones attacking it wear down its hull at the biggest ship's rate.
	c._spawn_protect_drone(false)
	var td: Dictionary = drones()[0]
	td.hold = 999.0
	td.dog_target = ""
	td.position = t.position + Vector3(0.01, 0.0, 0.0)
	var h0 := float(t.hull)
	c._damage_tender(t, 1.0)
	var expect: float = 1.0 / c.civilian_kill_seconds() * c.civilian_damage_factor({"kind": "civilian_c"})
	check(absf((h0 - float(t.hull)) - expect) < 0.0001, "Tender hull drops like the biggest support ship (%.4f a second)" % expect)
	check(c.contact_tag(t).begins_with("REPAIR TENDER ") and c.contact_tag(t).ends_with("%"), "Damaged label shows its hull (%s)" % c.contact_tag(t))
	t.hull = 0.001
	check(c._damage_tender(t, 1.0) and c.repair_tender().is_empty(), "At zero hull the tender is destroyed")
	check(c.status_message.begins_with("REPAIR TENDER LOST") and c.protect_tenders_lost == 1, "Status line: REPAIR TENDER LOST")
	tlist[0].hull = 0.5
	for i in 60:
		c._update_protect_extras(1.0 / 60.0)
	check(c.repair_tender().is_empty(), "Destroyed tender is gone for the round")
	check(c.gunships_lost == 0, "A lost tender is not a lost Gunship")
	# A surviving tender lands after the round.
	start_protect(2, 3, seed_found)
	for k in ships():
		k.hull = 0.9
	c._update_protect_extras(1.0 / 60.0)
	t = c.repair_tender()
	t.position = Vector3(0.0, 0.3, 0.03)
	c._end_protect("ATTACK DRONES DESTROYED")
	var back: Dictionary = c.find_contact(t.id)
	check(not back.is_empty() and back.phase == "tender_return", "Round over: the tender flies home")
	var steps := 0
	while not c.find_contact(t.id).is_empty() and steps < 2000:
		c._update_tender_return(1.0 / 60.0)
		steps += 1
	check(c.find_contact(t.id).is_empty() and c.protect_tenders_landed == 1, "It lands on your ship (%.1f s)" % (steps / 60.0))
	# Older rule kept when the switch is off.
	c.protect_tender_launch_when_hit = false
	var old_found := false
	for sd in range(200, 260):
		start_protect(2, 3, sd)
		if not c.repair_tender().is_empty():
			old_found = true
			break
	check(old_found and not c.protect_tender_waiting, "Launch When Hit off: tender starts with the round")
	c.protect_tender_launch_when_hit = true
	# Result box: ALL INTERCEPTORS LOST title, moved to the top of the scope.
	start_protect(1, 2, 70)
	c._end_protect("INTERCEPTORS LOST")
	check(c.protect_result_title() == "ALL INTERCEPTORS LOST", "Total loss title: ALL INTERCEPTORS LOST (%s)" % c.protect_result_title())
	var rlines: Array[String] = c.rest_tally_lines()
	check(rlines.size() > 1 and rlines[0] == "ALL INTERCEPTORS LOST" and rlines[1].begins_with("SUPPORT FLEET LOST"), "Box: ALL INTERCEPTORS LOST over SUPPORT FLEET LOST (%s)" % ", ".join(rlines.slice(0, 2)))
	var rect: Rect2 = c.protect_result_rect(c.protect_result_rows(rlines))
	var radius: float = console.get_node("CenterContainer/Dome").sphere_radius
	check(is_equal_approx(c.protect_result_offset, -0.48) and rect.position.y < c.size.y * 0.5 - radius * 0.4, "Result box moved up to the top part of the scope (top %.0f)" % rect.position.y)
	start_protect(1, 2, 71)
	for k in ships():
		c.contacts.erase(k)
	c._end_protect("SUPPORT FLEET LOST")
	check(c.protect_result_title() == "SUPPORT FLEET LOST", "Ships all lost: title stays SUPPORT FLEET LOST")

	# ---------------- Sounds ----------------
	var rapid: AudioStreamWAV = ProtectAudio.make_rapid_fire()
	var latch: AudioStreamWAV = ProtectAudio.make_breacher_latch()
	var drain: AudioStreamWAV = ProtectAudio.make_breacher_drain()
	check(absf(rapid.get_length() - 0.34) < 0.02 and absf(latch.get_length() - 0.6) < 0.02, "Rapid fire 0.34 s, latch 0.6 s")
	check(drain.loop_mode == AudioStreamWAV.LOOP_FORWARD and absf(drain.get_length() - 1.0) < 0.02, "Drain hum is a 1 s loop")
	start_protect(1, 1, 50)
	c.protect_last_rapid_at = -100.0
	var n0 := int(c.protect_sound_counts.get("rapid_fire", 0))
	c._play_protect_sound("rapid_fire")
	var n1 := int(c.protect_sound_counts.get("rapid_fire", 0))
	c._play_protect_sound("rapid_fire")
	check(n1 == n0 + 1 and int(c.protect_sound_counts.get("rapid_fire", 0)) == n1, "Rapid fire is limited to about four bursts a second")
	c.protect_convoy_sounds = false
	c.battle_time += 1.0
	c._play_protect_sound("rapid_fire")
	check(int(c.protect_sound_counts.get("rapid_fire", 0)) == n1, "Convoy Sounds off: no rapid fire")
	c.protect_convoy_sounds = true

	# ---------------- Off = the 1.0.6 round ----------------
	c.protect_smart_drones = false
	c.protect_breachers = false
	start_protect(1, 1, 60)
	check(c.protect_breachers_total == 0, "Breachers off: none in the round")
	c._spawn_protect_drone(false)
	var old: Dictionary = drones()[0]
	old.hold = 0.0
	c._update_protect_drone(old, 1.0 / 30.0)
	check(not old.has("evading"), "Smart Drones off: the 1.0.6 drone rules")
	c.protect_smart_drones = true
	c.protect_breachers = true

	# ---------------- Test start screen stays out of the normal builds ----------------
	check(not Picker.wanted(), "Normal run: no Convoy Test start screen")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(not presets.contains("convoy_test"), "Normal export presets have no convoy_test feature")
	var picker_found := false
	for n in console.get_children():
		if n.get_script() == Picker:
			picker_found = true
	check(not picker_found, "The console adds no test start screen")

	print("CONVOY_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
