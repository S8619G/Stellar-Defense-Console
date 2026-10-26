extends SceneTree
## 1.0.0: approved hull percentage and tighter fill (design/hull-indicator-0.1.2/mockup-02),
## plus the 1.0.0 version and full-version export file names.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func frames(n: int = 5) -> void:
	for i in range(n):
		await process_frame

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_versions_and_names()
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://verify_hull_percent.cfg"
	console.high_score_file = "user://verify_hull_percent_scores.json"
	console.controller_file = "user://verify_hull_percent_controller.cfg"
	console.shell_dry_run = true
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	c.auto_spawn = false
	c.klaxon_enabled = false
	root.add_child(console)
	root.size = Vector2i(1600, 900)
	await frames(8)
	c.reset_battle()
	c.set_process(false)
	c.hit_flash_remaining = 0.0
	c.rapid_repair_remaining = 0.0
	var frame: Control = console.get_node("ConsoleFrame")
	var k: float = frame._frame_scale()
	var gauge0: Rect2 = frame.hull_gauge_rect()
	check(is_equal_approx(gauge0.end.y, frame._mock(0.0, frame.V2_ALERT_TOP - 18.0).y), "Bar ends 18 reference pixels above the alert box")
	check(is_equal_approx(gauge0.position.y, frame._mock(0.0, frame.V2_TAB_TOP + 16.0).y), "Bar top is unchanged")
	check(is_equal_approx(gauge0.size.x / k, 16.0), "Bar width is unchanged (16 reference pixels)")
	for fraction in [1.0, .5, .15, 0.0]:
		c.hull = c.max_hull * fraction
		await frames()
		var gauge: Rect2 = frame.hull_gauge_rect()
		var fill: Rect2 = frame.hull_gauge_fill_rect()
		var inner := gauge.grow(-0.5 * k)
		var percent: Rect2 = frame.hull_percent_rect()
		var tag := " at %d%%" % int(round(100 * fraction))
		check(frame.hull_percent_text() == "%d%%" % int(round(100 * fraction)), "Percentage reads" + tag)
		check(percent.position.y > gauge.end.y, "Percentage clears the bar" + tag)
		check(percent.end.y < frame._mock(0.0, frame.V2_ALERT_TOP).y, "Percentage clears the alert box" + tag)
		check(percent.position.x > frame._mock(frame.V2_PANEL_OUTER_L, 0.0).x, "Percentage stays inside the panel" + tag)
		check(absf(percent.get_center().x - gauge.get_center().x) < 1.0, "Percentage centred under the bar" + tag)
		check(is_equal_approx(fill.size.y, inner.size.y * fraction), "Fill height matches hull" + tag)
		check(is_equal_approx(fill.position.x, inner.position.x) and is_equal_approx(fill.size.x, inner.size.x), "Fill reaches the inner edge of the border" + tag)
		check(is_equal_approx(fill.end.y, inner.end.y), "Fill stays bottom-aligned" + tag)
	# Rounding.
	c.hull = c.max_hull * 0.996
	check(frame.hull_percent_text() == "100%", "99.6% rounds to 100%")
	c.hull = c.max_hull * 0.004
	check(frame.hull_percent_text() == "0%", "0.4% rounds to 0%")
	c.hull = -50.0
	check(frame.hull_percent_text() == "0%", "Below zero still shows 0%")
	c.hull = c.max_hull
	# Border drawn after the fill (source order in the draw routine).
	var source := FileAccess.get_file_as_string("res://scripts/ConsoleFrame.gd")
	var fill_at := source.find("draw_rect(gauge_fill")
	var border_at := source.find("draw_rect(hull_gauge_rect(), gauge_line, false")
	check(fill_at != -1 and border_at > fill_at, "Border is drawn last, over the fill")
	check(source.contains("hull_percent_text(),") and source.contains(", TEXT)"), "Percentage uses the neutral text colour")
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		await frames(8)
		var percent: Rect2 = frame.hull_percent_rect()
		check(percent.position.y > frame.hull_gauge_rect().end.y, "Percentage clears the bar at %s" % str(dimensions))
		check(percent.end.y < frame._mock(0.0, frame.V2_ALERT_TOP).y, "Percentage clears the alert box at %s" % str(dimensions))
		check(frame.hull_percent_font_size() >= 8, "Percentage text stays readable at %s" % str(dimensions))
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var fill: Rect2 = frame.hull_gauge_fill_rect()
		var point := root.get_final_transform() * (frame.global_position + fill.get_center())
		var pixel := image.get_pixel(int(point.x), int(point.y))
		check(Vector3(pixel.r - frame.hull_gauge_color().r, pixel.g - frame.hull_gauge_color().g, pixel.b - frame.hull_gauge_color().b).length() < 0.08, "Fill colour on screen at %s" % str(dimensions))
	print("HULL_PERCENTAGE_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	console.queue_free()
	await frames()
	for path in ["user://verify_hull_percent.cfg", "user://verify_hull_percent_scores.json", "user://verify_hull_percent_controller.cfg"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await create_timer(.2).timeout
	quit(1 if failures else 0)

func _versions_and_names() -> void:
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 1.1.1")
	var presets := ConfigFile.new()
	check(presets.load("res://export_presets.cfg") == OK, "Export presets load")
	var linux := ""
	var paths := []
	for section in presets.get_sections():
		if section.ends_with(".options") or not presets.has_section_key(section, "export_path"):
			continue
		var path: String = presets.get_value(section, "export_path")
		paths.append(path)
		if str(presets.get_value(section, "platform", "")) == "Linux":
			linux = path
	check(linux.get_file() == "Stellar_Defense_Console_1.1.1_Linux.x86_64", "Linux file name keeps the full version (Stellar_Defense_Console_1.1.1_Linux.x86_64)")
	check(linux.get_extension() == "x86_64" and linux.get_file().get_basename() == "Stellar_Defense_Console_1.1.1_Linux", "Linux extension is .x86_64, so the export dialog keeps the full version")
	var all_ok := paths.size() == 4
	for path in paths:
		if not str(path).get_file().begins_with("Stellar_Defense_Console_1.1.1_"):
			all_ok = false
	check(all_ok, "All four export file names start Stellar_Defense_Console_1.1.1_")
	var versions_ok := true
	for section in presets.get_sections():
		for key in presets.get_section_keys(section):
			if key.ends_with("file_version") or key.ends_with("product_version"):
				versions_ok = versions_ok and presets.get_value(section, key) == "1.1.1"
			elif key == "application/short_version" or key == "application/version":
				versions_ok = versions_ok and presets.get_value(section, key) == "1.1.1"
	check(versions_ok, "Windows and Mac version fields are 1.1.1")
