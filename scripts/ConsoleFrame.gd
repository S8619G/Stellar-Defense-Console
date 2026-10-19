extends Control
## Quiet structural chrome. The dome and rings remain separate and unchanged.
const EDGE := Color("#77324f")
const MUTED := Color("#b9a8b2")
const TEXT := Color("#ede0e8")
## Shared with the button borders so the chrome reads as one set.
const FRAME_WIDTH := 2.0
## 1.05: active bonus lines under the SCORE box (small, steady, accent color).
const BONUS_COLOR := Color(1.0, 0.6, 0.78, 0.85)
const BONUS_FONT_SIZE := 16
const BONUS_TOP := 156.0
const BONUS_LINE_STEP := 20.0
const ScopeShape = preload("res://scripts/ScopeShape.gd")
@onready var battle: Control = $"../CenterContainer/Dome/Contacts"
@onready var dome: Control = $"../CenterContainer/Dome"
@onready var ship_status: Control = $"../ShipStatus"

# ---------- 1.2.4 SCOPE FRAME (decoration only) ----------
@export_group("Scope Frame")
## The show-style scope outline: an arc over the top and a V down to the button bar,
## with inward range ticks. Off = the 1.2.3 plain frame (with its line under the dome).
@export var scope_frame_visible: bool = true
## Magenta corner panels beside the V and the three tabs in each top corner.
@export var corner_panels_visible: bool = true
@export var scope_border_color: Color = Color8(150, 60, 110)
@export var scope_tick_color: Color = Color8(90, 150, 175)
@export var scope_tick_major_color: Color = Color8(140, 200, 225)
@export var panel_color: Color = Color8(214, 70, 140)
@export var panel_dim_color: Color = Color8(120, 40, 80)
@export var panel_fill_color: Color = Color8(22, 6, 14)

# ---------- 1.2.5 CONSOLE LAYOUT 2 ----------
@export_group("Console Layout 2")
## 1.2.5 console layout from the approved mockup: taller corner panels with ready lights,
## the alert box in the left panel, the NAV DATA box in the right panel, a boxed status
## message and wider top tabs. Off = the 1.2.4 layout.
@export var console_layout_v2: bool = false
## The left panel's HULL gauge turns red at this hull percent or less.
@export_range(5.0, 60.0) var hull_low_percent: float = 30.0
## 0.1.2: wider vertical gauge; reference-pixel width scales with the console.
@export_range(12.0, 24.0) var hull_gauge_width: float = 16.0
## TRACKS shows the real contact count, and the right scale shows the Defense Shield charge.
@export var live_readouts: bool = true
## Made-up navigation data for the area of space; new at battle start and after each JUMP jump.
@export var nav_data_panel: bool = true
var nav_lines: Array[String] = []
var nav_jumps := 0
## Fixed seed for tests and captures (0 = random each time).
var nav_seed := 0
var _nav_last_time := 0.0
var _nav_connected := false

# ---------- 1.2.4 PANEL ANIMATION ----------
@export_group("Panel Animation")
## A few bar readouts in the corner panels slowly step, and one slowly fades.
## Never faster or brighter than the static panel. Off = still panels.
@export var panel_animation_enabled: bool = true
## Seconds between steps of a bar readout (slow).
@export_range(1.0, 20.0) var panel_step_seconds: float = 3.0
## How many segments a stepping readout moves either way.
@export_range(0, 2) var panel_step_amount: int = 1
## How far the fading segment dims (0 = no fade, 0.5 = to half).
@export_range(0.0, 0.5) var panel_flicker_amount: float = 0.3

## Mockup layout, in 1600x900 pixels around the dome centre (800, 399), scaled by
## 1.2 to the 1920x1080 console and by the dome's sphere radius (320 = 1.0).
const MOCK_CENTER := Vector2(800.0, 399.0)
const RIGHT_TABS: Array[String] = ["TRK 02", "SYS NOM", "RNG 4K", "IFF", "BRG 117", "NAV"]
const LEFT_TABS: Array[String] = ["PWR 98", "AUX", "CIC 3", "DC ON", "COMM", "LNK"]
const TOP_LEFT_TABS: Array[String] = ["RADAR", "PLOT", "SCALE 1:4"]
const TOP_RIGHT_TABS: Array[String] = ["TRACKS 12", "FILTER", "HOLD"]
## Right-panel bar readouts that step when animated (row numbers), and the one that fades.
const STEPPING_ROWS: Array[int] = [0, 2, 4]
const FADING_ROW := 1
var panel_time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	panel_time += delta
	if nav_data_panel:
		if not _nav_connected and battle != null:
			battle.jump_completed.connect(func() -> void:
				nav_jumps += 1
				new_nav_location())
			_nav_connected = true
		# A new battle (clock back to zero) is a new place too.
		if battle != null and (nav_lines.is_empty() or battle.battle_time < _nav_last_time):
			nav_jumps = 0
			new_nav_location()
		if battle != null:
			_nav_last_time = battle.battle_time
	# 1.2.5: the bottom buttons sit centred between the bar line and the frame bottom.
	var buttons := get_parent().get_node_or_null("BottomButtons") as Control
	var want_top := -102.0 if console_layout_v2 else -100.0
	if buttons != null and buttons.offset_top != want_top:
		buttons.offset_top = want_top
		buttons.offset_bottom = want_top + 64.0
	queue_redraw()

