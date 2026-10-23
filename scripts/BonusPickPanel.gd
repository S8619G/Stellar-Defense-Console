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
## 1.0.5: the KEEP / TAKE buttons are gone (the cards are the buttons), so the panel is
## shorter where they used to be.
const PANEL_SIZE := Vector2(820, 412)
const CARD_SIZE := Vector2(330, 170)
## Mouse travel (pixels) that counts as "the player moved the mouse".
const MOUSE_MOVE_PIXELS := 3.0

## Seconds before the prompt closes by itself and keeps the current bonus (1.0.5: 20 s).
var timeout_seconds: float = 20.0
## Small tag over the other card on the after-set offer (the first offer says JUST EARNED).
var set_offer_tag: String = "YOU CAN SWITCH TO"
## Card effect lines, filled in by the console from the battle's own values.
var rapid_seconds: float = 6.0
var double_seconds: float = 8.0

var current: String = "RAPID"
var other: String = "DOUBLE"
var set_offer: bool = false
var remaining: float = 0.0
## 1.0.5: true once the player has moved the mouse, pressed an arrow key or used a
## controller: the countdown stops and the prompt waits for a pick.
var waiting: bool = false
## What stopped the countdown: "mouse", "touch", "keyboard" or "controller" ("" = still counting).
var stopped_by: String = ""
## Card shown highlighted (0 = YOU HAVE NOW, the default; 1 = the other bonus).
var highlighted: int = 0
var mouse_travel: float = 0.0
var panel: Panel
var message_label: Label
var timeout_label: Label
## 1.0.5: the two cards are the pick buttons (0 = keep the current bonus, 1 = take the other).
var cards: Array[Button] = []
var card_tags: Array[Label] = []
var card_titles: Array[Label] = []
var card_effects: Array[Label] = []
var card_tag_texts: Array[String] = ["", ""]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	set_process_input(false)
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
		var card := Button.new()
		card.name = "Card%d" % index
		card.position = Vector2(44 + index * 402, 146)
		card.size = CARD_SIZE
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		card.text = ""
		panel.add_child(card)
		cards.append(card)
		card_tags.append(_label(card, "", Vector2(20, 14), Vector2(290, 22), 15, MUTED))
		card_titles.append(_label(card, "", Vector2(20, 42), Vector2(290, 34), 26, TEXT))
		card_effects.append(_label(card, "", Vector2(20, 86), Vector2(290, 70), 17, MUTED))
		card.pressed.connect(pick_card.bind(index))
		card.focus_entered.connect(_highlight.bind(index))
		card.mouse_entered.connect(_on_card_hover.bind(index))
	# Arrow keys and the D-pad move between the two cards only.
	for index in range(2):
		var card: Button = cards[index]
		var buddy: NodePath = card.get_path_to(cards[1 - index])
		var itself: NodePath = card.get_path_to(card)
		card.focus_neighbor_left = itself if index == 0 else buddy
		card.focus_neighbor_right = buddy if index == 0 else itself
		card.focus_neighbor_top = itself
		card.focus_neighbor_bottom = itself
		card.focus_next = buddy
		card.focus_previous = buddy
	timeout_label = _label(panel, "", Vector2(44, 336), Vector2(732, 26), 18, AMBER)
	_label(panel, "You can pick again after each set of five waves.", Vector2(44, 364), Vector2(732, 24), 15, MUTED)
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
	waiting = false
	stopped_by = ""
	mouse_travel = 0.0
	if after_set:
		message_label.text = "Set complete: keep your missile bonus or switch."
	else:
		message_label.text = "You just earned %s. You can only have one missile bonus." % full_name(other)
	card_tag_texts = ["YOU HAVE NOW", set_offer_tag if after_set else "JUST EARNED"]
	_fill_card(0, current)
	_fill_card(1, other)
	visible = true
	set_process(true)
	set_process_input(true)
	_center_panel()
	# The current bonus (YOU HAVE NOW) starts highlighted; Enter, Space or A picks it.
	_highlight(0)
	if is_inside_tree():
		cards[0].grab_focus()
	_update_timeout_text()

func is_open() -> bool:
	return visible

func _process(delta: float) -> void:
	if not visible:
		set_process(false)
		return
	if waiting:
		return
	remaining -= delta
	if remaining <= 0.0:
		_close(current, true)
		return
	_update_timeout_text()

## 1.0.5: mouse movement and arrow keys stop the countdown. (Controller input is reported
## by ControllerInput.gd through stop_countdown, because it handles those events first.)
func _input(event: InputEvent) -> void:
	if not visible or waiting:
		return
	if event is InputEventMouseMotion:
		mouse_travel += (event as InputEventMouseMotion).relative.length()
		if mouse_travel >= MOUSE_MOVE_PIXELS:
			stop_countdown("mouse")
	elif event is InputEventMouseButton and event.pressed:
		stop_countdown("mouse")
	elif event is InputEventScreenTouch and event.pressed:
		stop_countdown("touch")
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			stop_countdown("keyboard")

## Stop the countdown: the prompt now waits until the player picks a card.
func stop_countdown(source: String) -> void:
	if not visible or waiting:
		return
	waiting = true
	stopped_by = source
	_update_timeout_text()

func _update_timeout_text() -> void:
	if waiting:
		timeout_label.text = "Pick a bonus"
	else:
		timeout_label.text = "No pick in %d s: you keep %s" % [maxi(1, ceili(remaining)), full_name(current)]

## Pick card 0 (keep the current bonus) or card 1 (take the other one).
func pick_card(index: int) -> void:
	_close(current if index == 0 else other, false)

func _on_card_hover(index: int) -> void:
	if visible and is_inside_tree():
		cards[index].grab_focus()
	_highlight(index)

func _highlight(index: int) -> void:
	highlighted = clampi(index, 0, 1)
	for card_index in range(cards.size()):
		_paint_card(card_index, card_index == highlighted)

func _close(pick: String, timed_out: bool) -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	set_process_input(false)
	for card in cards:
		if card.has_focus():
			card.release_focus()
	picked.emit(pick, timed_out)

func full_name(pick: String) -> String:
	return "RAPID MISSILE" if pick == "RAPID" else "DOUBLE MISSILE"

func effect_text(pick: String) -> String:
	if pick == "RAPID":
		return "Fires 1 missile\nevery %s seconds" % _seconds_text(rapid_seconds)
	return "Fires a pair of missiles\nevery %s seconds" % _seconds_text(double_seconds)

func _fill_card(index: int, pick: String) -> void:
	card_tags[index].text = card_tag_texts[index]
	card_tags[index].add_theme_color_override("font_color", AMBER if card_tag_texts[index] == "JUST EARNED" else MUTED)
	card_titles[index].text = full_name(pick)
	card_effects[index].text = effect_text(pick)
	_paint_card(index, index == highlighted)

## The highlighted card gets the bright border and title; every state of the button
## (normal, hover, pressed, focus) uses the same look so only the highlight shows.
func _paint_card(index: int, lit: bool) -> void:
	var card: Button = cards[index]
	var look := _style(Color(0.09, 0.03, 0.07, 1.0) if lit else Color(0.04, 0.02, 0.04, 1.0), ACCENT if lit else EDGE, 10, 3 if lit else 2)
	var pressed_look := _style(Color(0.14, 0.05, 0.10, 1.0), ACCENT, 10, 3)
	for state in ["normal", "hover", "disabled", "hover_pressed"]:
		card.add_theme_stylebox_override(state, look)
	card.add_theme_stylebox_override("pressed", pressed_look)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card_titles[index].add_theme_color_override("font_color", ACCENT if lit else TEXT)

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
