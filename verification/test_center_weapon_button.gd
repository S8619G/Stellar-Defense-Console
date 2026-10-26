extends SceneTree
## Geometry, real GUI clicks and warning priority for the 0.1.2 center button.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _initialize() -> void:
	call_deferred("_run")

func frames(count: int = 4) -> void:
	for i in range(count):
		await process_frame

func button_point(ship: Control, model: Vector2) -> Vector2:
	var k: float = ship.stealth_box.size.x / 728.0
	return (model - Vector2(18, 189)) * k

func click(button: Button, point: Vector2) -> void:
	var where := button.global_position + point
	var motion := InputEventMouseMotion.new()
	motion.position = where
	motion.global_position = where
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = where
		event.global_position = where
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event, true)
	await frames()

func _run() -> void:
	var console: Control = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://center_weapon_test_settings.cfg"
	console.high_score_file = "user://center_weapon_test_scores.json"
	console.shell_dry_run = true
	console.quit_dry_run = true
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	c.auto_spawn = false
	root.add_child(console)
	root.size = Vector2i(1600,900)
	var ship: Control = console.get_node("ShipStatus")
	c.set_process(false)
	c.difficulty = 1
	c.reset_battle()
	c.waves_enabled = false
	c.wave = 5
	c.safe_remaining = 0.0
	c.carrier_weapons_enabled = false
	c.own_weapons_enabled = false
	c.launch_sound_enabled = false
	var bases: Array[Dictionary] = []
	for i in range(3):
		var b: Dictionary = c.find_contact(c.spawn_contact("unknown","unknown"))
		c._identify_carrier(b)
		bases.append(b)
	await frames()
	check(c.can_launch_stealth(), "Original three-capital readiness rule")
	check(ship.stealth_button.visible, "Center button visible when ready")
	check(ship.CENTER_WEAPON_POLYGON.size() == 19, "Exact 19-point traced inset")
	check(ship.stealth_box.size.x / ship.stealth_box.size.y > 5.0, "Wide central inset, not a narrow flight pod")
	for model in [Vector2(200,260),Vector2(430,258),Vector2(700,260)]:
		check(ship.stealth_button._has_point(button_point(ship,model)), "Center hull is clickable at " + str(model))
	for model in [Vector2(60,260),Vector2(20,190),Vector2(650,63),Vector2(1000,260)]:
		check(not ship.stealth_button._has_point(button_point(ship,model)), "Rear notch, outside corners, pod and bow are not clickable: " + str(model))
	await click(ship.stealth_button,button_point(ship,Vector2(60,260)))
	check(c.stealth_launches == 0, "Real GUI click in rear notch does not launch")
	await click(ship.stealth_button,button_point(ship,Vector2(650,63)))
	check(c.stealth_launches == 0, "Real GUI click in former top pod does not launch")
	# Preserve the warning over this region without an accidental launch through it.
	var h: Dictionary = c.find_contact(c.spawn_from_carrier("breacher",bases[0].id))
	h.position = h.hack_point
	c._update_breachers(0.0)
	await frames()
	check(c.hack_state() in ["hacking","draining"], "Intrusion overlay fixture active")
	if ship.breach_alert_on_ship_fill:
		# 1.1.0 (approved breach alert): the warning moves to the ship fill and the NAV DATA
		# window, so the STEALTH WEAPON button stays clickable during a breach.
		check(ship.stealth_button.blocked_rect.size.x == 0.0, "Breach alert on the ship fill: STEALTH WEAPON button stays clickable")
		check(ship.stealth_button._has_point(button_point(ship,Vector2(430,258))), "Center of the button still clickable during a breach")
	else:
		check(ship.stealth_button.blocked_rect.size.x > 0.0, "Existing warning area has click priority")
		check(not ship.stealth_button._has_point(ship.stealth_button.blocked_rect.get_center()), "Warning cannot trigger a weapon behind it")
	c._remove_contact(h.id)
	await frames()
	check(ship.stealth_button.blocked_rect.size.x == 0.0, "Full button restored after warning clears")
	await click(ship.stealth_button,button_point(ship,Vector2(430,258)))
	check(c.stealth_launches == 1 and c.count_kind("stealth_interceptor") == 1, "Real GUI center click launches exactly one Stealth Interceptor")
	check(not ship.stealth_button.visible, "Button hides while weapon is deployed")
	check(ship.stealth_label == "STEALTH WEAPON" and is_equal_approx(ship.stealth_pulse_hz,0.8), "Existing label and quiet pulse retained")
	check(ship.fill_opacity == 0.34 and not ship.emp_on_ship, "Hull fill and default EMP layout unchanged")
	print("CENTER_WEAPON_RESULT checks=%d failures=%d" % [checks,failures])
	# Release mixer-held imported audio before terminating this short fixture.
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	console.queue_free()
	await frames(2)
	await create_timer(0.2).timeout
	quit(1 if failures else 0)
