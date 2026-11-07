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
	# Left cluster: boat / aiming (legacy boat game).
	[&"boat_forward", "^", 110.0, 430.0, 60.0],
	[&"steer_left", "<", 60.0, 580.0, 55.0],
	[&"steer_right", ">", 200.0, 580.0, 55.0],
	[&"boat_back", "v", 110.0, 690.0, 40.0],
	# Right side: fishing. Kept at least 130 px from the right edge and 70 px from the bottom, away
	# from notches, rounded corners and browser toolbars. Two small columns sit left of CAST/REEL.
	[&"cast", "CAST", 1090.0, 360.0, 52.0],
	[&"reel_in", "REEL", 1090.0, 535.0, 66.0],
	[&"drag_up", "CLUTCH+", 945.0, 440.0, 36.0],
	[&"drag_down", "CLUTCH-", 945.0, 555.0, 36.0],
	[&"bait_deeper", "DEEP", 810.0, 440.0, 36.0],
	[&"bait_shallower", "SHAL", 810.0, 555.0, 36.0],
	[&"anchor", "ANCH", 945.0, 325.0, 40.0],
]

## Button art: Kenney Mobile Controls (CC0), assets/kenney_mobile_controls/.
## action -> [plate sprite, icon sprite or "", icon rotation in radians]. icon_arrow points right.
const ART_DIR := "res://assets/kenney_mobile_controls/"
const VISUALS := {
	&"boat_forward": ["button_circle", "icon_arrow", -PI * 0.5],
	&"boat_back": ["button_circle", "icon_arrow", PI * 0.5],
	&"steer_left": ["direction_left", "", 0.0],
	&"steer_right": ["direction_right", "", 0.0],
	&"reel_in": ["button_circle", "icon_arrow_rotate", 0.0],
	&"cast": ["button_circle", "icon_arrow_curved", 0.0],
	&"anchor": ["button_circle", "icon_hand", 0.0],
	&"drag_up": ["button_circle", "icon_size_larger", 0.0],
	&"drag_down": ["button_circle", "icon_size_smaller", 0.0],
	&"bait_deeper": ["button_circle", "icon_arrow", PI * 0.5],
	&"bait_shallower": ["button_circle", "icon_arrow", -PI * 0.5],
}

## Action -> how many times a button for it has been pressed. Scenes compare this counter with
## the value they saw last frame, so a tap shorter than a frame is never lost.
static var presses: Dictionary = {}

## Only these actions get a button. Empty = all. Set before the node enters the tree.
var enabled_actions: Array[StringName] = []
## Adds an analog joystick at the bottom left that drives steer_left/right and boat_forward/back
## with strength (walking in the shore scene). Set before the node enters the tree.
var joystick := false

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
		_pin(btn, Vector2(b[2], b[3]) - Vector2.ONE * btn.radius, Vector2.ONE * btn.radius * 2.0)
		var look: Array = VISUALS.get(action, ["button_circle", "", 0.0])
		btn.plate = _load_art(look[0])
		btn.icon = _load_art(look[1])
		btn.icon_rot = look[2]
		_root.add_child(btn)
	if joystick:
		_add_joystick()


## Builds the joystick if requested. Called at the end of _ready.
func _add_joystick() -> void:
	var j := TouchJoystick.new()
	j.radius = 105.0
	j.pad = _load_art("joystick_circle_pad_a")
	j.nub = _load_art("joystick_circle_nub_a")
	_pin(j, Vector2(175.0, 555.0) - Vector2.ONE * j.radius * 1.25, Vector2.ONE * j.radius * 2.5)
	_root.add_child(j)


## Places a control given in 1280x720 design coordinates and pins it to the nearest screen corner,
## so on a wider (or taller) screen the buttons stay under the thumbs at the edges instead of
## drifting toward the middle. The window stretches with aspect "expand" (project.godot).
static func _pin(c: Control, pos: Vector2, sz: Vector2) -> void:
	var right := pos.x + sz.x * 0.5 > 640.0
	var bottom := pos.y + sz.y * 0.5 > 360.0
	var ax := 1.0 if right else 0.0
	var ay := 1.0 if bottom else 0.0
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = pos.x - 1280.0 * ax
	c.offset_right = c.offset_left + sz.x
	c.offset_top = pos.y - 720.0 * ay
	c.offset_bottom = c.offset_top + sz.y


func _load_art(art_name: String) -> Texture2D:
	if art_name == "":
		return null
	return load(ART_DIR + art_name + ".png") as Texture2D


