extends SceneTree
## 0.1.2: this script checks 1.2.9 behaviour, so the 0.1.2 switches and Normal Protect values
## are set back to 1.2.9 (test_v130_features.gd checks 0.1.2).
const V130_OFF := {"ship_missiles_spread_carriers": false, "double_missile_quick_pair": false, "carrier_second_nuke": false, "rapid_missile_bonus": false, "rapid_repair_needs_shown_damage": false, "protect_normal_interceptor_share": 1.0, "protect_normal_fewer_on_top": true, "protect_normal_gunship_patch": 0.0, "protect_hard_interceptor_share": 1.0, "protect_hard_fewer_on_top": true, "protect_hard_gunship_patch": 0.0, "protect_fleet_spread": 1.0, "missile_bonus_pick_after_wave": false, "protect_hard_gunship_chance": 0.5}
var console: Node
var c: Control
var checks := 0
var failures := 0
var capture: AudioEffectCapture

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func peak() -> float:
	var value := 0.0
	for frame in capture.get_buffer(capture.get_frames_available()):
		value = maxf(value, absf(frame.x))
	return value

func base() -> Dictionary:
	var id: String = c.spawn_contact("unknown", "unknown")
	var b: Dictionary = c.find_contact(id)
	c._identify_carrier(b)
	return b

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	c = console.get_node("CenterContainer/Dome/Contacts")
	for _k130 in V130_OFF: c.set(_k130, V130_OFF[_k130])
	c.auto_spawn = false
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.arrival_sound_enabled = false
	root.add_child(console)
	c.set_process(false)
	console.set_process(false)
	check(console.sweep_volume_db == -20.0 and console.get_node("SweepLoop").volume_db == -20.0, "RADAR configured and actually playing at -20 dB")
	console.get_node("SweepLoop").stop()
	var bytes := FileAccess.get_file_as_bytes("res://assets/audio/radar_alert_loop.wav")
	var raw := bytes.slice(44)
	var regular_raw := FileAccess.get_file_as_bytes("res://assets/audio/arrival_alert_regular.wav").slice(44)
	var alert: AudioStreamWAV = c.klaxon_player.stream
	check(raw.size() == 134400, "Approved loop contains 67200 PCM frames")
	check(alert.data == regular_raw and is_equal_approx(alert.get_length(), 6.255625), "Identification uses exactly the approved overlapping three-set preview")
	var set_bytes := regular_raw.size() / 3
	for i in range(3):
		check(alert.data.slice(i * set_bytes, (i + 1) * set_bytes) == regular_raw.slice(0, set_bytes), "Identification set %d matches approved overlapping PCM" % (i + 1))
	check(alert.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Three-cycle sequence is finite, not an infinite loop")
	var nuclear: AudioStreamWAV = c.nuclear_player.stream
	check(nuclear.data.size() == raw.size() * 2, "Nuclear launch sequence contains exactly two cycles")
	check(nuclear.data.slice(0, raw.size()) == raw and nuclear.data.slice(raw.size()) == raw, "Nuclear launch uses the same approved alert")
	check(c.nuclear_player.pitch_scale == 1.5 and is_equal_approx(nuclear.get_length() / c.nuclear_player.pitch_scale, 2.8 / 1.5), "Nuclear warning is 1.5x speed / about 1.87 seconds")
	var siege: AudioStreamWAV = c.siege_alert_player.stream
	check(siege.data == raw + raw, "Siege Ship arrival retains the exact original two-cycle PCM")
	check(is_equal_approx(c.siege_alert_player.pitch_scale, 0.8) and c.siege_alert_player.volume_db == -5.0, "Siege Ship arrival retains original pitch and level")
	check(c.nuclear_player.volume_db == -7.0, "Nuclear alert retains original level")
	check(alert.data != nuclear.data and alert.data != siege.data, "Regular arrival is isolated from both preserved special alerts")
	check(alert.format == AudioStreamWAV.FORMAT_16_BITS and alert.mix_rate == 48000 and not alert.stereo, "New arrival is uncompressed mono PCM for editor and export")
	check(c.battery_player.pitch_scale == 3.0, "Battery sound runs at 3x speed for rapid buzz")
	check(c.prox_burst_seconds == 6.0 and c.battery_recharge_seconds == 24.0, "Battery drain and recharge times are six and twenty-four seconds (1.03)")

	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "AlertProbe")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 6.0
	AudioServer.add_bus_effect(bus, capture)
	for player in [c.klaxon_player, c.nuclear_player, c.nuclear_beep_player, c.battery_player]:
		player.bus = "AlertProbe"
	# 1.2.8: the boot splash holds start-up for 3 s (Minimum Display Time), which leaves
	# the Dummy mixer catching up with wall-clock timers for a moment. Let it settle
	# before the timed identification checks; the checks themselves are unchanged.
	for i in range(10):
		await create_timer(0.1).timeout
	peak()
	var first := base()
	var second := base()
	check(c.klaxon_count == 1 and c.klaxon_queue.size() == 1, "Second identification queues without interrupting first triple")
	for i in range(3):
		await create_timer(alert.get_length() / 3.0).timeout
		check(peak() > 0.03, "Identification cycle %d has measured mixer output" % (i + 1))
	await create_timer(0.18).timeout
	peak()
	# Dummy mixer completion can trail wall-clock timers under concurrent
	# rendering/simulation load. PCM length/repeat count are checked exactly.
	var completion_wait := 0.0
	while c.klaxon_player.playing and completion_wait < 0.8:
		await create_timer(0.05).timeout
		completion_wait += 0.05
	check(not c.klaxon_player.playing, "Identification stops after third cycle")
	await create_timer(0.15).timeout
	check(peak() == 0.0, "No fourth cycle or lingering sound")
	c._update_klaxon()
	check(c.klaxon_count == 2 and c.klaxon_queue.is_empty(), "Queued identification starts its own three-cycle sequence")
	c.klaxon_player.stop()
	c.klaxon_enabled = false
	var n1: String = c._launch_nuclear(first)
	var n2: String = c._launch_nuclear(second)
	c._update_nuclear_alarm(0.0)
	check(c.nuclear_alert_count == 1 and c.nuclear_alert_queue.size() == 1, "Simultaneous nuclear launches serialize their two-cycle warnings")
	await create_timer(0.94).timeout
	check(peak() > 0.02, "First accelerated nuclear cycle audible")
	await create_timer(1.08).timeout
	check(peak() > 0.02 and not c.nuclear_player.playing, "Second accelerated cycle audible, then finite warning stops")
	c._update_nuclear_alarm(0.0)
	check(c.nuclear_alert_count == 2 and c.nuclear_alert_queue.is_empty(), "Second live nuclear launch receives exactly one warning")
	c.nuclear_player.stop()  # Advance past queued warning deterministically.
	var nearest: Dictionary = c.find_contact(n1)
	nearest.launch_distance = 2.0
	nearest.position = c.own_ship_position + Vector3(0, 2.0, 0)
	c.find_contact(n2).position = c.own_ship_position + Vector3(0, 3.0, 0)
	var far: float = c.nuclear_beep_interval()
	nearest.position = c.own_ship_position + Vector3(0, 1.0, 0)
	var middle: float = c.nuclear_beep_interval()
	nearest.position = c.own_ship_position + Vector3(0, 0.02, 0)
	var close: float = c.nuclear_beep_interval()
	check(is_equal_approx(far, 1.2) and far > middle and middle > close and close >= 0.15, "Approach interval decreases monotonically with distance")
	print("BEEP_INTERVALS far=", far, " middle=", middle, " near=", close)
	c._update_nuclear_alarm(0.0)
	check(c.nuclear_beep_count == 1 and c.nuclear_beep_player.playing, "Approach beeps start after launch warnings")
	await create_timer(0.10).timeout
	check(peak() > 0.015, "Approach beep produces measured output")
	var start_count: int = c.nuclear_beep_count
	for i in range(100):
		c._update_nuclear_alarm(0.02)
	check(c.nuclear_beep_count - start_count >= 10 and c.nuclear_alert_count == 2, "Near threat produces rapid beeps, not repeated launch alarms")
	c.klaxon_enabled = true
	c.klaxon_queue.append(first.id)
	c._update_klaxon()
	check(not c.klaxon_player.playing, "Identification audio waits while a nuclear threat is active")
	c._remove_contact(n1)
	c._remove_contact(n2)
	c._update_nuclear_alarm(0.0)
	check(not c.nuclear_beep_player.playing and not c.nuclear_player.playing and c.nuclear_alert_queue.is_empty(), "Final interception or impact clears all threat audio")
	c._update_klaxon()
	check(c.klaxon_player.playing, "Pending identification can resume after threat clears")
	c.request_jump()
	check(not c.klaxon_player.playing and not c.nuclear_player.playing and not c.nuclear_beep_player.playing, "JUMP cancels alert and approach sounds")
	check(c.klaxon_queue.is_empty() and c.nuclear_alert_queue.is_empty(), "JUMP clears all pending audio")
	c.reset_battle()
	c.set_prox_defense(true)
	await create_timer(0.35).timeout
	check(peak() > 0.04 and c.battery_player.playing, "Fast defense buzz has measured sustained output")
	c.set_prox_defense(false)
	await create_timer(0.15).timeout
	peak()
	await create_timer(0.15).timeout
	check(peak() == 0.0 and c.prox_cooldown_remaining == 0.0, "Buzz stops immediately when firing stops")
	c.klaxon_player.play()
	c.nuclear_player.play()
	c.nuclear_beep_player.play()
	c.apply_damage(1000.0)
	check(not c.klaxon_player.playing and not c.nuclear_player.playing and not c.nuclear_beep_player.playing, "Game Over silences all alert paths")
	c.reset_battle()
	check(c.nuclear_alert_count == 0 and c.nuclear_beep_count == 0 and c.nuclear_alert_queue.is_empty(), "Retry resets threat audio state")
	peak()
	var sweep: AudioStreamPlayer = console.get_node("SweepLoop")
	for player in [sweep, c.klaxon_player, c.nuclear_player, c.nuclear_beep_player, c.battery_player, c.jump_player, c.arrival_player, c.launch_player, c.impact_player]:
		player.bus = "AlertProbe"
		player.play()
	await create_timer(4.45).timeout
	var mix_peak := peak()
	print("ALL_EFFECTS_MIX_PEAK ", mix_peak)
	check(mix_peak > 0.1 and mix_peak < 0.99, "Tested overlapping effects and quieter RADAR mix remain below clipping")
	check(sweep.playing and sweep.volume_db == -20.0, "RADAR remains at -20 dB through resets and other effects")
	sweep.stop()
	print("ALERT_RESULT checks=", checks, " failures=", failures)
	c._stop_special_audio()
	c.klaxon_player.stop()
	c.arrival_player.stop()
	c.launch_player.stop()
	console.free()
	console = null
	c = null
	alert = null
	nuclear = null
	AudioServer.remove_bus(bus)
	capture = null
	await create_timer(0.2).timeout
	call_deferred("quit", 0 if failures == 0 else 1)
