## Player state shared between scenes (map -> shore scene -> map) and saved between visits.
## The save lives in user://, which the Web export keeps in the browser's IndexedDB.
## Clearing the site data in the browser erases it.
##
## Progression (see GAME_DESIGN.md, "Progression"):
##   XP per catch = sqrt(base_price) x kg^0.4 x 4, plus a bonus for a species logged for the first
##   time and for a new personal record. Level n needs 40 x (n-1)^1.7 XP in total. Spots unlock by
##   level (`unlock_level` in fishing_spots.gd). Each outing has three goals (see ShoreFishing).
class_name GameSession
extends RefCounted

## Shown on screen so a player can tell a fresh deploy from a page the browser cached.
## Bump it with every build that changes behaviour.
const BUILD := "build 50"
const SAVE_PATH := "user://save.cfg"
const SAVE_VERSION := 1
const START_RIG := "shore_spinning_rig"
## Shore rigs in shop order. Prices live on each rig in BiomeDB.RIGS ("price").
const SHORE_RIGS: Array[String] = ["shore_spinning_rig", "shore_medium_rig", "shore_heavy_rig"]

# ---- tuning knobs: progression
const XP_PRICE_K := 4.0
const XP_FIRST_SPECIES := 25
const XP_RECORD := 10
const LEVEL_K := 40.0
const LEVEL_POW := 1.7
const MAX_LEVEL := 30

## Id of the FishingSpots entry the player picked on the map.
static var spot_id := ""
## "shore" or "boat" for the current outing (chosen on the map, not saved).
static var mode := "shore"
const BOAT_RENT := 60          ## coins to rent a rowing boat (kayık) for one outing
const BOAT_LEVEL := 3

## Fish landed during this visit: {fish_id, name, weight_kg, value, spot_id}. Not saved.
static var catches: Array[Dictionary] = []

static var coins := 0
static var sound_on := true
static var vibration_on := true
static var tutorial_done := false
## Bait and hook on the line (see Tackle). Saved.
static var bait_id := "sea_worm"
static var hook_id := "h4"
## Live baitfish kept in the bucket: caught small fish (istavrit, hamsi) or bought. Used up when a
## fish takes it or small fish strip it.
static var live_bait := 0
## Float rig (bait hangs at the float depth, bites show on the float) or bottom rig (dip takımı:
## a sinker holds the bait on the bottom, bites show on the rod tip and its bell). Saved.
static var rig_mode := "float"
## A landing net (kepçe): needed to land a heavy fish from a pier, quay or bridge. Saved.
static var has_net := false
## Test tools (set in the title screen's Settings): a TEST button on the shore hooks any species at
## once and lets you trigger jumps and the landing, to check a sprite or a fight in seconds.
## Test catches give no coins, XP or journal entry.
static var test_tools := false
## Date (YYYY-MM-DD) of the last completed daily challenge (see Daily).
static var daily_done := ""
const NET_PRICE := 250
const LIVE_BAIT_MAX := 12
const LIVE_BAIT_SPECIES: Array[String] = ["mediterranean_horse_mackerel", "european_anchovy", "atlantic_mackerel"]
static var xp := 0
static var rig_id := START_RIG
static var owned_rigs: Array[String] = [START_RIG]
static var best_kg: Dictionary = {}      ## fish id -> heaviest weight landed (kg)
static var counts: Dictionary = {}       ## fish id -> number landed

## The current outing (one visit to a spot). Not saved. Keys: spot_id, catches, xp, coins,
## new_species, records, species, goals, start_level.
static var outing: Dictionary = {}

static var _loaded := false


# ---------------------------------------------------------------- levels
static func xp_for_level(n: int) -> int:
	if n <= 1:
		return 0
	return int(round(LEVEL_K * pow(float(n - 1), LEVEL_POW)))


static func level() -> int:
	var n := 1
	while n < MAX_LEVEL and xp >= xp_for_level(n + 1):
		n += 1
	return n


## (XP earned inside the current level, XP the level is worth). For a progress bar.
static func level_progress() -> Vector2:
	var n := level()
	if n >= MAX_LEVEL:
		return Vector2(1.0, 1.0)
	var lo := xp_for_level(n)
	return Vector2(float(xp - lo), float(xp_for_level(n + 1) - lo))


static func xp_for_catch(base_price: int, kg: float) -> int:
	return maxi(1, int(round(sqrt(float(base_price)) * pow(maxf(kg, 0.01), 0.4) * XP_PRICE_K)))


