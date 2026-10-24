extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.2.7: inbound threat list in the alert box, the score
## multiplier on its own line, the wider status box with a fit-to-width safety net,
## the Protect the fleet result (sounds, large flashing bonus, longer hold), JUMP always
## held in the round, Auto Launch Interceptors in the round, new nuke speeds and faster
## Attack Drones and Breachers on Hard.
const ScopeShape = preload("res://scripts/ScopeShape.gd")
const BattleAudio = preload("res://scripts/BattleAudio.gd")
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
	c.auto_firewall = false
	c.auto_jump = false
	c.auto_rapid_repair = false
	c.reset_battle()
	c.pending.clear()
	c.contacts.clear()

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

func step(c: Control, seconds: float) -> void:
	for i in range(int(seconds * 30.0)):
		c._process(1.0 / 30.0)

func peak(stream: AudioStreamWAV) -> float:
	var best := 0
	for i in range(0, stream.data.size(), 2):
		best = maxi(best, absi(stream.data.decode_s16(i)))
	return best / 32767.0

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://v127_scores.json"
	console.settings_file = "user://v127_settings.cfg"
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	var frame: Control = console.get_node("ConsoleFrame")
	c.auto_spawn = false
	root.add_child(console)
	c.set_process(false)
	for i in range(4):
		await process_frame
	c.waves_enabled = true
	c.defined_waves = true
	c.auto_spawn = true  # the wave system needs it (no random arrivals are stepped here)
	c.wave_cues_enabled = false
	c.klaxon_enabled = false

	# ---------------- Balance: nuke speeds ----------------
	check(is_equal_approx(c.easy_nuke_speed, 1.1) and is_equal_approx(c.normal_nuke_speed, 1.25) and is_equal_approx(c.hard_nuke_speed, 1.45), "Nuke speeds: Easy 1.1, Normal 1.25, Hard 1.45 (field-tested)")
	check(is_equal_approx(c.nuke_speed_random_max, 0.08), "The 0-8% random nuke speed bonus is kept")
	for level in [0, 1, 2]:
		fresh(c, level)
		c.sets_completed = 0
		var want: float = [1.1, 1.25, 1.45][level]
		check(is_equal_approx(c.nuke_speed_factor(), want), "%s nuke speed factor is %.2f" % [["Easy", "Normal", "Hard"][level], want])

	# ---------------- Balance: Attack Drones and Breachers on Hard ----------------
	check(is_equal_approx(c.hard_drone_speed, 1.1) and is_equal_approx(c.hard_breacher_speed, 1.1), "Hard Attack Drone Speed and Hard Breacher Speed default to 1.1 (10% faster)")
	for level in [0, 1]:
		fresh(c, level)
		check(is_equal_approx(c.drone_speed(), c.small_hostile_speed) and is_equal_approx(c.heavy_speed(), c.breacher_speed), "%s: Attack Drone and Breacher speeds unchanged" % ["Easy", "Normal"][level])
	fresh(c, 2)
	check(is_equal_approx(c.drone_speed(), c.small_hostile_speed * 1.1) and is_equal_approx(c.heavy_speed(), c.breacher_speed * 1.1), "Hard: Attack Drones and Breachers 10% faster")
	check(is_equal_approx(c.speed_for_kind("drone"), c.small_hostile_speed * 1.1) and is_equal_approx(c.speed_for_kind("breacher"), c.breacher_speed * 1.1), "Hard: track speeds use the faster values")
	check(c.drone_speed() * 1.3 * 1.9 < c.speed_for_kind("interceptor"), "Hard: Interceptors stay well over 1.9x a chasing Attack Drone")
	# Measured: a Breacher covers more ground on Hard than on Normal in the same time.
	var travelled := []
	for level in [1, 2]:
		fresh(c, level)
		var b := base(c)
		var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
		var start: Vector3 = h.position
		step(c, 2.0)
		travelled.append(start.distance_to(c.find_contact(h.id).position) if not c.find_contact(h.id).is_empty() else 0.0)
	print("V127_HEAVY_TRAVEL normal=%.4f hard=%.4f ratio=%.3f" % [travelled[0], travelled[1], travelled[1] / maxf(0.0001, travelled[0])])
	check(travelled[0] > 0.0 and travelled[1] / travelled[0] > 1.06 and travelled[1] / travelled[0] < 1.12, "Measured: a Breacher flies about 10% further in 2 s on Hard (steering takes a little of it)")
	fresh(c, 2)
	check(is_equal_approx(c.protect_drone_speed, 0.07), "Protect the fleet Attack Drones keep their own speed")

	# ---------------- Alert box threat list ----------------
	fresh(c, 1)
	check(c.inbound_threats().is_empty(), "Quiet: no threat lines")
	var b1 := base(c)
	var b2 := base(c)
	c.nuclear_launch_delay = 99.0
	var nuke_id: String = c._launch_nuclear(b1)
	var m1: String = c.spawn_from_carrier("missile", b1.id)
	var m2: String = c.spawn_from_carrier("missile", b2.id)
	var h1: String = c.spawn_from_carrier("breacher", b1.id)
	c.spawn_from_carrier("drone", b2.id)
	var rows: Array = c.inbound_threats()
	var labels := []
	for r in rows:
		labels.append("%d %s" % [r[0], r[1]])
	print("V127_THREATS ", labels)
	check(not nuke_id.is_empty() and not m1.is_empty() and not m2.is_empty() and not h1.is_empty(), "Test threats launched (1 nuke, 2 missiles, 1 Breacher, 1 Attack Drone)")
	check(labels == ["1 NUKE INBOUND", "2 MISSILES INBOUND", "1 BREACHER INBOUND"], "Threat lines in order: nukes, missiles, Breachers, with counts")
	check(rows[0][2].r > 0.9 and rows[0][2].g < 0.4 and rows[1][2].g > 0.7, "Nukes red, missiles amber")
	check(not str(labels).contains("ATTACK DRONES INBOUND") or str(labels).contains("HEAVY"), "Attack Drones are not listed")
	c.find_contact(h1).phase = "emp_return"
	check(c.inbound_threats().size() == 2, "A Breacher retreating after an EMP is not inbound")
	c.find_contact(h1).phase = "approach"
	c.contacts.erase(c.find_contact(nuke_id))
	check(c.inbound_threats()[0][1] == "MISSILES INBOUND", "A line disappears when its count reaches 0")
	# Layout against the slanted edge, with the longest labels and more lines than fit.
	var box: PackedVector2Array = frame.alert_box_poly()
	var k: float = frame._frame_scale()
	var x0: float = box[0].x + 9.0 * k
	var fs := maxi(9, int(round(12.0 * k)))
	var y_start: float = box[1].y + 7.0 * k + ThemeDB.fallback_font.get_height(fs)
	var many := []
	for i in range(12):
		many.append([12, ["NUKES INBOUND", "MISSILES INBOUND", "BREACHERS INBOUND"][i % 3], Color.WHITE])
	var layout: Array = frame.threat_line_layout(box, many, x0, y_start, fs, k)
	var all_fit := true
	var unchanged := true
	for line in layout:
		if line.label_x + line.label_width > frame.alert_box_right_x(box, line.y) - 4.0 * k:
			all_fit = false
		if line.label != many[0][1] and line.label != many[1][1] and line.label != many[2][1]:
			unchanged = false
	print("V127_ALERT_LAYOUT lines=%d first_room=%.1f widest=%.1f" % [layout.size(), layout[0].room, layout[2].label_width])
	check(layout.size() >= 7 and layout.size() < 12, "The box holds at least 7 lines and stops at its bottom edge (%d)" % layout.size())
	check(all_fit, "Every threat line stays inside the slanted edge")
	check(unchanged, "All three labels fit uncut at the default size")
	var long_layout: Array = frame.threat_line_layout(box, [[3, "A VERY LONG THREAT LABEL THAT CANNOT FIT HERE", Color.WHITE]], x0, y_start, fs, k)
	check(long_layout[0].label_x + long_layout[0].label_width <= frame.alert_box_right_x(box, long_layout[0].y) - 4.0 * k and long_layout[0].size >= 9, "An over-long label shrinks, then is cut, and still fits")
	# Hacking takes over the box (no summary line).
	frame.queue_redraw()
	await process_frame
	check(c.hack_state() == "approach", "A Breacher approaching keeps the threat list (state approach)")

	# ---------------- Right panel score line ----------------
	fresh(c, 1)
	c.wave = 8
	c.sets_completed = 1
	c.wave_phase = "assault"
	check(not c.wave_detail_line().contains("SCORE"), "The wave detail line no longer carries the score multiplier")
	check(c.set_score_multiplier() > 1.0 and c.wave_score_line() == "SCORE MULTIPLIER  x%.2f" % c.set_score_multiplier(), "SCORE MULTIPLIER has its own line (%s)" % c.wave_score_line())
	c.sets_completed = 0
	check(c.wave_score_line().is_empty(), "No score line while the multiplier is 1.0")
	var font := ThemeDB.fallback_font
	var long_detail := "ASSAULT  |  ASSAULT ATTACK DRONE SWARM  |  FASTER WARHEADS"
	print("V127_RIGHT_FIT w16=%.1f fit=%d" % [font.get_string_size(long_detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, frame.fit_font_size(long_detail, 16, frame.RIGHT_PANEL_TEXT_ROOM)])
	check(frame.fit_font_size(long_detail, 16, frame.RIGHT_PANEL_TEXT_ROOM) < 16 and font.get_string_size(long_detail, HORIZONTAL_ALIGNMENT_LEFT, -1, frame.fit_font_size(long_detail, 16, frame.RIGHT_PANEL_TEXT_ROOM)).x <= frame.RIGHT_PANEL_TEXT_ROOM, "A right panel line that is too long shrinks to fit 316 px")
	check(frame.fit_font_size("SCORE MULTIPLIER  x1.25", 16, frame.RIGHT_PANEL_TEXT_ROOM) == 16, "The score line fits at full size")

	# ---------------- Wider status box ----------------
	var rect: Rect2 = frame._v2_status_rect()
	var outer_l: float = frame._mock(frame.V2_PANEL_OUTER_L, 0.0).x
	var outer_r: float = frame._mock(frame.V2_PANEL_OUTER_R, 0.0).x
	print("V127_STATUS_BOX x=%.1f..%.1f width=%.1f outer=%.1f..%.1f" % [rect.position.x, rect.end.x, rect.size.x, outer_l, outer_r])
	check(is_equal_approx(frame.V2_STATUS_HALF, 455.0), "Status box half width is 455 mockup px (was 300)")
	check(absf(rect.position.x - outer_l) < 0.6 and absf(rect.end.x - outer_r) < 0.6, "Status box edges line up with the panel outer edges")
	check(absf(rect.size.x - 1092.0) < 1.0, "Status box is 1,092 px wide at the default window")
	var status_label: Label = console.get_node("BattleStatus")
	var res_msg := "SIEGE SHIP CROSSING RIGHT TO LEFT | MISSILE BARRAGES | INTERCEPTORS, GUNSHIPS, SHIP MISSILES"
	check(console.status_font_size(status_label, res_msg, 18) == 18, "The long Siege Ship message fits at full size")
	var sweep_msg := "BONUS SWEEP | 2 OF 3 GROUPS DESTROYED | +900 | NEXT ASSAULT IN 7 | MULTIPLIER x1.25"
	check(console.status_font_size(status_label, sweep_msg, 18) == 18, "A long Bonus Sweep message fits at full size")
	var huge := res_msg + " | " + res_msg
	var shrunk: int = console.status_font_size(status_label, huge, 18)
	check(shrunk < 18 and shrunk >= 12, "Safety net: an over-long message shrinks (to %d px), never below 12" % shrunk)
	status_label.text = res_msg
	console._fit_status_label(status_label, 18)
	check(status_label.get_theme_font_size("font_size") == 18, "Status label keeps 18 px for every normal message")
	check(console.status_base_size == 18 and console.nuclear_base_size == 20, "Safety net starts from the scene font sizes (18, 20)")

	# ---------------- JUMP held in the round ----------------
	check(not ("protect_allow_jump" in c), "The Protect Allow Jump option is removed")
	start_protect(c, 1)
	c.jump_recharge_remaining = 0.0
	c.jump_offline = false
	check(c.protect_active() and not c.can_jump(), "JUMP cannot be used during Protect the fleet")
	check(not c.request_jump() and c.wave_phase == "protect", "A jump request is refused and the round goes on")
	c.auto_jump = true
	c.hull = 5
	step(c, 1.0)
	check(c.wave_phase == "protect" or c.is_defeated(), "Auto JUMP does not jump during the round")
	c.auto_jump = false
	await process_frame
	var jump_button: Button = console.get_node("BottomButtons/Jump")
	check(jump_button != null and jump_button.disabled and jump_button.text.contains("HELD | PROTECT THE CONVOY"), "JUMP button shows HELD | PROTECT THE CONVOY")

	# ---------------- Auto Launch Interceptors in the round ----------------
	start_protect(c, 1, 11)
	c.auto_launch_interceptors = true
	c.auto_defense_battery = true
	step(c, 6.0)
	var interceptors := 0
	for x in c.contacts:
		if x.kind == "interceptor":
			interceptors += 1
	print("V127_PROTECT_AUTO launched=%d auto=%d drones_total=%d interceptors_now=%d" % [c.protect_interceptors_launched, c.protect_auto_interceptor_launches, c.protect_drones_total, interceptors])
	check(c.protect_auto_interceptor_launches > 0 and c.protect_interceptors_launched > 0, "Auto Launch Interceptors launches during Protect the fleet")
	check(c.protect_interceptors_launched <= c.protect_drones_total, "Auto launches stay within one Interceptor per Attack Drone")
	check(not c.prox_active, "Auto Defense Shield stays paused in the round")
	var with_autos: float = c.points_for(1000)
	c.auto_launch_interceptors = false
	c.auto_defense_battery = false
	var without_autos: float = c.points_for(1000)
	print("V127_AUTO_CUT with=%.0f without=%.0f" % [with_autos, without_autos])
	check(absf(with_autos / without_autos - 0.8) < 0.01, "The usual 10% auto score cut per option applies (two options: x0.8)")
	start_protect(c, 1, 11)
	c.auto_launch_interceptors = false
	step(c, 6.0)
	check(c.protect_auto_interceptor_launches == 0 and c.protect_interceptors_launched <= 1, "With Auto Launch Interceptors off, only the round's patrol Interceptor goes out (%d)" % c.protect_interceptors_launched)

	# ---------------- Protect the fleet result ----------------
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
		var sounds_before: int = c.protect_result_sound_count
		c._end_protect("drones destroyed" if outcome != "lost" else "all lost")
		var lines: Array[String] = c.rest_tally_lines()
		print("V127_RESULT %s lines=%s rest=%.1f" % [outcome, lines, c.wave_rest_remaining])
		check(c.protect_outcome() == outcome, "%s: outcome detected" % outcome)
		var want_title: String = {"saved": "SUPPORT FLEET SAVED", "partial": "%d OF %d SHIPS SAVED" % [total - 1, total], "lost": "SUPPORT FLEET LOST"}[outcome]
		check(lines[0] == want_title, "%s: title %s" % [outcome, want_title])
		check(c.last_protect_result_sound == outcome and c.protect_result_sound_count == sounds_before + 1, "%s: its own sound plays once" % outcome)
		check(absf(c.wave_rest_remaining - (c.rest_seconds() + 5.0)) < 0.01, "%s: the result stays up 5 s longer (%.1f s on Normal)" % [outcome, c.wave_rest_remaining])
		var player_name: String = {"saved": "FleetSavedAudio", "partial": "FleetPartialAudio", "lost": "FleetLostAudio"}[outcome]
		var player: AudioStreamPlayer = c.get_node_or_null(player_name)
		check(player != null and player.stream is AudioStreamWAV, "%s: %s exists" % [outcome, player_name])
		var rows2: Array = c.protect_result_rows(lines)
		if outcome != "lost":
			check(lines[2].begins_with("+") and int(rows2[2][1]) == 40, "%s: the bonus is a large 40 px line (%s)" % [outcome, lines[2]])
			check(rows2[2][2].r > 0.9 and rows2[2][2].g > 0.8 and rows2[2][2].b < 0.7, "%s: the bonus is yellow" % outcome)
		else:
			check(lines[2] == "NO CONVOY BONUS" and int(rows2[2][1]) < 40, "lost: a quiet NO CONVOY BONUS line")
		check(lines[lines.size() - 1].begins_with("NEXT"), "%s: the NEXT line is kept" % outcome)
		# 1.0.9: the result uses the shared round box: 600 wide like the Game Over screen,
		# centred, in the upper scope and inside the radar area (the approved mockup lets its
		# top corners reach the scope's curved edge).
		var r: Rect2 = c.protect_result_rect(rows2)
		var centre: Vector2 = c.size * 0.5
		var inside := Rect2(Vector2.ZERO, c.size).encloses(r) and is_equal_approx(r.size.x, 600.0) and is_equal_approx(r.get_center().x, centre.x) and r.get_center().y < centre.y
		check(inside, "%s: the result panel is the shared 600-wide box in the upper scope" % outcome)
	# Saved partial colour: green; lost: red.
	check(c.protect_result_rows(c.rest_tally_lines())[0][2].r > 0.9, "SUPPORT FLEET LOST title is red")
	# Flash: twice a second for 3 s, then steady.
	c.protect_result_started = c.battle_time
	var toggles := 0
	var last := true
	var off_after := false
	for i in range(0, 80):
		c.battle_time = c.protect_result_started + i * 0.05
		var on: bool = c.protect_result_flash_on()
		if on != last:
			toggles += 1
		last = on
		if i * 0.05 >= 3.0 and not on:
			off_after = true
	check(toggles >= 11 and toggles <= 12, "The bonus and border flash twice a second for 3 s (%d changes)" % toggles)
	check(not off_after, "After 3 s the bonus stays steady")
	c.protect_result_sounds = false
	start_protect(c, 1, 5)
	var before: int = c.protect_result_sound_count
	c._end_protect("drones destroyed")
	check(c.protect_result_sound_count == before, "Protect Result Sounds off: no sound")
	c.protect_result_sounds = true
	# A normal wave rest is not lengthened.
	fresh(c, 1)
	c.wave = 2
	c.wave_phase = "assault"
	c.rest_after_protect = false
	c._begin_rest()
	check(absf(c.wave_rest_remaining - c.rest_seconds()) < 0.01, "Normal wave rests keep their length")

	# ---------------- The three sounds ----------------
	var saved: AudioStreamWAV = BattleAudio.make_fleet_saved()
	var partial: AudioStreamWAV = BattleAudio.make_fleet_partial()
	var lost: AudioStreamWAV = BattleAudio.make_fleet_lost()
	var secs := [saved.data.size() / 96000.0, partial.data.size() / 96000.0, lost.data.size() / 96000.0]
	var peaks := [peak(saved), peak(partial), peak(lost)]
	print("V127_SOUNDS seconds=%s peaks=%s" % [secs, peaks])
	check(absf(secs[0] - 1.9) < 0.01 and absf(secs[1] - 1.7) < 0.01 and absf(secs[2] - 2.0) < 0.01, "Sound lengths 1.9 s, 1.7 s, 2.0 s")
	check(peaks[0] < 0.79 and peaks[1] < 0.79 and peaks[2] < 0.79 and peaks[0] > 0.4 and peaks[1] > 0.4 and peaks[2] > 0.4, "No clipping, and all three at a similar level")
	check(saved.data != partial.data and partial.data != lost.data and saved.data != lost.data, "Three different sounds")
	check(saved.data == BattleAudio.make_fleet_saved().data, "Sounds are deterministic")
	check(is_equal_approx(c.fleet_saved_volume_db, -14.0) and is_equal_approx(c.fleet_partial_volume_db, -14.0) and is_equal_approx(c.fleet_lost_volume_db, -14.0), "Result sound volumes default to -14 dB, like the wave cues")

	print("V127_RESULT checks=%d failures=%d" % [checks, failures])
	for p in console.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	console.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures > 0 else 0)
