## Takes screenshots of the real game for visual review (not used by the game or CI).
## Run under a virtual display, e.g.:
##   xvfb-run -s "-screen 0 1560x720x24" godot --path . --rendering-driver opengl3 -s res://tools/shots/shot.gd -- spot=cesme_cove hour=0.35 out=/tmp/x
## Writes <out>_shore.png after the shore settles, <out>_fight.png with a TEST fish on the line in the
## first-person view, and <out>_catch.png with the landed fish held up. Uses numeric states because
## a -s script is compiled before autoloads exist (see tests/smoke_features.gd).
extends SceneTree

var _frame := 0
var _scene: Node
var _out := "/tmp/shot"
var _hour := 0.35
var _species := "bluefish"
var _params := {}          ## water shader overrides, "p:name=value" on the command line
var _shore_only := false
var _other := ""
var _x := INF              ## x=<px>: stand the angler at this x on the shore (e.g. the pier)           ## scene=title|map: just that screen


func _initialize() -> void:
	var spot := "dikili_bay"
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"spot": spot = kv[1]
			"out": _out = kv[1]
			"hour": _hour = float(kv[1])
			"fish": _species = kv[1]
			"shore_only": _shore_only = kv[1] == "1"
			"scene": _other = kv[1]
			"x": _x = float(kv[1])
			_:
				if kv[0].begins_with("p:"):
					_params[kv[0].substr(2)] = float(kv[1])
	GameSession.load_once()
	GameSession.tutorial_done = true
	GameSession.test_tools = true
	GameSession.spot_id = spot
	GameSession.mode = "shore"
	var path := "res://shore_fishing.tscn"
	if _other != "":
		path = "res://title_screen.tscn" if _other == "title" else "res://turkey_map.tscn"
	_scene = (load(path) as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _other != "":
		if _frame == 60:
			if _other == "map" and _scene.has_method("_select"):
				_scene.call("_select", "canakkale_kordon")
		if _frame == 90:
			_save(_other)
			quit(0)
		return false
	match _frame:
		3:
			var w: Node = _scene.get("_world")
			w.set("time_of_day", _hour)
			if _x != INF:
				var px: float = _x
				if px == 0.0:
					px = float(_scene.get("_pier_x"))
				_scene.set("_hand", Vector2(px, -60.0))
			var water: CanvasItem = _scene.get("_water")
			var mat := water.material as ShaderMaterial
			for k: String in _params:
				mat.set_shader_parameter(k, _params[k])
		90:
			_save("shore")
			if _shore_only:
				quit(0)
				return false
			_scene.call("_test_hook", _species, 0.6)
		150:
			_save("fight")
			_scene.call("_test_action", "land")
		260:
			_save("catch")
		262:
			quit(0)
	return false


func _save(tag: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, tag])
	print("SHOT ", tag, " ", img.get_size())
