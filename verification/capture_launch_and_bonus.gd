extends SceneTree
## 1.0.5 / 1.0.6 screenshots: the launch buttons (N READY, READY IN, ALL DEPLOYED, AUTO) and the
## missile bonus pick pop-up (countdown, waiting after input, after-set offer). Usage:
##   godot --path . --script res://verification/capture_launch_and_bonus.gd -- <folder> [width] [height]
var folder := ""
var console: Control
var c: Control

func _initialize() -> void:
	call_deferred("_run")

func grab(name: String) -> void:
	console._process(0.0)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(folder.path_join(name + ".png"))
	print("CAPTURE ", name, " ", image.get_size())

func tick(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		c._tick_waits(c.interceptor_waits, c.interceptors_in_hangar(), 0.05)
		c._tick_waits(c.gunship_waits, c.gunships_in_hangar(), 0.05)
		t += 0.05

func land(kind: String) -> void:
	for ship in c.contacts:
		if ship.kind == kind:
			ship.phase = "return"
			ship.position = c.launch_origin(ship.lane)
			break
	if kind == "gunship":
		c._update_gunships(0.0)
	else:
		c._update_interceptors(0.0)

func park_out() -> void:
	# Keep launched ships still on the scope for the picture.
	for ship in c.contacts:
		if ship.kind in ["interceptor", "gunship"] and ship.phase != "return":
			ship.phase = "patrol"

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	folder = args[0]
	var size := Vector2i(1600, 900)
	if args.size() >= 3:
		size = Vector2i(int(args[1]), int(args[2]))
	var suffix := "" if size == Vector2i(1600, 900) else "_%dx%d" % [size.x, size.y]
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://capture_launch.cfg"
	console.high_score_file = "user://capture_launch_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.launch_sound_enabled = false
	c.arrival_sound_enabled = false
	c.auto_spawn = false
	root.add_child(console)
	root.size = size
	DisplayServer.window_set_size(size)
	for i in range(8):
		await process_frame
	c.reset_battle()
	c.set_process(false)
	c.safe_remaining = 0.0
	if suffix == "":
		await grab("01_launch_start_2_ready")
		c.launch_interceptors()
		c.launch_gunship()
		park_out()
		await grab("02_after_press_ready_in")
		tick(4.05)
		# 1.0.6: 4 left in the hangar, the button shows the next 2.
		await grab("02b_next_two_ready")
		c.launch_interceptors()
		tick(4.05)
		c.launch_interceptors()
		tick(4.05)
		c.launch_gunship()
		park_out()
		await grab("03_all_deployed")
		land("interceptor")
		land("gunship")
		await grab("04_one_landed_ready_in")
		tick(3.05)
		await grab("05_landed_one_ready")
		c.auto_launch_interceptors = true
		c.auto_launch_gunships = true
		await grab("06_auto_tag")
		c.auto_launch_interceptors = false
		c.auto_launch_gunships = false
	# 1.0.6: a bonus earned during a wave is held for the end of the round.
	if suffix == "":
		c.difficulty = 1
		c.active_difficulty = 1
		c.auto_spawn = true
		c.waves_enabled = true
		c.wave_phase = "assault"
		c._add_points(17500)
		await grab("06b_bonus_held_status_line")
		c.auto_spawn = false
		c.missile_bonus_offer_waiting = false
	# Bonus pick pop-up.
	c.missile_bonus_offer_open = true
	console.open_bonus_pick("RAPID", "DOUBLE", false)
	await grab("07_bonus_countdown_default" + suffix)
	var panel: Control = console.bonus_pick_panel
	panel._process(7.2)
	await grab("08_bonus_countdown_12s" + suffix)
	panel.stop_countdown("mouse")
	panel.cards[1].grab_focus()
	await grab("09_bonus_waiting_other_highlighted" + suffix)
	panel.pick_card(0)
	await process_frame
	c.missile_bonus_offer_open = true
	console.open_bonus_pick("DOUBLE", "RAPID", true)
	await grab("10_bonus_after_set" + suffix)
	panel.pick_card(0)
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.2).timeout
	console.free()
	await create_timer(0.2).timeout
	quit(0)