func _draw() -> void:
	var right := size.x - 48.0
	var bottom := size.y - 28.0
	var outline := PackedVector2Array([Vector2(66,32), Vector2(right-18,32),
		Vector2(right,50), Vector2(right,bottom-18), Vector2(right-18,bottom),
		Vector2(66,bottom), Vector2(48,bottom-18), Vector2(48,50), Vector2(66,32)])
	draw_polyline(outline, EDGE, FRAME_WIDTH, true)
	draw_line(Vector2(48,124), Vector2(right,124), EDGE, 1.0, true)
	draw_line(Vector2(48,size.y-112), Vector2(right,size.y-112), EDGE, 1.0, true)
	var center := size.x * 0.5
	if scope_frame_visible:
		# 1.2.4: the plain line under the dome is removed; its top and sides stay.
		var r := Rect2(center-492,156,984,644)
		if not console_layout_v2:
			draw_polyline(PackedVector2Array([Vector2(r.position.x, r.end.y), r.position,
			Vector2(r.end.x, r.position.y), r.end]), Color("#482138"), 1.0)
		_draw_scope_frame()
		if console_layout_v2:
			_v2_status_box()
	else:
		draw_rect(Rect2(center-492,156,984,644), Color("#482138"), false, 1.0)
	# Header dividers organize title, four counters and score.
	for x in [420.0, size.x-460.0]:
		draw_line(Vector2(x,48), Vector2(x,108), EDGE, 1.0, true)
	var left := Vector2(82,208)
	_text("DEFENSE SHIELD", left, 19, MUTED)
	var state := "READY"
	var charge: float = battle.battery_percent()
	if battle.prox_active:
		state = "FIRING"
	elif charge <= 0.0:
		state = "EMPTY  RECHARGING"
	elif charge < 100.0:
		state = "RECHARGING" if battle.can_fire_battery() else "RECHARGING  WAIT %d%%" % int(battle.battery_restart_percent)
	_text("%d%% CHARGE" % int(charge), left+Vector2(0,46), 30, TEXT)
	_text(state, left+Vector2(0,80), 19, Color("#ffe28b"))
	draw_rect(Rect2(left+Vector2(0,100),Vector2(280,7)), Color("#352832"))
	var fraction := clampf(battle.prox_burst_remaining / maxf(0.1,battle.prox_burst_seconds),0.0,1.0)
	draw_rect(Rect2(left+Vector2(0,100),Vector2(280*fraction,7)), Color("#b4a267"))
	_text("RAPID REPAIR", left+Vector2(0,198), 19, MUTED)
	var repair_state := "%d CHARGE%s" % [battle.repair_charges, "" if battle.repair_charges == 1 else "S"]
	if battle.rapid_repair_remaining > 0.0:
		repair_state = "REPAIRING  %.1fs" % battle.rapid_repair_remaining
	elif battle.repair_charges <= 0:
		repair_state = "NO CHARGES"
	_text(repair_state, left+Vector2(0,240), 26, TEXT)
	_text("+%d%% HULL PER CHARGE" % int(battle.rapid_repair_percent), left+Vector2(0,274), 18, MUTED)
	var next_bonus: int = battle.points_to_next_bonus()
	_text("NEXT BONUS IN  %d PTS" % next_bonus, left+Vector2(0,306), 18, MUTED)
	var side := Vector2(size.x-372,208)
	var multiplier: float = battle.score_multiplier()
	_text("TARGET VALUES" if is_equal_approx(multiplier, 1.0) else "TARGET VALUES  x%.2f" % multiplier, side, 19, MUTED)
	_text("ATTACK DRONE", side+Vector2(0,46), 20, TEXT)
	_text(str(battle.points_for(battle.fighter_points)), side+Vector2(220,46), 20, TEXT)
	_text("BREACHER", side+Vector2(0,86), 20, TEXT)
	_text(str(battle.points_for(battle.breacher_points)), side+Vector2(220,86), 20, TEXT)
	_text("NUCLEAR", side+Vector2(0,126), 20, TEXT)
	_text(str(battle.points_for(battle.nuclear_points)), side+Vector2(220,126), 20, TEXT)
	_text("ENEMY CARRIER", side+Vector2(0,166), 20, TEXT)
	_text(str(battle.points_for(battle.carrier_points)), side+Vector2(220,166), 20, TEXT)
	_text("SIEGE SHIP", side+Vector2(0,206), 20, TEXT)
	_text(str(battle.points_for(battle.siege_points)), side+Vector2(220,206), 20, TEXT)
	# 1.05: points for each missile the Defense Shield destroys.
	_text("MISSILE", side+Vector2(0,246), 20, TEXT)
	_text(str(battle.points_for(battle.battery_kill_points)), side+Vector2(220,246), 20, TEXT)
	var low := 40.0  # everything below the new MISSILE row moves down one row
	draw_line(side+Vector2(0,234+low),side+Vector2(280,234+low),EDGE,1.0)
	_text("JUMP COST",side+Vector2(0,274+low),19,MUTED)
	_text("-%d POINTS" % battle.jump_score_cost,side+Vector2(0,316+low),26,TEXT)
	draw_line(side+Vector2(0,344+low),side+Vector2(280,344+low),EDGE,1.0)
	_text("THREAT WAVE  |  %s" % ["EASY", "NORMAL", "HARD"][clampi(battle.active_difficulty, 0, 2)],side+Vector2(0,384+low),19,MUTED)
	_text("WAVE %d" % battle.wave,side+Vector2(0,428+low),30,TEXT)
	if battle.wave_system_active():
		# 1.2.0: phase and set, then wave name, trait and set multiplier.
		# 1.2.7: the score multiplier has its own line; every line is fitted to the panel width.
		_text_fit(battle.wave_phase_line(),side+Vector2(0,462+low),18,MUTED)
		_text_fit(battle.wave_detail_line(),side+Vector2(0,486+low),16,Color("#ffe28b"))
		_text_fit(battle.wave_score_line(),side+Vector2(0,508+low),16,Color("#ffe28b"))
	elif battle.waves_enabled:
		var left_seconds := ceili(battle.seconds_to_next_wave())
		_text("NEXT WAVE IN  %d:%02d" % [int(left_seconds / 60.0), left_seconds % 60],side+Vector2(0,462+low),18,MUTED)
	var res: Dictionary = battle.siege_ship()
	if not res.is_empty():
		var hostile := Color(1.0, 0.36, 0.42)
		# 1.2.7: 22 px lower, under the new score multiplier line.
		_text("SIEGE SHIP",side+Vector2(0,538+low),19,hostile)
		_text("STRENGTH  %d%%" % ceili(100.0 * res.hits_remaining / res.max_hits),side+Vector2(0,572+low),20,TEXT)
		var barrage := "FIRING BARRAGE" if res.barrage_left > 0 else "NEXT BARRAGE  %ds" % ceili(res.barrage_timer)
		_text(barrage,side+Vector2(0,602+low),18,Color("#ffe28b"))
	_draw_bonus_lines()
	if get_parent().development_build:
		_text("RADAR  %d dB" % int(get_parent().sweep_volume_db), Vector2(82,size.y-132),18,MUTED)
		_text("F1  TUNING PANEL",Vector2(size.x-290,size.y-132),18,MUTED)
	_draw_hack_box()

## 1.05: steady bonus lines just below the SCORE box, right-aligned with it,
## above TARGET VALUES. No flashing, so the contacts keep the attention.
func bonus_line_positions() -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var names: Array[String] = battle.active_bonus_names()
	for index in range(names.size()):
		var width := ThemeDB.fallback_font.get_string_size(names[index], HORIZONTAL_ALIGNMENT_LEFT, -1, BONUS_FONT_SIZE).x
		spots.append(Vector2(size.x - 82.0 - width, BONUS_TOP + index * BONUS_LINE_STEP))
	return spots

