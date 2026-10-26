extends SceneTree
## 0.1.2 feature checks: Protect the fleet Normal rebalance (Interceptor Share 0.5, Fewer
## Interceptors off on Normal, one 25% Gunship patch per ship), spread targeting, Rapid Repair
## 100% fix, second Enemy Carrier nuke, Rapid Missile bonus, the paused missile bonus pick
## prompt (10 s timeout keeps current, offered again after each set, no swap button),
## the Double Missile quick pair, the three export presets and the version.

var failures := 0
var checks := 0
var console: Control
var c: Control

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
	c.breachers_enabled = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.nuclear_weapons_enabled = false
	c.siege_enabled = false
	c.auto_defense_battery = false
	c.auto_firewall = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.auto_jump = false
	c.auto_rapid_repair = false
	c.reset_battle()
	c.pending.clear()
	c.contacts.clear()

func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
		b.drone_timer = 999.0
		b.missile_timer = 999.0
		b.heavy_timer = 999.0
	return b

func fire_volley() -> void:
	c.own_fire_remaining = 0.0
	c._update_own_weapons(0.0)

func missile_targets() -> Array:
	var out := []
	for x in c.contacts:
		if x.kind == "own_missile":
			out.append(x.get("target_id", ""))
	return out

func earn(points: int) -> void:
	c._add_points(points)

func start_protect(level: int, sets: int, seed_value: int = 7) -> void:
	clean(level)
	c.auto_spawn = true
	c.waves_enabled = true
	c.rng.seed = seed_value
	c.wave = sets * 5
	c.sets_completed = sets
	c.wave_phase = "rest"
	c.wave_next_phase = "protect"
	c.safe_remaining = 0.0
	c._start_protect()

func round_drone_total() -> int:
	return int(c.protect_drones_total)

func all_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		all_buttons(child, out)

