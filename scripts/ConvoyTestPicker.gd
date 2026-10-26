extends CanvasLayer
## 1.0.7 test build only: a start screen that jumps straight into a Protect the convoy round
## at the chosen difficulty and set. Added by RadarConsole only when the build has the
## "convoy_test" feature (the separate Convoy Test export) or the --convoy-test argument.
## The normal game builds never show it.

var console: Control
var contacts: Control
var panel: PanelContainer
var menu_button: Button
var level := 1
var set_number := 1
var level_buttons: Array[Button] = []
var set_buttons: Array[Button] = []
var was_protect := false
var reshow_in := -1.0
var rounds_started := 0

const SETS := [1, 2, 3, 5]

static func wanted() -> bool:
	return OS.has_feature("convoy_test") or OS.get_cmdline_user_args().has("--convoy-test")

func setup(owner_console: Control, battle: Control) -> void:
	console = owner_console
	contacts = battle
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_button = Button.new()
	menu_button.text = "CONVOY TEST MENU"
	menu_button.position = Vector2(8, 2)
	menu_button.add_theme_font_size_override("font_size", 16)
	menu_button.pressed.connect(show_menu)
	add_child(menu_button)
	panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.05, 0.08, 0.96)
	box.border_color = Color(0.94, 0.67, 0.80)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 22
	box.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(_label("PROTECT THE CONVOY TEST", 26, Color(0.94, 0.67, 0.80)))
	column.add_child(_label("Test build 1.1.0 (Protect the convoy round).\nPick a difficulty and how far into the game the round comes. Later sets bring more drones and challenges.", 15, Color(0.85, 0.85, 0.88)))
	column.add_child(_label("DIFFICULTY", 16, Color(0.78, 0.59, 0.71)))
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 10)
	column.add_child(level_row)
	for index in range(3):
		var b := _choice(["EASY", "NORMAL", "HARD"][index])
		b.pressed.connect(_pick_level.bind(index))
		level_row.add_child(b)
		level_buttons.append(b)
	column.add_child(_label("ROUND AFTER SET", 16, Color(0.78, 0.59, 0.71)))
	var set_row := HBoxContainer.new()
	set_row.add_theme_constant_override("separation", 10)
	column.add_child(set_row)
	for n in SETS:
		var b := _choice("SET %d" % n)
		b.pressed.connect(_pick_set.bind(n))
		set_row.add_child(b)
		set_buttons.append(b)
	var start := Button.new()
	start.text = "START ROUND"
	start.custom_minimum_size = Vector2(0, 54)
	start.add_theme_font_size_override("font_size", 22)
	start.pressed.connect(start_round)
	column.add_child(start)
	column.add_child(_label("The menu comes back after each round. CONVOY TEST MENU (top left) opens it at any time.", 13, Color(0.65, 0.65, 0.70)))
	_refresh()
	show_menu()

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _choice(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(120, 44)
	b.add_theme_font_size_override("font_size", 18)
	var on := StyleBoxFlat.new()
	on.bg_color = Color(0.94, 0.67, 0.80)
	on.set_corner_radius_all(4)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.05, 0.08))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.05, 0.05, 0.08))
	return b

func _pick_level(index: int) -> void:
	level = index
	_refresh()

func _pick_set(n: int) -> void:
	set_number = n
	_refresh()

func _refresh() -> void:
	for index in range(level_buttons.size()):
		level_buttons[index].set_pressed_no_signal(index == level)
	for index in range(set_buttons.size()):
		set_buttons[index].set_pressed_no_signal(SETS[index] == set_number)

func show_menu() -> void:
	reshow_in = -1.0
	panel.visible = true
	menu_button.visible = false
	contacts.set_process(false)
	_center()

func _center() -> void:
	var view := get_viewport().get_visible_rect().size
	panel.reset_size()
	panel.position = (view - panel.get_combined_minimum_size()) * 0.5

func start_round() -> void:
	panel.visible = false
	menu_button.visible = true
	contacts.difficulty = level
	contacts.reset_battle()
	contacts.contacts.clear()
	contacts.pending.clear()
	contacts.safe_remaining = 0.0
	contacts.sets_completed = set_number
	contacts.wave = set_number * 5
	contacts._start_protect()
	contacts.set_process(true)
	rounds_started += 1
	was_protect = true
	if console.has_method("log_event"):
		console.log_event("convoy test round | difficulty %s | after set %d" % [["EASY", "NORMAL", "HARD"][level], set_number])

func _process(delta: float) -> void:
	if panel.visible:
		_center()
		return
	var now_protect: bool = contacts.wave_phase == "protect"
	if was_protect and not now_protect:
		# Leave the result on screen for a few seconds, then bring the menu back.
		reshow_in = 8.0
	was_protect = now_protect
	if reshow_in > 0.0:
		reshow_in -= delta
		if reshow_in <= 0.0:
			show_menu()