func _draw_bonus_lines() -> void:
	var names: Array[String] = battle.active_bonus_names()
	var spots := bonus_line_positions()
	for index in range(names.size()):
		_text(names[index], spots[index], BONUS_FONT_SIZE, BONUS_COLOR)

func _draw_hack_box() -> void:
	var alert_label: Label = get_parent().get_node("HackAlert")
	if console_layout_v2 and scope_frame_visible and corner_panels_visible:
		alert_label.self_modulate = Color(1, 1, 1, 0)
		_v2_alert_box()
		return
	alert_label.self_modulate = Color(1, 1, 1, 1)
	# Chamfered alert box around the hacking warning; flashes during a hack.
	# 1.1.1: also shown (steady amber) while a Breacher approaches.
	var state: String = battle.hack_state()
	if state == "":
		return
	var alert: Label = get_parent().get_node("HackAlert")
	# 1.2.0: fixed size, so the box no longer changes between messages.
	var text_height: float = maxf(get_parent().hack_text_height(), alert.size.y)
	var r := Rect2(alert.position - Vector2(10, 8), Vector2(alert.size.x + 20, text_height + 16))
	var blink: bool = int(battle.battle_time * 4.0) % 2 == 0
	var color := Color(1.0, 0.2, 0.26) if blink or state == "draining" else Color(1.0, 0.78, 0.25)
	if state == "approach":
		color = Color(1.0, 0.78, 0.25)
	var c := 10.0
	var box := PackedVector2Array([r.position + Vector2(c,0), Vector2(r.end.x-c, r.position.y),
		Vector2(r.end.x, r.position.y+c), r.end - Vector2(0,c), r.end - Vector2(c,0),
		Vector2(r.position.x+c, r.end.y), Vector2(r.position.x, r.end.y-c), r.position + Vector2(0,c),
		r.position + Vector2(c,0)])
	if scope_frame_visible and corner_panels_visible:
		# 1.2.4: the box sits over the left corner panel; back it with the console
		# background so the warning reads exactly as before and the panel stays behind.
		draw_colored_polygon(box, get_parent().get_node("Background").color)
	draw_colored_polygon(box, Color(color, 0.08))
	draw_polyline(box, color, FRAME_WIDTH, true)

# ---------- 1.2.4 SCOPE FRAME ----------
## Scale from mockup pixels (1600x900) to console pixels for the current dome.
func _frame_scale() -> float:
	return 1.2 * dome.sphere_radius / 320.0

## The dome is centred in its CenterContainer, whose rectangle is known at once
## (the dome's own position can lag a frame behind a window resize).
func _dome_center() -> Vector2:
	var holder := dome.get_parent() as Control
	return holder.global_position + holder.size * 0.5 - global_position

## Mockup point (1600x900 pixels) to console pixels, following the dome.
func _mock(x: float, y: float) -> Vector2:
	return _dome_center() + (Vector2(x, y) - MOCK_CENTER) * _frame_scale()

func _bar_line_y() -> float:
	return size.y - 112.0

## The outline corners: V starts (left, right) and where the V meets the button bar line.
func scope_outline() -> Dictionary:
	var c := _dome_center()
	var radius: float = dome.sphere_radius
	var start := ScopeShape.v_start() * radius
	var bar := _bar_line_y()
	return {"center": c, "arc_radius": ScopeShape.ARC * radius,
		"left_start": c + Vector2(-start.x, start.y), "right_start": c + Vector2(start.x, start.y),
		"left_bottom": Vector2(c.x - ScopeShape.V_HALF_WIDTH * radius, bar),
		"right_bottom": Vector2(c.x + ScopeShape.V_HALF_WIDTH * radius, bar)}

func _edge_x(a: Vector2, b: Vector2, y: float) -> float:
	return a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)

## True where the arc is hidden behind the status line at the top.
func _in_status_gap(p: Vector2) -> bool:
	var c := _dome_center()
	if console_layout_v2:
		return _v2_status_rect().grow(3.0 * _frame_scale()).has_point(p)
	return absf(p.x - c.x) < 128.0 * _frame_scale() and p.y < _mock(0.0, 140.0).y

func _draw_scope_frame() -> void:
	var o := scope_outline()
	var k := _frame_scale()
	if corner_panels_visible:
		_draw_corner_panels(o, k)
	# Border: arc from the left V start over the top to the right V start, then the V edges.
	var c: Vector2 = o.center
	var ra: float = o.arc_radius
	var t_left := deg_to_rad(180.0 - ScopeShape.V_START_DEG)
	var t_right := deg_to_rad(360.0 + ScopeShape.V_START_DEG)
	var seg := PackedVector2Array()
	var n := 240
	for i in range(n + 1):
		var t := t_left + (t_right - t_left) * float(i) / float(n)
		var p := c + Vector2(cos(t), sin(t)) * ra
		if _in_status_gap(p):
			if seg.size() > 1:
				draw_polyline(seg, scope_border_color, 2.0 * k, true)
			seg = PackedVector2Array()
		else:
			seg.append(p)
	if seg.size() > 1:
		draw_polyline(seg, scope_border_color, 2.0 * k, true)
	draw_line(o.left_start, o.left_bottom, scope_border_color, 2.0 * k, true)
	draw_line(o.right_start, o.right_bottom, scope_border_color, 2.0 * k, true)
	# Inward range ticks: every 5 degrees on the arc, longer every 30.
	var deg := int(ceil((180.0 - ScopeShape.V_START_DEG) / 5.0) * 5.0)
	while deg <= 360 + int(ScopeShape.V_START_DEG):
		var r := deg_to_rad(float(deg))
		var dir := Vector2(cos(r), sin(r))
		var length := (9.0 if deg % 30 == 0 else 5.0) * k
		if not _in_status_gap(c + dir * ra):
			draw_line(c + dir * ra, c + dir * (ra - length),
				scope_tick_major_color if deg % 30 == 0 else scope_tick_color, 1.0 * k)
		deg += 5
	# Nine ticks along each V edge (ten equal steps), the middle one longer.
	for edge in [[o.left_start, o.left_bottom], [o.right_start, o.right_bottom]]:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		var along := b - a
		var normal := Vector2(-along.y, along.x).normalized()
		if (c.x - a.x) * normal.x < 0.0:
			normal = -normal
		for step in range(1, 10):
			var p := a + along * (float(step) / 10.0)
			draw_line(p, p + normal * (9.0 if step == 5 else 5.0) * k, scope_tick_color, 1.0 * k)

