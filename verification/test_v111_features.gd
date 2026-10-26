extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
## Stellar Defense Console 1.1.1: the Breacher warning box moves down beside the
## ship outline (clear of the battle readout), shows from the approach stage, and
## the approach line reads PREPARE FIREWALL DEFENSE.
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
func box_rect(alert: Label) -> Rect2:
	# Same rectangle ConsoleFrame._draw_hack_box draws.
	# 1.2.0: the box now has a fixed five-line height.
	var text_height: float = maxf(alert.get_parent().hack_text_height(), alert.size.y)
	return Rect2(alert.position - Vector2(10, 8), Vector2(alert.size.x + 20, text_height + 16))
func base(c: Control) -> Dictionary:
	var b: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(b)
	b.drone_timer = 99.0
	b.missile_timer = 99.0
	b.heavy_timer = 99.0
	return b
func layout(console: Control, c: Control, state: String, lines: int) -> void:
	console._process(0.0)
	var alert: Label = console.get_node("HackAlert")
	var box := box_rect(alert)
	var readout: Label = console.battle_readout
	var readout_bottom := readout.global_position.y + readout.get_line_count() * readout.get_line_height()
	var emp: Label = console.emp_readout
	var buttons: Control = console.get_node("BottomButtons")
	check(c.hack_state() == state, "State is %s" % state)
	check(alert.visible and alert.get_line_count() == lines, "%s: warning shows %d lines" % [state, lines])
	check(box.position.y > emp.get_global_rect().end.y and box.position.y > readout_bottom, "%s: warning box sits below the battle readout and EMP CHARGES" % state)
	check(not box.intersects(emp.get_global_rect()) and not box.intersects(readout.get_global_rect()), "%s: warning box does not overlap the readout" % state)
	check(not console.pulse_readout.visible or not box.intersects(console.pulse_readout.get_global_rect()), "%s: warning box does not overlap the PULSE BOMB line (1.1.0)" % state)
	check(box.end.x <= 760.0, "%s: warning box stays left of the ship outline (x %.0f)" % [state, box.end.x])
	check(box.end.y <= 966.0 and box.end.y < buttons.get_global_rect().position.y, "%s: warning box stays above the bottom divider and buttons (y %.0f)" % [state, box.end.y])
	check(box.position.x >= 82.0, "%s: warning box stays inside the left edge" % state)
	print("V111_BOX ", state, " ", box)

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://test_v111_scores.json"
	console.settings_file = "user://test_v111.cfg"
	console.quit_dry_run = true
	console.shell_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	c.auto_spawn = false
	root.add_child(console)
	c.set_process(false)
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.difficulty = 1
	c.reset_battle()
	c.waves_enabled = false
	# --- Version 1.1.1 ---
	check(ProjectSettings.get_setting("application/config/version") == "1.1.1", "Project version is 1.1.1")
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.1.1", "Version text reads STELLAR DEFENSE CONSOLE 1.1.1")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(String(presets.get_value("preset.0", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Windows_x64.exe")
		and String(presets.get_value("preset.1", "export_path", "")).ends_with("Stellar_Defense_Console_1.1.1_Mac.zip")
		and presets.get_value("preset.1.options", "application/version", "") == "1.1.1", "Export presets name 1.1.1 files")
	# --- Scene values (editable in the Inspector) ---
	var alert: Label = console.get_node("HackAlert")
	check(alert.offset_left == 390.0 and alert.offset_top == 824.0 and alert.offset_right == 745.0 and alert.offset_bottom == 958.0, "HackAlert sits beside the ship outline (390, 824)-(745, 958)")
	check(alert.get_theme_font_size("font_size") == 17, "HackAlert font size is 17")
	# --- Hidden until a Breacher appears ---
	console._process(0.0)
	check(c.hack_state() == "" and not alert.visible and c.hacking_warning() == "", "No Breacher: warning and box hidden")
	c.kills = {"drone": 312, "breacher": 41, "missile": 188, "nuke": 22, "carrier": 18, "siege_ship": 2}
	c.emp_charges = 2
	var b := base(c)
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b.id))
	check(c.hacking_warning() == "BREACHER APPROACHING\nPREPARE FIREWALL DEFENSE", "Approach warning reads BREACHER APPROACHING / PREPARE FIREWALL DEFENSE")
	check(not c.hacking_warning().contains("BATTERY CANNOT"), "Old BATTERY CANNOT STOP IT line removed")
	layout(console, c, "approach", 2)
	h.position = h.hack_point
	c._update_breachers(0.0)
	check(c.hacking_warning().begins_with("BREACHER HACKING SHIP") and c.hacking_warning().contains("BREACH IN"), "Hack start adds the hacking lines in the same box")
	layout(console, c, "hacking", 4)
	for i in range(14):
		c._update_breachers(0.5)
	var b2 := base(c)
	var h2: Dictionary = c.find_contact(c.spawn_from_carrier("breacher", b2.id))
	h2.position = h2.hack_point
	c._update_breachers(0.0)
	c.set_firewall(true)
	layout(console, c, "draining", 5)
	print("V111_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
