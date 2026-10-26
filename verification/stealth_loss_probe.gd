extends SceneTree
## 1.1.1 Stealth Interceptor loss-rate probe (BACKLOG "Stealth Interceptor: fire from
## farther out and get home safer"). Normal, all-auto, up to 15 minutes per battle. Each
## time the Stealth Interceptor can launch, the probe launches it, alternating a nukes run
## and a PULSE BOMB run (a PULSE BOMB is handed over for the PULSE runs when none is held).
## PROBE_CONFIG: new (1.1.1 values) or old (the three settings at 1.1.0 values).
## PROBE_SEEDS: comma list. PROBE_OUT: file.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var config := OS.get_environment("PROBE_CONFIG")
	var seeds := OS.get_environment("PROBE_SEEDS")
	if seeds == "":
		seeds = "11,4242,7,99,2026,314,5,77,123,808"
	var out := FileAccess.open(OS.get_environment("PROBE_OUT"), FileAccess.WRITE)
	var totals := {"runs": 0, "lost": 0, "nukes": 0, "nukes_lost": 0, "pulse": 0, "pulse_lost": 0}
	for seed_text in seeds.split(","):
		var r: Dictionary = await _battle(config, int(seed_text))
		for k in totals:
			totals[k] += int(r[k])
		out.store_line(r.line)
		out.flush()
		print(r.line)
	var total := "%s TOTAL lost %d of %d runs (nukes %d of %d, PULSE %d of %d)" % [config, totals.lost, totals.runs,
		totals.nukes_lost, totals.nukes, totals.pulse_lost, totals.pulse]
	out.store_line(total)
	out.close()
	print(total)
	quit(0)

func _battle(config: String, seed: int) -> Dictionary:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://probe_scores_%d.json" % OS.get_process_id()
	console.settings_file = "user://probe_settings_%d.cfg" % OS.get_process_id()
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
	c.difficulty = 1
	c.active_difficulty = 1
	for p in c.get_property_list():
		var n: String = p.name
		if n.begins_with("auto_") and n != "auto_spawn" and p.type == TYPE_BOOL:
			c.set(n, true)
	if config == "old":
		c.stealth_fire_range = 0.35
		c.stealth_shot_seconds = 4.0
		c.stealth_home_turn = 1.0
	c.rng.seed = seed
	c.reset_battle()
	c.active_difficulty = 1
	var r := {"runs": 0, "lost": 0, "nukes": 0, "nukes_lost": 0, "pulse": 0, "pulse_lost": 0}
	var want_pulse := false
	var current := ""
	var lost_before := 0
	var step := 1.0 / 30.0
	var t := 0.0
	while t < 15.0 * 60.0 and not c.is_defeated():
		if current == "" and c.can_launch_stealth():
			# Every other run is a PULSE BOMB run: the probe hands over a PULSE BOMB when none
			# has been earned yet, so both kinds of run are tested equally.
			if want_pulse and int(c.pulse_charges) <= 0:
				c.pulse_charges = 1
			var pulse: bool = want_pulse and int(c.pulse_charges) > 0
			if bool(c.launch_stealth(pulse)):
				current = "pulse" if pulse else "nukes"
				r.runs += 1
				r[current] += 1
				lost_before = int(c.stealth_lost)
				if pulse or not want_pulse:
					want_pulse = not want_pulse
		c._process(step)
		t += step
		if current != "" and not bool(c.stealth_out()):
			if int(c.stealth_lost) > lost_before:
				r.lost += 1
				r[current + "_lost"] += 1
			current = ""
	r.line = "%s s%d time %.1f min %s runs %d lost %d (nukes %d/%d, PULSE %d/%d) score %d" % [config, seed, t / 60.0,
		"DEFEATED" if c.is_defeated() else "ALIVE", r.runs, r.lost, r.nukes_lost, r.nukes, r.pulse_lost, r.pulse, c.score]
	console.queue_free()
	await process_frame
	return r
