extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.2.8: the startup splash screen, the Defense Shield
## shooting down nukes (one chance per nuke, splash damage, full nuke points, auto
## battery for nukes), the slower hack drain and the shorter Protect the fleet
## result line.
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

func fresh(c: Control, level: int) -> void:
	c.difficulty = level
	c.auto_defense_battery = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.auto_firewall = false
	c.auto_jump = false
	c.auto_rapid_repair = false
	c.reset_battle()
	c.pending.clear()
	c.contacts.clear()

func base(c: Control) -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	b.drone_timer = 99.0
	b.missile_timer = 99.0
	b.heavy_timer = 99.0
	b.flak_timer = 99.0
	b.nuclear_timer = 99.0
	return b

## A nuke launched by a Enemy Carrier, then placed at the given distance from the ship.
## The Enemy Carrier is removed so only the nuke is in play.
func nuke_at(c: Control, distance: float) -> Dictionary:
	var b := base(c)
	var id: String = c._launch_nuclear(b)
	var n: Dictionary = c.find_contact(id)
	var dir: Vector3 = c.own_ship_position.direction_to(b.position)
	c.contacts.erase(b)
	n.position = c.own_ship_position + dir * distance
	return n

## Runs only the nuke movement until the nuke is gone (shot down or impact).
func fly(c: Control, n: Dictionary, seconds: float = 30.0) -> void:
	var t := 0.0
	while t < seconds and not c.find_contact(n.id).is_empty() and not c.is_defeated():
		c._update_special_projectiles(1.0 / 30.0)
		t += 1.0 / 30.0

func start_protect(c: Control, level: int, seed_value: int = 7) -> void:
	fresh(c, level)
	c.rng.seed = seed_value
	c.wave = 5
	c.sets_completed = 1
	c.wave_phase = "rest"
	c.wave_next_phase = "protect"
	c.safe_remaining = 0.0
	c._start_protect()

