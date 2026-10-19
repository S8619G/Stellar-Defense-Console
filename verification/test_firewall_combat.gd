extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Firewall & Combat Test: header/ship-status layout, INTRUSION DETECTION,
## FIREWALL button, moving Siege Ship with spread timed barrages, and
## Interceptor/Gunship combat losses with point penalties.
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
	c.breachers_enabled = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.nuclear_weapons_enabled = false
	c.siege_enabled = false
	c.reset_battle()
func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
	return b
func at_wave(n: int) -> void:
	c.battle_time = (n - 1) * c.wave_seconds + 1.0
	c._update_wave()
func parked_heavy(phase: String) -> Dictionary:
	c.breachers_enabled = true
	var b := base()
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	h.position = h.hack_point
	h.phase = phase
	h.hack_remaining = c.hacking_seconds
	return h
func drone_at(target: Dictionary) -> Dictionary:
	var b := base()
	var r: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	r.phase = "harass"
	r.position = target.position + Vector3(0.02, 0.0, 0.0)
	r.attack_cooldown = 0.0
	return r

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
	c.rng.seed = 7
	clean()
	await process_frame

	# --- 1. Header and ship-status layout ---
	check(console.get_node("TopChrome").text == "RADAR", "Title reads RADAR")
	var frame_source := FileAccess.get_file_as_string("res://scripts/ConsoleFrame.gd")
	check(not frame_source.contains("\"SHIP STATUS\""), "SHIP STATUS text removed beside the ship outline")
	var status: Control = console.get_node("ShipStatus")
	check(status.jump_center > 0.02 and status.jump_center < 0.26 and absf(status.jump_center - 0.18) < 0.02, "JUMP centered in the left (stern) section of the outline")
	check(status.hull_center > 0.72 and status.hull_center < 0.99 and absf(status.hull_center - 0.855) < 0.02, "HULL centered in the right (bow) section of the outline")
	var buttons: Control = console.get_node("BottomButtons")
	await process_frame
	var names: Array = []
	var fits := true
	var previous := -1.0
	for button in buttons.get_children():
		names.append(String(button.name))
		fits = fits and button.position.x >= previous and button.get_rect().end.x <= buttons.size.x
		previous = button.get_rect().end.x
	check(names == ["RapidRepair", "Jump", "ProxDefense", "Firewall", "LaunchInterceptors", "LaunchGunship"], "FIREWALL button sits next to DEFENSE SHIELD")
	check(fits, "Six buttons fit without overlap")
	var firewall_button: Button = buttons.get_node("Firewall")
	check(firewall_button.toggle_mode, "FIREWALL is an on/off button like DEFENSE SHIELD")

	# --- 2. Intrusion detection and FIREWALL ---
	clean()
	console._process(0.016)
	check(not c.firewall_needed() and not c.can_deploy_firewall() and firewall_button.disabled and firewall_button.text.contains("STANDBY"), "FIREWALL on standby until a Breacher hacks")
	check(not (c.hack_state() in ["hacking", "draining"]), "No INTRUSION DETECTION box without a hack")
	var h := parked_heavy("approach")
	h.position = h.hack_point
	c._update_breachers(1.0 / 60.0)
	check(h.phase == "hacking" and c.hack_state() == "hacking", "Breacher begins hacking")
	console._process(0.016)
	check(c.can_deploy_firewall() and not firewall_button.disabled and firewall_button.text.contains("READY 100%"), "FIREWALL becomes available once hacking begins")
	check(c.hack_state() in ["hacking", "draining"], "INTRUSION DETECTION box shown while hacking")
	# Hack speed without and with the firewall
	var before: float = h.hack_remaining
	for i in range(60):
		c._update_breachers(1.0 / 60.0)
	var normal: float = before - h.hack_remaining
	firewall_button.toggled.emit(true)
	check(c.firewall_active and c.firewall_player.playing and c.firewall_uses == 1, "Pressing FIREWALL deploys it with its electronic sound")
	check(c.hacking_warning().contains("FIREWALL UP"), "Hacking alert shows FIREWALL UP | HACK SLOWED")
	before = h.hack_remaining
	for i in range(60):
		c._update_breachers(1.0 / 60.0)
		c._update_firewall(1.0 / 60.0)
	var slowed: float = before - h.hack_remaining
	check(absf(normal - 1.0) < 0.01 and absf(slowed - 0.25) < 0.01, "Firewall slows the hack to a quarter speed")
	console._process(0.016)
	check(firewall_button.button_pressed and firewall_button.text.contains("ACTIVE"), "Button shows ACTIVE with the remaining charge")
	for i in range(60 * 3 + 2):
		c._update_firewall(1.0 / 60.0)
	check(not c.firewall_active and c.firewall_charge == 0.0 and not c.firewall_player.playing, "Firewall is used up after 4 seconds")
	check(c.status_message.begins_with("FIREWALL SPENT"), "Status reports FIREWALL SPENT")
	check(c.firewall_seconds < c.prox_burst_seconds and c.firewall_recharge_seconds < c.battery_recharge_seconds, "Used up faster and recharges faster than the Defense Shield")
	for i in range(int(60 * 2.4)):
		c._update_firewall(1.0 / 60.0)
	check(not c.can_deploy_firewall(), "Cannot redeploy until it recharges to 25%")
	for i in range(int(60 * 0.2)):
		c._update_firewall(1.0 / 60.0)
	check(c.can_deploy_firewall(), "Redeploy possible at 25% (0.5 s pause + 2 s)")
	for i in range(60 * 7):
		c._update_firewall(1.0 / 60.0)
	check(c.firewall_percent() == 100.0, "Full recharge within 8.5 seconds")
	# Drain slowed too
	h.phase = "draining"
	h.hack_remaining = 0.0
	var hull_before: float = c.hull
	for i in range(60):
		c._update_breachers(1.0 / 60.0)
	var normal_drain: float = hull_before - c.hull
	c.set_firewall(true)
	hull_before = c.hull
	for i in range(60):
		c._update_breachers(1.0 / 60.0)
	check(absf(normal_drain - 2.0) < 0.05 and absf(hull_before - c.hull - 0.5) < 0.05, "Firewall also slows the hull drain")
	# Firewall lowers itself when the hack ends, keeping its charge
	var kept: float = c.firewall_charge
	for i in range(3):
		c._hit_breacher(h)
	c._update_firewall(0.0)
	check(not c.firewall_active and is_equal_approx(c.firewall_charge, kept) and not c.firewall_needed(), "Firewall lowers itself when the hack ends and keeps its charge")
	h = parked_heavy("hacking")
	c.set_firewall(true)
	c.set_firewall(false)
	check(not c.firewall_active and c.firewall_charge > 0.0, "Pressing again lowers the firewall")
	c.firewall_slow_factor = 0.0
	c.set_firewall(true)
	before = h.hack_remaining
	c._update_breachers(0.5)
	check(h.hack_remaining == before, "Firewall strength is adjustable in the Inspector (0 freezes the hack)")
	c.firewall_slow_factor = 0.25
	c.jump_recharge_remaining = 0.0
	c.request_jump()
	c._update_firewall(0.0)
	check(not c.firewall_active and not c.firewall_player.playing, "JUMP stops the firewall")
	c.reset_battle()
	check(c.firewall_percent() == 100.0 and c.firewall_uses == 0, "Retry restores a full firewall")
	var wav: AudioStreamWAV = c.firewall_player.stream
	var peak := 0
	for i in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	var first := wav.data.decode_s16(0)
	var last := wav.data.decode_s16(wav.data.size() - 2)
	check(wav.mix_rate == 22050 and wav.data.size() == 22050 * 2 and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end == 22050, "Electronic defense sound is a one-second seamless loop")
	check(peak > 3000 and peak < 30000 and absi(first - last) < 1500, "Sound is audible, not clipped, and has no click at the loop point")
	check(c.firewall_volume_db == -12.0, "Firewall sound volume -12 dB (adjustable)")

	# --- 3. Fighter losses ---
	clean()
	# Combat Tuning update (approved): defaults are now Interceptor 2 / Gunship 7 hit points with
	# Interceptor evasion (see test_combat_tuning). The loss mechanics below are checked at 4 / 4.
	check(c.interceptor_hit_points == 2 and c.gunship_hit_points == 7 and c.gunship_hit_points > c.breacher_hit_points, "Combat Tuning defaults: Interceptors 2 hits, Gunships 7 hits")
	var default_interceptor_hp: int = c.interceptor_hit_points
	var default_gunship_hp: int = c.gunship_hit_points
	var default_interceptor_evasion: float = c.interceptor_evasion_chance
	var default_hit_chance: float = c.drone_hit_chance
	c.interceptor_hit_points = 4
	c.gunship_hit_points = 4
	c.interceptor_evasion_chance = 0.0
	var v: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.phase = "intercept"
	v.position = Vector3(0.0, -0.1, 0.0)
	check(v.health == 4 and v.max_health == 4, "New Interceptors start with 4 hit points")
	c.score = 1000
	c.earned_points = 1000
	c.drone_hit_chance = 1.0
	var r := drone_at(v)
	c._update_drone(r, 1.0 / 60.0)
	check(v.health == 3 and c.interceptors_lost == 0, "Attack Drones can hit active Interceptors")
	check(c.fighter_health_percent(v) == 75, "Damaged Interceptor label shows 75%")
	for i in range(3):
		r.attack_cooldown = 0.0
		r.position = v.position + Vector3(0.02, 0.0, 0.0)
		c._update_drone(r, 1.0 / 60.0)
	check(c.find_contact(v.id).is_empty() and c.interceptors_lost == 1, "Fourth hit destroys the Interceptor")
	check(c.score == 800 and c.earned_points == 1000 and c.fighter_points_lost == 200, "Losing a Interceptor costs 200 points; bonus progress kept")
	check(c.status_message.contains("INTERCEPTOR LOST") and c.status_message.contains("-200"), "Status reports the Interceptor loss and penalty")
	check(c.count_interceptors() == 0 and c.launch_interceptors() > 0, "A lost Interceptor frees its launch slot")
	clean()
	var rp: Dictionary = c.find_contact(c._spawn_gunship())
	rp.phase = "patrol"
	rp.position = Vector3(0.1, -0.2, 0.0)
	check(rp.health == 4, "New Gunships start with 4 hit points")
	c.score = 300
	c.drone_hit_chance = 1.0
	c.gunship_evasion_chance = 0.0
	r = drone_at(rp)
	for i in range(4):
		r.attack_cooldown = 0.0
		r.position = rp.position + Vector3(0.02, 0.0, 0.0)
		c._update_drone(r, 1.0 / 60.0)
	check(c.find_contact(rp.id).is_empty() and c.gunships_lost == 1, "Attack Drones can shoot down a Gunship in four hits")
	check(c.score == 0 and c.fighter_points_lost == 300, "Gunship loss costs 400 points but the score never drops below zero")
	clean()
	rp = c.find_contact(c._spawn_gunship())
	rp.phase = "patrol"
	rp.position = Vector3(0.1, -0.2, 0.0)
	c.gunship_evasion_chance = 0.95
	c.drone_hit_chance = 1.0
	r = drone_at(rp)
	for i in range(20):
		r.attack_cooldown = 0.0
		r.position = rp.position + Vector3(0.02, 0.0, 0.0)
		c._update_drone(r, 1.0 / 60.0)
	check(c.gunship_evades >= 15, "Gunships still evade Attack Drone fire using Gunship Evasion Chance")
	c.gunship_evasion_chance = 0.75
	clean()
	var b := base()
	rp = c.find_contact(c._spawn_gunship())
	rp.phase = "attack"
	rp.position = b.position + Vector3(0.0, -0.4, 0.0)
	c.gunship_evasion_chance = 0.0
	c.score = 5000
	for i in range(4):
		var bolt: String = c._fire_flak(b)
		c.find_contact(bolt).position = rp.position
		c._update_special_projectiles(0.0)
	check(c.find_contact(rp.id).is_empty() and c.gunships_lost == 1 and c.score == 4600, "Enemy Carrier flak destroys a Gunship after four hits, -400 points")
	c.gunship_evasion_chance = 0.75
	clean()
	v = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.phase = "return"
	v.position = Vector3(0.0, -0.3, 0.0)
	c.returning_interceptor_loss_chance = 1.0
	c.score = 1000
	r = drone_at(v)
	c._update_drone(r, 1.0 / 60.0)
	check(c.find_contact(v.id).is_empty() and c.interceptors_lost == 1 and c.score == 800, "Returning Interceptors are still easy prey, and also cost 200 points")
	c.returning_interceptor_loss_chance = 0.5
	c.gunships_lost = 2
	console._process(0.016)
	var readout: String = console.get_node("BattleReadout").text
	check(readout.contains("INTERCEPTORS LOST  1") and readout.contains("GUNSHIPS LOST  2"), "Sidebar counts Interceptors lost and Gunships lost")
	clean()
	c.fighter_losses_enabled = false
	v = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.phase = "intercept"
	v.position = Vector3(0.0, -0.1, 0.0)
	r = drone_at(v)
	c._update_drone(r, 1.0 / 60.0)
	check(v.health == 4, "Fighter Losses can be switched off in the Inspector")
	c.fighter_losses_enabled = true
	c.drone_hit_chance = default_hit_chance
	c.interceptor_hit_points = default_interceptor_hp
	c.gunship_hit_points = default_gunship_hp
	c.interceptor_evasion_chance = default_interceptor_evasion
	c.reset_battle()
	check(c.interceptors_lost == 0 and c.gunships_lost == 0 and c.fighter_points_lost == 0, "Retry clears the loss counters")

	# --- 4. Moving Siege Ship ---
	clean()
	c.siege_enabled = true
	at_wave(2)
	var lefts := 0
	var rights := 0
	var lane_ok := true
	var edge_ok := true
	for i in range(30):
		var rs: Dictionary = c.find_contact(c.spawn_siege_ship())
		lane_ok = lane_ok and rs.position.y >= c.siege_lane.x - 0.001 and rs.position.y <= c.siege_lane.y + 0.001
		var edge := sqrt(1.0 - rs.position.y * rs.position.y)
		edge_ok = edge_ok and absf(absf(rs.position.x) - edge) < 0.001 and is_equal_approx(rs.finish.x, -rs.position.x) and rs.finish.y == rs.position.y
		if rs.position.x < 0.0:
			lefts += 1
		else:
			rights += 1
		c._remove_contact(rs.id)
	check(lefts > 5 and rights > 5, "Enters from the left or the right at random")
	check(edge_ok and lane_ok, "Appears at the scope edge and heads straight for the opposite edge")
	var ship: Dictionary = c.find_contact(c.spawn_siege_ship())
	var start: Vector3 = ship.position
	for i in range(600):
		c._update_siege(ship, 1.0 / 60.0)
	check(absf(start.distance_to(ship.position) - 0.30) < 0.005, "Crosses at 0.03 scope radii per second")
	check(c.siege_barrages >= 1, "Fires barrages while crossing")
	var crossing: float = start.distance_to(ship.finish) / c.siege_speed
	check(crossing > 55.0 and crossing < 70.0, "Takes about a minute to cross")
	var guard := 0
	while not c.find_contact(ship.id).is_empty() and guard < 60 * 120:
		c._update_siege(ship, 1.0 / 60.0)
		guard += 1
	check(c.find_contact(ship.id).is_empty() and c.sieges_escaped == 1 and c.sieges_destroyed == 0, "Disappears when it reaches the other side")
	check(c.status_message.begins_with("SIEGE SHIP LEFT") and c.siege_cooldown_remaining == c.siege_cooldown_now(), "Escape is announced and starts the quiet period (no points)")
	# Spread, timed barrages
	clean()
	c.siege_enabled = true
	at_wave(2)
	ship = c.find_contact(c.spawn_siege_ship())
	ship.barrage_timer = 0.01
	var spawned: Array = []
	var times: Array = []
	var t := 0.0
	while spawned.size() < 3 and t < 5.0:
		c._process(1.0 / 60.0)
		t += 1.0 / 60.0
		for m in c.contacts:
			if m.kind == "missile" and not (m.id in spawned):
				spawned.append(m.id)
				times.append(t)
	check(spawned.size() == 3 and times[2] - times[0] > 1.9, "Barrage missiles are timed one after another, not all at once")
	var spreads: Array = []
	for id in spawned:
		spreads.append(snappedf(c.find_contact(id).spread, 0.01))
	check(spreads == [-0.6, 0.0, 0.6], "Barrage fans out left, center and right")
	for i in range(60 * 5):
		c._process(1.0 / 60.0)
	var xs: Array = []
	for id in spawned:
		var m: Dictionary = c.find_contact(id)
		if not m.is_empty():
			# Sideways distance from the straight line to the ship.
			xs.append((m.position - c.own_ship_position).dot(m.side))
	xs.sort()
	check(xs.size() == 3 and xs[1] - xs[0] > 0.12 and xs[2] - xs[1] > 0.12, "Barrage missiles fly well apart, not lined up in a row")
	var faster := true
	for n in range(1, 10):
		at_wave(n)
		faster = faster and c.siege_barrage_interval_now() < c.missile_launch_interval * c.wave_interval_multiplier()
	check(faster, "Fires faster than Enemy Carriers in every wave")
	# Less damage per missile
	clean()
	c.siege_enabled = true
	at_wave(2)
	ship = c.find_contact(c.spawn_siege_ship())
	var rm: Dictionary = c.find_contact(c.spawn_from_carrier("missile", ship.id))
	rm.damage = c.siege_missile_damage
	rm.position = c.own_ship_position
	c._resolve_missiles()
	var res_damage: float = c.max_hull - c.hull
	c.hull = c.max_hull
	var bb := base()
	var bmiss: Dictionary = c.find_contact(c.spawn_from_carrier("missile", bb.id))
	bmiss.position = c.own_ship_position
	c._resolve_missiles()
	var base_damage: float = c.max_hull - c.hull
	check(res_damage == 5.0 and base_damage == 10.0, "Siege missiles do 5 hull damage, Enemy Carrier missiles 10")
	# Frequency rises with the waves
	var chances: Array = []
	var cooldowns: Array = []
	for n in [2, 4, 6, 9]:
		at_wave(n)
		chances.append("%.2f" % c.siege_chance_now())
		cooldowns.append(int(c.siege_cooldown_now()))
	check(chances == ["0.25", "0.35", "0.45", "0.60"], "Arrival chance rises 25% -> 60% as waves get tougher")
	check(cooldowns == [90, 70, 50, 40], "Quiet period shrinks 90 s -> 40 s as waves get tougher")
	# Enemy Carrier placement no longer blocked by the moving ship
	clean()
	c.siege_enabled = true
	at_wave(5)
	c.spawn_siege_ship()
	var placed := 0
	for i in range(4):
		if not base().is_empty():
			placed += 1
	check(placed == 4, "Four Enemy Carriers still fit while the Siege Ship crosses")
	check(c.siege_hit_points == 10 and c.siege_points == 2500, "Hit points 10 (crossing ship can escape), worth 2,500")

	# A focused attack (Gunships + ship missiles) can destroy it before it escapes
	clean()
	c.own_weapons_enabled = true
	c.siege_enabled = true
	at_wave(2)
	c.spawn_siege_ship()
	var spent := 0.0
	while not c.siege_ship().is_empty() and spent < 90.0:
		c._process(1.0 / 60.0)
		spent += 1.0 / 60.0
		if int(spent * 60.0) % 120 == 0:
			c.launch_gunship()
	print("FOCUSED_ATTACK seconds=", snappedf(spent, 0.1), " destroyed=", c.sieges_destroyed)
	check(c.sieges_destroyed == 1 and c.sieges_escaped == 0 and spent < crossing, "A focused attack destroys it before it escapes")

	# --- 5. Integrated ten-minute battle ---
	clean()
	c.auto_spawn = true
	c.carrier_weapons_enabled = true
	c.own_weapons_enabled = true
	c.breachers_enabled = true
	c.nuclear_weapons_enabled = true
	c.siege_enabled = true
	# 1.2.0: this checks the original combat flow, so it runs on the classic timer waves.
	c.defined_waves = false
	# 1.2.7: the faster nukes change how this scripted run plays out; it checks the
	# classic combat flow, so it pins the 1.2.6 nuke speeds (test_v127_features checks the new ones).
	c.easy_nuke_speed = 1.0
	c.normal_nuke_speed = 1.1
	c.hard_nuke_speed = 1.6
	c.reset_battle()
	var caps := true
	var never_negative := true
	var firewall_used := 0
	var retries := 0
	var lost_v := 0
	var lost_r := 0
	var escaped := 0
	var destroyed := 0
	for frame in range(60 * 600):
		c._process(1.0 / 60.0)
		if frame % 300 == 0:
			c.launch_interceptors()
			c.launch_gunship()
		if frame % 240 == 0:
			c.set_prox_defense(true)
		if c.can_deploy_firewall() and not c.firewall_active:
			c.set_firewall(true)
		if c.hull < 60.0:
			c.request_rapid_repair()
		never_negative = never_negative and c.score >= 0
		caps = caps and c.count_kind("missile") <= c.missile_cap() and c.count_kind("siege_ship") <= 1 and c.count_tracks() <= c.max_contacts
		if c.is_defeated():
			lost_v += c.interceptors_lost
			lost_r += c.gunships_lost
			escaped += c.sieges_escaped
			destroyed += c.sieges_destroyed
			firewall_used += c.firewall_uses
			retries += 1
			c.reset_battle()
	lost_v += c.interceptors_lost
	lost_r += c.gunships_lost
	escaped += c.sieges_escaped
	destroyed += c.sieges_destroyed
	firewall_used += c.firewall_uses
	print("COMBAT_SIMULATION seconds=600 interceptors_lost=", lost_v, " gunships_lost=", lost_r, " firewall_uses=", firewall_used,
		" sieges_destroyed=", destroyed, " sieges_escaped=", escaped, " retries=", retries, " score=", c.score, " wave=", c.wave)
	check(caps and never_negative, "Ten-minute battle: limits hold and the score never goes negative")
	check(lost_v + lost_r > 0 and firewall_used > 0, "Ten-minute battle: fighters are lost in combat and the firewall gets used")

	print("FIREWALL_COMBAT_RESULT checks=", checks, " failures=", failures)
	for p in console.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	await create_timer(0.3).timeout
	console.free()
	console = null
	c = null
	await create_timer(0.2).timeout
	call_deferred("quit", 0 if failures == 0 else 1)
