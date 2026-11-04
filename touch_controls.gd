## On-screen touch buttons for phones and tablets.
## Each button fires the same input action the keyboard uses (boat_forward, reel_in, ...),
## so no gameplay script needs to know whether the input came from a finger or a key.
## Multi-touch is handled: two fingers can hold throttle and steer at once.
## Button positions are in the 1280x720 design space. Godot maps touches into the same space,
## so the buttons track the window size with no extra conversion.
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

## Pointer id used for mouse clicks (and for touches the browser only reports as mouse events).
const MOUSE_ID := 1000

## Action -> how many times a button for it has been pressed. Scenes compare this counter with the
## value they saw last frame, so a quick tap is never missed between two physics frames.
static var presses: Dictionary = {}

## Pointer id (finger index or MOUSE_ID) -> index into BUTTONS, for the pointer holding it.
var _held: Dictionary = {}
var _pad: Control
var _tap_pos := Vector2.ZERO
var _tap_age := 99.0


func _ready() -> void:
	layer = 10
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	add_child(_pad)


func _process(delta: float) -> void:
	if _tap_age < 0.6:
		_tap_age += delta
		_pad.queue_redraw()


## Touches arrive as InputEventScreenTouch on most phones; some browsers (and every desktop)
## deliver mouse events instead. Both go through the same path. If one tap produces both, the
## second press finds the button already held and is ignored, and its release is a no-op.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_pointer(event.index, event.position, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer(MOUSE_ID, event.position, event.pressed)


func _pointer(id: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		_tap_pos = pos
		_tap_age = 0.0
		_pad.queue_redraw()
		var idx := _button_at(pos)
		if idx >= 0 and not _held.values().has(idx):
			_held[id] = idx
			var action: StringName = BUTTONS[idx][0]
			presses[action] = int(presses.get(action, 0)) + 1
			_set_action(action, true)
			get_viewport().set_input_as_handled()
	elif _held.has(id):
		_set_action(BUTTONS[_held[id]][0], false)
		_held.erase(id)
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


## Maps a touch position to a button index, or -1.
## Godot already maps touches into the 1280x720 design space before _input (the window's stretch
## transform is undone), so the table's coordinates compare directly. The second test, through the
## inverse viewport transform, covers the case where a touch arrives in raw window pixels.
func _button_at(pos: Vector2) -> int:
	var alt := get_viewport().get_final_transform().affine_inverse() * pos
	for i in BUTTONS.size():
		var b: Array = BUTTONS[i]
		if not _is_enabled(b[0]):
			continue
		var center := Vector2(b[2], b[3])
		var reach: float = b[4] * TOUCH_SCALE * 1.2
		if pos.distance_to(center) <= reach or alt.distance_to(center) <= reach:
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
	# Tap marker: shows where the game thinks the finger landed. If it is not under the finger,
	# touch coordinates are being mapped wrongly on this device.
	if _tap_age < 0.6:
		var k := _tap_age / 0.6
		_pad.draw_arc(_tap_pos, 18.0 + k * 26.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.3, 0.9 * (1.0 - k)), 3.0)
