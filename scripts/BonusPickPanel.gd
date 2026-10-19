extends Control
## 0.1.2 missile bonus pick prompt. Shown when both missile bonuses are earned (Rapid
## Missile and Double Missile) and again after each set of five waves. The player keeps
## the bonus they have or takes the other one; with no pick in time the current bonus
## is kept. The console pauses the battle while it is open. Built in code (same look as
## the Settings panel) so it needs no extra scene file. Layout matches
## design/mockups-0.1.2/mock_bonus_pick.png.

## Answer: Pick is "RAPID" or "DOUBLE"; Timed Out = no pick before the timer ran out.
signal picked(pick: String, timed_out: bool)

const EDGE := Color("#77324f")
const TEXT := Color("#ede0e8")
const MUTED := Color("#b9a8b2")
const ACCENT := Color(1.0, 0.6, 0.78)
const AMBER := Color("#ffe28b")
const PANEL_SIZE := Vector2(820, 470)
const CARD_SIZE := Vector2(330, 170)

## Seconds before the prompt closes by itself and keeps the current bonus.
var timeout_seconds: float = 10.0
## Small tag over the other card on the after-set offer (the first offer says JUST EARNED).
var set_offer_tag: String = "YOU CAN SWITCH TO"
## Card effect lines, filled in by the console from the battle's own values.
var rapid_seconds: float = 6.0
var double_seconds: float = 8.0

var current: String = "RAPID"
var other: String = "DOUBLE"
var set_offer: bool = false
var remaining: float = 0.0
var panel: Panel
var message_label: Label
var timeout_label: Label
var keep_button: Button
var take_button: Button
var cards: Array[Panel] = []
var card_tags: Array[Label] = []
var card_titles: Array[Label] = []
var card_effects: Array[Label] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	panel = Panel.new()
	panel.name = "Panel"
	panel.size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.015, 0.03, 0.97), Color(0.55, 0.23, 0.38)))
	add_child(panel)
	_label(panel, "PICK ONE MISSILE BONUS", Vector2(44, 26), Vector2(560, 40), 30, ACCENT)
	_label(panel, "BATTLE PAUSED", Vector2(PANEL_SIZE.x - 344, 34), Vector2(300, 30), 18, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var line := ColorRect.new()
	line.color = EDGE
	line.position = Vector2(44, 84)
	line.size = Vector2(PANEL_SIZE.x - 88, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
	message_label = _label(panel, "", Vector2(44, 100), Vector2(732, 30), 18, TEXT)
	for index in range(2):
		var card := Panel.new()
		card.name = "Card%d" % index
		card.position = Vector2(44 + index * 402, 146)
		card.size = CARD_SIZE
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(card)
		cards.append(card)
		card_tags.append(_label(card, "", Vector2(20, 14), Vector2(290, 22), 15, MUTED))
		card_titles.append(_label(card, "", Vector2(20, 42), Vector2(290, 34), 26, TEXT))
		card_effects.append(_label(card, "", Vector2(20, 86), Vector2(290, 70), 17, MUTED))
	timeout_label = _label(panel, "", Vector2(44, 336), Vector2(600, 26), 18, AMBER)
	_label(panel, "You can pick again after each set of five waves.", Vector2(44, 364), Vector2(600, 24), 15, MUTED)
	keep_button = _button("KeepButton", Vector2(44, 396))
	keep_button.pressed.connect(_answer.bind(true))
	take_button = _button("TakeButton", Vector2(446, 396))
	take_button.pressed.connect(_answer.bind(false))
	resized.connect(_center_panel)
	_center_panel()

func _center_panel() -> void:
	if panel:
		panel.position = ((size - PANEL_SIZE) * 0.5).round()

## Show the prompt. Current = the bonus in use now; Other = the one the player can take.
func open(current_pick: String, other_pick: String, after_set: bool) -> void:
	current = current_pick
	other = other_pick
	set_offer = after_set
	remaining = maxf(1.0, timeout_seconds)
	if after_set:
		message_label.text = "Set complete: keep your missile bonus or switch."
	else:
		message_label.text = "You just earned %s. You can only have one missile bonus." % full_name(other)
	_fill_card(0, current, "YOU HAVE NOW", true)
	_fill_card(1, other, set_offer_tag if after_set else "JUST EARNED", false)
	timeout_label.text = "No pick in %s s: you keep %s" % [_seconds_text(remaining), full_name(current)]
	keep_button.text = "KEEP %s" % current
	take_button.text = "TAKE %s" % other
	visible = true
	set_process(true)
	_center_panel()

func is_open() -> bool:
	return visible

func _process(delta: float) -> void:
	if not visible:
		set_process(false)
		return
	remaining -= delta
	if remaining <= 0.0:
		_close(current, true)

func _answer(keep: bool) -> void:
	_close(current if keep else other, false)

func _close(pick: String, timed_out: bool) -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	picked.emit(pick, timed_out)

func full_name(pick: String) -> String:
	return "RAPID MISSILE" if pick == "RAPID" else "DOUBLE MISSILE"

func effect_text(pick: String) -> String:
	if pick == "RAPID":
		return "Fires 1 missile\nevery %s seconds" % _seconds_text(rapid_seconds)
	return "Fires a pair of missiles\nevery %s seconds" % _seconds_text(double_seconds)

func _fill_card(index: int, pick: String, tag: String, selected: bool) -> void:
	cards[index].add_theme_stylebox_override("panel", _style(Color(0.09, 0.03, 0.07, 1.0) if selected else Color(0.04, 0.02, 0.04, 1.0), ACCENT if selected else EDGE, 10, 3 if selected else 2))
	card_tags[index].text = tag
	card_tags[index].add_theme_color_override("font_color", AMBER if tag == "JUST EARNED" else MUTED)
	card_titles[index].text = full_name(pick)
	card_titles[index].add_theme_color_override("font_color", ACCENT if selected else TEXT)
	card_effects[index].text = effect_text(pick)

func _seconds_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	return "%.1f" % value

func _style(bg: Color, border: Color, radius := 12, width := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s

func _label(parent: Control, text: String, at: Vector2, box: Vector2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = box
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(node_name: String, at: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = at
	button.size = Vector2(330, 56)
	button.focus_mode = Control.FOCUS_ALL
	panel.add_child(button)
	return button
