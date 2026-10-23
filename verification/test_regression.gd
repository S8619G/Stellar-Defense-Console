extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}

var console: Node
var c: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)
	else:
		print("PASS ", message)

func clean() -> void:
	c.breachers_enabled = false
	c.auto_spawn = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.klaxon_enabled = false
	c.nuclear_weapons_enabled = false
	c.max_hull = 100.0
	c.max_carriers = 2
	c.max_drones_per_carrier = 4
	c.max_drones = 8
	c.max_contacts = 14
	c.prox_success_chance = 0.75
	c.reset_battle()

func base() -> String:
	var id: String = c.spawn_contact("unknown", "unknown")
	if not id.is_empty():
		c._identify_carrier(c.find_contact(id))
	return id

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
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
	c.random_seed = 42919
	root.add_child(console)
	console.set_process(false)
	c.set_process(false)
	console.get_node("SweepLoop").stop()
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.klaxon_enabled = false
	clean()
	check(c.hull_percent() == 100 and c.jump_percent() == 100, "Initial HULL/JUMP are 100%")
	check(c.can_jump(), "Initial JUMP ready")
	check(c.pending.is_empty(), "Manual test has no ambient queue")
	var id: String = c.spawn_contact("carrier", "hostile")
	var track: Dictionary = c.find_contact(id)
	check(track.kind == "unknown" and track.faction == "unknown", "All distant arrivals begin unidentified")
	var initial: Vector3 = track.position
	check(initial.y >= 0.58 and initial.z >= 0.50, "Unknown appears far out in upper half")
	check(c.spawn_from_carrier("drone", id).is_empty(), "Unknown cannot launch fighters")
	c._process(2.99)
	check(track.kind == "unknown", "Identification delay holds")
	c._process(0.02)
	check(track.kind == "carrier" and track.faction == "hostile", "Unknown always resolves to hostile Enemy Carrier")
	check(track.position == initial and track.id == id, "Identification preserves position and track identity")
	check(c.identification_count == 1 and track.hits_remaining == 6, "One identification, six-hit capital health")
	c._process(30.0)
	check(track.position == initial and c.identification_count == 1, "Capital remains stationary; no repeated ID")
	var id2 := base()
	check(not id2.is_empty(), "Second Enemy Carrier allowed")
	check(c.spawn_contact("unknown", "unknown").is_empty(), "Capital plus unknown population respects cap")
	check(c.spawn_contact("drone", "hostile").is_empty(), "No independent Attack Drone spawns")
	check(c.spawn_contact("missile", "hostile").is_empty(), "No independent hostile missile spawns")
	check(c.spawn_contact("breacher", "hostile").is_empty(), "Excluded ship types rejected")
	var r: String = c.spawn_from_carrier("drone", id)
	var drone: Dictionary = c.find_contact(r)
	check(absf(drone.position.distance_to(initial) - c.carrier_emission_radius) < 0.0001, "Attack Drone launches at Enemy Carrier edge")
	for i in range(3):
		c.spawn_from_carrier("drone", id)
	check(c.count_base_drones(id) == 4, "Per-Enemy Carrier active fighter allowance is four")
	check(c.spawn_from_carrier("drone", id).is_empty(), "Fifth fighter denied at first Enemy Carrier")
	for i in range(4):
		c.spawn_from_carrier("drone", id2)
	check(c.count_kind("drone") == 8 and c.count_base_drones(id2) == 4, "Second Enemy Carrier has separate allowance; global cap eight")
	c._remove_contact(r)
	check(not c.spawn_from_carrier("drone", id).is_empty(), "Destroyed fighter frees exactly one launch slot")
	c.carrier_weapons_enabled = true
	track.drone_timer = 0.0
	c._update_carrier(track, 0.1)
	var queued_drones := 0
	for request in c.pending:
		if request.kind == "drone":
			queued_drones += 1
	check(queued_drones == 0, "Full carrier does not queue extra fighters")

	clean()
	c.apply_damage(1.0)
	check(c.hull_percent() == 99, "Hull counts down as a percentage")
	c._update_repair(20.0)
	check(c.hull == 99.0, "Repair waits 20 seconds after damage")
	c._update_repair(7.9)
	check(c.hull == 99.0, "Repair does not tick before interval")
	c._update_repair(0.11)
	check(c.hull == 100.0, "Repair adds 1% after eight eligible seconds")
	c._update_repair(1000.0)
	check(c.hull == 100.0, "Repair never exceeds full hull")
	c.apply_damage(99.5)
	check(c.hull_percent() == 1 and not c.is_defeated(), "Living hull never displays 0%")
	c._update_repair(24.0)
	c.apply_damage(0.1)
	check(c.repair_elapsed == 0.0 and c.repair_delay_remaining == 20.0, "New damage resets repair wait and partial tick")
	c.apply_damage(100.0)
	check(c.is_defeated() and c.hull_percent() == 0, "Destruction is 0%, not premature at 1%")
	c._process(1000.0)
	c._update_repair(1000.0)
	check(c.hull == 0.0, "No repair siege after game over")
	check(not c.request_jump() and c.launch_interceptors() == 0, "Defeat disables jump and Interceptor launch")
	console._process(0.0)
	# 1.0.8: the score screen comes in front 3 s after the ship is destroyed (SYSTEMS OFFLINE first).
	console.damage_effects.skip_to_score_screen()
	console._process(0.0)
	check(console.get_node("CenterContainer/Dome/GameOverPanel").visible, "Game over exposes mouse-only restart")
	console.get_node("CenterContainer/Dome/GameOverPanel/Retry").pressed.emit()
	check(c.hull_percent() == 100 and c.jump_percent() == 100, "Restart restores full HULL and JUMP")
	clean()
	c.max_hull = 200.0
	c.reset_battle()
	c.apply_damage(100.0)
	c._update_repair(28.0)
	check(c.hull == 102.0 and c.hull_percent() == 51, "Repair and percentage scale with Inspector max hull")

	clean()
	id = base()
	c.pending.append({"kind": "drone", "origin_id": id})
	c.own_weapons_enabled = true
	c.own_fire_remaining = 0.0
	c._update_own_weapons(0.0)
	c.apply_damage(25.0)
	check(c.count_kind("own_missile") == 1, "Player automatically launches against identified capital")
	check(c.request_jump(), "Ready JUMP can jump")
	check(c.contacts.is_empty() and c.pending.is_empty() and c.klaxon_queue.is_empty(), "JUMP clears both sides' projectiles, contacts and queues")
	check(c.jump_percent() == 1 and c.hull == 75.0, "Jump resets JUMP to 1%, preserves damage")
	check(not c.request_jump() and c.launch_interceptors() == 0, "No repeat jump or launches during safe interval")
	c._process(22.5)
	check(c.jump_percent() == 50 and not c.can_jump(), "Midpoint recharge shows 50%, remains locked")
	c._process(22.49)
	check(c.jump_percent() == 99 and not c.can_jump(), "JUMP cannot display 100 before ready")
	c._process(0.02)
	check(c.jump_percent() == 100 and c.can_jump(), "Full recharge unlocks jump")

	clean()
	id = base()
	track = c.find_contact(id)
	c.pending.append({"kind": "drone", "origin_id": id})
	c.pending.append({"kind": "missile", "origin_id": id})
	r = c.spawn_from_carrier("drone", id)
	for i in range(5):
		c._hit_carrier(track)
	check(not c.find_contact(id).is_empty() and track.hits_remaining == 1, "Enemy Carrier survives first five hits")
	c._hit_carrier(track)
	check(c.find_contact(id).is_empty() and c.carriers_destroyed == 1, "Sixth hit destroys Enemy Carrier once")
	check(c.pending.is_empty(), "Destroyed carrier cannot emit queued fighters or missiles")
	check(not c.find_contact(r).is_empty(), "Already launched Attack Drone remains in battle")
	c._hit_carrier(track)
	check(c.carriers_destroyed == 1 and c.own_missile_hits == 6, "Stale hit cannot double-count kill")
	check(c.spawn_from_carrier("missile", id).is_empty(), "Destroyed carrier cannot launch")

	clean()
	id = base()
	c.own_weapons_enabled = true
	c.own_fire_remaining = 0.0
	var beeps: int = c.beep_count
	c._update_own_weapons(0.0)
	var own: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "own_missile":
			own = contact
	check(own.faction == "friendly" and own.position == c.own_ship_position and own.target_id == id, "Friendly missile originates at own ship and targets Enemy Carrier")
	check(c.beep_count == beeps, "Player weapon launch does not trigger detection beep")
	c.prox_active = true
	c._resolve_missiles()
	check(c.count_kind("own_missile") == 1, "Prox defense never destroys player missiles")
	var hp: int = c.find_contact(id).hits_remaining
	c._update_own_weapons(2.0)
	check(c.find_contact(id).hits_remaining == hp and own.position != c.own_ship_position, "Friendly missile travels before causing damage")
	c.own_weapons_enabled = false
	c._update_own_weapons(10.0)
	check(c.find_contact(id).hits_remaining == hp - 1 and c.count_kind("own_missile") == 0, "Physical missile impact removes projectile and applies one hit")

	clean()
	id = base()
	c.own_weapons_enabled = true
	c.own_fire_remaining = 0.0
	c._update_own_weapons(0.0)
	c._remove_contact(id)
	c._update_own_weapons(0.01)
	check(c.count_kind("own_missile") == 0, "Orphaned player missile is cleaned up")
	id = c.spawn_contact("unknown", "unknown")
	c.own_fire_remaining = 0.0
	c._update_own_weapons(0.1)
	check(c.count_kind("own_missile") == 0, "Unidentified contact is never fired on")

	clean()
	id = base()
	c.launch_interceptors()
	var interceptor: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "interceptor":
			interceptor = contact
	check(interceptor.position.y <= -0.8 and c.count_interceptors() == 2, "Interceptors still launch in pairs at bottom edge")
	var excluded: Array[String] = []
	check(c._hostile_target(interceptor, excluded).is_empty(), "Interceptor refuses capital ship target")
	var edge_id: String = c.spawn_from_carrier("drone", id)
	var central_id: String = c.spawn_from_carrier("drone", id)
	c.find_contact(edge_id).position = Vector3(0.35, 0.35, 0.0)
	c.find_contact(central_id).position = Vector3(0.0, 0.0, 0.0)
	interceptor.position = Vector3(0.20, 0.10, 0.0)
	check(c._hostile_target(interceptor, excluded).id == central_id, "Interceptor prefers central fighter over peripheral fighter")
	interceptor.target_id = central_id
	c.find_contact(edge_id).position = Vector3(0.0, 0.01, 0.0)
	check(c._hostile_target(interceptor, excluded).id == central_id, "Target-lock hysteresis prevents small-distance jitter")
	var m: String = c.spawn_from_carrier("missile", id)
	c.find_contact(m).position = c.own_ship_position + Vector3(0.0, 0.20, 0.0)
	interceptor.target_id = ""
	interceptor.position = c.own_ship_position + Vector3(0.0, 0.25, 0.0)
	check(c._hostile_target(interceptor, excluded).id == m, "Nearby incoming missile remains defensive priority")
	interceptor.phase = "intercept"
	interceptor.position = c.find_contact(m).position
	c._update_interceptors(0.0)
	check(c.find_contact(m).is_empty() and c.missile_intercepts == 1, "Interceptor physically intercepts hostile missile")
	var test_ship := {"position": Vector3.ZERO, "velocity": Vector3.ZERO}
	var smooth := true
	for i in range(300):
		var old_velocity: Vector3 = test_ship.velocity
		var old_position: Vector3 = test_ship.position
		c._steer(test_ship, Vector3(0.5 if i < 150 else -0.5, 0.0, 0.0), c.interceptor_speed, 1.0 / 60.0)
		smooth = smooth and test_ship.velocity.length() <= c.interceptor_speed + 0.00001
		smooth = smooth and old_velocity.distance_to(test_ship.velocity) <= c.fighter_acceleration / 60.0 + 0.00001
		smooth = smooth and old_position.distance_to(test_ship.position) <= c.interceptor_speed / 60.0 + 0.00001
	check(smooth, "300 steering frames obey speed and acceleration bounds, including reversal")
	check(c.interceptor_speed < 0.24 and c.small_hostile_speed < 0.09, "Both small-ship classes slower than previous build")
	check(c.depth_strength == 0.25 and c.small_ship_icon_scale == 0.75 and c.carrier_icon_scale == 1.35, "Compact class sizes and mild depth scale unchanged")

	clean()
	id = base()
	m = c.spawn_from_carrier("missile", id)
	c.find_contact(m).position = c.own_ship_position
	c._resolve_missiles()
	check(c.hull == 90.0 and c.missile_hits == 1, "Hostile missile damages own hull once")
	c.prox_active = true
	c.prox_success_chance = 0.0
	m = c.spawn_from_carrier("missile", id)
	c.find_contact(m).position = c.own_ship_position + Vector3(0, 0.1, 0)
	c._resolve_missiles()
	check(c.find_contact(m).defense_checked, "Prox failure is recorded")
	c.prox_success_chance = 0.95
	c.set_prox_defense(false)
	c.set_prox_defense(true)
	c._resolve_missiles()
	check(not c.find_contact(m).is_empty(), "Toggling defense cannot reroll same missile")
	c._remove_contact(m)
	c.prox_success_chance = 1.0
	var leaked := 0
	for i in range(500):
		m = c.spawn_from_carrier("missile", id)
		c.find_contact(m).position = c.own_ship_position + Vector3(0, 0.1, 0)
		c._resolve_missiles()
		if not c.find_contact(m).is_empty():
			leaked += 1
			c._remove_contact(m)
	check(leaked > 0, "Runtime defense cap still allows leaks even at Inspector override 100%")

	clean()
	c.auto_spawn = true
	c.carrier_weapons_enabled = true
	c.own_weapons_enabled = true
	c.reset_battle()
	c.prox_active = true
	var caps_ok := true
	var stationary := true
	var respawns := 0
	var total_kills := 0
	for frame in range(36000):
		c._process(1.0 / 60.0)
		if frame % 480 == 0:
			c.launch_interceptors()
		if c.hull < 25 and c.can_jump():
			c.request_jump()
		for contact in c.contacts:
			if contact.kind == "carrier":
				stationary = stationary and contact.position == contact.start
				caps_ok = caps_ok and c.count_base_drones(contact.id) <= c.max_drones_per_carrier
		caps_ok = caps_ok and c.count_kind("drone") <= c.max_drones and c.count_interceptors() <= c.interceptor_limit()
		# Waves update (approved): the Enemy Carrier limit now rises with the wave, up to 4.
		caps_ok = caps_ok and c.count_kind("carrier") + c.count_kind("unknown") <= c.carrier_cap() and c.carrier_cap() <= c.wave_max_carriers
		caps_ok = caps_ok and c.count_kind("own_missile") <= c.max_own_missiles and c.count_kind("missile") <= c.missile_cap()
		if c.is_defeated():
			total_kills += c.carriers_destroyed
			respawns += 1
			c.reset_battle()
			c.prox_active = true
	total_kills += c.carriers_destroyed
	check(caps_ok and stationary, "Ten-minute mixed simulation: all population caps and stationary capitals hold")
	check(total_kills > 0, "Ten-minute simulation actually destroys Enemy Carriers with automatic player weapons")
	print("SIMULATION seconds=600 capital_kills=", total_kills, " gameover_restarts=", respawns)
	var status: Control = console.get_node("ShipStatus")
	check(status.damage_color(1.0).g > status.damage_color(1.0).r, "Full hull status is green")
	check(status.damage_color(0.65).r > status.damage_color(1.0).r, "Moderate damage moves to lighter green")
	check(status.damage_color(0.3).r > status.damage_color(0.3).g, "Low hull status turns orange")
	check(status.damage_color(0.01).g < 0.3, "Critical hull status turns red")
	await process_frame
	var dome: Control = console.get_node("CenterContainer/Dome")
	var bottom: Control = console.get_node("BottomButtons")
	check(status.global_position.y > dome.global_position.y + dome.size.y * 0.5 + dome.sphere_radius, "Status outline lies below radar perimeter")
	check(status.global_position.y + status.size.y < bottom.global_position.y, "Status outline lies above buttons")
	print("RESULT checks=", checks, " failures=", failures)
	c.arrival_player.stop()
	c.launch_player.stop()
	c.klaxon_player.stop()
	c._stop_special_audio()
	console.get_node("SweepLoop").stop()
	await create_timer(0.3).timeout
	console.free()
	console = null
	c = null
	await create_timer(0.2).timeout
	call_deferred("quit", 0 if failures == 0 else 1)
