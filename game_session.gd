## Small shared state that survives scene changes (map -> shore scene -> map).
class_name GameSession
extends RefCounted

## Id of the FishingSpots entry the player picked on the map.
static var spot_id := ""

## Every fish landed so far this session: {fish_id, name, weight_kg, value, spot_id}.
static var catches: Array[Dictionary] = []

static var coins := 0
