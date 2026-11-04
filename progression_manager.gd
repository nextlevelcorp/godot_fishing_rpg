## Player economy and progression: money, XP, level, gear upgrades, cargo and selling.
## Needs the BiomeDB autoload. Add as a Node in the main scene and set `current_zone`.
##
## Fish value = base_price * sqrt(weight_kg) * grade_mult * market_mult
##   market_mult = (1 + 0.8 * distance_caught_to_sold / 12000 km) * (0.85 if the sell zone already has the species)
class_name ProgressionManager
extends Node

signal money_changed(money: int)
signal xp_changed(xp: int, xp_needed: int, level: int)
signal leveled_up(new_level: int)
signal fish_stored(item: Dictionary)
signal cargo_rejected(item: Dictionary, reason: String)
signal fish_sold(summary: Dictionary)
signal gear_upgraded(track: String, new_level: int)

const MAX_PLAYER_LEVEL := 30
const BASE_LINE_DAMPING := 18.0

const GRADES := {
	"normal": {"name": "Normal", "value_mult": 1.0, "xp_mult": 1.0, "min_size01": 0.0},
	"rare": {"name": "Rare", "value_mult": 1.8, "xp_mult": 1.6, "min_size01": 0.45},
	"trophy": {"name": "Trophy", "value_mult": 3.5, "xp_mult": 3.0, "min_size01": 0.80},
}
const GRADE_ORDER := ["trophy", "rare", "normal"]

# Each track: ordered tiers. Tier 0 is what you start with. "value" is the stat that tier gives.
const UPGRADES := {
	"engine": {"name": "Boat Engine", "stat": "Thrust Force (N)", "levels": [
		{"name": "Rusty 15 hp Outboard", "value": 2600.0, "cost": 0, "min_level": 1},
		{"name": "Tuned 25 hp Outboard", "value": 3300.0, "cost": 350, "min_level": 3},
		{"name": "40 hp Four-Stroke", "value": 4200.0, "cost": 1100, "min_level": 7},
		{"name": "90 hp Twin Outboard", "value": 5300.0, "cost": 3000, "min_level": 14},
		{"name": "Offshore Diesel Inboard", "value": 6800.0, "cost": 8000, "min_level": 22},
	]},
	"hull": {"name": "Cargo Hull", "stat": "Weight Limit (kg)", "levels": [
		{"name": "Wooden Skiff", "value": 40.0, "cost": 0, "min_level": 1},
		{"name": "Fish Box Hull", "value": 80.0, "cost": 300, "min_level": 2},
		{"name": "Decked Trawler Hull", "value": 150.0, "cost": 900, "min_level": 6},
		{"name": "Insulated Hold", "value": 260.0, "cost": 2400, "min_level": 12},
		{"name": "Refrigerated Hold", "value": 420.0, "cost": 6500, "min_level": 20},
	]},
	"reel": {"name": "Fishing Reel", "stat": "Line Snap Threshold Bonus (N)", "levels": [
		{"name": "Basic Spinning Reel", "value": 0.0, "cost": 0, "min_level": 1},
		{"name": "Sealed Drag Reel", "value": 10.0, "cost": 250, "min_level": 2},
		{"name": "Carbon Drag Reel", "value": 25.0, "cost": 800, "min_level": 6},
		{"name": "Saltwater Lever-Drag Reel", "value": 45.0, "cost": 2200, "min_level": 12},
		{"name": "Tournament Big-Game Reel", "value": 70.0, "cost": 6000, "min_level": 20},
	]},
	"rod": {"name": "Fishing Rod", "stat": "Line Damping Bonus (N*s/m)", "levels": [
		{"name": "Fibreglass Rod", "value": 0.0, "cost": 0, "min_level": 1},
		{"name": "Graphite Composite Rod", "value": 4.0, "cost": 250, "min_level": 2},
		{"name": "Slow-Taper Graphite Rod", "value": 9.0, "cost": 800, "min_level": 6},
		{"name": "Hybrid Carbon Rod", "value": 15.0, "cost": 2200, "min_level": 12},
		{"name": "Pro Shock-Absorber Rod", "value": 22.0, "cost": 6000, "min_level": 20},
	]},
	# Sonar: "value" is range in px. detail 0 = blips only, 1 = + size class, 2 = + exact depth.
	"sonar": {"name": "Sonar", "stat": "Detection Range (px)", "levels": [
		{"name": "Basic Fishfinder", "value": 220.0, "cost": 0, "min_level": 1, "detail": 0, "detect_prob": 0.70, "pos_error_px": 14.0, "ghost_rate": 0.30, "ping_interval_s": 2.4},
		{"name": "Coastal Fishfinder", "value": 300.0, "cost": 400, "min_level": 4, "detail": 0, "detect_prob": 0.82, "pos_error_px": 9.0, "ghost_rate": 0.20, "ping_interval_s": 2.0},
		{"name": "Advanced Chrono-Sonar", "value": 380.0, "cost": 1500, "min_level": 8, "detail": 1, "detect_prob": 0.90, "pos_error_px": 5.0, "ghost_rate": 0.10, "ping_interval_s": 1.6},
		{"name": "Chrono-Sonar Pro", "value": 480.0, "cost": 4200, "min_level": 15, "detail": 2, "detect_prob": 0.95, "pos_error_px": 2.5, "ghost_rate": 0.04, "ping_interval_s": 1.2},
		{"name": "Chrono-Sonar Elite", "value": 620.0, "cost": 9000, "min_level": 22, "detail": 2, "detect_prob": 0.99, "pos_error_px": 1.0, "ghost_rate": 0.0, "ping_interval_s": 0.9},
	]},
}