static func is_unlocked(spot: Dictionary) -> bool:
	return level() >= int(spot.get("unlock_level", 1))


# ---------------------------------------------------------------- save and load
## Reads the save file once per run. Safe to call from every scene's _ready. Every value is
## type-checked: a damaged or hand-edited save falls back to defaults instead of breaking the game.
static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	coins = maxi(0, _to_int(cfg.get_value("player", "coins", 0)))
	xp = maxi(0, _to_int(cfg.get_value("player", "xp", 0)))
	owned_rigs.clear()
	var rigs: Variant = cfg.get_value("player", "owned_rigs", [START_RIG])
	if rigs is Array:
		for r: Variant in rigs:
			if r is String and not owned_rigs.has(r):
				owned_rigs.append(r)
	if not owned_rigs.has(START_RIG):
		owned_rigs.append(START_RIG)
	var rid: Variant = cfg.get_value("player", "rig_id", START_RIG)
	rig_id = String(rid) if (rid is String and owned_rigs.has(rid)) else START_RIG
	sound_on = bool(cfg.get_value("settings", "sound_on", true))
	vibration_on = bool(cfg.get_value("settings", "vibration_on", true))
	tutorial_done = bool(cfg.get_value("settings", "tutorial_done", false))
	var b: Variant = cfg.get_value("tackle", "bait", "sea_worm")
	bait_id = String(b) if (b is String and Tackle.BAITS.has(b)) else "sea_worm"
	var hk: Variant = cfg.get_value("tackle", "hook", "h4")
	hook_id = String(hk) if (hk is String and Tackle.HOOKS.has(hk)) else "h4"
	live_bait = clampi(_to_int(cfg.get_value("tackle", "live", 0)), 0, LIVE_BAIT_MAX)
	rig_mode = "bottom" if cfg.get_value("tackle", "rig", "float") == "bottom" else "float"
	has_net = cfg.get_value("tackle", "net", false) == true
	test_tools = cfg.get_value("settings", "test_tools", false) == true
	var dd: Variant = cfg.get_value("player", "daily_done", "")
	daily_done = String(dd) if dd is String else ""
	best_kg = _clean(cfg.get_value("journal", "best_kg", {}), true)
	counts = _clean(cfg.get_value("journal", "counts", {}), false)
	for k: String in counts:
		if not best_kg.has(k):
			best_kg[k] = 0.0        # the journal reads best_kg for every logged species
	AudioServer.set_bus_mute(0, not sound_on)


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "xp", xp)
	cfg.set_value("player", "rig_id", rig_id)
	cfg.set_value("player", "owned_rigs", owned_rigs)
	cfg.set_value("settings", "sound_on", sound_on)
	cfg.set_value("settings", "vibration_on", vibration_on)
	cfg.set_value("settings", "tutorial_done", tutorial_done)
	cfg.set_value("tackle", "bait", bait_id)
	cfg.set_value("tackle", "hook", hook_id)
	cfg.set_value("tackle", "live", live_bait)
	cfg.set_value("tackle", "rig", rig_mode)
	cfg.set_value("tackle", "net", has_net)
	cfg.set_value("settings", "test_tools", test_tools)
	cfg.set_value("player", "daily_done", daily_done)
	cfg.set_value("journal", "best_kg", best_kg)
	cfg.set_value("journal", "counts", counts)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("[GameSession] save failed with error %d" % err)


## Turns all game sound on or off and saves the choice.
static func set_sound(on: bool) -> void:
	sound_on = on
	AudioServer.set_bus_mute(0, not on)
	save()


static func set_tackle(bait: String, hook: String) -> void:
	if Tackle.BAITS.has(bait):
		bait_id = bait
	if Tackle.HOOKS.has(hook):
		hook_id = hook
	save()


static func set_test_tools(on: bool) -> void:
	test_tools = on
	save()


static func set_tutorial_done() -> void:
	tutorial_done = true
	save()


static func set_vibration(on: bool) -> void:
	vibration_on = on
	save()


static func _to_int(v: Variant) -> int:
	if v is int or v is float:
		return int(v)
	return 0


static func _clean(d: Variant, as_float: bool) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k: Variant in d:
			var v: Variant = d[k]
			if k is String and (v is float or v is int):
				out[k] = float(v) if as_float else int(v)
	return out


