extends SceneTree
## 1.1.0 balance runs: seeded all-auto battles, one line per battle.
## BAL_CONFIG: full (1.1.0 as shipped), no_priority (Interceptors use the 1.0.9
## targeting), no_pulse (no PULSE BOMB), jump_flat (JUMP always 3,000),
## no_repair_limit (no Rapid Repair limit), set_back (all of these at 1.0.9 values).
## BAL_PRESS_PULSE=1: act like a player who presses the stealth weapon button with a
## PULSE BOMB held once 2 or more large ships are on screen (the autos never press it).
## BAL_DIFF: 1 or 2. BAL_SEEDS: comma list. BAL_MINUTES: longest battle. BAL_OUT: file.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var config := OS.get_environment("BAL_CONFIG")
	var difficulty := int(OS.get_environment("BAL_DIFF"))
	var minutes := float(OS.get_environment("BAL_MINUTES")) if OS.get_environment("BAL_MINUTES") != "" else 30.0
	var out := FileAccess.open(OS.get_environment("BAL_OUT"), FileAccess.WRITE)
	for seed_text in OS.get_environment("BAL_SEEDS").split(","):
		var line: String = await _battle(config, difficulty, int(seed_text), minutes)
		out.store_line(line)
		out.flush()
		print(line)
	out.close()
	quit(0)

func _battle(config: String, difficulty: int, seed: int, minutes: float) -> String:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://bal_scores_%d.json" % OS.get_process_id()
	console.settings_file = "user://bal_settings_%d.cfg" % OS.get_process_id()
	console.quit_dry_run = true
	console.shell_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	root.add_child(console)
	await process_frame
	c.set_process(false)
	c.klaxon_enabled = false
	c.arrival_sound_enabled = false
	c.launch_sound_enabled = false
	c.wave_cues_enabled = false
	c.auto_spawn = true
	c.difficulty = difficulty
	for p in c.get_property_list():
		var n: String = p.name
		if n.begins_with("auto_") and n != "auto_spawn" and p.type == TYPE_BOOL:
			c.set(n, true)
	var back := {
		"no_priority": [["interceptors_hacking_breachers_first", false]],
		"no_pulse": [["pulse_bomb_enabled", false]],
		"jump_flat": [["jump_score_percent", 0.0]],
		"no_repair_limit": [["rapid_repair_limit_easy", 0], ["rapid_repair_limit", 0]],
		"set_back": [["jump_score_percent", 0.0], ["rapid_repair_limit_easy", 0], ["rapid_repair_limit", 0],
			["interceptors_hacking_breachers_first", false], ["pulse_bomb_enabled", false]],
	}
	for pair in back.get(config, []):
		c.set(pair[0], pair[1])
	c.rng.seed = seed
	c.reset_battle()
	var jumps := [0, 0]
	c.jump_completed.connect(func() -> void:
		jumps[0] += 1
		jumps[1] += int(c.last_jump_cost))
	var step := 1.0 / 30.0
	var t := 0.0
	var low_hull := 100.0
	var press_pulse := OS.get_environment("BAL_PRESS_PULSE") == "1"
	while t < minutes * 60.0 and not c.is_defeated():
		if press_pulse and c.pulse_charges > 0 and c.large_ship_count() >= 2 and c.can_launch_stealth():
			c.launch_stealth(true)
		c._process(step)
		t += step
		low_hull = minf(low_hull, c.hull)
	var line := "%s%s d%d s%d time %.1f min %s score %d wave %d jumps %d jump_points %d pulse %d breachers %d repair_lost %d" % [
		config, " press" if press_pulse else "", difficulty, seed, t / 60.0, "DEFEATED" if c.is_defeated() else "ALIVE", c.score, c.wave,
		jumps[0], jumps[1], int(c.pulse_detonations), int(c.breachers_destroyed), int(c.get("repair_charges_lost"))]
	console.queue_free()
	await process_frame
	return line
