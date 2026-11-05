## On-screen touch buttons and an analog stick for phones and tablets.
## Each button presses the same input action the keyboard uses (cast, reel_in, ...), so gameplay
## scripts do not care whether input came from a finger or a key.
##
## How touches reach this node (a phone test showed that only some buttons worked, so both ways
## are listened to and either one is enough):
##   1. _input        raw viewport events (ScreenTouch / ScreenDrag / mouse);
##   2. the Surface   a full-screen GUI Control whose _gui_input gets the same events through
##                    Godot's GUI, the path ordinary Buttons use.
## Both call _handle(). A finger is tracked by a key ("t<index>" or "m"), and a button counts as
## held while at least one key holds it, so an event that arrives twice changes nothing.
## Once a ScreenTouch has been seen, mouse events are ignored (they are the emulated copy).
##
## Positions are in the 1280x720 design space, the space events arrive in.
## Button art: Kenney Mobile Controls (CC0), assets/kenney_mobile_controls/.
class_name TouchControls
extends CanvasLayer

## Buttons are drawn and hit-tested at this multiple of the listed radius, so thumbs can reach them.
const TOUCH_SCALE := 1.35
const STICK_CENTER := Vector2(175.0, 555.0)
const STICK_RADIUS := 105.0
const DEADZONE := 0.15

const BUTTONS := [
	# [action, label, center_x, center_y, radius] in design coordinates (1280 x 720).
	# Left cluster: boat (legacy boat game).
	[&"boat_forward", "^", 110.0, 430.0, 60.0],
	[&"steer_left", "<", 60.0, 580.0, 55.0],
	[&"steer_right", ">", 200.0, 580.0, 55.0],
	[&"boat_back", "v", 110.0, 690.0, 40.0],
	# Right side: fishing. Kept at least 96 px from the right edge and 70 px from the bottom, away
	# from notches, rounded corners and browser toolbars. Two small columns sit left of CAST/REEL.
	[&"cast", "CAST", 1090.0, 360.0, 52.0],
	[&"reel_in", "REEL", 1090.0, 535.0, 66.0],
	[&"drag_up", "CLUTCH+", 945.0, 440.0, 36.0],
	[&"drag_down", "CLUTCH-", 945.0, 555.0, 36.0],
	[&"bait_deeper", "DEEP", 810.0, 440.0, 36.0],
	[&"bait_shallower", "SHAL", 810.0, 555.0, 36.0],
	[&"anchor", "ANCH", 945.0, 325.0, 40.0],
]

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

## Diagnostics shown by the shore scene: how many pointer events reached each path, and the last
## one. If `input` grows and `gui` stays 0 the raw path works on this device, and the other way round.
static var count_input := 0
static var count_gui := 0
static var last_event := "-"

## Only these actions get a button. Empty = all. Set before the node enters the tree.
var enabled_actions: Array[StringName] = []
## Adds an analog stick at the bottom left that drives steer_left/right and boat_forward/back with
## strength (walking in the shore scene). Set before the node enters the tree.
var joystick := false

var _surface: Surface
var _regions: Array[Dictionary] = []
var _holders: Dictionary = {}        # action -> {pointer key: true}
var _owner: Dictionary = {}          # pointer key -> region index (-1 = the stick)
var _touch_seen := false
var _stick_vec := Vector2.ZERO
var _taps: Array[Dictionary] = []
var _stick_pad: Texture2D
var _stick_nub: Texture2D


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b: Array in BUTTONS:
		var action: StringName = b[0]
		if not (enabled_actions.is_empty() or enabled_actions.has(action)):
			continue
		var look: Array = VISUALS.get(action, ["button_circle", "", 0.0])
		_regions.append({
			"action": action,
			"label": String(b[1]),
			"center": Vector2(b[2], b[3]),
			"radius": float(b[4]) * TOUCH_SCALE,
			"plate": _load_art(String(look[0])),
			"icon": _load_art(String(look[1])),
			"rot": float(look[2]),
		})
	if joystick:
		_stick_pad = _load_art("joystick_circle_pad_a")
		_stick_nub = _load_art("joystick_circle_nub_a")
	_surface = Surface.new()
	_surface.host = self
	add_child(_surface)


