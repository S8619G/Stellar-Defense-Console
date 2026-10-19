extends Button
## Clicks follow the visible center inset, not its bounding rectangle.
var hit_polygon := PackedVector2Array()
var blocked_rect := Rect2()

func _has_point(point: Vector2) -> bool:
	if hit_polygon.size() < 3:
		return false
	if blocked_rect.size.x > 0.0 and blocked_rect.has_point(point):
		return false
	return Geometry2D.is_point_in_polygon(point, hit_polygon)
