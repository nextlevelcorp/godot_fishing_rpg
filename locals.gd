## The local angler at each spot: one named person who fishes there every day, asks you for a few
## fish, and warms to you as you bring them. The first slice of "angler life" (GAME_DESIGN.md,
## "Locals on the shore"). The people, their lines and the reward numbers are game-design fill:
## no real person is portrayed.
##
## Friendship rises by one for each request you fill. Tiers:
##   0 Stranger, 1-2 Known face, 3-5 Friend (shares a secret about a fish), 6+ Old friend.
## A request asks for 1-3 fish of one species from the spot's list, favouring species in season.
## Only fish you keep count (legal size, inside the daily limits).
class_name Locals
extends RefCounted

const TIERS: Array[Array] = [[0, "Stranger"], [1, "Known face"], [3, "Friend"], [6, "Old friend"]]
const FRIEND_AT := 3
const COINS_BASE := 20
const XP_PER_FISH := 20

## spot id -> person. shirt/hat: how they are drawn on the shore. lines: what they say by tier.
const PEOPLE := {
	"galata_bridge": {"name": "Hasan Amca", "role": "retired ferry engineer, forty years on this rail", "shirt": Color(0.30, 0.34, 0.45), "hat": true,
		"lines": ["Merhaba. Mind my line, it's been here longer than you.", "Ah, you again. The istavrit are running, eh?", "Sit, sit. Have a tea. My grandson won't fish, you know.", "You fish this bridge like an Istanbullu now."]},
	"teos_harbor": {"name": "Zeynep", "role": "runs boat tours, fishes the harbour after work", "shirt": Color(0.75, 0.30, 0.30), "hat": false,
		"lines": ["Hi. Quiet water today, the tourists scared the fish.", "Back again? Good, I need help filling my bucket.", "You're the only one here who cleans up their line. Respect.", "Come on the boat one evening. I know where the octopus live."]},
	"dikili_bay": {"name": "Mehmet Dayı", "role": "olive farmer, fishes when the harvest allows", "shirt": Color(0.35, 0.50, 0.30), "hat": true,
		"lines": ["Hoş geldin. New here? The bay is kind to beginners.", "The olives can wait. Fish are biting.", "My wife says I talk about you more than my olives.", "Take some olive oil home. For the fish, of course."]},
	"cesme_cove": {"name": "Deniz", "role": "diving instructor, has seen what lives under these rocks", "shirt": Color(0.20, 0.55, 0.70), "hat": false,
		"lines": ["Hey. I've seen fish down there you wouldn't believe.", "You again! Want to know what I saw on today's dive?", "I'll tell you which rocks the bream sit behind. Only you.", "Best fishing partner on the peninsula. Don't tell my students."]},
	"sinop_harbor": {"name": "Rıza Kaptan", "role": "old trawler captain, ashore for good", "shirt": Color(0.20, 0.22, 0.30), "hat": true,
		"lines": ["Hm. Black Sea is no place for soft hands.", "You came back. Most don't, when the wind turns.", "Thirty winters on the trawlers. You remind me of my first mate.", "Kaptan's word: you've earned your sea legs."]},
	"trabzon_coast": {"name": "Fadime Teyze", "role": "sells tea on the harbour, fishes between customers", "shirt": Color(0.60, 0.25, 0.45), "hat": false,
		"lines": ["Çay? First one is free. The fish are not.", "Sit, sit. Your tea is ready, I saw you coming.", "My hamsi pilaf needs fish. And you need feeding.", "You're family now. The tea is always free."]},
	"canakkale_kordon": {"name": "Kemal Usta", "role": "mends nets on the waterfront, fishes the strait every morning", "shirt": Color(0.45, 0.40, 0.30), "hat": true,
		"lines": ["The strait runs hard today. Hold your rig down.", "Ah, the one who doesn't fear the current.", "When the lüfer come through, you stand next to me.", "Usta to usta now. The strait knows you."]},
	"fethiye_bay": {"name": "Ali", "role": "young spearfisher who switched to the rod", "shirt": Color(0.85, 0.55, 0.20), "hat": false,
		"lines": ["Yo. Rod fishing is harder than spearfishing, honestly.", "Teach me something new today?", "Okay, you're better than me. I admit it.", "Partner! Let's fish the point at dawn."]},
	"kas_coast": {"name": "Selin", "role": "marine biology student counting fish for her thesis", "shirt": Color(0.40, 0.60, 0.55), "hat": true,
		"lines": ["Hello! Could you tell me what you catch? It's for my thesis.", "Your catch notes are better than my professor's.", "I'll put you in the acknowledgements, I promise.", "Co-author material. Seriously."]},
	"antalya_gulf": {"name": "Osman Abi", "role": "runs a beach café, fishes at sunrise before opening", "shirt": Color(0.90, 0.85, 0.75), "hat": true,
		"lines": ["Günaydın! Café opens at nine, fish open at six.", "Back for the sunrise bite? Good choice.", "The grill is hot when you bring me fish.", "Your table is always reserved, abi."]},
}


static func person(spot_id: String) -> Dictionary:
	return PEOPLE.get(spot_id, {})


static func friendship(spot_id: String) -> int:
	return int(GameSession.local_friend.get(spot_id, 0))