func _draw_corner_panels(o: Dictionary, k: float) -> void:
	if console_layout_v2:
		_v2_panels(o, k)
		return
	var gap := 10.0 * k
	var top := _mock(0.0, 470.0).y
	var bottom := _bar_line_y() - 1.0 * k
	var lx := _mock(345.0, 0.0).x
	var rx := _mock(1255.0, 0.0).x
	var left := PackedVector2Array([Vector2(lx, top + 40.0 * k),
		Vector2(_edge_x(o.left_start, o.left_bottom, top) - gap, top),
		Vector2(o.left_bottom.x - gap, bottom), Vector2(lx, bottom)])
	var right := PackedVector2Array([Vector2(rx, top + 40.0 * k),
		Vector2(_edge_x(o.right_start, o.right_bottom, top) + gap, top),
		Vector2(o.right_bottom.x + gap, bottom), Vector2(rx, bottom)])
	for poly in [left, right]:
		draw_colored_polygon(poly, panel_fill_color)
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, panel_dim_color, 1.0 * k)
	var levels := panel_bar_levels()
	for i in range(RIGHT_TABS.size()):
		var y := top + (40.0 + 40.0 * i) * k
		var ex := _edge_x(o.right_start, o.right_bottom, y)
		_tab(ex + 22.0 * k, y, 84.0 * k, 16.0 * k, RIGHT_TABS[i], false, i == 2, k)
		for seg in range(5):
			var color := panel_color if seg < levels[i] else panel_dim_color
			if i == FADING_ROW and seg == levels[i] - 1:
				color = panel_color.lerp(panel_dim_color, panel_fade_amount())
			draw_rect(Rect2(ex + (116.0 + 9.0 * seg) * k, y + 4.0 * k, 6.0 * k, 9.0 * k), color)
	for i in range(LEFT_TABS.size()):
		var y := top + (40.0 + 40.0 * i) * k
		var ex := _edge_x(o.left_start, o.left_bottom, y)
		_tab(ex - (22.0 + 84.0) * k, y, 84.0 * k, 16.0 * k, LEFT_TABS[i], true, i == 4, k)
	# Left vertical gauge with a ruler.
	var gx := _mock(362.0, 0.0).x
	var gy0 := top + 60.0 * k
	var gy1 := _bar_line_y() - 23.0 * k
	draw_rect(Rect2(gx, gy0, 10.0 * k, gy1 - gy0), panel_dim_color, false, 1.0 * k)
	draw_rect(Rect2(gx + 1.0 * k, gy0 + (gy1 - gy0) * 0.35, 9.0 * k, (gy1 - gy0) * 0.65 - 1.0 * k), Color8(150, 50, 95))
	var mark := 0
	while gy0 + mark * 8.0 * k < gy1:
		var my := gy0 + mark * 8.0 * k
		draw_line(Vector2(gx + 13.0 * k, my), Vector2(gx + (22.0 if mark % 5 == 0 else 18.0) * k, my), panel_dim_color, 1.0 * k)
		mark += 1
	# Right segmented scale.
	var sx := _mock(1110.0, 0.0).x
	var sy := _bar_line_y() - 27.0 * k
	var lit := scale_lit_count()
	for seg in range(12):
		draw_rect(Rect2(sx + 11.0 * seg * k, sy, 8.0 * k, 9.0 * k), panel_color if seg < lit else panel_dim_color)
	_text("0   2   4   6   8   10", Vector2(sx, sy - 14.0 * k + _ascent(k)), _panel_font_size(k), panel_dim_color)
	for i in range(TOP_LEFT_TABS.size()):
		var p := _mock(372.0, 128.0 + 24.0 * i)
		_tab(p.x, p.y, 90.0 * k, 16.0 * k, TOP_LEFT_TABS[i], false, false, k)
	for i in range(TOP_RIGHT_TABS.size()):
		var p := _mock(1138.0, 128.0 + 24.0 * i)
		_tab(p.x, p.y, 90.0 * k, 16.0 * k, TOP_RIGHT_TABS[i], true, false, k)

func _panel_font_size(k: float) -> int:
	return maxi(8, int(round(10.0 * k)))

func _ascent(k: float) -> float:
	return ThemeDB.fallback_font.get_ascent(_panel_font_size(k))

## An angled tab with a short fake label (decoration only).
func _tab(x: float, y: float, w: float, h: float, label: String, flip: bool, bright: bool, k: float) -> void:
	var s := 8.0 * k
	var pts := PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w - s, y + h), Vector2(x - s, y + h)])
	if flip:
		pts = PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w + s, y + h), Vector2(x + s, y + h)])
	draw_colored_polygon(pts, Color8(110, 30, 70) if bright else Color8(60, 16, 38))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, panel_color, 1.0 * k)
	_text(label, Vector2(x + (10.0 if flip else 6.0) * k, y + 2.0 * k + _ascent(k)), _panel_font_size(k), Color8(240, 170, 205))

# ---------- 1.2.4 PANEL ANIMATION ----------
## Lit segments (of 5) for each right-panel bar readout. Still panels show the mockup
## levels 1-5; animated, rows 0, 2 and 4 step slowly by up to Panel Step Amount.
func panel_bar_levels() -> Array[int]:
	var levels: Array[int] = []
	for i in range(RIGHT_TABS.size()):
		var base := (i % 5) + 1
		if panel_animation_enabled and i in STEPPING_ROWS:
			base += _panel_step(i)
		levels.append(clampi(base, 1, 5))
	return levels

## Lit segments (of 12) on the right segmented scale: 8, stepping slowly when animated.
func scale_lit_count() -> int:
	var lit := 8
	if panel_animation_enabled:
		lit += _panel_step(7)
	return clampi(lit, 1, 12)

## How far the fading segment is dimmed now (0 to Panel Flicker Amount), a slow ease.
func panel_fade_amount() -> float:
	if not panel_animation_enabled:
		return 0.0
	var period := maxf(1.0, panel_step_seconds) * 2.0
	return panel_flicker_amount * (0.5 - 0.5 * cos(TAU * panel_time / period))

## A repeatable step (-amount to +amount) for one readout, changing every Panel Step
## Seconds, each readout on its own offset so they never all move together.
func _panel_step(index: int) -> int:
	var amount := clampi(panel_step_amount, 0, 2)
	if amount == 0:
		return 0
	var period := maxf(1.0, panel_step_seconds)
	var tick := int(floor(panel_time / period + 0.37 * index))
	return posmod(tick * 73 + index * 151 + (tick * tick) % 11, 2 * amount + 1) - amount