func civilians(c: Control) -> Array:
	var list: Array = []
	for x in c.contacts:
		if x.get("faction", "") == "civilian":
			list.append(x)
	return list

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://v128_scores.json"
	console.settings_file = "user://v128_settings.cfg"
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	c.auto_spawn = false
	root.add_child(console)
	c.set_process(false)
	for i in range(4):
		await process_frame
	c.waves_enabled = false
	c.klaxon_enabled = false
	c.ship_missiles_target_nukes = false

	# ---------------- Version ----------------
	check(ProjectSettings.get_setting("application/config/version") == "1.1.0", "Project version is 0.1.2")
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.0", "Version text reads STELLAR DEFENSE CONSOLE 1.1.0")
	var presets := ConfigFile.new()
	check(presets.load("res://export_presets.cfg") == OK, "Export presets load")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.0_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.0_Mac.zip")
		and presets.get_value("preset.1.options", "application/version", "") == "1.1.0"
		and presets.get_value("preset.1.options", "application/short_version", "") == "1.1.0", "Export presets name 0.1.2 files")

	# ---------------- Splash screen ----------------
	var splash_path := "res://assets/splash/stellar_defense_console_splash.png"
	check(ProjectSettings.get_setting("application/boot_splash/show_image", false) == true, "Boot splash shows an image")
	check(ProjectSettings.get_setting("application/boot_splash/image", "") == splash_path, "Boot splash image is %s" % splash_path)
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.WHITE)
	check(bg.is_equal_approx(Color(0, 0, 0, 1)), "Boot splash background is black (%s)" % bg)
	check(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time", 0)) == 4000, "Splash stays up at least 4,000 ms")
	check(ProjectSettings.get_setting("application/boot_splash/use_filter", false) == true, "Splash is drawn with smooth filtering")
	if ProjectSettings.has_setting("application/boot_splash/fit_image"):
		check(ProjectSettings.get_setting("application/boot_splash/fit_image") == true, "Splash fits the window, keeping its shape (Godot 4.4 setting)")
	else:
		check(int(ProjectSettings.get_setting("application/boot_splash/stretch_mode", 1)) == 1, "Splash keeps its shape when stretched")
	check(FileAccess.file_exists(splash_path), "Splash image file is in the project")
	var splash_tex: Texture2D = load(splash_path)
	check(splash_tex != null and splash_tex.get_width() == 1920 and splash_tex.get_height() == 1080, "Splash image is 1920 x 1080")
	var raw := FileAccess.get_file_as_bytes(splash_path)
	check(raw.size() > 8 and raw[0] == 0x89 and raw[1] == 0x50 and raw[2] == 0x4E and raw[3] == 0x47, "Splash image is a PNG (the only format Godot accepts)")
	var splash_img := Image.new()
	check(splash_img.load_png_from_buffer(raw) == OK, "Splash PNG decodes")
	# The approved patch is centered on black, with the game title underneath.
	var corner := splash_img.get_pixel(4, 4)
	check(corner.get_luminance() < 0.25, "Splash corner is dark (star field), not the Godot grey")
	var bright_bottom := 0
	for x in range(400, 1520, 2):
		for y in range(850, 950, 2):
			if splash_img.get_pixel(x, y).get_luminance() > 0.4:
				bright_bottom += 1
	check(bright_bottom > 200, "Game title is present at the bottom (%d bright samples)" % bright_bottom)
	for idx in [0, 1]:
		var excl := String(presets.get_value("preset.%d" % idx, "exclude_filter", ""))
		check(not excl.contains("assets") and not excl.contains("png") and presets.get_value("preset.%d" % idx, "export_filter", "") == "all_resources", "Preset %d exports the splash image (filter %s)" % [idx, excl])

	# ---------------- Defaults ----------------
	check(is_equal_approx(c.battery_nuke_chance, 0.35), "Battery Nuke Chance defaults to 0.35")
	check(is_equal_approx(c.battery_nuke_splash, 0.33), "Battery Nuke Splash defaults to 0.33")
	check(c.auto_battery_for_nukes, "Auto Shield For Nukes defaults to on")
	check(is_equal_approx(c.hack_drain_percent_per_second, 1.5), "Hack Drain Percent Per Second defaults to 1.5 (was 2.0)")
	check(is_equal_approx(c.prox_defense_radius, 0.12) and is_equal_approx(c.auto_battery_lead_radius, 0.22), "Kill zone 0.12 and auto lead 0.22 unchanged")
	check(is_equal_approx(c.nuclear_damage, 60.0) and c.nuclear_points == 500, "Nuclear damage 60 and nuke points 500 unchanged")

	# ---------------- Battery shoots down a nuke: splash, points, counts ----------------
	for level in [0, 1, 2]:
		fresh(c, level)
		c.battery_nuke_chance = 1.0
		var n := nuke_at(c, 0.2)
		c.set_prox_defense(true)
		check(c.prox_active, "L%d setup: battery firing" % level)
		var hull_before: float = c.hull
		var score_before: int = c.score
		var want_points: int = c.points_for(500)
		fly(c, n)
		var lost: float = hull_before - c.hull
		var want_splash: float = 60.0 * c.damage_factor() * 0.33
		print("V128_SPLASH level=%d lost=%.2f want=%.2f points=%d" % [level, lost, want_splash, c.score - score_before])
		check(c.find_contact(n.id).is_empty() and c.nuclear_hits == 0, "L%d: the nuke is destroyed before it hits" % level)
		check(absf(lost - want_splash) < 0.01, "L%d: splash damage is one third of a hit (%.2f of %.0f)" % [level, lost, 60.0 * c.damage_factor()])
		check(lost < 60.0 * c.damage_factor() * 0.5, "L%d: splash is well under a direct hit" % level)
		check(c.score - score_before == want_points, "L%d: full nuke points (%d)" % [level, want_points])
		check(c.battery_nuke_kills == 1 and c.battery_nuke_misses == 0 and c.nuclear_intercepts == 1 and int(c.kills.get("nuke", 0)) == 1, "L%d: counted as a battery kill, a nuke intercept and a nuke destroyed" % level)
		check(c.status_message == "DEFENSE SHIELD: NUKE DESTROYED | SPLASH DAMAGE", "L%d: status reads DEFENSE SHIELD: NUKE DESTROYED | SPLASH DAMAGE" % level)
		check(absf(c.battery_splash_damage - want_splash) < 0.01, "L%d: splash damage is tallied" % level)
	check(absf(60.0 * 0.75 * 0.33 - 14.85) < 0.01 and absf(60.0 * 1.25 * 0.33 - 24.75) < 0.01, "Splash about 15 / 20 / 25 hull on Easy / Normal / Hard")

	# Shot down only inside the kill zone
	fresh(c, 1)
	c.battery_nuke_chance = 1.0
	var far := nuke_at(c, 0.3)
	c.set_prox_defense(true)
	var min_seen := 1.0
	var t_far := 0.0
	while not c.find_contact(far.id).is_empty() and t_far < 30.0:
		min_seen = minf(min_seen, far.position.distance_to(c.own_ship_position))
		c._update_special_projectiles(1.0 / 30.0)
		t_far += 1.0 / 30.0
	check(c.battery_nuke_kills == 1 and min_seen <= 0.12 + 0.01 and min_seen > 0.12 - 0.02, "Shot down as it enters the 0.12 kill zone (closest %.3f)" % min_seen)

	# ---------------- A failed chance: the nuke hits and is not rolled again ----------------
	fresh(c, 1)
	c.battery_nuke_chance = 0.0
	var miss := nuke_at(c, 0.15)
	c.set_prox_defense(true)
	for i in range(30):
		c._update_special_projectiles(1.0 / 30.0)
	check(miss.get("battery_rolled", false) and c.battery_nuke_misses == 1 and c.battery_nuke_kills == 0, "A nuke in the zone gets its one chance (missed)")
	c.battery_nuke_chance = 1.0
	var hull_m: float = c.hull
	fly(c, miss)
	check(c.nuclear_hits == 1 and c.battery_nuke_kills == 0 and absf(hull_m - c.hull - 60.0) < 0.01, "After a miss the battery does not get a second chance; the hit does the full 60")

	# ---------------- No chance while the battery is not firing ----------------
	fresh(c, 1)
	c.battery_nuke_chance = 1.0
	var idle := nuke_at(c, 0.15)
	check(not c.prox_active, "Setup: battery not firing")
	fly(c, idle)
	check(c.nuclear_hits == 1 and c.battery_nuke_kills == 0 and c.battery_nuke_misses == 0, "Without the battery firing, the nuke is not shot down")

	# The battery started late, while the nuke is already inside the zone, still gets its chance
	fresh(c, 1)
	c.battery_nuke_chance = 1.0
	var late := nuke_at(c, 0.08)
	c._update_special_projectiles(1.0 / 30.0)
	c.set_prox_defense(true)
	fly(c, late)
	check(c.battery_nuke_kills == 1 and c.nuclear_hits == 0, "Firing while a nuke is already inside the zone still gives it its chance")

	# ---------------- One chance per nuke: about 1 in 3 ----------------
	fresh(c, 1)
	c.battery_nuke_chance = 0.35
	c.rng.seed = 128
	var kills := 0
	var trials := 400
	for i in range(trials):
		var nk := {"id": "NT%d" % i, "kind": "nuke", "faction": "hostile", "position": c.own_ship_position + Vector3(0.1, 0.0, 0.0), "age": 0.0}
		c.contacts.append(nk)
		c.prox_active = true
		c.hull = c.max_hull
		if c._battery_try_nuke(nk):
			kills += 1
		c.contacts.erase(nk)
		c.scored_contacts.clear()
	var rate := float(kills) / trials
	print("V128_RATE kills=%d of %d rate=%.3f" % [kills, trials, rate])
	check(rate > 0.28 and rate < 0.42, "About 1 nuke in 3 is shot down over 400 nukes (%.0f%%)" % (rate * 100.0))
	c.prox_active = false

	check(is_equal_approx(c.battery_nuke_chance, 0.35), "Chance restored for the remaining checks")

	# ---------------- Splash damage can end the battle cleanly ----------------
	fresh(c, 2)
	c.battery_nuke_chance = 1.0
	var last := nuke_at(c, 0.13)
	c.set_prox_defense(true)
	c.hull = 10.0
	fly(c, last)
	check(c.is_defeated() and c.battery_nuke_kills == 1, "Splash damage at low hull ends the battle without error")
	c.battery_nuke_chance = 0.35

	# ---------------- Auto Defense Shield fires for nukes ----------------
	fresh(c, 1)
	c.auto_defense_battery = true
	var auto_n := nuke_at(c, 0.21)
	c._update_automation()
	check(c.prox_active and c.auto_battery_started, "Auto shield starts for a nuke 0.21 away (no missiles)")
	check(c.nukes_for_battery(0.22) == 1 and c.missiles_in_defense_zone(0.22) == 0, "The nuke counts as a battery threat; the missile count is unchanged")
	fresh(c, 1)
	c.auto_defense_battery = true
	nuke_at(c, 0.3)
	c._update_automation()
	check(not c.prox_active, "Auto shield waits while the nuke is farther than 0.22")
	fresh(c, 1)
	c.auto_defense_battery = true
	c.auto_battery_for_nukes = false
	nuke_at(c, 0.21)
	c._update_automation()
	check(not c.prox_active, "Auto Shield For Nukes off: the auto shield ignores nukes, as in 1.2.7")
	c.auto_battery_for_nukes = true
	fresh(c, 1)
	c.auto_defense_battery = true
	var rolled := nuke_at(c, 0.1)
	rolled.battery_rolled = true
	c._update_automation()
	check(not c.prox_active, "A nuke that already had its chance does not start the auto shield")
	c.auto_defense_battery = false

	# ---------------- Slower hack drain ----------------
	for level in [0, 1, 2]:
		fresh(c, level)
		var b := base(c)
		var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
		h.position = h.hack_point
		c._update_breachers(0.0)
		check(h.phase == "hacking", "L%d setup: Breacher hacking" % level)
		h.phase = "draining"
		h.hack_remaining = 0.0
		var hb: float = c.hull
		c._update_breachers(2.0)
		var drained: float = hb - c.hull
		var want: float = c.max_hull * 1.5 * c.hack_speed() * 0.01 * 2.0
		print("V128_DRAIN level=%d drained=%.3f want=%.3f speed=%.2f" % [level, drained, want, c.hack_speed()])
		check(absf(drained - want) < 0.01, "L%d: 2 s of drain removes %.2f hull (1.5%% a second x hack speed %.2f)" % [level, want, c.hack_speed()])
		if level == 1:
			check(absf(drained - 3.0) < 0.01, "Normal drains 3 hull in 2 s (was 4)")
			check(c.hacking_warning().contains("HULL DRAIN 1.5%"), "Breach alert shows HULL DRAIN 1.5%")
	check(is_equal_approx(c.hacking_seconds, 6.0) and is_equal_approx(c.easy_hack_speed, 0.7) and is_equal_approx(c.hard_hack_speed, 1.3), "Hacking Seconds and the Easy/Hard hack speeds unchanged")

	# ---------------- Shorter Protect the fleet result line ----------------
	c.waves_enabled = true
	c.defined_waves = true
	c.auto_spawn = true
	c.wave_cues_enabled = false
	for outcome in ["saved", "partial", "lost"]:
		start_protect(c, 1, 5)
		var civs := civilians(c)
		var total: int = c.protect_civilians_total
		if outcome == "partial":
			c.contacts.erase(civs[0])
		elif outcome == "lost":
			for x in civs:
				c.contacts.erase(x)
		c.protect_drones_spawned = c.protect_drones_total
		c.protect_drones_destroyed = c.protect_drones_total
		c._end_protect("drones destroyed" if outcome != "lost" else "all lost")
		var lines: Array[String] = c.rest_tally_lines()
		print("V128_RESULT %s lines=%s" % [outcome, lines])
		var want_title: String = {"saved": "SUPPORT FLEET SAVED", "partial": "%d OF %d SHIPS SAVED" % [total - 1, total], "lost": "SUPPORT FLEET LOST"}[outcome]
		var want_line := "SUPPORT HULL %d%%  |  ATTACK DRONES DOWN %d OF %d" % [c.protect_hull_kept, c.protect_drones_destroyed, c.protect_drones_spawned]
		check(lines[0] == want_title, "%s: title %s unchanged" % [outcome, want_title])
		check(lines[1] == want_line, "%s: detail line reads %s" % [outcome, want_line])
		check(not lines[1].contains("SAVED"), "%s: the ship count is not repeated" % outcome)
	c.waves_enabled = false

	print("V128_RESULT checks=%d failures=%d" % [checks, failures])
	for p in console.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	console.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
