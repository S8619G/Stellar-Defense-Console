extends Control
## Approved, unmodified outline. Interior mask follows its connected silhouette.
## No in-ship Jump/Hull readouts. The center inset is the special-weapon button.
## INTRUSION DETECTION retains its existing location and drawing priority.
## 1.06: the outline pulses brighter green while a Rapid Repair runs.
## 1.07: the EMP is offered on the split FIREWALL button, so INTRUSION DETECTION
## always stays visible here (Emp On Ship brings back the 1.06 USE EMP box).
const OUTLINE = preload("res://assets/ship_outline.png")
## 1.1.0: the ship's fill in 45-degree stripes, for the breach alert.
const BREACH_STRIPES = preload("res://assets/ship_breach_stripes.png")
const FILL = preload("res://assets/ship_fill.png")
const CenterWeaponButton = preload("res://scripts/ShipWeaponButton.gd")
## Traced from the actual center inset, matching the approved 2026-10-18 markup.
## These coordinates preserve its rear notch and angled shoulders.
const CENTER_WEAPON_POLYGON := [
	Vector2(18, 212), Vector2(29, 221), Vector2(80, 224),
	Vector2(102, 242), Vector2(100, 285), Vector2(80, 301),
	Vector2(32, 302), Vector2(20, 308), Vector2(20, 312),
	Vector2(82, 312), Vector2(171, 327), Vector2(363, 327),
	Vector2(367, 320), Vector2(746, 319), Vector2(744, 195),
	Vector2(367, 195), Vector2(363, 189), Vector2(173, 189),
	Vector2(81, 210),
]
const CENTER_WEAPON_LABEL := Vector2(430, 258)
## Top (port-side) edge of the approved outline, in REGION pixels (traced from
## the retained ship_upper_defense.svg). The Defense Shield arc is built from it.
const TOP_EDGE := [Vector2(12, 208), Vector2(42, 158), Vector2(72, 146), Vector2(102, 134), Vector2(132, 122), Vector2(162, 110), Vector2(192, 107), Vector2(223, 107), Vector2(253, 107), Vector2(283, 107), Vector2(313, 113), Vector2(343, 136), Vector2(373, 157), Vector2(404, 157), Vector2(434, 42), Vector2(464, 30), Vector2(494, 30), Vector2(524, 30), Vector2(554, 30), Vector2(585, 30), Vector2(615, 30), Vector2(645, 30), Vector2(675, 30), Vector2(705, 30), Vector2(735, 30), Vector2(765, 30), Vector2(796, 30), Vector2(826, 30), Vector2(856, 30), Vector2(886, 20), Vector2(916, 12), Vector2(946, 12), Vector2(977, 12), Vector2(1007, 13), Vector2(1037, 13), Vector2(1067, 13), Vector2(1097, 30), Vector2(1127, 49), Vector2(1158, 69), Vector2(1188, 89), Vector2(1218, 108), Vector2(1248, 128), Vector2(1278, 159), Vector2(1308, 188), Vector2(1339, 218)]
const REGION := Rect2(0, 0, 1352, 505)
@export var contacts_path: NodePath = ^"../CenterContainer/Dome/Contacts"
@export_range(0.1, 0.8) var fill_opacity: float = 0.34
## Defense Shield arc: a smooth flak arc curving over the port side of the ship.
## Gap is the closest clearance; Projection pushes the arc further out from the ship.
@export_range(6.0, 30.0) var defense_gap_pixels: float = 12.0
@export_range(0.0, 30.0) var defense_arc_projection: float = 3.0
## How far (pixels) the arc reaches past the stern and bow.
@export_range(0.0, 40.0) var defense_arc_overhang: float = 8.0
@export_range(1.0, 8.0) var defense_arc_width: float = 3.0
## How fast the fire colors flicker along the line (changes per second).
@export_range(1.0, 30.0) var flak_flicker_hz: float = 12.0
## Fraction of the line that sparkles bright yellow-white at any moment.
@export_range(0.0, 0.5) var flak_sparkle_amount: float = 0.12
@export var flak_yellow := Color(1.0, 0.86, 0.10)
@export var flak_orange := Color(1.0, 0.52, 0.06)
@export var flak_deep := Color(0.92, 0.30, 0.04)
@export var flak_sparkle := Color(1.0, 0.97, 0.66)
## Horizontal centers (fraction of the outline width) of the JUMP and HULL readouts.
@export_range(0.05, 0.45) var jump_center: float = 0.18
## 1.08: the JUMP readout while a Breacher breach holds JUMP offline.
@export var jump_offline_color := Color("#ff6b6b")
@export_range(10, 30) var jump_offline_font_size: int = 18
@export_range(0.55, 0.95) var hull_center: float = 0.855
@export_group("Intrusion Detection")
@export var intrusion_box_size := Vector2(150, 64)
@export_range(4.0, 24.0) var intrusion_stripe_width: float = 9.0
@export_range(0.5, 8.0) var intrusion_flash_hz: float = 3.0
@export var intrusion_red := Color(0.86, 0.08, 0.12, 0.85)
## 1.1.0: on = while a Breacher is hacking or draining, the whole ship
## fill flashes red stripes and INTRUSION DETECTION shows in the NAV DATA window,
## so nothing covers the STEALTH WEAPON buttons. Off = the 1.0.9 box on the ship.
@export var breach_alert_on_ship_fill: bool = true
@export_group("Rapid Repair and EMP")
## Outline color reached at the top of each Rapid Repair pulse.
@export var repair_green := Color("#9dffb8")
@export var emp_blue := Color(0.35, 0.78, 1.0)
## 1.07: off = INTRUSION DETECTION always shows; the EMP is on the FIREWALL button.
@export var emp_on_ship: bool = false
@export_group("Stealth Weapon")
## 0.1.2: the center inset becomes the blue button only while the Stealth
## Interceptor can launch. Both flight pods retain their normal hull colour.
@export var stealth_blue := Color("#2a9dff")
@export var stealth_label: String = "STEALTH WEAPON"
@export_range(10, 24) var stealth_font_size: int = 15
## Gentle brightness pulse (cycles per second), not a flash.
@export_range(0.2, 2.0) var stealth_pulse_hz: float = 0.8
@onready var battle: Control = get_node(contacts_path)
var stealth_button: CenterWeaponButton
var stealth_box := Rect2()
## 1.1.0: the two pills (NUKES, PULSE) shown while a PULSE BOMB charge is held,
## in REGION pixels, and their latest screen rectangles (local to this control).
const PILL_NUKES := Rect2(140, 211, 270, 94)
const PILL_PULSE := Rect2(440, 211, 270, 94)
var nukes_pill_rect := Rect2()
## Controller hold toward the PULSE BOMB: 0..1 while held, -1 when not held.
var pulse_hold_progress: float = -1.0
var pulse_pill_rect := Rect2()
signal stealth_launched
## Invisible click area over the USE EMP box (shown only while the EMP can fire).
var emp_button: Button
var emp_box := Rect2()
signal emp_used

