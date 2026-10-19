extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
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
	c.breachers_enabled = true
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.reset_battle()
func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	return b
func heavy(b: Dictionary) -> Dictionary:
	return c.find_contact(c.spawn_from_carrier("breacher", b.id))
func begin_hack(h: Dictionary) -> void:
	h.position = h.hack_point
	c._update_breachers(0.0)
func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	c = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	# 1.2.8: pins the 1.2.7 hack drain (2% a second) for this file's hull arithmetic;
	# the 1.5% default is checked in test_v128_features.
	c.hack_drain_percent_per_second = 2.0
	# 1.2.1: this test checks the 1.2.0 combat rules, so it uses the 1.2.0 combat values
	# (test_v121_features checks the new 1.2.1 defaults).
	# 1.2.2: Nuclear Speed and Gunship Nuke Hit Interval are pinned to their 1.2.1 values too.
	for classic in [["carrier_hits_to_destroy", 6], ["breacher_hit_points", 3], ["nuclear_hit_points", 3],
			["nuclear_speed", 0.055], ["gunship_nuke_hit_interval", 0.6],
			["drone_interceptor_hits", 1], ["ship_nuke_target_fraction", 0.5], ["ship_missile_heavy_range", 0.3],
			["own_missile_interval", 6.0], ["heavy_launch_interval", 22.0]]:
		c.set(classic[0], classic[1])
	c.auto_spawn = false
	root.add_child(console)
	c.set_process(false)
	console.set_process(false)
	console.get_node("SweepLoop").stop()
	c.rng.seed = 9042
	clean()
	await process_frame
	await process_frame
	var own: Vector2 = c.global_position + c.projection(c.own_ship_position).point
	var rect: Rect2 = console.get_node("ShipStatus").get_global_rect()
	check(own.y >= rect.position.y and own.y < rect.position.y + 20.0, "Missile endpoint now lies on upper hull, not 69 pixels above it")
	print("NEW_IMPACT projected_global=", own, " ship_rect=", rect)
	var b := base()
	var missile: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	missile.position = Vector3(0.0, -0.82, -0.15)
	c._resolve_missiles()
	check(c.hull == 100.0 and c.impact_sound_count == 0, "Old impact location no longer damages hull or plays boom")
	missile.position = c.own_ship_position + Vector3(0, 0.02, 0)
	c._resolve_missiles()
	check(c.hull == 100.0 and not c.find_contact(missile.id).is_empty(), "Conventional missile must pass former broad collision threshold")
	missile.position = c.own_ship_position
	c._resolve_missiles()
	check(c.hull == 90.0 and c.impact_sound_count == 1, "Actual conventional impact damages once and triggers one boom")
	check(c.impact_player.playing and c.hit_flash_remaining == 0.45, "Impact sound and red-flash timer start together")
	c._resolve_missiles()
	check(c.hull == 90.0 and c.impact_sound_count == 1, "Removed missile cannot duplicate damage or feedback")
	c._process(0.5)
	check(c.hit_flash_remaining == 0.0, "Hull flash expires rather than permanently recoloring ship")
	var nuke: Dictionary = c.find_contact(c._launch_nuclear(b))
	nuke.position = Vector3(0.0, -0.82, -0.15)
	c._update_special_projectiles(0.0)
	check(c.hull == 90.0 and c.impact_sound_count == 1, "Nuclear missile also travels past old hit location")
	nuke.position = c.own_ship_position
	c._update_special_projectiles(0.0)
	check(c.hull == 30.0 and c.impact_sound_count == 2 and c.hit_flash_remaining > 0, "Nuclear hull impact has same synchronized feedback")
	c.apply_damage(1000.0)
	check(c.is_defeated() and c.impact_player.playing and c.hit_flash_remaining > 0, "Lethal missile hit is still audible and flashes")
	c._process(1.0)
	check(c.hit_flash_remaining == 0.0 and c.hull == 0.0, "Flash expires even after game over")
	c.reset_battle()
	check(not c.impact_player.playing and c.hit_flash_remaining == 0, "Retry clears impact feedback")
	check(c.impact_player.stream.get_length() == 0.45 and c.impact_player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Impact is a short nonlooping 0.45-second effect")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "ImpactProbe")
	AudioServer.add_bus_effect(bus, capture)
	c.impact_player.bus = "ImpactProbe"
	c.apply_damage(1.0)
	await create_timer(0.25).timeout
	var peak := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		peak = maxf(peak, absf(frame.x))
	check(peak > 0.04 and peak < 0.5, "Actual impact PCM has audible bounded output")
	print("IMPACT_PEAK ", peak)
	await create_timer(0.45).timeout
	check(not c.impact_player.playing, "Boom finishes without looping")
	c.impact_player.bus = "Master"
	AudioServer.remove_bus(bus)
	capture = null
	clean()
	b = base()
	var h := heavy(b)
	check(not h.is_empty() and h.kind == "breacher" and h.faction == "hostile", "Enemy Carrier emits hostile Breacher")
	check(absf(h.position.distance_to(b.position) - c.carrier_emission_radius) < 0.0001, "Breacher originates at Enemy Carrier edge")
	check(c.spawn_contact("breacher", "hostile").is_empty(), "Breachers cannot appear independently of a Enemy Carrier")
	check(c.spawn_from_carrier("breacher", b.id).is_empty(), "Per-Enemy Carrier Breacher cap enforced")
	var b2 := base()
	var h2 := heavy(b2)
	check(c.count_kind("breacher") == 2 and c.count_tracks() == 4, "Two capitals can support two heavies; heavies count toward total tracks")
	check(c.spawn_from_carrier("breacher", b2.id).is_empty(), "Global Breacher population cap enforced")
	var old: Vector3 = h.position
	c._update_breachers(1.0)
	check(h.position.distance_to(old) > 0.0 and h.position.distance_to(old) <= c.breacher_speed + 0.001, "Breacher approaches at bounded slow speed")
	check(c.breacher_speed < c.gunship_speed and c.breacher_speed < c.interceptor_speed, "Breacher slower than both friendly craft")
	begin_hack(h)
	check(h.phase == "hacking" and h.hack_remaining == 6.0 and c.hull == 100.0, "Reaching close range begins six-second hack without immediate damage")
	c._update_breachers(5.0)
	check(h.phase == "hacking" and h.hack_remaining == 1.0 and c.hull == 100.0, "Incomplete hack cannot drain hull")
	c._update_breachers(1.0)
	check(h.phase == "draining" and c.hull == 100.0, "Exact hack completion does not retroactively apply six seconds of drain")
	c._update_breachers(2.0)
	check(c.hull == 96.0 and c.active_hackers() == 1, "Successful hack drains two percent hull per second")
	check(c.impact_sound_count == 0 and c.hit_flash_remaining == 0.0, "Hacking does not spam missile impact sounds or flashes")
	c.set_prox_defense(true)
	var health: int = h.health
	c._resolve_missiles()
	check(not c.find_contact(h.id).is_empty() and h.health == health, "Defense shield cannot damage Breacher")
	console._process(0.0)
	check(console.get_node("HackAlert").visible and console.get_node("HackAlert").text.contains("HULL DRAIN"), "Successful hacking has persistent visible warning")
	check(console.get_node("HeaderMetrics/Enemies/Value").text == "2" and not console.get_node("BattleReadout").text.contains("BREACHERS  2"), "Enemy counter includes both attackers (1.1.0: the readout lists destroyed Breachers only)")
	check(console.get_node("BottomButtons/ProxDefense").text.begins_with("DEFENSE SHIELD"), "Visible button renamed Defense Shield")
	h.position = b.position
	c._update_breachers(1.0)
	check(h.phase == "approach" and c.hull == 96.0, "Moving hacker out of range breaks link and resets hack")
	begin_hack(h)
	c._update_breachers(9.0)
	check(c.hull == 90.0, "Large hack timestep drains only time after six-second setup")
	c._hit_carrier(b, 100.0)
	check(not c.find_contact(h.id).is_empty(), "Destroying parent Enemy Carrier does not erase an already launched hacker")
	var v: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.phase = "intercept"
	v.position = h.position
	c._update_interceptors(0.0)
	check(h.health == 2 and not c.find_contact(h.id).is_empty(), "First Interceptor hit damages three-hit Breacher")
	c._update_interceptors(0.0)
	check(h.health == 2, "Interceptor cannot fire every frame without cooldown")
	c._update_interceptors(0.81)
	check(h.health == 1 and not c.find_contact(h.id).is_empty(), "Breacher survives two hits, tougher than a one-hit Attack Drone")
	c._update_interceptors(0.81)
	check(c.find_contact(h.id).is_empty() and c.breachers_destroyed == 1 and c.score == 1300, "Third Interceptor hit destroys hacker and awards 300 points")
	var hp: float = c.hull
	c._update_breachers(1.0)
	check(c.hull == hp and c.active_hackers() == 0, "Destroying hacker immediately stops its hull drain")
	c._hit_breacher(h)
	check(c.score == 1300, "Stale Breacher cannot award twice")
	clean()
	b = base()
	h = heavy(b)
	begin_hack(h)
	c._update_breachers(6.0)
	c.launch_gunship()
	var r: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "gunship":
			r = contact
	r.phase = "patrol"
	r.position = h.position
	var excluded: Array[String] = []
	check(c._gunship_target(r, excluded).id == h.id, "Gunship prioritizes Breacher over capital attack")
	var nid: String = c._launch_nuclear(b)
	check(c._gunship_target(r, excluded).id == nid, "Nuclear threat retains highest Gunship priority")
	c._remove_contact(nid)
	c._update_gunships(0.0)
	check(h.health == 2, "Gunship can damage hacker")
	c._update_gunships(0.0)
	check(h.health == 2, "Gunship heavy-target attack has cooldown")
	c._update_gunships(1.21)
	c._update_gunships(1.21)
	check(c.find_contact(h.id).is_empty() and c.score == 300, "Gunship destroys Breacher for 300 points")
	clean()
	b = base()
	b2 = base()
	h = heavy(b)
	h2 = heavy(b2)
	begin_hack(h)
	begin_hack(h2)
	c._update_breachers(6.0)
	c._update_breachers(1.0)
	check(c.hull == 96.0 and c.active_hackers() == 2, "Two completed hacks stack to four percent per second")
	for i in range(3):
		c._hit_breacher(h)
	c._update_breachers(1.0)
	check(c.hull == 94.0 and c.active_hackers() == 1, "Removing one hacker removes only its contribution")
	c.request_jump()
	c._update_breachers(10.0)
	check(c.hull == 94.0 and c.active_hackers() == 0 and c.contacts.is_empty(), "JUMP escapes all hacking links without lingering drain")
	clean()
	b = base()
	h = heavy(b)
	begin_hack(h)
	c._update_breachers(6.0)
	c._update_breachers(60.0)
	check(c.hull == 0.0 and c.is_defeated(), "Unopposed hacking can destroy the main ship")
	c.reset_battle()
	check(c.active_hackers() == 0 and c.hacking_warning().is_empty() and c.hull == 100.0, "Retry clears all hacking state")
	clean()
	b = base()
	c.carrier_weapons_enabled = true
	b.heavy_timer = 0.0
	c._update_carrier(b, 0.0)
	check(c.pending_heavies() == 1, "Enemy Carrier autonomously queues Breacher launch")
	b.heavy_timer = 0.0
	c._update_carrier(b, 0.0)
	check(c.pending_heavies() == 1, "Queued launches count toward per-capital limit")
	c._process(1.0)
	check(c.count_kind("breacher") == 1, "Queued Breacher actually launches through normal ingestion path")
	clean()
	check(c.jump_score_cost == 3000 and c.breacher_points == 300 and c.bonus_repair_points == 10000, "Approved score and bonus defaults exposed")
	check(c.missile_damage == 10.0 and c.nuclear_damage == 60.0, "Standard missile damage reduced to 10; nuclear unchanged at 60")
	check(c.breacher_hit_points == 3 and c.prox_defense_radius == 0.12 and c.battery_shot_interval == 0.1, "Field-feedback defaults exposed for Inspector tuning")
	# Earn real capital kills rather than directly incrementing score.
	for i in range(9):
		c._hit_carrier(base(), 100.0)
	check(c.earned_points == 9000 and c.repair_charges == 1, "No bonus before ten thousand earned points")
	c.request_jump()
	check(c.score == 6000 and c.earned_points == 9000 and c.repair_charges == 1, "JUMP deducts 3000 score without resetting earned progress")
	c.safe_remaining = 0.0
	c._hit_carrier(base(), 100.0)
	check(c.score == 7000 and c.earned_points == 10000 and c.repair_charges == 2, "Ten thousand earned awards bonus despite lower net score")
	check(c.repair_bonuses_earned == 1, "First milestone recorded exactly once")
	c.hull = 50.0
	check(c.request_rapid_repair() and c.repair_charges == 1, "Repair spends one of two banked charges")
	check(not c.request_rapid_repair() and c.repair_charges == 1, "Repair cannot spend another charge while active")
	c._update_rapid_repair(5.0)
	check(c.hull == 75.0 and c.request_rapid_repair(), "Bonus charge can start a second 25-percent repair")
	c._update_rapid_repair(5.0)
	check(c.hull == 100.0 and c.repair_charges == 0, "Second repair consumes remaining charge and caps hull")
	for i in range(10):
		c._hit_carrier(base(), 100.0)
	# Waves update (approved): bonuses are spaced out at 10,000 / 25,000 / 50,000, then every 50,000.
	check(c.earned_points == 20000 and c.repair_charges == 0 and c.repair_bonuses_earned == 1, "Spaced bonuses: no second charge at 20,000 earned")
	for i in range(5):
		c._hit_carrier(base(), 100.0)
	check(c.earned_points == 25000 and c.repair_charges == 1 and c.repair_bonuses_earned == 2, "Second bonus charge arrives at 25,000 earned")
	c.jump_recharge_remaining = 0.0
	c.request_jump()
	check(c.repair_charges == 1 and c.earned_points == 25000, "Later JUMP preserves earned repair charge and milestones")
	c.safe_remaining = 0.0
	c._hit_carrier(base(), 100.0)
	check(c.repair_charges == 1, "Re-earning net points after JUMP cannot repeat old milestone")
	c.hull = 100.0
	check(not c.request_rapid_repair() and c.repair_charges == 1, "Full hull never wastes earned repair charge")
	c.reset_battle()
	check(c.score == 0 and c.earned_points == 0 and c.repair_bonuses_earned == 0 and c.repair_charges == 1, "Retry resets reward accounting and restores only starting charge")
	c.score = 500
	c.request_jump()
	check(c.score == 0 and not c.request_jump(), "Three-thousand penalty still floors at zero and failed jump costs nothing")
	# --- Field-feedback update: battery reliability, parking, targeting ---
	clean()
	c.own_weapons_enabled = false
	b = base()
	var hits := 0
	for trial in range(40):
		c.reset_battle()
		c.breachers_enabled = false
		b = base()
		var mm: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
		var tt := 0.0
		while not c.find_contact(mm.id).is_empty() and tt < 30.0:
			# Fire about five seconds before impact, inside the six-second reserve.
			if not c.prox_active and mm.position.distance_to(c.own_ship_position) <= c.missile_speed * 5.0:
				c.set_prox_defense(true)
			c._process(1.0 / 60.0)
			tt += 1.0 / 60.0
		if c.hull < 100.0:
			hits += 1
	check(hits <= 1, "Battery firing through the zone stops nearly every standard missile")
	print("BATTERY_TRIALS hits=", hits, " of 40")
	clean()
	b = base()
	var late: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	late.position = c.own_ship_position + Vector3(0, c.prox_defense_radius - 0.01, 0)
	c.battle_time = 10.0
	c.prox_success_chance = 0.0
	c.set_prox_defense(true)
	c._resolve_missiles()
	var first_shot: float = late.next_battery_shot
	c._resolve_missiles()
	check(late.next_battery_shot == first_shot, "Battery shots are paced, not every frame")
	c.battle_time += c.battery_shot_interval
	c._resolve_missiles()
	check(late.next_battery_shot > first_shot, "A missed missile is shot at again while still in the zone")
	c.prox_success_chance = 0.95
	c.battle_time += c.battery_shot_interval
	c._resolve_missiles()
	check(c.find_contact(late.id).is_empty() and c.impacts.back().get("battery", false), "Battery kill shows the yellow battery burst")
	c.prox_success_chance = 0.45
	c.set_prox_defense(false)
	clean()
	b = base()
	h = heavy(b)
	var park: Vector3 = h.hack_point
	check(park.distance_to(c.own_ship_position) < 0.20, "Breacher parks very close to the ship")
	var park_px: Vector2 = c.global_position + c.projection(park).point
	var ship_rect: Rect2 = console.get_node("ShipStatus").get_global_rect()
	check(park_px.y < ship_rect.position.y and park_px.y > ship_rect.position.y - 45.0, "Parked Breacher sits just above the visible hull")
	print("PARK_PX ", park_px, " ship_top=", ship_rect.position.y)
	var sim_t := 0.0
	while h.phase == "approach" and sim_t < 60.0:
		c._update_breachers(1.0 / 60.0)
		sim_t += 1.0 / 60.0
	check(h.phase == "hacking" and h.velocity == Vector3.ZERO, "Unopposed Breacher flies in and stops to hack")
	print("HEAVY_ARRIVAL seconds=", sim_t)
	# Interceptors stay on Attack Drones while any are in their zone.
	clean()
	b = base()
	h = heavy(b)
	h.position = Vector3(0.0, -0.3, 0.0)
	var rd: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	rd.position = Vector3(0.3, 0.1, 0.0)
	var vp: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	vp.phase = "intercept"
	vp.position = Vector3(0.0, -0.32, 0.0)
	var none: Array[String] = []
	check(c._hostile_target(vp, none).id == rd.id, "Interceptors stay on Attack Drones even when a Breacher is closer")
	c._remove_contact(rd.id)
	check(c._hostile_target(vp, none).id == h.id, "Interceptors break away for Breacher once Attack Drones are clear")
	# Gunship under Enemy Carrier fire keeps evading/attacking instead of chasing heavies.
	c.launch_gunship()
	var rp: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "gunship":
			rp = contact
	rp.phase = "patrol"
	rp.position = b.position + Vector3(0.0, -0.4, 0.0)
	check(c._gunship_target(rp, none).id == h.id, "Free Gunship goes after Breacher")
	var bolt_id: String = c._fire_flak(b)
	var bolt: Dictionary = c.find_contact(bolt_id)
	if not bolt.is_empty():
		bolt.target_id = rp.id
	check(not bolt.is_empty() and c._gunship_target(rp, none).id == b.id, "Gunship under Enemy Carrier flak does not divert to Breacher")
	# Ship missiles target a nearby Breacher and can destroy it.
	clean()
	c.own_weapons_enabled = true
	b = base()
	h = heavy(b)
	begin_hack(h)
	c.own_fire_remaining = 0.0
	c._update_own_weapons(0.0)
	var shot: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "own_missile":
			shot = contact
	check(not shot.is_empty() and shot.target_id == h.id, "Ship missile targets parked Breacher before Enemy Carrier")
	var kill_t := 0.0
	while not c.find_contact(h.id).is_empty() and kill_t < 30.0:
		c._update_own_weapons(1.0 / 30.0)
		kill_t += 1.0 / 30.0
	check(c.find_contact(h.id).is_empty() and c.score == 300, "Ship missiles alone can destroy a Breacher")
	print("SHIP_MISSILE_HEAVY_KILL seconds=", kill_t)
	c.reset_battle()
	clean()
	b = base()
	h = heavy(b)
	h.position = c.own_ship_position + Vector3(0, 1.5, 0)
	c.own_fire_remaining = 0.0
	c.own_weapons_enabled = true
	c._update_own_weapons(0.0)
	var far_shot: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "own_missile":
			far_shot = contact
	check(not far_shot.is_empty() and far_shot.target_id == b.id, "Distant Breacher does not pull ship missiles off Enemy Carriers")
	c.own_weapons_enabled = false
	clean()
	c.auto_spawn = true
	c.carrier_weapons_enabled = true
	c.own_weapons_enabled = true
	c.reset_battle()
	var caps := true
	var heavy_seen := false
	var hacks_seen := false
	var kills := 0
	var retries := 0
	for frame in range(36000):
		c._process(1.0 / 60.0)
		if frame % 600 == 0:
			c.launch_interceptors()
			c.launch_gunship()
			c.set_prox_defense(true)
		if c.hull < 60:
			c.request_rapid_repair()
		heavy_seen = heavy_seen or c.count_kind("breacher") > 0
		hacks_seen = hacks_seen or c.active_hackers() > 0
		caps = caps and c.count_kind("breacher") <= c.breacher_cap() and c.breacher_cap() <= 3 and c.count_tracks() <= c.max_contacts and c.repair_charges >= 0
		for contact in c.contacts:
			if contact.kind == "carrier":
				caps = caps and c.count_base_heavies(contact.id, true) <= 1
		if c.is_defeated():
			kills += c.breachers_destroyed
			retries += 1
			c.reset_battle()
	kills += c.breachers_destroyed
	check(caps and heavy_seen, "Ten-minute integrated simulation respects Breacher and repair limits")
	print("HEAVY_SIMULATION seconds=600 heavy_kills=", kills, " hack_seen=", hacks_seen, " retries=", retries, " score=", c.score, " earned=", c.earned_points)
	check(kills > 0, "Integrated simulation actually destroys Breachers")
	print("HEAVY_UPDATE_RESULT checks=", checks, " failures=", failures)
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	console = null
	c = null
	await create_timer(0.2).timeout
	call_deferred("quit", 0 if failures == 0 else 1)
