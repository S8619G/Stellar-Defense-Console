extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.06: full build naming, hover tooltips off by default,
## the version text as a centered link to the log folder (DIAGNOSTIC LOG row
## removed), missiles and nukes drawn on top, the Rapid Repair sound and green
## outline pulse, and the EMP defense against hacking Breachers.
const GameSettings = preload("res://scripts/GameSettings.gd")
const BattleAudio = preload("res://scripts/BattleAudio.gd")
var console: Control
var c: Control
var ship: Control
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
func clean(level: int = 1) -> void:
	c.difficulty = level
	c.auto_spawn = false
	c.breachers_enabled = true
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
	# 1.07: the 1.06 USE EMP box is now an option; the Firewall is off here so the EMP is offered at once.
	c.firewall_enabled = false
	ship.emp_on_ship = true
	c.reset_battle()
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
func peak(stream: AudioStreamWAV, from_s := 0.0, to_s := 99.0) -> float:
	var top := 0
	var start := int(from_s * stream.mix_rate) * 2
	var stop := mini(stream.data.size(), int(to_s * stream.mix_rate) * 2)
	for i in range(start, stop, 2):
		top = maxi(top, absi(stream.data.decode_s16(i)))
	return top / 32767.0
func pitch(stream: AudioStreamWAV, from_s: float, to_s: float) -> float:
	var crossings := 0
	var previous := 0
	for i in range(int(from_s * stream.mix_rate), int(to_s * stream.mix_rate)):
		var v := stream.data.decode_s16(i * 2)
		if previous < 0 and v >= 0:
			crossings += 1
		previous = v
	return crossings / (to_s - from_s)
func seconds_of(stream: AudioStreamWAV) -> float:
	return stream.data.size() / 2.0 / stream.mix_rate
