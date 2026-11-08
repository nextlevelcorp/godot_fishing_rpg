## One challenge a day, the same for everyone on that date: a species at a spot, at least a weight.
## Picked from the spots you have unlocked, favouring species in season. Reward once per day.
class_name Daily
extends RefCounted

const XP := 40


static func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## {spot, spot_name, species, species_name, min_kg, coins}; empty when nothing is unlocked.
static func challenge() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(today_key())
	var spots: Array[String] = []
	for id: String in FishingSpots.ids():
		if GameSession.is_unlocked(FishingSpots.get_spot(id)):
			spots.append(id)
	if spots.is_empty():
		return {}
	var spot_id := spots[rng.randi() % spots.size()]
	var spot := FishingSpots.get_spot(spot_id)
	var ids: Array = spot["species"]
	# Weighted pick: in-season species more likely, rare ones less.
	var total := 0.0
	var weights: Array[float] = []
	for sid: String in ids:
		var w := Season.factor(sid) / sqrt(float(BiomeDB.get_species(sid)["base_price"]))
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	var species := String(ids[ids.size() - 1])
	for i in ids.size():
		pick -= weights[i]
		if pick <= 0.0:
			species = String(ids[i])
			break
	var sp := BiomeDB.get_species(species)
	var wr: Vector2 = sp["weight_kg"]
	# About half of the fish of this species that bite reach this weight (median of roll_weight_kg).
	var min_kg := maxf(snappedf(wr.x + 0.22 * (wr.y - wr.x), 0.05), 0.05)
	return {"spot": spot_id, "spot_name": String(spot["name"]), "species": species,
		"species_name": BiomeDB.display_name(species), "min_kg": min_kg, "coins": 120 + int(sp["base_price"])}


static func done_today() -> bool:
	return GameSession.daily_done == today_key()


## Checks a landed fish against today's challenge; pays out once. Returns the coins paid, or 0.
static func try_complete(spot_id: String, species: String, kg: float) -> int:
	if done_today():
		return 0
	var c := challenge()
	if c.is_empty() or c["spot"] != spot_id or c["species"] != species or kg < float(c["min_kg"]):
		return 0
	GameSession.daily_done = today_key()
	GameSession.coins += int(c["coins"])
	GameSession.xp += XP
	GameSession.save()
	return int(c["coins"])


static func text() -> String:
	var c := challenge()
	if c.is_empty():
		return "No challenge today."
	var status := "DONE today. A new one tomorrow." if done_today() else "Reward: %d coins and %d XP." % [int(c["coins"]), XP]
	return "Catch a %s of at least %.2f kg at %s.\n%s" % [c["species_name"], float(c["min_kg"]), c["spot_name"], status]