func _ready() -> void:
	emp_button = Button.new()
	emp_button.name = "UseEmpButton"
	emp_button.flat = true
	emp_button.focus_mode = Control.FOCUS_NONE
	emp_button.mouse_filter = Control.MOUSE_FILTER_STOP
	emp_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		emp_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	emp_button.visible = false
	emp_button.pressed.connect(_on_emp_pressed)
	add_child(emp_button)
	stealth_button = CenterWeaponButton.new()
	stealth_button.name = "StealthWeaponButton"
	stealth_button.flat = true
	stealth_button.focus_mode = Control.FOCUS_NONE
	stealth_button.mouse_filter = Control.MOUSE_FILTER_STOP
	stealth_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		stealth_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	stealth_button.visible = false
	stealth_button.pressed.connect(_on_stealth_pressed)
	add_child(stealth_button)

func _on_stealth_pressed() -> void:
	if not is_instance_valid(battle):
		return
	var use_pulse := true
	if int(battle.get("pulse_charges")) > 0:
		# 1.1.0: the player picks a pill. Left half (NUKES pill side) keeps the
		# charge for later; right half (PULSE pill side) drops the PULSE BOMB. A controller
		# press (mouse not over the button) uses the PULSE BOMB.
		var mouse := get_local_mouse_position()
		if Rect2(stealth_box).has_point(mouse):
			var split := (nukes_pill_rect.end.x + pulse_pill_rect.position.x) * 0.5
			use_pulse = mouse.x >= split
	fire_stealth(use_pulse)

func fire_stealth(use_pulse: bool) -> bool:
	if is_instance_valid(battle) and battle.launch_stealth(use_pulse):
		stealth_launched.emit()
		return true
	return false

func _on_emp_pressed() -> void:
	if is_instance_valid(battle) and battle.request_emp():
		emp_used.emit()