func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://v106_test_settings.cfg"
	console.high_score_file = "user://v106_test_scores.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	if FileAccess.file_exists(console.settings_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(console.settings_file))
	c = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	ship = console.get_node("ShipStatus")
	c.auto_spawn = false
	c.random_seed = 1006
	root.add_child(console)
	c.set_process(false)
	console.get_node("TuningPanel").visible = false
	clean()

	# --- Full build naming ---
	check(ProjectSettings.get_setting("application/config/version") == "1.0.9", "Project version is 1.06")
	check(not console.test_build, "Test Build is off by default (full build)")
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.0.9", "Version text reads STELLAR DEFENSE CONSOLE 1.06 (no TEST)")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.0.9_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.0.9_Mac.zip")
		and presets.get_value("preset.1.options", "application/version", "") == "1.0.9", "Export presets name 1.06 files (no Test)")

	# --- Hover tooltips off by default ---
	await frames(2)
	var repair_button: Button = console.get_node("BottomButtons/RapidRepair")
	check(not console.show_hover_tooltips, "Show Hover Tooltips is off by default")
	var shown := 0
	var kept := 0
	for node in console.find_children("*", "Control", true, false):
		if not (node as Control).tooltip_text.is_empty():
			shown += 1
		if node.has_meta("hover_tip") and not String(node.get_meta("hover_tip")).is_empty():
			kept += 1
	check(shown == 0, "No control shows a hover pop-up (%d with text)" % shown)
	check(kept >= 10, "The help text is kept in place for later (%d controls)" % kept)
	check(String(repair_button.get_meta("hover_tip", "")).contains("25000"), "Rapid Repair help text still lists the milestones")
	console.show_hover_tooltips = true
	console._process(0.016)
	check(repair_button.tooltip_text.contains("25000"), "Ticking Show Hover Tooltips brings the pop-ups back")
	console.show_hover_tooltips = false
	console._process(0.016)
	check(repair_button.tooltip_text.is_empty(), "Unticking it hides them again")

	# --- Settings: centered version link, no DIAGNOSTIC LOG row ---
	console.open_settings()
	await frames(2)
	var panel: Control = console.settings_panel
	var row_texts: Array[String] = []
	for child in panel.panel.get_children():
		if child is Label:
			row_texts.append((child as Label).text)
		elif child is Button and not (child is LinkButton):
			row_texts.append((child as Button).text)
	check(not row_texts.has("DIAGNOSTIC LOG") and not row_texts.has("OPEN LOG FOLDER"), "DIAGNOSTIC LOG row and OPEN LOG FOLDER button removed")
	check(not ("open_logs_button" in panel), "No OPEN LOG FOLDER button in the panel code")
	check(panel.PANEL_SIZE == Vector2(860, 988), "Panel is 988 px tall (1.0.8: one row added for SCREEN EFFECTS)")
	var link: LinkButton = panel.version_label
	check(link is LinkButton and link.text == "STELLAR DEFENSE CONSOLE 1.0.9", "Version text is a link reading STELLAR DEFENSE CONSOLE 1.06")
	var link_rect := Rect2(link.get_global_position() - panel.panel.get_global_position(), link.size)
	# 1.08: the version text and the "!" icon beside it are centered together.
	var icon_rect := Rect2(panel.log_icon_button.get_global_position() - panel.panel.get_global_position(), panel.log_icon_button.size)
	var row_rect := link_rect.merge(icon_rect)
	check(absf(row_rect.get_center().x - panel.PANEL_SIZE.x * 0.5) <= 1.5, "Version link is centered on the panel (%.1f vs %.1f)" % [row_rect.get_center().x, panel.PANEL_SIZE.x * 0.5])
	var close_rect := rect_of(panel.close_button)
	check(link_rect.position.y >= close_rect.end.y and link_rect.end.y <= panel.PANEL_SIZE.y, "Version link sits below the bottom buttons, inside the panel")
	check(link.get_theme_font_size("font_size") <= 16 and link.get_theme_color("font_color").a <= 0.7, "Version link stays small and dim")
	check(link.underline == LinkButton.UNDERLINE_MODE_ON_HOVER, "Version link underlines on hover, so it reads as a link")
	var opens: int = console.log_folder_opens
	panel.log_icon_button.pressed.emit()  # 1.08: the "!" icon opens the folder; the version text opens GitHub.
	check(console.log_folder_opens == opens + 1, "Clicking the version link opens the log folder (dry run in tests)")
	check(String(panel.log_icon_button.get_meta("hover_tip", "")).contains("log") and link.tooltip_text.is_empty(), "Version link help text kept but not popped up")
	var buttons: Array[Control] = []
	var labels: Array[Label] = []
	for child in panel.panel.get_children():
		if child is Button:
			buttons.append(child)
		elif child is Label:
			labels.append(child)
	buttons.append(link)
	var overlaps := 0
	for i in range(buttons.size()):
		for j in range(i + 1, buttons.size()):
			var a := link_rect if buttons[i] == link else rect_of(buttons[i])
			var b2 := link_rect if buttons[j] == link else rect_of(buttons[j])
			if a.intersects(b2):
				overlaps += 1
	for label in labels:
		if label.text == "" or not label.visible:
			continue
		for button in buttons:
			var r := link_rect if button == link else rect_of(button)
			if text_rect(label).intersects(r):
				overlaps += 1
	check(overlaps == 0, "Settings panel: no overlapping buttons or text (%d controls)" % buttons.size())
	check(panel.panel.position.y >= 0.0 and panel.PANEL_SIZE.y <= 1000.0, "Settings panel fits the 1080-pixel layout")
	console.close_settings()

	# --- Missiles and nukes on top ---
	check(c.PROJECTILE_KINDS == ["missile", "own_missile", "gunship_missile", "nuke", "flak"], "Missiles, ship and Gunship missiles, nukes and flak are drawn as one top group")
	var src := FileAccess.get_file_as_string("res://scripts/RadarContacts.gd")
	var draw_code := src.substr(src.find("func _draw() -> void:"), 1600)
	var ships_at := draw_code.find("_draw_contact(contact, font)")
	var squads_at := draw_code.find("_draw_interceptor_squadrons(font)")
	var blasts_at := draw_code.find("_draw_explosions()")
	var top_at := draw_code.find("for contact in projectiles:")
	check(ships_at > 0 and squads_at > ships_at and blasts_at > squads_at and top_at > blasts_at, "Draw order: ships and labels, squadrons, explosions, then missiles and nukes")
	check(draw_code.find("_draw_jump_flash()") > top_at, "Only the full-screen JUMP flash is drawn over the missiles")

	# --- Rapid Repair sound and outline pulse ---
	clean()
	var stream: AudioStreamWAV = c.repair_sound_player.stream
	check(absf(seconds_of(stream) - c.rapid_repair_seconds) < 0.05, "Repair sound lasts the length of the repair (%.2f s)" % seconds_of(stream))
	check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Repair sound does not loop")
	check(pitch(stream, 0.3, 0.8) * 1.8 < pitch(stream, 4.0, 4.5), "Repair sound rises like a recharge (%.0f Hz to %.0f Hz)" % [pitch(stream, 0.3, 0.8), pitch(stream, 4.0, 4.5)])
	check(peak(stream) < 0.8 and peak(stream) > 0.2, "Repair sound is clear and below clipping (peak %.2f)" % peak(stream))
	check(c.repair_sound_volume_db < c.klaxon_volume_db - 6.0 and c.emp_zap_volume_db < c.klaxon_volume_db, "Repair sound sits below the alerts (%.0f dB)" % c.repair_sound_volume_db)
	check(c.repair_sound_player.bus == GameSettings.EFFECTS_BUS, "Repair sound follows the Effects volume and mute")
	check(c.repair_flash_level() == 0.0, "No pulse while no repair runs")
	c.hull = c.max_hull * 0.5
	check(c.request_rapid_repair(), "Rapid Repair starts")
	check(c.repair_sounds == 1 and c.repair_sound_player.playing, "Repair sound starts with the repair")
	var levels: Array[float] = []
	for step in range(30):
		c.battle_time += 0.05
		levels.append(c.repair_flash_level())
	check(levels.max() > 0.95 and levels.min() < 0.05, "Outline pulses fully during the repair (%.2f to %.2f)" % [levels.min(), levels.max()])
	var tint_src := FileAccess.get_file_as_string("res://scripts/ShipStatus.gd")
	check(tint_src.contains("tint = tint.lerp(repair_green, repair_pulse)") and ship.repair_green.g > 0.9 and ship.repair_green.g > ship.repair_green.r, "The pulse goes to a brighter green")
	check(tint_src.find("repair_pulse") < tint_src.find("hit_flash_remaining > 0.0"), "A missile hit still flashes red over the pulse")
	for step in range(int(c.rapid_repair_seconds * 60.0) + 30):
		c._process(1.0 / 60.0)
	check(c.rapid_repair_remaining <= 0.0 and c.repair_flash_level() == 0.0, "Pulse stops when the repair ends")
	check(not c.repair_sound_player.playing, "Repair sound stops when the repair ends")
	c.auto_rapid_repair = true
	c.hull = c.max_hull * 0.4
	c.repair_charges = 1
	c._update_automation()
	check(c.repair_sounds == 2, "AUTO RAPID REPAIR plays the same sound")
	c.auto_rapid_repair = false
	c.repair_sound_enabled = false
	c.rapid_repair_remaining = 0.0
	c.repair_charges = 1
	c.request_rapid_repair()
	check(c.repair_sounds == 2, "Repair sound can be switched off in the Inspector")
	c.repair_sound_enabled = true
	c.repair_flash_enabled = false
	check(c.repair_flash_level() == 0.0, "Pulse can be switched off in the Inspector")
	c.repair_flash_enabled = true
	c.hull = c.max_hull * 0.3
	c.rapid_repair_remaining = 2.0
	c.apply_damage(c.max_hull)
	c._process(0.016)
	check(not c.repair_sound_player.playing and c.repair_flash_level() == 0.0, "Game over stops the repair sound and pulse")

	# --- EMP charges ---
	clean()
	check(c.emp_enabled and c.emp_points_per_charge == 5000 and c.emp_max_charges == 2, "EMP: one charge per 5,000 points, up to 2")
	check(c.emp_charges == 0, "A battle starts with no EMP charge")
	c._add_points(4990)
	check(c.emp_charges == 0, "4,990 earned: no charge yet")
	c._add_points(10)
	check(c.emp_charges == 1, "5,000 earned: one charge")
	c._add_points(5000)
	check(c.emp_charges == 2, "10,000 earned: two charges")
	c._add_points(5000)
	check(c.emp_charges == 2, "15,000 earned: still two (most held)")
	c.score = 5000
	c.request_jump()
	check(c.emp_charges == 2, "An JUMP jump keeps the charges")
	c.jump_recharge_remaining = 0.0
	c.safe_remaining = 0.0
	console._process(0.016)
	check(console.emp_readout.text == "EMP CHARGES  2", "Sidebar shows EMP CHARGES 2 (1.1.0: its own EMP-blue line)")
	c.reset_battle()
	check(c.emp_charges == 0, "Retry / new battle starts with no charge")

	# --- USE EMP appears only while hacking with a charge ---
	clean()
	c.emp_charges = 1
	await frames(2)
	check(not c.can_use_emp() and not ship.emp_button.visible, "No USE EMP while nothing is hacking")
	var b := base()
	var h := hacker(b)
	check(not h.is_empty() and h.phase == "hacking", "Setup: a Breacher is hacking")
	c.emp_charges = 0
	await frames(2)
	check(not c.can_use_emp() and not ship.emp_button.visible, "Hacking without a charge: INTRUSION DETECTION, no USE EMP")
	c.emp_charges = 1
	await frames(2)
	check(c.can_use_emp() and ship.emp_button.visible, "Hacking with a charge: USE EMP can be clicked")
	var middle: Vector2 = ship.emp_box.get_center()
	var width: float = minf(ship.size.x, ship.size.y * ship.REGION.size.x / ship.REGION.size.y)
	var rect := Rect2((ship.size - Vector2(width, width * ship.REGION.size.y / ship.REGION.size.x)) * 0.5, Vector2(width, width * ship.REGION.size.y / ship.REGION.size.x))
	check(middle.distance_to(rect.position + rect.size * Vector2(0.49, 0.5)) < 1.0 and ship.emp_box.size == ship.intrusion_box_size, "USE EMP takes the place of INTRUSION DETECTION in the middle of the ship")
	check(rect_of(ship.emp_button).is_equal_approx(ship.emp_box), "The click area covers the USE EMP box (%s vs %s)" % [rect_of(ship.emp_button), ship.emp_box])
	var status_src := FileAccess.get_file_as_string("res://scripts/ShipStatus.gd")
	check(status_src.contains("var title := \"USE EMP\"") and status_src.contains("if emp_on_ship and battle.can_use_emp():\n\t\t_draw_use_emp(middle)\n\telif battle.hack_state()"), "Box reads USE EMP instead of INTRUSION DETECTION")
	var zaps_before: int = c.emp_uses
	var hull_before: float = c.hull
	var score_before: int = c.score
	var destroyed_before: int = c.breachers_destroyed
	ship.emp_button.pressed.emit()
	check(c.emp_uses == zaps_before + 1 and c.emp_charges == 0, "Clicking USE EMP uses one charge")
	check(h.phase == "emp", "The Breacher is overloaded")
	check(c.emp_player.playing, "The electric zap plays")
	check(c.status_message.begins_with("EMP DISCHARGED"), "Status line: EMP DISCHARGED")
	await frames(2)
	check(not ship.emp_button.visible, "USE EMP disappears once used")
	var blue: Color = c.display_color(h)
	check(blue.b > 0.9 and blue.b > blue.r + 0.3, "Overloaded Breacher shimmers electric blue")
	var tints: Array[float] = []
	for step in range(10):
		c.battle_time += 0.02
		tints.append(c.display_color(h).a)
	check(tints.max() - tints.min() > 0.15, "The blue shimmers (brightness changes)")
	check(c.hack_state() == "", "The hack stops at once")
	for step in range(9):
		c._update_breachers(0.1)
	check(h.phase == "emp", "Shimmer lasts about a second")
	for step in range(3):
		c._update_breachers(0.1)
	check(h.phase == "emp_return", "Then it turns back toward its Enemy Carrier")
	var gap_start: float = h.position.distance_to(b.position)
	for step in range(30):
		c._update_breachers(0.1)
	check(h.position.distance_to(b.position) < gap_start - 0.05, "It flies back to its Enemy Carrier")
	check(c.hull == hull_before, "No hull drain while it returns")
	check(c.hack_state() == "" and not c.hacking_warning().contains("APPROACHING"), "A returning Breacher is not shown as approaching")
	var docked := false
	for step in range(600):
		c._update_breachers(0.1)
		if c.find_contact(h.id).is_empty():
			docked = true
			break
	check(docked and c.emp_heavies_docked == 1, "It docks at the Enemy Carrier for repairs")
	check(c.breachers_destroyed == destroyed_before and c.score == score_before, "Not destroyed and no points")
	check(c.count_base_heavies(b.id) == 0, "Its Enemy Carrier can launch a repaired Breacher later")

	# --- Several hackers, draining, no Enemy Carrier ---
	clean()
	c.max_breachers = 2
	var b1 := base()
	var b2 := base()
	var h1 := hacker(b1)
	var h2 := hacker(b2)
	h2.hack_remaining = 0.0
	c._update_breachers(0.1)
	check(h1.phase == "hacking" and h2.phase == "draining", "Setup: one hacking and one draining")
	c.emp_charges = 2
	check(c.request_emp() and h1.phase == "emp" and h2.phase == "emp" and c.emp_charges == 1, "One EMP overloads every hacking and draining Breacher")
	check(not c.can_use_emp(), "With nothing hacking, the second charge waits")
	c._remove_contact(b1.id)
	c._remove_contact(b2.id)
	for step in range(12):
		c._update_breachers(0.1)
	var gone := false
	for step in range(120):
		c._update_breachers(0.1)
		if c.count_kind("breacher") == 0:
			gone = true
			break
	check(gone, "With no Enemy Carrier left, they fly off the scope")
	clean()
	c.emp_enabled = false
	var b3 := base()
	hacker(b3)
	c.emp_charges = 1
	check(not c.can_use_emp() and not c.request_emp(), "EMP can be switched off in the Inspector")
	c.emp_enabled = true

	# --- Manual only; sounds ---
	check(not GameSettings.DEFAULTS.has("auto_emp") and not ("auto_emp" in c), "No AUTO EMP option (manual only)")
	var zap: AudioStreamWAV = c.emp_player.stream
	check(seconds_of(zap) > 0.4 and seconds_of(zap) < 1.2 and zap.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Zap is short (%.2f s) and does not loop" % seconds_of(zap))
	check(peak(zap) > 0.3 and peak(zap) < 0.86, "Zap is sharp and below clipping (peak %.2f)" % peak(zap))
	check(peak(zap, 0.0, 0.1) > peak(zap, 0.55, 0.7) * 2.0, "Zap snaps at the start and fades")
	check(c.emp_player.bus == GameSettings.EFFECTS_BUS, "Zap follows the Effects volume and mute")
	var label_src := src.substr(src.find("func contact_tag("), 6000)  # 1.07: tags moved to contact_tag
	check(label_src.contains("\"EMP OVERLOAD\"") and not label_src.contains("\"BREACHER RTB\""), "Labels: EMP OVERLOAD; 1.09 drops the RTB tag (the flash shows the return)")

	# --- Session log ---
	clean()
	var log_text := ""
	var b4 := base()
	hacker(b4)
	c.emp_charges = 1
	await frames(2)
	if ship.emp_button.visible:
		ship.emp_button.pressed.emit()
	if is_instance_valid(console.session_log):
		log_text = FileAccess.get_file_as_string(console.session_log.file_path)
	check(log_text.contains("EMP used"), "Session log records EMP use")

	# --- Preserved ---
	check(not console.development_build and absf(console.sweep_volume_db + 20.0) < 0.01, "Development Build off by default; sweep still -20 dB")
	check(is_equal_approx(c.hard_nuke_speed, 1.45) and c.normal_double_missile_points == 17500 and c.battery_kill_points == 10, "1.05 values unchanged (Hard nuke speed 1.45 since 1.2.7)")

	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("V106_RESULT checks=%d failures=%d" % [checks, failures])
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
