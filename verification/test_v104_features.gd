extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.04: explosions for destroyed fighters and capital
## ships, Development Build off by default, missile and nuke speed by
## difficulty, Defense Shield kills at the flak arc, Auto Rapid Repair,
## Remember Settings and Reset to Defaults.
const GameSettings = preload("res://scripts/GameSettings.gd")
const BattleAudio = preload("res://scripts/BattleAudio.gd")
var console: Control
var c: Control
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)
func clean() -> void:
	c.auto_spawn = false
	c.breachers_enabled = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.nuclear_weapons_enabled = false
	c.siege_enabled = false
	c.auto_defense_battery = false
	c.auto_firewall = false
	c.auto_launch_interceptors = false
	c.auto_launch_gunships = false
	c.auto_jump = false
	c.auto_rapid_repair = false
	c.reset_battle()
func base() -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	if not b.is_empty():
		c._identify_carrier(b)
		b.drone_timer = 999.0
		b.missile_timer = 999.0
	return b
func near(a: float, b: float, tolerance := 0.002) -> bool:
	return absf(a - b) <= tolerance
func rect_of(control: Control) -> Rect2:
	return Rect2(control.position, control.size)
func text_rect(label: Label) -> Rect2:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := label.position.x
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = label.position.x + label.size.x - width
	return Rect2(Vector2(x, label.position.y), Vector2(width, font.get_height(font_size)))

## Arc in global pixels, and the distance from a scope position to it.
func arc_points() -> PackedVector2Array:
	var ship: Control = console.get_node("ShipStatus")
	var width: float = minf(ship.size.x, ship.size.y * ship.REGION.size.x / ship.REGION.size.y)
	var dims := Vector2(width, width * ship.REGION.size.y / ship.REGION.size.x)
	var rect := Rect2((ship.size - dims) * 0.5, dims)
	var g: Transform2D = ship.get_global_transform()
	var out := PackedVector2Array()
	for p in ship.defense_arc(rect):
		out.append(g * p)
	return out
func arc_distance(arc: PackedVector2Array, world: Vector3) -> float:
	var point: Vector2 = c.get_global_transform() * c.projection(world).point
	var best := INF
	for i in range(arc.size() - 1):
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, arc[i], arc[i + 1])))
	return best

## Fires the battery continuously at single missiles flying in from random
## directions; returns [share destroyed, median kill distance to the arc in pixels].
func battery_trial(level: int, kill_radius: float, interval: float, speeds: float, count: int, seed: int) -> Array:
	c.difficulty = level
	clean()
	c.prox_defense_radius = kill_radius
	c.battery_shot_interval = interval
	var saved := [c.easy_missile_speed, c.normal_missile_speed, c.hard_missile_speed]
	if speeds > 0.0:
		c.easy_missile_speed = speeds
		c.normal_missile_speed = speeds
		c.hard_missile_speed = speeds
	c.rng.seed = seed
	var b := base()
	var arc := arc_points()
	var killed := 0
	var distances: Array[float] = []
	for n in range(count):
		var m: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
		if m.is_empty():
			break
		var angle: float = c.rng.randf_range(-1.1, 1.1)
		m.position = c.own_ship_position + Vector3(sin(angle), cos(angle), c.rng.randf_range(-0.3, 0.3)).normalized() * 0.55
		var kills_before: int = c.prox_kills
		var last: Vector3 = m.position
		c.set_prox_defense(true)
		for frame in range(60 * 20):
			c.prox_burst_remaining = c.prox_burst_seconds
			if not c.prox_active:
				c.set_prox_defense(true)
			c.hull = c.max_hull
			last = m.position
			c._process(1.0 / 60.0)
			if c.find_contact(m.id).is_empty():
				break
		if c.prox_kills > kills_before:
			killed += 1
			distances.append(arc_distance(arc, last))
	c.easy_missile_speed = saved[0]
	c.normal_missile_speed = saved[1]
	c.hard_missile_speed = saved[2]
	c.prox_defense_radius = 0.12
	c.battery_shot_interval = 0.1
	distances.sort()
	var median: float = distances[distances.size() / 2] if not distances.is_empty() else -1.0
	return [float(killed) / maxf(1.0, count), median]

func peak(stream: AudioStreamWAV) -> float:
	var top := 0
	for i in range(0, stream.data.size(), 2):
		top = maxi(top, absi(stream.data.decode_s16(i)))
	return top / 32767.0

