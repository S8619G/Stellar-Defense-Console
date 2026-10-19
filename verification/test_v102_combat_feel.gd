extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.02: missile flash and small boom, nuke explosion with
## screen flash and boom, nukes that take several Gunship hits, a 0.5 s minimum
## for auto defenses, and Interceptor squadron grouping (display only).
const BattleAudio = preload("res://scripts/BattleAudio.gd")
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
	c.nuclear_weapons_enabled = false
	c.siege_enabled = false
	c.auto_defense_battery = false
	c.auto_firewall = false
	c.reset_battle()
func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
	return b
func step(seconds: float) -> void:
	for i in range(roundi(seconds * 60.0)):
		c._process(1.0 / 60.0)
func peak_and_rms(stream: AudioStreamWAV) -> Vector2:
	var data := stream.data
	var peak := 0.0
	var total := 0.0
	var n := data.size() / 2
	for i in range(n):
		var v := absf(data.decode_s16(i * 2) / 32767.0)
		peak = maxf(peak, v)
		total += v * v
	return Vector2(peak, sqrt(total / maxf(1, n)))
func interceptor_at(position: Vector3) -> Dictionary:
	c.launch_interceptors()
	var newest: Dictionary = {}
	for contact in c.contacts:
		if contact.kind == "interceptor":
			newest = contact
	return newest

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://v102_test_settings.cfg"
	console.high_score_file = "user://v102_test_scores.json"
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
	await process_frame
	clean()

	# --- 1. Destruction sounds ---
	var small := BattleAudio.make_missile_boom()
	var big := BattleAudio.make_nuke_boom()
	check(is_equal_approx(small.get_length(), 0.32) and is_equal_approx(big.get_length(), 1.1), "Missile boom 0.32 s, nuke explosion 1.1 s (brief)")
	check(small.data == BattleAudio.make_missile_boom().data and big.data == BattleAudio.make_nuke_boom().data, "Both sounds are original PCM generated the same every time")
	var small_level := peak_and_rms(small)
	var big_level := peak_and_rms(big)
	print("BOOM_LEVELS missile_peak=%.2f missile_rms=%.3f nuke_peak=%.2f nuke_rms=%.3f" % [small_level.x, small_level.y, big_level.x, big_level.y])
	check(small_level.x < 0.84 and big_level.x < 0.84, "No clipping in either sound")
	check(big_level.y * big.get_length() > small_level.y * small.get_length() * 3.0, "The nuke explosion is clearly bigger than the missile boom")
	check(c.missile_boom_player.bus == "Effects" and c.nuke_boom_player.bus == "Effects", "Both play on the Effects bus (Effects slider and mute apply)")
	check(c.missile_boom_volume_db < c.nuke_boom_volume_db and c.nuke_boom_volume_db < c.nuclear_alert_volume_db and c.nuke_boom_volume_db < c.klaxon_volume_db, "Booms sit below the alert levels; the missile boom is the quieter one")

	# --- 2. Missile destroyed: tiny flash and small boom ---
	var b := base()
	c.carrier_weapons_enabled = true
	var m: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	m.position = c.own_ship_position + Vector3(0.0, 0.1, 0.0)  # 1.04: kill zone at the flak arc
	c.prox_success_chance = 0.95
	c.set_prox_defense(true)
	var guard := 0
	while not c.find_contact(m.id).is_empty() and guard < 600:
		c._resolve_missiles()
		c.battle_time += 1.0 / 60.0
		guard += 1
	check(c.find_contact(m.id).is_empty() and c.explosions.size() == 1 and c.explosions[0].kind == "missile", "Defense Shield kill shows a missile flash")
	check(c.booms_played.missile == 1 and c.missile_boom_player.playing, "and plays the small boom")
	check(c.screen_flash_alpha() == 0.0, "A missile does not flash the whole screen")
	c.set_prox_defense(false)
	var m2: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	var m3: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
	c._explode(m2.position, "missile")
	c._explode(m3.position, "missile")
	check(c.explosions.size() == 3 and c.booms_played.missile == 1, "Two kills at the same moment: two flashes, one boom (no loud stacking)")
	c.battle_time += 0.2
	c._explode(m3.position, "missile")
	check(c.booms_played.missile == 2, "A later kill booms again")
	c._age_explosions(0.31)
	check(c.explosions.is_empty(), "Missile flashes are gone within 0.3 s")
	clean()
	var b2 := base()
	c.carrier_weapons_enabled = true
	var m4: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b2.id))
	var v: Dictionary = interceptor_at(Vector3.ZERO)
	v.phase = "intercept"
	v.position = m4.position
	c._update_interceptors(1.0 / 60.0)
	var interceptor_flash := false
	for blast in c.explosions:
		interceptor_flash = interceptor_flash or blast.kind == "missile"
	check(c.find_contact(m4.id).is_empty() and interceptor_flash, "A Interceptor kill also shows the missile flash")

	# --- 3. Nukes take several Gunship hits; explosion and screen flash ---
	var needed := {}
	for level in [0, 1, 2]:
		c.difficulty = level
		clean()
		var nb := base()
		var nid: String = c._launch_nuclear(nb)
		c.launch_gunship()
		var start_position: Vector3 = c.find_contact(nid).position
		var first_hit := -1.0
		var first_position := Vector3.ZERO
		var killed_at := -1.0
		var killed_position := Vector3.ZERO
		var label_damaged := false
		for frame in range(60 * 60):
			var before: int = c.nuke_hits_landed
			var nuke: Dictionary = c.find_contact(nid)
			var last_position: Vector3 = nuke.position if not nuke.is_empty() else killed_position
			c._process(1.0 / 60.0)
			nuke = c.find_contact(nid)
			if c.nuke_hits_landed > before and first_hit < 0.0:
				first_hit = c.battle_time
				first_position = last_position
			if not nuke.is_empty() and nuke.has("nuke_hits") and nuke.nuke_hits < nuke.nuke_max_hits:
				label_damaged = true
			if nuke.is_empty():
				killed_at = c.battle_time
				killed_position = last_position
				break
		needed[level] = {"hits": c.nuke_hits_landed, "chase": killed_at - first_hit, "travel": first_position.distance_to(killed_position),
			"intercepted": c.nuclear_intercepts == 1, "label": label_damaged, "flash": c.screen_flash_alpha(),
			"blast": c.explosions.any(func(e: Dictionary) -> bool: return e.kind == "nuke"), "boom": c.booms_played.nuke, "flown": start_position.distance_to(killed_position)}
	print("NUKE_SIMULATION easy=", needed[0].hits, " normal=", needed[1].hits, " hard=", needed[2].hits,
		" normal_chase_seconds=%.2f normal_travel=%.3f normal_flown=%.3f" % [needed[1].chase, needed[1].travel, needed[1].flown])
	check(needed[1].intercepted and needed[1].hits == 3, "NORMAL: a Gunship needs 3 hits to destroy a nuke")
	check(needed[0].hits == 2 and needed[2].hits == 4 and needed[0].intercepted and needed[2].intercepted, "EASY 2 hits, HARD 4 hits (difficulty toughness)")
	check(needed[1].chase >= 1.1 and needed[1].travel >= 0.06, "The Gunship chases the nuke a visible distance (%.2f s)" % needed[1].chase)
	check(needed[1].label, "Damaged nuke shows its strength (NUCLEAR 67%)")
	check(needed[1].blast and needed[1].boom == 1, "Destroyed nuke shows an explosion with one boom")
	check(needed[1].flash > 0.2, "and a brief warm screen flash")
	c.difficulty = 1
	c._age_explosions(0.36)
	check(c.screen_flash_alpha() == 0.0, "The screen flash is over within 0.35 s (single flash, no strobing)")
	c._age_explosions(0.5)
	check(not c.explosions.any(func(e: Dictionary) -> bool: return e.kind == "nuke"), "The explosion clears within 0.8 s")
	clean()
	var ib := base()
	var impact_id: String = c._launch_nuclear(ib)
	var hull_before: float = c.hull
	c.find_contact(impact_id).position = c.own_ship_position
	c._update_special_projectiles(1.0 / 60.0)
	check(c.hull < hull_before and c.explosions.any(func(e: Dictionary) -> bool: return e.kind == "nuke_impact") and near(c.screen_flash_alpha(), c.nuke_impact_flash_strength), "A nuke hitting the ship explodes at the ship with a stronger flash")
	console._process(0.0)
	var overlay: ColorRect = console.get_node("ScreenFlash")
	check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE and near(overlay.color.a, c.screen_flash_alpha()) and overlay.get_index() < console.get_node("SettingsGear").get_index(), "Screen flash layer follows the flash, never blocks clicks and stays under the gear and Settings")
	clean()
	c.screen_flash_enabled = false
	c._explode(Vector3.ZERO, "nuke")
	check(c.screen_flash_alpha() == 0.0 and c.booms_played.nuke == 1, "Screen flash can be switched off in the Inspector (sound remains)")
	c.screen_flash_enabled = true
	c.explosion_effects_enabled = false
	c.explosions.clear()
	c._explode(Vector3.ZERO, "missile")
	check(c.explosions.is_empty(), "Explosion graphics can be switched off in the Inspector")
	c.explosion_effects_enabled = true

	# --- 4. Auto defenses stay on at least 0.5 s ---
	clean()
	var ab := base()
	c.carrier_weapons_enabled = true
	c.auto_defense_battery = true
	var am: Dictionary = c.find_contact(c.spawn_from_carrier("missile", ab.id))
	am.position = c.own_ship_position + Vector3(0.0, 0.2, 0.0)  # 1.04: auto lead zone
	c._update_automation()
	check(c.prox_active, "Auto shield engages")
	c.contacts.erase(am)
	c.battle_time += 0.2
	c._update_automation()
	check(c.prox_active, "Still firing 0.2 s later even though the zone is clear")
	c.battle_time += 0.35
	c._update_automation()
	check(not c.prox_active, "Stops after the 0.5 s minimum")
	c.auto_defense_battery = false
	clean()
	c.breachers_enabled = true
	c.auto_firewall = true
	var fb := base()
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", fb.id))
	h.position = h.hack_point
	c._update_breachers(1.0 / 60.0)
	c._update_automation()
	check(c.firewall_active, "Auto firewall engages")
	c.contacts.erase(h)
	c.battle_time += 0.2
	c._update_firewall(0.2)
	check(c.firewall_active, "Still up 0.2 s later even though the hack ended")
	c.battle_time += 0.35
	c._update_firewall(0.016)
	c._update_automation()
	check(not c.firewall_active, "Lowers after the 0.5 s minimum")
	c.auto_firewall = false
	clean()
	c.breachers_enabled = true
	var mb := base()
	var mh: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", mb.id))
	mh.position = mh.hack_point
	c._update_breachers(1.0 / 60.0)
	c.set_firewall(true)
	c.contacts.erase(mh)
	c._update_firewall(0.016)
	check(not c.firewall_active, "A firewall raised by hand still lowers at once when the hack ends")

	# --- 5. Interceptor squadrons ---
	clean()
	c.launch_interceptors()
	var interceptors: Array = c.contacts.filter(func(x: Dictionary) -> bool: return x.kind == "interceptor")
	check(interceptors.size() == 2, "Two Interceptors launched")
	interceptors[0].position = Vector3(0.0, -0.3, 0.0)
	interceptors[1].position = Vector3(0.04, -0.3, 0.0)
	c._update_interceptor_squadrons()
	check(c.interceptor_squadrons.size() == 1 and c.interceptor_squadrons[0].size() == 2, "Interceptors flying together show as one Interceptor Squadron")
	check(c.count_interceptors() == 2 and c.count_kind("interceptor") == 2, "INTERCEPTORS ACTIVE still counts each Interceptor")
	# 1.07: split distance 0.06 from the centre (was 0.12), so 0.10 apart still holds.
	interceptors[1].position = Vector3(0.10, -0.3, 0.0)
	c._update_interceptor_squadrons()
	check(c.interceptor_squadrons.size() == 1, "They stay grouped while within the split distance (no flicker)")
	interceptors[1].position = Vector3(0.30, -0.3, 0.0)
	c._update_interceptor_squadrons()
	check(c.interceptor_squadrons.is_empty(), "They split into single Interceptors once apart")
	interceptors[1].position = Vector3(0.10, -0.3, 0.0)
	c._update_interceptor_squadrons()
	check(c.interceptor_squadrons.is_empty(), "They do not regroup until close again (join and split distances differ)")
	interceptors[1].position = Vector3(0.05, -0.3, 0.0)
	c._update_interceptor_squadrons()
	check(c.interceptor_squadrons.size() == 1 and c.find_contact(interceptors[0].id).has("health") and c.find_contact(interceptors[1].id).has("health"), "Each Interceptor stays its own contact with its own health inside a squadron")
	interceptors[0].phase = "return"
	c._update_interceptor_squadrons()
	check(c.interceptor_squadrons.is_empty(), "A returning Interceptor leaves the squadron so its RTB flash stays visible")
	c.interceptor_squadrons_enabled = false
	interceptors[0].phase = "intercept"
	c._update_interceptor_squadrons()
	check(c.interceptor_squadrons.is_empty(), "Squadron grouping can be switched off in the Inspector")
	c.interceptor_squadrons_enabled = true
	# Battle simulation: grouping changes stay calm.
	clean()
	c.rng.seed = 11
	c.auto_spawn = true
	c.carrier_weapons_enabled = true
	var changes := 0
	var grouped_frames := 0
	var previous := ""
	for frame in range(60 * 120):
		if frame % 600 == 0 and c.count_interceptors() < 4:
			c.launch_interceptors()
		c._process(1.0 / 60.0)
		var key := str(c.interceptor_squadrons)
		if key != previous:
			changes += 1
			previous = key
		if not c.interceptor_squadrons.is_empty():
			grouped_frames += 1
	print("SQUADRON_SIMULATION seconds=120 changes=", changes, " grouped_seconds=%.1f" % (grouped_frames / 60.0))
	check(grouped_frames > 0, "Squadrons appear in a normal battle")
	check(changes <= 60, "Squadrons change at most about once every 2 seconds on average (%d changes in 2 minutes)" % changes)
	c.auto_spawn = false
	clean()

	print("V102_RESULT checks=", checks, " failures=", failures)
	for p in console.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
	for f in ["user://v102_test_settings.cfg", "user://v102_test_scores.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	console.free()
	await create_timer(0.3).timeout
	call_deferred("quit", 0 if failures == 0 else 1)

func near(a: float, b: float, tolerance := 0.02) -> bool:
	return absf(a - b) <= tolerance
