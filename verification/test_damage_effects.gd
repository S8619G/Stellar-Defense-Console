extends SceneTree
## 1.0.8 damage effects: nuke-hit screen scramble, the red SYSTEMS OFFLINE screen, radar
## sound stopping, the score screen in front after 2 s (never scrambled) and the
## SCREEN EFFECTS switch. Needs a display (screen pixels are compared).
const GameSettings = preload("res://scripts/GameSettings.gd")
const DamageEffects = preload("res://scripts/DamageEffects.gd")
var checks := 0
var failures := 0
var console: Control
var c: Control
var fx: Control

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

## Steps the effect clock without frames advancing it.
func step(seconds: float, slices: int = 10) -> void:
	for i in range(slices):
		fx._update(seconds / slices)

func new_console(settings_name: String) -> void:
	if console != null:
		console.queue_free()
		await frames(2)
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
	await frames(4)

func carrier_base() -> Dictionary:
	var id: String = c.spawn_contact("unknown", "unknown")
	var b: Dictionary = c.find_contact(id)
	c._identify_carrier(b)
	return b

func defeat() -> void:
	c.hull = 0.0
	console._process(0.0)

func region_diff(a: Image, b: Image, r: Rect2i) -> float:
	var total := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, 3):
		for x in range(r.position.x, r.end.x, 3):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			total += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
			n += 1
	return total / maxf(1.0, n)

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://verify_fx.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://verify_fx_scores.json"))
	await new_console("verify_fx")
	c.auto_spawn = false
	c.reset_battle()
	c.set_process(false)
	fx.set_process(false)
	fx.rng.seed = 11

	# ---------------- placement ----------------
	check(fx is DamageEffects and fx.get_parent() == console, "Damage effects layer is part of the console")
	var r: Rect2 = fx.inner_rect()
	check(r == Rect2(410, 125, 1100, 843), "Effects cover only the inner console (x 410-1510, y 125-968 at 1920x1080): %s" % r)
	check(fx.get_index() > console.get_node("NuclearAlert").get_index() and fx.get_index() > console.get_node("ShipStatus").get_index() and fx.get_index() > console.get_node("BattleStatus").get_index(), "Effects draw after the dome, ship, status line and alerts")
	check(console.game_over_panel.z_index > fx.z_index, "Score screen draws in front of the effects")
	check(console.settings_panel.z_index > console.game_over_panel.z_index and console.gear_button.z_index > console.game_over_panel.z_index, "Settings and the gear stay in front of the score screen")
	check(fx.mouse_filter == Control.MOUSE_FILTER_IGNORE and fx.red_screen.mouse_filter == Control.MOUSE_FILTER_IGNORE and fx.scramble.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Effects never block mouse clicks")
	check(not fx.red_screen.visible and not fx.scramble.visible, "Nothing shows in normal play")

	# ---------------- nuke hits ----------------
	check(fx.screen_effects_enabled and console.settings.screen_effects, "SCREEN EFFECTS is on by default")
	var hits: Array = []
	c.nuke_hit_ship.connect(func(full: bool) -> void: hits.append(full))
	var start_hull: float = c.hull
	var nid: String = c._launch_nuclear(carrier_base())
	c.find_contact(nid).position = c.own_ship_position
	c._update_special_projectiles(0.0)
	check(hits == [true] and c.hull < start_hull, "A direct nuke hit on the ship sends the full-hit cue")
	console._process(0.0)
	fx._update(0.0)
	check(fx.scramble.visible and is_equal_approx(fx.scramble_strength, 1.0), "Full nuke hit: screen scrambles at full strength")
	step(0.5)
	check(fx.scramble.visible and fx.scramble_strength < 0.6, "Full nuke hit fades out (%.2f at 0.5 s)" % fx.scramble_strength)
	step(0.35)
	check(not fx.scramble.visible, "Full nuke hit is over after about 0.8 s")
	# Partial (Defense Shield) hit through the real path.
	c.hull = c.max_hull
	c.prox_active = true
	c.battery_nuke_chance = 1.0
	var nid2: String = c._launch_nuclear(carrier_base())
	var nuke: Dictionary = c.find_contact(nid2)
	nuke.position = c.own_ship_position + (nuke.position - c.own_ship_position).normalized() * c.prox_defense_radius * 0.5
	check(c._battery_try_nuke(nuke) and hits.size() == 2 and hits[1] == false, "A Defense Shield partial hit sends the partial-hit cue")
	c.prox_active = false
	fx._update(0.0)
	check(fx.scramble.visible and absf(fx.scramble_strength - 0.55) < 0.01, "Partial hit: about half strength (%.2f)" % fx.scramble_strength)
	step(0.3)
	check(fx.scramble.visible, "Partial hit still showing at 0.3 s")
	step(0.15)
	check(not fx.scramble.visible, "Partial hit is over after about 0.4 s")
	# Scrambled pixels stay inside the inner console.
	c.hull = c.max_hull
	var clean_shot := await shot()
	fx.nuke_hit(true)
	fx._update(0.02)
	var hit_shot := await shot()
	var k := 1600.0 / 1920.0
	var inner := Rect2i(Vector2i(r.position * k) + Vector2i(4, 4), Vector2i(r.size * k) - Vector2i(8, 8))
	check(region_diff(clean_shot, hit_shot, inner) > 0.05, "The inner console is scrambled on screen")
	check(region_diff(clean_shot, hit_shot, Rect2i(40, 120, 290, 560)) < 0.004 and region_diff(clean_shot, hit_shot, Rect2i(1290, 120, 280, 560)) < 0.004, "Side panels are not scrambled")
	# The score digits (right end of the header) can still be counting up after the shield kill, so they are left out.
	check(region_diff(clean_shot, hit_shot, Rect2i(40, 10, 1400, 90)) < 0.004 and region_diff(clean_shot, hit_shot, Rect2i(40, 816, 1520, 80)) < 0.004, "Top header and bottom button bar are not scrambled")
	step(1.0)

	# ---------------- ship destroyed ----------------
	check(not console.sweep_stopped, "Radar sound running before the ship is destroyed")
	defeat()
	check(fx.is_destroyed() and console.sweep_stopped, "Ship destroyed: SYSTEMS OFFLINE sequence starts and the radar sound is told to stop")
	console._update_sweep_sound(0.01)
	check(console.sweep_loop.volume_db < console.sweep_volume_db, "Radar sound fades (very short) instead of clicking")
	console._update_sweep_sound(0.05)
	check(not console.sweep_loop.playing, "Radar sound has stopped within about 0.03 s")
	console._update_sweep_sound(1.0)
	console._on_sweep_finished()
	check(not console.sweep_loop.playing, "Radar sound does not restart by itself")
	check(not console.game_over_panel.visible, "Score screen not shown at once")
	fx._update(0.0)
	check(fx.scramble.visible and fx.scramble_strength >= 0.75 and not fx.red_screen.visible, "Heavy scramble first (%.2f), no red yet" % fx.scramble_strength)
	step(0.6)
	check(fx.scramble_strength >= 0.75 and not fx.red_screen.visible, "Heavy scramble lasts about 0.7 s")
	var flicker_half := false
	var flicker_full := false
	for i in range(9):
		step(1.0 / 30.0, 1)
		if fx.destroyed_time > 0.7 and fx.destroyed_time < 1.0:
			if fx.red_screen.visible and fx.scramble.visible:
				flicker_half = true
			if fx.red_screen.visible and not fx.scramble.visible:
				flicker_full = true
	check(flicker_half and flicker_full, "Red screen flickers in over about 0.3 s")
	fx.destroyed_time = 1.0
	fx._update(0.0)
	check(fx.red_screen.visible and not fx.scramble.visible, "Then the red SYSTEMS OFFLINE screen shows")
	check(fx.offline_text.clip_contents and fx.red_screen.size == r.size, "Red screen fills exactly the inner console")
	# Statuses.
	check(fx.statuses.size() == DamageEffects.SYSTEM_NAMES.size() and DamageEffects.SYSTEM_NAMES.size() == 16, "16 ship systems listed")
	var all_known := true
	for s in fx.statuses:
		all_known = all_known and s in ["OFFLINE", "DESTROYED", "DAMAGED"]
	check(all_known, "Every status is OFFLINE, DESTROYED or DAMAGED")
	check(DamageEffects.SYSTEM_NAMES[0] == "MAIN POWER" and DamageEffects.SYSTEM_NAMES[15] == "LIFE SUPPORT" and DamageEffects.SYSTEM_NAMES[10] == "INTERCEPTOR LAUNCH BAY", "Systems in the same order each time")
	var patterns := {}
	for seed_value in range(20):
		var probe := DamageEffects.new()
		root.add_child(probe)
		probe.set_process(false)
		probe.rng.seed = 900 + seed_value
		probe.ship_destroyed()
		patterns[",".join(probe.statuses)] = true
		probe.queue_free()
	check(patterns.size() >= 15, "Statuses are picked at random each time (%d different lists in 20)" % patterns.size())
	# 1.0.9: the list builds up one typed line about every 0.9 s.
	check(fx.visible_line_count() == 1, "First system line starts as the red screen appears")
	fx.destroyed_time = 1.0 + 0.9 * 3 + 0.01
	fx._update(0.0)
	check(fx.visible_line_count() == 4, "A new line about every 0.9 s (1.0.9)")
	# Score screen timing.
	fx.destroyed_time = 2.95
	fx._update(0.0)
	console._process(0.0)
	check(not console.game_over_panel.visible, "Score screen not yet in front at 2.95 s")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_B
	key.unicode = 66
	var before_letters: String = console.entry_initials()
	console._input(key)
	check(console.entry_initials() == before_letters, "Typing does nothing before the score screen shows")
	check(console.controller.context() != "initials" and console.controller.context() != "game_over", "Controller does not act on the hidden score screen")
	fx.destroyed_time = 3.0
	fx._update(0.0)
	console._process(0.0)
	check(console.game_over_panel.visible, "Score screen in front 2 s after the red screen (3 s after the ship is destroyed)")
	check(fx.red_screen.visible, "Red screen stays behind the score screen")
	# Light scramble pulses: gaps 2.5-4 s, about 0.3 s, about 40%.
	var peak := 0.0
	var starts: Array[float] = []
	var was_on := false
	var t := 3.0
	while t < 30.0:
		step(1.0 / 60.0, 1)
		t += 1.0 / 60.0
		peak = maxf(peak, fx.scramble_strength)
		if fx.scramble.visible and not was_on:
			starts.append(fx.destroyed_time)
		was_on = fx.scramble.visible
	var gaps_ok := starts.size() >= 6
	for i in range(1, starts.size()):
		var gap: float = starts[i] - starts[i - 1]
		gaps_ok = gaps_ok and gap >= 2.45 and gap <= 4.05
	check(gaps_ok, "Light scramble repeats every 2.5 to 4 s (%d pulses in 27 s)" % starts.size())
	check(peak > 0.35 and peak <= 0.401, "Light scramble is about 40%% strength (peak %.2f)" % peak)
	# Score screen pixels are never scrambled.
	fx.destroyed_time = fx.pulses[fx.pulses.size() - 1] + 0.03
	fx._update(0.0)
	console._process(0.0)
	check(fx.scramble.visible, "A light scramble is showing")
	var with_pulse := await shot()
	var saved_strength: float = fx.scramble_strength
	fx.scramble.visible = false
	var without_pulse := await shot()
	var panel_rect: Rect2 = console.game_over_panel.get_global_rect()
	var pr := Rect2i(Vector2i(panel_rect.position * k) + Vector2i(3, 3), Vector2i(panel_rect.size * k) - Vector2i(6, 6))
	# 1.0.9: the score screen background is 80% solid, so the scramble shows faintly through
	# it; its text, buttons and border are in front and never moved or split. Compare with the
	# same area with the score screen hidden: in front, at most about a quarter shows through.
	var panel_diff := region_diff(with_pulse, without_pulse, pr)
	console.game_over_panel.modulate = Color(1, 1, 1, 0)
	fx.scramble.visible = true
	var bare_with := await shot()
	fx.scramble.visible = false
	var bare_without := await shot()
	console.game_over_panel.modulate = Color(1, 1, 1, 1)
	var bare_diff := region_diff(bare_with, bare_without, pr)
	check(saved_strength > 0.1 and bare_diff > 0.0 and panel_diff < bare_diff * 0.3, "Score screen is never scrambled (difference %.4f in front vs %.4f with it hidden; only its 20%% see-through background)" % [panel_diff, bare_diff])
	var red_strip := Rect2i(int(r.position.x * k) + 6, pr.end.y + 4, int(r.size.x * k) - 12, 40)
	check(region_diff(with_pulse, without_pulse, red_strip) > 0.02, "The red screen behind it is scrambled")
	# Mouse Retry restores everything.
	console.get_node("CenterContainer/Dome/GameOverPanel/Retry").pressed.emit()
	console._process(0.0)
	fx._update(0.0)
	check(not fx.is_destroyed() and not fx.red_screen.visible and not fx.scramble.visible and not console.game_over_panel.visible, "Retry clears the red screen")
	check(not console.sweep_stopped and console.sweep_loop.playing and is_equal_approx(console.sweep_loop.volume_db, console.sweep_volume_db), "Retry starts the radar sound again at its normal level")

	# ---------------- SCREEN EFFECTS OFF ----------------
	console.toggle_settings()
	var button: Button = console.settings_panel.screen_effects_button
	check(button.text == "ON" and button.button_pressed, "Settings shows SCREEN EFFECTS ON")
	button.button_pressed = false
	check(button.text == "OFF" and not console.settings.screen_effects and not fx.screen_effects_enabled, "SCREEN EFFECTS switches OFF")
	var saved: Dictionary = GameSettings.load_settings(console.settings_file)
	check(saved.screen_effects == false, "SCREEN EFFECTS OFF is saved")
	var panel_rect2: Rect2 = Rect2(Vector2.ZERO, console.settings_panel.PANEL_SIZE)
	var inside := true
	for b in [button, console.settings_panel.remember_button, console.settings_panel.reset_button, console.settings_panel.close_button, console.settings_panel.quit_button]:
		inside = inside and panel_rect2.encloses(Rect2(b.position, b.size))
	check(inside and console.settings_panel.PANEL_SIZE.y <= 1060.0, "Settings panel with the new row fits the 1080-pixel layout (1.1.0: FRAME RATE row too)")
	check(button.position.y < console.settings_panel.remember_button.position.y and button.position.x == console.settings_panel.remember_button.position.x, "SCREEN EFFECTS row sits above REMEMBER SETTINGS, switch lined up with the others")
	console.toggle_settings()
	c.set_process(false)
	c.hull = c.max_hull
	fx.nuke_hit(true)
	fx._update(0.02)
	check(not fx.scramble.visible, "OFF: a nuke hit does not scramble the screen")
	defeat()
	fx._update(0.0)
	check(fx.red_screen.visible and not fx.scramble.visible, "OFF: the red SYSTEMS OFFLINE screen shows at once, without scramble")
	check(console.sweep_stopped, "OFF: the radar sound still stops")
	var any_scramble := false
	var any_flicker := false
	for i in range(600):
		step(1.0 / 60.0, 1)
		any_scramble = any_scramble or fx.scramble.visible
		any_flicker = any_flicker or (fx.red_screen.visible and fx.offline_text.modulate.a < 1.0)
		if is_equal_approx(fx.destroyed_time, 1.9):
			console._process(0.0)
	check(not any_scramble and not any_flicker, "OFF: no scramble or flicker for 10 s")
	fx.destroyed_time = 1.95
	fx._update(0.0)
	console._process(0.0)
	check(not console.game_over_panel.visible, "OFF: score screen not yet in front at 1.95 s")
	fx.destroyed_time = 2.0
	fx._update(0.0)
	console._process(0.0)
	check(console.game_over_panel.visible, "OFF: score screen in front 2 s after the red screen")
	console.get_node("CenterContainer/Dome/GameOverPanel/Retry").pressed.emit()
	console._process(0.0)
	# DEFAULTS puts it back ON; Remember Settings OFF keeps it.
	var reset: Dictionary = GameSettings.reset_all(console.settings)
	check(reset.screen_effects == true, "DEFAULTS puts SCREEN EFFECTS back ON")
	var startup: Dictionary = GameSettings.startup({"screen_effects": false, "remember_settings": false})
	check(startup.screen_effects == false, "SCREEN EFFECTS is kept even with Remember Settings OFF (like the volumes)")
	check(GameSettings.clean({"screen_effects": "no"}).screen_effects == true, "A bad saved value falls back to ON")
	# A new console reads the saved OFF.
	await new_console("verify_fx")
	check(not fx.screen_effects_enabled and console.settings_panel != null, "Saved SCREEN EFFECTS OFF is used on the next start")
	console.settings.screen_effects = true
	GameSettings.save_settings(console.settings_file, console.settings)

	# ---------------- gameplay unchanged ----------------
	# 1.0.9: the faster Hard Rapid Missile changed the 1.0.8 seed (4242) to a battle with no
	# nuke hits, so the first seed below with nuke hits is used.
	var traces: Array = []
	var play_seed := 4242
	for seed_try in [4242, 11, 77, 2026, 9001, 31337]:
		await new_console("verify_fx_play")
		console._on_settings_changed(GameSettings.clean({"screen_effects": true, "difficulty": 2, "auto_battery": true, "auto_interceptors": true, "auto_gunships": true, "auto_repair": true}))
		c.difficulty = 2
		c.reset_battle()
		c.rng.seed = seed_try
		c.set_process(false)
		for i in range(30000):
			c._process(1.0 / 30.0)
			console._process(1.0 / 30.0)
			if c.is_defeated() or c.nuclear_hits > 0:
				break
		if c.nuclear_hits > 0:
			play_seed = seed_try
			break
	print("Seed with nuke hits: ", play_seed)
	for effects_on in [true, false]:
		await new_console("verify_fx_play")
		console._on_settings_changed(GameSettings.clean({"screen_effects": effects_on, "difficulty": 2, "auto_battery": true, "auto_interceptors": true, "auto_gunships": true, "auto_repair": true}))
		c.difficulty = 2
		c.reset_battle()
		c.rng.seed = play_seed
		c.set_process(false)
		var trace: Array = []
		for i in range(30000):
			c._process(1.0 / 30.0)
			console._process(1.0 / 30.0)
			if i % 300 == 0:
				trace.append([c.score, snappedf(c.hull, 0.001), c.contacts.size(), c.wave])
			if c.is_defeated():
				break
		trace.append([c.score, snappedf(c.hull, 0.001), c.contacts.size(), c.wave, snappedf(c.battle_time, 0.01), c.nuclear_hits])
		traces.append({"trace": trace, "scrambles": fx.nuke_scrambles, "defeated": c.is_defeated()})
	print("PLAY ON: ", traces[0].trace[-1], " scrambles ", traces[0].scrambles, "  OFF: ", traces[1].trace[-1], " scrambles ", traces[1].scrambles)
	check(traces[0].scrambles > 0 and traces[1].scrambles == 0, "Seeded battle had nuke hits (scrambles shown only with effects ON)")
	check(traces[0].trace == traces[1].trace and traces[0].defeated, "Same seeded battle plays out exactly the same with effects ON and OFF (to defeat)")
	console.settings.screen_effects = true
	GameSettings.save_settings(console.settings_file, console.settings)
	console.queue_free()
	await frames(2)
	print("DAMAGE_EFFECTS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
