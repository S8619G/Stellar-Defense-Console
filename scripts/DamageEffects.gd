extends Control
## 1.0.8: damage effects over the inner console (the centre panel, from under the top
## header down to the bottom button bar). Visual only: no gameplay, scoring or timing
## change, and its own random numbers (never the battle's).
##
## - Nuke hits the ship: brief scrambled screen (full hit about 0.8 s; a Defense Shield
##   partial hit about half strength for about 0.4 s).
## - Ship destroyed: heavy scramble (0.7 s), then the red SYSTEMS OFFLINE screen flickers
##   in (0.3 s); a light scramble repeats on it every 2.5 to 4 s. The score screen is put in
##   front 2 s after the red screen shows and is never scrambled.
## - SCREEN EFFECTS OFF (Settings): no scrambles; the red screen still shows (no flicker)
##   and the score screen comes in front 2 s after it.
## - 1.0.9: the SYSTEMS OFFLINE list types out one line about every 0.9 s, left to right,
##   with a block cursor, and steps up one line at a time once the panel is full.
## - 1.0.9: low hull warning: while the console says the hull is low (below 6%), a light
##   flicker of the same scramble (about 0.25 s at 7%) every 1.5 to 3 s. A nuke hit's own
##   scramble takes over while it plays. Off with SCREEN EFFECTS off.

const SYSTEM_NAMES: Array[String] = ["MAIN POWER", "AUXILIARY POWER", "RADAR", "TRACKING",
	"TARGETING", "DEFENSE SHIELD", "JUMP DRIVE", "NAVIGATION", "COMMUNICATIONS", "DATA LINK",
	"INTERCEPTOR LAUNCH BAY", "GUNSHIP BAY", "FIREWALL", "RAPID REPAIR", "DAMAGE CONTROL",
	"LIFE SUPPORT"]
const STATUSES: Array[String] = ["OFFLINE", "DESTROYED", "DAMAGED"]

## Timings (seconds) from the approved mockups.
const FULL_HIT_SECONDS := 0.8
const PARTIAL_HIT_SECONDS := 0.4
const PARTIAL_HIT_STRENGTH := 0.55
const DESTROY_SCRAMBLE_SECONDS := 0.7
const DESTROY_FLICKER_SECONDS := 0.3
const RED_TO_SCORE_SECONDS := 2.0
const LIGHT_PULSE_SECONDS := 0.3
const LIGHT_PULSE_STRENGTH := 0.4
const LIGHT_PULSE_GAP_MIN := 2.5
const LIGHT_PULSE_GAP_MAX := 4.0
## 1.0.9 SYSTEMS OFFLINE list: a new line every LINE_SECONDS, typed at TYPE_CHARS_PER_SECOND
## (name, dots, then status), stepping up one line in STEP_SCROLL_SECONDS when the panel is full.
const LINE_SECONDS := 0.9
const TYPE_CHARS_PER_SECOND := 90.0
const STEP_SCROLL_SECONDS := 0.12
## Block cursor blinks this many times a second on the newest line once it is typed.
const CURSOR_BLINKS_PER_SECOND := 1.5
## List layout on the red panel (panel pixels): first line top, line step, font size, margins.
const LIST_TOP := 222.0
const LIST_STEP := 53.0
const LIST_FONT_SIZE := 32
const LIST_MARGIN := 180.0
## 1.0.9 low hull flicker.
const LOW_HULL_SECONDS := 0.25
const LOW_HULL_STRENGTH := 0.07
const LOW_HULL_GAP_MIN := 1.5
const LOW_HULL_GAP_MAX := 3.0
## First flicker this long after the warning starts.
const LOW_HULL_FIRST_SECONDS := 0.6
## New scramble pattern this many times a second (the mockups ran at 30 frames a second).
const PATTERN_RATE := 30.0

## Inner console in 1920x1080 console pixels: centre +/- 550, under the header line
## (y 124) to the button bar line (bottom - 112).
const HALF_WIDTH := 550.0
const TOP := 125.0
const BOTTOM_GAP := 112.0

## Settings switch SCREEN EFFECTS (on by default).
var screen_effects_enabled: bool = true

var rng := RandomNumberGenerator.new()
var red_screen: ColorRect
var offline_text: Control
var scramble: ColorRect
var _red_material: ShaderMaterial
var _scramble_material: ShaderMaterial

