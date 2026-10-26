extends SceneTree
## 1.1.0 in-game captures of each change. CAP_DIR = output folder, CAP_W / CAP_H = window.
## Run with a display (for example xvfb-run with a screen larger than the window).
var console: Control
var c: Control
var ship: Control
var dir := ""
var tag := ""

func _initialize() -> void:
	call_deferred("_run")

func frames(n: int = 4) -> void:
	for i in range(n):
		await process_frame

func save(name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [dir, name, tag])
	print("saved ", name, " ", img.get_size())

func fresh(level: int) -> void:
	if console != null:
		console.queue_free()
		await frames(2)
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://cap110_%s.cfg" % tag
	console.high_score_file = "user://cap110_%s.json" % tag
	console.quit_dry_run = true
	console.shell_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	root.add_child(console)
	ship = console.get_node("ShipStatus")
	await frames(3)
	c.difficulty = level
	c.auto_spawn = false
	c.waves_enabled = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.siege_enabled = false
	c.max_carriers = 3
	for p in c.get_property_list():
		if String(p.name).begins_with("auto_") and p.type == TYPE_BOOL:
			c.set(p.name, false)
	c.rng.seed = 110
	c.reset_battle()

func carrier(pos: Vector3) -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	b.position = pos
	b.drone_timer = 999.0
	b.missile_timer = 999.0
	b.heavy_timer = 999.0
	return b

func step(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		c._process(1.0 / 30.0)
		t += 1.0 / 30.0
	await frames(2)

func _run() -> void:
	dir = OS.get_environment("CAP_DIR")
	var w := int(OS.get_environment("CAP_W"))
	var h := int(OS.get_environment("CAP_H"))
	tag = "%dx%d" % [w, h]
	DisplayServer.window_set_size(Vector2i(w, h))
	await frames(4)
	# 1 and 2: DEFEND THE AEGIS and the JUMP cost at 46,000 points.
	await fresh(1)
	carrier(Vector3(-0.3, 0.6, 0.0))
	c.score = 46000
	c.earned_points = 46000
	await step(1.0)
	c.status_remaining = 0.0
	await step(0.1)
	await frames(120)
	c.status_remaining = 0.0
	await save("01_aegis_and_jump_cost")
	# 3: Rapid Repair limit reached, earning paused.
	await fresh(1)
	carrier(Vector3(0.3, 0.6, 0.0))
	c.hull = c.max_hull * 0.6
	# Limit of 4 reached (set directly, so no bonus pop-up covers the panel).
	c.earned_points = c.repair_bonus_threshold(4) + 2000
	c.score = c.earned_points
	c.repair_bonuses_earned = 4
	c.repair_charges = 4
	c.repair_earning_paused = true
	await step(0.5)
	c.status_remaining = 0.0
	await save("03_rapid_repair_paused")
	# 7: Interceptors going after a hacking Breacher.
	await fresh(1)
	var b := carrier(Vector3(0.0, 0.7, 0.0))
	var hk: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	hk.position = hk.hack_point
	c._update_breachers(0.0)
	var d: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	d.position = Vector3(-0.35, 0.1, 0.0)
	d.phase = "attack"
	c.launch_interceptors()
	await step(1.2)
	await save("07_interceptors_on_hacking_breacher")
	# 9: breach alert on the ship fill and INTRUSION DETECTION in NAV DATA.
	await save("09_breach_alert")
	# 8: PULSE BOMB held: NUKES and PULSE pills on the STEALTH WEAPON button.
	await pulse_scene(false)
	# 8: a nuclear missile caught in the area: slowed, with the ice-blue shimmer.
	await pulse_scene(true)
	quit(0)

func pulse_scene(with_nuke: bool) -> void:
	await fresh(1)
	# One PULSE BOMB charge held (set directly; a low score keeps the missile bonus pop-up away).
	c.earned_points = 6000
	c.score = 6000
	c.pulse_awards_earned = 1
	c.pulse_charges = 1
	var b1 := carrier(Vector3(-0.42, 0.45, 0.0))
	var b2 := carrier(Vector3(0.0, 0.62, 0.0))
	var b3 := carrier(Vector3(0.42, 0.42, 0.0))
	for k in [b1, b2, b3]:
		for i in 2:
			var dr: Dictionary = c.find_contact(c.spawn_from_carrier("drone", k.id))
			dr.position = k.position + Vector3(-0.1 + 0.2 * i, -0.16, 0.0)
			dr.phase = "attack"
	if not with_nuke:
		c.status_message = c.PULSE_EARNED_TEXT
		c.status_remaining = 4.0
		await step(0.2)
		await save("08a_pulse_bomb_earned_pills")
	var nuke_id := ""
	c.launch_stealth(true)
	var t := 0.0
	while t < 30.0 and c.pulse_detonations == 0:
		c._process(1.0 / 30.0)
		t += 1.0 / 30.0
		if with_nuke and nuke_id.is_empty() and not c.pulse_bombs.is_empty():
			# Launched as the bomb drops, so it is inside the area when the bomb goes off.
			nuke_id = c._launch_nuclear(b2)
	if with_nuke:
		await step(1.5)
		print("nuke slowed: ", c.find_contact(nuke_id).get("pulse_slowed", false))
		await save("08c_pulse_bomb_nuke_slowed")
		return
	await step(0.25)
	await save("08b_pulse_bomb_frozen")
	var guard := 0.0
	while guard < 12.0 and c.status_message != c.PULSE_ENDED_TEXT:
		c._process(1.0 / 30.0)
		guard += 1.0 / 30.0
	await frames(2)
	await save("08d_pulse_bomb_freeze_ended")
