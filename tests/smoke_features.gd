## Headless feature smoke test, run by CI after the scene smoke runs (see .github/workflows/web-pages.yml).
## It drives the real shore scene: audio is loaded and plays, the settings survive a save and load, a
## TEST fish can be hooked, made to jump and landed, and a test catch gives no rewards. Every check
## prints "SMOKE ok:" or "SMOKE FAIL:" and a failure fails the build. It cannot hear anything and
## cannot see the screen: it proves the code paths run without errors, nothing more.
extends SceneTree

# ShoreFishing.State, as numbers. Do not write `ShoreFishing.State.FIGHT` here: a script run with -s
# is compiled before the autoloads exist, and shore_fishing.gd needs BiomeDB, so naming the class in
# this file stops the whole scene from compiling ("Identifier not found: BiomeDB", build 45 CI).
const STATE_AIM := 0
const STATE_FIGHT := 5

var _frame := 0
var _scene: Node
var _fails := 0
var _coins_before := 0
var _xp_before := 0


func _ok(msg: String) -> void:
	print("SMOKE ok: ", msg)


func _fail(msg: String) -> void:
	_fails += 1
	print("SMOKE FAIL: ", msg)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok(msg)
	else:
		_fail(msg)


func _initialize() -> void:
	GameSession.load_once()
	# Settings are saved and read back.
	GameSession.set_test_tools(true)
	GameSession.set_sound(true)
	GameSession._loaded = false
	GameSession.test_tools = false
	GameSession.load_once()
	_check(GameSession.test_tools, "test_tools survives save and load")
	_check(not AudioServer.is_bus_mute(0), "master bus is not muted when sound is on")
	GameSession.spot_id = "dikili_bay"
	GameSession.mode = "shore"
	var packed := load("res://shore_fishing.tscn") as PackedScene
	_scene = packed.instantiate()
	root.add_child(_scene)
	_coins_before = GameSession.coins
	_xp_before = GameSession.xp


func _process(_delta: float) -> bool:
	_frame += 1
	var amb: Ambience = _scene.get("_amb")
	match _frame:
		5:
			_check(amb != null, "ambience exists")
			if amb != null:
				var streams: Dictionary = amb.get("_streams")
				var voices: Array = amb.get("_voices")
				print("SMOKE info: %d sounds loaded, %d voices, %d buses, master muted: %s" % [streams.size(), voices.size(), AudioServer.bus_count, str(AudioServer.is_bus_mute(0))])
				_check(streams.size() >= 40, "at least 40 sounds loaded (got %d)" % streams.size())
				_check(voices.size() >= 8, "at least 8 sound voices (got %d)" % voices.size())
				amb.play("splash", 1.0)
				amb.play("step_wood", 0.5)
				amb.play_at("splash", 0.9, 80.0)
		8:
			var voices2: Array = amb.get("_voices")
			var playing := 0
			for v: AudioStreamPlayer in voices2:
				if v.playing:
					playing += 1
			print("SMOKE info: %d voices playing" % playing)
			_check(playing >= 1, "a sound is playing after play()")
		12:
			var ui_has_test := false
			for n in _scene.find_children("*", "Button", true, false):
				if (n as Button).text == "TEST":
					ui_has_test = true
			_check(ui_has_test, "the TEST button exists on the shore")
			_scene.call("_open_test_panel")
		16:
			var panels := 0
			for n in _scene.find_children("*", "Button", true, false):
				if (n as Button).text.contains("Whiting"):
					panels += 1
			_check(panels >= 1, "the TEST panel lists species (Whiting found)")
			_scene.call("_test_hook", "whiting", 0.4)
		40:
			_check(int(_scene.get("_state")) == STATE_FIGHT, "a TEST fish is on the line")
			_scene.call("_test_action", "jump")
		80:
			_scene.call("_test_action", "thrash")
		120:
			_scene.call("_test_action", "land")
		160:
			_check(GameSession.coins == _coins_before and GameSession.xp == _xp_before, "a test catch gives no coins or XP")
			_check(int(_scene.get("_state")) != STATE_FIGHT, "the test fish was landed")
			# Hook a cephalopod and a crab, which have painted pictures but procedural fallbacks.
			_scene.set("_state", STATE_AIM)
			_scene.call("_test_hook", "european_squid", 0.5)
		200:
			_scene.call("_test_action", "land")
		240:
			print("SMOKE done: %d failure(s)" % _fails)
			quit(1 if _fails > 0 else 0)
	return false