func _load_art(art_name: String) -> Texture2D:
	if art_name == "":
		return null
	return load(ART_DIR + art_name + ".png") as Texture2D


func _process(delta: float) -> void:
	for t in _taps:
		t["age"] = float(t["age"]) + delta
	_taps.assign(_taps.filter(func(t: Dictionary) -> bool: return float(t["age"]) < 0.5))
	if _surface != null and (not _taps.is_empty() or not _owner.is_empty()):
		_surface.queue_redraw()


# ---------------------------------------------------------------- events
func _input(event: InputEvent) -> void:
	if not _is_pointer_event(event):
		return
	count_input += 1
	last_event = _describe(event)
	if _handle(event):
		get_viewport().set_input_as_handled()


## Called by the Surface; returns true if the event was ours.
func _on_gui(event: InputEvent) -> bool:
	if not _is_pointer_event(event):
		return false
	count_gui += 1
	last_event = _describe(event)
	return _handle(event)


func _is_pointer_event(event: InputEvent) -> bool:
	return event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion


func _describe(event: InputEvent) -> String:
	var kind := event.get_class()
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		pos = event.position
		kind += (" down i%d" if event.pressed else " up i%d") % event.index
	elif event is InputEventScreenDrag:
		pos = event.position
		kind += " i%d" % event.index
	elif event is InputEventMouse:
		pos = event.position
	return "%s (%d,%d)" % [kind, int(pos.x), int(pos.y)]


func _handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		_touch_seen = true
		return _point("t%d" % event.index, event.position, event.pressed)
	if event is InputEventScreenDrag:
		_touch_seen = true
		return _drag("t%d" % event.index, event.position)
	if _touch_seen:
		return false          # the mouse event is the emulated copy of a touch
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return _point("m", event.position, event.pressed)
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		return _drag("m", event.position)
	return false


func _point(key: String, pos: Vector2, pressed: bool) -> bool:
	if pressed:
		if _owner.has(key):
			return true       # the same press arriving a second time
		var idx := _region_at(pos)
		if idx == -2:
			return false
		_owner[key] = idx
		_taps.append({"pos": pos, "age": 0.0})
		if idx == -1:
			_stick_move(pos)
		else:
			_hold(_regions[idx]["action"], key)
		_surface.queue_redraw()
		return true
	if not _owner.has(key):
		return false
	var held: int = _owner[key]
	_owner.erase(key)
	if held == -1:
		_stick_vec = Vector2.ZERO
		_apply_stick()
	else:
		_unhold(_regions[held]["action"], key)
	_surface.queue_redraw()
	return true


func _drag(key: String, pos: Vector2) -> bool:
	if _owner.has(key) and int(_owner[key]) == -1:
		_stick_move(pos)
		return true
	return _owner.has(key)


## -2 = nothing, -1 = the stick, otherwise the index of the button under pos.
func _region_at(pos: Vector2) -> int:
	if joystick and pos.distance_to(STICK_CENTER) <= STICK_RADIUS * 1.25:
		return -1
	var best := -2
	var best_d := INF
	for i in _regions.size():
		var r: Dictionary = _regions[i]
		var center: Vector2 = r["center"]
		var d := pos.distance_to(center)
		if d <= float(r["radius"]) * 1.05 and d < best_d:
			best = i
			best_d = d
	return best


func _covers(pos: Vector2) -> bool:
	return _region_at(pos) != -2


# ---------------------------------------------------------------- actions
func _hold(action: StringName, key: String) -> void:
	var h: Dictionary = _holders.get(action, {})
	var was_empty := h.is_empty()
	h[key] = true
	_holders[action] = h
	if was_empty:
		presses[action] = int(presses.get(action, 0)) + 1
		_set_action(action, true, 1.0)


func _unhold(action: StringName, key: String) -> void:
	var h: Dictionary = _holders.get(action, {})
	h.erase(key)
	if h.is_empty():
		_set_action(action, false, 0.0)


func _is_held(action: StringName) -> bool:
	var h: Dictionary = _holders.get(action, {})
	return not h.is_empty()


## Sets the action's state (read by Input.get_axis / is_action_pressed) and also sends the event
## (read by _unhandled_input handlers such as the boat sandbox's cast).
func _set_action(action: StringName, down: bool, strength: float) -> void:
	if down:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	ev.strength = strength
	Input.parse_input_event(ev)