func _process(_delta: float) -> void:
	if is_instance_valid(emp_button) and is_instance_valid(battle):
		var can_fire: bool = emp_on_ship and battle.can_use_emp() and emp_box.size.x > 0.0
		emp_button.visible = can_fire
		if can_fire:
			emp_button.position = emp_box.position
			emp_button.size = emp_box.size
	if is_instance_valid(stealth_button) and is_instance_valid(battle):
		var ready: bool = battle.can_launch_stealth() and stealth_box.size.x > 0.0
		stealth_button.visible = ready
		if ready:
			stealth_button.position = stealth_box.position
			stealth_button.size = stealth_box.size
			# Existing alert/EMP overlays keep priority. Clicking their box must
			# never accidentally launch a special weapon underneath it.
			var overlay: bool = (emp_on_ship and battle.can_use_emp()) or (battle.hack_state() in ["hacking", "draining"] and not breach_alert_on_ship_fill)
			stealth_button.blocked_rect = Rect2(emp_box.position - stealth_box.position, emp_box.size) if overlay else Rect2()
	_since_redraw += _delta
	_check_redraw.call_deferred()

# ---------- 1.1.0 REDRAW ONLY WHAT CHANGES ----------
## 1.1.0: the ship is rebuilt every frame only while something on it moves (the
## STEALTH WEAPON pulse, the flak arc, the USE EMP box); otherwise only when what it
## shows changes. Off = every frame (1.0.9).
@export var redraw_only_changes: bool = true
## Safety net: a full rebuild at least this often (seconds), even when nothing changed.
@export_range(0.1, 5.0) var redraw_safety_seconds: float = 1.0
## Times the ship was rebuilt (for tests and the speed check).
var redraw_count: int = 0
var _redraw_key: Array = []
var _since_redraw: float = 0.0
var _key_props: Array[String] = []
const KEY_SKIP: Array[String] = ["battle", "stealth_button", "emp_button", "redraw_count", "_redraw_key",
	"_since_redraw", "_key_props", "_arc_cache", "_arc_cache_key"]

## True while something on the ship moves every frame.
func ship_animating() -> bool:
	if not is_instance_valid(battle):
		return false
	return battle.can_launch_stealth() or (battle.prox_active and not battle.is_defeated()) \
		or (emp_on_ship and battle.can_use_emp())

## 1.1.0: everything the ship shows, in one list. A change in any of it = rebuild.
func redraw_key() -> Array:
	var key: Array = []
	if _key_props.is_empty():
		for property in get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not String(property.name) in KEY_SKIP:
				_key_props.append(String(property.name))
	for name in _key_props:
		var value: Variant = get(name)
		key.append(value.duplicate(true) if value is Array or value is Dictionary else value)
	key.append(size)
	if not is_instance_valid(battle):
		return key
	var state: String = battle.hack_state()
	key.append_array([hull_display_color(), state, battle.can_launch_stealth(), battle.prox_active,
		battle.is_defeated(), battle.can_use_emp(), battle.get("pulse_charges"), battle.get("pulse_color")])
	if state in ["hacking", "draining"]:
		key.append(int(battle.battle_time * intrusion_flash_hz * 2.0) % 2)
	return key

func _check_redraw() -> void:
	if not redraw_only_changes or ship_animating() or _since_redraw >= redraw_safety_seconds:
		_redraw_key = []
		_since_redraw = 0.0
		queue_redraw()
		return
	var key := redraw_key()
	if key != _redraw_key:
		_redraw_key = key
		_since_redraw = 0.0
		queue_redraw()

static func damage_color(fraction: float) -> Color:
	var value := clampf(fraction, 0.0, 1.0)
	if value >= 0.65:
		return Color("#bef5a0").lerp(Color("#32d86d"), (value - 0.65) / 0.35)
	if value >= 0.30:
		return Color("#ff9b38").lerp(Color("#bef5a0"), (value - 0.30) / 0.35)
	return Color("#f03939").lerp(Color("#ff9b38"), value / 0.30)

func hull_display_color() -> Color:
	# Shared by the ship and the vertical hull gauge so they never drift.
	var tint := damage_color(battle.hull / maxf(1.0, battle.max_hull))
	var repair_pulse: float = battle.repair_flash_level()
	if repair_pulse > 0.0:
		tint = tint.lerp(repair_green, repair_pulse)
	if battle.hit_flash_remaining > 0.0:
		tint = Color("#ff243f")
	return tint

