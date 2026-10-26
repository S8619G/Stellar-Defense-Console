extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.2.0: defined waves (force-based waves, short rests,
## sets of five, traits, set tactics, bonus sweep, tally, set multiplier and a
## random Systems Bonus) and the fixed-size Breacher warning box.
var checks := 0
var failures := 0
var cleared_signals: Array[int] = []
var changed_signals: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)
func near(a: float, b: float, eps: float = 0.0005) -> bool:
	return absf(a - b) <= eps
func box_rect(alert: Label) -> Rect2:
	# Same rectangle ConsoleFrame._draw_hack_box draws (1.2.0: fixed five lines).
	var text_height: float = maxf(alert.get_parent().hack_text_height(), alert.size.y)
	return Rect2(alert.position - Vector2(10, 8), Vector2(alert.size.x + 20, text_height + 16))
func base(c: Control) -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	b.drone_timer = 99.0
	b.missile_timer = 99.0
	b.heavy_timer = 99.0
	b.flak_timer = 99.0
	b.nuclear_timer = 99.0
	return b
func clear_capitals(c: Control) -> void:
	for index in range(c.contacts.size() - 1, -1, -1):
		if c.contacts[index].kind in ["carrier", "unknown", "siege_ship"]:
			c.contacts.remove_at(index)
	c.pending.clear()
