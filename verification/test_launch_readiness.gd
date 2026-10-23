extends SceneTree
## Stellar Defense Console 1.0.5: each Interceptor and Gunship has its own ready timer.
## The button shows how many are ready, ALL DEPLOYED shows straight away when every ship
## is out, and a landing never restarts another ship's wait. Same rules for Auto Launch.
## 1.0.6: the number shown is how many the next press sends (up to 2 Interceptors,
## 1 Gunship), not every ready ship in the hangar.
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

func clean(level: int = 1) -> void:
	c.difficulty = level
	c.auto_spawn = false
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
	c.waves_enabled = false
	c.safe_remaining = 0.0
	c.wave = 5

## Count down the ship waits only (no movement), like the battle clock does.
func tick(seconds: float, step: float = 0.05) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		c._tick_waits(c.interceptor_waits, c.interceptors_in_hangar(), step)
		c._tick_waits(c.gunship_waits, c.gunships_in_hangar(), step)
		t += step

func interceptors_out() -> Array:
	var list := []
	for ship in c.contacts:
		if ship.kind == "interceptor":
			list.append(ship)
	return list

func gunships_out() -> Array:
	var list := []
	for ship in c.contacts:
		if ship.kind == "gunship":
			list.append(ship)
	return list

func land(ship: Dictionary) -> void:
	ship.phase = "return"
	ship.position = c.launch_origin(ship.lane)
	if ship.kind == "gunship":
		c._update_gunships(0.0)
	else:
		c._update_interceptors(0.0)

func interceptor_line() -> String:
	console._process(0.0)
	return console.launch_button.text.get_slice("\n", 1)