func _run() -> void:
	# ---- Version and export presets ----
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 0.1.2")
	var presets := ConfigFile.new()
	check(presets.load("res://export_presets.cfg") == OK, "Export presets load")
	check(presets.get_value("preset.0", "name") == "Windows Desktop" and presets.get_value("preset.0.options", "binary_format/architecture") == "x86_64"
		and str(presets.get_value("preset.0", "export_path")).ends_with("Stellar_Defense_Console_1.1.1_Windows_x64.exe"), "Windows x64 preset")
	check(presets.get_value("preset.2", "name") == "Windows Desktop ARM64" and presets.get_value("preset.2.options", "binary_format/architecture") == "arm64"
		and str(presets.get_value("preset.2", "export_path")).ends_with("Stellar_Defense_Console_1.1.1_Windows_arm64.exe"), "Windows ARM64 preset")
	check(presets.get_value("preset.1", "platform") == "macOS" and presets.get_value("preset.1.options", "binary_format/architecture") == "universal"
		and str(presets.get_value("preset.1", "export_path")).ends_with("Stellar_Defense_Console_1.1.1_Mac.zip")
		and presets.get_value("preset.1.options", "application/short_version") == "1.1.1", "Mac universal preset (Intel and M-series)")
	check(presets.get_value("preset.0.options", "application/file_version") == "1.1.1" and presets.get_value("preset.2.options", "application/file_version") == "1.1.1", "Windows file versions follow the project version (as 1.2.9)")

	# ---- Script defaults (1.2.9 behaviour) and the scene's 0.1.2 values ----
	var plain: Control = load("res://scripts/RadarContacts.gd").new()
	for key in ["ship_missiles_spread_carriers", "double_missile_quick_pair", "carrier_second_nuke", "rapid_missile_bonus", "rapid_repair_needs_shown_damage"]:
		check(plain.get(key) == false, "Script default off (1.2.9): " + key)
	check(plain.missile_bonus_pick_after_wave == true, "1.0.6: script default on: missile_bonus_pick_after_wave (pick waits for the end of the round)")
	check(is_equal_approx(plain.protect_hard_interceptor_share, 0.5) and plain.protect_hard_fewer_on_top == false and is_equal_approx(plain.protect_hard_gunship_patch, 0.25), "Hard Protect defaults: share 0.5, Fewer Interceptors off, 25% patch")
	check(is_equal_approx(plain.protect_fleet_spread, 1.6), "Fleet spread 1.6 on every difficulty")
	check(is_equal_approx(plain.protect_hard_gunship_chance, 1.0) and is_equal_approx(plain.protect_gunship_chance, 0.5), "Repair Tender: every eligible round on Hard, half on Normal/Easy")
	check(is_equal_approx(plain.protect_normal_interceptor_share, 0.5) and plain.protect_normal_fewer_on_top == false and is_equal_approx(plain.protect_normal_gunship_patch, 0.25), "Normal Protect defaults: share 0.5, Fewer Interceptors off, 25% patch")
	check(is_equal_approx(plain.normal_second_nuke_min_seconds, 75.0) and is_equal_approx(plain.normal_second_nuke_max_seconds, 120.0), "Normal second nuke 75-120 s")
	check(is_equal_approx(plain.hard_second_nuke_min_seconds, 180.0) and is_equal_approx(plain.hard_second_nuke_max_seconds, 300.0), "Hard second nuke 180-300 s")
	check(plain.normal_rapid_missile_points == 10000 and plain.hard_rapid_missile_points == 6000 and is_equal_approx(plain.normal_rapid_missile_interval, 6.0) and is_equal_approx(plain.hard_rapid_missile_interval, 5.0), "Rapid Missile: Normal 10,000 pts / 6 s, Hard 6,000 pts / 5 s")
	check(is_equal_approx(plain.double_missile_pair_seconds, 0.3), "Quick pair gap 0.3 s")
	check(plain.missile_bonus_offer_each_set == true, "Pick offered again after each set")
	check(plain.get("test_pick_double") == null, "Prototype computer pick removed")
	plain.free()

	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://test_v130.cfg"
	console.quit_dry_run = true
	console.shell_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	root.add_child(console)
	c.set_process(false)
	for key in ["ship_missiles_spread_carriers", "double_missile_quick_pair", "carrier_second_nuke", "rapid_missile_bonus", "rapid_repair_needs_shown_damage", "missile_bonus_pick_after_wave"]:
		check(c.get(key) == true, "Scene turns on: " + key)
	check(is_equal_approx(console.bonus_pick_seconds, 20.0), "1.0.5: pick prompt timeout 20 s (Inspector)")
	var scene_text := FileAccess.get_file_as_string("res://scenes/RadarConsole.tscn")
	check(not scene_text.contains("test_pick_double") and not scene_text.contains("protect_normal_") and not scene_text.contains("protect_hard_") and not scene_text.contains("protect_fleet_spread"), "Scene carries no prototype or Protect overrides")

	# ---- Rapid Repair 100% fix ----
	clean(1)
	c.repair_charges = 1
	c.hull = c.max_hull * 0.996
	check(c.hull_percent() == 100, "Hull 99.6% reads 100%")
	check(not c.can_rapid_repair(), "Rapid Repair grey when the readout shows 100%")
	c.request_rapid_repair()
	check(c.repair_charges == 1 and c.rapid_repair_remaining <= 0.0, "No charge spent at a shown 100%")
	c.hull = c.max_hull * 0.98
	check(c.hull_percent() == 98 and c.can_rapid_repair(), "Rapid Repair live at 98%")
	c.rapid_repair_needs_shown_damage = false
	c.hull = c.max_hull * 0.996
	check(c.can_rapid_repair(), "Switch off gives the 1.2.9 behaviour")
	c.rapid_repair_needs_shown_damage = true
	for level in [0, 2]:
		clean(level)
		c.repair_charges = 1
		c.hull = c.max_hull * 0.996
		check(not c.can_rapid_repair(), "Fix applies on difficulty %d" % level)

	# ---- Spread targeting ----
	clean(1)
	c.own_weapons_enabled = true
	var b1 := base()
	var b2 := base()
	b1.hits_remaining = 1
	b2.hits_remaining = 5
	fire_volley()
	fire_volley()
	var t := missile_targets()
	check(t.size() == 2 and t[0] == b1.id and t[1] == b2.id, "Normal: a covered Enemy Carrier is skipped (second missile to the other)")
	clean(0)
	c.own_weapons_enabled = true
	b1 = base()
	b2 = base()
	b1.hits_remaining = 1
	b2.hits_remaining = 5
	fire_volley()
	fire_volley()
	t = missile_targets()
	check(t.size() == 2 and t[0] == b1.id and t[1] == b1.id, "Easy keeps the 1.2.9 choice")

	# ---- Double Missile quick pair ----
	clean(0)
	c.own_weapons_enabled = true
	c.double_missile_unlocked_at = 0.0
	b1 = base()
	b2 = base()
	check(c.missiles_per_volley() == 2, "Double Missile active (Easy)")
	fire_volley()
	check(c.count_kind("own_missile") == 1, "Quick pair: first missile only at launch")
	c._update_own_weapons(0.28)
	check(c.count_kind("own_missile") == 1, "Quick pair: still one at 0.28 s")
	c._update_own_weapons(0.03)
	check(c.count_kind("own_missile") == 2, "Quick pair: second missile at about 0.3 s")
	check(c.own_pair_launches == 1, "Quick pair counted")
	c._update_own_weapons(1.0)
	check(c.count_kind("own_missile") <= 2, "No extra missile after the pair")
	clean(1)
	c.own_weapons_enabled = true
	c.double_missile_unlocked_at = 0.0
	c.rapid_missile_bonus = false
	b1 = base()
	b2 = base()
	fire_volley()
	c._update_own_weapons(0.31)
	t = missile_targets()
	check(t.size() == 2 and t[0] != t[1], "Normal quick pair: the two missiles go to two Enemy Carriers")
	c.rapid_missile_bonus = true
	clean(0)
	c.own_weapons_enabled = true
	c.double_missile_unlocked_at = 0.0
	c.double_missile_quick_pair = false
	base()
	fire_volley()
	check(c.count_kind("own_missile") == 2, "Quick pair off: both missiles at once (1.2.9)")
	c.double_missile_quick_pair = true
	clean(0)
	c.own_weapons_enabled = true
	c.double_missile_unlocked_at = 0.0
	base()
	fire_volley()
	c.reset_battle()
	check(c.own_pair_remaining == 0.0, "New battle clears a waiting second missile")

	# ---- Second Enemy Carrier nuke ----
	for level in [1, 2]:
		var low := 75.0 if level == 1 else 180.0
		var high := 120.0 if level == 1 else 300.0
		var in_range := true
		for n in range(40):
			clean(level)
			var b := base()
			c._launch_nuclear(b)
			if b.get("nuclear_launched", true) or float(b.nuclear_timer) < low - 0.001 or float(b.nuclear_timer) > high + 0.001:
				in_range = false
		check(in_range, "Difficulty %d: re-arms once, cool-down %d-%d s" % [level, low, high])
		clean(level)
		var b := base()
		c._launch_nuclear(b)
		c._launch_nuclear(b)
		check(b.nuclear_launched == true and int(b.nukes_fired) == 2 and c._launch_nuclear(b) == "", "Difficulty %d: two nukes per Enemy Carrier, no third" % level)
	clean(0)
	b1 = base()
	c._launch_nuclear(b1)
	check(b1.nuclear_launched == true and c._launch_nuclear(b1) == "", "Easy: one nuke per Enemy Carrier")

	# ---- Rapid Missile bonus ----
	clean(1)
	earn(9999)
	check(not c.rapid_missile_active(), "Normal: no Rapid Missile below 10,000 points")
	earn(1)
	check(c.rapid_missile_active() and is_equal_approx(c.ship_missile_gap(), 5.0) and c.missiles_per_volley() == 1, "Normal: Rapid Missile at 10,000 points, 1 missile every 5 s (1.0.9)")
	clean(2)
	earn(6000)
	check(c.rapid_missile_active() and is_equal_approx(c.ship_missile_gap(), 4.0), "Hard: Rapid Missile at 6,000 points, every 4 s (1.0.9)")
	clean(0)
	earn(50000)
	check(not c.rapid_missile_active() and c.double_missile_active() and c.missile_bonus_offers == 0, "Easy: no Rapid Missile and never a pick")

	# ---- Missile bonus pick prompt ----
	var panel: Control = console.bonus_pick_panel
	check(panel != null and panel.get_parent() == console, "Pick prompt built into the console")
	check(panel.get_index() > console.gear_button.get_index(), "Prompt sits above the gear button")
	clean(1)
	c.set_process(true)
	earn(10000)
	check(not console.bonus_pick_open, "No prompt with only Rapid Missile")
	earn(7500)
	check(console.bonus_pick_open and panel.visible and c.missile_bonus_offer_open, "Prompt opens when Double Missile is earned")
	check(not c.is_processing(), "Battle paused while the prompt is open")
	check(c.rapid_missile_active() and not c.double_missile_active(), "Current bonus stays in use until a pick")
	check(panel.message_label.text == "You just earned DOUBLE MISSILE. You can only have one missile bonus.", "Prompt message matches the mockup")
	check(panel.card_tags[0].text == "YOU HAVE NOW" and panel.card_titles[0].text == "RAPID MISSILE" and panel.card_effects[0].text == "Fires 1 missile\nevery 5 seconds\nMissiles fly 20% faster", "Current card matches the 1.0.9 card text")
	check(panel.card_tags[1].text == "JUST EARNED" and panel.card_titles[1].text == "DOUBLE MISSILE" and panel.card_effects[1].text == "Fires a pair of missiles\nevery 8 seconds\nCan hit two targets at once", "Just-earned card matches the 1.0.9 card text")
	check(panel.timeout_label.text == "No pick in 20 s: you keep RAPID MISSILE", "Timeout line: 20 s countdown")
	check(panel.get("keep_button") == null and panel.get("take_button") == null and panel.cards.size() == 2 and panel.cards[0] is Button and panel.highlighted == 0, "1.0.5: no KEEP / TAKE buttons; the two cards are the buttons, current one highlighted")
	var buttons := []
	all_buttons(console, buttons)
	var swap_found := false
	for button in buttons:
		if str(button.text).to_upper().contains("SWAP"):
			swap_found = true
	check(not swap_found, "No swap button anywhere")
	console.toggle_settings()
	check(not console.settings_open, "Settings cannot open over the prompt")
	panel._process(19.9)
	check(console.bonus_pick_open, "Prompt still open at 19.9 s")
	panel._process(0.2)
	check(not console.bonus_pick_open and not panel.visible and c.is_processing(), "Prompt closes after 20 s and the battle resumes")
	check(c.missile_bonus_pick == "RAPID" and c.rapid_missile_active() and not c.double_missile_active(), "No pick in time keeps Rapid Missile")
	check(c.status_message == "RAPID MISSILE BONUS ACTIVE", "Status shows the kept bonus")
	# After a set: offered again.
	c.wave = 5
	c._clear_wave()
	check(console.bonus_pick_open and c.missile_bonus_set_offers == 1, "Offered again after a set of five waves")
	check(panel.message_label.text == "Set complete: keep your missile bonus or switch." and panel.card_tags[1].text == "YOU CAN SWITCH TO", "After-set wording")
	panel.cards[1].pressed.emit()
	check(not console.bonus_pick_open and c.missile_bonus_pick == "DOUBLE" and c.double_missile_active() and not c.rapid_missile_active(), "Clicking the DOUBLE card switches the bonus")
	check(c.missiles_per_volley() == 2 and is_equal_approx(c.ship_missile_gap(), 8.0), "Double Missile: a pair every 8 s")
	c.wave = 10
	c._clear_wave()
	check(console.bonus_pick_open and panel.card_titles[0].text == "DOUBLE MISSILE" and panel.card_titles[1].text == "RAPID MISSILE", "Next set offers the other way round")
	panel.cards[0].pressed.emit()
	check(c.missile_bonus_pick == "DOUBLE" and c.missile_bonus_switches == 1, "Clicking the current card keeps it")
	c.wave = 12
	c._clear_wave()
	check(not console.bonus_pick_open, "No offer after a wave that ends no set")
	c.missile_bonus_offer_each_set = false
	c.wave = 15
	c._clear_wave()
	check(not console.bonus_pick_open, "After-set offer can be switched off")
	c.missile_bonus_offer_each_set = true
	# Double first, then Rapid (Hard with the thresholds swapped for the test).
	clean(2)
	c.hard_rapid_missile_points = 25000
	earn(20000)
	check(c.double_missile_active() and not console.bonus_pick_open, "Hard: Double Missile first, no prompt")
	earn(5000)
	check(console.bonus_pick_open and panel.message_label.text == "You just earned RAPID MISSILE. You can only have one missile bonus." and panel.card_titles[0].text == "DOUBLE MISSILE" and panel.card_effects[1].text == "Fires 1 missile\nevery 4 seconds\nMissiles fly 20% faster", "Rapid earned second: DOUBLE card first, RAPID card second, every 4 s on Hard (1.0.9)")
	panel.cards[1].pressed.emit()
	check(c.rapid_missile_active() and not c.double_missile_active(), "TAKE RAPID")
	c.hard_rapid_missile_points = 6000
	# Earned mid-fight: the pick waits for the end of the wave.
	clean(1)
	c.auto_spawn = true
	c.waves_enabled = true
	c.wave = 3
	c.wave_phase = "assault"
	c.set_process(true)
	earn(17500)
	check(not console.bonus_pick_open and not c.missile_bonus_offer_open and c.missile_bonus_offer_waiting, "Mid-wave: no prompt, pick held for the end of the wave")
	check(c.rapid_missile_active() and not c.double_missile_active() and c.is_processing(), "Mid-wave: battle keeps running with Rapid Missile")
	check(c.status_message == "DOUBLE MISSILE EARNED | PICK YOUR BONUS AFTER THIS ROUND", "1.0.6: mid-wave status line names the bonus just earned (Double)")
	c._clear_wave()
	check(console.bonus_pick_open and panel.message_label.text == "You just earned DOUBLE MISSILE. You can only have one missile bonus." and not c.missile_bonus_offer_waiting, "Prompt opens when the wave is cleared")
	panel.cards[0].pressed.emit()
	check(c.missile_bonus_pick == "RAPID" and c.missile_bonus_set_offers == 0, "Kept; no extra after-set offer")
	# Earned in Protect the fleet: the pick waits for the end of the round.
	start_protect(1, 1)
	c.set_process(true)
	earn(17500)
	check(not console.bonus_pick_open and c.missile_bonus_offer_waiting, "Protect round: pick held")
	c._end_protect("test")
	check(console.bonus_pick_open, "Prompt opens when the round ends")
	panel.cards[0].pressed.emit()
	# Switched off: the prompt opens at once, as before.
	clean(1)
	c.auto_spawn = true
	c.waves_enabled = true
	c.wave = 3
	c.wave_phase = "assault"
	c.missile_bonus_pick_after_wave = false
	c.set_process(true)
	earn(17500)
	check(console.bonus_pick_open, "Pick After Wave off: prompt opens mid-wave")
	panel.cards[0].pressed.emit()
	c.missile_bonus_pick_after_wave = true
	# A new battle while the prompt is open closes it without a pick.
	clean(1)
	c.set_process(true)
	earn(17500)
	check(console.bonus_pick_open, "Prompt open before reset")
	c.reset_battle()
	console._process(0.0)
	check(not console.bonus_pick_open and not panel.visible and c.is_processing(), "Reset closes the prompt")
	c.set_process(false)
	# Without a console (computer tests) the current bonus is kept.
	var lone: Control = load("res://scripts/RadarContacts.gd").new()
	lone.rapid_missile_bonus = true
	lone.difficulty = 1
	lone.active_difficulty = 1
	lone.missile_bonus_pick_after_wave = false
	lone._add_points(17500)
	check(lone.rapid_missile_active() and not lone.missile_bonus_offer_open and lone.missile_bonus_offers == 1, "No console: keeps the current bonus")
	lone.free()

	# ---- Protect the fleet Normal rebalance ----
	start_protect(1, 1)
	var total := round_drone_total()
	check(total > 0 and c.protect_interceptor_total() == ceili(total * 0.5), "Normal: Interceptor launches = half the Attack Drones, rounded up (%d of %d)" % [c.protect_interceptor_total(), total])
	c.protect_short_interceptors = 2
	if not c.protect_challenges.has("fewer"):
		c.protect_challenges.append("fewer")
	check(c.protect_interceptor_total() == ceili(total * 0.5), "Normal: Fewer Interceptors has no effect")
	start_protect(0, 1)
	var easy_drones := round_drone_total()
	c.protect_short_interceptors = 2
	check(c.protect_interceptor_total() == easy_drones - 2, "Easy: share not applied, Fewer Interceptors still counts")
	start_protect(2, 2)
	var hard_drones := round_drone_total()
	check(hard_drones > 0 and c.protect_interceptor_total() == ceili(hard_drones * 0.5), "Hard: Interceptor launches = half the Attack Drones, rounded up (%d of %d)" % [c.protect_interceptor_total(), hard_drones])
	c.protect_short_interceptors = 2
	check(c.protect_interceptor_total() == ceili(hard_drones * 0.5), "Hard: Fewer Interceptors has no effect")
	c.protect_hard_interceptor_share = 1.0
	check(c.protect_interceptor_total() == hard_drones - 2, "Hard Interceptor Share 1.0 gives the 1.2.9 rule back")
	c.protect_hard_interceptor_share = 0.5
	# Hard: the repair Gunship joins the round after wave 10 (set 2).
	var hard_gunships := 0
	for seed_value in range(10):
		start_protect(2, 2, 500 + seed_value)
		# 1.0.7.2: the tender may wait on your ship for the first damaged ship.
		if not c.repair_tender().is_empty() or c.protect_tender_waiting:
			hard_gunships += 1
	check(hard_gunships == 10, "Hard: repair Gunship in every round after wave 10 (%d of 10)" % hard_gunships)
	# Fleet spread: ships start further from the centre, always inside the scope.
	for level in [0, 1, 2]:
		var dist := {}
		var inside := true
		for spread in [1.0, 1.6]:
			var total_d := 0.0
			var n := 0
			for seed_value in range(20):
				c.protect_fleet_spread = spread
				start_protect(level, 2, 300 + seed_value)
				for x in c.contacts:
					if x.get("faction", "") == "civilian":
						total_d += Vector2(x.position.x, x.position.y).length()
						n += 1
						if not load("res://scripts/ScopeShape.gd").contains(Vector2(x.position.x, -x.position.y), 0.1):
							inside = false
			dist[spread] = total_d / maxi(1, n)
		c.protect_fleet_spread = 1.6
		check(dist[1.6] > dist[1.0] * 1.35, "Difficulty %d: spread 1.6 starts ships further out (%.2f vs %.2f)" % [level, dist[1.6], dist[1.0]])
		check(inside, "Difficulty %d: spread ships start inside the scope" % level)
	# Gunship patch: one 25% patch per ship, then it moves on.
	c.protect_gunship_chance = 1.0
	start_protect(1, 3, 16)
	c.civilian_self_repair = false
	var gunship: Dictionary = c.repair_tender()
	if gunship.is_empty():
		c._spawn_repair_tender()
		gunship = c.repair_tender()
	check(not gunship.is_empty(), "Repair Tender present")
	var ships := []
	for x in c.contacts:
		if x.get("faction", "") == "civilian":
			ships.append(x)
	check(ships.size() >= 2, "Two or more civilian ships")
	if ships.size() >= 2 and not gunship.is_empty():
		for s in ships:
			s.hull = 1.0
		ships[0].hull = 0.30
		ships[1].hull = 0.50
		for frame in range(60 * 90):
			c._update_protect_extras(1.0 / 60.0)
		check(absf(float(ships[0].hull) - 0.55) < 0.005 and absf(float(ships[0].get("patched", 0.0)) - 0.25) < 0.005, "Ship 1 patched once: 30% -> 55%")
		check(absf(float(ships[1].hull) - 0.75) < 0.005, "Ship 2 patched once: 50% -> 75%")
		check(gunship.get("target_id", "") == "", "Gunship moves on when every ship has had its patch")
	c.protect_gunship_chance = 1.0
	start_protect(2, 3, 16)
	c.civilian_self_repair = false
	gunship = c.repair_tender()
	if gunship.is_empty():
		c._spawn_repair_tender()
		gunship = c.repair_tender()
	ships = []
	for x in c.contacts:
		if x.get("faction", "") == "civilian":
			ships.append(x)
	if ships.size() >= 1 and not gunship.is_empty():
		for s in ships:
			s.hull = 1.0
		ships[0].hull = 0.30
		for frame in range(60 * 90):
			c._update_protect_extras(1.0 / 60.0)
		check(absf(float(ships[0].hull) - 0.55) < 0.005, "Hard: one 25% patch per ship (30% -> 55%)")
	else:
		check(false, "Hard repair Gunship present")

	print("V130_RESULT checks=%d failures=%d" % [checks, failures])
	# Stop sounds still playing (a wave-clear cue started just before quitting would
	# otherwise be reported as a leak at exit).
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await process_frame
	console.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