func fresh(c: Control, level: int) -> void:
	c.difficulty = level
	c.reset_battle()
	c.pending.clear()
	c.contacts.clear()

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://test_v120_scores.json"
	console.settings_file = "user://test_v120.cfg"
	console.quit_dry_run = true
	console.shell_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	root.add_child(console)
	c.set_process(false)
	c.auto_spawn = true
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.wave_cleared.connect(func(n: int) -> void: cleared_signals.append(n))
	c.wave_changed.connect(func(n: int) -> void: changed_signals.append(n))
	fresh(c, 1)
	# --- Version 1.2.0 ---
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 1.2.1")
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.1", "Version text reads STELLAR DEFENSE CONSOLE 1.1.1")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Mac.zip")
		and presets.get_value("preset.1.options", "application/short_version", "") == "1.1.1"
		and presets.get_value("preset.1.options", "application/version", "") == "1.1.1", "Export presets name 1.2.1 files")

	# --- Defaults (Inspector) ---
	check(c.defined_waves and c.wave_system_active(), "Defined waves are on by default")
	check(c.wave_set_size == 5 and c.wave_names == ["PROBE", "STRIKE", "ASSAULT", "PRESSURE", "MAJOR ENGAGEMENT"], "Sets of five: Probe, Strike, Assault, Pressure, Major engagement")
	# 1.2.1: waves 3 to 5 bring one Enemy Carrier fewer.
	check(c.normal_wave_force == [2, 3, 2, 3, 3] and c.easy_wave_force == [2, 2, 2, 2, 2] and c.hard_wave_force == [2, 3, 3, 3, 3], "Enemy force per wave on Easy, Normal and Hard")
	check(c.wave_onscreen_carriers == [2, 2, 3, 3, 4], "Enemy Carriers on screen per wave: 2, 2, 3, 3, 4 (never more than 1.1.1's 4)")
	check(near(c.easy_rest_seconds, 10.0) and near(c.normal_rest_seconds, 7.0) and near(c.hard_rest_seconds, 5.0), "Rest: Easy 10 s, Normal 7 s, Hard 5 s")
	check(near(c.set_score_step, 0.25) and near(c.set_score_cap, 3.0), "Score multiplier +0.25x per set, cap 3x")
	# 1.2.2: Protect the fleet replaces the bonus sweep by default (Set End Round).
	check(c.systems_bonuses.size() == 8 and c.set_end_round == 0 and c.traits_enabled and c.set_modifiers_enabled, "Eight Systems Bonuses, Protect the fleet, traits and tactics on")
	for level in [0, 1, 2]:
		c.active_difficulty = level
		check(near(c.rest_seconds(), [10.0, 7.0, 5.0][level]), "rest_seconds on level %d" % level)
	c.active_difficulty = 1

	# --- Wave 1: the force arrives and ends the wave when destroyed ---
	fresh(c, 1)
	check(c.wave == 1 and c.wave_phase == "assault" and c.wave_name() == "PROBE" and c.wave_force_quota() == 2, "Wave 1 is the Probe: 2 Enemy Carriers")
	check(c.carrier_cap() == 2 and c.breacher_cap() == 1, "Probe allows 2 Enemy Carriers and 1 Breacher on screen")
	check(c.wave_wants_carrier(), "Wave wants Enemy Carriers before its force has arrived")
	base(c)
	base(c)
	check(c.wave_force_spawned == 2 and not c.wave_wants_carrier(), "After its 2 Enemy Carriers, the Probe sends no more")
	c._queue_wave()
	check(c.pending.is_empty(), "No further Enemy Carrier is queued once the force has arrived")
	check(c.wave_force_left() == 2, "Two Enemy Carriers left to destroy")
	c._update_wave_system(0.1)
	check(c.wave_phase == "assault", "Wave stays in the assault while Enemy Carriers remain")
	# Leave Attack Drones and a Breacher on the scope: they jump out at the clear.
	c.contacts.append({"id": "H90", "kind": "drone", "faction": "hostile", "position": Vector3.ZERO, "phase": "harass", "age": 0.0})
	c.contacts.append({"id": "HR91", "kind": "breacher", "faction": "hostile", "position": Vector3.ZERO, "phase": "approach", "age": 0.0})
	c.contacts.append({"id": "M92", "kind": "missile", "faction": "hostile", "position": Vector3(0, 0.5, 0), "age": 0.0})
	clear_capitals(c)
	c.hull = c.max_hull * 0.8
	var before: int = c.score
	cleared_signals.clear()
	c._update_wave_system(0.1)
	check(c.wave_phase == "rest" and c.waves_cleared == 1 and cleared_signals == [1], "Destroying the force clears wave 1 and starts the rest")
	check(c.last_wave_bonus == c.points_for(500 + 10 * 80) and c.score - before == c.last_wave_bonus, "Tally: 500 + 10 per hull percent kept (80%% = 1300)")
	check(c.count_kind("drone") == 0 and c.count_kind("breacher") == 0 and c.fighters_jumped_out == 2, "Remaining Attack Drones and Breachers jump away at the clear")
	check(c.count_kind("missile") == 1, "Missiles already in flight keep coming")
	check(near(c.wave_rest_remaining, 7.0), "Normal rest is 7 seconds")
	check(c.status_message.begins_with("WAVE 1 CLEARED | +"), "Status shows WAVE 1 CLEARED")
	# 1.2.2: set 1 gives no Systems Bonus (test_v122_features checks the schedule).
	check(c.last_systems_bonus.is_empty() and c.rest_tally_lines().has("NO SYSTEMS BONUS"), "Wave 1: no Systems Bonus in set 1 (1.2.2)")
	var tally: Array[String] = c.rest_tally_lines()
	check(tally.size() >= 2 and tally[0].begins_with("WAVE 1 CLEARED") and tally[tally.size() - 1].begins_with("NEXT  WAVE 2 STRIKE"), "Rest tally shows the clear and the next wave")
	check(c.wave_phase_line().begins_with("SET 1  |  REST 7"), "Right panel shows SET 1 | REST")
	c._queue_wave()
	check(c.pending.is_empty(), "No Enemy Carriers arrive during the rest")
	c._update_wave_system(3.9)
	check(not c.wave_inbound_announced, "Not yet inbound with 3.1 s of rest left")
	c._update_wave_system(0.2)
	check(c.wave_inbound_announced and c.status_message.begins_with("WAVE 2 INBOUND | STRIKE") and c.action_stations_count == 1, "Last 3 s: WAVE 2 INBOUND and the action-stations cue")
	changed_signals.clear()
	c._update_wave_system(3.0)
	check(c.wave == 2 and c.wave_phase == "assault" and c.wave_force_quota() == 3 and changed_signals == [2], "Rest ends: wave 2 Strike with 3 Enemy Carriers")
	check(c.status_message.begins_with("WAVE 2 | STRIKE | 3 ENEMY CARRIERS"), "Wave start banner names the wave and its force")
	check(c.wave_phase_line() == "SET 1  |  ENEMY CARRIERS LEFT 3" and c.wave_detail_line() == "STRIKE", "Right panel shows SET 1 | ENEMY CARRIERS LEFT 3 and STRIKE")

	# --- Safety cap ---
	c.wave_assault_time = c.wave_safety_seconds
	check(not c.wave_wants_carrier(), "Safety cap: no more Enemy Carriers after the safety time")
	c._update_wave_system(0.1)
	check(c.wave_phase == "rest" and c.waves_cleared == 2, "Safety cap: the wave ends once the scope is clear")

	# --- Traits ---
	fresh(c, 1)
	check(c._draw_trait(1) == "" and c._draw_trait(2) == "" and c._draw_trait(5) == "", "Normal: no traits on waves 1, 2 and 5")
	var t3: String = c._draw_trait(3)
	var t4: String = c._draw_trait(4)
	check(t3 in c.WAVE_TRAITS and t4 in c.WAVE_TRAITS and t3 != t4, "Normal: waves 3 and 4 get different traits (%s, %s)" % [t3, t4])
	var t8: String = c._draw_trait(8)
	check(t8 in c.WAVE_TRAITS, "Traits reset for the next set")
	fresh(c, 2)
	check(c._draw_trait(2) in c.WAVE_TRAITS, "Hard: traits from wave 2")
	fresh(c, 0)
	check(c._draw_trait(3) == "" and c._draw_trait(4) == "" and c._draw_trait(8) in c.WAVE_TRAITS, "Easy: no traits in set 1, traits from set 2")
	fresh(c, 1)
	var plain_drone: float = c.drone_interval_factor()
	var plain_missile: float = c.missile_interval_factor()
	c.wave_trait = "ATTACK DRONE SWARM"
	check(near(c.drone_interval_factor(), plain_drone * 0.7) and near(c.missile_interval_factor(), plain_missile * 1.3), "ATTACK DRONE SWARM: Attack Drones x0.7 interval, missiles x1.3")
	c.wave_trait = "MISSILE BARRAGE"
	check(near(c.missile_interval_factor(), plain_missile * 0.7), "MISSILE BARRAGE: missiles x0.7 interval")
	c.wave_trait = "NUCLEAR STRIKE"
	check(near(c.nuclear_delay_factor(), 0.5), "NUCLEAR STRIKE: nukes launch at half the delay")
	c.wave_trait = "HEAVY ASSAULT"
	check(near(c.heavy_interval_factor(), 0.6), "HEAVY ASSAULT: Breachers x0.6 interval")
	c.wave_trait = "ESCORT"
	check(near(c.capital_arrival_factor(), 0.4), "ESCORT: Enemy Carriers arrive close together")
	c.wave_phase = "rest"
	check(near(c.capital_arrival_factor(), 1.0), "Traits apply only during their wave's assault")
	c.wave_trait = ""
	c.wave_phase = "assault"

	# --- Set tactics and multiplier ---
	fresh(c, 1)
	check(near(c.set_launch_factor(), 1.0) and c.set_carrier_hits_bonus() == 0 and near(c.set_hack_factor(), 1.0) and near(c.set_warhead_factor(), 1.0), "Set 1 has no added tactics")
	c.sets_completed = 1
	check(c.newest_set_modifier() == "QUICKER LAUNCHES" and near(c.set_launch_factor(), 0.85), "Set 2: QUICKER LAUNCHES x0.85")
	c.sets_completed = 2
	check(c.newest_set_modifier() == "HARDENED ENEMY CARRIERS" and c.set_carrier_hits_bonus() == 1, "Set 3: HARDENED ENEMY CARRIERS +1 hit")
	var hard_base := base(c)
	check(int(hard_base.max_hits) == maxi(2, c.scaled_hits(c.carrier_hits_to_destroy)) + 1, "A Enemy Carrier in set 3 takes one more hit")
	c.sets_completed = 3
	check(c.newest_set_modifier() == "FASTER HACKING" and near(c.set_hack_factor(), 1.0 / 0.85), "Set 4: FASTER HACKING (6 s to about 5 s)")
	c.sets_completed = 4
	check(c.newest_set_modifier() == "FASTER WARHEADS" and near(c.set_warhead_factor(), 1.08), "Set 5: FASTER WARHEADS +8%")
	c.sets_completed = 5
	check(near(c.set_launch_factor(), 0.85 * 0.925), "Set 6: the cycle repeats in half steps")
	c.sets_completed = 60
	check(c.set_launch_factor() >= 0.5 and c.set_carrier_hits_bonus() <= 3 and c.set_hack_factor() <= 1.0 / 0.6 + 0.0001 and c.set_warhead_factor() <= 1.3, "Set tactics stay capped in very long battles")
	for pair in [[0, 1.0], [1, 1.25], [2, 1.5], [4, 2.0], [8, 3.0], [20, 3.0]]:
		c.sets_completed = pair[0]
		check(near(c.set_score_multiplier(), pair[1]), "After %d sets the score multiplier is x%.2f" % pair)
	c.sets_completed = 2
	check(c.points_for(100) == 150 and near(c.score_multiplier(), 1.5), "Set multiplier applies to every score")
	# 1.2.7: the multiplier moved to its own right panel line.
	check(c.wave_score_line() == "SCORE MULTIPLIER  x1.50" and not c.wave_detail_line().contains("SCORE"), "Right panel shows SCORE MULTIPLIER x1.50 on its own line (1.2.7)")
	fresh(c, 0)
	c.sets_completed = 1
	check(near(c.set_launch_factor(), 0.925), "Easy: half-strength tactics")
	fresh(c, 1)

	# --- Major engagement, Siege Ship and the set bonus ---
	fresh(c, 1)
	c.wave = 5
	c.wave_force_spawned = 4
	check(c.is_major_wave() and c.wave_name() == "MAJOR ENGAGEMENT" and c.carrier_cap() == 4 and c.breacher_cap() == 3, "Wave 5 is the Major engagement: 4 Enemy Carriers, 3 Breachers on screen")
	c.wave_assault_time = 1.0
	c._update_wave_system(0.1)
	check(c.wave_phase == "assault", "Major engagement waits for its Siege Ship")
	c.wave_assault_time = c.major_siege_delay
	c._update_wave_system(0.1)
	check(c.wave_siege_spawned and c.count_kind("siege_ship") == 1, "Siege Ship arrives in the Major engagement")
	c._update_wave_system(0.1)
	check(c.wave_phase == "assault", "Wave continues while the Siege Ship is on the scope")
	clear_capitals(c)
	c.hull = c.max_hull
	c._update_wave_system(0.1)
	check(c.wave_phase == "rest" and c.sets_completed == 1 and c.wave_next_phase == "protect", "Clearing the Major engagement completes set 1; Protect the fleet is next (1.2.2)")
	check(c.last_wave_bonus == roundi(500 + 10 * 100 + 2500), "Major engagement tally adds the 2,500 set bonus")
	check(c.rest_tally_lines().has("SET 1 COMPLETE  |  SCORE x1.25"), "Tally shows SET 1 COMPLETE | SCORE x1.25")
	# Random Siege Ship spawning is off with defined waves.
	fresh(c, 1)
	c.wave = 3
	c.siege_spawn_chance = 1.0
	c.siege_max_chance = 1.0
	c.siege_check_remaining = 0.0
	c._update_siege_spawning(0.1)
	check(c.count_kind("siege_ship") == 0, "No random Siege Ship outside the Major engagement")

	# --- Bonus sweep ---
	fresh(c, 1)
	c.wave = 5
	c.sets_completed = 1
	c._start_sweep()
	check(c.wave_phase == "sweep" and c.status_message.begins_with("BONUS SWEEP"), "Bonus sweep starts")
	c._update_wave_system(0.01)
	check(c.sweep_spawned == 3 and c.sweep_left() == 3, "Attack Drones cross in groups of three")
	var flier: Dictionary = {}
	for contact in c.contacts:
		if contact.get("phase", "") == "sweep":
			flier = contact
			break
	var start_x: float = flier.position.x
	c._update_drone(flier, 1.0)
	check(flier.phase == "sweep" and absf(flier.position.x) < absf(start_x) + 0.001, "Sweep Attack Drones fly straight across")
	check(c.count_kind("missile") == 0 and c.count_kind("carrier") == 0, "No missiles and no Enemy Carriers in the sweep")
	# One escapes.
	flier.position = flier.sweep_exit
	c._update_drone(flier, 0.01)
	check(c.sweep_escaped == 1 and c.sweep_left() == 2, "A Attack Drone leaving the far edge counts as escaped")
	var score_before: int = c.score
	for contact in c.contacts.duplicate():
		if contact.get("phase", "") == "sweep":
			c._award_destroyed(contact)
			c._remove_contact(contact.id)
	check(c.sweep_destroyed == 2, "Destroyed sweep Attack Drones are counted")
	check(c.score - score_before == 2 * c.points_for(c.fighter_points), "Sweep Attack Drones score normal points (with the set multiplier)")
	c.sweep_spawned = c.sweep_drones
	c._update_wave_system(0.01)
	check(c.wave_phase == "rest" and c.sweeps_perfect == 0 and c.wave_next_phase == "assault", "Sweep with an escape: no PERFECT bonus, rest before wave 6")
	check(c.rest_tally_lines()[0].begins_with("BONUS SWEEP  2 OF"), "Tally shows the sweep result")
	c.wave_rest_remaining = 0.5
	c._update_wave_system(0.1)
	check(c.status_message.contains("WAVE 6 INBOUND | PROBE") and c.status_message.contains("NEW ENEMY TACTIC: QUICKER LAUNCHES") and c.status_message.contains("SCORE x1.25"), "Wave 6 announcement names the new tactic and multiplier")
	c._update_wave_system(1.0)
	check(c.wave == 6 and c.wave_set_number() == 2 and c.wave_position() == 1 and c.wave_force_quota() == 2, "Set 2 starts again at the Probe")
	# Perfect sweep.
	fresh(c, 1)
	c.wave = 5
	c.sets_completed = 1
	c._start_sweep()
	var guard := 0
	while c.sweep_spawned < c.sweep_drones and guard < 20:
		c._update_sweep(c.sweep_group_gap + 0.01)
		for contact in c.contacts.duplicate():
			if contact.get("phase", "") == "sweep":
				c._award_destroyed(contact)
				c._remove_contact(contact.id)
		guard += 1
	score_before = c.score
	c._update_wave_system(0.01)
	check(c.sweeps_perfect == 1 and c.score - score_before == c.points_for(c.sweep_perfect_points), "PERFECT sweep: 3,000 x set multiplier")
	check(c.last_sweep_result.contains("PERFECT"), "Tally reads PERFECT")

	# --- JUMP ---
	fresh(c, 1)
	c.jump_recharge_remaining = 0.0
	c._begin_rest()
	c.wave_next_phase = "assault"
	c.score = 5000
	check(c.request_jump(), "JUMP is available during the rest")
	check(c.score == 5000 + c.points_for(c.jump_rest_jump_points), "JUMP during the rest is free and adds a small bonus")
	check(near(c.safe_remaining, c.rest_jump_safe_seconds) and near(c.wave_rest_remaining, 0.0), "Rest jump: short safe period, next wave early")
	c.safe_remaining = 0.0
	c._update_wave_system(0.1)
	check(c.wave == 2 and c.wave_phase == "assault", "After the rest jump the next wave begins")
	c.wave_force_spawned = 2
	c.jump_recharge_remaining = 0.0
	c.score = 5000
	check(c.request_jump() and c.score == 5000 - c.jump_score_cost, "JUMP mid-wave keeps its normal cost")
	check(c.wave == 2 and c.wave_force_spawned == 0 and c.waves_escaped == 1 and c.status_message.contains("WAVE 2 STARTS AGAIN"), "Mid-wave jump: the wave counts as escaped and starts again")

	# --- Systems Bonus ---
	fresh(c, 1)
	# 1.2.2: these checks cover each bonus's effect, so they use the 1.2.0 schedule
	# (a bonus every wave, drawn from all eight) through one unlocked tier.
	c.bonus_start_wave = 1
	c.bonus_wave_chance = 1.0
	c.bonus_low_tier.assign(["REPAIR", "EMP", "INTERCEPTORS", "GUNSHIP", "SPEED", "AUTO SHIELD", "RAPID FIRE", "STEALTH"])
	c.bonus_low_tier_set = 1
	c.bonus_medium_tier_set = 99
	c.bonus_high_tier_set = 99
	# 1.1.0: the cap of 3 is the rule without a Rapid Repair limit (test_sdc_110 covers the limit).
	c.rapid_repair_limit = 0
	c.rapid_repair_limit_easy = 0
	c.repair_charges = 3
	check(not c._bonus_applies("REPAIR"), "No extra repair at 3 charges")
	c.repair_charges = 1
	check(c._bonus_applies("REPAIR"), "Extra repair below 3 charges")
	c.emp_charges = c.emp_max_charges
	check(not c._bonus_applies("EMP"), "No extra EMP when EMP is full")
	c.emp_charges = 0
	check(c._bonus_applies("EMP"), "Extra EMP when below the cap")
	c.stealth_cooldown_remaining = 30.0
	check(c._bonus_applies("STEALTH"), "Stealth Interceptor bonus while it is rearming (Normal)")
	c.active_difficulty = 0
	check(not c._bonus_applies("STEALTH"), "No Stealth bonus on Easy")
	c.active_difficulty = 1
	c.stealth_cooldown_remaining = 0.0
	check(not c._bonus_applies("STEALTH"), "No Stealth bonus when it is already ready")
	var repeats := 0
	var last := ""
	var seen := {}
	for n in range(80):
		c.repair_charges = 1
		c.emp_charges = 0
		c.stealth_cooldown_remaining = 30.0
		c._award_systems_bonus()
		if c.last_systems_bonus == last:
			repeats += 1
		last = c.last_systems_bonus
		seen[last] = true
	check(repeats == 0, "The same Systems Bonus never comes twice in a row")
	check(seen.size() == 8, "All eight Systems Bonuses can be drawn (%d seen)" % seen.size())
	c.systems_bonuses.assign(["REPAIR"])
	c.last_systems_bonus = ""
	c.repair_charges = 1
	c._award_systems_bonus()
	check(c.repair_charges == 2, "EXTRA RAPID REPAIR adds a charge")
	c.systems_bonuses.assign(["EMP"])
	c.emp_charges = 0
	c._award_systems_bonus()
	check(c.emp_charges == 1, "EXTRA EMP CHARGE adds a charge")
	c.systems_bonuses.assign(["STEALTH"])
	c.stealth_cooldown_remaining = 40.0
	c._award_systems_bonus()
	check(near(c.stealth_cooldown_remaining, 0.0), "STEALTH INTERCEPTOR READY makes the Stealth Interceptor ready")
	c.systems_bonuses.assign(["INTERCEPTORS"])
	c._award_systems_bonus()
	check(c.interceptor_limit() == c.max_interceptors + 2, "EXTRA INTERCEPTOR SQUADRON: two more Interceptors for the next wave")
	c.systems_bonuses.assign(["GUNSHIP"])
	c._award_systems_bonus()
	check(c.gunship_limit() == c.max_gunships + 1 and c.interceptor_limit() == c.max_interceptors, "EXTRA GUNSHIP: one more Gunship; the previous boost ends")
	c.systems_bonuses.assign(["SPEED"])
	c._award_systems_bonus()
	check(near(c.speed_for_kind("interceptor"), c.interceptor_speed * 1.15), "FIGHTER SPEED: Interceptors 15% faster")
	c.systems_bonuses.assign(["AUTO SHIELD"])
	c.auto_defense_battery = false
	var mult_before: float = c.score_multiplier()
	c._award_systems_bonus()
	check(c.battery_auto_on() and c.auto_options_on() == 0 and near(c.score_multiplier(), mult_before), "FREE AUTO SHIELD: battery runs itself with no score penalty")
	check(c.active_bonus_names().has("BONUS: FREE AUTO SHIELD"), "Active boost listed under SCORE")
	c.systems_bonuses.assign(["RAPID FIRE"])
	c._award_systems_bonus()
	check(near(c.fire_interval_factor(), 0.75) and not c.battery_auto_on(), "RAPID FIRE: ship and fighter fire every 75% of the time")
	c.systems_bonus_enabled = false
	check(c._award_systems_bonus() == "" and c.active_boosts.is_empty(), "Systems Bonus can be turned off")
	c.systems_bonus_enabled = true
	c.systems_bonuses.assign(["REPAIR", "EMP", "INTERCEPTORS", "GUNSHIP", "SPEED", "AUTO SHIELD", "RAPID FIRE", "STEALTH"])
	c.bonus_start_wave = 6
	c.bonus_wave_chance = 0.4
	c.bonus_low_tier.assign(["EMP", "SPEED"])
	c.bonus_low_tier_set = 2
	c.bonus_medium_tier_set = 3
	c.bonus_high_tier_set = 5

	# --- Classic timer waves remain available ---
	fresh(c, 1)
	c.defined_waves = false
	check(not c.wave_system_active() and c.carrier_cap() == c.max_carriers and c.wave_phase_line() == "", "Defined Waves off: the 1.1.1 timer waves")
	c.defined_waves = true
	c.auto_spawn = false
	check(not c.wave_system_active(), "Defined waves only run while contacts arrive on their own")
	c.auto_spawn = true

	# --- High scores keep sets and waves cleared ---
	fresh(c, 1)
	c.waves_cleared = 7
	c.sets_completed = 1
	var stats: Dictionary = c.battle_stats()
	check(stats.get("waves_cleared", -1) == 7 and stats.get("sets", -1) == 1, "Battle stats include waves cleared and sets")
	var clean: Dictionary = preload("res://scripts/HighScores.gd").clean_stats(stats)
	check(clean.get("sets", -1) == 1 and clean.get("waves_cleared", -1) == 7, "High-score table keeps them")
	var text: String = console.score_stats_text({"initials": "ABC", "score": 100, "wave": 8, "difficulty": "N", "stats": clean})
	check(text.contains("WAVES CLEARED 7   SETS COMPLETED 1"), "Score hover shows WAVES CLEARED and SETS COMPLETED")
	var old_text: String = console.score_stats_text({"initials": "ABC", "score": 100, "wave": 8, "difficulty": "N", "stats": {"drone": 3}})
	check(not old_text.contains("SETS"), "Entries from before 1.2.0 show no sets line")

	# --- Audio cues ---
	check(c.action_stations_player != null and c.action_stations_player.stream != null and near(c.action_stations_player.stream.get_length(), 1.2, 0.01), "Action-stations cue is 1.2 s")
	check(c.all_clear_player != null and c.all_clear_player.stream != null and near(c.all_clear_player.stream.get_length(), 1.4, 0.01), "All-clear cue is 1.4 s")
	check(c.wave_cues_enabled and near(c.action_stations_volume_db, -14.0) and near(c.all_clear_volume_db, -14.0), "Wave cues on at -14 dB, editable")

	# --- Fixed-size Breacher box ---
	fresh(c, 1)
	c.auto_spawn = false
	c.waves_enabled = false
	var alert: Label = console.get_node("HackAlert")
	var b := base(c)
	c.emp_charges = 2
	var heavy_id: String = c.spawn_from_carrier("breacher", b.id)
	var heavy: Dictionary = c.find_contact(heavy_id)
	var rects := {}
	for state in ["approach", "hacking", "draining"]:
		if state == "hacking":
			heavy.phase = "hacking"
			heavy.position = heavy.hack_point
		elif state == "draining":
			heavy.phase = "draining"
		console._process(0.0)
		rects[state] = box_rect(alert)
		check(c.hack_state() == state, "Box state %s" % state)
		print("V120_BOX ", state, " ", rects[state], " lines=", alert.get_line_count())
		check(rects[state].end.y <= 966.0 and rects[state].position.x >= 82.0 and rects[state].end.x <= 760.0, "%s: box stays beside the ship outline, above the divider" % state)
	check(rects["approach"] == rects["hacking"] and rects["hacking"] == rects["draining"], "The box keeps one size and position for the approach and the hack")
	heavy.phase = "approach"
	console._process(0.0)
	check(alert.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and alert.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "Approach warning is centred in the box")
	check(near(alert.size.y, console.hack_text_height(), 0.5) and console.hack_text_height() >= 5 * alert.get_line_height(), "Warning text area is exactly five lines tall (%.1f)" % alert.size.y)
	var text_center := alert.position.y + alert.size.y * 0.5
	check(absf(text_center - rects["approach"].get_center().y) <= 1.0, "Approach text is vertically centred in the box")
	heavy.phase = "hacking"
	console._process(0.0)
	check(alert.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT and alert.vertical_alignment == VERTICAL_ALIGNMENT_TOP, "Hacking activity replaces it, left-aligned from the top")
	check(alert.offset_left == 390.0 and alert.offset_top == 824.0 and alert.offset_right == 745.0, "HackAlert keeps its 1.1.1 place")
	c.contacts.clear()
	console._process(0.0)
	check(not alert.visible and c.hack_state() == "", "Box hidden again with no Breacher")
	c.auto_spawn = true
	c.waves_enabled = true

	print("V120_RESULT checks=%d failures=%d" % [checks, failures])
	# Stop every player first so no playback is left running at exit.
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await process_frame
	console.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
