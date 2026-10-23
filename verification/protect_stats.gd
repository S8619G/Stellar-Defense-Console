extends SceneTree
## Plays many Protect the fleet rounds (LAUNCH pressed whenever ready) and reports how
## Attack Drone time is spent: holding at the jump-in point, dogfighting an Interceptor,
## attacking a civilian ship (in range) or flying to one. Also how often the drones and
## Interceptors sit in one tight clump away from every civilian ship.
var console: Control
var c: Control

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var out := []
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://ps.cfg"
	console.high_score_file = "user://ps_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	c.klaxon_enabled = false
	c.launch_sound_enabled = false
	c.arrival_sound_enabled = false
	c.wave_cues_enabled = false
	c.protect_round_sounds = false
	root.add_child(console)
	await process_frame
	c.set_process(false)
	console.set_process(false)
	var overrides: Dictionary = {}
	var env := OS.get_environment("PS_SET")
	if env != "":
		for pair in env.split(","):
			var kv := pair.split("=")
			overrides[kv[0]] = str_to_var(kv[1])
	for level in [0, 1, 2]:
		var hold := 0.0
		var dog := 0.0
		var attack := 0.0
		var travel := 0.0
		var clump := 0.0
		var total_time := 0.0
		var saved := 0
		var ships := 0
		var hull_lost := 0.0
		var rounds := 0
		var latches := 0
		var bkills := 0
		var btotal := 0
		var lost_f := 0
		var secs := 0.0
		for seed in range(1, 21):
			for k in overrides:
				c.set(k, overrides[k])
			c.difficulty = level
			c.auto_launch_interceptors = false
			c.rng.seed = seed * 7919
			c.reset_battle()
			c.contacts.clear()
			c.pending.clear()
			c.safe_remaining = 0.0
			c.wave = 5 + 5 * (seed % 3)
			c.sets_completed = 1 + seed % 3
			c._start_protect()
			var step := 1.0 / 30.0
			var frames := 0
			while c.wave_phase == "protect" and frames < 30 * 320:
				if c.interceptors_next_launch() > 0:
					c.launch_interceptors()
				c._process(step)
				frames += 1
				var drones := []
				var fighters := []
				var civs := []
				for k in c.contacts:
					if k.get("faction", "") == "civilian":
						civs.append(k)
					elif k.kind == "drone" and k.get("phase", "") == "protect":
						drones.append(k)
					elif k.kind == "interceptor" and k.get("phase", "") != "return":
						fighters.append(k)
				for d in drones:
					if float(d.get("hold", 0.0)) > 0.0:
						hold += step
					elif str(d.get("dog_target", "")) != "" or d.get("evading", false):
						dog += step
					else:
						var t: Dictionary = c.find_contact(str(d.get("civ_target", "")))
						if not t.is_empty() and d.position.distance_to(t.position) <= c.protect_attack_range:
							attack += step
						else:
							travel += step
				# Clump: every drone within 0.12 of the drones' centre, at least 2 drones, none attacking.
				if drones.size() >= 2:
					var centre := Vector3.ZERO
					for d in drones:
						centre += d.position
					centre /= drones.size()
					var tight := true
					var any_attack := false
					for d in drones:
						if d.position.distance_to(centre) > 0.12:
							tight = false
						var t2: Dictionary = c.find_contact(str(d.get("civ_target", "")))
						if str(d.get("dog_target", "")) == "" and not t2.is_empty() and d.position.distance_to(t2.position) <= c.protect_attack_range:
							any_attack = true
					if tight and not any_attack:
						clump += step
				total_time += step
			rounds += 1
			ships += c.protect_civilians_total
			saved += c.protect_saved
			latches += c.protect_breacher_latches if "protect_breacher_latches" in c else 0
			bkills += c.protect_breachers_destroyed if "protect_breachers_destroyed" in c else 0
			btotal += c.protect_breachers_total if "protect_breachers_total" in c else 0
			lost_f += c.protect_burst_losses if "protect_burst_losses" in c else c.protect_dogfight_interceptors_lost
			secs += c.protect_elapsed
		var drone_time := hold + dog + attack + travel
		out.append("%s %s: %d rounds, %.0f s of round time | drone time: holding %.0f%%, dogfighting %.0f%%, attacking ships %.0f%%, flying to a ship %.0f%% | all drones clumped and none attacking: %.0f%% of round time | ships saved %d of %d | Breachers %d, latched %d, destroyed %d | Interceptors shot down %d | avg round %.0f s" % [
			env if env != "" else "as 1.0.6", ["Easy", "Normal", "Hard"][level], rounds, total_time,
			100.0 * hold / drone_time, 100.0 * dog / drone_time, 100.0 * attack / drone_time, 100.0 * travel / drone_time,
			100.0 * clump / total_time, saved, ships, btotal, latches, bkills, lost_f, secs / rounds])
	print("\n".join(out))
	console.free()
	quit(0)
