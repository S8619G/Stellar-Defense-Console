extends Control
## 1.1.1 update pop-up, in front of everything (the startup check, CHECK NOW and GO BACK).
## Looks: mockups/settings_redesign_1.1.0 (screens 4 to 6).
##   found:       NEW VERSION AVAILABLE with what's new; LATER, SKIP THIS VERSION, UPDATE NOW.
##                UPDATE NOW is greyed out during a battle ("Finish or end the battle first").
##   working:     UPDATING TO x with the download bar and CANCEL.
##   message:     a title, a short text and OK.
##   confirm:     GO BACK TO x? with CANCEL and GO BACK.

signal later_pressed
signal skip_pressed
signal update_pressed
signal cancel_pressed
signal ok_pressed
signal go_back_confirmed

const EDGE := Color("#77324f")
const TEXT := Color("#ede0e8")
const MUTED := Color("#b9a8b2")
const ACCENT := Color(1.0, 0.6, 0.78)
const AMBER := Color("#ffe28b")
const WIDTH := 700.0
const BAR_WIDTH := 628.0

var mode: String = ""
var box: Panel
var title: Label
var sub: Label
var you: Label
var line: ColorRect
var news_head: Label
var news: Array[Label] = []
var note: Label
var track: ColorRect
var fill: ColorRect
var progress_text: Label
var step_text: Label
var later_button: Button
var skip_button: Button
var update_button: Button
var cancel_button: Button
var ok_button: Button
var go_back_button: Button
var _target: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	box = Panel.new()
	box.name = "UpdateBox"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.02, 0.045, 0.99)
	st.border_color = ACCENT
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.anti_aliasing = true
	box.add_theme_stylebox_override("panel", st)
	add_child(box)
	_target = box
	title = _label("", Vector2(36, 26), Vector2(628, 36), 26, ACCENT)
	sub = _label("", Vector2(36, 66), Vector2(628, 24), 16, MUTED)
	you = _label("", Vector2(36, 92), Vector2(628, 24), 16, MUTED)
	line = ColorRect.new()
	line.color = EDGE
	line.position = Vector2(36, 126)
	line.size = Vector2(628, 1)
	box.add_child(line)
	news_head = _label("WHAT'S NEW", Vector2(36, 140), Vector2(628, 28), 19, TEXT)
	for i in range(4):
		news.append(_label("", Vector2(48, 174 + i * 28), Vector2(616, 26), 16, MUTED))
	note = _label("", Vector2(36, 296), Vector2(628, 70), 15, AMBER)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	track = ColorRect.new()
	track.color = Color(0.22, 0.09, 0.16)
	track.size = Vector2(BAR_WIDTH, 14)
	box.add_child(track)
	fill = ColorRect.new()
	fill.color = Color(0.72, 0.36, 0.53)
	fill.size = Vector2(0, 14)
	box.add_child(fill)
	progress_text = _label("", Vector2.ZERO, Vector2(628, 26), 17, TEXT)
	step_text = _label("", Vector2.ZERO, Vector2(628, 24), 15, MUTED)
	later_button = _button("LATER", Vector2(180, 56))
	skip_button = _button("SKIP THIS VERSION", Vector2(232, 56))
	update_button = _button("UPDATE NOW", Vector2(200, 56))
	cancel_button = _button("CANCEL", Vector2(180, 56))
	ok_button = _button("OK", Vector2(180, 56))
	go_back_button = _button("GO BACK", Vector2(200, 56))
	skip_button.add_theme_font_size_override("font_size", 17)
	later_button.name = "LaterButton"
	skip_button.name = "SkipButton"
	update_button.name = "UpdateNowButton"
	cancel_button.name = "CancelButton"
	ok_button.name = "OkButton"
	go_back_button.name = "GoBackConfirmButton"
	later_button.pressed.connect(func() -> void: later_pressed.emit())
	skip_button.pressed.connect(func() -> void: skip_pressed.emit())
	update_button.pressed.connect(func() -> void: update_pressed.emit())
	cancel_button.pressed.connect(func() -> void: cancel_pressed.emit())
	ok_button.pressed.connect(func() -> void: ok_pressed.emit())
	go_back_button.pressed.connect(func() -> void: go_back_confirmed.emit())
	resized.connect(_center)

