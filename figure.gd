## Upright people for the three-quarter top-down view (the Stardew Valley look): feet on the ground,
## a soft shadow, legs that swing while walking, body, arms and a head seen from the front, the back
## or the side depending on where the person faces. Drawn with primitives, no sprites.
class_name Figure
extends RefCounted


## feet: ground point. facing: walking or looking direction (screen space, y down = toward camera).
## step: walk-cycle phase in radians. moving: legs swing only while walking. s: scale (1 = adult).
## look: {shirt, pants, skin, hair, hat (Color or null)}. hold: a point both hands grip (a rod), or
## Vector2.INF for free arms. Walking left or right shows the person in profile, legs scissoring,
## so nobody slides sideways like a crab.
static func draw_person(ci: CanvasItem, feet: Vector2, facing: Vector2, step: float, moving: bool, look: Dictionary,
		s: float = 1.0, hold: Vector2 = Vector2.INF) -> void:
	var shirt: Color = look.get("shirt", Color(0.25, 0.40, 0.65))
	var pants: Color = look.get("pants", Color(0.20, 0.22, 0.28))
	var skin: Color = look.get("skin", Color(0.92, 0.74, 0.58))
	var hair: Color = look.get("hair", Color(0.20, 0.14, 0.10))
	var shoe := Color(0.12, 0.10, 0.09)
	var profile := absf(facing.x) > 0.55
	var dir := 1.0 if facing.x >= 0.0 else -1.0
	var toward := facing.y > 0.25 and not profile
	var swing := sin(step) if moving else 0.0
	var bob := absf(sin(step)) * 1.5 * s if moving else 0.0
	_ellipse(ci, feet + Vector2(0.0, 1.0 * s), Vector2((8.0 if profile else 11.0) * s, 4.0 * s), Color(0.0, 0.0, 0.0, 0.25))
	var hip := feet + Vector2(0.0, -16.0 * s - bob)
	var chest := hip + Vector2(0.0, -12.0 * s)
	var holding := hold != Vector2.INF
	if profile:
		# Legs scissor forward and back along the walking direction.
		var fwd := Vector2(dir * 6.0 * s * swing, 0.0)
		ci.draw_line(hip, feet - fwd, pants.darkened(0.15), 4.5 * s)
		_foot(ci, feet - fwd, dir, s, shoe)
		ci.draw_line(hip, feet + fwd, pants, 4.8 * s)
		_foot(ci, feet + fwd, dir, s, shoe)
		ci.draw_colored_polygon(PackedVector2Array([hip + Vector2(-4.0 * s, 1.0 * s), hip + Vector2(4.0 * s, 1.0 * s),
			chest + Vector2(4.5 * s, -2.0 * s), chest + Vector2(-4.5 * s, -2.0 * s)]), shirt)
		var shoulder := chest + Vector2(dir * 1.0 * s, -1.0 * s)
		if holding:
			_arm(ci, shoulder, hold, shirt, skin, s)
		else:
			var hand := shoulder + Vector2(-dir * 5.0 * s * swing, 11.0 * s)
			_arm(ci, shoulder, hand, shirt, skin, s)
		var head := chest + Vector2(dir * 1.0 * s, -8.0 * s)
		disc(ci, head, 6.2 * s, skin)
		disc(ci, head + Vector2(-dir * 1.6 * s, -1.2 * s), 5.8 * s, hair)
		disc(ci, head + Vector2(dir * 2.2 * s, 0.8 * s), 4.2 * s, skin)
		disc(ci, head + Vector2(dir * 6.0 * s, 1.0 * s), 1.4 * s, skin.darkened(0.08))     # nose
		disc(ci, head + Vector2(dir * 3.2 * s, -0.6 * s), 0.9 * s, Color(0.1, 0.08, 0.08))
		_hat(ci, look, head, dir, s, true)
		return
	# Front or back view.
	var spread := 5.0 * s * swing
	ci.draw_line(hip + Vector2(-3.0 * s, 0.0), feet + Vector2(-3.0 * s, -absf(spread) * 0.3), pants, 4.5 * s)
	ci.draw_line(hip + Vector2(3.0 * s, 0.0), feet + Vector2(3.0 * s, -absf(spread) * 0.3), pants, 4.5 * s)
	disc(ci, feet + Vector2(-3.0 * s, -maxf(spread, 0.0) * 0.6), 2.4 * s, shoe)
	disc(ci, feet + Vector2(3.0 * s, minf(spread, 0.0) * 0.6), 2.4 * s, shoe)
	var back_view := not toward
	if holding and back_view:
		_arm(ci, chest + Vector2(-7.0 * s, -2.0 * s), hold, shirt, skin, s)
		_arm(ci, chest + Vector2(7.0 * s, -2.0 * s), hold + Vector2(2.0 * s, 4.0 * s), shirt, skin, s)
	ci.draw_colored_polygon(PackedVector2Array([hip + Vector2(-6.0 * s, 1.0 * s), hip + Vector2(6.0 * s, 1.0 * s),
		chest + Vector2(7.5 * s, -2.0 * s), chest + Vector2(-7.5 * s, -2.0 * s)]), shirt)
	if not holding:
		_arm(ci, chest + Vector2(-7.5 * s, -2.0 * s), chest + Vector2(-8.5 * s, 10.0 * s - spread * 0.5), shirt, skin, s)
		_arm(ci, chest + Vector2(7.5 * s, -2.0 * s), chest + Vector2(8.5 * s, 10.0 * s + spread * 0.5), shirt, skin, s)
	elif not back_view:
		_arm(ci, chest + Vector2(-7.0 * s, -2.0 * s), hold, shirt, skin, s)
		_arm(ci, chest + Vector2(7.0 * s, -2.0 * s), hold + Vector2(2.0 * s, 4.0 * s), shirt, skin, s)
	var head := chest + Vector2(0.0, -8.0 * s)
	disc(ci, head, 6.5 * s, skin)
	if toward:
		disc(ci, head + Vector2(0.0, -2.5 * s), 6.6 * s, hair)
		disc(ci, head + Vector2(0.0, 1.2 * s), 5.6 * s, skin)
		disc(ci, head + Vector2(-2.2 * s, 0.8 * s), 0.9 * s, Color(0.1, 0.08, 0.08))
		disc(ci, head + Vector2(2.2 * s, 0.8 * s), 0.9 * s, Color(0.1, 0.08, 0.08))
	else:
		disc(ci, head + Vector2(0.0, -0.5 * s), 6.4 * s, hair)
	_hat(ci, look, head, 0.0, s, false)


