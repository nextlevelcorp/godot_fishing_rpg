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
				_check(streams.size() >= 37, "all 37 sounds loaded (got %d)" % streams.size())
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
			_check(int(_scene.get("_local_idx")) >= 0, "the spot has a named local angler")
			_check(_scene.get("_talk_btn") != null, "the TALK button exists on the shore")
			_scene.call("_open_talk_panel")
			var tp: Variant = _scene.get("_talk_panel")
			_check(tp != null and is_instance_valid(tp), "the TALK panel opens")
			if tp != null and is_instance_valid(tp):
				(tp as Node).queue_free()
			# Weekly tournament: entering picks rivals; at the horn with no fish you place last, no prize.
			var coins_before := GameSession.coins
			GameSession.coins = 100
			_scene.call("_start_tourney")
			var tr: Dictionary = _scene.get("_tourney")
			_check(not tr.is_empty() and (tr["rivals"] as Array).size() >= 1, "a tournament starts with rivals")
			tr["t"] = 0.0
			_scene.call("_tick_tourney", 0.1)
			_check(bool((_scene.get("_tourney") as Dictionary).get("over", false)), "the tournament ends at the horn")
			_check(GameSession.coins == 100 - 30, "entry was paid and no prize was given for no fish")
			var tp2: Variant = _scene.get("_talk_panel")
			if tp2 != null and is_instance_valid(tp2):
				(tp2 as Node).queue_free()
			# Tackle shop: a pack of a special bait costs coins, adds stock, and each use takes one.
			GameSession.coins = 100
			var stock_before: Dictionary = GameSession.bait_stock.duplicate()
			GameSession.bait_stock.erase("tube_worm")
			_check(GameSession.stock("tube_worm") == 0 and GameSession.stock("mussel") == -1, "shop baits start empty, free baits are unlimited")
			_check(GameSession.buy_bait("tube_worm") and GameSession.stock("tube_worm") == 5 and GameSession.coins == 60, "buying a pack of tube worm adds 5 for 40 coins")
			GameSession.use_bait("tube_worm")
			_check(GameSession.stock("tube_worm") == 4, "using a shop bait takes one")
			GameSession.bait_stock = stock_before
			GameSession.coins = coins_before
			_scene.call("_open_test_panel")
		14:
			_check_game_rules()
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