func _center() -> void:
	if box:
		box.position = ((size - box.size) * 0.5).round()

func _hide_all() -> void:
	for c in box.get_children():
		(c as CanvasItem).visible = false

func _show(nodes: Array) -> void:
	for n in nodes:
		(n as CanvasItem).visible = true

func _finish(height: float, focus: Button) -> void:
	box.size = Vector2(WIDTH, height)
	visible = true
	_center()
	if focus and focus.visible and not focus.disabled:
		focus.grab_focus()

## NEW VERSION AVAILABLE. can_update false: UPDATE NOW greyed out (during a battle).
func show_found(release: Dictionary, running: String, build: String, can_update: bool) -> void:
	mode = "found"
	_hide_all()
	title.text = "NEW VERSION AVAILABLE"
	var bits := ["%s for %s" % [release.get("version", "?"), _build_words(build)]]
	if str(release.get("date", "")) != "":
		bits.append("released %s" % release.date)
	if int(release.get("size", 0)) > 0:
		bits.append(_mb(int(release.size)))
	sub.text = "   |   ".join(PackedStringArray(bits))
	you.text = "You have %s" % running
	var lines: Array = release.get("notes", [])
	news_head.text = "WHAT'S NEW"
	_show([title, sub, you, line])
	var y := 174.0
	if not lines.is_empty():
		news_head.visible = true
		for i in news.size():
			news[i].visible = i < lines.size()
			if i < lines.size():
				news[i].text = "-  " + str(lines[i])
				news[i].position = Vector2(48, 174 + i * 28)
		y = 174.0 + lines.size() * 28.0 + 12.0
	else:
		y = 146.0
	note.position = Vector2(36, y)
	note.size = Vector2(628, 64)
	if can_update:
		note.text = "UPDATE NOW downloads the new version, checks it, swaps it in and reopens the game. Settings and high scores are kept."
	else:
		note.text = "Finish or end the battle first. UPDATE NOW works when the battle is over (Game Over screen)."
	note.visible = true
	var by := y + 82.0
	later_button.position = Vector2(36, by)
	skip_button.position = Vector2(232, by)
	update_button.position = Vector2(484, by)
	update_button.size = Vector2(180, 56)
	update_button.disabled = not can_update
	_show([later_button, skip_button, update_button])
	_finish(by + 86.0, update_button if can_update else later_button)

func _build_words(build: String) -> String:
	# "WINDOWS ARM64" -> "Windows ARM64", "MAC (UNIVERSAL)" -> "Mac"
	match build:
		"WINDOWS X64": return "Windows x64"
		"WINDOWS ARM64": return "Windows ARM64"
		"MAC (UNIVERSAL)": return "Mac"
		"LINUX X86_64": return "Linux"
	return build

func _mb(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)

## UPDATING TO x, with the download bar.
func show_working(version: String, release: Dictionary, running: String, build: String) -> void:
	mode = "working"
	_hide_all()
	title.text = "UPDATING TO %s" % version
	var bits := ["%s for %s" % [version, _build_words(build)]]
	if str(release.get("date", "")) != "":
		bits.append("released %s" % release.date)
	if int(release.get("size", 0)) > 0:
		bits.append(_mb(int(release.size)))
	sub.text = "   |   ".join(PackedStringArray(bits))
	you.text = "You have %s" % running
	_show([title, sub, you, line])
	track.position = Vector2(36, 156)
	fill.position = Vector2(36, 156)
	fill.size.x = 0.0
	progress_text.position = Vector2(36, 180)
	step_text.position = Vector2(36, 208)
	progress_text.text = "STARTING THE DOWNLOAD"
	step_text.text = "Next: check the download, swap in %s, reopen the game" % version
	_show([track, fill, progress_text, step_text])
	cancel_button.position = Vector2(484, 252)
	cancel_button.visible = true
	cancel_button.disabled = false
	_finish(338.0, cancel_button)