func _stick_move(pos: Vector2) -> void:
	_stick_vec = ((pos - STICK_CENTER) / STICK_RADIUS).limit_length(1.0)
	_apply_stick()


func _apply_stick() -> void:
	_axis(&"steer_right", maxf(0.0, _stick_vec.x))
	_axis(&"steer_left", maxf(0.0, -_stick_vec.x))
	_axis(&"boat_back", maxf(0.0, _stick_vec.y))
	_axis(&"boat_forward", maxf(0.0, -_stick_vec.y))


func _axis(action: StringName, strength: float) -> void:
	if strength > DEADZONE:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


## Lets go of everything: window lost focus, app went to the background, node leaving the tree.
func release_all() -> void:
	for key: String in _owner.keys():
		var idx: int = _owner[key]
		if idx == -1:
			_stick_vec = Vector2.ZERO
			_apply_stick()
		else:
			_unhold(_regions[idx]["action"], key)
	_owner.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		release_all()


# ---------------------------------------------------------------- drawing
func _paint(c: Control) -> void:
	for r: Dictionary in _regions:
		var center: Vector2 = r["center"]
		var rad: float = r["radius"]
		var lit := _is_held(r["action"])
		var press := 0.92 if lit else 1.0
		var plate: Texture2D = r["plate"]
		var icon: Texture2D = r["icon"]
		if plate != null:
			var pr := rad * press
			c.draw_texture_rect(plate, Rect2(center - Vector2(pr, pr), Vector2(pr, pr) * 2.0), false,
				Color(0.75, 0.95, 1.0, 1.0) if lit else Color(1.0, 1.0, 1.0, 0.85))
		else:
			c.draw_circle(center, rad, Color(1, 1, 1, 0.45 if lit else 0.22))
			c.draw_arc(center, rad, 0.0, TAU, 40, Color(1, 1, 1, 0.85), 3.0)
		if icon != null:
			var s := rad / maxf(icon.get_width(), 1.0) * press
			c.draw_set_transform(center - Vector2(0.0, rad * 0.12), float(r["rot"]), Vector2(s, s))
			c.draw_texture(icon, -icon.get_size() * 0.5, Color(1.0, 1.0, 1.0, 0.95))
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var font := ThemeDB.fallback_font
		var text: String = r["label"]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var ty := rad * 0.62
		c.draw_string_outline(font, center + Vector2(-tw * 0.5, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0.0, 0.05, 0.1, 0.9))
		c.draw_string(font, center + Vector2(-tw * 0.5, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.95))
	if joystick:
		if _stick_pad != null:
			c.draw_texture_rect(_stick_pad, Rect2(STICK_CENTER - Vector2.ONE * STICK_RADIUS, Vector2.ONE * STICK_RADIUS * 2.0), false, Color(1.0, 1.0, 1.0, 0.8))
		else:
			c.draw_circle(STICK_CENTER, STICK_RADIUS, Color(1.0, 1.0, 1.0, 0.18))
		var knob := STICK_CENTER + _stick_vec * STICK_RADIUS * 0.6
		var nr := STICK_RADIUS * 0.45
		if _stick_nub != null:
			c.draw_texture_rect(_stick_nub, Rect2(knob - Vector2.ONE * nr, Vector2.ONE * nr * 2.0), false, Color(1.0, 1.0, 1.0, 0.95))
		else:
			c.draw_circle(knob, nr, Color(1.0, 1.0, 1.0, 0.5))
	# Tap marker: where the game thinks the finger landed.
	for t: Dictionary in _taps:
		var k := float(t["age"]) / 0.5
		c.draw_arc(t["pos"], 14.0 + k * 24.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.3, 0.95 * (1.0 - k)), 3.0)


## The full-screen GUI Control: second way in for touches, and where everything is drawn. It only
## claims touches that land on a button or the stick, so other UI underneath (like MAP) still works.
class Surface extends Control:
	var host: TouchControls

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _has_point(point: Vector2) -> bool:
		return host != null and host._covers(point)

	func _gui_input(event: InputEvent) -> void:
		if host != null and host._on_gui(event):
			accept_event()

	func _draw() -> void:
		if host != null:
			host._paint(self)
