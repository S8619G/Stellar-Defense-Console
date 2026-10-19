extends SceneTree
## Live geometry, exact shared colours, screen pixels and Shield rename.
var checks := 0
var failures := 0
var console: Control
var c: Control
var frame: Control
var ship: Control
var capture_folder := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func frames(count: int = 4) -> void:
	for i in range(count):
		await process_frame

func _run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		capture_folder = OS.get_cmdline_user_args()[0]
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://verify_hull_shield.cfg"
	console.high_score_file = "user://verify_hull_shield_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.auto_spawn = false
	c.klaxon_enabled = false
	root.add_child(console)
	root.size = Vector2i(1600, 900)
	await frames(8)
	c.reset_battle()
	c.set_process(false)
	frame = console.get_node("ConsoleFrame")
	ship = console.get_node("ShipStatus")
	c.hit_flash_remaining = 0
	c.rapid_repair_remaining = 0
	check(frame.console_layout_v2, "Current console uses the live hull gauge")
	check(is_equal_approx(frame.hull_gauge_width, 16.0), "Hull gauge is 16 reference pixels, up from 10")
	for fraction in [1.0, .65, .5, .3, .15, 0.0]:
		c.hull = c.max_hull * fraction
		await frames()
		var gauge: Rect2 = frame.hull_gauge_rect()
		var fill: Rect2 = frame.hull_gauge_fill_rect()
		var inner := gauge.grow(-0.5 * frame._frame_scale())
		check(is_equal_approx(gauge.size.x / frame._frame_scale(), 16.0), "Gauge width scales at hull %.2f" % fraction)
		check(is_equal_approx(fill.size.y, inner.size.y * fraction), "Fill height matches actual hull %.2f" % fraction)
		check(is_equal_approx(fill.end.y, inner.end.y), "Fill remains bottom-aligned at hull %.2f" % fraction)
		check(frame.hull_gauge_color().is_equal_approx(ship.damage_color(fraction)), "Gauge and ship share condition colour at hull %.2f" % fraction)
		if fraction > 0:
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var point := root.get_final_transform() * (frame.global_position + fill.get_center())
			var pixel := image.get_pixel(int(point.x), int(point.y))
			var expected: Color = frame.hull_gauge_color()
			check(absf(pixel.r - expected.r) + absf(pixel.g - expected.g) + absf(pixel.b - expected.b) < .04, "Rendered gauge pixels match live colour at hull %.2f" % fraction)
			if not capture_folder.is_empty() and fraction in [1.0, .5, .15]:
				image.save_png(capture_folder.path_join("hull_%03d.png" % int(round(fraction * 100))))
	c.hull = c.max_hull * .5
	c.rapid_repair_remaining = 1.0
	c.battle_time = .125
	check(frame.hull_gauge_color().is_equal_approx(ship.hull_display_color()), "Repair pulse is shared with ship")
	check(not frame.hull_gauge_color().is_equal_approx(ship.damage_color(.5)), "Repair pulse actually changes the shared colour")
	c.hit_flash_remaining = .2
	check(frame.hull_gauge_color().is_equal_approx(Color("#ff243f")), "Damage flash is shared with ship")
	c.hit_flash_remaining = 0
	c.rapid_repair_remaining = 0
	for amount in [-10.0, c.max_hull * 2]:
		c.hull = amount
		var fill: Rect2 = frame.hull_gauge_fill_rect()
		var inner: Rect2 = frame.hull_gauge_rect().grow(-0.5 * frame._frame_scale())
		check(fill.size.y >= 0 and fill.size.y <= inner.size.y, "Out-of-range hull is safely clamped")
	c.hull = c.max_hull
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		await frames(8)
		check(is_equal_approx(frame.hull_gauge_rect().size.x / frame._frame_scale(), 16.0), "Width preserved at " + str(dimensions))
		check(frame.hull_gauge_rect().encloses(frame.hull_gauge_fill_rect()), "Fill stays inside border at " + str(dimensions))
	c.prox_active = false
	console._process(0)
	check(console.prox_button.text.begins_with("DEFENSE SHIELD"), "Main defense control uses new name")
	for path in ["ConsoleFrame", "RadarConsole", "RadarContacts", "SettingsPanel", "ShipStatus"]:
		var text := FileAccess.get_file_as_string("res://scripts/" + path + ".gd").to_upper()
		check(not text.contains("DEFENSE BATTERY"), "No old player-visible phrase in " + path)
	check(FileAccess.get_file_as_string("res://scripts/SettingsPanel.gd").contains("AUTO DEFENSE SHIELD"), "Auto setting uses Defense Shield")
	check(c.BONUS_LABELS.get("AUTO SHIELD") == "FREE AUTO SHIELD", "Bonus label uses Shield")
	c.auto_defense_battery = false
	c.active_boosts = {"AUTO SHIELD": true}
	check(c.battery_auto_on(), "Renamed auto-shield bonus still activates existing defense")
	c.active_boosts = {}
	check(not c.battery_auto_on(), "Bonus expiration still clears automatic defense")
	var Settings = load("res://scripts/GameSettings.gd")
	check(Settings.clean({"auto_battery": true}).auto_battery, "Existing saved auto-defense setting remains compatible")
	print("HULL_SHIELD_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	console.queue_free()
	await frames()
	await create_timer(.2).timeout
	quit(1 if failures else 0)