## Upper arm and forearm from the shoulder to the hand, with a sleeve and a hand.
static func _arm(ci: CanvasItem, shoulder: Vector2, hand: Vector2, shirt: Color, skin: Color, s: float) -> void:
	var elbow := shoulder.lerp(hand, 0.5) + Vector2(0.0, 3.0 * s)
	ci.draw_line(shoulder, elbow, shirt.darkened(0.12), 3.6 * s)
	ci.draw_line(elbow, hand, shirt.darkened(0.05), 3.2 * s)
	disc(ci, hand, 2.2 * s, skin)


static func _foot(ci: CanvasItem, at: Vector2, dir: float, s: float, col: Color) -> void:
	ci.draw_line(at + Vector2(-dir * 1.0 * s, 0.0), at + Vector2(dir * 3.5 * s, 0.0), col, 2.8 * s)


static func _hat(ci: CanvasItem, look: Dictionary, head: Vector2, dir: float, s: float, profile: bool) -> void:
	var hat: Variant = look.get("hat", null)
	if not (hat is Color):
		return
	var hc: Color = hat
	if profile:
		ci.draw_line(head + Vector2(-dir * 4.0 * s, -4.0 * s), head + Vector2(dir * 9.0 * s, -3.0 * s), hc.darkened(0.15), 2.2 * s)
	else:
		_ellipse(ci, head + Vector2(0.0, -4.0 * s), Vector2(8.5 * s, 2.6 * s), hc.darkened(0.15))
	disc(ci, head + Vector2(0.0, -5.0 * s), 5.2 * s, hc)


## A cat seen from the side: body, head with ears, tail curling on an oscillator.
static func draw_cat(ci: CanvasItem, pos: Vector2, dir: float, t: float, col: Color) -> void:
	_ellipse(ci, pos + Vector2(0.0, 2.0), Vector2(9.0, 3.0), Color(0.0, 0.0, 0.0, 0.2))
	var body := pos + Vector2(0.0, -6.0)
	_ellipse(ci, body, Vector2(8.0, 4.5), col)
	ci.draw_line(body + Vector2(-5.0, 2.0), pos + Vector2(-5.0, 0.0), col.darkened(0.1), 2.0)
	ci.draw_line(body + Vector2(5.0, 2.0), pos + Vector2(5.0, 0.0), col.darkened(0.1), 2.0)
	var head := body + Vector2(dir * 8.0, -3.0)
	disc(ci, head, 4.0, col)
	ci.draw_colored_polygon(PackedVector2Array([head + Vector2(-3.0, -2.0), head + Vector2(-2.0, -6.0), head + Vector2(0.0, -3.0)]), col)
	ci.draw_colored_polygon(PackedVector2Array([head + Vector2(3.0, -2.0), head + Vector2(2.0, -6.0), head + Vector2(0.0, -3.0)]), col)
	var tail_base := body + Vector2(-dir * 7.0, -1.0)
	var tail_tip := tail_base + Vector2(-dir * 6.0, -8.0 + sin(t * 3.0) * 3.0)
	ci.draw_line(tail_base, tail_tip, col.darkened(0.15), 2.0)


## Circles and ellipses are one white disc texture stretched and tinted: a textured rect instead of a
## 12-64 point polygon. Rects that share a texture can be batched by the renderer, and the disc has a
## soft 1 px edge, so heads and shadows look smoother too. (Performance review, 2026-11-08.)
static var _disc_tex: Texture2D


static func disc_texture() -> Texture2D:
	if _disc_tex == null:
		_disc_tex = load("res://assets/art/ui/disc.png") as Texture2D
	return _disc_tex


static func disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	_ellipse(ci, c, Vector2(r, r), col)


static func _ellipse(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	if _disc_tex == null:
		_disc_tex = load("res://assets/art/ui/disc.png") as Texture2D
	if _disc_tex == null:
		var pts := PackedVector2Array()
		for i in 12:
			var a := TAU * float(i) / 12.0
			pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
		ci.draw_colored_polygon(pts, col)
		return
	ci.draw_texture_rect(_disc_tex, Rect2(c - r, r * 2.0), false, col)
