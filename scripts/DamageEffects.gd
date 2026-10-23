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
	red_screen.visible = false
	scramble.visible = false

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
	return int(red_seconds() * (1.0 / 0.38)) + 1

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
	# The list: one line about every 0.38 s from the top, then it scrolls up.
	var t_on := maxf(0.0, red_seconds())
	var top := 222.0
	var bottom := h - 36.0
	var step := 53.0
	var speed := step / 0.38
	var line_size := 32
	var n := int(t_on * speed / step) + 1
	var offset := maxf(0.0, t_on * speed + step - (bottom - top))
	var lx := 180.0
	var rx := w - 180.0
	var ascent := font.get_ascent(line_size)
	var dot_width := font.get_string_size(" .", HORIZONTAL_ALIGNMENT_LEFT, -1, line_size).x
	for i in range(maxi(0, n - 20), n):
		var y := top + i * step - offset
		if y < top - step or y > bottom:
			continue
		var index := i % SYSTEM_NAMES.size()
		var system_name := SYSTEM_NAMES[index]
		var state: String = statuses[index] if index < statuses.size() else "OFFLINE"
		var alpha := 1.0
		if offset > 0.0 and y < top + 50.0:
			alpha = maxf(0.0, (y - top + 10.0) / 60.0)
		if y > bottom - 30.0:
			alpha = maxf(0.0, (bottom - y) / 30.0)
		if alpha <= 0.0:
			continue
		var nw := font.get_string_size(system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size).x
		var sw := font.get_string_size(state, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size).x
		var base := y + ascent
		offline_text.draw_string(font, Vector2(lx, base), system_name, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size, Color(1, 1, 1, alpha))
		var x := lx + nw + 14.0
		var room := (rx - sw - 14.0) - x
		var dots := ""
		var count := int(floor(room / maxf(1.0, dot_width)))
		for d in range(maxi(0, count)):
			dots += " ."
		offline_text.draw_string(font, Vector2(x, base), dots, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size, Color(1.0, 0.8, 0.8, alpha * 0.8))
		offline_text.draw_string(font, Vector2(rx - sw, base), state, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size, Color(1, 1, 1, alpha))
