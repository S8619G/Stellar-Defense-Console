extends SceneTree
## Stellar Defense Console 1.0.6: the missile bonus pick pop-up never opens during a
## battle round. A bonus earned during a wave, a Protect the fleet round or a Bonus
## Sweep is kept in use, a status line says the pick comes after the round, and the
## pop-up opens when that round ends. Earned between rounds, it opens at once.
var failures := 0
var checks := 0
var console: Control
var c: Control
var panel: Control

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func clean(level: int) -> void:
	if console.bonus_pick_open:
		panel.cards[0].pressed.emit()
	c.difficulty = level
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
	c.pending.clear()
	c.contacts.clear()
	c.auto_spawn = true
	c.waves_enabled = true
	c.wave = 3
	c.set_process(false)

func open_now() -> bool:
	console._process(0.0)
	return console.bonus_pick_open and panel.visible and c.missile_bonus_offer_open

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://test_round_end.cfg"
	console.high_score_file = "user://test_round_end_scores.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	c = console.get_node("CenterContainer/Dome/Contacts")
	root.add_child(console)
	panel = console.bonus_pick_panel
	c.set_process(false)

	var plain: Control = load("res://scripts/RadarContacts.gd").new()
	check(plain.missile_bonus_pick_after_wave == true, "Pick After Round is on in the script itself")
	plain.free()
	check(c.missile_bonus_pick_after_wave == true, "Pick After Round is on in the game")

	# --- During a wave ---
	clean(1)
	c.wave_phase = "assault"
	c._add_points(17500)
	check(c.rapid_missile_active() and c.missile_bonus_offer_waiting and not open_now(), "Wave: second bonus earned, no pop-up, current bonus (Rapid) kept")
	check(c.status_message == "DOUBLE MISSILE EARNED | PICK YOUR BONUS AFTER THIS ROUND", "Wave: status line names the bonus just earned")
	c._clear_wave()
	check(open_now() and not c.missile_bonus_offer_waiting, "Wave cleared: the pop-up opens")
	check(panel.message_label.text.contains("DOUBLE MISSILE"), "The pop-up offers the bonus just earned")
	check(not c.is_processing(), "The battle clock is stopped while the pop-up is open")
	panel.cards[1].pressed.emit()
	check(c.double_missile_active() and not console.bonus_pick_open, "Picking the card takes Double Missile")

	# --- During a Bonus Sweep (new in 1.0.6) ---
	clean(1)
	c._start_sweep()
	check(c.wave_phase == "sweep", "Bonus Sweep running")
	c._add_points(17500)
	check(c.missile_bonus_offer_waiting and not open_now(), "Bonus Sweep: no pop-up during the sweep")
	check(c.status_message == "DOUBLE MISSILE EARNED | PICK YOUR BONUS AFTER THIS ROUND", "Bonus Sweep: status line")
	c._end_sweep()
	check(c.wave_phase == "rest" and open_now(), "Bonus Sweep over: the pop-up opens")
	panel.cards[0].pressed.emit()
	check(c.rapid_missile_active() and not console.bonus_pick_open, "Keeping the current card keeps Rapid Missile")

	# --- Perfect sweep bonus pushes the score over the line at the end of the sweep ---
	clean(1)
	c._start_sweep()
	c._add_points(17499)
	check(not c.missile_bonus_offer_waiting and not open_now(), "Just under the second bonus: nothing yet")
	c.sweep_spawned = 4
	c.sweep_destroyed = 4
	c._end_sweep()
	check(open_now(), "Perfect sweep bonus earns it as the sweep ends: the pop-up opens after the sweep")

	# --- During Protect the fleet ---
	clean(1)
	c.wave = 5
	c._start_protect()
	check(c.wave_phase == "protect", "Protect the fleet running")
	c._add_points(17500)
	check(c.missile_bonus_offer_waiting and not open_now(), "Protect the fleet: no pop-up during the round")
	c._end_protect("test")
	check(open_now(), "Protect the fleet over: the pop-up opens")

	# --- Between rounds ---
	clean(1)
	c.wave_phase = "rest"
	c._add_points(17500)
	check(open_now() and not c.missile_bonus_offer_waiting, "Between rounds: the pop-up opens at once")

	# --- New battle drops a held pick ---
	clean(1)
	c.wave_phase = "assault"
	c._add_points(17500)
	check(c.missile_bonus_offer_waiting, "Held during a wave")
	c.reset_battle()
	check(not c.missile_bonus_offer_waiting and not open_now(), "A new battle drops the held pick")

	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("ROUND_END_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