## Nuke hit scramble.
var hit_time: float = -1.0
var hit_duration: float = 0.0
var hit_strength: float = 0.0
## Ship destroyed sequence (-1 = not destroyed).
var destroyed_time: float = -1.0
var destroyed_with_effects: bool = true
var statuses: Array[String] = []
var pulses: Array[float] = []
## Counters for tests and the session log.
var nuke_scrambles: int = 0
## 1.0.9 low hull warning: on while the console reports a low hull; the clock counts the
## seconds it has been on and the next flicker starts at low_hull_next.
var low_hull_warning: bool = false
var low_hull_clock: float = 0.0
var low_hull_next: float = LOW_HULL_FIRST_SECONDS
var low_hull_flickers: int = 0
var destroyed_sequences: int = 0
## The strength of the scramble shown this frame (0 = none), for tests and captures.
var scramble_strength: float = 0.0
var _pattern_clock: float = 0.0
var _flicker: float = 1.0
var _dropout: float = 1.0
var _title_font: FontVariation

func _ready() -> void:
	name = "DamageEffects"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.randomize()
	_title_font = FontVariation.new()
	_title_font.base_font = ThemeDB.fallback_font
	_title_font.variation_embolden = 0.9
	red_screen = ColorRect.new()
	red_screen.name = "RedScreen"
	red_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	red_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_red_material = ShaderMaterial.new()
	_red_material.shader = load("res://shaders/systems_offline_red.gdshader")
	red_screen.material = _red_material
	red_screen.visible = false
	add_child(red_screen)
	offline_text = Control.new()
	offline_text.name = "OfflineText"
	offline_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	offline_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offline_text.clip_contents = true
	offline_text.draw.connect(_draw_offline_text)
	red_screen.add_child(offline_text)
	scramble = ColorRect.new()
	scramble.name = "Scramble"
	scramble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scramble.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scramble_material = ShaderMaterial.new()
	_scramble_material.shader = load("res://shaders/screen_scramble.gdshader")
	scramble.material = _scramble_material
	scramble.visible = false
	add_child(scramble)

## The inner console rectangle in this node's parent (the console, 1920x1080 layout).
func inner_rect() -> Rect2:
	var parent_size: Vector2 = (get_parent() as Control).size if get_parent() is Control else Vector2(1920, 1080)
	var cx := parent_size.x * 0.5
	return Rect2(cx - HALF_WIDTH, TOP, HALF_WIDTH * 2.0, parent_size.y - BOTTOM_GAP - TOP)

func _fit_rect() -> void:
	var r := inner_rect()
	position = r.position
	size = r.size

## A nuke hit the ship. full = a direct hit; false = a Defense Shield partial hit.
func nuke_hit(full: bool) -> void:
	if not screen_effects_enabled or is_destroyed():
		return
	var strength := 1.0 if full else PARTIAL_HIT_STRENGTH
	var duration := FULL_HIT_SECONDS if full else PARTIAL_HIT_SECONDS
	if is_hit_active() and hit_strength * _envelope(hit_time, hit_duration) > strength:
		return
	hit_time = 0.0
	hit_strength = strength
	hit_duration = duration
	nuke_scrambles += 1

func is_hit_active() -> bool:
	return hit_time >= 0.0 and hit_time <= hit_duration

## The ship was destroyed: start the SYSTEMS OFFLINE sequence.
func ship_destroyed() -> void:
	if is_destroyed():
		return
	destroyed_time = 0.0
	destroyed_with_effects = screen_effects_enabled
	hit_time = -1.0
	statuses.clear()
	for i in range(SYSTEM_NAMES.size()):
		statuses.append(STATUSES[rng.randi_range(0, STATUSES.size() - 1)])
	pulses.clear()
	var t := red_start() + rng.randf_range(LIGHT_PULSE_GAP_MIN, LIGHT_PULSE_GAP_MAX)
	pulses.append(t)
	destroyed_sequences += 1

func is_destroyed() -> bool:
	return destroyed_time >= 0.0

## Seconds after the ship is destroyed when the red screen shows fully.
func red_start() -> float:
	return DESTROY_SCRAMBLE_SECONDS + DESTROY_FLICKER_SECONDS if destroyed_with_effects else 0.0

## True once the score screen should be in front (2 s after the red screen).
func score_screen_ready() -> bool:
	return is_destroyed() and destroyed_time >= red_start() + RED_TO_SCORE_SECONDS

## Seconds the red screen has shown fully (negative before).
func red_seconds() -> float:
	return destroyed_time - red_start() if is_destroyed() else -1.0

## Tests: jump straight to the moment the score screen comes in front.
func skip_to_score_screen() -> void:
	if is_destroyed():
		destroyed_time = maxf(destroyed_time, red_start() + RED_TO_SCORE_SECONDS)
		_update(0.0)

## Retry / New Battle: everything back to normal.
func reset() -> void:
	destroyed_time = -1.0
	hit_time = -1.0
	statuses.clear()
	pulses.clear()
	scramble_strength = 0.0
	set_low_hull_warning(false)
	red_screen.visible = false
	scramble.visible = false

