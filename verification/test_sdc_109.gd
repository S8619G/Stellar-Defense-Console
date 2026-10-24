extends SceneTree
## Stellar Defense Console 1.0.9: the four changes of this version.
## 1. Shared size, place and see-through look for the score and round boxes.
## 2. A slower, typed-out SYSTEMS OFFLINE list.
## 3. Low hull warning below 6%: flashing HULL bar plus a light screen flicker.
## 4. Rapid Missile balance (Normal every 5 s, Hard every 4 s, 20% faster) and the card text.
## Needs a display (the HULL bar colour is read from screen pixels).
const GameSettings = preload("res://scripts/GameSettings.gd")
var checks := 0
var failures := 0
var console: Control
var c: Control
var fx: Control
var frame: Control

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)
	print("PASS " if ok else "FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func frames(count: int = 3) -> void:
	for i in range(count):
		await process_frame

func shot() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func new_console(settings_name: String) -> void:
	if console != null:
		console.queue_free()
		await frames(2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://%s.cfg" % settings_name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://%s_scores.json" % settings_name))
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://%s.cfg" % settings_name
	console.high_score_file = "user://%s_scores.json" % settings_name
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
	frame = console.get_node("ConsoleFrame")
	await frames(4)

func quiet(level: int) -> void:
	c.difficulty = level
	c.auto_spawn = false
	c.waves_enabled = false
	c.own_weapons_enabled = false
	c.auto_defense_battery = false
	c.auto_firewall = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.reset_battle()
	c.set_process(false)

func _run() -> void:
	await new_console("verify_109")
	await _score_boxes()
	await _typed_list()
	await _low_hull()
	await _missiles()
	print("SDC_109_RESULT checks=%d failures=%d" % [checks, failures])
	console.queue_free()
	await frames(2)
	quit(1 if failures > 0 else 0)

# ---------------- 1. score and round boxes ----------------
func _score_boxes() -> void:
	var plain: Control = load("res://scripts/RadarContacts.gd").new()
	check(plain.shared_score_boxes == false, "Script default off: shared_score_boxes (1.0.8 boxes)")
	plain.free()
	check(c.shared_score_boxes and is_equal_approx(c.score_box_width, 600.0) and is_equal_approx(c.score_box_offset, -0.48), "Scene: shared round boxes on, 600 wide, upper scope place")
	check(is_equal_approx(c.score_box_opacity, 0.65) and is_equal_approx(c.score_box_background().a, 0.65), "Round boxes are 65% solid")
	var kinds := {
		"wave cleared": ["WAVE 3 CLEARED", "DESTROYED 12  |  +1,820", "BONUS +300", "NEXT  WAVE 4 IN 9"],
		"set complete": ["SET 1 COMPLETE", "WAVES 5 OF 5  |  +6,400", "SET BONUS +2,000", "NEXT  WAVE 6 PROBE IN 9"],
		"bonus sweep": ["BONUS SWEEP RESULT", "TARGETS DESTROYED 8 OF 10", "SWEEP BONUS +800", "NEXT  WAVE 11 IN 9"],
	}
	var rects := []
	c.rest_after_protect = false
	for kind in kinds:
		var lines: Array[String] = []
		lines.assign(kinds[kind])
		var rows: Array = c.score_box_rows(lines)
		rects.append(c.score_box_rect(rows))
		check(int(rows[0][1]) == 26 and int(rows[1][1]) == 16 and int(rows[2][1]) == 16, "%s: title 26, detail lines 16" % kind)
		var last: Color = rows[rows.size() - 1][2]
		check(last.r > 0.9 and last.g > 0.8 and last.b < 0.7, "%s: the NEXT line is yellow" % kind)
	# Convoy result: its own rows, same box.
	c.rest_after_protect = true
	c.last_protect_bonus = 1886
	var convoy_lines: Array[String] = ["SUPPORT FLEET SAVED", "SUPPORT HULL 76%  |  ATTACK DRONES DOWN 4 OF 4", "+1886", "CONVOY BONUS  |  FULL CONVOY", "NEXT  WAVE 6 PROBE IN 9"]
	var convoy_rows: Array = c.score_box_rows(convoy_lines)
	var convoy_rect: Rect2 = c.score_box_rect(convoy_rows)
	check(c.protect_result_rect(convoy_rows) == convoy_rect, "Convoy result uses the shared box")
	c.rest_after_protect = false
	var same := true
	for r in rects + [convoy_rect]:
		same = same and is_equal_approx(r.position.x, rects[0].position.x) and is_equal_approx(r.position.y, rects[0].position.y) and is_equal_approx(r.size.x, 600.0)
	check(same, "All four round boxes share one width (600) and top-left corner")
	check(is_equal_approx(rects[0].get_center().x, c.size.x * 0.5) and rects[0].get_center().y < c.size.y * 0.5, "Round boxes are centred in the upper scope")
	var game_over: Rect2 = console.game_over_panel.get_rect()
	check(is_equal_approx(game_over.size.x, 600.0), "Round box edges line up with the 600-wide Game Over screen")
	# Off: the 1.0.8 box comes back.
	c.shared_score_boxes = false
	c.rest_after_protect = true
	check(is_equal_approx(c.protect_result_rect(convoy_rows).size.x, 560.0), "Shared boxes off: the 1.0.8 560-wide convoy box")
	c.rest_after_protect = false
	c.shared_score_boxes = true
	# Game Over screen and stats box.
	var style: StyleBoxFlat = console.game_over_panel.get_theme_stylebox("panel")
	check(style != null and is_equal_approx(style.bg_color.a, 0.8), "Game Over screen is 80% solid (was 97%)")
	var stats_style: StyleBoxFlat = console.stats_box.get_theme_stylebox("panel")
	check(stats_style != null and is_equal_approx(stats_style.bg_color.a, 0.8), "High score stats box is 80% solid (was 96%)")
	var labels: Array = console.game_over_panel.find_children("*", "Label", true, false)
	var outlined := labels.size() > 3
	for label in labels:
		outlined = outlined and label.get_theme_constant("outline_size") == 5
	check(outlined, "Every Game Over and stats box text line has a dark outline (%d lines)" % labels.size())

# ---------------- 2. typed SYSTEMS OFFLINE list ----------------
func _typed_list() -> void:
	quiet(1)
	c.hull = 0.0
	console._process(0.0)
	check(c.is_defeated() and fx.is_destroyed(), "Ship destroyed: SYSTEMS OFFLINE runs")
	fx.destroyed_time = 1.0
	fx._update(0.0)
	check(fx.visible_line_count() == 1 and fx.typed_chars(0) == 0, "First line starts typing as the red screen appears")
	fx.destroyed_time = 1.1
	fx._update(0.0)
	check(fx.typed_chars(0) == 9 and fx.typed_chars(1) == 0, "Typed left to right at 90 letters a second (9 letters in 0.1 s)")
	fx.destroyed_time = 1.0 + 0.89
	fx._update(0.0)
	check(fx.visible_line_count() == 1, "Still one line just before 0.9 s")
	fx.destroyed_time = 1.0 + 0.91
	fx._update(0.0)
	check(fx.visible_line_count() == 2, "Second line at 0.9 s")
	var font: Font = fx.offline_text.get_theme_default_font()
	var w: float = fx.offline_text.size.x
	var longest := 0
	for i in range(fx.SYSTEM_NAMES.size()):
		var state: String = fx.statuses[i] if i < fx.statuses.size() else "OFFLINE"
		longest = maxi(longest, fx.SYSTEM_NAMES[i].length() + fx._dots_for(font, fx.SYSTEM_NAMES[i], state, w).length() + state.length())
	check(longest / fx.TYPE_CHARS_PER_SECOND < fx.LINE_SECONDS, "Every line finishes typing before the next starts (longest %.2f s)" % (longest / fx.TYPE_CHARS_PER_SECOND))
	# Steps up one line at a time once the panel is full.
	var rows: int = fx.list_rows()
	check(rows >= 5, "Red panel holds %d lines before the list steps up" % rows)
	fx.destroyed_time = 1.0 + fx.LINE_SECONDS * (rows - 1) + 0.5
	fx._update(0.0)
	check(is_zero_approx(fx.list_scroll_offset()), "No step up while the panel has room")
	fx.destroyed_time = 1.0 + fx.LINE_SECONDS * rows + 0.01
	fx._update(0.0)
	var mid: float = fx.list_scroll_offset()
	fx.destroyed_time = 1.0 + fx.LINE_SECONDS * rows + 0.13
	fx._update(0.0)
	var full: float = fx.list_scroll_offset()
	check(mid > 0.0 and mid < fx.LIST_STEP and is_equal_approx(full, fx.LIST_STEP), "A new line past a full panel steps the list up one line in 0.12 s")
	fx.destroyed_time = 1.0 + fx.LINE_SECONDS * (rows + 1) + 0.5
	fx._update(0.0)
	check(is_equal_approx(fx.list_scroll_offset(), fx.LIST_STEP * 2.0), "Two lines past full: stepped up two lines")
	check(fx.score_screen_ready() == true, "Score screen still comes in front (2 s after the red screen)")
	c.reset_battle()
	console._process(0.0)
	check(not fx.is_destroyed(), "New battle clears the red screen")

# ---------------- 3. low hull warning ----------------
func _low_hull() -> void:
	quiet(1)
	console._process(0.0)
	check(is_equal_approx(frame.low_hull_warning_percent, 6.0), "Low hull warning below 6%")
	var cases := [[100.0, false], [6.0, false], [5.99, true], [5.7, true], [1.0, true], [0.01, true]]
	for case in cases:
		c.hull = case[0]
		check(frame.low_hull_warning_active() == case[1], "Hull %.2f%%: warning %s" % [case[0], "on" if case[1] else "off"])
	c.hull = 0.0
	check(not frame.low_hull_warning_active(), "Ship destroyed: no low hull warning")
	# Bar flash: 2.5 times a second, bright first.
	quiet(1)
	c.hull = 5.0
	frame._process(0.0)
	console._process(0.0)
	check(frame.low_hull_flash_on() and fx.low_hull_warning, "Warning starts bright, flicker armed")
	var changes := 0
	var was: bool = frame.low_hull_flash_on()
	for i in range(240):
		frame._process(1.0 / 60.0)
		if frame.low_hull_flash_on() != was:
			changes += 1
			was = frame.low_hull_flash_on()
	check(changes >= 18 and changes <= 22, "HULL bar flashes about 2.5 times a second (%d changes in 4 s)" % changes)
	# Pixel check: the HULL bar is bright red, then dark red.
	frame.low_hull_time = 0.05
	frame.queue_redraw()
	var bright_img := await shot()
	frame.low_hull_time = 0.3
	frame.set_process(false)
	frame.queue_redraw()
	var dark_img := await shot()
	frame.set_process(true)
	var fill: Rect2 = frame.hull_gauge_fill_rect()
	var p := frame.get_global_transform_with_canvas() * fill.get_center()
	var k := root.get_texture().get_size().x / float(root.size.x)
	var bp: Color = bright_img.get_pixelv(Vector2i(p * k))
	var dp: Color = dark_img.get_pixelv(Vector2i(p * k))
	check(bp.r > 0.85 and bp.g < 0.3 and dp.r < 0.5 and dp.r > dp.g, "HULL bar on screen: bright red %s then dark red %s" % [bp.to_html(false), dp.to_html(false)])
	# Light screen flicker: about 0.25 s at 7%, every 1.5 to 3 s.
	fx.set_low_hull_warning(false)
	fx.set_low_hull_warning(true)
	var starts: Array[float] = []
	var peak := 0.0
	var t := 0.0
	var on := false
	while t < 40.0:
		fx._update(1.0 / 60.0)
		t += 1.0 / 60.0
		var s: float = fx.low_hull_flicker_strength()
		peak = maxf(peak, s)
		if s > 0.0 and not on:
			starts.append(t)
		on = s > 0.0
	var gaps_ok := starts.size() >= 12
	for i in range(1, starts.size()):
		var gap: float = starts[i] - starts[i - 1]
		gaps_ok = gaps_ok and gap >= 1.45 and gap <= 3.3
	check(starts.size() > 0 and absf(starts[0] - 0.6) < 0.05, "First flicker 0.6 s after the warning starts")
	check(gaps_ok, "Flicker repeats every 1.5 to 3 s (%d in 40 s)" % starts.size())
	check(peak > 0.06 and peak <= 0.0701, "Flicker is light: about 7%% (peak %.3f)" % peak)
	check(fx.low_hull_flickers >= 12, "Flickers counted (%d)" % fx.low_hull_flickers)
	# Nuke hit scramble takes over while it plays.
	fx.nuke_hit(true)
	fx._update(0.05)
	check(fx.scramble_strength > 0.2, "A nuke hit's own scramble takes over (strength %.2f)" % fx.scramble_strength)
	fx.reset()
	# SCREEN EFFECTS off: no flicker, the bar still flashes.
	console._on_settings_changed(GameSettings.clean({"screen_effects": false, "difficulty": 1}))
	quiet(1)
	c.hull = 4.0
	console._process(0.0)
	var shown := false
	for i in range(600):
		fx._update(1.0 / 60.0)
		frame._process(1.0 / 60.0)
		shown = shown or fx.scramble.visible
	check(not shown and frame.low_hull_warning_active(), "SCREEN EFFECTS off: no flicker; the HULL bar still flashes")
	console._on_settings_changed(GameSettings.clean({"screen_effects": true, "difficulty": 1}))
	# Stops at 6% or more.
	c.hull = 6.0
	console._process(0.0)
	frame._process(0.0)
	check(not fx.low_hull_warning and not frame.low_hull_warning_active() and is_zero_approx(frame.low_hull_time), "Repaired to 6%: warning stops")
	c.hull = 0.0
	console._process(0.0)
	check(not fx.low_hull_warning, "Ship destroyed: warning off (SYSTEMS OFFLINE takes over)")
	c.reset_battle()
	console._process(0.0)

# ---------------- 4. Rapid Missile balance ----------------
func _missiles() -> void:
	var plain: Control = load("res://scripts/RadarContacts.gd").new()
	check(is_equal_approx(plain.rapid_missile_speed_factor, 1.0), "Script default: 1.0.8 missile speed")
	plain.free()
	check(is_equal_approx(c.normal_rapid_missile_interval, 5.0) and is_equal_approx(c.hard_rapid_missile_interval, 4.0) and is_equal_approx(c.rapid_missile_speed_factor, 1.2), "Scene: Normal every 5 s, Hard every 4 s, 20% faster")
	for level in [1, 2]:
		quiet(level)
		c.own_weapons_enabled = true
		c._add_points(c.normal_rapid_missile_points if level == 1 else c.hard_rapid_missile_points)
		check(c.rapid_missile_active() and is_equal_approx(c.ship_missile_gap(), 5.0 if level == 1 else 4.0), "%s: Rapid Missile every %d s" % ["Normal" if level == 1 else "Hard", 5 if level == 1 else 4])
		var own := {"kind": "own_missile"}
		var gun := {"kind": "gunship_missile"}
		check(is_equal_approx(c.missile_flight_speed(own), c.own_missile_speed * 1.2) and is_equal_approx(c.missile_flight_speed(gun), c.own_missile_speed), "Rapid Missile: ship missiles 20% faster, Gunship missiles unchanged")
	# Double Missile unchanged.
	quiet(2)
	c.hard_rapid_missile_points = 999999
	c._add_points(c.hard_double_missile_points)
	check(c.double_missile_active() and is_equal_approx(c.missile_flight_speed({"kind": "own_missile"}), c.own_missile_speed), "Double Missile: normal missile speed")
	c.hard_rapid_missile_points = 6000
	# Missile actually flies faster on the scope.
	quiet(1)
	c._add_points(c.normal_rapid_missile_points)
	var target_id: String = c.spawn_contact("unknown", "unknown")
	var target: Dictionary = c.find_contact(target_id)
	c._identify_carrier(target)
	target.position = Vector3(0.9, 0.0, 0.0)
	c._launch_ship_missile(target)
	var m: Dictionary = c.contacts[c.contacts.size() - 1]
	var expected: float = (1.0 / 30.0) * c.movement_speed * c.own_missile_speed * 1.2
	var before: Vector3 = m.position
	c._process(1.0 / 30.0)
	var moved: float = before.distance_to(m.position)
	check(absf(moved - expected) < expected * 0.05, "Rapid Missile missile moves 20%% farther each step (%.4f, expected %.4f)" % [moved, expected])
	# Card text.
	var panel: Control = console.bonus_pick_panel
	panel.rapid_seconds = 5.0
	panel.double_seconds = 8.0
	panel.rapid_speed_factor = 1.2
	check(panel.effect_text("RAPID") == "Fires 1 missile\nevery 5 seconds\nMissiles fly 20% faster", "RAPID card: every 5 s on Normal, missiles fly 20% faster")
	panel.rapid_seconds = 4.0
	check(panel.effect_text("RAPID") == "Fires 1 missile\nevery 4 seconds\nMissiles fly 20% faster", "RAPID card: every 4 s on Hard")
	check(panel.effect_text("DOUBLE") == "Fires a pair of missiles\nevery 8 seconds\nCan hit two targets at once", "DOUBLE card: pair every 8 s, can hit two targets at once")
	panel.rapid_speed_factor = 1.0
	check(panel.effect_text("RAPID") == "Fires 1 missile\nevery 4 seconds", "Speed 1.0: no speed line")
	# Card text fits its card.
	panel.rapid_speed_factor = 1.2
	var font: Font = panel.card_effects[0].get_theme_font("font")
	var fs: int = panel.card_effects[0].get_theme_font_size("font_size")
	var fits := true
	for text in [panel.effect_text("RAPID"), panel.effect_text("DOUBLE")]:
		var lines: PackedStringArray = text.split("\n")
		var widest := 0.0
		for line in lines:
			widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var height: float = font.get_height(fs) * lines.size()
		fits = fits and widest <= panel.card_effects[0].size.x and height <= panel.card_effects[0].size.y + 4.0
	check(fits, "Three-line card text fits inside the card")
