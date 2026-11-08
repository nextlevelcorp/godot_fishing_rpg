## One look for every button and panel: deep-sea navy with a warm gold edge, rounded corners, and a
## gold fill when pressed. Built in code (no .tres) and set on each screen's root Control, so every
## Button and PanelContainer below it uses it unless it sets its own style.
class_name UiTheme
extends RefCounted

const NAVY := Color(0.09, 0.24, 0.36)
const NAVY_HOVER := Color(0.13, 0.32, 0.46)
const GOLD := Color(0.95, 0.75, 0.30)
const EDGE := Color(1.0, 0.85, 0.40, 0.60)
const PANEL := Color(0.02, 0.10, 0.18, 0.95)

static var _cached: Theme


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	t.set_stylebox("normal", "Button", _box(NAVY, EDGE))
	t.set_stylebox("hover", "Button", _box(NAVY_HOVER, EDGE))
	t.set_stylebox("pressed", "Button", _box(GOLD, GOLD.lightened(0.2)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _box(Color(0.12, 0.16, 0.20, 0.8), Color(1.0, 1.0, 1.0, 0.15)))
	t.set_color("font_color", "Button", Color(0.96, 0.97, 1.0))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.10, 0.08, 0.04))
	t.set_color("font_disabled_color", "Button", Color(1.0, 1.0, 1.0, 0.35))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, EDGE, 18))
	_cached = t
	return t


static func _box(bg: Color, edge: Color, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb
