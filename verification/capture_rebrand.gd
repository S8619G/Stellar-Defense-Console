extends SceneTree
var folder := ""

func _initialize() -> void:
	call_deferred("_run")

func grab(name: String) -> void:
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(folder.path_join(name + ".png"))
	print("CAPTURE ", name, " ", image.get_size())

func _run() -> void:
	folder = OS.get_cmdline_user_args()[0]
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://capture_rebrand.cfg"
	console.high_score_file = "user://capture_rebrand_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	root.add_child(console)
	root.size = Vector2i(1600,900)
	c.difficulty = 1
	c.reset_battle()
	c.rng.seed = 7
	for i in range(1500):
		c._process(1.0/30.0)
		if i % 150 == 0:
			c.spawn_contact("interceptor", "friendly")
	c.set_process(false)
	c.hull = c.max_hull
	c.hit_flash_remaining = 0.0
	console.dome.set_process(false)
	console.dome._time = .65
	console.dome.queue_redraw()
	await grab("console_healthy")
	c.hull = c.max_hull*.2
	c.prox_active = true
	await grab("console_damaged")
	c.hull = c.max_hull
	c.prox_active = false
	# Screenshot fixture only: expose the existing special-weapon housing.
	c.stealth_min_large_ships = 1
	c.stealth_cooldown_remaining = 0.0
	c.safe_remaining = 0.0
	await grab("console_stealth_ready")
	console.toggle_settings()
	await grab("settings")
	console.toggle_settings()
	c.missile_bonus_pick = "double"
	c.missile_bonus_offer_open = true
	console.open_bonus_pick("double", "rapid", false)
	await grab("bonus_prompt")
	console.queue_free()
	await process_frame
	quit()
