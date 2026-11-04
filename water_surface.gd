## Attach to a ColorRect (child of a Node2D). Keeps the rect covering the camera, records the boat's
## wake trail and feeds the nightshoal_water shader. Set `shader` (or it loads res://nightshoal_water.gdshader).
## The shader works in world space, so the rect simply follows the camera.
class_name WaterSurface
extends ColorRect

const MAX_POINTS := 32

@export var boat: Boat
@export var camera: Camera2D
@export var weather: WeatherManager          ## optional: waves, whitecaps and darkness follow the weather
@export var shader: Shader
@export var sample_distance_px := 14.0
@export var trail_lifetime_s := 6.0
@export var min_wake_speed01 := 0.04
@export var overscan := 1.15

var _points: Array[Vector2] = []     # history, newest first (live boat point is added when uploading)
var _ages: Array[float] = []
var _powers: Array[float] = []
var _mat: ShaderMaterial


func _ready() -> void:
	if shader == null:
		shader = load("res://nightshoal_water.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	material = _mat
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -100
	_mat.set_shader_parameter("trail_lifetime", trail_lifetime_s)


func _process(delta: float) -> void:
	_cover_camera()
	if weather:
		_mat.set_shader_parameter("storm", weather.turbulence01)
		_mat.set_shader_parameter("wind_dir", weather.wind_dir)
	if boat:
		_update_wake(delta)


func set_daylight(value: float) -> void:
	_mat.set_shader_parameter("daylight", value)


func set_sun(direction: Vector2, elevation: float) -> void:
	_mat.set_shader_parameter("sun_direction", direction)
	_mat.set_shader_parameter("sun_elevation", elevation)


func _cover_camera() -> void:
	var view := get_viewport_rect().size
	var center := global_position + size * 0.5
	var zoom := Vector2.ONE
	if camera:
		center = camera.get_screen_center_position()
		zoom = camera.zoom
	size = view / zoom * overscan
	global_position = center - size * 0.5


func _update_wake(delta: float) -> void:
	for i in _ages.size():
		_ages[i] += delta
	while not _ages.is_empty() and _ages[_ages.size() - 1] > trail_lifetime_s:
		_points.pop_back()
		_ages.pop_back()
		_powers.pop_back()

	var pos := boat.global_position
	if boat.speed01 > min_wake_speed01 and (_points.is_empty() or pos.distance_to(_points[0]) >= sample_distance_px):
		_points.push_front(pos)
		_ages.push_front(0.0)
		_powers.push_front(boat.speed01)

	var pts := PackedVector2Array()
	var ages := PackedFloat32Array()
	var pows := PackedFloat32Array()
	pts.resize(MAX_POINTS)
	ages.resize(MAX_POINTS)
	pows.resize(MAX_POINTS)
	var count := 0
	if boat.speed01 > min_wake_speed01 or not _points.is_empty():
		pts[0] = pos                       # live head of the trail
		ages[0] = 0.0
		pows[0] = boat.speed01
		count = 1
		for i in mini(_points.size(), MAX_POINTS - 1):
			pts[count] = _points[i]
			ages[count] = _ages[i]
			pows[count] = _powers[i]
			count += 1

	_mat.set_shader_parameter("boat_pos", pos)
	_mat.set_shader_parameter("boat_dir", boat.heading)
	_mat.set_shader_parameter("boat_speed01", boat.speed01)
	_mat.set_shader_parameter("trail_count", count)
	_mat.set_shader_parameter("trail_points", pts)
	_mat.set_shader_parameter("trail_ages", ages)
	_mat.set_shader_parameter("trail_power", pows)
