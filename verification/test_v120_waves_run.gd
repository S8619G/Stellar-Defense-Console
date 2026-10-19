extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.2.0: a fifteen-minute defined-wave battle on Normal
## (hull topped up so a full set, the bonus sweep and set 2 are reached).
## Checks every limit each frame, the phase order, rest lengths and wave numbering.
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

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://test_v120_run_scores.json"
	console.settings_file = "user://test_v120_run.cfg"
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
	c.auto_spawn = true
	c.difficulty = 1
	# 1.2.2: this run checks the 1.2.0 sweep path and bonus mix, so it selects the
	# Bonus sweep (Set End Round) and the 1.2.0 schedule (a bonus every wave, all eight).
	c.set_end_round = 1
	c.bonus_start_wave = 1
	c.bonus_wave_chance = 1.0
	c.bonus_low_tier.assign(["REPAIR", "EMP", "INTERCEPTORS", "GUNSHIP", "SPEED", "AUTO SHIELD", "RAPID FIRE", "STEALTH"])
	c.bonus_low_tier_set = 1
	c.bonus_medium_tier_set = 99
	c.bonus_high_tier_set = 99
	c.rng.seed = 120
	c.reset_battle()
	var caps_ok := true
	var first_bad := ""
	var order_ok := true
	var numbering_ok := true
	var last_phase: String = c.wave_phase
	var rest_started := 0.0
	var rest_lengths: Array[float] = []
	var assault_started := 0.0
	var longest_assault := 0.0
	var sweep_seen := false
	var max_mult := 1.0
	var last_wave: int = c.wave
	var max_capitals := 0
	var step := 1.0 / 60.0
	for frame in range(60 * 900):
		c._process(step)
		if frame % 300 == 0:
			c.launch_interceptors()
			c.launch_gunship()
		if frame % 240 == 0:
			c.set_prox_defense(true)
		if c.hull < 30.0:
			c.hull = c.max_hull
		var capitals: int = c.count_kind("carrier") + c.count_kind("unknown")
		max_capitals = maxi(max_capitals, capitals)
		var bad := ""
		if capitals > c.carrier_cap(): bad = "carriers"
		elif c.count_kind("breacher") > c.breacher_cap(): bad = "heavy"
		elif c.count_kind("drone") > c.max_drones: bad = "drones"
		elif c.count_tracks() > c.max_contacts: bad = "tracks"
		elif c.count_kind("missile") > c.missile_cap(): bad = "missiles"
		elif c.count_interceptors() > c.interceptor_limit(): bad = "interceptors"
		elif c.count_kind("gunship") > c.gunship_limit(): bad = "gunships"
		elif c.count_kind("siege_ship") > 1: bad = "siege"
		if bad != "" and caps_ok:
			caps_ok = false
			first_bad = "%s at %.1f s (wave %d %s)" % [bad, c.battle_time, c.wave, c.wave_phase]
		if c.wave_phase != last_phase:
			var allowed := {"assault": ["rest"], "rest": ["assault", "sweep"], "sweep": ["rest"]}
			if c.wave_phase not in allowed.get(last_phase, []):
				order_ok = false
				print("BAD_ORDER ", last_phase, " -> ", c.wave_phase)
			if last_phase == "rest":
				rest_lengths.append(c.battle_time - rest_started)
			if last_phase == "assault":
				longest_assault = maxf(longest_assault, c.battle_time - assault_started)
			if c.wave_phase == "rest":
				rest_started = c.battle_time
			if c.wave_phase == "assault":
				assault_started = c.battle_time
				numbering_ok = numbering_ok and c.wave == last_wave + 1
				last_wave = c.wave
			if c.wave_phase == "sweep":
				sweep_seen = true
				numbering_ok = numbering_ok and c.wave % c.wave_set_size == 0
			last_phase = c.wave_phase
		max_mult = maxf(max_mult, c.set_score_multiplier())
	var rests_ok := true
	for length in rest_lengths:
		rests_ok = rests_ok and length <= 7.0 + 0.1 and length >= 1.5
	check(caps_ok, "Fifteen-minute run: every limit holds%s" % ("" if caps_ok else " (first: " + first_bad + ")"))
	check(order_ok, "Phases run assault -> rest -> (sweep -> rest) -> assault")
	check(numbering_ok, "Each assault is the next wave number; sweeps follow a Major engagement")
	check(c.waves_cleared >= 6, "Several waves are cleared (%d)" % c.waves_cleared)
	check(c.sets_completed >= 1 and sweep_seen and max_mult >= 1.25, "A full set, its bonus sweep and the x1.25 multiplier are reached")
	check(rests_ok and rest_lengths.size() >= 6, "Every rest lasts at most 7 s on Normal (%d rests)" % rest_lengths.size())
	check(longest_assault <= c.wave_safety_seconds + 120.0, "No wave runs far past the safety time (longest %.0f s)" % longest_assault)
	check(max_capitals <= 4, "Never more than 4 Enemy Carriers on the scope (peak %d)" % max_capitals)
	check(c.systems_bonus_counts.size() >= 3, "Several kinds of Systems Bonus were awarded (%s)" % str(c.systems_bonus_counts))
	print("V120_RUN seconds=900 wave=", c.wave, " cleared=", c.waves_cleared, " sets=", c.sets_completed, " sweeps=", c.sweeps_flown,
		" perfect=", c.sweeps_perfect, " rests=", rest_lengths.size(), " longest_assault=", int(longest_assault), " peak_capitals=", max_capitals,
		" score=", c.score, " wave_bonus=", c.wave_bonus_points, " bonuses=", c.systems_bonus_counts, " jumped_out=", c.fighters_jumped_out)
	print("V120_RUN_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await process_frame
	console.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
