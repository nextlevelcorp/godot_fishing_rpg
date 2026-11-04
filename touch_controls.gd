## On-screen touch buttons for phones and tablets.
## Each button fires the same input action the keyboard uses (boat_forward, reel_in, ...),
## so no gameplay script needs to know whether the input came from a finger or a key.
## Multi-touch is handled: two fingers can hold throttle and steer at once.
## Button positions are in the 1280x720 design space; they are mapped to the real screen
## through the viewport transform, so they track the window size.
class_name TouchControls
extends CanvasLayer

const BUTTONS := [
	# [action, label, center_x, center_y, radius] in design coordinates (1280 x 720).
	# Left cluster: boat.
	[&"boat_forward", "^", 110.0, 430.0, 60.0],
	[&"steer_left", "<", 60.0, 580.0, 55.0],
	[&"steer_right", ">", 200.0, 580.0, 55.0],
	[&"boat_back", "v", 110.0, 690.0, 40.0],
	# Right cluster: fishing.
	[&"reel_in", "REEL", 1100.0, 600.0, 80.0],
	[&"cast", "CAST", 1100.0, 430.0, 55.0],
	[&"anchor", "ANCH", 960.0, 690.0, 45.0],
	[&"drag_up", "DRAG+", 960.0, 380.0, 38.0],
	[&"drag_down", "DRAG-", 960.0, 470.0, 38.0],
	[&"bait_deeper", "DEEP", 1200.0, 330.0, 36.0],
	[&"bait_shallower", "SHAL", 1200.0, 250.0, 36.0],
]

## Finger index -> index into BUTTONS, for the touch that is currently holding it.
var _held: Dictionary = {}
var _pad: Control


func _ready() -> void:
	layer = 10
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	add_child(_pad)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var idx := _button_at_screen(event.position)
			if idx >= 0 and not _held.values().has(idx):
				_held[event.index] = idx
				_set_action(BUTTONS[idx][0], true)
				_pad.queue_redraw()
				get_viewport().set_input_as_handled()
		elif _held.has(event.index):
			_set_action(BUTTONS[_held[event.index]][0], false)
			_held.erase(event.index)
			_pad.queue_redraw()
			get_viewport().set_input_as_handled()


func _set_action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


## Maps a screen position to a button index, or -1.
func _button_at_screen(screen_pos: Vector2) -> int:
	var xf := get_viewport().get_final_transform()
	var scale_factor := xf.get_scale().x
	for i in BUTTONS.size():
		var b: Array = BUTTONS[i]
		var center := xf * Vector2(b[2], b[3])
		var radius: float = b[4] * scale_factor
		if screen_pos.distance_to(center) <= radius * 1.15:
			return i
	return -1


func _draw_pad() -> void:
	var font := ThemeDB.fallback_font
	var held_set := _held.values()
	for i in BUTTONS.size():
		var b: Array = BUTTONS[i]
		var center := Vector2(b[2], b[3])
		var radius: float = b[4]
		var lit := held_set.has(i)
		_pad.draw_circle(center, radius, Color(1, 1, 1, 0.35 if lit else 0.18))
		_pad.draw_arc(center, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 2.0)
		var size := 18 if String(b[1]).length() <= 2 else 14
		var text_w := font.get_string_size(b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_pad.draw_string(font, center + Vector2(-text_w * 0.5, size * 0.35), b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.85))