func _draw() -> void:
	redraw_count += 1
	if not is_instance_valid(battle):
		return
	var width := minf(size.x, size.y * REGION.size.x / REGION.size.y)
	var dimensions := Vector2(width, width * REGION.size.y / REGION.size.x)
	var rect := Rect2((size - dimensions) * 0.5, dimensions)
	var tint := hull_display_color()
	if breach_fill_active():
		# Black under the stripes, then red stripes that flash bright and dim.
		var bright := int(battle.battle_time * intrusion_flash_hz * 2.0) % 2 == 0
		draw_texture_rect_region(FILL, rect, REGION, Color(0, 0, 0, 0.85))
		draw_texture_rect_region(BREACH_STRIPES, rect, REGION, Color(intrusion_red, 0.95 if bright else 0.45))
	else:
		draw_texture_rect_region(FILL, rect, REGION, Color(tint, fill_opacity))
	draw_texture_rect_region(OUTLINE, rect, REGION, Color(tint, 0.95))
	var k := dimensions.x / REGION.size.x
	var weapon_polygon := center_weapon_points(rect)
	stealth_box = Rect2(weapon_polygon[0], Vector2.ZERO)
	for point in weapon_polygon:
		stealth_box = stealth_box.expand(point)
	var local_polygon := PackedVector2Array()
	for point in weapon_polygon:
		local_polygon.append(point - stealth_box.position)
	stealth_button.hit_polygon = local_polygon
	if battle.can_launch_stealth():
		_draw_stealth_button(rect, k)
	if battle.prox_active and not battle.is_defeated():
		# Ship's port/left side is the TOP of this horizontal screen silhouette.
		# A separate flak arc stays above the art with a visible air gap.
		_draw_flak_arc(defense_arc(rect))
	# 0.1.2: no Jump or Hull readouts inside Aegis. Hull tint and the separate
	# vertical gauge remain; Jump charge/offline state remains on its button.
	var middle := rect.position + dimensions * Vector2(0.49, 0.5)
	emp_box = Rect2(middle - intrusion_box_size * 0.5, intrusion_box_size)
	if emp_on_ship and battle.can_use_emp():
		_draw_use_emp(middle)
	elif battle.hack_state() in ["hacking", "draining"] and not breach_alert_on_ship_fill:
		_draw_intrusion(middle)

func breach_fill_active() -> bool:
	return breach_alert_on_ship_fill and battle.hack_state() in ["hacking", "draining"]

var _arc_cache_key := Rect2()
var _arc_cache := PackedVector2Array()

func defense_arc(rect: Rect2) -> PackedVector2Array:
	# A smooth, gentle elliptical arc over the port side of the ship. Its shape
	# (center and width) was fitted to the outline; its height is set so the
	# arc clears every point of the top edge by Gap + Projection pixels.
	var key := Rect2(rect.position, rect.size + Vector2(defense_gap_pixels, defense_arc_projection))
	if key == _arc_cache_key and not _arc_cache.is_empty():
		return _arc_cache
	var k := rect.size.x / REGION.size.x
	var cx := REGION.size.x * 0.5
	var cy := REGION.size.y * 1.14
	var rx := REGION.size.x * 0.80
	var clearance := (defense_gap_pixels + defense_arc_projection) / k
	var ry := 0.0
	for i in range(TOP_EDGE.size() - 1):
		var a: Vector2 = TOP_EDGE[i]
		var b: Vector2 = TOP_EDGE[i + 1]
		for step in range(8):
			var p := a.lerp(b, step / 8.0)
			var u := (p.x - cx) / rx
			ry = maxf(ry, (cy - (p.y - clearance)) / sqrt(1.0 - u * u))
	var overhang := defense_arc_overhang / k
	var out := PackedVector2Array()
	var count := 96
	for i in range(count + 1):
		var x := lerpf(-overhang, REGION.size.x + overhang, float(i) / count)
		var u := (x - cx) / rx
		var y := cy - ry * sqrt(maxf(0.0, 1.0 - u * u))
		out.append(rect.position + Vector2(x, y) * k)
	_arc_cache_key = key
	_arc_cache = out
	return out

