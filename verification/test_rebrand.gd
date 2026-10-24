extends SceneTree
## New identity and approved display/audio behaviour, independent of older suites.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check(ProjectSettings.get_setting("application/config/name") == "Stellar Defense Console", "Original working title")
	check(ProjectSettings.get_setting("application/config/version") == "1.0.9", "Pre-release version")
	check(OS.get_user_data_dir().ends_with("Stellar Defense Console"), "Independent save directory")
	check(not DirAccess.dir_exists_absolute("res://references"), "No reference directory")
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://verify_rebrand_settings.cfg"
	console.high_score_file = "user://verify_rebrand_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	c.auto_spawn = false
	root.add_child(console)
	await process_frame
	check(console.version_text() == "STELLAR DEFENSE CONSOLE 1.0.9", "Product name in settings")
	check(console.github_url.is_empty() and console.settings_panel.version_label.disabled, "No stale public release link")
	check(console.get_node("TopChrome").text == "RADAR", "Simple RADAR display label")
	check(console.get_node("BottomButtons/Jump") == console.jump_button, "Jump button remains connected")
	var tags := {"interceptor":"INTERCEPTOR", "gunship":"GUNSHIP", "drone":"ATTACK DRONE",
		"breacher":"BREACHER", "carrier":"ENEMY CARRIER 100%", "siege_ship":"SIEGE SHIP 100%"}
	for kind in tags:
		var contact := {"id":"01", "kind":kind, "phase":"approach", "hits_remaining":10.0, "max_hits":10.0}
		check(c.contact_tag(contact) == tags[kind], "Public contact name: " + tags[kind])
	check(c.public_craft_name({"kind":"gunship","phase":"protect_repair"}) == "REPAIR TENDER", "Repair Tender name")
	var Icons = load("res://scripts/RadarContactIcons.gd")
	for kind in Icons.KINDS:
		var texture: Texture2D = Icons.ICONS.get(kind)
		check(texture != null and texture.get_width() > 0, "Replacement art covers " + kind)
	check(Icons.ICONS.stealth_interceptor != Icons.ICONS.interceptor, "Distinct Stealth mark")
	check(Icons.ICONS.repair_tender != Icons.ICONS.gunship, "Distinct Tender mark")
	check(not Icons.is_interceptor("stealth_interceptor"), "Stealth retains its separate combat category")
	var dome: Control = console.dome
	check(dome.stellar_angles(0.0).is_equal_approx(Vector2.ZERO), "Both sweeps begin at rest")
	check(is_equal_approx(dome.stellar_angles(.6).x, -PI*.5), "First sweep speed/direction")
	check(is_equal_approx(dome.STELLAR_SECOND_START, 0.672) and is_zero_approx(dome.stellar_angles(0.67).y) and dome.stellar_angles(0.68).y > 0.0, "Right ring starts at 56% of the left sweep (0.672 s)")
	check(dome.stellar_angles(0.9).x < 0 and dome.stellar_angles(0.9).y > 0 and dome.stellar_angles(0.9).x > -PI, "Opposing sweeps overlap for 0.528 s")
	var ended := Vector2(-PI, PI)
	check(not dome.stellar_angles(1.86).is_equal_approx(ended) and dome.stellar_angles(1.872).is_equal_approx(ended), "Second ends at 1.872 seconds")
	check(dome.stellar_angles(3.249).is_equal_approx(ended), "Pause after second sweep lasts to the end of the 3.25 s cycle")
	check(dome.stellar_angles(3.25).is_equal_approx(Vector2.ZERO), "3.25-second cycle repeats")
	for angle in [-PI, -PI*.5, 0.0, PI*.5, PI]:
		var points: PackedVector2Array = dome.three_ring_points(Vector2.ZERO, 1, angle)
		check(points[24].distance_to(Vector2(0, .5)*dome.sphere_radius) < .01
			and points[72].distance_to(Vector2(0, -.5)*dome.sphere_radius) < .01,
			"Front/back hinge anchors stay fixed at angle " + str(angle))
	var wave: AudioStreamWAV = console.sweep_loop.stream
	check(wave != null and wave.mix_rate == 48000 and wave.loop_end == 156000, "Approved 3.25-second audio cycle")
	check(wave.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Export-safe audio looping")
	check(is_equal_approx(console.sweep_volume_db, -20.0), "Existing -20 dB sweep mix retained")
	var quiet := true
	for value in wave.data.slice(108000*2,156000*2):
		if value != 0:
			quiet = false
			break
	check(quiet, "Full one-second pause is silent")
	# 1.0.3: the second sweep tone starts with the right ring (0.672 s = sample 32256).
	var samples := PackedInt32Array()
	for i in range(0, wave.data.size(), 2):
		samples.append(wave.data.decode_s16(i))
	var before := 0
	for i in range(31000, 32256):
		before = maxi(before, absi(samples[i]))
	var after := 0
	for i in range(32256, 32256 + 4800):
		after = maxi(after, absi(samples[i]))
	check(before < 6000 and after > 25000, "Second sweep tone starts with the right ring at 0.672 s")
	var peak := 0
	for v in samples:
		peak = maxi(peak, absi(v))
	check(peak <= 29490, "Overlapping tones do not clip (peak at or below the original)")
	var tail_quiet := true
	for i in range(int(1.6 * 48000), 156000):
		if samples[i] != 0:
			tail_quiet = false
			break
	check(tail_quiet, "Silent from 1.6 s to the end of the cycle")
	for name in ["radar_sweep_loop", "radar_alert_loop", "radar_contact_chirp"]:
		var imported: AudioStreamWAV = load("res://assets/audio/" + name + ".wav")
		check(imported != null and imported.format == AudioStreamWAV.FORMAT_16_BITS,
			"Export import preserves uncompressed PCM: " + name)
	var ship_source := FileAccess.get_file_as_string("res://scripts/ShipStatus.gd")
	check(not ship_source.contains('_text("JUMP"') and not ship_source.contains('_text("HULL"'), "No two in-ship status readouts")
	check(ship_source.contains("damage_color(battle.hull"), "Hull damage colour retained")
	var frame_source := FileAccess.get_file_as_string("res://scripts/ConsoleFrame.gd")
	check(frame_source.contains('var hull_f := clampf(battle.hull') and frame_source.contains('"HULL"'), "Live vertical hull gauge retained")
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	check(presets.get_value("preset.3", "platform") == "Linux", "Linux desktop preset")
	print("REBRAND_RESULT checks=%d failures=%d" % [checks,failures])
	console.queue_free()
	await process_frame
	quit(1 if failures else 0)