func gunship_line() -> String:
	console._process(0.0)
	return console.gunship_button.text.get_slice("\n", 1)

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://launch_ready_settings.cfg"
	console.high_score_file = "user://launch_ready_scores.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	c = console.get_node("CenterContainer/Dome/Contacts")
	root.add_child(console)
	c.set_process(false)
	console.set_process(false)

	# --- Same pause lengths as 1.0.4 ---
	check(c.interceptors_per_launch == 2 and is_equal_approx(c.launch_cooldown_seconds, 4.0) and is_equal_approx(c.interceptor_recovery_seconds, 3.0), "Interceptors: 2 per press, 4 s launch cooldown, 3 s landing pause (unchanged)")
	check(is_equal_approx(c.gunship_launch_cooldown, 8.0) and is_equal_approx(c.gunship_recovery_seconds, 5.0), "Gunships: 1 per press, 8 s launch cooldown, 5 s landing pause (unchanged)")
	check(console.launch_state_text(0, 0, 3.0) == "ALL DEPLOYED" and console.launch_state_text(4, 2, 0.0) == "2 READY" and console.launch_state_text(2, 0, 2.2) == "READY IN 3s", "Button text: ALL DEPLOYED first, then N READY, then READY IN")

	# --- Opening launches play out as in 1.0.4 ---
	clean()
	check(c.interceptors_ready() == 6 and interceptor_line() == "2 READY" and not console.launch_button.disabled, "1.0.6: battle start, 6 in the hangar: the button shows 2 READY (what one press sends)")
	check(c.interceptors_next_launch() == 2 and c.gunships_next_launch() == 1, "1.0.6: next press sends 2 Interceptors / 1 Gunship")
	check(c.launch_interceptors() == 2 and c.count_interceptors() == 2, "One press sends 2")
	check(c.interceptors_ready() == 0 and interceptor_line() == "READY IN 4s" and console.launch_button.disabled, "The 4 still in the hangar wait the 4 s launch cooldown: READY IN 4s")
	tick(3.9)
	check(c.interceptors_ready() == 0 and c.launch_interceptors() == 0, "Still waiting at 3.9 s")
	tick(0.15)
	check(c.interceptors_ready() == 4 and interceptor_line() == "2 READY", "1.0.6: at 4 s, 4 in the hangar: the button shows the next 2 (2 READY)")
	check(c.launch_interceptors() == 2 and interceptor_line() == "READY IN 4s", "Second press sends 2 more")
	tick(4.05)
	check(c.launch_interceptors() == 2 and c.count_interceptors() == 6, "Third press sends the last 2")
	check(interceptor_line() == "ALL DEPLOYED" and console.launch_button.disabled, "Every Interceptor out: ALL DEPLOYED straight away (no countdown first)")

	# --- A landing never restarts another ship's wait ---
	var out := interceptors_out()
	land(out[0])
	check(c.interceptors_returned == 1 and c.interceptor_waits.size() == 1 and interceptor_line() == "READY IN 3s", "First Interceptor lands: READY IN 3s (its own wait)")
	tick(1.02)
	land(out[1])
	check(c.interceptor_waits.size() == 2 and absf(c.interceptor_waits[0].left - 2.0) < 0.06 and absf(c.interceptor_waits[1].left - 3.0) < 0.01, "Second lands 1 s later: the first keeps its 2 s left, the second starts its own 3 s")
	check(interceptor_line() == "READY IN 2s", "The button counts down to the first one")
	tick(2.02)
	check(c.interceptors_ready() == 1 and interceptor_line() == "1 READY", "3 s after its landing the first is ready: 1 READY")
	check(c.launch_interceptors() == 1 and c.count_interceptors() == 5, "One ready: it launches alone")
	check(interceptor_line() == "READY IN 1s", "The second keeps its own countdown (not held by the launch cooldown)")
	tick(1.02)
	check(c.launch_interceptors() == 1 and c.count_interceptors() == 6, "A second later the next press sends that one too")
	check(interceptor_line() == "ALL DEPLOYED", "All out again: ALL DEPLOYED")

	# --- A landing does not touch ships already ready ---
	clean()
	c.launch_interceptors()
	tick(4.05)
	c.launch_interceptors()
	tick(4.05)
	check(c.interceptors_ready() == 2 and c.count_interceptors() == 4, "4 out, 2 ready")
	land(interceptors_out()[0])
	check(c.interceptors_ready() == 2 and interceptor_line() == "2 READY", "One lands: the 2 ready ones stay ready (2 READY)")
	check(c.launch_interceptors() == 2 and c.count_interceptors() == 5, "They launch at once")
	tick(3.05)
	check(c.interceptors_ready() == 1, "The landed one is ready after its own 3 s")

	# --- Lost Interceptor: its replacement is ready at once (as in 1.0.4) ---
	clean()
	c.launch_interceptors()
	tick(4.05)
	c.launch_interceptors()
	tick(4.05)
	c.launch_interceptors()
	check(interceptor_line() == "ALL DEPLOYED", "6 out")
	var lost: Dictionary = interceptors_out()[0]
	c.contacts.erase(lost)
	check(c.interceptors_ready() == 1 and interceptor_line() == "1 READY", "A destroyed Interceptor's replacement is ready at once")

	# --- JUMP clears the launch cooldown, not landing waits (as in 1.0.4) ---
	clean()
	c.launch_interceptors()
	land(interceptors_out()[0])
	check(c.interceptor_waits.size() == 5, "4 in launch cooldown + 1 in landing wait")
	c._clear_waits(c.interceptor_waits, "launch")
	check(c.interceptor_waits.size() == 1 and c.interceptors_ready() == 4, "Clearing the launch cooldown keeps the landing wait")
	clean()
	c.launch_interceptors()
	land(interceptors_out()[0])
	c.jump_recharge_remaining = 0.0
	var jumped: bool = c.request_jump()
	check(not jumped or (c.interceptor_waits.size() == 1 and c.interceptor_waits[0].why == "landing"), "JUMP clears the launch cooldown only")

	# --- Hangar gets smaller (boost ends): extra waits drop out ---
	clean()
	c.interceptor_waits.append({"left": 9.0, "why": "landing"})
	for i in range(6):
		c.interceptor_waits.append({"left": 1.0, "why": "launch"})
	tick(0.05)
	check(c.interceptor_waits.size() == 6 and c.interceptors_ready() == 0, "Never more waits than ships in the hangar (longest dropped)")
	var longest := 0.0
	for w in c.interceptor_waits:
		longest = maxf(longest, w.left)
	check(longest < 1.0, "The longest wait was the one dropped")

	# --- 1.0.6: the number always matches what the next press sends ---
	clean()
	c.launch_interceptors()
	tick(4.05)
	c.launch_interceptors()
	land(interceptors_out()[0])
	tick(4.05)
	check(c.interceptors_ready() == 3 and interceptor_line() == "2 READY", "1.0.6: 3 ready in the hangar: 2 READY")
	check(c.launch_interceptors() == 2, "The press sends exactly the 2 shown")
	check(interceptor_line() == "READY IN 4s", "Then the button counts down the launch cooldown")
	tick(4.05)
	check(interceptor_line() == "1 READY" and c.launch_interceptors() == 1, "Then the last one: 1 READY, and the press sends 1")

	# --- Gunships: same rules ---
	clean()
	check(c.gunship_limit() == 2 and c.gunships_ready() == 2 and gunship_line() == "1 READY", "1.0.6: Gunships, 2 in the hangar: the button shows 1 READY (one per press)")
	check(c.launch_gunship() == 1 and gunship_line() == "READY IN 8s" and console.gunship_button.disabled, "One press sends 1; the other waits the 8 s launch cooldown")
	tick(8.05)
	check(gunship_line() == "1 READY" and c.launch_gunship() == 1, "At 8 s the second is ready and launches")
	check(gunship_line() == "ALL DEPLOYED" and console.gunship_button.disabled, "Both out: ALL DEPLOYED straight away")
	var g := gunships_out()
	land(g[0])
	check(gunship_line() == "READY IN 5s", "First Gunship lands: READY IN 5s")
	tick(2.0)
	land(g[1])
	check(c.gunship_waits.size() == 2 and absf(c.gunship_waits[0].left - 3.0) < 0.06, "The second landing does not restart the first one's wait")
	tick(3.05)
	check(c.gunships_ready() == 1 and gunship_line() == "1 READY" and c.launch_gunship() == 1, "First Gunship ready 5 s after its own landing and launches")
	check(gunship_line() == "READY IN 2s", "The other keeps its own countdown")
	tick(2.05)
	check(c.launch_gunship() == 1 and gunship_line() == "ALL DEPLOYED", "It launches when its own wait ends")

	# --- Auto Launch: Interceptors ---
	clean()
	c.auto_launch_interceptors = true
	var carrier: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(carrier)
	carrier.drone_timer = 999.0
	carrier.missile_timer = 999.0
	carrier.heavy_timer = 999.0
	var drone: Dictionary = c.find_contact(c.spawn_from_carrier("drone", carrier.id))
	drone.position = Vector3(0.2, 0.3, 0.0)
	for i in range(4):
		var v: Dictionary = c.find_contact(c._spawn_interceptor("interceptor", false))
		v.position = Vector3(0.0, 0.9, 0.0)
		v.phase = "return"
	c._hold_after_landing("interceptor")
	var before: int = c.auto_interceptor_launches
	c._update_auto_launch()
	check(c.auto_interceptor_launches == before + 1 and c.count_interceptors() == 5, "Auto Launch sends the ready Interceptor while another is in its landing wait")
	c._update_auto_launch()
	check(c.auto_interceptor_launches == before + 1, "Auto Launch then waits")
	tick(3.05)
	c._update_auto_launch()
	check(c.auto_interceptor_launches == before + 2 and c.count_interceptors() == 6, "Auto Launch sends the landed one when its own wait ends")

	# --- Auto Launch: Gunships (several nukes: every ready Gunship) ---
	clean()
	c.auto_launch_gunships = true
	c.nuclear_weapons_enabled = true
	var nb: Dictionary = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(nb)
	nb.drone_timer = 999.0
	nb.missile_timer = 999.0
	nb.heavy_timer = 999.0
	c._launch_nuclear(nb)
	c._launch_nuclear(nb)
	c._hold_after_landing("gunship")
	c._update_auto_launch()
	check(c.count_kind("gunship") == 1 and c.gunship_waits.size() == 1, "Several nukes: the ready Gunship goes, the one in its landing wait stays")
	tick(5.05)
	c._update_auto_launch()
	check(c.count_kind("gunship") == 2, "It goes when its own 5 s ends")
	clean()
	c.auto_launch_gunships = true
	c.nuclear_weapons_enabled = true
	nb = c.find_contact(c.spawn_contact("unknown", "unknown"))
	c._identify_carrier(nb)
	nb.drone_timer = 999.0
	nb.missile_timer = 999.0
	nb.heavy_timer = 999.0
	c._launch_nuclear(nb)
	c._update_auto_launch()
	check(c.count_kind("gunship") == 1 and c.gunship_ready_in() > 7.0, "One nuke: one Gunship; the other waits the launch cooldown")
	c._launch_nuclear(nb)
	c._update_auto_launch()
	check(c.count_kind("gunship") == 2, "A second nuke: the launch cooldown is skipped and the other Gunship goes too (as in 1.0.4)")

	# --- AUTO tag still shows ---
	clean()
	c.auto_launch_interceptors = true
	console._process(0.0)
	check(console.launch_button.text == "LAUNCH INTERCEPTORS\nAUTO 2 READY", "1.0.6: Auto Launch on: LAUNCH INTERCEPTORS / AUTO 2 READY")
	c.auto_launch_interceptors = false

	# --- Protect the fleet round starts with every Interceptor ready ---
	clean()
	c.launch_interceptors()
	land(interceptors_out()[0])
	c._start_protect()
	check(c.interceptor_waits.is_empty() and c.interceptor_ready_in() == 0.0, "Protect the fleet starts with no waits")

	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("LAUNCH_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
