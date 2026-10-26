extends SceneTree
## Stellar Defense Console 1.1.0: the changes of this version.
## 1. DEFEND THE AEGIS on the top message bar.
## 2. JUMP cost: 3,000 points or 10% of the current score, whichever is bigger.
## 3. Rapid Repair limit: 2 on Easy, 4 on Normal and Hard; earning pauses at the limit.
## 4. Idle screens (Game Over, Settings): 10 frames a second, sleep allowed after 5 minutes.
## 5. FRAME RATE setting: STANDARD (60) or SMOOTH (the screen's rate), one switch button.
## 7. Interceptors attack hacking Breachers first while no Gunship is out.
## 8. Stealth Interceptor PULSE BOMB earned by score.
## 9. Breach alert on the ship fill, INTRUSION DETECTION in the NAV DATA window.
## 8b. PULSE BOMB: drain, double damage, Breachers sent home, frozen-drone targets, controller hold.
## 11. NAV DATA: HELIUM-3 FIELD in place of the older fuel-field word; every line fits.
## Needs a display (pixel and click checks).
const Icons = preload("res://scripts/RadarContactIcons.gd")
var checks := 0
var NONE: Array[String] = []
var failures := 0
var console: Control
var c: Control
var ship: Control
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
	ship = console.get_node("ShipStatus")
	frame = console.get_node("ConsoleFrame")
	await frames(4)

func clean(level: int = 1) -> void:
	c.difficulty = level
	c.auto_spawn = false
	c.waves_enabled = false
	c.breachers_enabled = true
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.nuclear_weapons_enabled = false
	c.siege_enabled = false
	c.auto_defense_battery = false
	c.auto_firewall = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.auto_rapid_repair = false
	c.auto_jump = false
	c.max_carriers = 3
	c.reset_battle()
	c.set_process(false)

func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
		b.drone_timer = 999.0
		b.missile_timer = 999.0
		b.heavy_timer = 999.0
	return b

func hacker(b: Dictionary) -> Dictionary:
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	if not h.is_empty():
		h.position = h.hack_point
		c._update_breachers(0.0)
	return h

func drone_at(b: Dictionary, pos: Vector3) -> Dictionary:
	var r: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b.id))
	r.position = pos
	r.phase = "attack"
	return r