## 1.0.9: the console turns the low hull warning on (hull below 6%) and off (6% or more,
## or the ship destroyed). Turning it on starts a fresh flicker timing.
func set_low_hull_warning(on: bool) -> void:
	if on == low_hull_warning:
		return
	low_hull_warning = on
	low_hull_clock = 0.0
	low_hull_next = LOW_HULL_FIRST_SECONDS

## Strength of the low hull flicker at this moment (0 between flickers).
func low_hull_flicker_strength() -> float:
	if not low_hull_warning or is_destroyed():
		return 0.0
	return LOW_HULL_STRENGTH * _envelope(low_hull_clock - low_hull_next, LOW_HULL_SECONDS)

func set_screen_effects(on: bool) -> void:
	screen_effects_enabled = on
	if not on:
		hit_time = -1.0

func _process(delta: float) -> void:
	_update(delta)

func _update(delta: float) -> void:
	_fit_rect()
	if hit_time >= 0.0:
		hit_time += delta
		if hit_time > hit_duration:
			hit_time = -1.0
	var strength := 0.0
	var red_alpha := 0.0
	if is_destroyed():
		destroyed_time += delta
		var u := destroyed_time
		if not destroyed_with_effects:
			red_alpha = 1.0
		elif u < DESTROY_SCRAMBLE_SECONDS:
			strength = minf(1.0, 0.75 + u / DESTROY_SCRAMBLE_SECONDS * 0.5)
		elif u < red_start():
			# Flicker in: every third pattern frame is a half-strength red screen, scrambled.
			if int(u * PATTERN_RATE) % 3 == 0:
				red_alpha = 0.5
				strength = 0.9
			else:
				red_alpha = 1.0
		else:
			red_alpha = 1.0
			if screen_effects_enabled:
				while not pulses.is_empty() and u > pulses[pulses.size() - 1] + LIGHT_PULSE_SECONDS:
					var next := pulses[pulses.size() - 1] + rng.randf_range(LIGHT_PULSE_GAP_MIN, LIGHT_PULSE_GAP_MAX)
					pulses.append(next)
					if pulses.size() > 8:
						pulses.remove_at(0)
				for p in pulses:
					var k := u - p
					if k >= 0.0 and k <= LIGHT_PULSE_SECONDS:
						strength = maxf(strength, LIGHT_PULSE_STRENGTH * _envelope(k, LIGHT_PULSE_SECONDS))
	elif is_hit_active():
		strength = hit_strength * _envelope(hit_time, hit_duration)
	if low_hull_warning and not is_destroyed():
		low_hull_clock += delta
		if low_hull_clock > low_hull_next + LOW_HULL_SECONDS:
			# One flicker finished: count it (when shown) and pick the next gap.
			if screen_effects_enabled:
				low_hull_flickers += 1
			low_hull_next = low_hull_clock + rng.randf_range(LOW_HULL_GAP_MIN, LOW_HULL_GAP_MAX)
		if not is_hit_active():
			strength = maxf(strength, low_hull_flicker_strength())
	if not screen_effects_enabled:
		strength = 0.0
	scramble_strength = strength
	red_screen.visible = red_alpha > 0.0
	if red_screen.visible:
		_red_material.set_shader_parameter("alpha", red_alpha)
		_red_material.set_shader_parameter("px_size", size)
		offline_text.modulate.a = red_alpha
		offline_text.queue_redraw()
	scramble.visible = strength > 0.001
	if scramble.visible:
		_pattern_clock += delta
		var seed_now := floorf(_pattern_clock * PATTERN_RATE)
		if seed_now != _scramble_material.get_shader_parameter("seed") or delta == 0.0:
			_flicker = rng.randf_range(1.0 - 0.45 * strength, 1.0 + 0.15 * strength)
			_dropout = 0.15 if rng.randf() < 0.12 * strength else 1.0
		_scramble_material.set_shader_parameter("seed", seed_now)
		_scramble_material.set_shader_parameter("intensity", strength)
		_scramble_material.set_shader_parameter("flicker", _flicker * _dropout)
		_scramble_material.set_shader_parameter("px_size", size)

## Full strength for the first 18%, then fading out.
static func _envelope(u: float, d: float) -> float:
	if u < 0.0 or u > d or d <= 0.0:
		return 0.0
	var k := u / d
	return 1.0 if k < 0.18 else pow(maxf(0.0, 1.0 - (k - 0.18) / 0.82), 1.3)

## Lines shown on the red screen so far (for tests).
func visible_line_count() -> int:
	if red_seconds() < 0.0:
		return 0
	return int(red_seconds() / LINE_SECONDS) + 1

## 1.0.9: how many characters of list line i are typed so far (name, dots and status).
func typed_chars(line_index: int) -> int:
	if red_seconds() < 0.0:
		return 0
	return maxi(0, int((red_seconds() - line_index * LINE_SECONDS) * TYPE_CHARS_PER_SECOND))

