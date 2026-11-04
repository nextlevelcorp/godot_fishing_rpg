## Radar screen widget. Put it under a CanvasLayer (or any Control); it docks itself bottom-right.
## Reads SonarSystem.contacts, so what it shows depends on the sonar tier:
##   tier 0 raw green blips | tier 1 coloured blips sized by Small/Medium/Trophy | tier 2 + depth label
class_name SonarDisplay
extends Control

@export var sonar: SonarSystem
@export var boat: Boat
@export var fish_ai: FishInteractionAI
@export var diameter_px := 240.0
@export var margin_px := 16.0
@export var heading_up := false            ## true = rotate the scope so the bow points up
@export var dock_left := false             ## true = bottom-left corner instead of bottom-right

const SIZE_NAMES := ["Small", "Medium", "Trophy"]
const SIZE_COLORS := [Color(0.55, 1.0, 0.65), Color(1.0, 0.9, 0.35), Color(1.0, 0.45, 0.35)]
const GREEN := Color(0.30, 0.90, 0.60)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := 0.0 if dock_left else 1.0
	anchor_left = side
	anchor_right = side
	anchor_top = 1.0
	anchor_bottom = 1.0
	if dock_left:
		offset_left = margin_px
		offset_right = margin_px + diameter_px
	else:
		offset_left = -diameter_px - margin_px
		offset_right = -margin_px
	offset_top = -diameter_px - margin_px
	offset_bottom = -margin_px


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c, r, Color(0.02, 0.09, 0.07, 0.88))
	for k in 3:
		draw_arc(c, r * float(k + 1) / 3.0, 0.0, TAU, 48, Color(GREEN, 0.30), 1.0)
	draw_line(c + Vector2(-r, 0.0), c + Vector2(r, 0.0), Color(GREEN, 0.20), 1.0)
	draw_line(c + Vector2(0.0, -r), c + Vector2(0.0, r), Color(GREEN, 0.20), 1.0)
	draw_arc(c, r, 0.0, TAU, 64, Color(GREEN, 0.85), 2.0)
	if sonar == null:
		return

	var font := ThemeDB.fallback_font
	var px_scale := r / sonar.range_px
	var origin := boat.global_position if boat else Vector2.ZERO
	var rot := 0.0
	if heading_up and boat:
		rot = -(boat.heading.angle() + PI * 0.5)

	if sonar.pulse_active:
		draw_arc(c, sonar.pulse_radius * px_scale, 0.0, TAU, 64, Color(0.6, 1.0, 0.75, 0.8), 2.0)

	for ct in sonar.contacts:
		var rel: Vector2 = ((ct["pos"] as Vector2) - origin).rotated(rot) * px_scale
		if rel.length() > r:
			continue
		var fade := clampf(1.0 - float(ct["age"]) / sonar.contact_life_s, 0.0, 1.0)
		if sonar.detail == 0:
			draw_circle(c + rel, 3.0, Color(GREEN, fade))
			continue
		var sc := int(ct["size"])
		var col: Color = SIZE_COLORS[sc]
		col.a = fade
		var radius := 3.0 + 2.5 * float(sc)
		draw_circle(c + rel, radius, col)
		var label: String = SIZE_NAMES[sc]
		if sonar.detail >= 2:
			label += " %.0f m" % float(ct["depth"])
		draw_string(font, c + rel + Vector2(radius + 3.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

	# bait marker
	if fish_ai and fish_ai.state != FishInteractionAI.State.IDLE:
		var b := (fish_ai.bait_pos - origin).rotated(rot) * px_scale
		if b.length() <= r:
			var p := c + b
			draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), Color.WHITE, 2.0)
			draw_line(p + Vector2(-4, 4), p + Vector2(4, -4), Color.WHITE, 2.0)

	# boat marker and bow tick
	draw_circle(c, 3.0, Color.WHITE)
	var bow := Vector2.UP if heading_up or boat == null else boat.heading.rotated(rot)
	draw_line(c, c + bow * 10.0, Color.WHITE, 2.0)

	var eff := sonar.last_efficiency_pct
	var eff_text := "--" if eff < 0.0 else "%.0f%%" % eff
	draw_string(font, Vector2(10.0, size.y - 10.0), "%s   PING EFF %s" % [sonar.tier_name, eff_text], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(GREEN, 0.95))
