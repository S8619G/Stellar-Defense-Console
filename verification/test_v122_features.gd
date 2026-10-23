extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.2.2: thicker wave tally border, Systems Bonus schedule
## and tiers, no FREE AUTO SHIELD while AUTO DEFENSE SHIELD is on, tougher
## Enemy Carriers, faster nukes, slower Gunship anti-nuke fire, and Protect the fleet.
var checks := 0
var failures := 0
var events: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)
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
func on_event(message: String) -> void:
	events.append(message)

## Draws one Systems Bonus at wave `number` from a clean state; returns its code ("" = none).
func draw(c: Control, number: int) -> String:
	c.wave = number
	c.repair_charges = 0
	c.emp_charges = 0
	c.stealth_cooldown_remaining = 30.0
	c.last_systems_bonus = ""
	c._award_systems_bonus()
	var code: String = c.last_systems_bonus
	return code

func tier_of(c: Control, code: String) -> int:
	if code in c.bonus_low_tier:
		return 0
	if code in c.bonus_medium_tier:
		return 1
	if code in c.bonus_high_tier:
		return 2
	return -1

## Counts of [none, low, medium, high] over `runs` draws at wave `number`.
func tally(c: Control, number: int, runs: int) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	for i in range(runs):
		var code := draw(c, number)
		counts[tier_of(c, code) + 1] += 1
	return counts

## Puts the battle at the start of a Protect the fleet round after set 1.
func start_protect(c: Control, level: int, seed_value: int = 7) -> void:
	fresh(c, level)
	pin_122_round(c)
	c.rng.seed = seed_value
	c.wave = 5
	c.sets_completed = 1
	c.wave_phase = "rest"
	c.wave_next_phase = "protect"
	c.safe_remaining = 0.0
	c._start_protect()

## 1.2.3: this test checks the 1.2.2 round rules, so it pins the 1.2.2 round values
## (test_v123_features checks the new 1.2.3 defaults).
func pin_122_round(c: Control) -> void:
	c.protect_drone_group_size = 2
	c.protect_drone_group_gap = 1.5
	c.protect_drone_interceptor_hits = 2
	c.protect_drone_hits_step = 0
	c.protect_return_fire_chance = 0.0
	c.protect_kill_time_step = 0.0

func civilians(c: Control) -> Array:
	var list: Array = []
	for x in c.contacts:
		if x.get("faction", "") == "civilian":
			list.append(x)
	return list

