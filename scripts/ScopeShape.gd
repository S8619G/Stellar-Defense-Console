extends RefCounted
## 1.2.4: the RADAR scope outline, shared by the console frame (drawing) and the
## contacts (Keep Play In Wedge), so both always use the same shape.
##
## Units are the dome's sphere radius, measured from the dome centre, with y pointing
## down the screen. The outline is a circular arc over the top that runs down to
## V_START_DEG below horizontal, then two straight edges down and inward to the
## button bar line, V_HALF_WIDTH either side of centre.

## Border arc radius (1.05 x sphere radius clears the orbital rings).
const ARC := 1.05
## The V edges start this many degrees below horizontal.
const V_START_DEG := 4.0
## Half the width of the V where it meets the button bar line.
const V_HALF_WIDTH := 0.75
## How far below the dome centre the V meets the button bar line (968 - 480 = 488 px
## at the default layout, 1.525 x 320).
const V_DEPTH := 1.525

static func v_start() -> Vector2:
	var a := deg_to_rad(V_START_DEG)
	return Vector2(ARC * cos(a), ARC * sin(a))

## Half width of the V at height y (y between the V start and V_DEPTH).
static func v_half_width_at(y: float, depth: float = V_DEPTH) -> float:
	var s := v_start()
	var f := clampf((y - s.y) / maxf(0.001, depth - s.y), 0.0, 1.0)
	return lerpf(s.x, V_HALF_WIDTH, f)

## Extra horizontal allowance so a margin is measured square to the V edges.
static func v_margin_factor(depth: float = V_DEPTH) -> float:
	var s := v_start()
	var dx := s.x - V_HALF_WIDTH
	var dy := depth - s.y
	return sqrt(dx * dx + dy * dy) / dy

## True when p (sphere-radius units, y down) is inside the shape, at least margin from its edge.
static func contains(p: Vector2, margin: float = 0.0) -> bool:
	return p.distance_to(clamp_inside(p, margin)) <= 0.000001

## The nearest point inside the shape (shrunk by margin) for p, by moving it straight
## in towards the centre over the arc and sideways or up inside the V.
static func clamp_inside(p: Vector2, margin: float = 0.0) -> Vector2:
	var s := v_start()
	var q := p
	if q.y <= s.y:
		var limit := maxf(0.0, ARC - margin)
		if q.length() > limit:
			q = q.normalized() * limit
		return q
	q.y = minf(q.y, V_DEPTH - margin)
	var half := maxf(0.0, v_half_width_at(q.y) - margin * v_margin_factor())
	q.x = clampf(q.x, -half, half)
	return q
