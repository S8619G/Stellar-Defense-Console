extends Control
##
## RADAR Dome - fully parameter-driven animation for live tuning.
##
## Every visual element is an @export variable so you can adjust it live in
## the editor Inspector OR at runtime with the on-screen sliders (see
## RadarConsole.gd). Change a value, watch it update instantly.
##

## 1.2.6: the scope outline (shared with the console frame and the contacts).
const ScopeShape = preload("res://scripts/ScopeShape.gd")

# ---------- SPHERE / BACKGROUND ----------
@export_group("Sphere")
@export var sphere_radius: float = 320.0         # Radius of the dome in pixels
@export var sphere_visible: bool = true          # Show the faint sphere outline
@export var sphere_color: Color = Color(0.2, 0.9, 1.0, 0.15)  # Faint cyan
@export var sphere_line_width: float = 1.0

# ---------- RINGS ----------
@export_group("Rings")
@export_range(0, 6) var ring_count: int = 2      # How many rings on screen
@export var ring_color: Color = Color(0.3, 1.0, 1.0, 1.0)     # Bright cyan
@export var ring_glow_color: Color = Color(0.6, 1.0, 1.0, 0.4) # Soft glow
@export var ring_thickness: float = 4.0
@export var ring_glow_thickness: float = 14.0
@export_range(0.5, 20.0) var ring_rotation_seconds: float = 4.0  # Full rotation period
@export var rings_hinged_at_top: bool = true     # true = share top pivot; false = free axes

# Per-ring base tilt (only used when rings_hinged_at_top = false)
@export var ring_a_axis_tilt_deg: float = 0.0
@export var ring_b_axis_tilt_deg: float = 90.0

# ---------- RING HINGE (1.2.4) ----------
@export_group("Ring Hinge")
## Off = today's look (horizontal ring hinged at the left and right sides).
## On = horizontal ring lies around the dome's middle and is hinged at the front and back.
@export var ring_horizontal_hinge_front_back: bool = false
## How far above the dome the viewer sits; sets how open the flat ring looks.
@export_range(0.0, 60.0) var ring_view_elevation_deg: float = 30.0
## Turn direction of the front-and-back ring: 1 or -1.
@export_range(-1, 1, 2) var ring_front_back_direction: int = -1

# ---------- RING TRAIL (1.2.4) ----------
@export_group("Ring Trail")
## Off = today's look (one thin line per ring). On = a soft trail of faint glow copies.
@export var ring_trail_enabled: bool = false
## How far back in time the trail reaches.
@export_range(0.05, 1.0) var ring_trail_seconds: float = 0.20
## How many faint copies make up the trail (more = smoother, same total light).
@export_range(1, 32) var ring_trail_copies: int = 24
## Trail light. Keep it low: the rings are quiet background.
@export_range(0.0, 1.0) var ring_trail_strength: float = 0.30
## With the trail on, the ring's own glow is scaled by this so overall light stays the same.
@export_range(0.0, 1.0) var ring_trail_glow_scale: float = 0.50