func _run() -> void:
	await new_console("verify_110")
	_aegis()
	_jump_cost()
	_rapid_repair()
	await _idle_and_frame_rate()
	_breacher_priority()
	await _pulse_bomb()
	await _breach_alert()
	await _pulse_more()
	await _nav_words()
	print("SDC_110_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------
func _aegis() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/RadarContacts.gd")
	check(source.contains("DEFEND THE AEGIS") and not source.contains("LOWER SCOPE"), "Top message bar reads DEFEND THE AEGIS (no LOWER SCOPE)")
	var scene := FileAccess.get_file_as_string("res://scenes/RadarConsole.tscn")
	check(not scene.contains("LOWER SCOPE"), "No LOWER SCOPE text left in the scene")

# ------------------------------------------------------------------
func _jump_cost() -> void:
	clean(1)
	c.score = 10000
	check(c.jump_cost_now() == 3000, "Score 10,000: JUMP costs 3,000 (10% is less)")
	c.score = 30000
	check(c.jump_cost_now() == 3000, "Score 30,000: JUMP costs 3,000 (10% is the same)")
	c.score = 46000
	check(c.jump_cost_now() == 4600, "Score 46,000: JUMP costs 4,600")
	c.score = 125000
	check(c.jump_cost_now() == 12500, "Score 125,000: JUMP costs 12,500")
	c.score = 1000
	check(c.jump_cost_now() == 3000, "Score 1,000: JUMP costs 3,000 (score cannot go below zero)")
	console._process(0.0)
	check(console.jump_button.text.contains("-3000 POINTS"), "JUMP button shows the cost")
	c.score = 46000
	console._process(0.0)
	check(console.jump_button.text.contains("-4600 POINTS"), "JUMP button cost follows the score (-4600)")
	var before: int = c.score
	check(c.request_jump(), "JUMP mid-wave works")
	check(c.score == before - 4600 and c.last_jump_cost == 4600, "Mid-wave JUMP takes 10% of 46,000")
	check(c.status_message.contains("-4600 POINTS"), "JUMP status line names the real cost")
	c.score = 1000
	c.jump_recharge_remaining = 0.0
	c.safe_remaining = 0.0
	c.request_jump()
	check(c.score == 0, "Small score: JUMP stops at zero")
	# Seeded 1.0.9 value: percent 0 = always 3,000.
	c.jump_score_percent = 0.0
	c.score = 46000
	check(c.jump_cost_now() == 3000, "Jump Score Percent 0 gives the 1.0.9 cost")
	c.jump_score_percent = 10.0

# ------------------------------------------------------------------
func _rapid_repair() -> void:
	clean(0)
	check(c.repair_limit() == 2, "Easy: at most 2 Rapid Repair charges")
	c._add_points(c.repair_bonus_threshold(1))
	check(c.repair_charges == 2 and c.repair_earning_paused, "Easy: second charge reaches the limit, earning pauses")
	c._add_points(c.repair_bonus_threshold(2) - c.earned_points)
	check(c.repair_charges == 2, "Easy: charge at the next total is lost (still 2)")
	clean(1)
	check(c.repair_limit() == 4, "Normal: at most 4 charges")
	c.hull = c.max_hull * 0.5
	for i in range(1, 4):
		c._add_points(c.repair_bonus_threshold(i) - c.earned_points)
	check(c.repair_charges == 4 and c.repair_earning_paused, "Normal: 4 charges, earning paused")
	check(not c._bonus_applies("REPAIR"), "EXTRA RAPID REPAIR not offered while paused")
	c._add_points(c.repair_bonus_threshold(4) - c.earned_points)
	check(c.repair_charges == 4 and c.repair_charges_lost >= 1, "Normal: the 5th charge is lost")
	# Use 2: down to 2, still paused. Use 1 more: down to 1, earning starts again.
	for i in range(2):
		c.rapid_repair_remaining = 0.0
		c.hull = c.max_hull * 0.5
		c.request_rapid_repair()
	check(c.repair_charges == 2 and c.repair_earning_paused, "Down to 2: still paused")
	c.rapid_repair_remaining = 0.0
	c.hull = c.max_hull * 0.5
	c.request_rapid_repair()
	check(c.repair_charges == 1 and not c.repair_earning_paused, "Down to 1: earning starts again")
	var next_total: int = c.earned_points + c.points_to_next_bonus()
	check(next_total > c.earned_points and c.repair_bonuses_for(next_total) == c.repair_bonuses_earned + 1, "Next charge comes at the next total still ahead")
	check(c._bonus_applies("REPAIR"), "EXTRA RAPID REPAIR offered again after earning resumes")
	c._add_points(c.points_to_next_bonus())
	check(c.repair_charges == 2, "Next total gives a charge again")
	check(FileAccess.get_file_as_string("res://scripts/ConsoleFrame.gd").contains("EARNING AT %d CHARGE"), "Left panel shows EARNING AT 1 CHARGE while paused")
	clean(2)
	check(c.repair_limit() == 4, "Hard: at most 4 charges")
	c.rapid_repair_limit = 0
	c.rapid_repair_limit_easy = 0
	for i in range(1, 6):
		c._add_points(c.repair_bonus_threshold(i) - c.earned_points)
	check(c.repair_charges == 6 and not c.repair_earning_paused, "Limit 0 gives the 1.0.9 rule (no limit)")
	c.rapid_repair_limit = 4
	c.rapid_repair_limit_easy = 2

# ------------------------------------------------------------------
func _idle_and_frame_rate() -> void:
	clean(1)
	c.set_process(false)
	console.frame_cap_disabled = false
	console.settings.smooth_frame_rate = false
	console._apply_settings()
	console._process(0.0)
	check(Engine.max_fps == 60, "STANDARD: at most 60 frames a second during a battle (%d)" % Engine.max_fps)
	console.settings_panel.frame_rate_button.button_pressed = true
	console._process(0.0)
	check(console.settings.smooth_frame_rate and console.chosen_max_fps() >= 60, "SMOOTH: the screen's rate, never below 60 (%d)" % console.chosen_max_fps())
	check(console.chosen_max_fps() > 0, "SMOOTH never runs without a limit")
	check(console.settings_panel.frame_rate_button.text == "SMOOTH", "One switch button reads SMOOTH")
	console.settings_panel.frame_rate_button.button_pressed = false
	check(console.settings_panel.frame_rate_button.text == "STANDARD" and not console.settings.smooth_frame_rate, "Switch button back to STANDARD")
	var saved := ConfigFile.new()
	console.settings_panel.frame_rate_button.button_pressed = true
	await frames(2)
	check(saved.load(console.settings_file) == OK and bool(saved.get_value("settings", "smooth_frame_rate", false)), "FRAME RATE is saved with the settings")
	console.settings_panel.frame_rate_button.button_pressed = false
	var panel_rect := Rect2(console.settings_panel.panel.position, console.settings_panel.panel.size)
	# 1.1.1: the tabbed redesign replaced the tall single panel with one 860 x 800 panel.
	check(panel_rect.size == Vector2(860, 800), "Settings panel is the 1.1.1 tabbed size (860 x 800)")
	# Settings open (the pause) = idle screen.
	console.open_settings()
	console._process(0.0)
	check(console.idle_screen_active and Engine.max_fps == console.idle_max_fps, "Settings screen: 10 frames a second (%d)" % Engine.max_fps)
	check(console.keep_awake, "Settings screen: still keeps the computer awake at first")
	console.idle_seconds = console.idle_sleep_seconds + 1.0
	console._process(0.0)
	check(not console.keep_awake and not DisplayServer.screen_is_kept_on() if DisplayServer.get_name() != "headless" else not console.keep_awake, "After 5 minutes: the computer may sleep")
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.pressed = true
	console._input(key)
	check(console.keep_awake and console.idle_seconds < 1.0, "Any key restarts the 5-minute wait and keeps the computer awake")
	var motion := InputEventMouseMotion.new()
	console.idle_seconds = 100.0
	console._input(motion)
	check(console.idle_seconds < 1.0, "Mouse movement restarts the wait too")
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	console.idle_seconds = 100.0
	console._input(pad)
	check(console.idle_seconds < 1.0, "Controller button restarts the wait too")
	console.close_settings()
	console._process(0.0)
	check(not console.idle_screen_active and Engine.max_fps == 60 and console.keep_awake, "Back in battle: 60 frames a second, computer kept awake")
	# Game Over = idle screen.
	c.hull = 0.0
	console._process(0.0)
	if c.is_defeated():
		check(console.idle_screen_active and Engine.max_fps == console.idle_max_fps, "Game Over: 10 frames a second")
	else:
		check(console.idle_screen_wanted() == c.is_defeated(), "Game Over counts as an idle screen")
	console.frame_cap_disabled = true
	console._apply_frame_rate()
	clean(1)
	console._process(0.0)

# ------------------------------------------------------------------
func _breacher_priority() -> void:
	clean(1)
	var b := base()
	b.position = Vector3(0.0, 0.7, 0.0)
	var h := hacker(b)
	check(h.get("phase", "") == "hacking", "Breacher is hacking the ship")
	var d := drone_at(b, c.own_ship_position + Vector3(0.05, 0.08, 0.0))
	c.launch_interceptors()
	var wing: Array = c.contacts.filter(func(k: Dictionary) -> bool: return Icons.is_interceptor(k.kind))
	var on_hacker := 0
	for v in wing:
		var t: Dictionary = c._hostile_target(v, NONE)
		if not t.is_empty() and t.id == h.id:
			on_hacker += 1
			v.target_id = h.id
	check(on_hacker == mini(2, wing.size()) and wing.size() >= 2, "No Gunship out: 2 Interceptors go after the hacking Breacher (%d of %d)" % [on_hacker, wing.size()])
	# A Gunship out attacking turns the rule off.
	for v in wing:
		v.target_id = ""
	c.launch_gunship()
	check(c.gunship_out_attacking(), "Gunship launched counts as out attacking")
	var first: Dictionary = c._hostile_target(wing[0], NONE)
	check(first.is_empty() or first.id != h.id or not c.interceptors_hacking_breachers_first or c._hacking_breacher_target(wing[0], NONE).is_empty(), "Gunship out: the hacking-Breacher rule is off")
	for k in c.contacts:
		if k.kind == "gunship":
			k.phase = "return"
	check(not c.gunship_out_attacking(), "A returning Gunship does not count")
	check(not c._hacking_breacher_target(wing[0], NONE).is_empty(), "Gunship flying back: Interceptors go after the hacking Breacher again")
	c.interceptors_hacking_breachers_first = false
	check(c._hacking_breacher_target(wing[0], NONE).is_empty(), "Setting off gives the 1.0.9 rule")
	c.interceptors_hacking_breachers_first = true
	c._remove_contact(d.id)

# ------------------------------------------------------------------
func _pulse_bomb() -> void:
	clean(0)
	c._add_points(60000)
	check(c.pulse_charges == 0, "Easy: no PULSE BOMB charges")
	clean(1)
	c._add_points(39990)
	check(c.pulse_charges == 0, "Normal: none before 40,000 points")
	c._add_points(10)
	check(c.pulse_charges == 1 and c.status_message == c.PULSE_EARNED_TEXT, "Normal: 1 charge at 40,000 points with the EARNED message")
	check(c.PULSE_EARNED_TEXT == "PULSE BOMB EARNED | READY ON THE STEALTH WEAPON BUTTON", "Earned wording as approved")
	c._add_points(40000)
	check(c.pulse_charges == 1 and c.pulse_charges_lost == 1 and c.status_message == c.PULSE_HELD_TEXT, "Only 1 held: the next one is lost with the ALREADY HELD message")
	clean(2)
	c._add_points(49990)
	check(c.pulse_charges == 0, "Hard: none before 50,000")
	c._add_points(10)
	check(c.pulse_charges == 1, "Hard: 1 charge at 50,000")
	console._update_battle_readout()
	check(console.pulse_readout.visible and console.pulse_readout.text == "PULSE BOMB  1", "Readout shows PULSE BOMB 1 under EMP CHARGES")
	check(console.pulse_readout.get_global_rect().position.y >= console.emp_readout.get_global_rect().end.y - 1.0, "PULSE BOMB line sits under EMP CHARGES")
	check(console.emp_readout.text == "EMP CHARGES  %d" % c.emp_charges, "EMP CHARGES line unchanged")
	c.difficulty = 0
	c.reset_battle()
	console._update_battle_readout()
	check(not console.pulse_readout.visible, "Easy: no PULSE BOMB line")
	# Launch with the PULSE BOMB.
	clean(1)
	c.pulse_charges = 1
	var b1 := base()
	var b2 := base()
	var b3 := base()
	b1.position = Vector3(-0.2, 0.6, 0.0)
	b2.position = Vector3(0.0, 0.65, 0.0)
	b3.position = Vector3(0.2, 0.6, 0.0)
	var dr := drone_at(b1, Vector3(-0.1, 0.5, 0.0))
	var far := drone_at(b1, Vector3(0.0, -0.75, 0.0))
	far.position = c.own_ship_position + Vector3(0.0, 0.05, 0.0)
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b2.id))
	h.position = b2.position + Vector3(0.03, -0.05, 0.0)
	check(c.can_launch_stealth(), "Stealth Interceptor offered")
	check(c.launch_stealth(true), "Stealth Interceptor launched with the PULSE BOMB")
	check(c.status_message.contains("PULSE BOMB STRIKE ON ENEMY CARRIERS"), "Launch message as approved")
	var t := 0.0
	var away := false
	while t < 30.0 and c.pulse_detonations == 0:
		c._process(0.05)
		t += 0.05
		if not away and c.status_message == "STEALTH INTERCEPTOR | PULSE BOMB AWAY":
			away = true
	check(away, "Dropped message as approved: STEALTH INTERCEPTOR | PULSE BOMB AWAY")
	check(c.pulse_detonations == 1 and c.pulse_charges == 0, "The bomb goes off and the charge is used")
	check(float(b1.get("frozen", 0.0)) > 0.0 and float(b2.get("frozen", 0.0)) > 0.0 and float(b3.get("frozen", 0.0)) > 0.0, "Carriers in the area are frozen")
	check(c.status_message.begins_with("PULSE BOMB | ") and c.status_message.contains("FROZEN FOR 10 S"), "Goes-off message: %s" % c.status_message)
	# Freeze ends after 10 s.
	var ended := false
	t = 0.0
	while t < 11.0:
		c._process(0.05)
		t += 0.05
		if c.status_message == c.PULSE_ENDED_TEXT:
			ended = true
	check(ended, "PULSE BOMB FREEZE ENDED message after the freeze")
	check(float(b1.get("frozen", 0.0)) <= 0.0 or c.find_contact(b1.id).is_empty(), "Carriers move again after 10 s")
	# Nuclear missile caught in the area: slowed (not frozen) until it hits or is destroyed.
	clean(1)
	var nb := base()
	nb.position = Vector3(0.0, 0.7, 0.0)
	var nuke_id: String = c._launch_nuclear(nb)
	var nuke: Dictionary = c.find_contact(nuke_id)
	check(not nuke.is_empty(), "A nuclear missile is on its way")
	nuke.position = Vector3(0.0, 0.45, 0.0)
	c._detonate_pulse(Vector3(0.0, 0.6, 0.0))
	check(nuke.get("pulse_slowed", false) and float(nuke.get("frozen", 0.0)) <= 0.0 and c.pulse_nukes_slowed == 1, "Nuclear missile in the area is slowed, not frozen")
	check(c.display_color(nuke).b > c.display_color(nuke).r and c.nuke_marker_color(nuke).b > c.nuke_marker_color(nuke).r, "Slowed nuclear missile marker shimmers ice-blue")
	nuke.pulse_slowed = false
	check(c.nuke_marker_color(nuke).r > c.nuke_marker_color(nuke).b, "A nuclear missile not slowed keeps the yellow and red flash")
	nuke.pulse_slowed = true
	var p0: Vector3 = nuke.position
	c._update_special_projectiles(0.1)
	var moved: float = p0.distance_to(nuke.position)
	nuke.pulse_slowed = false
	var p1: Vector3 = nuke.position
	c._update_special_projectiles(0.1)
	var moved_full: float = p1.distance_to(nuke.position)
	nuke.pulse_slowed = true
	check(moved_full > 0.0 and absf(moved / moved_full - 0.6) < 0.05, "Slowed nuclear missile flies at 60%% speed (%.4f vs %.4f)" % [moved, moved_full])
	nuke.position = Vector3(0.0, 0.45, 0.0)
	for i in range(240):
		c._process(0.05)
		if c.find_contact(nuke_id).is_empty():
			break
		if i == 220:
			check(nuke.get("pulse_slowed", false), "Nuclear missile still slow after the 10 s freeze")
	# Stealth button pills.
	clean(1)
	c.pulse_charges = 1
	for i in 3:
		base()
	ship._process(0.0)
	ship.queue_redraw()
	await frames(3)
	check(ship.stealth_button.visible and ship.pulse_pill_rect.size.x > 10.0 and ship.nukes_pill_rect.size.x > 10.0, "STEALTH WEAPON button shows NUKES and PULSE pills while a charge is held")
	check(not c.launch_stealth(false) or c.pulse_charges == 1, "NUKES pill keeps the PULSE BOMB charge for later")

