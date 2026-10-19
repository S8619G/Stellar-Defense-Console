extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Returning Flights Test: return flights, vulnerability, hacking alerts,
## battery use meter, score count-up, chamfered buttons and build switch.
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
	c.reset_battle()
func base(x: float = 0.0) -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	return b
func interceptor() -> Dictionary:
	var v: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.phase = "intercept"
	return v

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	c = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	# 1.2.8: pins the 1.2.7 hack drain (2% a second) for this file's hull arithmetic;
	# the 1.5% default is checked in test_v128_features.
	c.hack_drain_percent_per_second = 2.0
	c.auto_spawn = false
	root.add_child(console)
	c.set_process(false)
	console.set_process(false)
	console.get_node("SweepLoop").stop()
	c.rng.seed = 5150
	clean()
	await process_frame

	# --- Returning Interceptors: lighter green, slow flash ---
	var v := interceptor()
	var normal: Color = c.display_color(v)
	v.phase = "return"
	c.battle_time = 0.0
	var bright: Color = c.display_color(v)
	c.battle_time = 0.5 / c.returning_flash_hz
	var dim: Color = c.display_color(v)
	check(bright.g >= normal.g and bright.r > normal.r + 0.1 and bright.b > normal.b + 0.1, "Returning Interceptor is a lighter shade of green")
	check(bright.a > 0.95 and dim.a < 0.6, "Returning Interceptor flashes slowly (bright then dim over one cycle)")
	check(c.returning_flash_hz <= 1.0 and c.returning_flash_hz < c.hacking_flash_hz / 4.0, "Return flash is slow compared with hacking flash")
	v.phase = "intercept"
	check(c.display_color(v) == normal, "Active Interceptor keeps normal green")

	# --- Attack Drones return to their Enemy Carrier and flash ---
	clean()
	var b := base()
	b.position = Vector3(-0.3, 0.6, 0.5)
	var r: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	r.phase = "harass"
	r.position = Vector3(0.0, -0.1, 0.05)
	r.age = c.drone_sortie_seconds + 0.1
	c._update_drone(r, 1.0 / 60.0)
	check(r.phase == "return", "Attack Drone returns to refuel and rearm after its sortie")
	var rc: Color = c.display_color(r)
	check(rc.g > c.hostile_color.g + 0.1, "Returning Attack Drone is a lighter shade of red")
	var gap0: float = r.position.distance_to(b.position)
	c._update_drone(r, 1.0)
	check(r.position.distance_to(b.position) < gap0, "Returning Attack Drone flies toward its Enemy Carrier")
	check(r.velocity.length() <= c.small_hostile_speed * c.returning_speed_factor + 0.0001, "Returning Attack Drone is slower (low on fuel)")
	r.position = b.position + Vector3(0.0, -0.03, 0.0)
	var score_before: int = c.score
	c._update_drone(r, 1.0 / 60.0)
	check(c.find_contact(r.id).is_empty() and c.drones_docked == 1 and c.score == score_before, "Attack Drone docks at Enemy Carrier without awarding points")
	check(c.count_base_drones(b.id) == 0, "Docked Attack Drone frees its Enemy Carrier launch slot")

	# Parent destroyed: return to nearest surviving Enemy Carrier, without changing launch ownership.
	clean()
	var b1 := base()
	var b2 := base()
	r = c.find_contact(c.spawn_from_carrier("drone", b1.id))
	r.phase = "harass"
	r.age = c.drone_sortie_seconds + 1.0
	c._hit_carrier(b1, 100.0)
	c._update_drone(r, 1.0 / 60.0)
	check(r.phase == "return" and r.home_id == b2.id and r.origin_id == b1.id, "Orphaned Attack Drone returns to another Enemy Carrier; launch ownership unchanged")
	check(c.count_base_drones(b2.id) == 0, "Orphaned Attack Drone does not consume the other Enemy Carrier's launch cap")
	c._hit_carrier(b2, 100.0)
	c._update_drone(r, 1.0 / 60.0)
	check(r.phase == "harass" and not c.find_contact(r.id).is_empty(), "With no Enemy Carrier left, Attack Drone keeps fighting")

	# --- Returning ships are more vulnerable ---
	clean()
	b = base()
	r = c.find_contact(c.spawn_from_carrier("drone", b.id))
	r.phase = "return"
	r.position = Vector3(0.1, 0.55, 0.3)
	v = interceptor()
	v.position = Vector3(0.0, 0.0, 0.0)
	var none: Array[String] = []
	check(c._hostile_target(v, none).id == r.id, "Interceptors pursue returning Attack Drones even beyond their normal screen")
	var fresh: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	fresh.phase = "harass"
	r.position = Vector3(0.18, 0.0, 0.0)
	fresh.position = Vector3(-0.14, 0.0, 0.0)
	check(c._hostile_target(v, none).id == r.id, "Returning Attack Drone is preferred over a slightly closer active Attack Drone")

	clean()
	b = base()
	r = c.find_contact(c.spawn_from_carrier("drone", b.id))
	r.phase = "harass"
	r.age = 0.0
	v = interceptor()
	v.phase = "return"
	v.age = c.sortie_seconds + 1.0
	r.position = Vector3(0.0, -0.3, 0.0)
	v.position = Vector3(0.02, -0.3, 0.0)
	c.returning_interceptor_loss_chance = 1.0
	c._update_drone(r, 1.0 / 60.0)
	check(c.find_contact(v.id).is_empty() and c.interceptors_lost == 1, "Attack Drone can shoot down a returning Interceptor")
	var v2 := interceptor()
	v2.position = r.position
	c._update_drone(r, 1.0 / 60.0)
	check(not c.find_contact(v2.id).is_empty(), "Active Interceptors remain protected as before")
	var v3 := interceptor()
	v3.phase = "return"
	v3.position = r.position
	c._update_drone(r, 1.0 / 60.0)
	check(not c.find_contact(v3.id).is_empty(), "Attack Drone attack has a cooldown")
	c.returning_interceptor_loss_chance = 0.5
	console._process(0.0)
	check(console.get_node("BattleReadout").text.contains("INTERCEPTORS LOST  1"), "Sidebar reports Interceptors lost")

	clean()
	b = base()
	c.launch_gunship()
	var rp: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "gunship":
			rp = contact
	rp.phase = "return"
	rp.position = b.position + Vector3(0.0, -0.3, 0.0)
	c.gunship_evasion_chance = 0.95
	c.returning_gunship_evasion_chance = 0.0
	var fl: String = c._fire_flak(b)
	var bolt: Dictionary = c.find_contact(fl)
	bolt.position = rp.position
	c._update_special_projectiles(0.0)
	# Firewall & Combat update (approved): Gunships now have Gunship Hit Points (4).
	check(rp.health == c.gunship_hit_points - 1, "Returning Gunship is easier to hit with Enemy Carrier flak")
	c.gunship_evasion_chance = 0.75
	c.returning_gunship_evasion_chance = 0.35
	check(c.display_color(rp).r > c.friendly_color.r + 0.1, "Returning Gunship also shows the lighter return shade")

	# --- Breacher hacking: rapid flash, alert box and countdown ---
	clean()
	c.breachers_enabled = true
	b = base()
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	check(c.hack_state() == "approach" and c.hacking_warning().contains("APPROACHING"), "Approaching Breacher is announced")
	h.position = h.hack_point
	c._update_breachers(0.0)
	c.battle_time = 0.0
	var on: Color = c.display_color(h)
	c.battle_time = 1.0 / (c.hacking_flash_hz * 2.0) + 0.001
	var off: Color = c.display_color(h)
	check(on.a > 0.9 and off.a < 0.3 and c.hacking_flash_hz >= 5.0, "Hacking Breacher flashes rapidly in its color")
	check(on.r == c.hostile_color.r and on.g == c.hostile_color.g, "Flash keeps the Breacher's own red")
	c._update_breachers(1.8)
	var text: String = c.hacking_warning()
	check(c.hack_state() == "hacking" and text.contains("HACKING SHIP") and text.contains("PENETRATING DEFENSES"), "Side alert says the ship is being hacked")
	check(text.contains("BREACH IN 4.2 s"), "Alert shows a countdown to hack completion")
	console._process(0.0)
	check(console.get_node("HackAlert").visible and console.get_node("HackAlert").text == text, "Alert label shows the countdown text")
	c._update_breachers(4.2)
	c._update_breachers(0.5)
	text = c.hacking_warning()
	check(c.hack_state() == "draining" and text.contains("COMPUTERS BREACHED") and text.contains("HULL DRAIN 2.0%"), "Completed hack switches alert to breach and drain rate")
	var b2h := base()
	var h2: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b2h.id))
	h2.position = h2.hack_point
	c._update_breachers(0.0)
	check(c.hacking_warning().contains("NEXT BREACH IN 6.0 s"), "Second hacker's countdown shown while first drains")
	c.battle_time = 0.0
	check(c.display_color(h).a > 0.9, "Draining Breacher keeps flashing")
	c.request_jump()
	check(c.hack_state() == "" and c.hacking_warning().is_empty(), "JUMP clears hacking alert")

	# --- Defense Shield use meter ---
	clean()
	check(c.battery_percent() == 100.0 and c.can_fire_battery(), "Battery starts full and ready")
	c.set_prox_defense(true)
	c._update_battery(3.0)
	check(is_equal_approx(c.battery_percent(), 50.0), "Firing depletes quickly: half in three seconds")
	c.set_prox_defense(false)
	c._update_battery(1.0)
	check(is_equal_approx(c.battery_percent(), 50.0), "Recharge waits a one-second delay after stopping")
	c._update_battery(12.0)
	check(is_equal_approx(c.battery_percent(), 100.0), "Recharges slowly: empty-to-full rate of twenty-four seconds (1.03)")
	check(c.battery_recharge_seconds == 24.0 and c.prox_burst_seconds == 6.0, "Depletes four times faster than it recharges (1.03)")
	c.set_prox_defense(true)
	c._update_battery(6.0)
	check(not c.prox_active and c.battery_percent() == 0.0, "Empty battery stops firing")
	c._update_battery(1.0 + 24.0 * 0.10)
	c.set_prox_defense(true)
	check(not c.prox_active and not c.can_fire_battery(), "Cannot refire until fifteen percent is restored")
	c._update_battery(24.0 * 0.06)
	console._process(0.0)
	check(c.can_fire_battery() and not console.get_node("BottomButtons/ProxDefense").disabled, "Battery and button become usable again past the restart level")
	check(console.get_node("BottomButtons/ProxDefense").text.contains("RECHARGING 16%"), "Button shows recharge percent")
	c.set_prox_defense(true)
	console._process(0.0)
	check(c.prox_active and console.get_node("BottomButtons/ProxDefense").text.contains("FIRING 16%"), "Button shows firing percent")
	c.set_prox_defense(false)
	c.reset_battle()
	console._process(0.0)
	check(c.battery_percent() == 100.0 and console.get_node("BottomButtons/ProxDefense").text.contains("READY 100%"), "Retry restores a full battery")

	# --- Score shows a single zero and counts up ---
	clean()
	console._process(0.016)
	check(console.get_node("ScoreValue").text == "0", "Score shows a single zero at start")
	c._hit_carrier(base(), 100.0)
	console._process(0.05)
	var mid := int(console.get_node("ScoreValue").text)
	check(mid > 0 and mid < 1000, "Score counts up instead of jumping")
	for i in range(120):
		console._process(1.0 / 60.0)
	check(console.get_node("ScoreValue").text == "1000", "Score count-up settles exactly on the real score")
	check(not console.get_node("ScoreValue").text.begins_with("0"), "No leading zeros")
	c.reset_battle()
	console._process(0.016)
	check(console.get_node("ScoreValue").text == "0", "Retry snaps the display back to zero")

	# --- Buttons match the notched frame ---
	var button: Button = console.get_node("BottomButtons/LaunchInterceptors")
	var ok := true
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := button.get_theme_stylebox(style_name) as StyleBoxFlat
		ok = ok and sb != null and sb.corner_detail == 1 and sb.corner_radius_top_left == 10 and sb.corner_radius_bottom_right == 10
		ok = ok and sb.border_width_top >= 2
	check(ok, "All button states use notched (chamfered) corners and at least a two-pixel line")
	var frame_script: GDScript = load("res://scripts/ConsoleFrame.gd")
	check(frame_script.get_script_constant_map().get("FRAME_WIDTH", 0.0) == 2.0, "Frame outline uses the same two-pixel line")

	# --- Development labels and F1 for test vs final build ---
	check(not console.development_build, "1.04: Development Build is off by default (labels and F1 hidden)")
	console.development_build = true  # ticked for tuning
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	console._input(key)
	check(console.get_node("TuningPanel").visible, "F1 opens tuning panel in a test build")
	console._input(key)
	console.development_build = false
	console._input(key)
	check(not console.get_node("TuningPanel").visible, "Final build setting disables F1 tuning panel")
	console.development_build = true

	# --- Ten-minute integrated simulation with return flights ---
	clean()
	c.auto_spawn = true
	c.breachers_enabled = true
	c.carrier_weapons_enabled = true
	c.own_weapons_enabled = true
	c.reset_battle()
	var caps := true
	var drone_returns := false
	var interceptor_returns := false
	var lost := 0
	var docked := 0
	var retries := 0
	for frame in range(36000):
		c._process(1.0 / 60.0)
		if frame % 600 == 0:
			c.launch_interceptors()
			c.launch_gunship()
		if frame % 300 == 0 and c.count_kind("missile") > 0:
			c.set_prox_defense(true)
		if frame % 300 == 150:
			c.set_prox_defense(false)
		if c.hull < 60:
			c.request_rapid_repair()
		# 1.2.2: faster nukes end this battle early, before Attack Drone sorties finish; the hull is
		# topped up (as in test_v120_waves_run) so return flights and docking are exercised.
		if c.hull < 30.0:
			c.hull = c.max_hull
		for contact in c.contacts:
			if contact.kind == "drone" and contact.phase == "return":
				drone_returns = true
			if contact.kind == "interceptor" and contact.phase == "return":
				interceptor_returns = true
			if contact.kind == "carrier":
				caps = caps and c.count_base_drones(contact.id) <= c.max_drones_per_carrier
		caps = caps and c.count_kind("drone") <= c.max_drones and c.count_interceptors() <= c.interceptor_limit() and c.count_tracks() <= c.max_contacts
		caps = caps and c.prox_burst_remaining >= 0.0 and c.prox_burst_remaining <= c.prox_burst_seconds
		if c.is_defeated():
			lost += c.interceptors_lost
			docked += c.drones_docked
			retries += 1
			c.reset_battle()
	lost += c.interceptors_lost
	docked += c.drones_docked
	check(caps, "Ten-minute simulation keeps all caps with return flights and battery meter")
	check(drone_returns and interceptor_returns and docked > 0, "Attack Drones and Interceptors actually return during play")
	print("RETURN_SIMULATION seconds=600 drones_docked=", docked, " interceptors_lost_returning=", lost, " retries=", retries, " score=", c.score)
	print("RETURNING_UPDATE_RESULT checks=", checks, " failures=", failures)
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	console = null
	c = null
	await create_timer(0.2).timeout
	call_deferred("quit", 0 if failures == 0 else 1)
