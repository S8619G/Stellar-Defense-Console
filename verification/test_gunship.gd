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

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func clean() -> void:
	c.breachers_enabled = false
	c.auto_spawn = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.nuclear_weapons_enabled = true
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.gunship_evasion_chance = 0.75
	c.reset_battle()

func base() -> Dictionary:
	var id: String = c.spawn_contact("unknown", "unknown")
	var b: Dictionary = c.find_contact(id)
	c._identify_carrier(b)
	return b

func gunship() -> Dictionary:
	c.gunship_cooldown_remaining = 0.0
	c.launch_gunship()
	var found: Dictionary = {}
	for ship in c.contacts:
		if ship.kind == "gunship":
			found = ship
	found.phase = "patrol"
	return found

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
	c.random_seed = 8083
	root.add_child(console)
	c.set_process(false)
	console.set_process(false)
	console.get_node("SweepLoop").stop()
	clean()
	c.set_prox_defense(true)
	check(c.prox_active and c.prox_burst_remaining == 6.0 and c.battery_player.playing, "Defense activation begins timed burst and gunfire")
	c._update_battery(5.9)
	check(c.prox_active, "Battery operates for allowed burst window")
	c.set_prox_defense(true)
	check(c.prox_burst_remaining < 0.11, "Repeated activation cannot extend burst")
	c._update_battery(0.11)
	check(not c.prox_active and c.prox_burst_remaining == 0.0 and not c.battery_player.playing, "Exhausted battery stops at zero charge")
	c.set_prox_defense(true)
	check(not c.prox_active, "Cannot activate while empty")
	c._update_battery(23.9)
	check(c.prox_burst_remaining > 5.0 and c.prox_burst_remaining < 6.0, "Recharge is gradual over twenty-four seconds after a one-second delay (1.03)")
	c._update_battery(0.11)
	c.set_prox_defense(true)
	check(c.prox_active, "Battery can reactivate once recharged above restart level")
	var held: float = c.prox_burst_remaining
	c.set_prox_defense(false)
	check(not c.prox_active and c.prox_burst_remaining == held, "Early stop keeps remaining charge")
	c.set_prox_defense(true)
	check(c.prox_active and c.prox_burst_remaining == held, "Restart resumes from current charge without bonus")
	clean()
	c.set_prox_defense(true)
	c.request_jump()
	check(not c.prox_active and c.prox_cooldown_remaining == 0.0 and c.prox_burst_remaining == 6.0, "Jump stops battery and preserves reserve")
	check(c.jump_player.playing and c.count_kind("nuke") == 0, "JUMP action plays jump sound")

	clean()
	var b := base()
	c.carrier_weapons_enabled = true
	c._update_carrier(b, 17.9)
	check(c.count_kind("nuke") == 0, "Enemy Carrier waits before nuclear launch")
	c._update_carrier(b, 0.11)
	check(c.count_kind("nuke") == 1 and b.nuclear_launched, "Enemy Carrier launches its single nuclear missile")
	var nuclear_id := ""
	for contact in c.contacts:
		if contact.kind == "nuke":
			nuclear_id = contact.id
	var n: Dictionary = c.find_contact(nuclear_id)
	check(absf(n.position.distance_to(b.position) - c.carrier_emission_radius) < 0.0001, "Nuke starts at actual Enemy Carrier edge")
	c._update_carrier(b, 100.0)
	check(c.nuclear_launches == 1 and c._launch_nuclear(b).is_empty(), "Nuclear allowance cannot replenish on same Enemy Carrier")
	check(c.nuclear_speed < c.missile_speed, "Nuclear missiles slower than conventional missiles")
	n.speed_bonus = 0.0  # 1.1.0: random nuke speed bonus off for the exact measurement
	var start: Vector3 = n.position
	c._update_special_projectiles(1.0)
	check(absf(start.distance_to(n.position) - c.nuclear_speed * c.nuke_speed_factor()) < 0.0001, "Nuclear missile moves continuously at configured speed")
	c.launch_interceptors()
	var v: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "interceptor":
			v = contact
	var excluded: Array[String] = []
	check(c._hostile_target(v, excluded).is_empty(), "Interceptors cannot target nuclear missiles or Enemy Carriers")
	n.position = c.own_ship_position + Vector3(0, 0.1, 0)
	c.set_prox_defense(true)
	c._resolve_missiles()
	check(not c.find_contact(nuclear_id).is_empty(), "Proximity battery cannot destroy nuclear missile")
	c._update_nuclear_alarm(0.0)
	check(c.nuclear_player.playing, "Live nuclear threat triggers distinct alarm")
	console._process(0.0)
	check(console.get_node("NuclearAlert").visible, "Live nuclear threat exposes prominent warning")
	c.request_jump()
	check(c.contacts.is_empty() and not c.nuclear_player.playing, "JUMP escapes nuke and stops threat alarm")

	clean()
	b = base()
	nuclear_id = c._launch_nuclear(b)
	c.find_contact(nuclear_id).position = c.own_ship_position
	c._update_special_projectiles(0.0)
	check(c.hull == 40.0 and c.nuclear_hits == 1, "Nuclear impact deals 60 hull damage once")
	c._update_special_projectiles(0.0)
	check(c.hull == 40.0 and c.nuclear_hits == 1, "Removed nuke cannot damage twice")
	var b2 := base()
	nuclear_id = c._launch_nuclear(b2)
	c.find_contact(nuclear_id).position = c.own_ship_position
	c._update_special_projectiles(0.0)
	check(c.is_defeated(), "Second nuclear impact can end game")
	console._process(0.0)
	var panel: Panel = console.get_node("CenterContainer/Dome/GameOverPanel")
	check(panel.visible and panel.get_node("Title").text == "Game Over" and panel.get_node("Retry").text == "Retry", "Game Over and Retry display in one panel")
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	check(style.border_width_left == 3 and style.border_color.r > 0.9, "Game Over panel has red border")
	check(c.launch_gunship() == 0 and not c.request_jump(), "Defeat blocks Gunships and JUMP")
	panel.get_node("Retry").pressed.emit()
	console._process(0.0)
	check(not panel.visible and c.hull == 100.0 and c.jump_percent() == 100, "Retry resets run and hides Game Over")

	clean()
	check(c.launch_gunship() == 1 and c.count_kind("gunship") == 1, "Launch Gunship button path spawns one craft")
	check(c.launch_gunship() == 0, "Gunship launch cooldown enforced")
	c.gunship_cooldown_remaining = 0.0
	check(c.launch_gunship() == 1, "Second Gunship available after cooldown")
	c.gunship_cooldown_remaining = 0.0
	check(c.launch_gunship() == 0, "Active Gunship capacity enforced")
	check(c.gunship_speed < c.interceptor_speed, "Gunship slower than Interceptor")
	clean()
	b = base()
	var r := gunship()
	r.position = Vector3(0, 0, 0)
	check(c._gunship_target(r, excluded).id == b.id, "Gunship attacks identified Enemy Carrier when no nuke")
	c.nuclear_hit_points = 1  # 1.02: one-hit setting reproduces the original instant interception
	nuclear_id = c._launch_nuclear(b)
	check(c._gunship_target(r, excluded).id == nuclear_id, "Nuclear interception overrides capital attack")
	n = c.find_contact(nuclear_id)
	r.position = n.position
	c._update_gunships(0.0)
	check(c.find_contact(nuclear_id).is_empty() and c.nuclear_intercepts == 1, "Gunship physically destroys nearby nuclear missile")
	check(not c.find_contact(r.id).is_empty(), "Nuclear interception does not sacrifice Gunship")
	c._update_nuclear_alarm(0.0)
	check(not c.nuclear_player.playing, "Last interception silences nuclear alert")
	r.position = b.position + Vector3(0, -0.4, 0)
	r.fire_timer = 0.0
	c._update_gunships(0.0)
	check(c.count_kind("gunship_missile") == 1, "Gunship launches light missile within range")
	c._update_own_weapons(5.0)
	check(b.hits_remaining == 5.5 and c.gunship_missile_hits == 1, "Gunship missile deals half a main-ship missile's damage")
	check(c.count_kind("gunship_missile") == 0, "Light projectile removed after impact")
	var bolt_id: String = c._fire_flak(b)
	check(not bolt_id.is_empty() and c.find_contact(bolt_id).target_id == r.id, "Enemy Carrier fires back at Gunship")
	c.gunship_evasion_chance = 0.0
	c.find_contact(bolt_id).position = r.position
	c._update_special_projectiles(0.0)
	# Firewall & Combat update (approved): Gunships take Gunship Hit Points (4) unevaded hits.
	check(r.health == c.gunship_hit_points - 1 and c.gunships_lost == 0, "First unevaded hit damages Gunship")
	for i in range(c.gunship_hit_points - 1):
		bolt_id = c._fire_flak(b)
		if not bolt_id.is_empty():
			c.find_contact(bolt_id).position = r.position
			c._update_special_projectiles(0.0)
	check(c.find_contact(r.id).is_empty() and c.gunships_lost == 1, "Last unevaded hit destroys Gunship")
	r = gunship()
	r.position = b.position + Vector3(0, -0.4, 0)
	c.gunship_evasion_chance = 0.75
	var evades := 0
	for i in range(100):
		r.health = 1000
		bolt_id = c._fire_flak(b)
		c.find_contact(bolt_id).position = r.position
		c._update_special_projectiles(0.0)
	evades = c.gunship_evades
	check(evades > 50 and evades < 95, "100 flak trials exercise successful evasions and hits")
	print("EVASION trials=100 evades=", evades)
	bolt_id = c._fire_flak(b)
	c._remove_contact(r.id)
	c._update_special_projectiles(0.0)
	check(c.find_contact(bolt_id).is_empty(), "Flak cleans up after Gunship disappears")
	clean()
	c.launch_interceptors()
	for contact in c.contacts:
		if contact.kind == "interceptor":
			contact.age = 100.0
			contact.position = c.launch_origin(contact.lane)
	c._update_interceptors(0.0)
	check(c.count_interceptors() == 0 and c.interceptors_returned == 2, "Interceptor disappearance at end of sortie is recorded as recovery")
	check(c.status_message.contains("RECOVERED"), "Interceptor recovery explicitly announced")
	r = gunship()
	r.age = 100.0
	r.position = c.launch_origin(r.lane)
	c._update_gunships(0.0)
	check(c.count_kind("gunship") == 0 and c.gunships_returned == 1, "Gunship recovery tracked separately from losses")

	clean()
	c.auto_spawn = true
	c.carrier_weapons_enabled = true
	c.own_weapons_enabled = true
	c.reset_battle()
	var caps := true
	var nuke_total := 0
	var intercept_total := 0
	var kills := 0
	var retries := 0
	for frame in range(36000):
		c._process(1.0 / 60.0)
		if frame % 300 == 0:
			c.launch_interceptors()
			c.launch_gunship()
			c.set_prox_defense(true)
		if c.hull < 30 and c.can_jump():
			c.request_jump()
		caps = caps and c.count_kind("gunship") <= c.gunship_limit() and c.count_kind("gunship_missile") <= 4 and c.count_kind("flak") <= 8
		caps = caps and c.count_kind("drone") <= c.max_drones and c.count_interceptors() <= c.interceptor_limit() and c.count_kind("missile") <= c.missile_cap()
		for contact in c.contacts:
			if contact.kind == "carrier":
				caps = caps and c.count_base_drones(contact.id) <= c.max_drones_per_carrier and contact.position == contact.start
		if c.is_defeated():
			nuke_total += c.nuclear_launches
			intercept_total += c.nuclear_intercepts
			kills += c.carriers_destroyed
			retries += 1
			c.reset_battle()
	nuke_total += c.nuclear_launches
	intercept_total += c.nuclear_intercepts
	kills += c.carriers_destroyed
	check(caps, "Ten-minute combined combat keeps fighter/projectile caps and fixed capitals")
	check(nuke_total > 0 and intercept_total > 0 and kills > 0, "Simulation exercises nuclear launches, Gunship interceptions and capital kills")
	print("SIMULATION seconds=600 nuclear_launches=", nuke_total, " gunship_intercepts=", intercept_total, " capital_kills=", kills, " retries=", retries)
	console._process(0.0)
	check(console.get_node("HeaderMetrics/Enemies/Caption").text == "ENEMY FIGHTERS" and console.get_node("HeaderMetrics/Interceptors/Caption").text == "INTERCEPTORS ACTIVE", "HUD explicitly labels active enemy fighters and Interceptors")
	await process_frame
	var dome: Control = console.get_node("CenterContainer/Dome")
	check((panel.position + panel.size * 0.5).distance_to(dome.size * 0.5) < 1.0, "Game Over panel centered on radar")
	var buttons: Control = console.get_node("BottomButtons")
	check(buttons.get_child_count() == 6 and buttons.get_child(5).get_rect().end.x <= buttons.size.x, "All six action buttons fit in console (FIREWALL added)")
	print("GUNSHIP_RESULT checks=", checks, " failures=", failures)
	c._stop_special_audio()
	c.arrival_player.stop()
	c.launch_player.stop()
	c.klaxon_player.stop()
	console.free()
	console = null
	c = null
	await create_timer(0.2).timeout
	call_deferred("quit", 0 if failures == 0 else 1)