## Rules that need no screen: the local's request and friendship, the weekly tournament's week and
## spot, and that the new saved fields survive a save and load. The classes that use BiomeDB are
## loaded at run time (see the note at the top: naming them here would stop this script compiling).
func _check_game_rules() -> void:
	var locals: GDScript = load("res://locals.gd")
	var tourney: GDScript = load("res://tournament.gd")
	var spot := "dikili_bay"
	var saved_friend: Dictionary = GameSession.local_friend.duplicate()
	var saved_req: Dictionary = GameSession.local_req.duplicate()
	var saved_coins := GameSession.coins
	var saved_xp := GameSession.xp
	GameSession.local_friend = {}
	GameSession.local_req = {}
	# The local's request: a species from the spot, 1 fish at friendship 0.
	var req: Dictionary = locals.call("request", spot)
	var spot_species: Array = FishingSpots.get_spot(spot)["species"]
	_check(not req.is_empty() and spot_species.has(String(req["species"])) and int(req["need"]) == 1, "the local asks for 1 fish of a species from this spot")
	_check(not bool(locals.call("on_kept", spot, "not_a_species")), "a wrong species does not count for the request")
	_check(not bool(locals.call("can_turn_in", spot)), "the request cannot be handed in before the fish is kept")
	_check(bool(locals.call("on_kept", spot, String(req["species"]))), "the asked species counts toward the request")
	_check(bool(locals.call("can_turn_in", spot)), "the request can be handed in once the fish is kept")
	# Hand-in pays coins and XP, adds friendship and clears the request.
	GameSession.coins = 0
	GameSession.xp = 0
	var reward := int(locals.call("reward_coins", spot))
	var res: Dictionary = locals.call("turn_in", spot)
	_check(not res.is_empty() and GameSession.coins == reward and reward > 0, "handing in pays the reward (%d coins)" % reward)
	_check(GameSession.xp == 20 and int(locals.call("friendship", spot)) == 1 and not GameSession.local_req.has(spot), "XP, friendship +1 and a fresh request after the hand-in")
	_check(not bool(locals.call("can_turn_in", spot)), "the same fish cannot be handed in twice")
	var lines: PackedStringArray = locals.call("talk_lines", spot)
	_check(lines.size() >= 2, "the local has a greeting and a request to say")
	# Tiers: Stranger 0, Known face 1, Friend 3, Old friend 6; friends tell a secret.
	_check(int(locals.call("tier", 0)) == 0 and int(locals.call("tier", 2)) == 1 and int(locals.call("tier", 3)) == 2 and int(locals.call("tier", 9)) == 3, "friendship tiers")
	GameSession.local_friend[spot] = 3
	var friend_lines: PackedStringArray = locals.call("talk_lines", spot)
	_check(friend_lines.size() >= 3 and friend_lines[friend_lines.size() - 1].begins_with("Between us:"), "a friend shares a secret")
	# Every spot has its local.
	var missing := 0
	for id: String in FishingSpots.ids():
		if (locals.call("person", id) as Dictionary).is_empty():
			missing += 1
	_check(missing == 0, "every spot has a named local")
	# Reactions.
	var nod: String = locals.call("react", String(spot_species[0]), 0.1, true)
	_check(nod.begins_with("Good, put it back"), "the local approves of a released fish")
	# Tournament week and spot.
	var wk1: String = tourney.call("week_key")
	var sp1: String = tourney.call("spot_this_week")
	_check(wk1.begins_with("w") and wk1 == String(tourney.call("week_key")), "the tournament week key is stable")
	_check(sp1 != "" and GameSession.is_unlocked(FishingSpots.get_spot(sp1)) and sp1 == String(tourney.call("spot_this_week")), "this week's tournament spot is unlocked and stable")
	# New saved fields survive a save and load.
	var saved_stock: Dictionary = GameSession.bait_stock.duplicate()
	var saved_week := GameSession.tourney_week
	var saved_wins := GameSession.tourney_wins
	GameSession.local_friend = {"dikili_bay": 4}
	GameSession.local_req = {"dikili_bay": {"species": "garfish", "need": 2, "have": 1}}
	GameSession.bait_stock = {"tube_worm": 7}
	GameSession.tourney_week = "w-test"
	GameSession.tourney_wins = 3
	GameSession.save()
	GameSession.local_friend = {}
	GameSession.local_req = {}
	GameSession.bait_stock = {}
	GameSession.tourney_week = ""
	GameSession.tourney_wins = 0
	GameSession._loaded = false
	GameSession.load_once()
	_check(int(GameSession.local_friend.get("dikili_bay", 0)) == 4, "local friendship survives save and load")
	var lr: Dictionary = GameSession.local_req.get("dikili_bay", {})
	_check(String(lr.get("species", "")) == "garfish" and int(lr.get("need", 0)) == 2 and int(lr.get("have", 0)) == 1, "the open request survives save and load")
	_check(int(GameSession.bait_stock.get("tube_worm", 0)) == 7, "special bait stock survives save and load")
	_check(GameSession.tourney_week == "w-test" and GameSession.tourney_wins == 3, "the tournament week and wins survive save and load")
	# Put everything back so nothing leaks into the checks that follow or the next run.
	GameSession.local_friend = saved_friend
	GameSession.local_req = saved_req
	GameSession.bait_stock = saved_stock
	GameSession.tourney_week = saved_week
	GameSession.tourney_wins = saved_wins
	GameSession.coins = saved_coins
	GameSession.xp = saved_xp
