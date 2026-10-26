extends SceneTree
## 1.1.0 redraw check: the console frame and the ship are rebuilt only when what they
## show changes. At many moments of seeded battles this compares the screen the player
## sees with a full rebuild of both, pixel for pixel. Needs a display (xvfb-run).
## RD_OUT = folder for pictures of any mismatch (optional). RD_FRAMES = frames per battle.
var console: Control
var c: Control
var frame: Control
var ship: Control
var checks := 0
var failures := 0
var moments := 0
var out_dir := ""

func _initialize() -> void:
	call_deferred("_run")

func ok(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)

func frames(n: int = 1) -> void:
	for i in range(n):
		await process_frame

func shot() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func fresh(level: int, autos: bool, seed: int) -> void:
	if console != null:
		console.queue_free()
		await frames(2)
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://redraw110.cfg"
	console.high_score_file = "user://redraw110.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	root.add_child(console)
	frame = console.get_node("ConsoleFrame")
	ship = console.get_node("ShipStatus")
	frame.nav_seed = 1100
	await frames(3)
	c.difficulty = level
	for p in c.get_property_list():
		var n := String(p.name)
		if n.begins_with("auto_") and n != "auto_spawn" and p.type == TYPE_BOOL:
			c.set(n, autos)
	c.rng.seed = seed
	c.reset_battle()
	await frames(2)

## What the player sees now against a full rebuild of the same moment.
func compare(label: String) -> void:
	var seen := await shot()
	paused = true
	frame.queue_redraw()
	frame.fade_layer.queue_redraw()
	ship.queue_redraw()
	await frames(1)
	var full := await shot()
	paused = false
	moments += 1
	var same := seen.get_data() == full.get_data()
	checks += 1
	if not same:
		failures += 1
		print("FAIL redraw matches a full rebuild: ", label)
		if out_dir != "":
			seen.save_png("%s/%s_seen.png" % [out_dir, label.replace(" ", "_")])
			full.save_png("%s/%s_full.png" % [out_dir, label.replace(" ", "_")])

func battle_run(label: String, level: int, seed: int, total: int, every: int) -> void:
	await fresh(level, true, seed)
	c.auto_spawn = true
	var before := failures
	var start_frame: int = frame.redraw_count
	var start_ship: int = ship.redraw_count
	var start_moments := moments
	for i in range(total):
		await frames(1)
		if i % every == every - 1:
			await compare("%s frame %d" % [label, i])
	var shown := total + 2 * (moments - start_moments)
	ok(failures == before, "%s: %d moments match a full rebuild pixel for pixel" % [label, moments - start_moments])
	print("INFO %s: console frame rebuilt %d of %d frames, ship %d" % [label, frame.redraw_count - start_frame, shown, ship.redraw_count - start_ship])

func _run() -> void:
	out_dir = OS.get_environment("RD_OUT")
	var total := int(OS.get_environment("RD_FRAMES")) if OS.get_environment("RD_FRAMES") != "" else 300
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await frames(4)
	Engine.time_scale = 3.0
	# Seeded all-auto battles on Easy, Normal and Hard.
	await battle_run("Easy seed 7", 0, 7, total, 3)
	await battle_run("Normal seed 11", 1, 11, total, 3)
	await battle_run("Hard seed 4242", 2, 4242, total, 3)
	Engine.time_scale = 1.0

	# Still screen: nothing changes, so the frame is not rebuilt every frame.
	await fresh(1, false, 3)
	c.auto_spawn = false
	c.waves_enabled = false
	frame.panel_animation_enabled = false
	# No safety rebuild during this count (slow test displays draw only a few frames a second).
	frame.redraw_safety_seconds = 5.0
	ship.redraw_safety_seconds = 5.0
	Engine.time_scale = 0.1
	await frames(30)
	var f0: int = frame.redraw_count
	var s0: int = ship.redraw_count
	await frames(30)
	ok(frame.redraw_count - f0 <= 3, "still screen: console frame rebuilt %d times in 30 frames" % (frame.redraw_count - f0))
	ok(ship.redraw_count - s0 <= 3, "still screen: ship rebuilt %d times in 30 frames" % (ship.redraw_count - s0))
	Engine.time_scale = 1.0
	frame.redraw_safety_seconds = 1.0
	ship.redraw_safety_seconds = 1.0
	await compare("still screen")
	# The fading light still fades while the frame stays still.
	frame.panel_animation_enabled = true
	await frames(5)
	var fade_a: float = frame.panel_fade_amount()
	await frames(20)
	ok(not is_equal_approx(fade_a, frame.panel_fade_amount()) and frame._fade_rect.size.x > 0.0, "fading light keeps fading on its own layer")
	await compare("fading light")
	# Safety net: a full rebuild at least once a second.
	frame.panel_animation_enabled = false
	f0 = frame.redraw_count
	await create_timer(1.3).timeout
	ok(frame.redraw_count - f0 >= 1, "safety rebuild within a second")

	# Each value change shows on the very next picture.
	c.score = 46000
	await frames(1)
	await compare("score change")
	ok(c.jump_cost_now() == 4600, "JUMP cost value changed for the check")
	c.repair_charges = 3
	await frames(1)
	await compare("repair charges change")
	c.hull = c.max_hull * 0.04
	for i in range(20):
		await frames(1)
		if i % 3 == 0:
			await compare("low hull flash %d" % i)
	c.hull = c.max_hull * 0.5
	c.repair_charges = 2
	ok(c.request_rapid_repair(), "Rapid Repair started for the check")
	for i in range(12):
		await frames(1)
		if i % 3 == 0:
			await compare("rapid repair %d" % i)
	# Window size change rebuilds both.
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await frames(4)
	await compare("window 1280x720")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await frames(4)
	await compare("window 1600x900")
	# Redraw switched off = every frame (the 1.0.9 way).
	frame.redraw_only_changes = false
	ship.redraw_only_changes = false
	f0 = frame.redraw_count
	s0 = ship.redraw_count
	await frames(20)
	ok(frame.redraw_count - f0 >= 19 and ship.redraw_count - s0 >= 19, "switched off: rebuilt every frame")
	await compare("switched off")
	frame.redraw_only_changes = true
	ship.redraw_only_changes = true

	# Ship destroyed: the end screen with the SYSTEMS OFFLINE list.
	await fresh(1, false, 5)
	c.apply_damage(c.max_hull * 2.0)
	ok(c.is_defeated(), "ship destroyed for the check")
	for i in range(30):
		await frames(1)
		if i % 3 == 0:
			await compare("ship destroyed %d" % i)

	ok(moments >= 300, "%d moments compared" % moments)
	console.queue_free()
	await frames(2)
	print("REDRAW_RESULT checks=%d failures=%d moments=%d" % [checks, failures, moments])
	quit(1 if failures > 0 else 0)