## 1.0.9: lines that fit on the red panel below the title before the list steps up.
func list_rows() -> int:
	return maxi(1, int(floor((offline_text.size.y - 36.0 - LIST_TOP) / LIST_STEP)))

## 1.0.9: how far the list has stepped up, in pixels. Each new line past a full panel moves
## it up one line in STEP_SCROLL_SECONDS (fast at first, easing in).
func list_scroll_offset() -> float:
	var t_on := maxf(0.0, red_seconds())
	var n := visible_line_count()
	var rows := list_rows()
	var since := t_on - (n - 1) * LINE_SECONDS
	var before := maxf(0.0, n - 1 - rows) * LIST_STEP
	var after := maxf(0.0, n - rows) * LIST_STEP
	var k := clampf(since / STEP_SCROLL_SECONDS, 0.0, 1.0)
	return lerpf(before, after, 1.0 - pow(1.0 - k, 2.0))

## 1.0.9: the dots between a system name and its status, filling the room between them.
func _dots_for(font: Font, system_name: String, state: String, w: float) -> String:
	var nw := font.get_string_size(system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE).x
	var sw := font.get_string_size(state, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE).x
	var dot_width := font.get_string_size(" .", HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE).x
	var room := (w - LIST_MARGIN - sw - 14.0) - (LIST_MARGIN + nw + 14.0)
	return " .".repeat(maxi(0, int(floor(room / maxf(1.0, dot_width)))))

func _draw_offline_text() -> void:
	var w := offline_text.size.x
	var h := offline_text.size.y
	var font: Font = _title_font
	var white := Color(1, 1, 1)
	# Title, fitted to the panel width.
	var title := "SYSTEMS OFFLINE"
	var title_size := 101
	while title_size > 40 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > w - 120.0:
		title_size -= 2
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	offline_text.draw_string(font, Vector2((w - tw) * 0.5, 50.0 + font.get_ascent(title_size)), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, white)
	offline_text.draw_line(Vector2(132, 192), Vector2(w - 132, 192), white, 3.0)
	# 1.0.9: the list types out line by line, then steps up one line at a time.
	var t_on := maxf(0.0, red_seconds())
	var bottom := h - 36.0
	var n := visible_line_count()
	var rows := list_rows()
	var offset := list_scroll_offset()
	var lx := LIST_MARGIN
	var rx := w - LIST_MARGIN
	var ascent := font.get_ascent(LIST_FONT_SIZE)
	for i in range(maxi(0, n - rows - 2), n):
		var y := LIST_TOP + i * LIST_STEP - offset
		if y < LIST_TOP - LIST_STEP or y > bottom:
			continue
		var index := i % SYSTEM_NAMES.size()
		var system_name := SYSTEM_NAMES[index]
		var state: String = statuses[index] if index < statuses.size() else "OFFLINE"
		# The top line fades out as it steps up past the line under the title.
		var alpha := 1.0
		if y < LIST_TOP:
			alpha = maxf(0.0, 1.0 - (LIST_TOP - y) / LIST_STEP)
		if alpha <= 0.0:
			continue
		var dots := _dots_for(font, system_name, state, w)
		var typed := typed_chars(i)
		var base := y + ascent
		var ink := Color(1, 1, 1, alpha)
		var name_part := system_name.substr(0, mini(typed, system_name.length()))
		offline_text.draw_string(font, Vector2(lx, base), name_part, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE, ink)
		var cursor_x := lx + font.get_string_size(name_part, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE).x
		var dots_x := lx + font.get_string_size(system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE).x + 14.0
		var dots_typed := clampi(typed - system_name.length(), 0, dots.length())
		if dots_typed > 0:
			var dots_part := dots.substr(0, dots_typed)
			offline_text.draw_string(font, Vector2(dots_x, base), dots_part, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE, Color(1.0, 0.8, 0.8, alpha * 0.8))
			cursor_x = dots_x + font.get_string_size(dots_part, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE).x
		var state_x := rx - font.get_string_size(state, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE).x
		var state_typed := clampi(typed - system_name.length() - dots.length(), 0, state.length())
		if state_typed > 0:
			var state_part := state.substr(0, state_typed)
			offline_text.draw_string(font, Vector2(state_x, base), state_part, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE, ink)
			cursor_x = state_x + font.get_string_size(state_part, HORIZONTAL_ALIGNMENT_LEFT, -1, LIST_FONT_SIZE).x
		# Block cursor: follows the typing, then blinks at the end of the newest line.
		var typing := typed < system_name.length() + dots.length() + state.length()
		if typing or (i == n - 1 and int(t_on * CURSOR_BLINKS_PER_SECOND * 2.0) % 2 == 0):
			offline_text.draw_rect(Rect2(cursor_x + 4.0, base - ascent * 0.9, 18.0, ascent), ink)