# ------------------------------------------------------------------
func _breach_alert() -> void:
	clean(1)
	var b := base()
	b.position = Vector3(0.0, 0.7, 0.0)
	var h := hacker(b)
	ship._process(0.0)
	frame.queue_redraw()
	ship.queue_redraw()
	await frames(3)
	check(ship.breach_alert_on_ship_fill and ship.breach_fill_active(), "Hacking: the ship fill shows the breach alert")
	check(c.hack_state() in ["hacking", "draining"], "Hack state is hacking")
	var img := await shot()
	var nav: PackedVector2Array = frame.nav_box_poly()
	var xf := root.get_final_transform() * frame.get_global_transform_with_canvas()
	var bounds := Rect2(nav[0], Vector2.ZERO)
	for p in nav:
		bounds = bounds.expand(p)
	var red := 0
	var inside := 0
	for gx in range(int(bounds.position.x), int(bounds.end.x), 3):
		for gy in range(int(bounds.position.y), int(bounds.end.y), 3):
			var lp := Vector2(gx, gy)
			if not Geometry2D.is_point_in_polygon(lp, nav):
				continue
			inside += 1
			var px: Color = img.get_pixelv(Vector2i((xf * lp).clamp(Vector2.ZERO, Vector2(img.get_width() - 1, img.get_height() - 1))))
			if px.r > 0.6 and px.g < 0.35 and px.b < 0.4:
				red += 1
	var found_red := inside > 0 and float(red) / float(inside) > 0.2
	print("nav red share ", red, " / ", inside)
	check(found_red, "NAV DATA window shows the red INTRUSION DETECTION stripes")
	c._remove_contact(h.id)
	c._update_breachers(0.0)
	ship._process(0.0)
	check(not ship.breach_fill_active(), "Breach alert ends when the hacking ends")


