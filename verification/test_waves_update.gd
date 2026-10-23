extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Waves & High Scores Test: readability (1600x900, F11, larger icons, outlined
## names, smoothing), arcade top-10 board, wave difficulty, spaced bonus
## repairs and the Siege Ship.
const HighScores = preload("res://scripts/HighScores.gd")
var console: Control
var c: Control
var checks := 0
var failures := 0
var score_path := "user://test_waves_high_scores.json"

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
func key(code: int, unicode: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.pressed = true
	console._input(event)
func remove_scores() -> void:
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(score_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(score_path + suffix))
	var folder := DirAccess.open("user://")
	for name in folder.get_files():
		if name.begins_with("test_waves_high_scores.json.unreadable"):
			folder.remove(name)
func game_over_with(points: int) -> void:
	c.score = points
	c.earned_points = points
	c.apply_damage(10000.0)
	console._process(0.016)
	# 1.0.8: the score screen comes in front 3 s after the ship is destroyed (SYSTEMS OFFLINE first).
	console.damage_effects.skip_to_score_screen()
	console._process(0.016)

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
	c.rng.seed = 2026
	clean()
	await process_frame

	# --- 1. Readability ---
	check(ProjectSettings.get_setting("display/window/size/window_width_override") == 1600 and ProjectSettings.get_setting("display/window/size/window_height_override") == 900, "Default window is 1600 x 900")
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1920 and ProjectSettings.get_setting("display/window/size/viewport_height") == 1080 and ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "1920 x 1080 layout kept and scaled to the window")
	check(DisplayServer.window_get_size() == Vector2i(1600, 900), "Window actually opens at 1600 x 900")
	check(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d")) == 0, "2D MSAA left off (Compatibility reports it unsupported); smoothing uses anti-aliased drawing")
	check(c.icon_size == 1.3, "Contact icons enlarged to 1.3")
	check(c.label_font_size >= 14 and c.label_font_size == 16, "Contact names use a 16 design-pixel font (minimum 14)")
	check(c.label_outline_size > 0 and c.label_outline_color.a > 0.5 and c.label_outline_color.v < 0.1, "Contact names have a thin dark outline")
	var label: Color = c.label_color(Color(c.hostile_color, 0.88))
	check(label.a == 1.0 and label.g > c.hostile_color.g and label.r >= c.hostile_color.r - 0.001, "Contact names are slightly brighter than their icons")
	check(c.label_color(Color(c.hostile_color, 0.2)).a < 0.3, "Flashing ships keep their dim phase in the name text")
	var dome: Control = console.get_node("CenterContainer/Dome")
	check(dome.ring_color == Color(0.3254902, 0.34117648, 1, 1) and dome.ring_thickness == 0.4 and dome.ring_glow_thickness == 5.0 and dome.ripple_color == Color(0.3254902, 0.6862745, 1, 1), "Ring settings unchanged (rings not brightened)")
	check(not console.is_fullscreen(), "Game starts in a window")
	key(KEY_F11)
	await process_frame
	check(console.is_fullscreen(), "F11 switches to full screen")
	key(KEY_F11)
	await process_frame
	check(not console.is_fullscreen(), "F11 again returns to the window")
	key(KEY_F11)
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(not console.is_fullscreen(), "Esc also leaves full screen")
	console.fullscreen_key_enabled = false
	key(KEY_F11)
	await process_frame
	check(not console.is_fullscreen(), "Full-screen key can be turned off in the Inspector")
	console.fullscreen_key_enabled = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	console.tuning_panel.visible = false
	console.development_build = true  # 1.04: off by default; ticked for tuning
	key(KEY_F1)
	check(console.tuning_panel.visible, "F1 tuning panel still opens in the test build")
	key(KEY_F1)

	# --- 2. Waves ---
	clean()
	check(c.wave == 1 and c.current_wave() == 1, "Battle starts at wave 1")
	check(c.wave_seconds == 120.0 and c.waves_enabled, "Wave rises every 2 minutes by default")
	var waves_seen: Array = []
	c.wave_changed.connect(func(n): waves_seen.append(n))
	c.battle_time = 119.9
	c._update_wave()
	check(c.wave == 1, "Still wave 1 just before two minutes")
	c._process(0.2)
	check(c.wave == 2 and waves_seen == [2] and c.status_message.begins_with("WAVE 2"), "Wave 2 begins at two minutes with a status message")
	check(c.seconds_to_next_wave() > 119.0 and c.seconds_to_next_wave() <= 120.0, "Sidebar countdown to next wave restarts")
	var caps := []
	var mults := []
	var heavies := []
	for n in [1, 2, 3, 4, 5, 9]:
		at_wave(n)
		caps.append(c.carrier_cap())
		mults.append("%.2f" % c.wave_interval_multiplier())
		heavies.append(c.breacher_cap())
	check(caps == [2, 2, 3, 3, 4, 4], "Enemy Carrier limit grows 2 -> 3 (wave 3) -> 4 (wave 5) and stops at 4")
	check(mults == ["1.00", "0.90", "0.80", "0.70", "0.60", "0.60"], "Launch intervals shorten 10% per wave down to 60%")
	check(heavies == [2, 2, 2, 3, 3, 3], "Third Breacher allowed from wave 4")
	check(c.max_contacts == 20, "Max contacts raised to 20 for later waves")
	clean()
	at_wave(5)
	var four: Array = []
	for i in range(5):
		var b := base()
		if not b.is_empty():
			four.append(b)
	print("FOUR_PROBE placed=", four.size(), " cap=", c.carrier_cap(), " tracks=", c.count_tracks(), " max=", c.max_contacts)
	check(four.size() == 4, "Wave 5 fields four Enemy Carriers, never a fifth")
	var apart := true
	var inside := true
	for i in range(four.size()):
		inside = inside and Vector2(four[i].position.x, four[i].position.y).length() < 0.95
		for j in range(i + 1, four.size()):
			for box_a in c._capital_boxes(four[i].position, "carrier"):
				for box_b in c._capital_boxes(four[j].position, "carrier"):
					apart = apart and not box_a.intersects(box_b)
	check(apart and inside, "Capital ships placed apart so names do not overlap, all inside the scope")
	clean()
	check(not base().is_empty() and not base().is_empty() and base().is_empty(), "Wave 1 still allows only two Enemy Carriers")
	clean()
	at_wave(5)
	var b5 := base()
	c.carrier_weapons_enabled = true
	b5.drone_timer = 0.0
	b5.missile_timer = 0.0
	c._update_carrier(b5, 0.0)
	check(b5.drone_timer >= 7.0 * 0.6 * 0.85 - 0.001 and b5.drone_timer <= 7.0 * 0.6 * 1.15 + 0.001, "Wave 5 Attack Drone launches come at 60% of the interval")
	check(b5.missile_timer >= 11.0 * 0.6 * 0.85 - 0.001 and b5.missile_timer <= 11.0 * 0.6 * 1.15 + 0.001, "Wave 5 missile launches come at 60% of the interval")
	clean()
	at_wave(4)
	c.breachers_enabled = true
	var bases := [base(), base(), base()]
	var parks: Array = []
	for b in bases:
		var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
		if not h.is_empty():
			parks.append(h.hack_point)
	check(parks.size() == 3 and parks[0] != parks[1] and parks[1] != parks[2] and parks[0] != parks[2], "Three Breachers get three separate parking spots")
	check(c.spawn_from_carrier("breacher", bases[0].id).is_empty(), "Breacher limit of three holds")
	c.jump_recharge_remaining = 0.0
	c.request_jump()
	check(c.wave == 4, "JUMP keeps the current wave")
	c.reset_battle()
	check(c.wave == 1 and c.battle_time == 0.0, "Retry returns to wave 1")

	# --- 3. Spaced-out bonus repairs ---
	clean()
	var thresholds := []
	for n in range(1, 7):
		thresholds.append(c.repair_bonus_threshold(n))
	check(thresholds == [10000, 25000, 50000, 100000, 150000, 200000], "Bonus repairs at 10k, 25k, 50k, then every 50k")
	check(c.repair_bonuses_for(9999) == 0 and c.repair_bonuses_for(10000) == 1 and c.repair_bonuses_for(24999) == 1 and c.repair_bonuses_for(25000) == 2 and c.repair_bonuses_for(99999) == 3 and c.repair_bonuses_for(100000) == 4, "Bonus count follows the spaced milestones")
	var charges := []
	for i in range(50):
		c._hit_carrier(base(), 100.0)
		if c.earned_points in [9000, 10000, 24000, 25000, 49000, 50000]:
			charges.append(c.repair_charges)
	check(charges == [1, 2, 2, 3, 3, 4], "Real kills award charges only at 10k, 25k and 50k")
	check(c.points_to_next_bonus() == 50000, "Sidebar shows 50,000 to the next bonus after 50,000")
	console._process(0.016)
	check(String(console.get_node("BottomButtons/RapidRepair").get_meta("hover_tip", "")).contains("25000"), "Repair help text explains the spaced milestones (1.06: kept, pop-up off by default)")

	# --- 4. Siege Ship ---
	clean()
	c.siege_enabled = true
	c.siege_spawn_chance = 1.0
	c.siege_check_remaining = 0.0
	c._update_siege_spawning(0.1)
	check(c.siege_ship().is_empty(), "No Siege Ship in wave 1")
	at_wave(2)
	c.siege_check_remaining = 0.05
	c._update_siege_spawning(0.1)
	var rs: Dictionary = c.siege_ship()
	check(not rs.is_empty() and rs.kind == "siege_ship" and rs.faction == "hostile", "Siege Ship can arrive from wave 2")
	check(c.spawn_siege_ship().is_empty() and c.count_kind("siege_ship") == 1, "Only one Siege Ship at a time")
	# Firewall & Combat update (approved): it now crosses the scope, so hit points dropped from 16 to 10.
	check(rs.hits_remaining == float(c.siege_hit_points) and c.siege_hit_points > c.carrier_hits_to_destroy, "Hard to kill: more hits than a Enemy Carrier's 6")
	var fresh: Control = load("res://scripts/RadarContacts.gd").new()
	check(is_equal_approx(fresh.siege_spawn_chance, 0.25) and fresh.siege_check_seconds == 20.0 and fresh.siege_first_wave == 2 and fresh.siege_points == 2500, "Rare by default: 25% chance every 20 s from wave 2, worth 2,500")
	fresh.free()
	check(c.size_for_kind("siege_ship") > c.size_for_kind("carrier"), "Drawn as a large capital icon")
	check(c.count_kind("carrier") == 0 and c.count_tracks() == 1, "Not counted as a Enemy Carrier, but counted as a track")
	var start: Vector3 = rs.position
	var missile_times: Array = []
	var t := 0.0
	var seen := {}
	while t < 30.0:
		c._update_siege(rs, 1.0 / 60.0)
		t += 1.0 / 60.0
		for m in c.contacts.duplicate():
			if m.kind == "missile" and not seen.has(m.id):
				seen[m.id] = true
				missile_times.append(t)
				if missile_times.size() < 12:
					c._remove_contact(m.id)
	# Firewall & Combat update (approved): it moves, and barrages are 3 timed missiles 1 s apart,
	# every 8 s shortened by the wave (7.2 s in wave 2), first after 3 s.
	check(rs.position != start and absf(rs.position.y - start.y) < 0.001, "Siege Ship now moves across the scope")
	check(missile_times.size() == 12, "Four barrages of three missiles in 30 s")
	var gap_ok := missile_times.size() == 12
	if gap_ok:
		for i in range(12):
			if i % 3 != 0:
				gap_ok = gap_ok and absf(missile_times[i] - missile_times[i - 1] - 1.0) < 0.03
		gap_ok = gap_ok and absf(missile_times[0] - 3.0) < 0.03 and absf(missile_times[3] - missile_times[0] - 7.2) < 0.03
	check(gap_ok, "Barrage: first after 3 s, missiles 1 s apart, every 7.2 s in wave 2")
	check(c.missile_cap() == c.max_missiles + c.siege_barrage_missiles and c.count_kind("missile") <= c.missile_cap(), "Barrage may add its missiles above the normal missile limit")
	var bm: Dictionary = {}
	for m in c.contacts:
		if m.kind == "missile" and m.origin_id == rs.id:
			bm = m
	check(not bm.is_empty() and bm.start.distance_to(bm.origin_position) <= c.carrier_emission_radius + 0.001, "Barrage missiles leave from the Siege Ship")
	check(c.spawn_from_carrier("drone", rs.id).is_empty() and c.spawn_from_carrier("breacher", rs.id).is_empty(), "Siege Ship launches missiles only")
	bm.position = c.own_ship_position + Vector3(0.0, 0.1, 0.0)  # 1.04: kill zone at the flak arc
	c.prox_success_chance = 0.95
	c.prox_burst_remaining = c.prox_burst_seconds
	c.set_prox_defense(true)
	var hits_before: float = rs.hits_remaining
	rs.position = c.own_ship_position + Vector3(0.0, 0.1, 0.0)
	for i in range(20):
		c.battle_time += 0.3
		c._resolve_missiles()
	check(c.find_contact(bm.id).is_empty() and c.prox_kills > 0, "Defense Shield can shoot down barrage missiles")
	check(rs.hits_remaining == hits_before, "Defense Shield never damages the Siege Ship")
	c.set_prox_defense(false)
	c.prox_success_chance = 0.45
	rs.position = start
	# Barrages continue until destroyed
	var before_barrages: int = c.siege_barrages
	for i in range(60 * 30):
		c._update_siege(rs, 1.0 / 60.0)
	check(c.siege_barrages >= before_barrages + 2, "Barrages keep coming until it is destroyed")
	# Ship missiles alternate with Enemy Carriers
	for m in c.contacts.duplicate():
		if m.kind == "missile":
			c._remove_contact(m.id)
	var sb := base()
	c.own_weapons_enabled = true
	var targets: Array = []
	for i in range(4):
		c.own_fire_remaining = 0.0
		c._update_own_weapons(0.0)
		targets.append(c.contacts.back().target_id)
	check(targets == [sb.id, rs.id, sb.id, rs.id], "With a Enemy Carrier present, every second ship missile goes to the Siege Ship")
	c._hit_carrier(sb, 100.0)
	for m in c.contacts.duplicate():
		if m.kind == "own_missile":
			c._remove_contact(m.id)
	c.own_fire_remaining = 0.0
	c._update_own_weapons(0.0)
	var shot: Dictionary = c.contacts.back()
	check(shot.kind == "own_missile" and shot.target_id == rs.id, "With no Enemy Carrier, every ship missile goes to it")
	shot.position = rs.position + Vector3(0.0, -0.02, 0.0)
	c._update_own_weapons(0.0)
	check(rs.hits_remaining == float(c.siege_hit_points) - 1.0 and c.siege_hits_by.ship == 1, "Ship missile hit removes one hit point")
	c.own_weapons_enabled = false
	# Interceptors: attack only the Siege Ship among capitals, at a per-Interceptor interval
	clean()
	at_wave(3)
	var lone := base()
	var v: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.phase = "intercept"
	v.position = Vector3(0.0, -0.2, 0.0)
	c._update_interceptors(1.0 / 60.0)
	check(v.target_id == "", "Interceptors still never attack Enemy Carriers")
	c.siege_enabled = true
	rs = c.find_contact(c.spawn_siege_ship())
	v.position = rs.position + Vector3(0.0, -0.03, 0.0)
	v.velocity = Vector3.ZERO
	var interceptor_hits := 0
	for i in range(int(60 * 4.1)):
		v.position = rs.position + Vector3(0.0, -0.03, 0.0)
		c._update_interceptors(1.0 / 60.0)
		interceptor_hits = c.siege_hits_by.interceptor
	check(v.target_id == rs.id and interceptor_hits == 3, "Interceptors attack the Siege Ship, one hit per 2 s each")
	check(is_equal_approx(rs.hits_remaining, float(c.siege_hit_points) - 3 * 0.5), "Each Interceptor hit does half a ship-missile hit")
	var r: Dictionary = c.find_contact(c.spawn_from_carrier("drone", lone.id))
	r.position = Vector3(0.0, -0.1, 0.05)
	r.phase = "harass"
	# 1.08: one Interceptor is assigned to the Siege Ship and stays on it; with the
	# assignment off (0) the earlier rule applies and Attack Drones come first.
	c._update_interceptors(1.0 / 60.0)
	check(v.target_id == rs.id, "1.08: the one assigned Interceptor stays on the Siege Ship")
	c.interceptors_on_siege_ship = 0
	c._update_interceptors(1.0 / 60.0)
	check(v.target_id == r.id, "Interceptors still deal with Attack Drones first")
	c.interceptors_on_siege_ship = 1
	c._remove_contact(r.id)
	# Gunships prefer the Siege Ship over Enemy Carriers and can destroy it
	var rp: Dictionary = c.find_contact(c._spawn_gunship())
	rp.phase = "patrol"
	rp.position = (rs.position + lone.position) * 0.5 + Vector3(0.0, -0.3, 0.0)
	var none: Array[String] = []
	var choice: Dictionary = c._gunship_target(rp, none)
	check(choice.id == rs.id, "Gunships choose the Siege Ship over a Enemy Carrier")
	rp.position = rs.position + rs.position.direction_to(c.own_ship_position) * 0.38
	rp.fire_timer = 0.0
	c._update_gunships(1.0 / 60.0)
	var rm: Dictionary = {}
	for m in c.contacts:
		if m.kind == "gunship_missile":
			rm = m
	check(not rm.is_empty() and rm.target_id == rs.id, "Gunship fires light missiles at it")
	rm.position = rs.position
	c._update_own_weapons(0.0)
	check(is_equal_approx(rs.hits_remaining, float(c.siege_hit_points) - 1.5 - 0.5) and c.siege_hits_by.gunship == 1, "Gunship missile does half damage")
	# Destruction by any mix; points once
	var score_before: int = c.score
	var arrivals: Array = []
	c.siege_destroyed.connect(func(id): arrivals.append(id))
	while not c.find_contact(rs.id).is_empty():
		c._hit_siege(rs, 1.0, "ship")
	c._hit_siege(rs, 1.0, "ship")
	check(c.score == score_before + 2500 and arrivals.size() == 1 and c.sieges_destroyed == 1, "Destroying it scores 2,500 points exactly once")
	check(c.status_message.begins_with("SIEGE SHIP DESTROYED"), "Destruction status message")
	check(c.siege_cooldown_remaining == c.siege_cooldown_now() and c.siege_cooldown_now() <= 90.0, "Quiet period starts after destruction")
	c.siege_spawn_chance = 1.0
	c.siege_check_remaining = 0.0
	c._update_siege_spawning(1.0)
	check(c.siege_ship().is_empty(), "No new Siege Ship during the quiet period")
	for i in range(100):
		c._update_siege_spawning(1.0)
	check(not c.siege_ship().is_empty(), "Another may arrive after the quiet period")
	# Alert sound: distinct, deeper copy of the approved alert; never overlaps
	clean()
	at_wave(2)
	c.klaxon_enabled = true
	c.siege_enabled = true
	rs = c.find_contact(c.spawn_siege_ship())
	check(c.siege_alert_player.playing and c.siege_alert_count == 1, "Arrival plays the Siege Ship alert")
	print("ALERT_PROBE pitch=", c.siege_alert_player.pitch_scale, " bytes=", c.siege_alert_player.stream.data.size())
	check(is_equal_approx(c.siege_alert_player.pitch_scale, 0.8) and c.siege_alert_player.stream.data.size() == 134400 * 2, "Alert is the approved alert twice at 0.8x (deeper, distinct)")
	var b2 := base()
	check(not c.klaxon_player.playing, "Identification klaxon waits while the Siege alert plays")
	c.nuclear_weapons_enabled = true
	c._launch_nuclear(b2)
	c._update_nuclear_alarm(0.016)
	c._update_siege_alert()
	check(c.nuclear_player.playing and not c.siege_alert_player.playing, "Nuclear warning takes priority over the Siege alert")
	c.queue_redraw()
	await RenderingServer.frame_post_draw
	c.jump_recharge_remaining = 0.0
	c.request_jump()
	check(c.siege_ship().is_empty() and not c.siege_alert_player.playing and c.siege_cooldown_remaining == c.siege_cooldown_now(), "JUMP leaves the Siege Ship behind (quiet period before another)")
	c.reset_battle()
	check(c.siege_spawns == 0 and c.siege_cooldown_remaining == 0.0 and c.wave == 1, "Retry resets Siege Ship state")

	# --- 5. High score board ---
	remove_scores()
	console.high_score_file = score_path
	check(HighScores.clean_initials("s r9g") == "SRG" and HighScores.clean_initials("ab") == "ABA" and HighScores.clean_initials("") == "AAA", "Initials are three upper-case letters")
	var table: Array = []
	check(not HighScores.qualifies(table, 0) and HighScores.qualifies(table, 100), "Zero never ranks; any score ranks on an empty board")
	for i in range(12):
		HighScores.insert(table, "AAA", 1000 * (i + 1), 1)
	check(table.size() == 10 and table[0].score == 12000 and table[9].score == 3000, "Board keeps the top 10, highest first")
	check(not HighScores.qualifies(table, 3000) and HighScores.qualifies(table, 3001), "Must beat the 10th score to enter a full board")
	var row := HighScores.insert(table, "TIE", 8000, 2)
	check(row == 5 and table[4].initials == "AAA" and table[5].initials == "TIE", "Equal score ranks below the earlier holder")
	clean()
	c.auto_spawn = false
	game_over_with(4200)
	var panel: Panel = console.get_node("CenterContainer/Dome/GameOverPanel")
	check(panel.visible and console.entry_active and panel.get_node("Entry").visible, "Game Over with a new high score asks for initials")
	check(panel.get_node("EntryPrompt").text.contains("ENTER YOUR INITIALS"), "Prompt explains initials entry")
	check(panel.get_node("Entry/Up0").icon != null and panel.get_node("Entry/Down0").icon != null, "Arrow buttons have drawn arrow icons")
	check(console.entry_initials() == "AAA", "First entry starts at AAA")
	panel.get_node("Entry/Down0").pressed.emit()
	check(console.entry_initials() == "ZAA", "Mouse down-arrow wraps A to Z")
	panel.get_node("Entry/Up0").pressed.emit()
	panel.get_node("Entry/Up0").pressed.emit()
	check(console.entry_initials() == "BAA", "Mouse up-arrow steps to the next letter")
	console.entry_slot = 0
	key(KEY_S, 115)
	key(KEY_R, 82)
	key(KEY_9, 57)
	key(KEY_G, 103)
	check(console.entry_initials() == "SRG", "Typed letters fill the initials (lower case becomes upper; digits ignored)")
	key(KEY_UP)
	check(console.entry_initials() == "SRH", "Up arrow key changes the current letter")
	key(KEY_DOWN)
	key(KEY_LEFT)
	key(KEY_LEFT)
	key(KEY_UP)
	key(KEY_DOWN)
	check(console.entry_initials() == "SRG" and console.entry_slot == 0, "Left arrow moves between letters")
	key(KEY_ENTER)
	check(not console.entry_active and console.highlight_row == 0 and not panel.get_node("Entry").visible, "ENTER saves the score")
	check(panel.get_node("EntryPrompt").text == "SAVED  |  RANK 1", "Saved rank is shown")
	check(FileAccess.file_exists(score_path) and not FileAccess.file_exists(score_path + ".tmp"), "Board saved to the user data folder without leftover temporary file")
	var loaded := HighScores.load_board(score_path)
	check(loaded.scores.size() == 1 and loaded.scores[0].initials == "SRG" and loaded.scores[0].score == 4200 and loaded.last_initials == "SRG", "Saved board reloads with initials and score")
	var rows: Array = console.score_rows
	check(rows.size() == 10 and rows[0][0].text == "1." and rows[0][1].text == "SRG" and rows[0][2].text == "4200" and rows[1][1].text == "---", "Board shows rank, initials and score for all 10 places")
	panel.get_node("Retry").pressed.emit()
	console._process(0.016)
	check(not panel.visible and c.hull == c.max_hull and c.score == 0, "Retry still restarts the battle")
	# Retry before ENTER keeps the score under the initials shown (never lost)
	game_over_with(3100)
	check(console.entry_active and console.entry_initials() == "SRG", "Next entry starts from the last initials used")
	panel.get_node("Retry").pressed.emit()
	console._process(0.016)
	loaded = HighScores.load_board(score_path)
	check(loaded.scores.size() == 2 and loaded.scores[1].score == 3100 and loaded.scores[1].initials == "SRG", "Retry before ENTER still records the score")
	# Persists to a new console instance (like restarting the game)
	var second: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	second.high_score_file = score_path
	root.add_child(second)
	second.set_process(false)
	second.get_node("SweepLoop").stop()
	var sc: Control = second.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: sc.set(_k130, V130_OFF[_k130])
	sc.set_process(false)
	sc.klaxon_enabled = false
	sc.score = 50
	sc.apply_damage(10000.0)
	second._process(0.016)
	check(second.board.scores.size() == 2 and second.score_rows[0][1].text == "SRG" and second.entry_active, "Scores persist after restarting the game")
	for p in second.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	second.queue_free()
	# Full board, low score: no entry
	for i in range(10):
		HighScores.insert(loaded.scores, "ACE", 90000 - i, 5)
	HighScores.save_board(score_path, loaded.scores, "SRG")
	c.reset_battle()
	console._process(0.016)
	game_over_with(500)
	check(not console.entry_active and not panel.get_node("Entry").visible and panel.get_node("EntryPrompt").text.contains("DID NOT REACH"), "Score below the top 10 shows the board without entry")
	c.reset_battle()
	console._process(0.016)
	game_over_with(0)
	check(not console.entry_active, "Zero score never asks for initials")
	c.reset_battle()
	console._process(0.016)
	# Unreadable file is backed up, never silently discarded
	var bad := FileAccess.open(score_path, FileAccess.WRITE)
	bad.store_string("not json {")
	bad.close()
	game_over_with(700)
	var backups := 0
	for name in DirAccess.open("user://").get_files():
		if name.begins_with("test_waves_high_scores.json.unreadable"):
			backups += 1
	check(backups == 1 and console.entry_active, "Unreadable board file is backed up and a fresh board starts")
	key(KEY_ENTER)
	check(HighScores.load_board(score_path).scores.size() == 1, "Fresh board saves normally after recovery")
	c.reset_battle()
	console._process(0.016)
	remove_scores()

	# --- 6. Development Build switch still works ---
	console.development_build = false
	console.tuning_panel.visible = false
	key(KEY_F1)
	check(not console.tuning_panel.visible, "Final-build switch still disables F1")
	console.development_build = true
	check(console.sweep_volume_db == -20.0, "RADAR sweep stays at -20 dB")

	# --- 7. Fifteen-minute wave simulation (hull topped up so later waves are reached) ---
	# 1.2.0: this covers the classic timer waves (Defined Waves off); defined waves
	# have their own fifteen-minute run in test_v120_waves_run.
	clean()
	c.defined_waves = false
	c.auto_spawn = true
	c.carrier_weapons_enabled = true
	c.own_weapons_enabled = true
	c.breachers_enabled = true
	c.nuclear_weapons_enabled = true
	c.siege_enabled = true
	c.max_contacts = 20
	c.reset_battle()
	var caps_ok := true
	var max_capitals := 0
	var max_heavy := 0
	var res_seen_wave := 0
	var res_early := false
	for frame in range(60 * 900):
		c._process(1.0 / 60.0)
		if frame % 300 == 0:
			c.launch_interceptors()
			c.launch_gunship()
		if frame % 240 == 0:
			c.set_prox_defense(true)
		if c.hull < 30.0:
			c.hull = c.max_hull
		var capitals: int = c.count_kind("carrier") + c.count_kind("unknown")
		max_capitals = maxi(max_capitals, capitals)
		max_heavy = maxi(max_heavy, c.count_kind("breacher"))
		caps_ok = caps_ok and capitals <= c.carrier_cap() and c.count_kind("breacher") <= c.breacher_cap()
		caps_ok = caps_ok and c.count_kind("missile") <= c.missile_cap() and c.count_tracks() <= c.max_contacts and c.count_kind("siege_ship") <= 1
		if c.count_kind("siege_ship") > 0:
			res_early = res_early or c.wave < 2
			if res_seen_wave == 0:
				res_seen_wave = c.wave
	check(caps_ok, "Fifteen-minute run: wave limits, missile, track and one-Siege limits hold")
	check(c.wave == 8 and max_capitals >= 3, "Later waves reached and field more capital ships")
	check(c.siege_spawns >= 1 and not res_early, "Siege Ship appears, never before wave 2")
	print("WAVE_SIMULATION seconds=900 final_wave=", c.wave, " max_capitals=", max_capitals, " max_heavy=", max_heavy,
		" siege_spawns=", c.siege_spawns, " first_res_wave=", res_seen_wave, " sieges_destroyed=", c.sieges_destroyed,
		" barrages=", c.siege_barrages, " res_hits=", c.siege_hits_by, " carriers_destroyed=", c.carriers_destroyed, " earned=", c.earned_points, " bonus_charges=", c.repair_bonuses_earned)
	# Unassisted difficulty probe: no hull top-up, simple player habits.
	clean()
	c.defined_waves = true
	c.auto_spawn = true
	c.carrier_weapons_enabled = true
	c.own_weapons_enabled = true
	c.breachers_enabled = true
	c.nuclear_weapons_enabled = true
	c.siege_enabled = true
	c.reset_battle()
	var survived := 0.0
	for frame in range(60 * 1200):
		c._process(1.0 / 60.0)
		if frame % 300 == 0:
			c.launch_interceptors()
			c.launch_gunship()
		if frame % 240 == 0:
			c.set_prox_defense(true)
		if c.hull < 60.0:
			c.request_rapid_repair()
		if c.hull < 25.0 and c.can_jump():
			c.request_jump()
		if c.is_defeated():
			break
		survived = c.battle_time
	print("DIFFICULTY_PROBE survived_seconds=", int(survived), " wave=", c.wave, " score=", c.score, " siege_spawns=", c.siege_spawns, " defeated=", c.is_defeated())
	check(survived > 120.0, "Unassisted probe survives past wave 1")

	print("WAVES_UPDATE_RESULT checks=", checks, " failures=", failures)
	for p in console.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	await create_timer(0.3).timeout
	console.queue_free()
	console = null
	c = null
	await process_frame
	quit(0 if failures == 0 else 1)