## One round button. Handles touch (per finger) and mouse (desktop, or browsers that turn touches
## into mouse events). If a tap arrives both ways, the second press finds the button already down.
class TouchButton extends Control:
	const MOUSE_ID := 1000

	var action: StringName
	var label := ""
	var radius := 50.0
	var plate: Texture2D
	var icon: Texture2D
	var icon_rot := 0.0
	var _pointers: Dictionary = {}       # pointer id -> true while it holds this button
	var _tap := Vector2.ZERO
	var _tap_age := 99.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _has_point(point: Vector2) -> bool:
		return point.distance_to(size * 0.5) <= radius * 1.05

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
		var press := 0.92 if lit else 1.0
		if plate != null:
			var r := radius * press
			draw_texture_rect(plate, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(0.75, 0.95, 1.0, 1.0) if lit else Color(1.0, 1.0, 1.0, 0.85))
		else:
			draw_circle(c, radius, Color(1, 1, 1, 0.45 if lit else 0.22))
			draw_arc(c, radius, 0.0, TAU, 40, Color(1, 1, 1, 0.85), 3.0)
		if icon != null:
			var s := radius * 1.0 / maxf(icon.get_width(), 1.0) * press
			draw_set_transform(c - Vector2(0.0, radius * 0.12), icon_rot, Vector2(s, s))
			draw_texture(icon, -icon.get_size() * 0.5, Color(1.0, 1.0, 1.0, 0.95))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var font := ThemeDB.fallback_font
		var fs := 15
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var ty := radius * 0.62 if icon != null else fs * 0.35
		if plate != null and icon == null:
			ty = radius * 0.62
		draw_string_outline(font, c + Vector2(-tw * 0.5, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.0, 0.05, 0.1, 0.9))
		draw_string(font, c + Vector2(-tw * 0.5, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
		if _tap_age < 0.5:
			var k := _tap_age / 0.5
			draw_arc(_tap, 14.0 + k * 22.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.3, 0.95 * (1.0 - k)), 3.0)


## Analog stick: the thumb's offset from the centre, as a vector of length 0..1, is turned into
## action strengths (Input.get_vector reads them as an analog direction). Touch and mouse both work.
class TouchJoystick extends Control:
	const MOUSE_ID := 1000
	const DEADZONE := 0.15

	var radius := 105.0
	var pad: Texture2D
	var nub: Texture2D
	var _pointer := -1
	var _vec := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _has_point(point: Vector2) -> bool:
		return point.distance_to(size * 0.5) <= radius * 1.25

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed and _pointer == -1:
				_pointer = event.index
				_move(event.position)
			elif not event.pressed and event.index == _pointer:
				_release()
			accept_event()
		elif event is InputEventScreenDrag:
			if event.index == _pointer:
				_move(event.position)
			accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _pointer == -1:
				_pointer = MOUSE_ID
				_move(event.position)
			elif not event.pressed and _pointer == MOUSE_ID:
				_release()
			accept_event()
		elif event is InputEventMouseMotion and _pointer == MOUSE_ID:
			_move(event.position)
			accept_event()

	func _move(p: Vector2) -> void:
		var v := (p - size * 0.5) / radius
		_vec = v.limit_length(1.0)
		_apply()
		queue_redraw()

	func _release() -> void:
		_pointer = -1
		_vec = Vector2.ZERO
		_apply()
		queue_redraw()

	func _apply() -> void:
		_axis(&"steer_right", maxf(0.0, _vec.x))
		_axis(&"steer_left", maxf(0.0, -_vec.x))
		_axis(&"boat_back", maxf(0.0, _vec.y))
		_axis(&"boat_forward", maxf(0.0, -_vec.y))

	func _axis(action: StringName, strength: float) -> void:
		if strength > DEADZONE:
			Input.action_press(action, strength)
		else:
			Input.action_release(action)

	func _notification(what: int) -> void:
		if (what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT) and _pointer != -1:
			_release()

	func _draw() -> void:
		var c := size * 0.5
		if pad != null:
			draw_texture_rect(pad, Rect2(c - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, Color(1.0, 1.0, 1.0, 0.8))
		else:
			draw_circle(c, radius, Color(1.0, 1.0, 1.0, 0.18))
		var k := c + _vec * radius * 0.6
		var nr := radius * 0.45
		if nub != null:
			draw_texture_rect(nub, Rect2(k - Vector2.ONE * nr, Vector2.ONE * nr * 2.0), false, Color(1.0, 1.0, 1.0, 0.95))
		else:
			draw_circle(k, nr, Color(1.0, 1.0, 1.0, 0.5))
