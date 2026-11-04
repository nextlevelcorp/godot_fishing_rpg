## Drives CanvasModulate (global tint), Light2D energy and the water shader's sun/daylight.
## time_of_day: 0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
class_name DayNightCycle
extends Node

@export var canvas_modulate: CanvasModulate
@export var water: WaterSurface
@export var weather: WeatherManager       ## optional: clouds dim the sun, storms tint the world grey
@export var storm_tint := Color(0.55, 0.60, 0.70)
@export var lights: Array[Light2D] = []   ## lamps etc: full energy at night, off by day
@export var day_length_s := 240.0
@export_range(0.0, 1.0) var time_of_day := 0.30
@export var day_color := Color(1.0, 1.0, 1.0)
@export var dusk_color := Color(1.0, 0.66, 0.50)
@export var night_color := Color(0.16, 0.20, 0.42)


func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / day_length_s, 1.0)
	var sun := sin((time_of_day - 0.25) * TAU)               # -1 midnight .. +1 noon
	var daylight := smoothstep(-0.15, 0.35, sun)
	var dusk := 1.0 - smoothstep(0.0, 0.35, absf(sun))

	if canvas_modulate:
		var c := night_color.lerp(day_color, daylight)
		var tint := c.lerp(dusk_color, dusk * 0.6)
		if weather:
			tint = tint.lerp(tint * storm_tint, clampf(weather.turbulence01 * 0.8 + weather.cloud01 * 0.3, 0.0, 1.0))
		canvas_modulate.color = tint
	for l in lights:
		l.energy = 1.0 - daylight
	if water:
		var sun_angle := (time_of_day - 0.25) * TAU
		water.set_daylight(daylight * (lerpf(1.0, 0.35, weather.cloud01) if weather else 1.0))
		water.set_sun(Vector2(cos(sun_angle), -0.6), maxf(sun, 0.12))
