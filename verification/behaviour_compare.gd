extends SceneTree
## Seeded battle fingerprint, identical script for both versions (no version-specific names).
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var out := []
	for difficulty in [0, 1, 2]:
		for seed in [11, 4242]:
			for autos in [false, true]:
				out.append(await _battle(difficulty, seed, autos))
	var f := FileAccess.open(OS.get_environment("CMP_OUT"), FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	quit(0)
func _battle(difficulty: int, seed: int, autos: bool) -> String:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.high_score_file = "user://cmp_scores_%d.json" % OS.get_process_id()
	console.settings_file = "user://cmp_settings_%d.cfg" % OS.get_process_id()
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
	if autos:
		for p in c.get_property_list():
			var n: String = p.name
			if n.begins_with("auto_") and n != "auto_spawn" and p.type == TYPE_BOOL:
				c.set(n, true)
	# 1.1.0: CMP_SET_BACK=1 puts the 1.1.0 gameplay settings back to 1.0.9 values (no-op
	# on versions without them), to show nothing else changed.
	# 1.1.1: the three Stealth Interceptor settings go back to their 1.1.0 values with either
	# CMP_SET_BACK=1 (everything back to 1.0.9) or CMP_STEALTH_BACK=1 (only these three, to
	# show 1.1.1 matches 1.1.0 otherwise).
	var stealth_back := [["stealth_fire_range", 0.35], ["stealth_shot_seconds", 4.0], ["stealth_home_turn", 1.0]]
	if OS.get_environment("CMP_SET_BACK") == "1":
		for pair in [["jump_score_percent", 0.0], ["rapid_repair_limit_easy", 0], ["rapid_repair_limit", 0],
				["interceptors_hacking_breachers_first", false], ["pulse_bomb_enabled", false]] + stealth_back:
			c.set(pair[0], pair[1])
	elif OS.get_environment("CMP_STEALTH_BACK") == "1":
		for pair in stealth_back:
			c.set(pair[0], pair[1])
	c.rng.seed = seed
	c.reset_battle()
	var lines := PackedStringArray()
	var step := 1.0 / 30.0
	for frame in range(30 * 240):
		c._process(step)
		if frame % 30 == 29:
			var sx := 0.0
			var sy := 0.0
			var sz := 0.0
			for k in c.contacts:
				var pos: Vector3 = k.position
				sx += pos.x; sy += pos.y; sz += pos.z
			var kv := []
			for key in c.kills:
				kv.append(int(c.kills[key]))
			lines.append("%d|%.5f|%d|%d|%.5f|%.5f|%.5f|%s|%s" % [c.score, c.hull, c.wave, c.contacts.size(), sx, sy, sz, str(kv), c.wave_phase])
	var summary := "d%d s%d a%s score %d hull %.3f wave %d :: %s" % [difficulty, seed, autos, c.score, c.hull, c.wave, str("\n".join(lines).hash())]
	console.queue_free()
	await process_frame
	return summary + "\n" + "\n".join(lines)