## Index into TIERS for a friendship value.
static func tier(f: int) -> int:
	var t := 0
	for i in TIERS.size():
		if f >= int(TIERS[i][0]):
			t = i
	return t


static func tier_name(spot_id: String) -> String:
	return String(TIERS[tier(friendship(spot_id))][1])


## The open request at this spot: {species, need, have}. Made on first ask and kept (saved) until filled.
static func request(spot_id: String) -> Dictionary:
	var r: Dictionary = GameSession.local_req.get(spot_id, {})
	if not r.is_empty():
		return r
	var spot := FishingSpots.get_spot(spot_id)
	var ids: Array = spot.get("species", [])
	if ids.is_empty():
		return {}
	var f := friendship(spot_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [spot_id, f])
	# Weighted like the daily challenge: in-season and cheap (common) species ask more often.
	var total := 0.0
	var weights: Array[float] = []
	for sid: String in ids:
		var w := Season.factor(sid) / sqrt(maxf(float(BiomeDB.get_species(sid)["base_price"]), 1.0))
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	var species := String(ids[0])
	for i in ids.size():
		pick -= weights[i]
		if pick <= 0.0:
			species = String(ids[i])
			break
	r = {"species": species, "need": 1 + mini(f / 2, 2), "have": 0}
	GameSession.local_req[spot_id] = r
	GameSession.save()
	return r


## A fish was kept here. Counts toward the request if it is the asked species. True if it counted.
static func on_kept(spot_id: String, species: String) -> bool:
	if not PEOPLE.has(spot_id):
		return false
	var r := request(spot_id)
	if r.is_empty() or String(r["species"]) != species or int(r["have"]) >= int(r["need"]):
		return false
	r["have"] = int(r["have"]) + 1
	GameSession.local_req[spot_id] = r
	GameSession.save()
	return true


static func can_turn_in(spot_id: String) -> bool:
	var r := request(spot_id)
	return not r.is_empty() and int(r["have"]) >= int(r["need"])


static func reward_coins(spot_id: String) -> int:
	var r := request(spot_id)
	if r.is_empty():
		return 0
	return COINS_BASE + int(float(BiomeDB.get_species(String(r["species"]))["base_price"]) * float(r["need"]))


## Hands the fish over: coins, XP, +1 friendship, a fresh request. {coins, xp, tier_up, tier}.
static func turn_in(spot_id: String) -> Dictionary:
	if not can_turn_in(spot_id):
		return {}
	var r := request(spot_id)
	var coins := reward_coins(spot_id)
	var xp := XP_PER_FISH * int(r["need"])
	var before := tier(friendship(spot_id))
	GameSession.local_friend[spot_id] = friendship(spot_id) + 1
	GameSession.local_req.erase(spot_id)
	GameSession.coins += coins
	GameSession.xp += xp
	GameSession.save()
	var after := tier(friendship(spot_id))
	return {"coins": coins, "xp": xp, "tier_up": after > before, "tier": String(TIERS[after][1])}


static func species_name(id: String) -> String:
	return BiomeDB.display_name(id)


## What the person says now: a greeting for the tier, the request, and from Friend on a secret.
static func talk_lines(spot_id: String) -> PackedStringArray:
	var p := person(spot_id)
	var out := PackedStringArray()
	if p.is_empty():
		return out
	var lines: Array = p["lines"]
	out.append("\"%s\"" % String(lines[mini(tier(friendship(spot_id)), lines.size() - 1)]))
	var r := request(spot_id)
	if not r.is_empty():
		var sname := species_name(String(r["species"]))
		if can_turn_in(spot_id):
			out.append("\"You brought the %s! Hand them over.\"" % sname.to_lower())
		else:
			out.append("\"Bring me %d %s and I'll make it worth your while.\"  (%d / %d)" % [int(r["need"]), sname.to_lower(), int(r["have"]), int(r["need"])])
	if friendship(spot_id) >= FRIEND_AT:
		out.append(secret(spot_id))
	return out


## A tip only a friend gets: when one of the spot's species feeds and what it takes.
static func secret(spot_id: String) -> String:
	var ids: Array = FishingSpots.get_spot(spot_id).get("species", [])
	if ids.is_empty():
		return ""
	var sid := String(ids[(friendship(spot_id) + 1) % ids.size()])
	var when := String({"night": "after dark", "day": "in daylight", "twilight": "at dawn and dusk"}.get(BiomeDB.activity_kind(sid), "at dawn and dusk"))
	var baits := Tackle.best_baits(sid, 1)
	var bait := baits[0] if not baits.is_empty() else "a good bait"
	return "Between us: the %s here feed %s. Use %s, hook %s." % [species_name(sid).to_lower(), when, bait, Tackle.hook_range(sid)]


## What the local calls out when you land a fish near them: by its size within the species' range,
## or a nod when you release one. Game-design fill.
static func react(species: String, kg: float, released: bool) -> String:
	if released:
		return "Good, put it back. Let it grow."
	var wr: Vector2 = BiomeDB.get_species(species)["weight_kg"]
	var f := clampf((kg - wr.x) / maxf(wr.y - wr.x, 0.01), 0.0, 1.0)
	if f > 0.6:
		return "Maşallah! That's a real %s!" % species_name(species).to_lower()
	if f > 0.25:
		return "Nice %s. Dinner tonight." % species_name(species).to_lower()
	return "Small, but it counts."
