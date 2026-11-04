## Registers default keyboard bindings at runtime so every script runs out of the box.
## Rebind later in Project Settings > Input Map; existing actions are never overwritten.
class_name InputDefaults
extends RefCounted

const DEFAULTS := {
	&"boat_forward": KEY_W,
	&"boat_back": KEY_S,
	&"steer_left": KEY_A,
	&"steer_right": KEY_D,
	&"reel_in": KEY_SPACE,
	&"drag_up": KEY_UP,
	&"drag_down": KEY_DOWN,
	&"anchor": KEY_X,
	&"bait_deeper": KEY_E,
	&"bait_shallower": KEY_Q,
	&"cast": KEY_C,
}


static func ensure_all() -> void:
	for action: StringName in DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = DEFAULTS[action]
		InputMap.action_add_event(action, ev)