# ------------------------------------------------------------------
## 11. NAV DATA word (Stephen, 2026-10-25: HELIUM-3 FIELD). The longest possible
## NEAREST line must fit inside the NAV DATA window at 1280x720, 1600x900 and 1920x1080.
func _nav_words() -> void:
	check(frame.NAV_BODIES.has("HELIUM-3 FIELD"), "NAV DATA list has HELIUM-3 FIELD")
	var old_word := Marshalls.base64_to_utf8("VFlMSVVN")
	var found := false
	for list in [frame.NAV_NAMES, frame.NAV_STARS, frame.NAV_BODIES, frame.NAV_NOTES]:
		for word in list:
			if String(word).find(old_word) >= 0:
				found = true
	check(not found, "NAV DATA lists no longer use the older fuel-field word")
	check(frame.NAV_BODIES.size() == 8, "NAV DATA keeps 8 nearest-body words (same random picks)")
	var font := ThemeDB.fallback_font
	for res in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = res
		await frames(4)
		var k: float = frame._frame_scale()
		var box: PackedVector2Array = frame.nav_box_poly()
		var right := -INF
		for p in box:
			right = maxf(right, p.x)
		var x0: float = box[2].x + 8.0 * k
		var fs2 := maxi(8, int(round(10.5 * k)))
		var widest := 0.0
		for body in frame.NAV_BODIES:
			widest = maxf(widest, font.get_string_size("NEAREST  %s  %.1f AU" % [body, 5.9], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x)
		check(x0 + widest < right - 2.0 * k, "%dx%d: longest NEAREST line stays inside the NAV DATA border (%.0f of %.0f px)" % [res.x, res.y, widest, right - x0])
	root.size = Vector2i(1600, 900)
	await frames(4)


# ------------------------------------------------------------------
## 8b. PULSE BOMB effects in more detail, and the controller hold.
func three_large() -> Array:
	var list := [base(), base(), base()]
	list[0].position = Vector3(-0.2, 0.6, 0.0)
	list[1].position = Vector3(0.0, 0.65, 0.0)
	list[2].position = Vector3(0.2, 0.6, 0.0)
	return list

func _pulse_more() -> void:
	# Drain on a frozen Enemy Carrier: 5% of the current strength each second, never destroying it.
	clean(1)
	var b := base()
	b.position = Vector3(0.0, 0.6, 0.0)
	b.frozen = 10.0
	var before := float(b.hits_remaining)
	c._pulse_drain_step(b, 1.0)
	check(absf(float(b.hits_remaining) - before * 0.95) < 0.001, "Frozen Enemy Carrier loses 5%% of its current strength in a second (%.3f -> %.3f)" % [before, float(b.hits_remaining)])
	b.hits_remaining = 0.02
	for i in 12:
		c._pulse_drain_step(b, 1.0)
	check(float(b.hits_remaining) > 0.0 and not c.find_contact(b.id).is_empty(), "The drain never destroys an Enemy Carrier on its own")
	# Double damage while frozen.
	b.hits_remaining = 10.0
	c._hit_carrier(b, 1.0)
	check(is_equal_approx(float(b.hits_remaining), 8.0), "A frozen Enemy Carrier takes double damage (10 -> %.1f)" % float(b.hits_remaining))
	b.frozen = 0.0
	c._hit_carrier(b, 1.0)
	check(is_equal_approx(float(b.hits_remaining), 7.0), "Normal damage once the freeze is over (8 -> %.1f)" % float(b.hits_remaining))
	# Frozen Attack Drone: 10% of its full strength each second, can be destroyed, normal points.
	var d := drone_at(b, Vector3(0.1, 0.45, 0.0))
	d.frozen = 10.0
	var score_before: int = c.score
	var gone_after := -1
	for i in 12:
		if c._pulse_drain_step(d, 1.0):
			gone_after = i + 1
			break
	check(gone_after > 0 and gone_after <= 11, "A frozen Attack Drone is destroyed by the drain (after %d s)" % gone_after)
	check(c.score > score_before, "The drained Attack Drone gives points (%d -> %d)" % [score_before, c.score])
	# A hacking Breacher in the area breaks off and goes home.
	clean(1)
	var hb := base()
	hb.position = Vector3(0.0, 0.7, 0.0)
	var h := hacker(hb)
	check(h.get("phase", "") == "hacking", "Breacher hacking before the PULSE BOMB")
	c._detonate_pulse(h.position)
	check(h.get("phase", "") == "emp" and c.pulse_breachers_sent_home == 1, "The PULSE BOMB sends the hacking Breacher home (phase %s)" % h.get("phase", ""))
	# Interceptors: frozen Attack Drones first, each one a different drone.
	clean(1)
	var fb := base()
	fb.position = Vector3(0.0, 0.7, 0.0)
	var d1 := drone_at(fb, Vector3(-0.15, 0.3, 0.0))
	var d2 := drone_at(fb, Vector3(0.15, 0.3, 0.0))
	c._detonate_pulse(Vector3(0.0, 0.5, 0.0))
	check(float(d1.get("frozen", 0.0)) > 0.0 and float(d2.get("frozen", 0.0)) > 0.0 and float(fb.get("frozen", 0.0)) > 0.0, "Drones and Enemy Carrier frozen")
	c.launch_interceptors()
	var wing: Array = c.contacts.filter(func(k: Dictionary) -> bool: return Icons.is_interceptor(k.kind))
	var picked: Array[String] = []
	for v in wing.slice(0, 2):
		var t: Dictionary = c._hostile_target(v, NONE)
		if not t.is_empty():
			v.target_id = t.id
			picked.append(String(t.id))
	check(picked.size() == 2 and picked.has(d1.id) and picked.has(d2.id), "Two Interceptors take the two frozen Attack Drones, one each (%s)" % str(picked))
	# Controller: a short press fires NUKES and keeps the charge; a 1-second hold fires the PULSE BOMB.
	var pad: Node = console.controller
	var ship: Control = console.get_node("ShipStatus")
	for hold in [false, true]:
		clean(1)
		three_large()
		c.pulse_charges = 1
		await frames(3)
		check(ship.stealth_button.is_visible_in_tree(), "STEALTH WEAPON button shown (%s)" % ("hold" if hold else "short press"))
		pad.held["x"] = true
		pad.perform("launch_stealth", "x")
		pad._update_stealth_hold(0.5)
		check(c.stealth_launches == 0 and absf(float(ship.pulse_hold_progress) - 0.5) < 0.01, "Half a second in: nothing launched, PULSE fill at half (%s)" % ("hold" if hold else "short press"))
		if not hold:
			pad.held["x"] = false
			pad._update_stealth_hold(0.05)
			check(c.stealth_launches == 1 and c.pulse_charges == 1 and c.status_message.contains("NUCLEAR STRIKE"), "Short press: NUKES launched and the PULSE BOMB charge kept")
		else:
			pad._update_stealth_hold(0.55)
			check(c.stealth_launches == 1 and c.status_message.contains("PULSE BOMB STRIKE"), "1-second hold: PULSE BOMB launched")
		pad.held["x"] = false
		check(float(ship.pulse_hold_progress) < 0.0, "PULSE fill cleared after the press")
