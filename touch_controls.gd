## On-screen touch buttons for phones and tablets.
## Each button fires the same input action the keyboard uses (boat_forward, reel_in, ...),
## so no gameplay script needs to know whether the input came from a finger or a key.
## Multi-touch is handled: two fingers can hold throttle and steer at once.
## Button positions are in the 1280x720 design space; they are mapped to the real screen
## through the viewport transform, so they track the window size.
class_name TouchControls
extends CanvasLayer

## Buttons are drawn and hit-tested at this multiple of the listed radius, so thumbs can reach them.
const TOUCH_SCALE := 1.35

const BUTTONS := [
	# [action, label, center_x, center_y, radius] in design coordinates (1280 x 720).
	# Left cluster: boat.
	[&"boat_forward", "^", 110.0, 430.0, 60.0],
	[&"steer_left", "<", 60.0, 580.0, 55.0],
	[&"steer_right", ">", 200.0, 580.0, 55.0],
	[&"boat_back", "v", 110.0, 690.0, 40.0],
	# Right cluster: fishing.
	[&"reel_in", "REEL", 1100.0, 600.0, 80.0],
	[&"cast", "CAST", 1100.0, 400.0, 55.0],
	[&"anchor", "ANCH", 940.0, 695.0, 45.0],
	[&"drag_up", "DRAG+", 940.0, 350.0, 38.0],
	[&"drag_down", "DRAG-", 960.0, 470.0, 38.0],
	[&"bait_deeper", "DEEP", 1210.0, 300.0, 36.0],
	[&"bait_shallower", "SHAL", 1210.0, 220.0, 36.0],
]

## Only these actions get a button. Empty = show all. Set before the node enters the tree.
var enabled_actions: Array[StringName] = []

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


## Sets the action's state (read by Input.get_axis / is_action_pressed in the gameplay scripts)
## and also sends the event (read by _unhandled_input handlers such as cast).
func _set_action(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action, 1.0)
	else:
		Input.action_release(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _is_enabled(action: StringName) -> bool:
	return enabled_actions.is_empty() or enabled_actions.has(action)


## Maps a screen position to a button index, or -1.
func _button_at_screen(screen_pos: Vector2) -> int:
	var xf := get_viewport().get_final_transform()
	var scale_factor := xf.get_scale().x
	for i in BUTTONS.size():
		var b: Array = BUTTONS[i]
		if not _is_enabled(b[0]):
			continue
		var center := xf * Vector2(b[2], b[3])
		var radius: float = b[4] * TOUCH_SCALE * scale_factor
		if screen_pos.distance_to(center) <= radius * 1.2:
			return i
	return -1


func _draw_pad() -> void:
	var font := ThemeDB.fallback_font
	var held_set := _held.values()
	for i in BUTTONS.size():
		var b: Array = BUTTONS[i]
		if not _is_enabled(b[0]):
			continue
		var center := Vector2(b[2], b[3])
		var radius: float = b[4] * TOUCH_SCALE
		var lit := held_set.has(i)
		_pad.draw_circle(center, radius, Color(1, 1, 1, 0.45 if lit else 0.25))
		_pad.draw_arc(center, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 3.0)
		var size := 26 if String(b[1]).length() <= 2 else 20
		var text_w := font.get_string_size(b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_pad.draw_string(font, center + Vector2(-text_w * 0.5, size * 0.35), b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.85))