func _text(value: String, position: Vector2, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## 1.2.7: room for text in the right panel, from its text column to the inner border.
const RIGHT_PANEL_TEXT_ROOM := 316.0

## 1.2.7: the largest font size (down to 10) at which value fits in room.
func fit_font_size(value: String, font_size: int, room: float) -> int:
	var font := ThemeDB.fallback_font
	var fs := font_size
	while fs > 9 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	return fs

func _text_fit(value: String, position: Vector2, font_size: int, color: Color, room: float = RIGHT_PANEL_TEXT_ROOM) -> void:
	if value.is_empty():
		return
	_text(value, position, fit_font_size(value, font_size, room), color)


# ---------- 1.2.5: console layout 2 shapes (mockup pixels, 1600x900) ----------
const V2_PANEL_TOP := 340.0
## Gap from the scope border (V edge or arc) to every tab and light, in mockup pixels.
const V2_SCOPE_GAP := 22.0
## Outer (far) sides: top tabs and panels; panel tabs; ready lights.
const V2_PANEL_OUTER_L := 345.0
const V2_PANEL_OUTER_R := 1255.0
const V2_TAB_OUTER_L := 410.0
const V2_TAB_OUTER_R := 1190.0
const V2_TAB_TOP := 456.0
const V2_TAB_STEP := 31.0
const V2_ALERT_TOP := 636.0
## 1.2.7: the status box reaches the outer edges of the top tabs and corner panels (was 300).
const V2_STATUS_HALF := (V2_PANEL_OUTER_R - V2_PANEL_OUTER_L) * 0.5

func _v2_status_rect() -> Rect2:
	var k := _frame_scale()
	var status: Label = get_parent().get_node("BattleStatus")
	var cx := _dome_center().x
	var top := status.position.y - 3.0
	var h := status.size.y + 6.0
	return Rect2(cx - V2_STATUS_HALF * k, top, 2.0 * V2_STATUS_HALF * k, h)

func _chamfer(r: Rect2, c: float) -> PackedVector2Array:
	return PackedVector2Array([r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y),
		Vector2(r.end.x, r.position.y + c), r.end - Vector2(0, c), r.end - Vector2(c, 0),
		Vector2(r.position.x + c, r.end.y), Vector2(r.position.x, r.end.y - c), r.position + Vector2(0, c),
		r.position + Vector2(c, 0)])

func _v2_status_box() -> void:
	var k := _frame_scale()
	var box := _chamfer(_v2_status_rect(), 8.0 * k)
	draw_colored_polygon(box, panel_fill_color)
	draw_polyline(box, panel_color.darkened(0.25), 1.0 * k, true)

## The scope arc's x at height y (left or right side).
func _arc_x(o: Dictionary, y: float, left: bool) -> float:
	var dy: float = y - o.center.y
	var ra: float = o.arc_radius
	var dx := sqrt(maxf(0.0, ra * ra - dy * dy))
	return o.center.x - dx if left else o.center.x + dx

## A tab with a vertical outer side and an angled side next to the scope.
func _tab_v2(outer: float, inner_top: float, inner_bottom: float, y: float, h: float, label: String,
		fill: Color, line: Color, text_color: Color, k: float, font_size: int = -1, centred: bool = false) -> void:
	var pts := PackedVector2Array([Vector2(outer, y), Vector2(inner_top, y), Vector2(inner_bottom, y + h), Vector2(outer, y + h)])
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, line, 1.0 * k)
	var fs := _panel_font_size(k) if font_size < 0 else font_size
	var font := ThemeDB.fallback_font
	var left_x := minf(outer, minf(inner_top, inner_bottom))
	var right_x := maxf(outer, maxf(inner_top, inner_bottom))
	var tx := 0.0
	if centred:
		tx = (left_x + right_x) * 0.5 - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5
	elif outer < inner_top:
		tx = outer + 7.0 * k
	else:
		tx = outer - 7.0 * k - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ty := y + (h - font.get_height(fs)) * 0.5 + font.get_ascent(fs)
	draw_string(font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)

func _v2_panel_poly(o: Dictionary, k: float, left: bool) -> PackedVector2Array:
	var gap := 10.0 * k
	var top := _mock(0.0, V2_PANEL_TOP).y
	var bottom := _bar_line_y() - 1.0 * k
	var ch := 14.0 * k
	if left:
		var lx := _mock(345.0, 0.0).x
		return PackedVector2Array([Vector2(lx, top + ch), Vector2(lx + ch, top),
			Vector2(_edge_x(o.left_start, o.left_bottom, top) - gap, top),
			Vector2(o.left_bottom.x - gap, bottom), Vector2(lx, bottom)])
	var rx := _mock(1255.0, 0.0).x
	return PackedVector2Array([Vector2(rx, top + ch), Vector2(rx - ch, top),
		Vector2(_edge_x(o.right_start, o.right_bottom, top) + gap, top),
		Vector2(o.right_bottom.x + gap, bottom), Vector2(rx, bottom)])

## Ready = the matching bottom button can be pressed (display only).
func indicator_ready(button_name: String) -> bool:
	var b := get_parent().get_node_or_null("BottomButtons/" + button_name) as Button
	return b != null and b.visible and not b.disabled

func _v2_indicator(o: Dictionary, k: float, left: bool, row: int, label: String, ready: bool) -> void:
	var y := _mock(0.0, 354.0 + 44.0 * row).y
	var h := 32.0 * k
	var gap := V2_SCOPE_GAP * k
	var fill := Color8(150, 38, 92) if ready else Color8(34, 10, 22)
	var line := Color8(255, 130, 195) if ready else panel_dim_color
	var text_color := Color8(255, 236, 246) if ready else Color8(130, 74, 102)
	var fs := maxi(9, int(round(14.0 * k)))
	if left:
		var outer := _mock(357.0, 0.0).x
		_tab_v2(outer, _edge_x(o.left_start, o.left_bottom, y) - gap, _edge_x(o.left_start, o.left_bottom, y + h) - gap,
			y, h, label, fill, line, text_color, k, fs, true)
	else:
		var outer_r := _mock(1243.0, 0.0).x
		_tab_v2(outer_r, _edge_x(o.right_start, o.right_bottom, y) + gap, _edge_x(o.right_start, o.right_bottom, y + h) + gap,
			y, h, label, fill, line, text_color, k, fs, true)

func hull_gauge_rect() -> Rect2:
	var k := _frame_scale()
	var top := _mock(0.0, V2_TAB_TOP + 16.0).y
	var bottom := _mock(0.0, V2_ALERT_TOP - 18.0).y
	return Rect2(_mock(362.0, 0.0).x, top, hull_gauge_width * k, bottom - top)