@export var starting_money := 100
@export var hard_limit_ratio := 1.3
@export var current_zone := "aegean_sea"       ## where the player is right now (catch origin and market)
@export var print_telemetry := false

var money := 0
var xp := 0                                    ## XP inside the current level
var level := 1
var gear := {"engine": 0, "hull": 0, "reel": 0, "rod": 0, "sonar": 0}
var cargo := CargoHold.new()


func _ready() -> void:
	money = starting_money
	_sync_hold()
	money_changed.emit(money)
	xp_changed.emit(xp, xp_needed(), level)


# ------------------------------------------------------------------ stats
func stat(track: String) -> float:
	return UPGRADES[track]["levels"][gear[track]]["value"]


func tier_name(track: String) -> String:
	return UPGRADES[track]["levels"][gear[track]]["name"]


func cargo_ratio() -> float:
	return cargo.ratio()


## Full data row of the installed sonar tier (range in "value", plus detail, accuracy, ping speed).
func sonar_profile() -> Dictionary:
	return UPGRADES["sonar"]["levels"][gear["sonar"]]


func xp_needed() -> int:
	return int(100.0 * pow(level, 1.5))


func unlocked_zones() -> Array[String]:
	return BiomeDB.zones_for_level(level)


func _sync_hold() -> void:
	cargo.capacity_kg = stat("hull")
	cargo.hard_limit_ratio = hard_limit_ratio


# ------------------------------------------------------------------ fishing hookup
func bind_fishing(fc: FishingController) -> void:
	fc.fish_caught.connect(func(fish_id: String, kg: float) -> void: register_catch(fish_id, kg, current_zone))


## Call right before fc.hook_fish(): applies the rig, then the reel and rod upgrades on top.
func prepare_fight(fc: FishingController, rig_id: String) -> void:
	fc.apply_rig(BiomeDB.get_rig(rig_id))
	var reel := stat("reel")
	fc.line_break_force_n += reel                  # higher snap threshold
	fc.drag_max_n += reel * 0.65                   # clutch can be set harder too
	fc.line_damping = BASE_LINE_DAMPING + stat("rod")   # rod absorbs fast pulls
	fc.drag_setting_n = clampf(fc.drag_setting_n, fc.drag_min_n, minf(fc.drag_max_n, fc.line_break_force_n * 0.95))


# ------------------------------------------------------------------ catching
func grade_for(species_id: String, weight_kg: float) -> String:
	var r: Vector2 = BiomeDB.get_species(species_id)["weight_kg"]
	var size01 := clampf(inverse_lerp(r.x, r.y, weight_kg), 0.0, 1.0)
	for g: String in GRADE_ORDER:
		if size01 >= float(GRADES[g]["min_size01"]):
			return g
	return "normal"


## Builds the fish item, grants XP (always), and stores it if the hold can take it.
func register_catch(species_id: String, weight_kg: float, zone_id: String) -> Dictionary:
	var sp := BiomeDB.get_species(species_id)
	var grade := grade_for(species_id, weight_kg)
	var wr: Vector2 = sp["weight_kg"]
	var size01 := clampf(inverse_lerp(wr.x, wr.y, weight_kg), 0.0, 1.0)
	var item := {
		"species_id": species_id, "name": sp["name"], "weight_kg": weight_kg,
		"grade": grade, "caught_zone": zone_id,
	}
	_add_xp(int(8.0 * sqrt(float(sp["base_price"])) * float(GRADES[grade]["xp_mult"]) * (0.5 + size01)))
	if cargo.add(item):
		fish_stored.emit(item)
	else:
		cargo_rejected.emit(item, "Hold is full: this fish is too heavy to haul aboard.")
	return item


