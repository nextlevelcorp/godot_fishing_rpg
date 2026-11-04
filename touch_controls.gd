## On-screen touch buttons for phones and tablets.
## Each button presses the same input action the keyboard uses (cast, reel_in, steer_left, ...),
## so gameplay scripts do not care whether input came from a finger or a key.
##
## The buttons are GUI Controls, not a raw _input handler: on some mobile browsers raw _input
## never sees the touch, while the GUI (the path every Button on the map uses) always does.
## Godot's GUI gives each finger its own touch focus, so two buttons can be held at once.
## Positions are in the 1280x720 design space, the same space Controls are laid out in.
class_name TouchControls
extends CanvasLayer

## Buttons are drawn and hit-tested at this multiple of the listed radius, so thumbs can reach them.
const TOUCH_SCALE := 1.35

const BUTTONS := [
	# [action, label, center_x, center_y, radius] in design coordinates (1280 x 720).
	# Left cluster: boat / aiming.
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

## Action -> how many times a button for it has been pressed. Scenes compare this counter with
## the value they saw last frame, so a tap shorter than a frame is never lost.
static var presses: Dictionary = {}

## Only these actions get a button. Empty = all. Set before the node enters the tree.
var enabled_actions: Array[StringName] = []

var _root: Control


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for b: Array in BUTTONS:
		var action: StringName = b[0]
		if not (enabled_actions.is_empty() or enabled_actions.has(action)):
			continue
		var btn := TouchButton.new()
		btn.action = action
		btn.label = b[1]
		btn.radius = float(b[4]) * TOUCH_SCALE
		btn.position = Vector2(b[2], b[3]) - Vector2.ONE * btn.radius
		btn.size = Vector2.ONE * btn.radius * 2.0
		_root.add_child(btn)


## One round button. Handles touch (per finger) and mouse (desktop, or browsers that turn touches
## into mouse events). If a tap arrives both ways, the second press finds the button already down.
class TouchButton extends Control:
	const MOUSE_ID := 1000

	var action: StringName
	var label := ""
	var radius := 50.0
	var _pointers: Dictionary = {}       # pointer id -> true while it holds this button
	var _tap := Vector2.ZERO
	var _tap_age := 99.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _has_point(point: Vector2) -> bool:
		return point.distance_to(size * 0.5) <= radius * 1.15

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			_pointer(event.index, event.position, event.pressed)
			accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_pointer(MOUSE_ID, event.position, event.pressed)
			accept_event()

	func _pointer(id: int, pos: Vector2, pressed: bool) -> void:
		if pressed:
			_tap = pos
			_tap_age = 0.0
			if _pointers.is_empty():
				TouchControls.presses[action] = int(TouchControls.presses.get(action, 0)) + 1
				_set_action(true)
			_pointers[id] = true
		elif _pointers.has(id):
			_pointers.erase(id)
			if _pointers.is_empty():
				_set_action(false)
		queue_redraw()

	## Sets the action's state (read by Input.get_axis / is_action_pressed) and also sends the
	## event (read by _unhandled_input handlers such as the boat sandbox's cast).
	func _set_action(down: bool) -> void:
		if down:
			Input.action_press(action, 1.0)
		else:
			Input.action_release(action)
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		ev.strength = 1.0 if down else 0.0
		Input.parse_input_event(ev)

	func _process(delta: float) -> void:
		if _tap_age < 0.5:
			_tap_age += delta
			queue_redraw()

	func _notification(what: int) -> void:
		# Losing the window or the node mid-press must not leave the action stuck down.
		if (what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT) and not _pointers.is_empty():
			_pointers.clear()
			_set_action(false)

	func _draw() -> void:
		var c := size * 0.5
		var lit := not _pointers.is_empty()
		draw_circle(c, radius, Color(1, 1, 1, 0.45 if lit else 0.22))
		draw_arc(c, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.85), 3.0)
		var font := ThemeDB.fallback_font
		var fs := 26 if label.length() <= 2 else 20
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
		if _tap_age < 0.5:
			var k := _tap_age / 0.5
			draw_arc(_tap, 14.0 + k * 22.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.3, 0.95 * (1.0 - k)), 3.0)
