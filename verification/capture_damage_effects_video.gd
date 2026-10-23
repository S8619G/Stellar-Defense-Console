extends SceneTree
## 1.0.8: frame-by-frame video capture of the damage effects in the real game (review only).
## Usage: godot --path . --script res://verification/capture_damage_effects_video.gd -- <folder> <WxH>
## Timeline: 0-1.5 s battle, full nuke hit at 1.5 s, Defense Shield partial hit at 4.0 s,
## ship destroyed at 6.0 s, score screen in front at 9.0 s, then 9 s more of the red screen.
const FPS := 30.0
const FULL_HIT := 1.5
const PARTIAL_HIT := 4.0
const DESTROYED := 6.0
const LENGTH := 18.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var folder: String = OS.get_cmdline_user_args()[0]
	var dims: PackedStringArray = OS.get_cmdline_user_args()[1].split("x")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_fx_video.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_fx_video_scores.json"))
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://capture_fx_video.cfg"
	console.high_score_file = "user://capture_fx_video_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	root.add_child(console)
	root.size = Vector2i(int(dims[0]), int(dims[1]))
	var fx: Control = console.damage_effects
	fx.rng.seed = 4101
	c.difficulty = 1
	c.reset_battle()
	c.rng.seed = 7
	for i in range(900):
		c._process(1.0 / FPS)
		if i % 150 == 0:
			c.spawn_contact("interceptor", "friendly")
	c.hull = c.max_hull
	c.set_process(false)
	fx.set_process(false)
	console.set_process(false)
	var dome: Control = console.dome
	dome.set_process(false)
	var frame := 0
	var t := 0.0
	var did_full := false
	var did_partial := false
	var did_destroy := false
	while t < LENGTH:
		var dt := 1.0 / FPS
		if not did_destroy:
			c._process(dt)
			c.hull = maxf(c.hull, c.max_hull * 0.5)
		if t >= FULL_HIT and not did_full:
			did_full = true
			fx.nuke_hit(true)
			console.screen_flash.color.a = 0.0
		if t >= PARTIAL_HIT and not did_partial:
			did_partial = true
			fx.nuke_hit(false)
		if t >= DESTROYED and not did_destroy:
			did_destroy = true
			c.hull = 0.0
		console._process(dt)
		fx._update(dt)
		dome._time += dt
		dome.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("f%04d.png" % frame))
		frame += 1
		t += dt
	print("VIDEO_FRAMES ", frame)
	console.queue_free()
	quit()
