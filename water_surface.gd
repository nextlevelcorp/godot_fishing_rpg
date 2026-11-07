## Attach to a ColorRect (child of a Node2D). Keeps the rect covering the camera and feeds the
## nightshoal_water shader. Set `shader` (or it loads res://nightshoal_water.gdshader).
## The shader works in world space, so the rect simply follows the camera.
class_name WaterSurface
extends ColorRect

@export var camera: Camera2D
@export var weather: WeatherManager          ## optional: waves, whitecaps and darkness follow the weather
@export var shader: Shader
@export var overscan := 1.15

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


func _process(_delta: float) -> void:
	_cover_camera()
	if weather:
		_mat.set_shader_parameter("storm", weather.turbulence01)
		_mat.set_shader_parameter("wind_dir", weather.wind_dir)


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