func flak_color(index: int, time: float) -> Color:
	# Fire-like flicker: each short piece of the line blends between yellow,
	# orange and deep orange, with brief bright sparkles. The line never widens.
	var step := floorf(time * flak_flicker_hz)
	var blend := time * flak_flicker_hz - step
	var a := _hash01(index, int(step))
	var b := _hash01(index, int(step) + 1)
	var heat := lerpf(a, b, blend) * 0.7 + 0.3 * (0.5 + 0.5 * sin(index * 0.45 - time * 7.0))
	var color: Color
	if heat < 0.5:
		color = flak_deep.lerp(flak_orange, heat * 2.0)
	else:
		color = flak_orange.lerp(flak_yellow, (heat - 0.5) * 2.0)
	if _hash01(index * 7 + 3, int(step)) < flak_sparkle_amount:
		color = color.lerp(flak_sparkle, 1.0 - blend)
	return color

static func _hash01(a: int, b: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h >> 8) & 0xFFFF) / 65535.0

func _draw_flak_arc(points: PackedVector2Array) -> void:
	var time: float = battle.battle_time
	var piece := 0
	var carry := 0.0
	var segment_length := 5.0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var done := 0.0
		while done < length:
			var take := minf(segment_length - carry, length - done)
			var from := a.lerp(b, done / length)
			var to := a.lerp(b, (done + take) / length)
			draw_line(from, to, flak_color(piece, time), defense_arc_width, true)
			done += take
			carry += take
			if carry >= segment_length:
				carry = 0.0
				piece += 1

func _draw_intrusion(center: Vector2) -> void:
	# Red-outlined box filled with thick 45-degree red and black stripes.
	var box := Rect2(center - intrusion_box_size * 0.5, intrusion_box_size)
	draw_rect(box, Color.BLACK)
	var corners := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	var w := maxf(2.0, intrusion_stripe_width)
	var step := w * 2.0
	var start := -box.size.y
	while start < box.size.x:
		var x0 := box.position.x + start
		var band := PackedVector2Array([Vector2(x0, box.end.y), Vector2(x0 + w, box.end.y),
			Vector2(x0 + w + box.size.y, box.position.y), Vector2(x0 + box.size.y, box.position.y)])
		for piece in Geometry2D.intersect_polygons(band, corners):
			draw_colored_polygon(piece, intrusion_red)
		start += step
	draw_rect(box, Color(1.0, 0.16, 0.2), false, 2.0)
	# Flashing text on a dark plate so it stays readable over the stripes.
	if int(battle.battle_time * intrusion_flash_hz * 2.0) % 2 == 0:
		var plate := Rect2(box.position + Vector2(8, 10), box.size - Vector2(16, 20))
		draw_rect(plate, Color(0, 0, 0, 0.78))
		var font := ThemeDB.fallback_font
		var mid := box.get_center()
		for line in [["INTRUSION", -3.0], ["DETECTION", 17.0]]:
			var size_px := 17
			var width := font.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
			var at := mid + Vector2(-width * 0.5, line[1])
			draw_string_outline(font, at, line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 3, Color.BLACK)
			draw_string(font, at, line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(1.0, 0.92, 0.9))

func _draw_use_emp(center: Vector2) -> void:
	# Electric-blue box with USE EMP and the charges held; pulses so it is noticed.
	var box := Rect2(center - intrusion_box_size * 0.5, intrusion_box_size)
	var pulse := 0.5 + 0.5 * sin(TAU * 2.5 * battle.battle_time)
	draw_rect(box, Color(0.0, 0.03, 0.08, 0.92))
	draw_rect(box.grow(-4.0), Color(emp_blue, 0.10 + 0.12 * pulse))
	draw_rect(box, emp_blue.lerp(Color.WHITE, 0.4 * pulse), false, 2.5)
	var font := ThemeDB.fallback_font
	var mid := box.get_center()
	var title := "USE EMP"
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string_outline(font, mid + Vector2(-w * 0.5, 2.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 3, Color.BLACK)
	draw_string(font, mid + Vector2(-w * 0.5, 2.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.88, 0.97, 1.0))
	var charges: int = battle.emp_charges
	var note := "%d CHARGE%s" % [charges, "" if charges == 1 else "S"]
	var nw := font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, mid + Vector2(-nw * 0.5, 21.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(emp_blue, 0.95))

func stealth_pulse() -> float:
	return 0.5 + 0.5 * cos(TAU * stealth_pulse_hz * battle.battle_time)

func center_weapon_points(rect: Rect2) -> PackedVector2Array:
	var scale := rect.size.x / REGION.size.x
	var points := PackedVector2Array()
	for point in CENTER_WEAPON_POLYGON:
		points.append(rect.position + (point - REGION.position) * scale)
	return points

func _draw_stealth_button(rect: Rect2, k: float) -> void:
	# Exact center-inset shape, not a rectangle over the ship or a flight pod.
	var pulse := stealth_pulse()
	var points := center_weapon_points(rect)
	draw_colored_polygon(points, Color.BLACK)
	draw_colored_polygon(points, Color(stealth_blue, 0.55 + 0.35 * pulse))
	var border := points.duplicate()
	border.append(points[0])
	draw_polyline(border, stealth_blue.lerp(Color.WHITE, 0.45 * pulse), 1.0, true)
	# Do not draw the weapon label through the pre-existing warning/EMP text.
	if (battle.hack_state() in ["hacking", "draining"] and not breach_alert_on_ship_fill) or (emp_on_ship and battle.can_use_emp()):
		return
	var font := ThemeDB.fallback_font
	var center := rect.position + (CENTER_WEAPON_LABEL - REGION.position) * k
	if int(battle.get("pulse_charges")) > 0:
		_draw_weapon_pills(rect, k, pulse)
		return
	var label := stealth_label
	var font_size := stealth_font_size
	while font_size > 10 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > stealth_box.size.x - 16.0:
		font_size -= 1
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := center + Vector2(-w * 0.5, font_size * 0.36)
	draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0.05, 0.15, 0.9))
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.6 + 0.4 * pulse))