# ---------------------------------------------------------------- catches and outings
## Adds a landed fish to coins, XP, the journal and the outing goals, then saves.
## Returns {first, record, xp, level_up, level, goals_done}.
static func record_catch(fish_id: String, fish_name: String, weight_kg: float, value: int, base_price: int) -> Dictionary:
	var first := not counts.has(fish_id)
	var record := not first and weight_kg > float(best_kg.get(fish_id, 0.0))
	var gained := xp_for_catch(base_price, weight_kg)
	if first:
		gained += XP_FIRST_SPECIES
	if record:
		gained += XP_RECORD
	var level_before := level()
	coins += value
	xp += gained
	catches.append({"fish_id": fish_id, "name": fish_name, "weight_kg": weight_kg, "value": value, "spot_id": spot_id})
	best_kg[fish_id] = maxf(float(best_kg.get(fish_id, 0.0)), weight_kg)
	counts[fish_id] = int(counts.get(fish_id, 0)) + 1
	if not outing.is_empty():
		outing["catches"] = int(outing["catches"]) + 1
		outing["xp"] = int(outing["xp"]) + gained
		outing["coins"] = int(outing["coins"]) + value
		var species: Array = outing["species"]
		if not species.has(fish_id):
			species.append(fish_id)
		if first:
			var fresh: Array = outing["new_species"]
			fresh.append(fish_name)
		if record:
			var recs: Array = outing["records"]
			recs.append("%s %.2f kg" % [fish_name, weight_kg])
	var done := _progress_goals(weight_kg, first)
	save()
	var lv := level()
	return {"first": first, "record": record, "xp": gained, "level_up": lv > level_before, "level": lv, "goals_done": done}


## Starts a new outing at the current spot with the given goals (see ShoreFishing._make_goals).
static func start_outing(goals: Array[Dictionary]) -> void:
	outing = {"spot_id": spot_id, "catches": 0, "xp": 0, "coins": 0, "new_species": [], "records": [],
		"species": [], "goals": goals, "start_level": level()}


## Goal kinds: "count" (catch N fish), "new" (log N new species), "distinct" (N different species in
## this outing), "weight" (one fish of at least `target` kg). Returns the goals finished by this catch.
static func _progress_goals(weight_kg: float, first: bool) -> Array[Dictionary]:
	var finished: Array[Dictionary] = []
	if outing.is_empty():
		return finished
	var goals: Array = outing["goals"]
	for g: Dictionary in goals:
		if bool(g["done"]):
			continue
		match String(g["kind"]):
			"count":
				g["progress"] = int(g["progress"]) + 1
			"new":
				if first:
					g["progress"] = int(g["progress"]) + 1
			"distinct":
				var sp: Array = outing["species"]
				g["progress"] = sp.size()
			"weight":
				if weight_kg >= float(g["target"]):
					g["progress"] = 1
		var need := 1 if String(g["kind"]) == "weight" else int(g["target"])
		if int(g["progress"]) >= need:
			g["done"] = true
			coins += int(g["coins"])
			xp += int(g["xp"])
			outing["coins"] = int(outing["coins"]) + int(g["coins"])
			outing["xp"] = int(outing["xp"]) + int(g["xp"])
			finished.append(g)
	return finished


## One line for the HUD, for example "Catch 3 fish  1/3".
static func goal_line(g: Dictionary) -> String:
	var need := 1 if String(g["kind"]) == "weight" else int(g["target"])
	return "%s  %d/%d%s" % [g["text"], mini(int(g["progress"]), need), need, "  DONE" if bool(g["done"]) else ""]


## Adds (or with a negative n, uses) live baitfish. Returns the new count.
static func add_live_bait(n: int) -> int:
	live_bait = clampi(live_bait + n, 0, LIVE_BAIT_MAX)
	save()
	return live_bait


## Buys live baitfish from the bait shop. Returns false if not enough coins or the bucket is full.
static func buy_live_bait(n: int, price: int) -> bool:
	if coins < price or live_bait >= LIVE_BAIT_MAX:
		return false
	coins -= price
	add_live_bait(n)
	return true


static func buy_net() -> bool:
	if has_net or coins < NET_PRICE:
		return false
	coins -= NET_PRICE
	has_net = true
	save()
	return true


## Buys and equips a rig. Returns false if already owned or not enough coins.
static func buy_rig(id: String, price: int) -> bool:
	if owned_rigs.has(id) or coins < price:
		return false
	coins -= price
	owned_rigs.append(id)
	rig_id = id
	save()
	return true


static func equip(id: String) -> void:
	if owned_rigs.has(id):
		rig_id = id
		save()
