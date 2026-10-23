extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.07: enemy missiles pulse, ship and Gunship missiles find a
## new target, the FIREWALL button splits into FIREWALL | EMP 2 seconds after the
## Firewall runs out, shorter tags, and Interceptor squadrons that split up and rejoin.
var console: Control
var c: Control
var ship: Control
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
func clean(level: int = 1) -> void:
	c.difficulty = level
	c.auto_spawn = false
	c.breachers_enabled = true
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
func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
		b.drone_timer = 999.0
		b.missile_timer = 999.0
		b.heavy_timer = 999.0
	return b
func hacker(b: Dictionary) -> Dictionary:
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	if not h.is_empty():
		h.position = h.hack_point
		c._update_breachers(0.0)
	return h
func frames(n: int) -> void:
	for i in range(n):
		await process_frame
func step_weapons(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		c._update_own_weapons(0.05)
		t += 0.05
func interceptor_at(pos: Vector3) -> Dictionary:
	var v: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
	v.position = pos
	v.phase = "intercept"
	return v
func drone_at(b: Dictionary, pos: Vector3) -> Dictionary:
	var r: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	r.position = pos
	r.phase = "attack"
	return r

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://v107_test_settings.cfg"
	console.high_score_file = "user://v107_test_scores.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	if FileAccess.file_exists(console.settings_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(console.settings_file))
	c = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	ship = console.get_node("ShipStatus")
	c.auto_spawn = false
	c.random_seed = 1007
	root.add_child(console)
	c.set_process(false)
	console.get_node("TuningPanel").visible = false
	clean()

	# --- Full build 1.07 ---
	check(ProjectSettings.get_setting("application/config/version") == "1.0.8", "Project version is 1.08")
	check(not console.test_build and console.version_text() == "STELLAR DEFENSE CONSOLE 1.0.8", "Version text reads STELLAR DEFENSE CONSOLE 1.0.8")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.0.8_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.0.8_Mac.zip")
		and presets.get_value("preset.1.options", "application/version", "") == "1.0.8", "Export presets name 1.08 files")

	# --- 1. Enemy missiles pulse, never vanish ---
	var b := base()
	var m: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	check(not m.is_empty() and m.kind == "missile", "Setup: an enemy missile")
	check(c.enemy_missile_pulse and c.enemy_missile_pulse_hz == 2.0 and absf(c.enemy_missile_pulse_min - 0.35) < 0.001, "Pulse on, 2 per second, lowest 35% by default")
	var levels: Array[float] = []
	var alphas: Array[float] = []
	for i in range(50):
		c.battle_time = 10.0 + i * 0.01
		var col: Color = c.display_color(m)
		levels.append(maxf(col.r, maxf(col.g, col.b)))
		alphas.append(col.a)
	var top: float = maxf(c.hostile_color.r, maxf(c.hostile_color.g, c.hostile_color.b))
	check(absf(levels.max() - top) < 0.02, "Pulse reaches full brightness")
	check(absf(levels.min() - top * 0.35) < 0.03, "Pulse dips to about 35%% (%.2f of %.2f)" % [levels.min(), top])
	check(levels.min() > 0.0 and alphas.min() == alphas.max(), "The missile never vanishes (always drawn, alpha steady)")
	c.battle_time = 10.0
	var a0: Color = c.display_color(m)
	c.battle_time = 10.25
	var a1: Color = c.display_color(m)
	c.battle_time = 10.5
	var a2: Color = c.display_color(m)
	check(a0.r > a1.r and a2.is_equal_approx(a0), "One full pulse every half second (2 per second)")
	var nuke := {"id": "N-T1", "kind": "nuke", "faction": "hostile", "position": Vector3(0.1, 0.2, 0.0), "age": 0.0}
	var n0: Color = c.display_color(nuke)
	c.battle_time = 10.25
	check(c.display_color(nuke).is_equal_approx(n0), "Nukes keep their look (no pulse)")
	c.enemy_missile_pulse = false
	check(c.display_color(m).is_equal_approx(c.hostile_color), "Switching the pulse off restores the steady red")
	c.enemy_missile_pulse = true

	# --- 2. Ship and Gunship missiles find a new target ---
	clean()
	c.carrier_hits_to_destroy = 6
	var b1 := base()
	var b2 := base()
	check(not b1.is_empty() and not b2.is_empty(), "Setup: two Enemy Carriers")
	c._launch_ship_missile(b1)
	var shot: Dictionary = c.contacts[-1]
	check(shot.kind == "own_missile" and shot.target_id == b1.id, "Setup: a ship missile heading for Enemy Carrier 1")
	step_weapons(0.2)
	b1.hits_remaining = 0.5
	c._hit_carrier(b1)
	check(c.find_contact(b1.id).is_empty(), "Enemy Carrier 1 destroyed before the missile arrives")
	check(not c.find_contact(shot.id).is_empty(), "The missile is not removed")
	step_weapons(0.05)
	check(shot.target_id == b2.id and c.missile_retargets == 1, "It turns toward Enemy Carrier 2")
	var hits_before: float = b2.hits_remaining
	step_weapons(30.0)
	check(c.find_contact(shot.id).is_empty() and b2.hits_remaining < hits_before, "It hits Enemy Carrier 2 (not wasted)")
	# Gunship missile retargets too.
	clean()
	var r1 := base()
	var r2 := base()
	c.contacts.append({"id": "RM-T1", "kind": "gunship_missile", "faction": "friendly", "position": Vector3(0.0, -0.5, 0.0),
		"age": 0.0, "target_id": r1.id, "target_position": r1.position, "damage": 0.5})
	c._remove_contact(r1.id)
	step_weapons(0.05)
	check(c.find_contact("RM-T1").get("target_id", "") == r2.id, "A Gunship missile also turns to the next enemy")
	# Nearest valid enemy is chosen.
	clean()
	var far := base()
	var heavy: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", far.id))
	heavy.position = Vector3(0.05, -0.45, 0.0)
	var probe := {"id": "P-T", "kind": "own_missile", "position": Vector3(0.0, -0.5, 0.0), "target_id": ""}
	check(c.missile_retarget(probe).get("id", "") == heavy.id, "The nearest valid enemy is chosen (a close Breacher)")
	check(c.missile_retarget({"id": "P-X", "kind": "own_missile", "position": Vector3(0.0, -0.5, 0.0)}).get("faction", "") == "hostile", "Only enemies are chosen")
	# The nuke hit cap still holds.
	clean()
	c.ship_missiles_target_nukes = true
	var cap_base := base()
	var warhead := {"id": "N-CAP", "kind": "nuke", "faction": "hostile", "position": Vector3(0.0, -0.55, 0.0), "age": 0.0,
		"nuke_hits": 1, "nuke_max_hits": 3, "velocity": Vector3.ZERO}
	c.contacts.append(warhead)
	c._launch_ship_missile(warhead)
	var spare := {"id": "P-SPARE", "kind": "own_missile", "faction": "friendly", "position": Vector3(0.0, -0.6, 0.0), "age": 0.0,
		"target_id": "GONE", "target_position": Vector3.ZERO}
	check(c.missile_retarget(spare).get("id", "") == cap_base.id, "A nuke that already has enough missiles is skipped (1.05 rule kept)")
	c._remove_contact(cap_base.id)
	c.contacts.append(spare)
	c.nuclear_weapons_enabled = false
	step_weapons(0.05)
	check(c.find_contact("P-SPARE").is_empty(), "With no valid target left, the missile disappears")
	var contacts_src := FileAccess.get_file_as_string("res://scripts/RadarContacts.gd")
	check(not contacts_src.contains("contacts[index].target_id == id:\n\t\t\tcontacts.remove_at(index)"), "Destroyed or escaped targets no longer delete the missiles chasing them")

	# --- 3. FIREWALL | EMP split, 2 seconds after the Firewall runs out ---
	clean()
	check(not ship.emp_on_ship, "The 1.06 USE EMP box on the ship is off (INTRUSION DETECTION always shows)")
	check(absf(c.emp_delay_after_firewall - 2.0) < 0.001, "EMP Delay After Firewall is 2.0 seconds")
	var fw: Button = console.get_node("BottomButtons/Firewall")
	var split: Button = console.emp_split_button
	check(split != null and split.get_parent() == fw, "EMP half is part of the FIREWALL button")
	c.emp_charges = 1
	var hb2 := base()
	var hk := hacker(hb2)
	check(not hk.is_empty() and hk.phase == "hacking", "Setup: a Breacher is hacking, one EMP charge ready")
	c._update_emp_offer()
	console._process(0.016)
	check(not c.can_use_emp() and not split.visible, "Firewall ready: no EMP yet (Firewall first)")
	check(ship.battle.hack_state() in ["hacking", "draining"] and not ship.emp_button.visible, "INTRUSION DETECTION shows on the ship")
	c.set_firewall(true)
	check(c.firewall_active, "Firewall raised")
	var t := 0.0
	while c.firewall_active and t < 20.0:
		c.battle_time += 0.05
		c._update_firewall(0.05)
		c._update_emp_offer()
		t += 0.05
		if c.can_use_emp():
			break
	check(not c.firewall_active and c.firewall_charge <= 0.0, "Firewall ran out")
	check(not c.can_use_emp(), "No EMP while the Firewall is still running")
	var out_at: float = c.battle_time
	while c.battle_time - out_at < 1.9:
		c.battle_time += 0.05
		c._update_firewall(0.05)
		c._update_emp_offer()
	console._process(0.016)
	check(not c.can_use_emp() and not split.visible, "1.9 seconds after it runs out: still no EMP")
	while c.battle_time - out_at < 2.1:
		c.battle_time += 0.05
		c._update_firewall(0.05)
		c._update_emp_offer()
	console._process(0.016)
	check(c.can_use_emp() and split.visible, "2 seconds after the Firewall runs out: the EMP half appears")
	var half: float = fw.size.x * 0.5
	check(split.position.x >= half and split.position.x + split.size.x <= fw.size.x + 0.5 and absf(split.size.y - fw.size.y) < 0.5, "EMP fills the right half of the FIREWALL button")
	check(split.text.begins_with("EMP\n1 CHARGE") and fw.text.begins_with("FIREWALL\n"), "Halves read FIREWALL and EMP 1 CHARGE")
	var fw_box: StyleBox = fw.get_theme_stylebox("normal")
	check(fw_box.content_margin_right >= half, "FIREWALL text kept in the left half")
	var font: Font = split.get_theme_font("font")
	var fs: int = split.get_theme_font_size("font_size")
	var widest := 0.0
	for line in split.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var fw_widest := 0.0
	for line in fw.text.split("\n"):
		fw_widest = maxf(fw_widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fw.get_theme_font_size("font_size")).x)
	check(widest <= split.size.x - 8.0 and fw_widest <= half - 8.0, "Both halves fit their text (%.0f / %.0f px, %.0f / %.0f)" % [widest, split.size.x, fw_widest, half])
	check(split.size.x >= 100.0 and split.size.y >= 60.0, "EMP half is large enough to tap (%.0f x %.0f)" % [split.size.x, split.size.y])
	check(ship.battle.hack_state() in ["hacking", "draining"] and not ship.emp_button.visible, "INTRUSION DETECTION still shows while the EMP is offered")
	split.pressed.emit()
	check(c.emp_uses == 1 and c.emp_charges == 0 and hk.phase == "emp", "Clicking EMP fires it (Breacher overloaded)")
	c._update_emp_offer()
	console._process(0.016)
	check(not split.visible and fw.get_theme_stylebox("normal").content_margin_right < half, "Afterwards FIREWALL is a whole button again")
	# No charge: never split.
	clean()
	c.emp_charges = 0
	var hb3 := base()
	hacker(hb3)
	c.firewall_charge = 0.0
	for i in range(60):
		c.battle_time += 0.05
		c._update_emp_offer()
	console._process(0.016)
	check(c.emp_offer_open and not split.visible, "Without a charge the button never splits")
	# Firewall unavailable (recharging) when the hack starts also counts as out.
	c.emp_charges = 1
	console._process(0.016)
	check(split.visible, "Firewall too low to raise for 2 seconds also opens the EMP")
	c.reset_battle()
	check(not c.emp_offer_open, "Retry clears the EMP offer")

	# --- 4. Short tags ---
	clean()
	check(not c.show_full_tags, "Show Full Tags is off by default")
	var tb := base()
	var rd := drone_at(tb, Vector3(0.1, 0.0, 0.0))
	var vp := interceptor_at(Vector3(-0.1, -0.3, 0.0))
	vp.health = 1
	vp.max_health = 3
	var rp: Dictionary = c.find_contact(c._spawn_gunship())
	check(c.contact_tag(rd) == "ATTACK DRONE", "Attack Drone tag: ATTACK DRONE (%s)" % c.contact_tag(rd))
	check(c.contact_tag(vp) == "INTERCEPTOR", "Damaged Interceptor tag: INTERCEPTOR, no ID or percent")
	vp.phase = "return"
	check(c.contact_tag(vp) == "INTERCEPTOR", "Returning Interceptor tag: INTERCEPTOR, no RTB")
	check(not rp.is_empty() and c.contact_tag(rp) == "GUNSHIP", "Gunship tag: GUNSHIP")
	check(c.contact_tag(m) == "" and c.contact_tag({"id": "P-1", "kind": "own_missile"}) == "" and c.contact_tag({"id": "RM-1", "kind": "gunship_missile"}) == "", "Enemy, ship and Gunship missiles have no tag")
	var nk := {"id": "N-2", "kind": "nuke", "nuke_hits": 2, "nuke_max_hits": 3}
	check(c.contact_tag(nk) == "NUCLEAR 67%", "NUCLEAR keeps its hit percent")
	check(c.contact_tag(tb).begins_with("ENEMY CARRIER "), "ENEMY CARRIER keeps its strength")
	var hv := {"id": "H-1", "kind": "breacher", "phase": "hacking", "hack_remaining": 5.2}
	check(c.contact_tag(hv) == "HACKING 6s", "Breacher threat tags are kept")
	c.show_full_tags = true
	check(c.contact_tag(rd) == "ATTACK DRONE " + rd.id and c.contact_tag(vp).contains(vp.id), "Show Full Tags brings back IDs for testing")
	c.show_full_tags = false
	var draw_src := contacts_src.substr(contacts_src.find("func _draw_interceptor_squadrons("), 1600)
	check(draw_src.contains("\"INTERCEPTORS x%d\" % members.size()"), "Squadron tag reads INTERCEPTORS x2, INTERCEPTORS x3")

	# --- 5. Squadrons split to engage and rejoin ---
	clean()
	check(c.squadrons_split_to_engage and c.max_interceptors_per_tough_target == 2 and absf(c.squadron_split_distance - 0.06) < 0.001, "Squadrons Split To Engage on; 2 Interceptors per tough target; split distance 0.06")
	var sb := base()
	var v1 := interceptor_at(Vector3(0.0, -0.40, 0.0))
	var v2 := interceptor_at(Vector3(0.02, -0.40, 0.0))
	var v3 := interceptor_at(Vector3(0.04, -0.40, 0.0))
	var e1 := drone_at(sb, Vector3(-0.25, -0.10, 0.0))
	var e2 := drone_at(sb, Vector3(0.0, -0.05, 0.0))
	var e3 := drone_at(sb, Vector3(0.25, -0.10, 0.0))
	for e in [e1, e2, e3]:
		e.velocity = Vector3.ZERO
	c._update_interceptors(0.02)
	var chosen := {}
	for v in [v1, v2, v3]:
		chosen[v.target_id] = true
	check(chosen.size() == 3, "Three Interceptors, three Attack Drones: each takes a different Attack Drone (%d targets)" % chosen.size())
	c._update_interceptor_squadrons()
	check(c.squadron_of(v1.id) != -1, "They start out drawn as one squadron")
	var apart := false
	for i in range(60):
		c._update_interceptors(0.05)
		c._update_interceptor_squadrons()
		var groups := {}
		for v in [v1, v2, v3]:
			groups[c.squadron_of(v.id) if c.squadron_of(v.id) != -1 else v.id] = true
		if groups.size() >= 2:
			apart = true
	check(apart, "They break up to chase their own targets")
	# One Attack Drone left: they may all go for it.
	clean()
	var ob := base()
	var w1 := interceptor_at(Vector3(0.0, -0.40, 0.0))
	var w2 := interceptor_at(Vector3(0.03, -0.40, 0.0))
	var lone := drone_at(ob, Vector3(0.0, -0.1, 0.0))
	c._update_interceptors(0.02)
	check(w1.target_id == lone.id and w2.target_id == lone.id, "With only one enemy left, both go after it")
	# Rejoin when the area is clear.
	clean()
	var p1 := interceptor_at(Vector3(-0.35, -0.2, 0.0))
	var p2 := interceptor_at(Vector3(0.35, 0.1, 0.0))
	var p3 := interceptor_at(Vector3(0.0, -0.5, 0.0))
	for i in range(400):
		c._update_interceptors(0.05)
	c._update_interceptor_squadrons()
	check(p1.phase == "patrol" and p2.phase == "patrol", "With the area clear they patrol")
	check(c.squadron_of(p1.id) != -1 and c.squadron_of(p1.id) == c.squadron_of(p2.id) and c.squadron_of(p2.id) == c.squadron_of(p3.id), "They fly back and rejoin one squadron")
	var spread: float = maxf(p1.position.distance_to(p2.position), maxf(p1.position.distance_to(p3.position), p2.position.distance_to(p3.position)))
	check(spread < c.squadron_join_distance * 1.5, "Formation is tight (%.3f)" % spread)
	# A full flight of six still forms one squadron.
	clean()
	var six: Array = []
	for i in range(6):
		six.append(interceptor_at(Vector3(-0.3 + i * 0.12, -0.3, 0.0)))
	for i in range(500):
		c._update_interceptors(0.05)
	c._update_interceptor_squadrons()
	check(c.interceptor_squadrons.size() == 1 and c.interceptor_squadrons[0].size() == 6, "Six idle Interceptors rejoin as one squadron (INTERCEPTORS x6)")
	c.squadrons_split_to_engage = false
	clean()
	var q1 := interceptor_at(Vector3(0.0, -0.40, 0.0))
	var q2 := interceptor_at(Vector3(0.02, -0.40, 0.0))
	var qb := base()
	var f1 := drone_at(qb, Vector3(-0.2, -0.1, 0.0))
	var f2 := drone_at(qb, Vector3(0.0, -0.1, 0.0))
	c._update_interceptors(0.02)
	check(q1.target_id == q2.target_id, "Switch off: they all chase the nearest, as before 1.07")
	c.squadrons_split_to_engage = true
	# Defense priority kept: a hacking Breacher still pulls a Interceptor first.
	clean()
	var db := base()
	var dh := hacker(db)
	var dv := interceptor_at(Vector3(0.0, -0.40, 0.0))
	var dr := drone_at(db, Vector3(0.0, -0.2, 0.0))
	c._update_interceptors(0.02)
	check(dv.target_id == dr.id or dv.target_id == dh.id, "A Interceptor still engages the nearest threat (%s; drone %s, heavy %s)" % [dv.target_id, dr.id, dh.id])

	# --- Preserved ---
	check(not console.development_build and absf(console.sweep_volume_db + 20.0) < 0.01 and not console.show_hover_tooltips, "Development Build and hover pop-ups off; sweep still -20 dB")
	check(c.emp_points_per_charge == 5000 and c.emp_max_charges == 2 and is_equal_approx(c.hard_nuke_speed, 1.45), "1.06 EMP values unchanged; Hard nuke speed 1.45 (1.2.7)")

	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("V107_RESULT checks=%d failures=%d" % [checks, failures])
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
