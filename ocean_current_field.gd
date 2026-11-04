## Procedural global ocean fields from Perlin noise (Nature of Code flow field).
## current:  angle = 2*pi * noise, magnitude from a second noise  -> px/s
## wind:     same idea at a lower frequency                        -> px/s
## thermal:  0..1 water temperature proxy used by fish AI
class_name OceanCurrentField
extends Node

@export var world_seed := 1337
@export var current_frequency := 0.00035   ## noise cycles per pixel
@export var wind_frequency := 0.00015
@export var thermal_frequency := 0.00022
@export var evolve_speed := 0.03           ## how fast the fields slowly change over time
@export var max_current_px_s := 30.0
@export var max_wind_px_s := 20.0

var _angle_noise := FastNoiseLite.new()
var _speed_noise := FastNoiseLite.new()
var _wind_angle_noise := FastNoiseLite.new()
var _wind_speed_noise := FastNoiseLite.new()
var _thermal_noise := FastNoiseLite.new()
var _time := 0.0


func _ready() -> void:
	var i := 0
	for n: FastNoiseLite in [_angle_noise, _speed_noise, _wind_angle_noise, _wind_speed_noise, _thermal_noise]:
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.frequency = 1.0                   # positions are pre-scaled below
		n.seed = world_seed + i * 101
		i += 1


func _process(delta: float) -> void:
	_time += delta * evolve_speed


## Water current at a world position, in px/s.
func get_current(pos: Vector2) -> Vector2:
	var q := pos * current_frequency
	var angle := _angle_noise.get_noise_3d(q.x, q.y, _time) * TAU * 1.6
	var strength := lerpf(0.25, 1.0, clampf(_speed_noise.get_noise_3d(q.x + 71.0, q.y - 33.0, _time) * 1.5 * 0.5 + 0.5, 0.0, 1.0))
	return Vector2.from_angle(angle) * strength * max_current_px_s


## Wind at a world position, in px/s.
func get_wind(pos: Vector2) -> Vector2:
	var q := pos * wind_frequency
	var angle := _wind_angle_noise.get_noise_3d(q.x, q.y, _time * 1.7) * TAU * 1.6
	var strength := lerpf(0.2, 1.0, clampf(_wind_speed_noise.get_noise_3d(q.x - 19.0, q.y + 54.0, _time * 1.7) * 1.5 * 0.5 + 0.5, 0.0, 1.0))
	return Vector2.from_angle(angle) * strength * max_wind_px_s


## Normalised water temperature 0 (coldest) .. 1 (warmest).
func get_temperature_norm(pos: Vector2) -> float:
	var q := pos * thermal_frequency
	return clampf(_thermal_noise.get_noise_3d(q.x, q.y, _time * 0.5) * 1.5 * 0.5 + 0.5, 0.0, 1.0)
