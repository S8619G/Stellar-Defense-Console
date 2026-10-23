extends RefCounted
## Exact approved Draft 03 marks. Legacy category keys are compatibility IDs only.
## No reference-sheet geometry is retained. All live categories have a new mark.
const KINDS := [
	"unknown", "siege_ship", "carrier", "breacher", "drone",
	"drone_squadron", "aegis", "civilian_convoy", "friendly_unknown",
	"gunship", "civilian_liner", "interceptor", "interceptor_squadron",
	"civilian_a", "civilian_b", "civilian_c", "civilian_d", "civilian_e",
	"stealth_interceptor", "repair_tender"
]
const ICONS := {
	"unknown": preload("res://assets/icons/unknown.png"),
	"siege_ship": preload("res://assets/icons/siege.png"),
	"carrier": preload("res://assets/icons/carrier.png"),
	"breacher": preload("res://assets/icons/breacher.png"),
	# 1.0.7: the Protect the convoy Breacher uses the Breacher mark.
	"convoy_breacher": preload("res://assets/icons/breacher.png"),
	"drone": preload("res://assets/icons/drone.png"),
	"drone_squadron": preload("res://assets/icons/drone-squadron.png"),
	"aegis": preload("res://assets/ship_outline.png"),
	"civilian_convoy": preload("res://assets/icons/civilian-a.png"),
	"friendly_unknown": preload("res://assets/icons/unknown.png"),
	"gunship": preload("res://assets/icons/gunship.png"),
	"civilian_liner": preload("res://assets/icons/unknown.png"),
	"interceptor": preload("res://assets/icons/interceptor.png"),
	"interceptor_squadron": preload("res://assets/icons/interceptor-squadron.png"),
	"civilian_a": preload("res://assets/icons/civilian-a.png"),
	"civilian_b": preload("res://assets/icons/civilian-b.png"),
	"civilian_c": preload("res://assets/icons/civilian-c.png"),
	"civilian_d": preload("res://assets/icons/civilian-d.png"),
	"civilian_e": preload("res://assets/icons/civilian-e.png"),
	"stealth_interceptor": preload("res://assets/icons/stealth.png"),
	"repair_tender": preload("res://assets/icons/tender.png"),
}

static func is_interceptor(kind: String) -> bool:
	# This helper is also used by combat. The stealth craft must not be counted
	# or attacked as a normal Interceptor; only its artwork changes here.
	return kind in ["interceptor", "interceptor_squadron"]

static func draw_icon(canvas: CanvasItem, kind: String, center: Vector2, icon_scale: float, color: Color) -> void:
	var texture: Texture2D = ICONS.get(kind, ICONS.unknown)
	var diameter := 32.0 * icon_scale
	if kind in ["carrier", "siege_ship"]:
		diameter *= 1.5
	var dimensions := Vector2.ONE * diameter
	if kind == "aegis":
		dimensions.y *= float(texture.get_height()) / float(texture.get_width())
	canvas.draw_texture_rect(texture, Rect2(center - dimensions * 0.5, dimensions), false, color)