# ---------- THREE RINGS (1.2.9) ----------
@export_group("Three Rings")
## Off = 1.2.8 rings. On = three rings measured from the reference clip, each on
## its own hinge, sharing one cycle: vertical (hinged top/bottom), horizontal
## (hinged front/back) and a third horizontal ring (hinged left/right).
@export var three_rings_enabled: bool = false
## One cycle = each ring turns half way round (the clip: 2.0 s, the sweep pulse).
@export_range(0.5, 8.0) var three_ring_cycle_seconds: float = 2.0
## Moves the whole cycle in time (seconds), to line it up with the sweep pulse.
@export_range(-2.0, 2.0) var three_ring_time_offset: float = 0.0
## Easing: 0 = steady turn; 1 = stops briefly at the slow point. Clip: 0.69.
@export_range(0.0, 1.0) var three_ring_horizontal_ease: float = 0.69
## Easing for the vertical ring (slow point is face-on). Clip: 0.87.
@export_range(0.0, 1.0) var three_ring_vertical_ease: float = 0.87
## Vertical ring is half a cycle out of step with the horizontal rings (clip: 0.5).
@export_range(0.0, 1.0) var three_ring_vertical_phase: float = 0.5
## On = the vertical ring is pinned at the top and bottom of the dome outline and
## turns straight up and down (no side-to-side wobble). Off = drawn with the
## from-above view like the other rings (it tilts as it turns).
@export var three_ring_vertical_upright: bool = true
## Vertical ring centre above the dome centre (fraction of radius). 0 = centred.
@export_range(-0.3, 0.3) var three_ring_vertical_lift: float = 0.0
## Vertical ring size (fraction of radius). 1 = the dome outline.
@export_range(0.8, 1.1) var three_ring_vertical_scale: float = 1.0
## Show each ring.
@export var three_ring_show_vertical: bool = true
@export var three_ring_show_front_back: bool = true
@export var three_ring_show_left_right: bool = true
## Brightness of each ring (1 = Ring Color as set). Keep the rings quiet.
@export_range(0.0, 1.0) var three_ring_vertical_strength: float = 0.75
@export_range(0.0, 1.0) var three_ring_front_back_strength: float = 0.75
@export_range(0.0, 1.0) var three_ring_left_right_strength: float = 0.75
## Afterglow length for the two horizontal rings (seconds). The vertical ring uses
## Ring Trail Seconds. Total glow stays the same; a longer trail spreads it out.
@export_range(0.05, 1.5) var three_ring_horizontal_trail_seconds: float = 0.40

# ---------- BASE PLANE RIPPLES ----------
@export_group("Ripples")
@export var ripples_visible: bool = true
@export_range(0.5, 12.0) var ripple_period_seconds: float = 2.0
@export_range(1, 6) var ripple_count: int = 3
@export var ripple_color: Color = Color(0.3, 1.0, 1.0, 0.6)
@export var ripple_max_radius: float = 340.0
@export var ripple_thickness: float = 2.0
## On = the pulse rings lie on the same plane as the flat horizontal ring
## (centred on the dome, tilted to Ring View Elevation Deg). Off = today's look
## (0.25 x radius lower, flattened to 0.30). Set Ripple Max Radius to the sphere
## radius (320) so the outer pulse stops at the ring's edge.
@export var ripples_match_ring_plane: bool = false

# ---------- SCANLINES ----------
@export_group("Scanlines")
@export var scanlines_visible: bool = true
@export var scanline_color: Color = Color(0.0, 0.0, 0.0, 0.25)
@export var scanline_spacing: float = 4.0
@export_range(0.0, 200.0) var scanline_scroll_speed: float = 12.0
## 1.2.6: draw the rolling scanlines only inside the scope outline (the arc and the V),
## so they never roll over the console panels and tabs that reach into the dome's
## square. Off = 1.2.5 (scanlines over the whole dome square).
@export var scanlines_inside_scope: bool = false

# ---------- INTERNAL STATE ----------
var _time: float = 0.0
var _sweep_clock: AudioStreamPlayer

func _ready() -> void:
	_sweep_clock = get_parent().get_parent().get_node_or_null("SweepLoop") as AudioStreamPlayer

