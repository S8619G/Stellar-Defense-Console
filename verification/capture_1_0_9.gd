extends SceneTree
## 1.0.9 in-game review captures (screens and video frames) from the real 1.0.9 code.
## Args: <folder> <boxes|typing|lowhull>
const HighScores = preload("res://scripts/HighScores.gd")
const FPS := 30.0
var folder := ""
var console: Control
var c: Control
var fx: Control

func _initialize() -> void:
	call_deferred("_run")

func save(name: String) -> void:
	c.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))
	print("CAPTURE ", name)

func make_console(tag: String) -> void:
	for f in ["user://cap_%s.cfg" % tag, "user://cap_%s_scores.json" % tag]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var scores := []
	var names := ["KJR", "AMB", "TLC", "SRG", "DNW", "PEX", "LOU", "MAV"]
	for i in names.size():
		HighScores.insert(scores, names[i], 48000 - i * 5200, 14 - i, 10, ["N", "H", "N", "E"][i % 4],
			{"drone": 120 - i * 9, "breacher": 30 - i * 2, "missile": 200 - i * 15, "nuke": 12 - i, "carrier": 6 - i / 2, "siege_ship": 2, "waves_cleared": 13 - i, "sets": 2})
	HighScores.save_board("user://cap_%s_scores.json" % tag, scores, "SRG")
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://cap_%s.cfg" % tag
	console.high_score_file = "user://cap_%s_scores.json" % tag
	console.shell_dry_run = true
	console.quit_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	root.add_child(console)
	root.size = Vector2i(1600, 900)
	fx = console.damage_effects
	fx.rng.seed = 4101
	await process_frame

func _run() -> void:
	folder = OS.get_cmdline_user_args()[0]
	var mode: String = OS.get_cmdline_user_args()[1]
	DirAccess.make_dir_recursive_absolute(folder)
	await make_console(mode)
	if mode == "boxes":
		await boxes()
	elif mode == "typing":
		await typing()
	elif mode == "lowhull":
		await lowhull()
	quit()

func step(n: int) -> void:
	for i in n:
		c.hull = c.max_hull
		c._process(1.0 / 30.0)
		console._process(1.0 / 30.0)

func boxes() -> void:
	c.difficulty = 1
	c.reset_battle()
	c.rng.seed = 11
	c.auto_launch_interceptors = true
	c.auto_launch_gunships = true
	c.auto_defense_battery = true
	c.auto_firewall = true
	c.set_process(false)
	var done := {}
	var sweep_started := false
	var picked := false
	var n := 0
	while n < 80000 and not (done.has("1_wave_cleared") and done.has("2_set_complete") and done.has("3_bonus_sweep_result") and done.has("4_convoy_result")):
		step(1); n += 1
		if console.bonus_pick_panel.is_open():
			if not picked:
				picked = true
				await process_frame
				await save("5_bonus_pick_cards")
			console.bonus_pick_panel.pick_card(1)
			await process_frame
			continue
		if done.has("4_convoy_result") and not sweep_started and c.wave_phase == "rest" and not c.rest_after_protect:
			c.wave_next_phase = "sweep"
			sweep_started = true
			print("SWEEP NEXT at ", n)
		if sweep_started and n % 300 == 0 and not done.has("3_bonus_sweep_result"):
			print("phase ", c.wave_phase, " next ", c.wave_next_phase)
		var lines: Array[String] = c.rest_tally_lines()
		if lines.is_empty():
			continue
		var key := ""
		if c.rest_after_protect: key = "4_convoy_result"
		elif lines[0].begins_with("BONUS SWEEP"): key = "3_bonus_sweep_result"
		elif lines.any(func(l): return l.contains("COMPLETE  |  SCORE")): key = "2_set_complete"
		elif lines[0].begins_with("WAVE"): key = "1_wave_cleared"
		if key == "" and not done.has("dbg_" + lines[0].left(12)):
			done["dbg_" + lines[0].left(12)] = true
			print("UNMATCHED ", c.wave_phase, " ", lines)
		if key == "" or done.has(key):
			continue
		step(100)
		if console.bonus_pick_panel.is_open():
			continue
		done[key] = true
		print("step ", n, " ", key, " ", c.rest_tally_lines())
		await save(key)
	if not picked:
		# The pick card pop-up: show it directly with Normal values.
		console.open_bonus_pick("RAPID", "DOUBLE", false)
		await process_frame
		await save("5_bonus_pick_cards")
		console.bonus_pick_panel.pick_card(0)
		await process_frame
	c.score = 21350
	c.hull = 0.0
	console._process(0.0)
	fx._update(0.0)
	fx.set_process(false)
	fx.destroyed_time = 6.0
	fx._update(0.0)
	console._process(0.0)
	console.show_score_stats_for(-1)
	await save("6_game_over")
	console.show_score_stats_for(1)
	await save("7_game_over_stats")

func warmup() -> void:
	c.difficulty = 1
	c.reset_battle()
	c.rng.seed = 7
	for i in range(900):
		c._process(1.0 / FPS)
		if i % 150 == 0:
			c.spawn_contact("interceptor", "friendly")
	c.set_process(false)
	fx.set_process(false)
	console.set_process(false)
	console.dome.set_process(false)

func typing() -> void:
	warmup()
	c.hull = c.max_hull
	c.score = 21350
	var t := 0.0
	var n := 0
	var did := false
	while t < 15.0:
		var dt := 1.0 / FPS
		if not did:
			c._process(dt)
			c.hull = c.max_hull
		if t >= 1.0 and not did:
			did = true
			c.hull = 0.0
		console._process(dt)
		fx._update(dt)
		console.dome._time += dt
		console.dome.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("f%04d.png" % n))
		n += 1
		t += dt
	print("VIDEO_FRAMES ", n)

func lowhull() -> void:
	warmup()
	var frame: Control = console.get_node("ConsoleFrame")
	frame.set_process(false)
	var t := 0.0
	var n := 0
	var length := float(OS.get_environment("LH_LENGTH")) if OS.get_environment("LH_LENGTH") != "" else 14.0
	while t < length:
		var dt := 1.0 / FPS
		c._process(dt)
		# 20% for 2.5 s, then 5% (warning on), then repaired to 8% at 11 s (warning off).
		c.hull = c.max_hull * (0.20 if t < 2.5 else (0.05 if t < 11.0 else 0.08))
		console._process(dt)
		fx.hit_time = -1.0
		console.screen_flash.color.a = 0.0
		fx._update(dt)
		frame._process(dt)
		frame.queue_redraw()
		console.dome._time += dt
		console.dome.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("f%04d.png" % n))
		n += 1
		t += dt
	print("VIDEO_FRAMES ", n)
