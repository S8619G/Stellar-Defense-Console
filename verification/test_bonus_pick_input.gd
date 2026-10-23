extends SceneTree
## Stellar Defense Console 1.0.5: missile bonus pick pop-up. 20-second countdown that stops
## and waits once the player moves the mouse, presses an arrow key or uses a controller.
## The two description cards are the pick buttons (no KEEP / TAKE buttons); the current
## bonus card starts highlighted.
var console: Control
var panel: Control
var checks := 0
var failures := 0
var last_pick := ""
var last_timed_out := false
var pick_count := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func frames(count: int = 3) -> void:
	for i in range(count):
		await process_frame

func _on_picked(pick: String, timed_out: bool) -> void:
	last_pick = pick
	last_timed_out = timed_out
	pick_count += 1

func open() -> void:
	# As in a battle: the pop-up stands for an open offer (otherwise the console drops it).
	console.contacts.missile_bonus_offer_open = true
	console.open_bonus_pick("RAPID", "DOUBLE", false)
	await frames(2)

func key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		root.push_input(e, true)
	await frames(2)

func mouse_move(at: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = rel
	root.push_input(e, true)
	await frames(2)

func click(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = down
		root.push_input(e, true)
		await frames(1)
	await frames(2)

func centre(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

func _run() -> void:
	console = load("res://scenes/RadarConsole.tscn").instantiate()
	console.settings_file = "user://bonus_input_settings.cfg"
	console.high_score_file = "user://bonus_input_scores.json"
	console.quit_dry_run = true
	console.shell_dry_run = true
	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	root.add_child(console)
	var c: Control = console.get_node("CenterContainer/Dome/Contacts")
	c.auto_spawn = false
	c.set_process(false)
	panel = console.bonus_pick_panel
	panel.picked.connect(_on_picked)
	await frames(3)

	# --- Layout ---
	await open()
	check(is_equal_approx(console.bonus_pick_seconds, 20.0) and is_equal_approx(panel.timeout_seconds, 20.0), "Countdown is 20 seconds")
	check(panel.cards.size() == 2 and panel.cards[0] is Button and panel.cards[1] is Button, "The two description cards are buttons")
	var texts := []
	for node in panel.find_children("*", "Button", true, false):
		texts.append(str(node.text).to_upper())
	var old_buttons := false
	for t in texts:
		if t.contains("KEEP") or t.contains("TAKE"):
			old_buttons = true
	check(not old_buttons and panel.find_children("*", "Button", true, false).size() == 2, "No KEEP / TAKE buttons: only the two cards")
	check(panel.highlighted == 0 and panel.cards[0].has_focus() and panel.card_titles[0].text == "RAPID MISSILE", "The current bonus (YOU HAVE NOW) is highlighted by default")
	var lit: StyleBoxFlat = panel.cards[0].get_theme_stylebox("normal")
	var dim: StyleBoxFlat = panel.cards[1].get_theme_stylebox("normal")
	check(lit.border_color.is_equal_approx(panel.ACCENT) and lit.border_width_top == 3 and dim.border_width_top == 2, "Highlighted card has the bright, thicker border")
	var panel_rect: Rect2 = panel.panel.get_global_rect()
	var ok_layout := true
	for card in panel.cards:
		if not panel_rect.encloses(card.get_global_rect()):
			ok_layout = false
	check(ok_layout and panel.timeout_label.get_global_rect().position.y > panel.cards[0].get_global_rect().end.y, "Cards sit inside the pop-up, countdown line below them")
	check(panel.PANEL_SIZE.y < 470.0, "Pop-up is shorter now the button row is gone")

	# --- Countdown runs on its own, live ---
	# The test drives the clock alone here (real frames would also count down).
	panel.set_process(false)
	check(panel.timeout_label.text == "No pick in 20 s: you keep RAPID MISSILE" and not panel.waiting, "Countdown line: No pick in 20 s")
	panel._process(5.0)
	check(panel.timeout_label.text == "No pick in 15 s: you keep RAPID MISSILE", "The number counts down (15 s left)")
	panel._process(14.8)
	check(console.bonus_pick_open, "Still open at 19.8 s")
	panel._process(0.3)
	check(not console.bonus_pick_open and last_pick == "RAPID" and last_timed_out, "Nobody touches anything: after 20 s the current bonus is kept")

	# --- Mouse movement stops the countdown ---
	await open()
	await mouse_move(Vector2(40, 40), Vector2(1, 0))
	check(not panel.waiting, "A 1-pixel jitter does not count as moving the mouse")
	await mouse_move(Vector2(44, 44), Vector2(4, 4))
	check(panel.waiting and panel.stopped_by == "mouse" and panel.timeout_label.text == "Pick a bonus", "Moving the mouse stops the countdown: Pick a bonus")
	panel._process(30.0)
	panel._process(300.0)
	check(console.bonus_pick_open and pick_count == 1, "Then it waits (still open after 5 more minutes)")
	await mouse_move(centre(panel.cards[1]), Vector2(10, 0))
	check(panel.highlighted == 1, "Pointing at the other card highlights it")
	await click(centre(panel.cards[1]))
	check(not console.bonus_pick_open and last_pick == "DOUBLE" and not last_timed_out, "Clicking the other card takes it")

	# --- Click the current card ---
	await open()
	await mouse_move(centre(panel.cards[0]), Vector2(8, 0))
	await click(centre(panel.cards[0]))
	check(not console.bonus_pick_open and last_pick == "RAPID" and not last_timed_out, "Clicking the current card keeps it")

	# --- Arrow keys stop the countdown and move the highlight; Enter picks ---
	await open()
	await key(KEY_RIGHT)
	check(panel.waiting and panel.stopped_by == "keyboard" and panel.highlighted == 1, "Right arrow stops the countdown and highlights the other card")
	await key(KEY_RIGHT)
	check(panel.highlighted == 1, "Right again stays on it (no wandering to the battle buttons)")
	await key(KEY_DOWN)
	check(panel.highlighted == 1 and panel.cards[1].has_focus(), "Down does not leave the pop-up")
	await key(KEY_LEFT)
	check(panel.highlighted == 0, "Left goes back to the current card")
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	check(not console.bonus_pick_open and last_pick == "DOUBLE", "Enter picks the highlighted card")
	await open()
	await key(KEY_ENTER)
	check(not console.bonus_pick_open and last_pick == "RAPID", "Enter straight away picks the default (current) bonus")
	await open()
	await key(KEY_A)
	check(not panel.waiting, "Other keys do not stop the countdown")
	panel.pick_card(0)

	# --- Touch tap on a card ---
	await open()
	var tap_at := centre(panel.cards[1])
	for down in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = tap_at
		t.pressed = down
		Input.parse_input_event(t)
		Input.flush_buffered_events()
		await frames(2)
	if console.bonus_pick_open:
		# Some headless set-ups do not turn touches into clicks; the tap still stops the countdown.
		check(panel.waiting and panel.stopped_by in ["touch", "mouse"], "A tap stops the countdown")
		panel.pick_card(1)
	else:
		check(last_pick == "DOUBLE", "Tapping the other card takes it")

	# --- Controller ---
	await open()
	var pad: Node = console.controller
	if pad == null:
		for node in console.find_children("*", "Node", true, false):
			if node.get_script() != null and str(node.get_script().resource_path).ends_with("ControllerInput.gd"):
				pad = node
	check(pad != null and pad.context() == "bonus", "Controller sees the pop-up")
	pad._direction_pressed(Vector2i.RIGHT)
	await frames(2)
	check(panel.waiting and panel.stopped_by == "controller" and panel.highlighted == 1, "D-pad right stops the countdown and highlights the other card")
	pad._press("a")
	await frames(2)
	check(not console.bonus_pick_open and last_pick == "DOUBLE", "A picks the highlighted card")

	# --- Reset closes it cleanly ---
	await open()
	c.reset_battle()
	await frames(2)
	if console.bonus_pick_open:
		console._drop_bonus_pick()
	check(not panel.visible and not panel.is_processing_input(), "Closed pop-up stops listening for input")

	for f in [console.settings_file, console.high_score_file]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("BONUS_INPUT_RESULT checks=%d failures=%d" % [checks, failures])
	for player in console.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	await create_timer(0.3).timeout
	console.free()
	await create_timer(0.3).timeout
	quit(1 if failures > 0 else 0)