## 1.1.0: two pill buttons inside the blue STEALTH WEAPON area.
func _draw_weapon_pills(rect: Rect2, k: float, pulse: float) -> void:
	var font := ThemeDB.fallback_font
	nukes_pill_rect = Rect2(rect.position + (PILL_NUKES.position - REGION.position) * k, PILL_NUKES.size * k)
	pulse_pill_rect = Rect2(rect.position + (PILL_PULSE.position - REGION.position) * k, PILL_PULSE.size * k)
	var mouse := get_local_mouse_position()
	var split := (nukes_pill_rect.end.x + pulse_pill_rect.position.x) * 0.5
	var over := Rect2(stealth_box).has_point(mouse) and pulse_hold_progress < 0.0
	var ice: Color = battle.get("pulse_color")
	var pills := [[nukes_pill_rect, "NUKES", Color(0.03, 0.10, 0.24), Color.WHITE, over and mouse.x < split],
		[pulse_pill_rect, "PULSE", ice, Color(0.02, 0.08, 0.16), over and mouse.x >= split]]
	for pill in pills:
		var box: Rect2 = pill[0]
		var style := StyleBoxFlat.new()
		style.bg_color = pill[2].lerp(Color.WHITE, 0.25) if pill[4] else pill[2]
		var holding_pulse: bool = pulse_hold_progress >= 0.0 and pill[1] == "PULSE"
		if holding_pulse:
			style.bg_color = Color(0.05, 0.22, 0.34)
		style.set_corner_radius_all(int(box.size.y * 0.5))
		style.set_border_width_all(2 if pill[4] else 1)
		style.border_color = Color.WHITE.lerp(ice, 0.3) if pill[4] else Color(1, 1, 1, 0.55 + 0.35 * pulse)
		style.anti_aliasing = true
		draw_style_box(style, box)
		if pulse_hold_progress >= 0.0:
			if pill[1] == "NUKES":
				# Holding the controller button: let go now for NUKES.
				var ring := StyleBoxFlat.new()
				ring.draw_center = false
				ring.set_corner_radius_all(int(box.size.y * 0.5))
				ring.set_border_width_all(2)
				ring.border_color = Color(1.0, 0.89, 0.55)
				ring.anti_aliasing = true
				draw_style_box(ring, box.grow(2.0))
			else:
				# PULSE fills from left to right; full = PULSE BOMB.
				var fill := StyleBoxFlat.new()
				fill.bg_color = ice.lerp(Color.WHITE, 0.35)
				fill.set_corner_radius_all(int(box.size.y * 0.5))
				fill.anti_aliasing = true
				var part := Rect2(box.position, Vector2(maxf(box.size.y, box.size.x * pulse_hold_progress), box.size.y))
				if pulse_hold_progress > 0.02:
					draw_style_box(fill, part)
		var text: String = pill[1]
		var font_size := stealth_font_size
		while font_size > 9 and (font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > box.size.x - 10.0 or font_size > box.size.y * 0.72):
			font_size -= 1
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at := box.get_center() + Vector2(-w * 0.5, font_size * 0.36)
		if holding_pulse:
			draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.02, 0.08, 0.16))
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
		else:
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, pill[3])

func _text(value: String, center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
