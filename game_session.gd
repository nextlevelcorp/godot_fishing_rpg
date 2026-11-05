## Player state shared between scenes (map -> shore scene -> map) and saved between visits.
## The save lives in user://, which the Web export keeps in the browser's IndexedDB.
## Clearing the site data in the browser erases it.
class_name GameSession
extends RefCounted

## Shown on screen so a player can tell a fresh deploy from a page the browser cached.
## Bump it with every build that changes behaviour.
const BUILD := "build 14"
const SAVE_PATH := "user://save.cfg"
const START_RIG := "shore_spinning_rig"
## Shore rigs in shop order. Prices live on each rig in BiomeDB.RIGS ("price").
const SHORE_RIGS: Array[String] = ["shore_spinning_rig", "shore_medium_rig", "shore_heavy_rig"]

## Id of the FishingSpots entry the player picked on the map.
static var spot_id := ""

## Fish landed during this visit: {fish_id, name, weight_kg, value, spot_id}. Not saved.
static var catches: Array[Dictionary] = []

static var coins := 0
static var rig_id := START_RIG
static var owned_rigs: Array[String] = [START_RIG]
static var best_kg: Dictionary = {}      ## fish id -> heaviest weight landed (kg)
static var counts: Dictionary = {}       ## fish id -> number landed

static var _loaded := false


## Reads the save file once per run. Safe to call from every scene's _ready.
static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	coins = int(cfg.get_value("player", "coins", 0))
	owned_rigs.assign(cfg.get_value("player", "owned_rigs", [START_RIG]))
	if not owned_rigs.has(START_RIG):
		owned_rigs.append(START_RIG)
	rig_id = String(cfg.get_value("player", "rig_id", START_RIG))
	if not owned_rigs.has(rig_id):
		rig_id = START_RIG
	best_kg = cfg.get_value("journal", "best_kg", {})
	counts = cfg.get_value("journal", "counts", {})


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "rig_id", rig_id)
	cfg.set_value("player", "owned_rigs", owned_rigs)
	cfg.set_value("journal", "best_kg", best_kg)
	cfg.set_value("journal", "counts", counts)
	cfg.save(SAVE_PATH)


## Adds a landed fish to coins and the journal, then saves.
static func record_catch(fish_id: String, fish_name: String, weight_kg: float, value: int) -> void:
	coins += value
	catches.append({"fish_id": fish_id, "name": fish_name, "weight_kg": weight_kg, "value": value, "spot_id": spot_id})
	best_kg[fish_id] = maxf(float(best_kg.get(fish_id, 0.0)), weight_kg)
	counts[fish_id] = int(counts.get(fish_id, 0)) + 1
	save()


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