func hull_gauge_fill_rect() -> Rect2:
	# Fill meets the inner edge of the centred one-pixel border.
	var inner := hull_gauge_rect().grow(-0.5 * _frame_scale())
	var fraction := clampf(battle.hull / maxf(1.0, battle.max_hull), 0.0, 1.0)
	var height := inner.size.y * fraction
	return Rect2(inner.position.x, inner.end.y - height, inner.size.x, height)

func hull_gauge_color() -> Color:
	return ship_status.hull_display_color()

func hull_percent_text() -> String:
	var fraction := clampf(battle.hull / maxf(1.0, battle.max_hull), 0.0, 1.0)
	return "%d%%" % int(round(fraction * 100.0))

func hull_percent_font_size() -> int:
	return maxi(8, int(round(9.0 * _frame_scale())))

func hull_percent_baseline() -> Vector2:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(hull_percent_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, hull_percent_font_size()).x
	var gauge := hull_gauge_rect()
	var bottom := _mock(0.0, V2_ALERT_TOP).y
	var label_top := gauge.end.y + (bottom - gauge.end.y - font.get_height(hull_percent_font_size())) * .5
	return Vector2(gauge.get_center().x - width * .5, label_top + font.get_ascent(hull_percent_font_size()))

func hull_percent_rect() -> Rect2:
	var font := ThemeDB.fallback_font
	var font_size := hull_percent_font_size()
	var dimensions := font.get_string_size(hull_percent_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return Rect2(hull_percent_baseline() - Vector2(0, font.get_ascent(font_size)), dimensions)

func _v2_panels(o: Dictionary, k: float) -> void:
	for side in [true, false]:
		var poly := _v2_panel_poly(o, k, side)
		draw_colored_polygon(poly, panel_fill_color)
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, panel_dim_color, 1.0 * k)
	# Eye-level ready lights mirroring the bottom buttons (not buttons).
	_v2_indicator(o, k, true, 0, "INTERCEPTORS", indicator_ready("LaunchInterceptors"))
	_v2_indicator(o, k, true, 1, "GUNSHIP", indicator_ready("LaunchGunship"))
	_v2_indicator(o, k, false, 0, "JUMP", indicator_ready("Jump"))
	_v2_indicator(o, k, false, 1, "DEFENSES", indicator_ready("ProxDefense"))
	var tab_fill := Color8(60, 16, 38)
	var tab_bright := Color8(110, 30, 70)
	var tab_text := Color8(240, 170, 205)
	var levels := panel_bar_levels()
	var h := 16.0 * k
	for i in range(RIGHT_TABS.size()):
		var y := _mock(0.0, V2_TAB_TOP + V2_TAB_STEP * i).y
		var g := V2_SCOPE_GAP * k
		var outer := _mock(V2_TAB_OUTER_R, 0.0).x
		_tab_v2(outer, _edge_x(o.right_start, o.right_bottom, y) + g, _edge_x(o.right_start, o.right_bottom, y + h) + g,
			y, h, RIGHT_TABS[i], tab_bright if i == 2 else tab_fill, panel_color, tab_text, k)
		for seg in range(5):
			var color := panel_color if seg < levels[i] else panel_dim_color
			if i == FADING_ROW and seg == levels[i] - 1:
				color = panel_color.lerp(panel_dim_color, panel_fade_amount())
			draw_rect(Rect2(outer + (10.0 + 9.0 * seg) * k, y + 4.0 * k, 6.0 * k, 9.0 * k), color)
	for i in range(LEFT_TABS.size()):
		var y := _mock(0.0, V2_TAB_TOP + V2_TAB_STEP * i).y
		var g := V2_SCOPE_GAP * k
		_tab_v2(_mock(V2_TAB_OUTER_L, 0.0).x, _edge_x(o.left_start, o.left_bottom, y) - g, _edge_x(o.left_start, o.left_bottom, y + h) - g,
			y, h, LEFT_TABS[i], tab_bright if i == 4 else tab_fill, panel_color, tab_text, k)
	# Left gauge, now ending above the alert box.
	var gx := _mock(362.0, 0.0).x
	var gy0 := _mock(0.0, V2_TAB_TOP + 16.0).y
	var gy1 := hull_gauge_rect().end.y
	# Hull gauge: wider, with the same live condition colour as the ship.
	var hull_f := clampf(battle.hull / maxf(1.0, battle.max_hull), 0.0, 1.0)
	var low := hull_f * 100.0 <= hull_low_percent
	var gauge_line := Color8(235, 70, 80) if low else panel_dim_color
	var gauge_fill := hull_gauge_fill_rect()
	if gauge_fill.size.y > 0.0:
		draw_rect(gauge_fill, hull_gauge_color())
	# Border last: fill can reach its inner edge without covering the outline.
	draw_rect(hull_gauge_rect(), gauge_line, false, 1.0 * k)
	draw_string(ThemeDB.fallback_font, hull_percent_baseline(), hull_percent_text(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, hull_percent_font_size(), TEXT)
	var hfs := maxi(8, int(round(10.0 * k)))
	draw_string(ThemeDB.fallback_font, Vector2(gx - 3.0 * k, gy0 - 5.0 * k), "HULL", HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, Color8(255, 120, 130) if low else Color8(240, 170, 205))
	var mark := 0
	while gy0 + mark * 8.0 * k < gy1:
		var my := gy0 + mark * 8.0 * k
		draw_line(Vector2(gx + (hull_gauge_width + 3.0) * k, my), Vector2(gx + (hull_gauge_width + (12.0 if mark % 5 == 0 else 8.0)) * k, my), panel_dim_color, 1.0 * k)
		mark += 1
	_v2_nav_box()
	# Right segmented scale (unchanged).
	var sx := _mock(1110.0, 0.0).x
	var sy := _bar_line_y() - 27.0 * k
	var lit := scale_lit_count()
	var scale_label := "0   2   4   6   8   10"
	if live_readouts:
		lit = int(round(12.0 * clampf(battle.battery_percent() / 100.0, 0.0, 1.0)))
		scale_label = "DEFENSE SHIELD  %d%%" % int(battle.battery_percent())
	for seg in range(12):
		draw_rect(Rect2(sx + 11.0 * seg * k, sy, 8.0 * k, 9.0 * k), panel_color if seg < lit else panel_dim_color)
	_text(scale_label, Vector2(sx, sy - 14.0 * k + _ascent(k)), _panel_font_size(k), Color8(240, 170, 205) if live_readouts else panel_dim_color)
	# Top tabs: lower, wider, reaching to the scope; the angled end follows the arc.
	var th := 18.0 * k
	var tgap := V2_SCOPE_GAP * k
	for i in range(TOP_LEFT_TABS.size()):
		var y := _mock(0.0, 168.0 + 26.0 * i).y
		_tab_v2(_mock(V2_PANEL_OUTER_L, 0.0).x, _arc_x(o, y, true) - tgap, _arc_x(o, y + th, true) - tgap, y, th,
			TOP_LEFT_TABS[i], tab_fill, panel_color, tab_text, k)
	var right_labels: Array[String] = TOP_RIGHT_TABS.duplicate()
	if live_readouts:
		right_labels[0] = "TRACKS %02d" % battle.contacts.size()
	for i in range(TOP_RIGHT_TABS.size()):
		var y := _mock(0.0, 168.0 + 26.0 * i).y
		_tab_v2(_mock(V2_PANEL_OUTER_R, 0.0).x, _arc_x(o, y, false) + tgap, _arc_x(o, y + th, false) + tgap, y, th,
			right_labels[i], tab_fill, panel_color, tab_text, k)

## The alert box in the left panel: always shown, ALERT STATUS when quiet,
## the Breacher warnings when there is an alert. Right side follows the V.
func alert_box_poly() -> PackedVector2Array:
	var o := scope_outline()
	var k := _frame_scale()
	var top := _mock(0.0, V2_ALERT_TOP).y
	var bottom := _bar_line_y() - 9.0 * k
	var lx := _mock(357.0, 0.0).x
	var gap := V2_SCOPE_GAP * k
	var c := 8.0 * k
	var rt := _edge_x(o.left_start, o.left_bottom, top) - gap
	var rb := _edge_x(o.left_start, o.left_bottom, bottom) - gap
	return PackedVector2Array([Vector2(lx, top + c), Vector2(lx + c, top), Vector2(rt, top),
		Vector2(rb, bottom), Vector2(lx + c, bottom), Vector2(lx, bottom - c), Vector2(lx, top + c)])

## 1.2.9: PROTECT THE FLEET with SHIPS n OF m, ATTACK DRONES n LEFT and TIME m:ss.
func protect_counter_rows() -> Array:
	var left_s := maxi(0, ceili(battle.protect_time_left()))
	return [["SHIPS", "%d OF %d" % [battle.civilians_left(), battle.protect_civilians_total], battle.civilian_color],
		["ATTACK DRONES", "%d LEFT" % battle.protect_drones_left(), Color(1.0, 0.36, 0.36)],
		["TIME", "%d:%02d" % [floori(left_s / 60.0), left_s % 60], Color8(230, 220, 228)]]

func _draw_protect_counter(x0: float, y0: float, fs: int, k: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(x0, y0 + font.get_ascent(fs)), "PROTECT THE FLEET", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(240, 170, 205))
	var line_h := font.get_height(fs) * 1.25
	var value_fs := maxi(10, int(round(14.0 * k)))
	var y := y0 + font.get_height(fs) + line_h * 0.4
	for row in protect_counter_rows():
		y += line_h
		draw_string(font, Vector2(x0, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(200, 150, 180))
		draw_string(font, Vector2(x0 + 70.0 * k, y), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, value_fs, row[2])

func _v2_alert_box() -> void:
	var k := _frame_scale()
	var box := alert_box_poly()
	var state: String = battle.hack_state()
	var font := ThemeDB.fallback_font
	var x0 := box[0].x + 9.0 * k
	var y0 := box[1].y + 7.0 * k
	draw_colored_polygon(box, get_parent().get_node("Background").color)
	# 1.2.7: quiet or a Breacher approaching: ALERT STATUS and the inbound threat list.
	# Hacking and a breach still take over the whole box.
	if state == "" or state == "approach":
		draw_colored_polygon(box, panel_fill_color if state == "" else Color(1.0, 0.78, 0.25, 0.08))
		draw_polyline(box, panel_color.darkened(0.2), 1.5 * k, true)
		var fs := maxi(9, int(round(12.0 * k)))
		# 1.2.9: during Protect the fleet the box counts ships, Attack Drones and time left.
		if battle.protect_round_counter and battle.protect_active():
			_draw_protect_counter(x0, y0, fs, k)
			return
		draw_string(font, Vector2(x0, y0 + font.get_ascent(fs)), "ALERT STATUS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(240, 170, 205))
		_draw_threat_list(box, battle.inbound_threats(), x0, y0 + font.get_height(fs), fs, k)
		return
	var blink: bool = int(battle.battle_time * 4.0) % 2 == 0
	var color := Color(1.0, 0.2, 0.26) if blink or state == "draining" else Color(1.0, 0.78, 0.25)
	var text_color := Color(1.0, 0.78, 0.25)
	if state == "draining":
		text_color = Color(1.0, 0.25, 0.3) if blink else Color(1.0, 0.55, 0.58)
	elif state == "hacking":
		text_color = Color(1.0, 0.25, 0.3) if blink else Color(1.0, 0.78, 0.25)
	if state == "approach":
		color = Color(1.0, 0.78, 0.25)
	draw_colored_polygon(box, Color(color, 0.08))
	draw_polyline(box, alert_outline_color(state, blink), FRAME_WIDTH * k, true)
	# Wrap each line to the box width at its height (the right side slants).
	var fs2 := maxi(9, int(round(12.0 * k)))
	var line_h := font.get_height(fs2)
	var lines: Array[String] = []
	for raw in battle.hacking_warning().split("\n"):
		var words: PackedStringArray = raw.split(" ")
		var cur := ""
		for w in words:
			var trial: String = w if cur == "" else cur + " " + w
			if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x > box[2].x - x0 - 8.0 * k and cur != "":
				lines.append(cur)
				cur = w
			else:
				cur = trial
		lines.append(cur)
	var total := line_h * lines.size()
	var inner_h := box[3].y - box[2].y
	var y := y0 if state != "approach" else box[2].y + (inner_h - total) * 0.5
	for line in lines:
		var lx := x0
		if state == "approach":
			var bw := box[2].x - box[0].x
			lx = box[0].x + (bw - font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x) * 0.5
		draw_string(font, Vector2(lx, y + font.get_ascent(fs2)), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, text_color)
		y += line_h

## 1.2.7: x of the box's slanted right edge at height y.
func alert_box_right_x(box: PackedVector2Array, y: float) -> float:
	var span := box[3].y - box[2].y
	return box[2].x if span <= 0.0 else lerpf(box[2].x, box[3].x, clampf((y - box[2].y) / span, 0.0, 1.0))

## 1.2.7: one line per inbound threat: the count right-aligned in a narrow column, then the
## label. Each label is measured against the slanted edge at its line's top (the narrowest
## point) and shrinks, then is cut, so text never crosses the outline. Lines that would run
## past the bottom of the box are not drawn.
func threat_line_layout(box: PackedVector2Array, rows: Array, x0: float, y_start: float, font_size: int, k: float) -> Array:
	var font := ThemeDB.fallback_font
	var line_h := font.get_height(font_size)
	var out := []
	var y := y_start
	for row in rows:
		if y + line_h > box[3].y - 4.0 * k:
			break
		var label: String = row[1]
		var lx := x0 + 26.0 * k
		var room := alert_box_right_x(box, y) - 6.0 * k - lx
		var fs := font_size
		while fs > 9 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
		while label.length() > 1 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			label = label.substr(0, label.length() - 1)
		out.append({"count": str(row[0]), "label": label, "color": row[2], "y": y, "size": fs, "label_x": lx,
			"count_right": x0 + 18.0 * k, "label_width": font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
			"room": room})
		y += line_h
	return out

func _draw_threat_list(box: PackedVector2Array, rows: Array, x0: float, y_start: float, font_size: int, k: float) -> void:
	var font := ThemeDB.fallback_font
	for line in threat_line_layout(box, rows, x0, y_start, font_size, k):
		var fs: int = line.size
		var ascent := font.get_ascent(fs)
		var cw := font.get_string_size(line.count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(line.count_right - cw, line.y + ascent), line.count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, line.color)
		draw_string(font, Vector2(line.label_x, line.y + ascent), line.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, line.color)

## 1.2.6: the alert box outline. Where 1.2.5 drew it amber (a Breacher approaching,
## and the steady half of the hacking blink) it now uses the normal panel outline colour,
## the same as the quiet ALERT STATUS box. The red blink while hacking and the steady red
## of a breach are unchanged. The text colours inside the box are not affected.
func alert_outline_color(state: String, blink: bool) -> Color:
	if state == "draining" or (state == "hacking" and blink):
		return Color(1.0, 0.2, 0.26)
	return panel_color.darkened(0.2)


# ---------- 1.2.5: navigation data panel ----------
const NAV_NAMES: Array[String] = ["KESTREL", "ORIN", "TALOS", "MERIDIAN", "HALCYON", "CEPHA", "IOLA", "SABLE", "ARDEN", "VESPER", "CALLIS", "NEREID", "THANE", "OSPREY", "LYRAN", "MARROW"]
const NAV_STARS: Array[String] = ["M3 RED DWARF", "K2 ORANGE DWARF", "G5 YELLOW STAR", "F8 WHITE STAR", "BINARY K/M PAIR", "WHITE DWARF", "BROWN DWARF", "B9 BLUE GIANT"]
const NAV_BODIES: Array[String] = ["GAS GIANT", "ICE GIANT", "ROCKY WORLD", "ASTEROID BELT", "OCEAN WORLD", "DEAD MOON", "TYLIUM FIELD", "NEBULA EDGE"]
const NAV_NOTES: Array[String] = ["RADIATION LOW", "RADIATION MODERATE", "ION STORM DISTANT", "DEBRIS FIELD NEAR", "NO SIGNALS", "COMMS RELAY QUIET", "DUST CLOUD THIN", "MAGNETIC FIELD WEAK"]

func new_nav_location() -> void:
	var rng := RandomNumberGenerator.new()
	if nav_seed != 0:
		rng.seed = nav_seed + nav_jumps * 7919
	else:
		rng.randomize()
	var sector := "%s-%02d" % [NAV_NAMES[rng.randi_range(0, NAV_NAMES.size() - 1)], rng.randi_range(1, 99)]
	var planets := rng.randi_range(0, 9)
	var body := NAV_BODIES[rng.randi_range(0, NAV_BODIES.size() - 1)]
	var note := NAV_NOTES[rng.randi_range(0, NAV_NOTES.size() - 1)]
	nav_lines = [
		"SECTOR  %s" % sector,
		"X %+06.1f  Y %+06.1f  Z %+05.1f" % [rng.randf_range(-999.0, 999.0), rng.randf_range(-999.0, 999.0), rng.randf_range(-99.0, 99.0)],
		"STAR  %s  %.1f LY" % [NAV_STARS[rng.randi_range(0, NAV_STARS.size() - 1)], rng.randf_range(0.2, 9.9)],
		("PLANETS  %d" % planets) if planets > 0 else "NO PLANETS",
		("NEAREST  %s  %.1f AU" % [body, rng.randf_range(0.1, 6.0)]) if planets > 0 else "DEEP SPACE",
		note,
	]

## Mirror of the alert box on the right, ending above the Defense Shield scale.
func nav_box_poly() -> PackedVector2Array:
	var o := scope_outline()
	var k := _frame_scale()
	var top := _mock(0.0, V2_ALERT_TOP).y
	var bottom := _bar_line_y() - 52.0 * k
	var rx := _mock(1243.0, 0.0).x
	var gap := V2_SCOPE_GAP * k
	var c := 8.0 * k
	var lt := _edge_x(o.right_start, o.right_bottom, top) + gap
	var lb := _edge_x(o.right_start, o.right_bottom, bottom) + gap
	return PackedVector2Array([Vector2(rx, top + c), Vector2(rx - c, top), Vector2(lt, top),
		Vector2(lb, bottom), Vector2(rx - c, bottom), Vector2(rx, bottom - c), Vector2(rx, top + c)])

func _v2_nav_box() -> void:
	if not nav_data_panel:
		return
	var k := _frame_scale()
	var box := nav_box_poly()
	draw_colored_polygon(box, panel_fill_color)
	draw_polyline(box, panel_color.darkened(0.2), 1.5 * k, true)
	var font := ThemeDB.fallback_font
	var fs := maxi(9, int(round(12.0 * k)))
	var fs2 := maxi(8, int(round(10.5 * k)))
	var x0 := box[2].x + 8.0 * k
	var y := box[2].y + 7.0 * k
	draw_string(font, Vector2(x0, y + font.get_ascent(fs)), "NAV DATA  |  JUMP %d" % nav_jumps, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(240, 170, 205))
	y += font.get_height(fs) + 2.0 * k
	for line in nav_lines:
		draw_string(font, Vector2(x0, y + font.get_ascent(fs2)), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color8(205, 145, 180))
		y += font.get_height(fs2)
