## Upright people for the three-quarter top-down view (the Stardew Valley look): feet on the ground,
## a soft shadow, legs that swing while walking, body, arms and a head seen from the front, the back
## or the side depending on where the person faces. Drawn with primitives, no sprites.
class_name Figure
extends RefCounted


## feet: ground point. facing: walking or looking direction (screen space, y down = toward camera).
## step: walk-cycle phase in radians. moving: legs swing only while walking. s: scale (1 = adult).
## look: {shirt, pants, skin, hair, hat (Color or null)}.
static func draw_person(ci: CanvasItem, feet: Vector2, facing: Vector2, step: float, moving: bool, look: Dictionary, s: float = 1.0) -> void:
	var shirt: Color = look.get("shirt", Color(0.25, 0.40, 0.65))
	var pants: Color = look.get("pants", Color(0.20, 0.22, 0.28))
	var skin: Color = look.get("skin", Color(0.92, 0.74, 0.58))
	var hair: Color = look.get("hair", Color(0.20, 0.14, 0.10))
	var side := clampf(facing.x, -1.0, 1.0)
	var toward := facing.y > 0.25                    # facing the camera: we see the face
	var swing := sin(step) * 5.0 * s if moving else 0.0
	var bob := absf(sin(step)) * 1.5 * s if moving else 0.0
	# shadow
	_ellipse(ci, feet + Vector2(0.0, 1.0 * s), Vector2(11.0 * s, 4.0 * s), Color(0.0, 0.0, 0.0, 0.25))
	# legs
	var hip := feet + Vector2(0.0, -16.0 * s - bob)
	ci.draw_line(hip + Vector2(-3.0 * s, 0.0), feet + Vector2(-3.0 * s + swing * 0.6, 0.0), pants, 4.5 * s)
	ci.draw_line(hip + Vector2(3.0 * s, 0.0), feet + Vector2(3.0 * s - swing * 0.6, 0.0), pants, 4.5 * s)
	ci.draw_circle(feet + Vector2(-3.0 * s + swing * 0.6, 0.0), 2.4 * s, Color(0.12, 0.10, 0.09))
	ci.draw_circle(feet + Vector2(3.0 * s - swing * 0.6, 0.0), 2.4 * s, Color(0.12, 0.10, 0.09))
	# body
	var chest := hip + Vector2(0.0, -12.0 * s)
	ci.draw_colored_polygon(PackedVector2Array([hip + Vector2(-6.0 * s, 1.0 * s), hip + Vector2(6.0 * s, 1.0 * s),
		chest + Vector2(7.5 * s, -2.0 * s), chest + Vector2(-7.5 * s, -2.0 * s)]), shirt)
	ci.draw_line(chest + Vector2(-7.5 * s, -2.0 * s), chest + Vector2(-8.0 * s, 9.0 * s - swing * 0.5), shirt.darkened(0.12), 3.5 * s)
	ci.draw_line(chest + Vector2(7.5 * s, -2.0 * s), chest + Vector2(8.0 * s, 9.0 * s + swing * 0.5), shirt.darkened(0.12), 3.5 * s)
	ci.draw_circle(chest + Vector2(-8.0 * s, 9.5 * s - swing * 0.5), 2.0 * s, skin)
	ci.draw_circle(chest + Vector2(8.0 * s, 9.5 * s + swing * 0.5), 2.0 * s, skin)
	# head
	var head := chest + Vector2(side * 1.5 * s, -8.0 * s)
	ci.draw_circle(head, 6.5 * s, skin)
	if toward:
		ci.draw_circle(head + Vector2(0.0, -2.5 * s), 6.6 * s, hair)
		ci.draw_circle(head + Vector2(0.0, 1.2 * s), 5.6 * s, skin)
		ci.draw_circle(head + Vector2(-2.2 * s + side * 1.5 * s, 0.8 * s), 0.9 * s, Color(0.1, 0.08, 0.08))
		ci.draw_circle(head + Vector2(2.2 * s + side * 1.5 * s, 0.8 * s), 0.9 * s, Color(0.1, 0.08, 0.08))
	else:
		ci.draw_circle(head + Vector2(-side * 1.0 * s, -0.5 * s), 6.4 * s, hair)
	var hat: Variant = look.get("hat", null)
	if hat is Color:
		var hc: Color = hat
		_ellipse(ci, head + Vector2(0.0, -4.0 * s), Vector2(8.5 * s, 2.6 * s), hc.darkened(0.15))
		ci.draw_circle(head + Vector2(0.0, -5.0 * s), 5.2 * s, hc)


## A cat seen from the side: body, head with ears, tail curling on an oscillator.
static func draw_cat(ci: CanvasItem, pos: Vector2, dir: float, t: float, col: Color) -> void:
	_ellipse(ci, pos + Vector2(0.0, 2.0), Vector2(9.0, 3.0), Color(0.0, 0.0, 0.0, 0.2))
	var body := pos + Vector2(0.0, -6.0)
	_ellipse(ci, body, Vector2(8.0, 4.5), col)
	ci.draw_line(body + Vector2(-5.0, 2.0), pos + Vector2(-5.0, 0.0), col.darkened(0.1), 2.0)
	ci.draw_line(body + Vector2(5.0, 2.0), pos + Vector2(5.0, 0.0), col.darkened(0.1), 2.0)
	var head := body + Vector2(dir * 8.0, -3.0)
	ci.draw_circle(head, 4.0, col)
	ci.draw_colored_polygon(PackedVector2Array([head + Vector2(-3.0, -2.0), head + Vector2(-2.0, -6.0), head + Vector2(0.0, -3.0)]), col)
	ci.draw_colored_polygon(PackedVector2Array([head + Vector2(3.0, -2.0), head + Vector2(2.0, -6.0), head + Vector2(0.0, -3.0)]), col)
	var tail_base := body + Vector2(-dir * 7.0, -1.0)
	var tail_tip := tail_base + Vector2(-dir * 6.0, -8.0 + sin(t * 3.0) * 3.0)
	ci.draw_line(tail_base, tail_tip, col.darkened(0.15), 2.0)


static func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	ci.draw_colored_polygon(pts, col)
