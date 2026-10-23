extends SceneTree
## Plays a Protect the fleet round, pressing LAUNCH INTERCEPTORS whenever it is ready,
## saving screenshots and a per-second record of drones, Interceptors and civilian hull.
var console: Control
var c: Control
var folder := ""
var rows := []

func _initialize() -> void:
	call_deferred("_run")

func grab(name: String) -> void:
	console._process(0.0)
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func spread(kind: String) -> Array:
	var pts := []
	for k in c.contacts:
		if k.kind == kind and k.get("phase", "") != "return":
			pts.append(k.position)
	if pts.size() < 2:
		return [pts.size(), 0.0]
	var total := 0.0
	var n := 0
	for i in range(pts.size()):
		for j in range(i + 1, pts.size()):
			total += Vector2(pts[i].x, pts[i].y).distance_to(Vector2(pts[j].x, pts[j].y))
			n += 1
	return [pts.size(), total / n]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	folder = args[0]
	var seed := int(args[1]) if args.size() > 1 else 11
	var level := int(args[2]) if args.size() > 2 else 1
	var auto := args.size() > 3 and args[3] == "auto"
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://pp.cfg"
	console.high_score_file = "user://pp_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.launch_sound_enabled = false
	c.arrival_sound_enabled = false
	c.wave_cues_enabled = false
	root.add_child(console)
	await process_frame
	c.set_process(false)
	console.set_process(false)
	c.difficulty = level
	c.auto_launch_interceptors = auto
	c.rng.seed = seed
	c.reset_battle()
	c.contacts.clear()
	c.pending.clear()
	c.safe_remaining = 0.0
	c.sets_completed = int(args[4]) if args.size() > 4 else 1
	c.wave = 5 * c.sets_completed
	if args.size() > 5:
		c.protect_breacher_delay_min = float(args[5])
		c.protect_breacher_delay_max = float(args[5])
	c._start_protect()
	var step := 1.0 / 30.0
	var frame := 0
	var shot := 0
	while c.wave_phase == "protect" and frame < 30 * 150:
		if not auto and c.interceptors_next_launch() > 0:
			c.launch_interceptors()
		c._process(step)
		console._process(step)
		frame += 1
		if frame % 30 == 0:
			var hull := 0.0
			var attacking := 0
			var near := 0
			for k in c.contacts:
				if k.get("faction", "") == "civilian":
					hull += float(k.hull)
				if k.kind == "drone" and k.get("faction", "") == "hostile":
					if str(k.get("civ_target", "")) != "":
						attacking += 1
					for s in c.contacts:
						if s.get("faction", "") == "civilian" and Vector2(s.position.x, s.position.y).distance_to(Vector2(k.position.x, k.position.y)) < 0.18:
							near += 1
							break
			var ds := spread("drone")
			var vs := spread("interceptor")
			var phases := {}
			for k in c.contacts:
				if k.kind == "drone":
					phases[str(k.get("phase", ""))] = phases.get(str(k.get("phase", "")), 0) + 1
			rows.append("t=%3ds drones=%d (spread %.2f, with target %d, near a ship %d, phases %s) interceptors=%d (spread %.2f) civ_hull_sum=%.2f left=%d breacher=%s latched=%d bursts=%d" % [frame / 30, ds[0], ds[1], attacking, near, str(phases), vs[0], vs[1], hull, c.civilians_left(), str(c.convoy_breachers_left()), c.convoy_breachers_latched(), c.protect_bursts])
		if frame % 90 == 0:
			await grab("t%03d" % (frame / 30))
			shot += 1
	rows.append("end phase=%s elapsed=%.0f result=%s" % [c.wave_phase, c.protect_elapsed, str(c.get("last_protect_result"))])
	var f := FileAccess.open(folder.path_join("record.txt"), FileAccess.WRITE)
	f.store_string("\n".join(rows) + "\n")
	f.close()
	console.free()
	quit(0)