func _run() -> void:
	var fresh: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	check(not fresh.development_build, "Development Build is OFF by default in the scene (labels and F1 hidden)")
	fresh.free()
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://v104_test_settings.cfg"
	console.high_score_file = "user://v104_test_scores.json"
	console.quit_dry_run = true
	if FileAccess.file_exists(console.settings_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(console.settings_file))
	c = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	c.auto_spawn = false
	root.add_child(console)
	c.set_process(false)
	console.set_process(false)
	await process_frame
	await process_frame
	clean()

	# --- 1. Version and Development Build ---
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Version 1.08")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Windows_x64.exe") and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Mac.zip"), "Export names use 1.05")
	check(not console.development_build, "Console starts with Development Build off")
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	console.tuning_panel.visible = false
	console._input(key)
	check(not console.tuning_panel.visible, "F1 does nothing while Development Build is off")
	console.development_build = true
	console._input(key)
	check(console.tuning_panel.visible, "Ticking Development Build brings F1 tuning back")
	console._input(key)
	console.development_build = false
	var frame_source := FileAccess.get_file_as_string("res://scripts/ConsoleFrame.gd")
	check(frame_source.contains("if get_parent().development_build:") and frame_source.contains("F1  TUNING PANEL"), "RADAR dB and F1 labels are drawn only with Development Build on")

	# --- 2. Missile and nuke speed by difficulty ---
	check(c.easy_missile_speed == 1.0 and c.normal_missile_speed == 1.1 and c.hard_missile_speed == 1.6, "Missile speed: Easy 1.0x (unchanged), Normal 1.1x, Hard 1.6x")
	# 1.2.7: nuke speeds are now Easy 1.1, Normal 1.25, Hard 1.45 (field-tested).
	check(is_equal_approx(c.easy_nuke_speed, 1.1) and is_equal_approx(c.normal_nuke_speed, 1.25) and is_equal_approx(c.hard_nuke_speed, 1.45), "Nuke speed: Easy 1.1x, Normal 1.25x, Hard 1.45x (1.2.7)")
	var moved := []
	var nuke_moved := []
	for level in range(3):
		c.difficulty = level
		clean()
		var b := base()
		var m: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b.id))
		m.position = c.own_ship_position + Vector3(0, 0.9, 0)
		var start: Vector3 = m.position
		c._process(0.5)
		moved.append(start.distance_to(m.position) / 0.5)
		c.nuclear_weapons_enabled = true
		c._launch_nuclear(b)
		var nuke := {}
		for contact in c.contacts:
			if contact.kind == "nuke":
				nuke = contact
		if not nuke.is_empty():
			nuke.speed_bonus = 0.0  # 1.1.0: random nuke speed bonus off for the exact measurement
			var nstart: Vector3 = nuke.position
			c._update_special_projectiles(1.0)
			nuke_moved.append(nstart.distance_to(nuke.position))
	print("SPEEDS missiles easy=%.3f normal=%.3f hard=%.3f nukes easy=%.3f normal=%.3f hard=%.3f (scope radii per second)" % [moved[0], moved[1], moved[2], nuke_moved[0], nuke_moved[1], nuke_moved[2]])
	check(near(moved[0], c.missile_speed * c.movement_speed) and near(moved[1], c.missile_speed * c.movement_speed * 1.1) and near(moved[2], c.missile_speed * c.movement_speed * 1.6), "Missiles fly at 0.12 / 0.132 / 0.192 on Easy / Normal / Hard")
	check(nuke_moved.size() == 3 and near(nuke_moved[0], c.nuclear_speed * c.movement_speed * c.easy_nuke_speed) and near(nuke_moved[2], c.nuclear_speed * c.movement_speed * c.hard_nuke_speed), "Nukes fly at the Easy and Hard speed factors (1.2.7: 1.1 and 1.45)")
	check(nuke_moved.size() == 3 and nuke_moved[2] < c.gunship_speed * c.movement_speed, "Hard nukes are close to Gunship speed but still catchable")

	# --- 3. Defense Shield kills at the flak arc ---
	c.difficulty = 1
	clean()
	check(c.prox_defense_radius == 0.12 and c.auto_battery_lead_radius == 0.22 and c.battery_shot_interval == 0.1 and c.prox_success_chance == 0.45, "Kill zone 0.12, auto lead 0.22, shots every 0.1 s at 45% (Inspector values)")
	var b3 := base()
	var far: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b3.id))
	far.position = c.own_ship_position + Vector3(0, 0.2, 0)
	c.prox_success_chance = 0.95
	c.set_prox_defense(true)
	for i in range(10):
		c.battle_time += 0.1
		c._resolve_missiles()
	check(not c.find_contact(far.id).is_empty(), "A missile well above the arc is not shot down")
	far.position = c.own_ship_position + Vector3(0, 0.09, 0)
	for i in range(10):
		c.battle_time += 0.1
		c._resolve_missiles()
	check(c.find_contact(far.id).is_empty() and c.prox_kills == 1, "A missile at the arc is shot down")
	c.prox_success_chance = 0.45
	c.set_prox_defense(false)
	clean()
	c.auto_defense_battery = true
	var b4 := base()
	var lead: Dictionary = c.find_contact(c.spawn_from_carrier("missile", b4.id))
	lead.position = c.own_ship_position + Vector3(0, 0.3, 0)
	c._update_automation()
	check(not c.prox_active, "Auto shield waits while the missile is still far up the scope")
	lead.position = c.own_ship_position + Vector3(0, 0.2, 0)
	c._update_automation()
	check(c.prox_active and c.auto_battery_starts == 1, "Auto shield starts just before the missile reaches the arc")
	c.auto_defense_battery = false
	c.set_prox_defense(false)
	var arc := arc_points()
	var crossing := INF
	for d in range(0, 50):
		crossing = minf(crossing, arc_distance(arc, c.own_ship_position + Vector3(0, d / 100.0, 0)))
	check(arc_distance(arc, c.own_ship_position + Vector3(0, 0.12, 0)) < 40.0 and crossing < 4.0, "The kill zone edge is a short way above the drawn arc")
	var results := {}
	for level in range(3):
		var old: Array = battery_trial(level, 0.45, 0.3, 1.0, 40, 11 + level)
		var now: Array = battery_trial(level, 0.12, 0.1, -1.0, 40, 11 + level)
		results[level] = [old, now]
		print("BATTERY_ARC level=%s stopped_1.03=%d%% median_px_1.03=%.0f stopped_1.04=%d%% median_px_1.04=%.0f" % [["easy", "normal", "hard"][level], roundi(old[0] * 100.0), old[1], roundi(now[0] * 100.0), now[1]])
	check(results[1][1][1] >= 0.0 and results[1][1][1] < 30.0 and results[1][0][1] > 80.0, "Missiles now burst next to the arc (was far above it)")
	check(results[0][1][0] >= 0.9 and results[1][1][0] >= 0.9 and results[2][1][0] >= 0.85, "A firing battery still stops most missiles on every level")

	# --- 4. Auto Rapid Repair ---
	c.difficulty = 1
	clean()
	check(c.auto_repair_hull_percent == 50.0 and not c.auto_rapid_repair, "Auto Rapid Repair is off by default and acts at 50% hull")
	c.auto_rapid_repair = true
	c.repair_charges = 2
	c.hull = 60.0
	c._update_automation()
	check(c.rapid_repair_remaining == 0.0 and c.repair_charges == 2, "No repair above 50% hull")
	c.hull = 50.0
	c._update_automation()
	check(c.rapid_repair_remaining > 0.0 and c.repair_charges == 1 and c.auto_repairs == 1, "At 50% hull one charge is used by itself")
	c._update_automation()
	check(c.repair_charges == 1 and c.auto_repairs == 1, "No second charge while a repair is running")
	c.rapid_repair_remaining = 0.0
	c.repair_charges = 0
	c.hull = 30.0
	c._update_automation()
	check(c.auto_repairs == 1 and c.rapid_repair_remaining == 0.0, "Nothing happens without a charge")
	clean()
	c.auto_rapid_repair = true
	c.auto_jump = true
	c.repair_charges = 1
	c.score = 9000
	c.hull = 5.0
	c._update_automation()
	check(c.auto_repairs == 1 and c.auto_jumps == 1, "With Auto JUMP on, a low hull uses the repair first and still jumps")
	c.auto_jump = false
	check(c.auto_options_on() == 1 and near(c.score_multiplier_for(1, 6), 0.4), "Auto Rapid Repair counts as an auto option (all six on: x0.40)")
	clean()
	c.auto_rapid_repair = true
	c.repair_charges = 1
	c.hull = 70.0
	console._process(0.016)
	check(console.repair_button.text.contains("AUTO"), "RAPID REPAIR button shows AUTO")
	check(not console.repair_button.disabled, "RAPID REPAIR still works by hand")
	c.auto_rapid_repair = false
	console._process(0.016)
	check(not console.repair_button.text.contains("AUTO"), "No AUTO tag when the option is off")

	# --- 5. Settings: Auto Rapid Repair, Remember Settings, Reset to Defaults ---
	check(GameSettings.DEFAULTS.auto_repair == false and GameSettings.DEFAULTS.remember_settings == true, "New settings: Auto Rapid Repair OFF, Remember Settings ON")
	var forget := GameSettings.startup({"remember_settings": false, "difficulty": 2, "auto_jump": true, "auto_repair": true, "auto_battery": true, "effects_volume": 30, "radar_muted": true})
	check(forget.difficulty == 1 and not forget.auto_jump and not forget.auto_repair and not forget.auto_battery, "Remember OFF: next start is NORMAL with all auto options off")
	check(forget.effects_volume == 30 and forget.radar_muted and not forget.remember_settings, "Remember OFF keeps volumes, mutes and the switch itself")
	var keep := GameSettings.startup({"remember_settings": true, "difficulty": 2, "auto_jump": true})
	check(keep.difficulty == 2 and keep.auto_jump, "Remember ON: everything carries over (as in 1.03)")
	var reset := GameSettings.reset_all({"remember_settings": false, "difficulty": 0, "effects_volume": 10, "auto_interceptors": true})
	check(reset.difficulty == 1 and reset.effects_volume == 50 and not reset.auto_interceptors and not reset.remember_settings, "Reset to Defaults restores everything except the Remember choice")
	console._on_settings_changed({"remember_settings": false, "difficulty": 2, "auto_repair": true, "effects_volume": 35})
	check(c.auto_rapid_repair and console.settings_saved, "The Auto Rapid Repair switch reaches the battle and is saved")
	var second: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	second.settings_file = console.settings_file
	second.high_score_file = "user://v104_test_scores_2.json"
	second.get_node("CenterContainer/Dome/Contacts").auto_spawn = false
	root.add_child(second)
	await process_frame
	check(second.settings.difficulty == 1 and not second.settings.auto_repair and second.settings.effects_volume == 35, "A new start with Remember OFF: NORMAL, autos off, volume kept")
	second.free()
	console._on_settings_changed({"remember_settings": true, "difficulty": 1})
	console.open_settings()
	var panel = console.settings_panel
	check(panel.remember_button.button_pressed and panel.remember_button.text == "ON" and panel.auto_repair_button.text == "OFF", "Panel shows REMEMBER SETTINGS ON and AUTO RAPID REPAIR OFF")
	panel.auto_repair_button.button_pressed = true
	check(console.settings.auto_repair and c.auto_rapid_repair, "AUTO RAPID REPAIR button turns the option on")
	check(panel.multiplier_label.text.contains("x0.90"), "Score multiplier shows the repair option (x0.90)")
	panel.effects_slider.value = 20
	panel.reset_button.pressed.emit()
	check(panel.reset_button.text == "CONFIRM" and console.settings.effects_volume == 20, "DEFAULTS asks for confirmation first (1.05: renamed from RESET TO DEFAULTS)")
	panel.reset_button.pressed.emit()
	check(console.settings.effects_volume == 50 and not console.settings.auto_repair and console.settings.remember_settings and panel.reset_button.text == "DEFAULTS", "Second press resets to defaults")
	var buttons: Array[Button] = []
	var labels: Array[Label] = []
	for child in panel.panel.get_children():
		if child is Button:
			buttons.append(child)
		elif child is Label:
			labels.append(child)
	var overlaps := 0
	for i in range(buttons.size()):
		for j in range(i + 1, buttons.size()):
			if rect_of(buttons[i]).intersects(rect_of(buttons[j])):
				overlaps += 1
	for label in labels:
		if label.text == "":
			continue
		for button in buttons:
			if text_rect(label).intersects(rect_of(button)):
				overlaps += 1
	var inside := true
	for button in buttons:
		inside = inside and Rect2(Vector2.ZERO, panel.PANEL_SIZE).encloses(rect_of(button))
	check(overlaps == 0, "Settings panel: no overlapping buttons or text")
	check(inside and panel.PANEL_SIZE.y <= 1060.0, "Settings panel fits the 1080-pixel layout (1.1.0: at least 10 px above and below)")
	console.close_settings()

	# --- 6. Explosions for fighters and capital ships ---
	clean()
	check(c.craft_explosions_enabled and c.craft_explosion_seconds == 0.4, "Fighter explosions on, about 0.4 s")
	var b6 := base()
	var drone: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b6.id))
	c.screen_flash_remaining = 0.0
	c._award_destroyed(drone)
	check(c.explosions.size() == 1 and c.explosions[0].kind == "craft" and c.booms_played.craft == 1, "Destroyed Attack Drone: small burst and short boom")
	check(c.screen_flash_alpha() == 0.0, "No screen flash for a fighter")
	c.breachers_enabled = true
	var heavy: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b6.id))
	check(not heavy.is_empty(), "Breacher spawned for the test")
	if not heavy.is_empty():
		for i in range(int(heavy.health)):
			c._hit_breacher(heavy)
	check(c.explosions.size() == 2 and c.explosions[1].kind == "heavy" and c.booms_played.heavy == 1, "Destroyed Breacher: bigger burst and boom")
	check(c.explosion_life("heavy") > c.explosion_life("craft") and c.heavy_explosion_scale > 1.0, "Breacher burst lasts longer and is larger")
	c.launch_interceptors()
	var interceptor := {}
	for contact in c.contacts:
		if contact.kind == "interceptor":
			interceptor = contact
	c.battle_time += 1.0
	c._lose_fighter(interceptor, "TEST")
	check(c.explosions.size() == 3 and c.explosions[2].kind == "own_craft", "Lost Interceptor: own-colour burst")
	check(c.own_craft_color != c.enemy_craft_color and c.own_craft_color.g > c.own_craft_color.r, "Own losses burst green-white, enemy fighters orange")
	c.battle_time += 1.0
	var r1: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b6.id))
	var r2: Dictionary = c.find_contact(c.spawn_from_carrier("drone", b6.id))
	var booms_before: int = c.booms_played.craft
	c._award_destroyed(r1)
	c._award_destroyed(r2)
	check(c.booms_played.craft == booms_before + 1, "Two fighters at once: one boom (no loud stacking)")
	c.screen_flash_remaining = 0.0
	c._hit_carrier(b6, 999.0)
	var capital_found := false
	for blast in c.explosions:
		capital_found = capital_found or blast.kind == "capital"
	check(capital_found and c.booms_played.capital == 1 and c.capital_explosions == 1, "Destroyed Enemy Carrier: large explosion and deep boom")
	check(c.screen_flash_alpha() > 0.2, "Enemy Carrier explosion flashes the screen once")
	check(c.explosion_life("capital") > c.explosion_life("nuke"), "Capital explosion is longer than a nuke's")
	clean()
	c.siege_enabled = true
	var rid: String = c.spawn_siege_ship()
	var rs: Dictionary = c.find_contact(rid)
	check(not rs.is_empty(), "Siege Ship spawned for the test")
	c.battle_time += 1.0
	if not rs.is_empty():
		c._hit_siege(rs, 999.0, "TEST")
	check(c.capital_explosions == 1 and c.booms_played.capital == 1, "Destroyed Siege Ship: large explosion and deep boom")
	c.screen_flash_enabled = false
	c.screen_flash_remaining = 0.0
	c._explode(Vector3.ZERO, "capital")
	check(c.screen_flash_alpha() == 0.0, "Screen flash switch also covers capital explosions")
	c.screen_flash_enabled = true
	c.craft_explosions_enabled = false
	var count_before: int = c.explosions.size()
	c.battle_time += 1.0
	var crafts_before: int = c.booms_played.craft
	c._explode(Vector3.ZERO, "craft")
	check(c.explosions.size() == count_before and c.booms_played.craft == crafts_before, "Fighter explosions can be switched off in the Inspector")
	c.craft_explosions_enabled = true
	var craft_wav := BattleAudio.make_craft_boom()
	var heavy_wav := BattleAudio.make_heavy_boom()
	var capital_wav := BattleAudio.make_capital_boom()
	check(near(craft_wav.data.size() / 96000.0, 0.26, 0.01) and near(heavy_wav.data.size() / 96000.0, 0.45, 0.01) and near(capital_wav.data.size() / 96000.0, 2.0, 0.01), "New booms are 0.26 s, 0.45 s and 2.0 s")
	check(peak(craft_wav) <= 0.81 and peak(heavy_wav) <= 0.86 and peak(capital_wav) <= 0.86 and peak(capital_wav) > 0.3, "New booms stay below clipping")
	check(c.craft_boom_volume_db < c.missile_boom_volume_db and c.capital_boom_volume_db > c.nuke_boom_volume_db - 3.0, "Fighter boom is quieter than the missile boom; capital boom is close to the nuke boom")
	check(c.craft_boom_player.bus == "Effects" and c.heavy_boom_player.bus == "Effects" and c.capital_boom_player.bus == "Effects", "New booms follow the Effects volume and mute")

	for f in [console.settings_file, console.high_score_file, "user://v104_test_scores_2.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("V104_RESULT checks=%d failures=%d" % [checks, failures])
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
