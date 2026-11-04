## Marine weather dashboard: compass with the wind arrow, wind speed in knots + Beaufort, wind heading,
## wave height/amplitude, barometer, bite multiplier and a live wave scope along the swell direction.
## Add it anywhere under a CanvasLayer; it docks itself top-right.
class_name WeatherDashboard
extends Control

@export var weather: WeatherManager
@export var boat: Boat
@export var wave_physics: BoatWavePhysics
@export var width_px := 310.0
@export var height_px := 196.0
@export var margin_px := 16.0

var _flash_s := 0.0
var _flash_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -width_px - margin_px
	offset_right = -margin_px
	offset_top = margin_px
	offset_bottom = margin_px + height_px
	if weather:
		weather.state_changed.connect(_on_state_changed)


func _on_state_changed(new_state: int, old_state: int) -> void:
	var worse := new_state > old_state
	_flash_text = ("WEATHER WARNING: " if worse else "Weather easing: ") + String(WeatherManager.STATE_NAMES[new_state])
	_flash_s = 4.0


func _process(delta: float) -> void:
	_flash_s = maxf(_flash_s - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.12, 0.86))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.55, 0.70, 0.9), false, 1.5)
	if weather == null:
		return
	var font := ThemeDB.fallback_font
	var state_col := weather.state_color()
	var txt := Color(0.85, 0.95, 1.0)

	draw_string(font, Vector2(12.0, 21.0), weather.state_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, state_col)

	# compass rose with the wind arrow (points where the wind blows TO)
	var c := Vector2(58.0, 92.0)
	var r := 38.0
	draw_arc(c, r, 0.0, TAU, 48, Color(0.5, 0.75, 0.9, 0.8), 1.5)
	for k in 8:
		var a := float(k) * TAU / 8.0
		var d := Vector2.UP.rotated(a)
		draw_line(c + d * (r - 5.0), c + d * r, Color(0.5, 0.75, 0.9, 0.8), 1.0)
	draw_string(font, c + Vector2(-4.0, -r - 3.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt)
	draw_string(font, c + Vector2(r + 4.0, 4.0), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt)
	draw_string(font, c + Vector2(-4.0, r + 13.0), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt)
	draw_string(font, c + Vector2(-r - 13.0, 4.0), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt)
	var dir := weather.wind_dir
	var side := Vector2(-dir.y, dir.x)
	var head := c + dir * (r * 0.8)
	draw_line(c - dir * (r * 0.8), head, state_col, 3.0)
	draw_colored_polygon(PackedVector2Array([head + dir * 8.0, head - dir * 6.0 + side * 6.0, head - dir * 6.0 - side * 6.0]), state_col)

	# readouts
	var x := 112.0
	draw_string(font, Vector2(x, 52.0), "WIND   %.1f kn   Bft %d" % [weather.wind_knots, weather.beaufort()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)
	draw_string(font, Vector2(x, 72.0), "FROM   %03.0f deg   %s" % [weather.wind_from_deg, weather.wind_from_cardinal()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)
	draw_string(font, Vector2(x, 92.0), "WAVES  Hs %.1f m   amp %.1f m" % [weather.sea_hs_m, weather.wave_amplitude_m], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)
	draw_string(font, Vector2(x, 112.0), "BARO   %.0f hPa   %s" % [weather.pressure_hpa, weather.pressure_trend], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)
	draw_string(font, Vector2(x, 132.0), "FISH BITE  x%.2f" % weather.bite_multiplier(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt)

	# wave scope: sea surface profile along the swell direction through the boat
	var x0 := 12.0
	var x1 := size.x - 12.0
	var mid := size.y - 26.0
	draw_line(Vector2(x0, mid), Vector2(x1, mid), Color(0.4, 0.6, 0.75, 0.5), 1.0)
	var origin := boat.global_position if boat else Vector2.ZERO
	var pts := PackedVector2Array()
	for k in 41:
		var u := float(k) / 40.0
		var h := weather.wave_height_m(origin + weather.swell_dir * lerpf(-70.0, 70.0, u) * weather.px_per_m)
		pts.append(Vector2(lerpf(x0, x1, u), mid - clampf(h / 6.0, -1.0, 1.0) * 14.0))
	draw_polyline(pts, Color(0.5, 0.85, 1.0), 2.0)
	var bx := (x0 + x1) * 0.5
	draw_circle(Vector2(bx, pts[20].y), 3.5, Color.WHITE)

	var foot := "Boat heave %+.1f m" % weather.wave_height_m(origin)
	if wave_physics:
		foot = "ANCHOR %s   %.0f / %.0f N   heave %+.1f m" % ["DOWN" if wave_physics.anchored else "UP", wave_physics.anchor_tension_n, wave_physics.anchor_hold_n, wave_physics.heave_m]
	draw_string(font, Vector2(12.0, size.y - 6.0), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.85, 0.95))

	if _flash_s > 0.0:
		var a := clampf(_flash_s, 0.0, 1.0)
		draw_string(font, Vector2(12.0, 38.0), _flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.85, 0.4, a))
