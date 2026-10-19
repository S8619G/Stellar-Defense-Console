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
	c.breachers_enabled = false
	c.reset_battle()
	c.auto_spawn = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false

func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	return b

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
	root.add_child(console)
	c.set_process(false)
	console.set_process(false)
	console.get_node("SweepLoop").stop()
	c.random_seed = 1234
	c.rng.seed = 1234
	clean()
	check(c.score == 0 and not c.rapid_repair_used, "Fresh run has zero score and one repair charge")
	check(c.prox_burst_remaining == 6.0, "Fresh battery contains six seconds of reserve")
	c.set_prox_defense(true)
	c._update_battery(2.0)
	c.set_prox_defense(false)
	check(c.prox_burst_remaining == 4.0 and c.prox_cooldown_remaining == 0.0, "Two seconds used leaves four, with no lockout")
	check(not c.battery_player.playing, "Paused battery sound stops")
	c._update_battery(120.0)
	check(c.prox_burst_remaining == 6.0 and c.prox_cooldown_remaining == 0.0, "Idle battery recharges back to full")
	c.set_prox_defense(true)
	c._update_battery(1.0)
	c.set_prox_defense(false)
	check(is_equal_approx(c.prox_burst_remaining, 5.0), "Firing drains quickly: one second of charge per second")
	for i in range(20):
		c.set_prox_defense(true)
		c.set_prox_defense(false)
	check(is_equal_approx(c.prox_burst_remaining, 5.0), "Toggle spam cannot add charge")
	c.set_prox_defense(true)
	c._update_battery(5.0)
	check(c.prox_burst_remaining == 0.0 and not c.prox_active, "Exactly empty stops firing")
	c.set_prox_defense(false)
	c.set_prox_defense(true)
	check(not c.prox_active, "Empty battery cannot be reactivated")
	c._update_battery(1.0)
	check(c.prox_burst_remaining == 0.0, "Recharge waits for the short delay")
	c._update_battery(2.0)
	c.set_prox_defense(true)
	check(not c.prox_active and c.battery_percent() < c.battery_restart_percent, "Cannot restart below the restart level")
	var kept: float = c.prox_burst_remaining
	c.request_jump()
	check(is_equal_approx(c.prox_burst_remaining, kept), "JUMP keeps current battery charge")
	c.safe_remaining = 0.0
	c._update_battery(2.0)  # 1.03: 24 s recharge, so 4 s of charging passes 15%
	c.set_prox_defense(true)
	check(c.prox_active, "Battery restarts once charge passes the restart level")
	c.set_prox_defense(false)
	clean()
	c.set_prox_defense(true)
	c._update_battery(2.5)
	c.score = 4500
	check(c.request_jump(), "Charged JUMP succeeds")
	check(c.score == 1500, "Successful JUMP deducts exactly 3000 points")
	check(c.prox_burst_remaining == 3.5 and not c.prox_active and c.prox_cooldown_remaining == 0.0, "JUMP stops firing and retains partial reserve")
	check(not c.request_jump() and c.score == 1500, "Rejected JUMP never deducts points")
	c.set_prox_defense(true)
	check(not c.prox_active, "Post-jump safety blocks defense")
	c.safe_remaining = 0.0
	c.set_prox_defense(true)
	check(c.prox_active and c.prox_burst_remaining == 3.5, "Defense resumes retained reserve after safety")
	clean()
	c.score = 100
	c.request_jump()
	check(c.score == 0, "JUMP score floor is zero")
	clean()
	var b := base()
	var drone: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	drone.position = Vector3(0.0, 0.0, 0.0)
	c.launch_interceptors()
	for ship in c.contacts:
		if ship.kind == "interceptor":
			ship.phase = "intercept"
			ship.position = drone.position
	c._update_interceptors(0.0)
	check(c.find_contact(drone.id).is_empty() and c.score == 100, "Actual Interceptor kill awards one Attack Drone score despite two interceptors")
	c._award_destroyed(drone)
	check(c.score == 100, "Stale destroyed contact cannot score twice")
	c._hit_carrier(b, 5.0)
	check(c.score == 100, "Nonlethal capital hit awards no points")
	c._hit_carrier(b, 0.5, true)
	c._hit_carrier(b, 0.5, true)
	check(c.score == 1100 and c.carriers_destroyed == 1, "Mixed main and Gunship capital damage awards one 1000-point kill")
	c._hit_carrier(b, 9.0)
	check(c.score == 1100, "Duplicate capital hit cannot repeat award")
	clean()
	b = base()
	c.nuclear_hit_points = 1  # 1.02: one-hit setting reproduces the original instant interception
	var n: Dictionary = c.find_contact(c._launch_nuclear(b))
	for i in range(2):
		c.gunship_cooldown_remaining = 0.0
		c.launch_gunship()
	for ship in c.contacts:
		if ship.kind == "gunship":
			ship.phase = "patrol"
			ship.position = n.position
	c._update_gunships(0.0)
	check(c.score == 500 and c.nuclear_intercepts == 1 and c.find_contact(n.id).is_empty(), "Actual Gunship interception awards nuclear value once")
	c._award_destroyed(n)
	check(c.score == 500, "Stale nuke cannot repeat award")
	var missile: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	c._award_destroyed(missile)
	check(c.score == 500, "Conventional missile has no score award")
	c._remove_contact(missile.id)
	check(c.score == 500, "Generic cleanup does not award score")
	c.request_jump()
	check(c.score == 0 and c.contacts.is_empty(), "JUMP clears contacts without kill credit")
	clean()
	b = base()
	n = c.find_contact(c._launch_nuclear(b))
	n.position = c.own_ship_position
	c._update_special_projectiles(0.0)
	check(c.hull == 40.0 and c.score == 0, "Nuclear impact cannot count as interception")
	clean()
	check(not c.request_rapid_repair() and not c.rapid_repair_used, "Full hull rejects repair without wasting charge")
	c.apply_damage(60.0)
	check(c.request_rapid_repair() and c.rapid_repair_used, "Damaged hull consumes one repair charge")
	check(not c.request_rapid_repair(), "Second repair request is rejected")
	c._update_rapid_repair(2.0)
	check(c.hull == 50.0 and c.rapid_repair_remaining == 3.0, "Repair adds ten percentage points in first two seconds")
	c.apply_damage(10.0)
	c._update_rapid_repair(1.0)
	check(c.hull == 45.0, "Repair does not shield concurrent incoming damage")
	c.request_jump()
	check(c.rapid_repair_used and c.rapid_repair_remaining == 2.0, "JUMP retains used charge and ongoing repair")
	c._update_rapid_repair(10.0)
	check(c.hull == 55.0 and c.rapid_repair_remaining == 0.0, "Large time step cannot exceed total 25-point repair allowance")
	check(not c.request_rapid_repair(), "JUMP cannot replenish repair charge")
	clean()
	c.hull = 95.0
	c.request_rapid_repair()
	c._update_rapid_repair(5.0)
	check(c.hull == 100.0 and c.rapid_repair_used, "Repair caps at full hull; unused excess is not banked")
	clean()
	c.max_hull = 200.0
	c.hull = 80.0
	c.request_rapid_repair()
	c._update_rapid_repair(5.0)
	check(c.hull == 130.0, "Repair scales to configured maximum hull")
	c.max_hull = 100.0
	clean()
	c.hull = 30.0
	c.request_rapid_repair()
	c.score = 1700
	c.apply_damage(1000.0)
	c._update_rapid_repair(100.0)
	check(c.hull == 0.0 and c.rapid_repair_remaining == 0.0, "Lethal damage cancels repair; no siege")
	check(not c.request_rapid_repair() and not c.request_jump() and c.score == 1700, "Death blocks repair and jump without score changes")
	console._process(5.0)
	check(console.get_node("ScoreValue").text == "1700", "Score counter counts up to live value without leading zeros")
	check(console.get_node("CenterContainer/Dome/GameOverPanel/FinalScore").text == "FINAL SCORE  1700", "Game Over displays final score")
	console.get_node("CenterContainer/Dome/GameOverPanel/Retry").pressed.emit()
	console._process(0.0)
	check(c.score == 0 and c.scored_contacts.is_empty(), "Retry resets score and duplicate-award ledger")
	check(not c.rapid_repair_used and c.prox_burst_remaining == 6.0 and c.hull == 100.0, "Retry restores hull, repair charge and battery")
	check(console.get_node_or_null("BottomButtons/Hail") == null, "Unused Hail button removed")
	check(console.get_node("BottomButtons/RapidRepair").disabled, "Full-hull repair button disabled")
	c.apply_damage(40.0)
	console._process(0.0)
	check(not console.get_node("BottomButtons/RapidRepair").disabled, "Damage enables repair button")
	console.get_node("BottomButtons/RapidRepair").pressed.emit()
	check(c.rapid_repair_used, "Actual repair button signal invokes one-use repair")
	console.get_node("BottomButtons/ProxDefense").toggled.emit(true)
	c._update_battery(1.0)
	console.get_node("BottomButtons/ProxDefense").toggled.emit(false)
	console._process(0.0)
	check(not c.prox_active and c.prox_burst_remaining == 5.0 and console.get_node("BottomButtons/ProxDefense").text.contains("83%"), "UI toggle stops firing and shows charge percent")
	b = base()
	c.spawn_from_carrier("drone", b.id)
	c.launch_interceptors()
	c.launch_gunship()
	console._process(0.0)
	check(console.get_node("HeaderMetrics/Enemies/Value").text == "1", "Enemy counter reflects active Attack Drones")
	check(console.get_node("HeaderMetrics/Interceptors/Value").text == "2 / 6", "Interceptor counter reflects active capacity")
	check(console.get_node("HeaderMetrics/Gunships/Value").text == "1 / 2", "Gunship counter reflects active capacity")
	check(console.get_node("HeaderMetrics/Enemy Carriers/Value").text == "1", "Capital counter reflects identified Enemy Carriers")
	check(not console.get_node("TuningPanel").visible, "Tuning panel does not obscure gameplay by default")
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	console.development_build = true  # 1.04: off by default; ticked for tuning
	console._input(key)
	check(console.get_node("TuningPanel").visible, "F1 still opens tuning controls")
	console._input(key)
	check(not console.get_node("TuningPanel").visible, "F1 closes tuning controls")
	check(console.get_node("ShipStatus").defense_gap_pixels == 12.0, "Defense line has configurable twelve-pixel outward gap")
	check(console.sweep_volume_db == -20.0, "Ambient RADAR stays at minus twenty dB")
	await process_frame
	await process_frame
	var buttons: Control = console.get_node("BottomButtons")
	var status: Control = console.get_node("ShipStatus")
	print("LAYOUT root=", console.size, " ship=", status.get_global_rect(), " buttons=", buttons.get_global_rect())
	check(status.get_global_rect().end.y < buttons.global_position.y, "Ship status and controls do not overlap")
	check(buttons.get_global_rect().end.y < console.size.y - 28.0, "Buttons fit inside outer frame")
	var bounds_ok := true
	var previous_right := 0.0
	for button in buttons.get_children():
		bounds_ok = bounds_ok and button.position.x >= previous_right and button.get_rect().end.x <= buttons.size.x
		previous_right = button.get_rect().end.x
	check(bounds_ok, "All controls fit without horizontal overlap")
	check(console.get_node("HeaderMetrics").get_global_rect().end.x < console.get_node("ScoreValue").global_position.x, "Counters and score occupy separate header regions")
	print("CONSOLE_RESULT checks=", checks, " failures=", failures)
	c._stop_special_audio()
	c.arrival_player.stop()
	c.launch_player.stop()
	c.klaxon_player.stop()
	console.get_node("SweepLoop").stop()
	# Same teardown as the other suites: stop every player and let audio settle before freeing.
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	console = null
	c = null
	await create_timer(0.2).timeout
	call_deferred("quit", 0 if failures == 0 else 1)