func protect_drones(c: Control) -> Array:
	var list: Array = []
	for x in c.contacts:
		if x.get("phase", "") == "protect":
			list.append(x)
	return list

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://test_v122_scores.json"
	console.settings_file = "user://test_v122.cfg"
	console.quit_dry_run = true
	console.shell_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	# 1.0.7: these checks cover the 1.2.2 round rules; the Breacher has its own suite (test_protect_convoy).
	c.protect_breachers = false
	# 1.0.7: these checks cover the 60 s limit; the new round end is checked in test_protect_convoy.
	c.protect_timer_end = true
	c.protect_interceptors_lost_end = false
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
	c.battle_event.connect(on_event)

	# --- Version 1.2.2 ---
	check(ProjectSettings.get_setting("application/config/version") == "1.0.8", "Project version is 1.2.2")
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.0.8", "Version text reads STELLAR DEFENSE CONSOLE 1.0.8")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.0.8_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.0.8_Mac.zip")
		and presets.get_value("preset.1.options", "application/short_version", "") == "1.0.8"
		and presets.get_value("preset.1.options", "application/version", "") == "1.0.8", "Export presets name 1.2.2 files")

	# --- Item 1: wave tally border ---
	check(is_equal_approx(c.rest_tally_border_width, 3.0), "Wave tally border is 3 px (was 1), an Inspector value")

	# --- Items 4-6: approved values ---
	check(c.carrier_hits_to_destroy == 11, "Enemy Carrier Hits To Destroy is 11 (was 10)")
	check(is_equal_approx(c.nuclear_speed, 0.058), "Nuclear Speed is 0.058 (was 0.055)")
	check(is_equal_approx(c.nuke_speed_random_max, 0.08) and c.hard_nuke_speed_lean, "Nuke 0-8% random bonus and the Hard lean stay")
	check(is_equal_approx(c.easy_nuke_speed, 1.1) and is_equal_approx(c.normal_nuke_speed, 1.25) and is_equal_approx(c.hard_nuke_speed, 1.45), "Nuke difficulty speed factors (1.2.7): 1.1 / 1.25 / 1.45")
	check(is_equal_approx(c.gunship_nuke_hit_interval, 0.7), "Gunship Nuke Hit Interval is 0.7 s (was 0.6)")
	check(c.nuclear_hit_points == 6, "Nukes still take 6 hits")
	var expect_base := {0: 7, 1: 11, 2: 15}
	var expect_nuke_time := {0: 2.8, 1: 4.2, 2: 5.6}
	for level in [0, 1, 2]:
		fresh(c, level)
		var b := base(c)
		check(int(b.hits_remaining) == expect_base[level], "Level %d: Enemy Carrier takes %d hits" % [level, expect_base[level]])
		var nuke: Dictionary = c.find_contact(c._launch_nuclear(b))
		var per_nuke: float = c.nuke_hits_left(nuke) * c.gunship_nuke_hit_interval
		check(is_equal_approx(per_nuke, expect_nuke_time[level]), "Level %d: one Gunship needs %.1f s of fire per nuke" % [level, expect_nuke_time[level]])
		# Nuke flight speed with the random bonus at zero.
		nuke.speed_bonus = 0.0
		var before: Vector3 = nuke.position
		c._update_special_projectiles(1.0)
		var moved: float = before.distance_to(nuke.position)
		var factor: float = [1.1, 1.25, 1.45][level]  # 1.2.7 factors
		check(absf(moved - 0.058 * factor * c.movement_speed) < 0.0005, "Level %d: nuke flies %.4f per second" % [level, 0.058 * factor])
	# Random bonus still applies on top.
	fresh(c, 1)
	var b_bonus := base(c)
	var n_bonus: Dictionary = c.find_contact(c._launch_nuclear(b_bonus))
	n_bonus.speed_bonus = 0.08
	var p0: Vector3 = n_bonus.position
	c._update_special_projectiles(1.0)
	check(absf(p0.distance_to(n_bonus.position) - 0.058 * 1.25 * 1.08) < 0.0005, "The random bonus multiplies the new base speed")

	# --- Item 2: Systems Bonus schedule ---
	check(c.bonus_start_wave == 6 and is_equal_approx(c.bonus_wave_chance, 0.4), "Bonuses start at wave 6 with a 40% chance per wave")
	check(c.bonus_low_tier == ["EMP", "SPEED"] and c.bonus_medium_tier == ["REPAIR", "GUNSHIP", "RAPID FIRE"]
		and c.bonus_high_tier == ["INTERCEPTORS", "AUTO SHIELD", "STEALTH"], "Tier lists as decided")
	check(c.bonus_low_tier_set == 2 and c.bonus_medium_tier_set == 3 and c.bonus_high_tier_set == 5, "Tiers unlock in sets 2, 3 and 5")
	check(c.hard_bonus_set_delay == 1 and is_equal_approx(c.hard_bonus_chance_factor, 0.5), "Hard: one set later, half the chance")
	for level in [0, 1]:
		fresh(c, level)
		c.rng.seed = 11
		var none_early := true
		for number in range(1, 6):
			for i in range(40):
				if not draw(c, number).is_empty():
					none_early = false
		check(none_early, "Level %d: set 1 (waves 1-5) gives no Systems Bonus" % level)
		var mid := tally(c, 7, 2000)
		var rate := float(2000 - mid[0]) / 2000.0
		check(rate > 0.36 and rate < 0.44, "Level %d: wave 7 gives a bonus about 40%% of the time (%.3f)" % [level, rate])
		check(mid[2] == 0 and mid[3] == 0, "Level %d: set 2 bonuses are all low tier" % level)
		var end2 := tally(c, 10, 300)
		check(end2[0] == 0 and end2[1] == 300, "Level %d: the end of set 2 (wave 10) always gives a low-tier bonus" % level)
		var set3 := tally(c, 15, 1500)
		check(set3[0] == 0 and set3[3] == 0, "Level %d: end of set 3 is guaranteed; no high tier yet" % level)
		var low_share := float(set3[1]) / 1500.0
		check(low_share > 0.28 and low_share < 0.39, "Level %d: set 3 gives a lower tier about 1 in 3 (%.3f)" % [level, low_share])
		var set5 := tally(c, 25, 1500)
		var lower := float(set5[1] + set5[2]) / 1500.0
		check(set5[0] == 0 and set5[3] > 0 and lower > 0.28 and lower < 0.39 and set5[1] > 0 and set5[2] > 0,
			"Level %d: set 5 gives high tier, 1 in 3 from a lower unlocked tier (%.3f)" % [level, lower])
	fresh(c, 2)
	c.rng.seed = 12
	var hard_early := true
	for number in range(1, 11):
		for i in range(40):
			if not draw(c, number).is_empty():
				hard_early = false
	check(hard_early, "Hard: no Systems Bonus before wave 11")
	var hard_mid := tally(c, 12, 2000)
	var hard_rate := float(2000 - hard_mid[0]) / 2000.0
	check(hard_rate > 0.16 and hard_rate < 0.24, "Hard: wave 12 gives a bonus about 20%% of the time (%.3f)" % hard_rate)
	var hard_end := tally(c, 15, 300)
	check(hard_end[0] == 0 and hard_end[1] == 300, "Hard: end of set 3 (wave 15) is guaranteed and low tier (shifted one set)")
	var hard_set4 := tally(c, 20, 600)
	check(hard_set4[0] == 0 and hard_set4[3] == 0 and hard_set4[2] > 0, "Hard: set 4 reaches the medium tier, no high tier yet")
	var hard_set6 := tally(c, 30, 600)
	check(hard_set6[3] > 0, "Hard: set 6 reaches the high tier")
	# Tally panel lines.
	fresh(c, 1)
	c.rng.seed = 3
	c.wave = 2
	c._clear_wave()
	check(c.last_bonus_label.is_empty() and c.rest_tally_lines().has("NO SYSTEMS BONUS"), "A wave with no reward shows NO SYSTEMS BONUS")
	c.show_no_systems_bonus = false
	check(not c.rest_tally_lines().has("NO SYSTEMS BONUS"), "Show No Systems Bonus off hides the line")
	c.show_no_systems_bonus = true
	fresh(c, 1)
	c.wave = 10
	c._clear_wave()
	check(not c.last_bonus_label.is_empty() and c.rest_tally_lines()[1].begins_with("SYSTEMS BONUS  "), "End of set 2: the tally shows the Systems Bonus")
	c.systems_bonus_enabled = false
	fresh(c, 1)
	c.wave = 10
	c._clear_wave()
	check(c.last_bonus_label.is_empty() and not c.rest_tally_lines().has("NO SYSTEMS BONUS"), "Systems Bonus off: no bonus and no NO SYSTEMS BONUS line")
	c.systems_bonus_enabled = true

	# --- Item 3: FREE AUTO SHIELD is skipped while AUTO DEFENSE SHIELD is on ---
	fresh(c, 1)
	c.auto_defense_battery = true
	check(not c._bonus_applies("AUTO SHIELD"), "AUTO DEFENSE SHIELD on: FREE AUTO SHIELD does not apply")
	c.rng.seed = 21
	var auto_seen := 0
	var high_seen := 0
	for i in range(900):
		var code := draw(c, 25)
		if code == "AUTO SHIELD":
			auto_seen += 1
		if tier_of(c, code) == 2:
			high_seen += 1
	check(auto_seen == 0 and high_seen > 0, "Auto shield on: never picked in 900 set-5 draws; Interceptors or Stealth come instead (%d high)" % high_seen)
	c.bonus_high_tier.assign(["AUTO SHIELD"])
	var fallback_ok := true
	for i in range(300):
		var code := draw(c, 25)
		if code.is_empty() or code == "AUTO SHIELD" or tier_of(c, code) == 2:
			fallback_ok = false
	check(fallback_ok, "Auto shield on and it is the only high-tier bonus: the draw falls back to a lower tier")
	c.auto_defense_battery = false
	check(c._bonus_applies("AUTO SHIELD"), "AUTO DEFENSE SHIELD off: FREE AUTO SHIELD applies")
	var picked_off := 0
	for i in range(300):
		if draw(c, 25) == "AUTO SHIELD":
			picked_off += 1
	check(picked_off > 120, "Auto shield off: FREE AUTO SHIELD can be picked (%d of 300)" % picked_off)
	c.bonus_high_tier.assign(["INTERCEPTORS", "AUTO SHIELD", "STEALTH"])
	c.rng.seed = 22
	var normal_auto := 0
	for i in range(900):
		if draw(c, 25) == "AUTO SHIELD":
			normal_auto += 1
	check(normal_auto > 100, "Auto shield off: picked in normal set-5 draws (%d of 900)" % normal_auto)

	# --- Item 7: Protect the fleet ---
	check(c.set_end_round == 0, "Set End Round is Protect the fleet by default")
	check(not ("protect_allow_jump" in c), "JUMP is always held during the round (1.2.7: the option is removed)")
	check(c.protect_civilians_min == 2 and c.protect_civilians_max == 4 and is_equal_approx(c.protect_round_seconds, 60.0), "2-4 civilian ships, 60 s limit")
	check(c.protect_ship_points == 500 and c.protect_full_fleet_points == 1000, "Bonus 500 x hull per ship, +1000 full fleet")
	check(is_equal_approx(c.civilian_icon_scale, 1.6) and is_equal_approx(c.civilian_capital_icon_scale, 2.1), "Civilian icon scales 1.6 and 2.1 (approved)")
	check(is_equal_approx(c.size_for_kind("civilian_c"), 2.1) and is_equal_approx(c.size_for_kind("civilian_a"), 1.6) and c.size_for_kind("civilian_c") < c.size_for_kind("carrier") * 2.0,
		"Shape C at capital size, A/B/D/E at the larger solo size")
	# After the Major engagement.
	fresh(c, 1)
	c.wave = 5
	c._clear_wave()
	check(c.wave_next_phase == "protect" and c.sets_completed == 1, "Clearing the Major engagement: Protect the fleet is next")
	check(c.inbound_message().begins_with("PROTECT THE CONVOY INBOUND"), "Inbound line names Protect the fleet")
	check(c.rest_tally_lines()[-1].begins_with("NEXT  PROTECT THE CONVOY  IN"), "Tally: NEXT PROTECT THE CONVOY")
	check(c.next_wave_number() == 5 and c.upcoming_trait.is_empty(), "No wave number or trait for the round")
	var boosts_before: Dictionary = c.active_boosts.duplicate()
	# Leftovers on the scope before the round.
	var b4 := base(c)
	c.spawn_from_carrier("drone", b4.id)
	c.spawn_from_carrier("missile", b4.id)
	c.launch_interceptors()
	c._spawn_gunship()
	c.prox_burst_remaining = c.prox_burst_seconds
	c.set_prox_defense(true)
	c.wave_rest_remaining = 0.0
	c.wave_inbound_announced = true
	c._hold_ready(c.interceptor_waits, 1, 3.0)
	c._update_wave_system(0.1)
	check(c.wave_phase == "protect" and c.protect_active(), "The round starts after the rest")
	check(c.count_kind("carrier") == 0 and c.count_kind("missile") == 0 and c.count_kind("gunship") == 0 and c.count_interceptors() == 0 and protect_drones(c).size() == 0 and c.count_kind("drone") == 0,
		"The scope is reset: no Enemy Carriers, missiles or leftover fighters")
	check(not c.prox_active, "The Defense Shield stops")
	check(c.status_message.begins_with("PROTECT THE CONVOY"), "Status header reads PROTECT THE CONVOY")
	var ships := civilians(c)
	check(ships.size() >= 2 and ships.size() <= 4 and ships.size() == c.protect_civilians_total, "2 to 4 civilian ships appear (%d)" % ships.size())
	var kinds_ok := true
	var seen_kinds := {}
	for s in ships:
		if s.kind not in ["civilian_a", "civilian_b", "civilian_c", "civilian_d", "civilian_e"] or seen_kinds.has(s.kind) or not is_equal_approx(float(s.hull), 1.0):
			kinds_ok = false
		seen_kinds[s.kind] = true
	check(kinds_ok, "Each is a different civilian type, at full hull")
	check(c.active_boosts == boosts_before, "A Systems Bonus from the Major engagement carries over to the next wave")
	check(c.interceptor_ready_in() <= 0.0, "LAUNCH INTERCEPTORS is ready at the start of the round")
	# Variety over many rounds.
	var counts_seen := {}
	var kinds_seen := {}
	for seed_value in range(60):
		start_protect(c, 1, seed_value)
		counts_seen[c.protect_civilians_total] = true
		for s in civilians(c):
			kinds_seen[s.kind] = true
	check(counts_seen.has(2) and counts_seen.has(3) and counts_seen.has(4) and counts_seen.size() == 3, "Over 60 rounds: 2, 3 and 4 ships all appear")
	check(kinds_seen.size() == 5, "Over 60 rounds: all five civilian types A-E appear")
	# Attack Drone count by set and difficulty.
	var drone_table := {0: [2, 4, 6, 8, 10, 10], 1: [4, 6, 8, 10, 12, 12], 2: [6, 8, 10, 12, 12, 12]}
	for level in [0, 1, 2]:
		fresh(c, level)
		var got: Array[int] = []
		for done in range(1, 7):
			c.sets_completed = done
			got.append(c.protect_drone_count())
		check(got == drone_table[level], "Level %d: Attack Drones by set %s" % [level, str(got)])
	# Interceptors only.
	start_protect(c, 1)
	check(c.gunship_limit() == 0 and c.launch_gunship() == 0 and c.count_kind("gunship") == 0, "No Gunships in the round")
	c.prox_burst_remaining = c.prox_burst_seconds
	c.set_prox_defense(true)
	check(not c.can_fire_battery() and not c.prox_active, "Defense Shield off in the round")
	c.jump_recharge_remaining = 0.0
	check(not c.can_jump() and not c.request_jump(), "JUMP held in the round (default)")
	c._update_own_weapons(0.5)
	check(c.count_kind("own_missile") == 0, "No ship missiles in the round")
	check(not c.can_launch_stealth(), "No Stealth Interceptor in the round")
	# Interceptor launches capped at the Attack Drone count.
	var total_drones: int = c.protect_drones_total
	check(total_drones == 4, "Normal, after set 1: 4 Attack Drones")
	var launched := 0
	for i in range(10):
		c.interceptor_waits.clear()
		c.interceptor_waits.clear()
		launched += c.launch_interceptors()
	check(launched == total_drones and c.count_interceptors() == total_drones and c.interceptor_limit() == total_drones, "Interceptor launches stop at the Attack Drone count (%d)" % launched)
	for i in range(c.contacts.size() - 1, -1, -1):
		if c.contacts[i].kind == "interceptor":
			c.contacts.remove_at(i)
			break
	c.interceptor_waits.clear()
	c.interceptor_waits.clear()
	check(c.launch_interceptors() == 0 and c.interceptor_limit() == c.count_interceptors(), "A lost Interceptor is not replaced: launches, not Interceptors on the scope, are capped")
	# Auto options pause.
	start_protect(c, 1)
	c.auto_launch_interceptors = true
	c.auto_launch_gunships = true
	c.auto_defense_battery = true
	c.prox_burst_remaining = c.prox_burst_seconds
	c._update_protect(0.0)
	for r in protect_drones(c):
		r.position = Vector3(0.0, 0.0, 0.0)
	c._update_automation()
	# 1.2.7: Auto Launch Interceptors carries through to the round; the others still pause.
	check(c.count_interceptors() > 0 and c.count_kind("gunship") == 0 and not c.prox_active, "Auto Launch Interceptors launches in the round; Auto Launch Gunships and the auto shield pause (1.2.7)")
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.auto_defense_battery = false
	# Attack Drones arrive in groups and attack only civilians.
	start_protect(c, 1)
	c._update_protect(0.0)
	check(c.protect_drones_spawned == 2 and protect_drones(c).size() == 2, "Attack Drones arrive two at a time")
	c._update_protect(c.protect_drone_group_gap + 0.01)
	check(c.protect_drones_spawned == 4 and c.protect_drones_left() == 4, "All 4 Attack Drones arrive")
	for r in protect_drones(c):
		c._update_protect_drone(r, 0.05)
	var claims := {}
	for r in protect_drones(c):
		claims[r.civ_target] = int(claims.get(r.civ_target, 0)) + 1
	var spread_ok := true
	for k in claims:
		if civilians(c).size() >= 2 and claims[k] > 2 + int(4 / civilians(c).size()):
			spread_ok = false
	check(claims.size() >= 2 and spread_ok, "Attack Drones spread over the civilian ships (%s)" % str(claims))
	# Kill time by difficulty.
	for level in [0, 1, 2]:
		start_protect(c, level)
		c._spawn_protect_drone(false)
		var r: Dictionary = protect_drones(c)[0]
		var ship: Dictionary = civilians(c)[0]
		r.civ_target = ship.id
		var seconds: float = [26.0, 20.0, 14.0][level]
		var t := 0.0
		while t < seconds - 0.25:
			r.position = ship.position
			c._update_protect_drone(r, 0.1)
			t += 0.1
		check(not c.find_contact(ship.id).is_empty() and float(ship.hull) > 0.0 and float(ship.hull) < 0.03, "Level %d: one Attack Drone has nearly destroyed a ship after %.1f s" % [level, t])
		for i in range(5):
			r.position = ship.position
			c._update_protect_drone(r, 0.1)
		check(c.find_contact(ship.id).is_empty() and c.protect_lost == 1, "Level %d: one Attack Drone destroys a civilian ship in %d s" % [level, int(seconds)])
	start_protect(c, 1)
	c._spawn_protect_drone(false)
	c._spawn_protect_drone(false)
	var pair := protect_drones(c)
	var target: Dictionary = civilians(c)[0]
	pair[0].civ_target = target.id
	pair[1].civ_target = target.id
	var tt := 0.0
	while not c.find_contact(target.id).is_empty() and tt < 30.0:
		for r in pair:
			r.position = target.position
			c._update_protect_drone(r, 0.1)
		tt += 0.1
	check(tt > 9.8 and tt < 10.3, "Two Attack Drones on one ship take half as long (%.1f s)" % tt)
	# Damage colors: blue dimming to grey-blue, blinking when critical, never amber or red.
	start_protect(c, 1)
	var ship_c: Dictionary = civilians(c)[0]
	check(c.display_color(ship_c).is_equal_approx(c.civilian_color) and c.contact_tag(ship_c) == "SUPPORT 100%", "Undamaged: blue, SUPPORT 100%")
	ship_c.hull = 0.6
	var mid_color: Color = c.display_color(ship_c)
	check(mid_color.is_equal_approx(c.civilian_damaged_color.lerp(c.civilian_color, 0.6)) and c.contact_tag(ship_c) == "SUPPORT 60%", "60% hull: dimmer blue in proportion, SUPPORT 60%")
	ship_c.hull = 0.2
	var alphas := {}
	for step in range(12):
		c.battle_time = step * 0.05
		alphas[snappedf(c.display_color(ship_c).a, 0.01)] = true
	check(alphas.size() >= 2, "Critical hull blinks")
	var blue_ok := true
	for h in [1.0, 0.8, 0.6, 0.4, 0.2, 0.05]:
		ship_c.hull = h
		var col: Color = c.display_color(ship_c)
		if not (col.b > col.r + 0.1 and col.b > col.g):
			blue_ok = false
	check(blue_ok, "Every damage level stays blue (no amber or red)")
	check(c.label_color(c.display_color(ship_c)).b > 0.4, "Label tinted to match")
	# Interceptors destroy Attack Drones; the round ends when every Attack Drone is destroyed.
	start_protect(c, 1)
	events.clear()
	var score0: int = c.score
	while c.protect_drones_spawned < c.protect_drones_total:
		c._update_protect(c.protect_drone_group_gap + 0.01)
	c.launch_interceptors()
	var v: Dictionary = {}
	for x in c.contacts:
		if x.kind == "interceptor":
			v = x
	v.phase = "intercept"
	var kills := 0
	for r in protect_drones(c):
		r.position = Vector3(0.0, -0.1, 0.0)
	for step in range(400):
		var left := protect_drones(c)
		if left.is_empty():
			break
		v.position = left[0].position
		v.drone_fire_remaining = 0.0
		c._update_interceptors(0.1)
	check(c.protect_drones_destroyed == 4 and c.score > score0, "Interceptors destroy the Attack Drones (2 hits each) and score them")
	c._update_protect(0.1)
	check(c.wave_phase == "rest" and c.rest_after_protect and c.protect_end_reason == "ATTACK DRONES DESTROYED", "All Attack Drones destroyed: the round ends")
	var full_bonus: int = c.points_for(500 * c.protect_civilians_total + 1000)
	check(c.protect_saved == c.protect_civilians_total and c.last_protect_bonus == full_bonus and c.protect_full_fleets == 1, "Full fleet saved: 500 per ship + 1000, x score multiplier (%d)" % full_bonus)
	var lines: Array[String] = c.rest_tally_lines()
	# 1.2.7: result title, a detail line, the bonus on its own line, then its label.
	check(lines[0] == "SUPPORT FLEET SAVED" and lines[1].begins_with("SUPPORT HULL") and c.protect_saved == c.protect_civilians_total, "Tally: SUPPORT FLEET SAVED, every ship saved; the detail line starts with the fleet hull (1.2.9)")
	check(lines[1].contains("SUPPORT HULL 100%") and lines[2] == "+%d" % full_bonus and lines[3].ends_with("FULL CONVOY"), "Tally: hull and bonus (1.2.7 layout)")
	check(lines[-1].begins_with("NEXT  WAVE 6 PROBE"), "Tally: next wave 6")
	check(c.count_kind("civilian_a") + c.count_kind("civilian_b") + c.count_kind("civilian_c") + c.count_kind("civilian_d") + c.count_kind("civilian_e") == 0, "Civilian ships leave after the round")
	var interceptors_home := true
	for x in c.contacts:
		if x.kind == "interceptor" and x.phase != "return":
			interceptors_home = false
	check(interceptors_home, "Interceptors head home after the round")
	var logged := false
	for e in events:
		if e.begins_with("protect the fleet complete (ATTACK DRONES DESTROYED)"):
			logged = true
	check(logged, "Session log records the round result")
	c.wave_rest_remaining = 0.0
	c.wave_inbound_announced = true
	c._update_wave_system(0.1)
	check(c.wave_phase == "assault" and c.wave == 6, "Next comes wave 6")
	check(not c.protect_active() and c.gunship_limit() == c.max_gunships and c.interceptor_limit() >= c.max_interceptors, "Normal limits return after the round")
	# Hull-weighted bonus with a loss.
	start_protect(c, 1, 5)
	while civilians(c).size() < 3:
		start_protect(c, 1, randi())
	var list := civilians(c)
	list[0].hull = 1.0
	list[1].hull = 0.5
	c._remove_contact(list[2].id)
	for i in range(3, list.size()):
		c._remove_contact(list[i].id)
	c.protect_drones_spawned = c.protect_drones_total
	c._update_protect(0.1)
	check(c.protect_saved == 2 and c.last_protect_bonus == c.points_for(750) and c.protect_hull_kept == 75, "Bonus is hull-weighted: 500 x (1.0 + 0.5), no full-fleet bonus (%d)" % c.last_protect_bonus)
	# Time limit: Attack Drones still present jump away.
	start_protect(c, 1)
	c._update_protect(0.0)
	c.protect_elapsed = c.protect_round_seconds
	c._update_protect(0.01)
	check(c.wave_phase == "rest" and c.protect_end_reason == "TIME" and c.protect_drones_escaped == 2 and c.count_kind("drone") == 0, "60 s limit: Attack Drones still present jump away")
	# Every civilian lost.
	start_protect(c, 1)
	for s in civilians(c):
		c._remove_contact(s.id)
	c._update_protect(0.1)
	check(c.protect_end_reason == "SUPPORT FLEET LOST" and c.last_protect_bonus == 0 and c.protect_saved == 0, "All civilian ships lost: the round ends with no bonus")
	# A full unassisted round in the battle loop: Attack Drones only, no Enemy Carriers, missiles or nukes.
	start_protect(c, 1, 99)
	var only_drones := true
	var guard := 0
	while c.wave_phase == "protect" and guard < 1000:
		c._process(0.1)
		guard += 1
		for x in c.contacts:
			if x.kind in ["carrier", "unknown", "missile", "nuke", "breacher", "siege_ship", "gunship", "own_missile"]:
				only_drones = false
	check(only_drones, "Unassisted round: Attack Drones only")
	check(c.wave_phase == "rest" and c.protect_end_reason in ["SUPPORT FLEET LOST", "TIME"] and guard <= 601, "Unassisted round ends by the 60 s limit or the fleet lost (%s, %.1f s)" % [c.protect_end_reason, guard * 0.1])
	check(c.hull >= c.max_hull - 0.01, "Attack Drones in the round do not damage the ship")
	print("V122_PROTECT unassisted reason=", c.protect_end_reason, " seconds=", guard * 0.1, " saved=", c.protect_saved, "/", c.protect_civilians_total, " lost=", c.protect_lost)
	# JUMP. 1.2.7: the Protect Allow Jump option is removed; JUMP is always held in the round.
	start_protect(c, 1)
	c.jump_recharge_remaining = 0.0
	check(not c.can_jump() and not c.request_jump(), "JUMP cannot be used during the round (1.2.7)")
	check(c.wave_phase == "protect", "The round goes on after a refused jump (1.2.7)")
	# Old sweep is an Inspector option.
	fresh(c, 1)
	c.set_end_round = 1
	c.wave = 5
	c._clear_wave()
	check(c.wave_next_phase == "sweep", "Set End Round = Bonus sweep keeps the 1.2.0 sweep")
	fresh(c, 1)
	c.set_end_round = 2
	c.wave = 5
	c._clear_wave()
	check(c.wave_next_phase == "assault", "Set End Round = None goes straight to wave 6")
	c.set_end_round = 0
	# Console buttons in the round.
	start_protect(c, 1)
	console._process(0.0)
	check(console.gunship_button.disabled and console.gunship_button.text.ends_with("INTERCEPTORS ONLY"), "LAUNCH GUNSHIP reads OFF | INTERCEPTORS ONLY")
	check(console.prox_button.disabled and console.prox_button.text.ends_with("INTERCEPTORS ONLY"), "DEFENSE SHIELD reads OFF | INTERCEPTORS ONLY")
	check(console.jump_button.disabled and console.jump_button.text.ends_with("HELD | PROTECT THE CONVOY"), "JUMP reads HELD")
	check(not console.launch_button.disabled, "LAUNCH INTERCEPTORS is ready")
	check(c.wave_phase_line().begins_with("ATTACK DRONES LEFT 4  |  "), "Right panel: Attack Drones left and time")
	# Reset clears the round.
	c.reset_battle()
	check(not c.protect_active() and c.protect_rounds == 0 and c.protect_drones_total == 0, "New battle clears the round")

	print("V122_RESULT checks=", checks, " failures=", failures)
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await process_frame
	console.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