func set_progress(done: int, total: int) -> void:
	if mode != "working":
		return
	var fraction := clampf(float(done) / float(total), 0.0, 1.0) if total > 0 else 0.0
	fill.size.x = BAR_WIDTH * fraction
	progress_text.text = ("DOWNLOADING  %.1f OF %.1f MB" % [done / 1048576.0, total / 1048576.0]) if total > 0 else ("DOWNLOADING  %.1f MB" % (done / 1048576.0))

## Steps after the download: CHECKING, UNPACKING, STARTING.
func set_stage(stage: String, version: String) -> void:
	if mode != "working":
		return
	match stage:
		"CHECKING":
			fill.size.x = BAR_WIDTH
			progress_text.text = "CHECKING THE DOWNLOAD"
			step_text.text = "Next: swap in %s, reopen the game" % version
		"UNPACKING":
			fill.size.x = BAR_WIDTH
			progress_text.text = "UNPACKING"
			step_text.text = "Next: swap in %s, reopen the game" % version
		"STARTING":
			fill.size.x = BAR_WIDTH
			progress_text.text = "STARTING %s" % version
			step_text.text = "This copy closes once the new one has started."
			cancel_button.disabled = true
			if cancel_button.has_focus():
				cancel_button.release_focus()

## A title, a short text and OK.
func show_message(heading: String, text: String) -> void:
	mode = "message"
	_hide_all()
	title.text = heading
	note.text = text
	note.add_theme_color_override("font_color", MUTED)
	note.position = Vector2(36, 76)
	note.size = Vector2(628, 64)
	_show([title, note])
	ok_button.position = Vector2(484, 152)
	ok_button.visible = true
	_finish(236.0, ok_button)

## GO BACK TO x? with CANCEL and GO BACK.
func show_confirm_go_back(version: String) -> void:
	mode = "confirm"
	_hide_all()
	title.text = "GO BACK TO VERSION %s?" % version
	note.text = "The game will close and reopen as version %s. Settings and high scores are kept." % version
	note.add_theme_color_override("font_color", AMBER)
	note.position = Vector2(36, 76)
	note.size = Vector2(628, 64)
	_show([title, note])
	cancel_button.position = Vector2(36, 152)
	cancel_button.disabled = false
	go_back_button.position = Vector2(464, 152)
	_show([cancel_button, go_back_button])
	_finish(236.0, cancel_button)

func close() -> void:
	mode = ""
	visible = false
	note.add_theme_color_override("font_color", AMBER)

## B or Esc: LATER, CANCEL or OK (never UPDATE NOW or GO BACK).
func back() -> void:
	match mode:
		"found": later_pressed.emit()
		"working":
			if cancel_button.visible and not cancel_button.disabled:
				cancel_pressed.emit()
		"message": ok_pressed.emit()
		"confirm": cancel_pressed.emit()

## Buttons the controller highlight can move between.
func focus_targets() -> Array[Control]:
	var out: Array[Control] = []
	for b in [later_button, skip_button, update_button, cancel_button, go_back_button, ok_button]:
		if b.visible and not b.disabled:
			out.append(b)
	out.sort_custom(func(a: Control, c: Control) -> bool: return a.position.x < c.position.x)
	return out

func _label(text: String, at: Vector2, size_box: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = size_box
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target.add_child(label)
	return label

func _button(text: String, size_box: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.size = size_box
	b.focus_mode = Control.FOCUS_ALL
	_target.add_child(b)
	return b