func _add_xp(amount: int) -> void:
	if level >= MAX_PLAYER_LEVEL:
		return
	xp += amount
	while xp >= xp_needed() and level < MAX_PLAYER_LEVEL:
		xp -= xp_needed()
		level += 1
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_needed(), level)


# ------------------------------------------------------------------ market
## Far-from-home fish are exotic (up to +80%); fish the local market already has sell cheaper (x0.85).
func market_multiplier(species_id: String, caught_zone: String, sell_zone: String) -> float:
	var a: Vector2 = BiomeDB.ZONES[caught_zone]["lat_lon"]
	var b: Vector2 = BiomeDB.ZONES[sell_zone]["lat_lon"]
	var exotic := 1.0 + clampf(_haversine_km(a, b) / 12000.0, 0.0, 1.0) * 0.8
	var local := 0.85 if BiomeDB.ZONES[sell_zone]["species"].has(species_id) else 1.0
	return exotic * local


func item_value(item: Dictionary, sell_zone: String) -> int:
	var sp := BiomeDB.get_species(item["species_id"])
	var raw := float(sp["base_price"]) * sqrt(float(item["weight_kg"])) * float(GRADES[item["grade"]]["value_mult"])
	return int(round(raw * market_multiplier(item["species_id"], item["caught_zone"], sell_zone)))


## Sells the whole hold at the market of sell_zone.
func sell_all(sell_zone: String) -> Dictionary:
	var total := 0
	var lines: Array[Dictionary] = []
	for item: Dictionary in cargo.clear():
		var value := item_value(item, sell_zone)
		total += value
		lines.append({
			"fish": item["name"], "grade": GRADES[item["grade"]]["name"], "kg": item["weight_kg"],
			"caught_in": item["caught_zone"], "market_mult": market_multiplier(item["species_id"], item["caught_zone"], sell_zone),
			"value": value,
		})
	money += total
	var summary := {"zone": sell_zone, "count": lines.size(), "total": total, "lines": lines}
	money_changed.emit(money)
	fish_sold.emit(summary)
	return summary


# ------------------------------------------------------------------ upgrades
## Returns {ok, reason}. Pays and applies the next tier of a track if allowed.
func try_upgrade(track: String) -> Dictionary:
	if not UPGRADES.has(track):
		return {"ok": false, "reason": "Unknown upgrade track."}
	var tiers: Array = UPGRADES[track]["levels"]
	var next_index: int = gear[track] + 1
	if next_index >= tiers.size():
		return {"ok": false, "reason": "%s is already at maximum tier." % UPGRADES[track]["name"]}
	var tier: Dictionary = tiers[next_index]
	if level < int(tier["min_level"]):
		return {"ok": false, "reason": "Requires player level %d." % int(tier["min_level"])}
	if money < int(tier["cost"]):
		return {"ok": false, "reason": "Need %d more coins." % (int(tier["cost"]) - money)}
	money -= int(tier["cost"])
	gear[track] = next_index
	_sync_hold()
	money_changed.emit(money)
	gear_upgraded.emit(track, next_index)
	return {"ok": true, "reason": "Installed: %s" % tier["name"]}


# ------------------------------------------------------------------ save / load / debug
func to_dict() -> Dictionary:
	return {"money": money, "xp": xp, "level": level, "gear": gear.duplicate(), "cargo": cargo.items.duplicate(true), "zone": current_zone}


func from_dict(d: Dictionary) -> void:
	money = d.get("money", starting_money)
	xp = d.get("xp", 0)
	level = d.get("level", 1)
	var saved_gear: Dictionary = d.get("gear", {})
	for track: String in gear:
		gear[track] = int(saved_gear.get(track, 0))
	current_zone = d.get("zone", current_zone)
	_sync_hold()
	cargo.restore(d.get("cargo", []))
	money_changed.emit(money)
	xp_changed.emit(xp, xp_needed(), level)


func telemetry_line() -> String:
	return "lvl %d (%d/%d xp) | %d coins | hold %.0f/%.0f kg | engine %.0f N | reel +%.0f N | rod +%.0f" % [
		level, xp, xp_needed(), money, cargo.total_kg, cargo.capacity_kg, stat("engine"), stat("reel"), stat("rod")]


static func _haversine_km(a: Vector2, b: Vector2) -> float:
	var la1 := deg_to_rad(a.x)
	var la2 := deg_to_rad(b.x)
	var dlat := la2 - la1
	var dlon := deg_to_rad(b.y - a.y)
	var h := sin(dlat * 0.5) * sin(dlat * 0.5) + cos(la1) * cos(la2) * sin(dlon * 0.5) * sin(dlon * 0.5)
	return 12742.0 * asin(minf(1.0, sqrt(h)))