func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_sweep_clock) and _sweep_clock.playing:
		# The loop contains both cues and the quiet second. Follow the audible
		# clock, not a second free-running timer that could drift over a long game.
		_time = maxf(0.0, _sweep_clock.get_playback_position()
			+ AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	queue_redraw()  # Trigger _draw() every frame

# ------------------------------------------------------------------
# DRAW
# ------------------------------------------------------------------
func _draw() -> void:
	var center: Vector2 = size * 0.5
	_draw_ripples(center)
	_draw_sphere_ghost(center)
	_draw_rings(center)
	_draw_scanlines()

# ---- SPHERE GHOST ----
func _draw_sphere_ghost(center: Vector2) -> void:
	if not sphere_visible:
		return
	# Just a faint circle to hint at the sphere volume.
	_draw_ellipse(center, sphere_radius, sphere_radius, sphere_color, sphere_line_width, 64)

# ---- RIPPLES on the base plane ----
func _draw_ripples(center: Vector2) -> void:
	if not ripples_visible:
		return
	# Ripples emit from center outward on the ground plane (drawn as flattened ellipses).
	var period: float = ripple_period_seconds
	for i in range(ripple_count):
		var phase: float = fposmod(_time + i * (period / float(ripple_count)), period) / period
		var r: float = phase * ripple_max_radius
		var alpha: float = (1.0 - phase) * ripple_color.a
		var col: Color = Color(ripple_color.r, ripple_color.g, ripple_color.b, alpha)
		# Flatten to look like a horizontal ripple on a ground plane.
		_draw_ellipse(ripple_center(center), r, r * ripple_flatten(), col, ripple_thickness, 64)

## Where the pulse rings are centred: on the dome (ring plane) or 0.25 x radius lower (1.2.3).
func ripple_center(center: Vector2) -> Vector2:
	return center if ripples_match_ring_plane else center + Vector2(0, sphere_radius * 0.25)

## Height-to-width ratio of the pulse rings: sin(Ring View Elevation Deg) on the ring plane, else 0.30.
func ripple_flatten() -> float:
	return sin(deg_to_rad(ring_view_elevation_deg)) if ripples_match_ring_plane else 0.30

# ---- RINGS ----
func _draw_rings(center: Vector2) -> void:
	if ring_count <= 0:
		return
	_draw_stellar_rings(center)
	return

## Same front/back hinge, opposite half-turns. 1.0.3: the second (right) ring
## starts when the first (left) ring is 56% through its sweep (0.672 s), so the
## two rings visibly cross; then a 1.378 s pause. The second sweep tone in
## radar_sweep_loop.wav starts at the same moment. (1.0.2 and earlier: 1.05 s.)
const STELLAR_CYCLE := 3.25
const STELLAR_SWEEP := 1.20
const STELLAR_SECOND_START_SHARE := 0.56
const STELLAR_SECOND_START := STELLAR_SWEEP * STELLAR_SECOND_START_SHARE

static func stellar_angles(at_time: float) -> Vector2:
	var phase := fposmod(at_time, STELLAR_CYCLE)
	return Vector2(-PI * clampf(phase / STELLAR_SWEEP, 0.0, 1.0),
		PI * clampf((phase - STELLAR_SECOND_START) / STELLAR_SWEEP, 0.0, 1.0))

func _draw_stellar_rings(center: Vector2) -> void:
	var phase := fposmod(_time, STELLAR_CYCLE)
	if ring_trail_enabled:
		for k in range(24, 0, -1):
			var f := float(k) / 24.0
			var ghost_angles := stellar_angles(maxf(0.0, phase - 0.30 * f))
			var ghost := ring_color
			ghost.a *= 0.75 * 2.6 * (1.0 - f) / 24.0
			for angle in [ghost_angles.x, ghost_angles.y]:
				draw_polyline(three_ring_points(center, 1, angle), ghost, 2.7, true)
	var angles := stellar_angles(phase)
	var core := ring_color
	core.a *= 0.75
	for angle in [angles.x, angles.y]:
		draw_polyline(three_ring_points(center, 1, angle), core, ring_thickness, true)

## 0..1 eased progress: u - k * sin(2 pi u) / (2 pi).
static func ring_ease(u: float, k: float) -> float:
	return u - k * sin(TAU * u) / TAU

## The three rings' angles (radians) at a time: [vertical, front_back, left_right].
func three_ring_angles(at_time: float) -> Array:
	var u := fposmod((at_time + three_ring_time_offset) / maxf(0.1, three_ring_cycle_seconds), 1.0)
	var h := -PI * ring_ease(u, three_ring_horizontal_ease)
	var uv := fposmod(u + three_ring_vertical_phase, 1.0)
	var v := PI * 0.5 + PI * ring_ease(uv, three_ring_vertical_ease)
	return [v, h, h]

## Screen points of one ring: kind 0 vertical, 1 front/back, 2 left/right.
func three_ring_points(center: Vector2, kind: int, angle: float, segments: int = 96) -> PackedVector2Array:
	var e: float = deg_to_rad(ring_view_elevation_deg)
	var ca := cos(angle)
	var sa := sin(angle)
	var r := sphere_radius
	var c0 := center
	if kind == 0:
		r *= three_ring_vertical_scale
		c0 += Vector2(0.0, -three_ring_vertical_lift * sphere_radius)
	var pts := PackedVector2Array()
	for k in range(segments + 1):
		var t: float = float(k) / float(segments) * TAU
		var c := cos(t)
		var s := sin(t)
		var p: Vector3
		match kind:
			0: p = Vector3(s * sa, c, s * ca)
			1: p = Vector3(c * ca, c * sa, s)
			_: p = Vector3(c, -s * sa, s * ca)
		if kind == 0 and three_ring_vertical_upright:
			pts.append(c0 + Vector2(p.x, -p.y) * r)
		else:
			pts.append(c0 + Vector2(p.x, -(p.y * cos(e) - p.z * sin(e))) * r)
	return pts

func _draw_three_rings(center: Vector2, at_time: float, fade: float, only: Array = [true, true, true]) -> void:
	var ang := three_ring_angles(at_time)
	var shows := [three_ring_show_vertical, three_ring_show_front_back, three_ring_show_left_right]
	var strengths := [three_ring_vertical_strength, three_ring_front_back_strength, three_ring_left_right_strength]
	for kind in range(3):
		if not shows[kind] or not only[kind]:
			continue
		var pts := three_ring_points(center, kind, ang[kind])
		var g := ring_glow_color
		g.a *= strengths[kind]
		if fade >= 0.0:
			g.a *= fade
			draw_polyline(pts, g, ring_glow_thickness, true)
			continue
		if ring_trail_enabled:
			g.a *= ring_trail_glow_scale
		var core := ring_color
		core.a *= strengths[kind]
		draw_polyline(pts, g, ring_glow_thickness, true)
		draw_polyline(pts, core, ring_thickness, true)

func _draw_ring_pair(center: Vector2, at_time: float, fade: float) -> void:
	# spin_angle is the shared rotation phase driven by ring_rotation_seconds.
	var spin_angle: float = fposmod(at_time / ring_rotation_seconds, 1.0) * TAU

	for i in range(ring_count):
		var base_tilt_deg: float
		if rings_hinged_at_top:
			# HINGED MODE:
			# Both rings share the TOP pivot and stay locked 90 deg apart from each other.
			# We rotate the whole rigid pair together around the vertical axis.
			base_tilt_deg = float(i) * (180.0 / max(ring_count, 1))
		else:
			# FREE MODE: each ring uses its independent tilt.
			base_tilt_deg = ring_a_axis_tilt_deg if i == 0 else ring_b_axis_tilt_deg

		# Live spin adds to the base tilt. In hinged mode, both rings share spin_angle
		# so they rotate together as a rigid frame.
		var tilt_rad: float = deg_to_rad(base_tilt_deg) + spin_angle

		# We draw the ring as an ellipse whose horizontal radius = sphere_radius
		# and whose vertical radius = sphere_radius * cos(tilt) — this gives the
		# illusion of a 3D circle rotating in and out of the screen plane.
		var rx: float = sphere_radius
		var ry: float = sphere_radius * abs(cos(tilt_rad))

		# Rotate the ellipse itself in the 2D plane. In hinged mode, both rings
		# also share this in-plane rotation so their intersection stays anchored.
		var plane_rot: float
		if rings_hinged_at_top:
			# Rings meet at the top of the sphere (a fixed on-screen point above center).
			# We rotate each ring's in-plane axis 90 deg apart from the next.
			plane_rot = deg_to_rad(base_tilt_deg)
		else:
			plane_rot = deg_to_rad(base_tilt_deg)

		if i == 0 and rings_hinged_at_top and ring_horizontal_hinge_front_back:
			_draw_front_back_ring(center, spin_angle, fade)
			continue
		# Trail copies draw the soft glow only, at the given fade.
		if fade >= 0.0:
			var g := ring_glow_color
			g.a *= fade
			_draw_rotated_ellipse(center, rx, ry, plane_rot, g, ring_glow_thickness, 96)
			continue
		# Glow first (thick, soft) then the thin core line.
		var main_glow := ring_glow_color
		if ring_trail_enabled:
			main_glow.a *= ring_trail_glow_scale
		_draw_rotated_ellipse(center, rx, ry, plane_rot, main_glow,
							  ring_glow_thickness, 96)
		_draw_rotated_ellipse(center, rx, ry, plane_rot, ring_color,
							  ring_thickness, 96)

# Horizontal ring hinged at the front and back of the dome: it starts flat
# around the middle and turns about the front-to-back axis, seen from Ring View
# Elevation Deg above. Trail copies (fade >= 0) draw the soft glow only.
func _draw_front_back_ring(center: Vector2, angle: float, fade: float) -> void:
	var pts := front_back_ring_points(center, angle)
	if fade >= 0.0:
		var g := ring_glow_color
		g.a *= fade
		draw_polyline(pts, g, ring_glow_thickness, true)
		return
	var main_glow := ring_glow_color
	if ring_trail_enabled:
		main_glow.a *= ring_trail_glow_scale
	draw_polyline(pts, main_glow, ring_glow_thickness, true)
	draw_polyline(pts, ring_color, ring_thickness, true)

## Screen points of the front-and-back hinged ring at a spin angle: ring point
## (cos t * cos th, cos t * sin th, sin t) with th = angle * Ring Front Back Direction,
## seen from Ring View Elevation Deg above.
func front_back_ring_points(center: Vector2, angle: float, segments: int = 96) -> PackedVector2Array:
	var e: float = deg_to_rad(ring_view_elevation_deg)
	var th: float = angle * float(ring_front_back_direction)
	var ca: float = cos(th)
	var sa: float = sin(th)
	var pts := PackedVector2Array()
	for k in range(segments + 1):
		var t: float = float(k) / float(segments) * TAU
		var x: float = cos(t) * ca
		var y: float = cos(t) * sa
		var z: float = sin(t)
		pts.append(center + Vector2(x, -(y * cos(e) - z * sin(e))) * sphere_radius)
	return pts

# ---- SCANLINES ----
func _draw_scanlines() -> void:
	if not scanlines_visible:
		return
	var offset: float = fmod(_time * scanline_scroll_speed, scanline_spacing)
	var y: float = -scanline_spacing + offset
	var center: Vector2 = size * 0.5
	while y < size.y:
		if scanlines_inside_scope:
			var half := scope_half_width_at(y, center)
			if half > 0.0:
				draw_line(Vector2(center.x - half, y), Vector2(center.x + half, y), scanline_color, 1.0)
		else:
			draw_line(Vector2(0, y), Vector2(size.x, y), scanline_color, 1.0)
		y += scanline_spacing

## 1.2.6: half width in pixels of the scope outline at dome-local height y (0 = outside).
func scope_half_width_at(y: float, center: Vector2) -> float:
	var u := (y - center.y) / maxf(1.0, sphere_radius)
	var s := ScopeShape.v_start()
	if u <= s.y:
		if absf(u) >= ScopeShape.ARC:
			return 0.0
		return sqrt(ScopeShape.ARC * ScopeShape.ARC - u * u) * sphere_radius
	if u > ScopeShape.V_DEPTH:
		return 0.0
	return ScopeShape.v_half_width_at(u) * sphere_radius

# ------------------------------------------------------------------
# GEOMETRY HELPERS
# ------------------------------------------------------------------
func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color,
				   thickness: float, segments: int) -> void:
	_draw_rotated_ellipse(center, rx, ry, 0.0, color, thickness, segments)

func _draw_rotated_ellipse(center: Vector2, rx: float, ry: float, rotation_rad: float,
						   color: Color, thickness: float, segments: int) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var cos_r: float = cos(rotation_rad)
	var sin_r: float = sin(rotation_rad)
	for i in range(segments + 1):
		var t: float = float(i) / float(segments) * TAU
		var x: float = rx * cos(t)
		var y: float = ry * sin(t)
		# Rotate the (x, y) point by rotation_rad.
		var xr: float = x * cos_r - y * sin_r
		var yr: float = x * sin_r + y * cos_r
		pts.append(center + Vector2(xr, yr))
	draw_polyline(pts, color, thickness, true)
