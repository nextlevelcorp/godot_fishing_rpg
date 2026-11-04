## Autoload this script as "BiomeDB" (Project Settings > Globals > Autoload).
## Single source of truth for zones, species, rigs and baits. Pure data + lookups.
## Every cross-reference is checked in validate() at startup (explicit telemetry).
extends Node

# ---------------------------------------------------------------- RIGS
# rod_stiffness: N/m, line_stiffness: N/m, line_break_force_n: N, drag_max_n: N (reel clutch ceiling)
const RIGS := {
	"light_bottom_rig": {"name": "Light Bottom Rig", "rod_stiffness": 90.0, "line_stiffness": 900.0, "line_break_force_n": 35.0, "drag_max_n": 22.0, "spool_m": 90.0, "min_level": 1},
	"light_spinning_rig": {"name": "Light Spinning Rig", "rod_stiffness": 100.0, "line_stiffness": 950.0, "line_break_force_n": 48.0, "drag_max_n": 30.0, "spool_m": 120.0, "min_level": 5},
	"heavy_river_baitcaster": {"name": "Heavy River Baitcaster", "rod_stiffness": 170.0, "line_stiffness": 1500.0, "line_break_force_n": 110.0, "drag_max_n": 70.0, "spool_m": 140.0, "min_level": 10},
	"deep_sea_boat_rig": {"name": "Deep Sea Boat Rig", "rod_stiffness": 190.0, "line_stiffness": 1700.0, "line_break_force_n": 95.0, "drag_max_n": 62.0, "spool_m": 260.0, "min_level": 15},
	"heavy_saltwater_spinning": {"name": "Heavy Saltwater Spinning", "rod_stiffness": 210.0, "line_stiffness": 1900.0, "line_break_force_n": 125.0, "drag_max_n": 85.0, "spool_m": 200.0, "min_level": 20},
}

# ---------------------------------------------------------------- BAITS
const BAITS := {
	"live_sandworm": {"name": "Live Sand-worm", "kind": "live", "bite_bonus": 1.0},
	"cut_squid": {"name": "Cut Squid", "kind": "natural", "bite_bonus": 0.9},
	"live_shrimp": {"name": "Live Shrimp", "kind": "live", "bite_bonus": 1.0},
	"live_baitfish": {"name": "Live Baitfish", "kind": "live", "bite_bonus": 1.2},
	"soft_plastic_shad": {"name": "Soft Plastic Shad", "kind": "lure", "bite_bonus": 0.85},
	"crankbait": {"name": "Crankbait", "kind": "lure", "bite_bonus": 0.9},
	"heavy_jig": {"name": "Heavy Jig", "kind": "lure", "bite_bonus": 1.0},
	"surface_popper": {"name": "Surface Popper", "kind": "lure", "bite_bonus": 1.1},
	"sinking_stickbait": {"name": "Sinking Stickbait", "kind": "lure", "bite_bonus": 0.95},
}

# ---------------------------------------------------------------- BITE PROFILES
# How a species takes bait (used by FishInteractionAI). Missing keys fall back to BITE_DEFAULT.
#   caution          0..1   hesitation before swallowing; high = many light nibbles, slow commit
#   noise_hz                speed of the 1D Perlin nibble pulses (nibble rate is about 0.4 * noise_hz per second)
#   nibble_force_n          rod-tip tension spike of one light nibble
#   nibbles          min,max nibbles before the fish may commit (0,0 = strikes at once)
#   strike_force_n          tension of the solid bite
#   bite_window_s           seconds the player has to set the hook after the solid bite
#   spook_chance            chance that reeling during a nibble scares the fish off
#   self_hook_chance        chance the fish hooks itself if the window is missed
#   max_nibble_s            fish gives up after this long without committing
#   appetite         0..1.2 overall interest multiplier
const BITE_DEFAULT := {
	"caution": 0.5, "noise_hz": 0.9, "nibble_force_n": 2.0, "nibbles": Vector2i(1, 3),
	"strike_force_n": 10.0, "bite_window_s": 0.9, "spook_chance": 0.7, "self_hook_chance": 0.0,
	"max_nibble_s": 18.0, "appetite": 0.8,
}

const BITE_PROFILES := {
	# Aegean
	"gilthead_seabream": {"caution": 0.78, "noise_hz": 1.1, "nibble_force_n": 1.6, "nibbles": Vector2i(3, 6), "strike_force_n": 7.0, "bite_window_s": 0.9, "spook_chance": 1.0, "max_nibble_s": 25.0, "appetite": 0.85},
	"european_seabass": {"caution": 0.55, "noise_hz": 1.3, "nibble_force_n": 2.2, "nibbles": Vector2i(1, 3), "strike_force_n": 12.0, "bite_window_s": 0.8, "spook_chance": 0.8, "appetite": 0.85},
	"red_mullet": {"caution": 0.40, "noise_hz": 2.0, "nibble_force_n": 1.0, "nibbles": Vector2i(2, 5), "strike_force_n": 4.0, "bite_window_s": 1.1, "spook_chance": 0.5, "appetite": 0.9},
	"european_anchovy": {"caution": 0.20, "noise_hz": 3.0, "nibble_force_n": 0.6, "nibbles": Vector2i(1, 3), "strike_force_n": 1.5, "bite_window_s": 1.0, "spook_chance": 0.2, "appetite": 1.0},
	"bluefish": {"caution": 0.08, "noise_hz": 3.2, "nibble_force_n": 5.0, "nibbles": Vector2i(0, 0), "strike_force_n": 34.0, "bite_window_s": 0.55, "spook_chance": 0.1, "self_hook_chance": 0.35, "max_nibble_s": 4.0, "appetite": 1.0},
	# Tokyo Bay
	"japanese_seabass": {"caution": 0.50, "noise_hz": 1.2, "nibble_force_n": 2.4, "nibbles": Vector2i(1, 3), "strike_force_n": 14.0, "bite_window_s": 0.8, "spook_chance": 0.8, "appetite": 0.9},
	"red_seabream": {"caution": 0.70, "noise_hz": 1.0, "nibble_force_n": 2.0, "nibbles": Vector2i(2, 5), "strike_force_n": 10.0, "bite_window_s": 0.9, "spook_chance": 0.95, "max_nibble_s": 22.0},
	"japanese_horse_mackerel": {"caution": 0.25, "noise_hz": 3.0, "nibble_force_n": 0.8, "nibbles": Vector2i(1, 4), "strike_force_n": 3.5, "bite_window_s": 1.0, "spook_chance": 0.2, "appetite": 1.0},
	# Amazon
	"peacock_bass": {"caution": 0.15, "noise_hz": 2.6, "nibble_force_n": 4.0, "nibbles": Vector2i(0, 1), "strike_force_n": 28.0, "bite_window_s": 0.6, "spook_chance": 0.2, "self_hook_chance": 0.25, "max_nibble_s": 6.0, "appetite": 1.0},
	"red_tailed_catfish": {"caution": 0.35, "noise_hz": 0.5, "nibble_force_n": 5.0, "nibbles": Vector2i(1, 2), "strike_force_n": 30.0, "bite_window_s": 1.4, "spook_chance": 0.4, "max_nibble_s": 20.0},
	"arapaima": {"caution": 0.40, "noise_hz": 0.45, "nibble_force_n": 6.0, "nibbles": Vector2i(1, 3), "strike_force_n": 40.0, "bite_window_s": 1.3, "spook_chance": 0.5, "max_nibble_s": 24.0},
	# North Sea
	"atlantic_cod": {"caution": 0.30, "noise_hz": 0.8, "nibble_force_n": 5.0, "nibbles": Vector2i(1, 2), "strike_force_n": 24.0, "bite_window_s": 1.0, "spook_chance": 0.4},
	"haddock": {"caution": 0.50, "noise_hz": 1.2, "nibble_force_n": 3.0, "nibbles": Vector2i(2, 4), "strike_force_n": 14.0, "bite_window_s": 0.9, "spook_chance": 0.7},
	"atlantic_halibut": {"caution": 0.45, "noise_hz": 0.4, "nibble_force_n": 6.0, "nibbles": Vector2i(1, 3), "strike_force_n": 38.0, "bite_window_s": 1.5, "spook_chance": 0.5, "max_nibble_s": 30.0},
	# Great Barrier Reef
	"giant_trevally": {"caution": 0.05, "noise_hz": 3.5, "nibble_force_n": 8.0, "nibbles": Vector2i(0, 0), "strike_force_n": 55.0, "bite_window_s": 0.5, "spook_chance": 0.05, "self_hook_chance": 0.45, "max_nibble_s": 3.0, "appetite": 1.1},
	"coral_trout": {"caution": 0.30, "noise_hz": 1.6, "nibble_force_n": 4.0, "nibbles": Vector2i(0, 2), "strike_force_n": 26.0, "bite_window_s": 0.7, "spook_chance": 0.5},
	"swordfish": {"caution": 0.60, "noise_hz": 0.5, "nibble_force_n": 8.0, "nibbles": Vector2i(2, 4), "strike_force_n": 60.0, "bite_window_s": 1.2, "spook_chance": 0.6, "max_nibble_s": 30.0, "appetite": 0.9},
	"spanish_mackerel": {"caution": 0.10, "noise_hz": 3.0, "nibble_force_n": 5.0, "nibbles": Vector2i(0, 0), "strike_force_n": 32.0, "bite_window_s": 0.5, "spook_chance": 0.1, "self_hook_chance": 0.2, "max_nibble_s": 4.0, "appetite": 1.0},
}

# ---------------------------------------------------------------- WEATHER TRAITS
# How a species reacts to the weather (read by FishSchool and FishInteractionAI).
#   storm_dive_m   metres the school sinks at full sea turbulence. Predators also follow their prey school's dive.
#   gate_states    the species only surfaces and bites in these weather states ("calm", "overcast", "gale", "storm")
#   open_depth_m   depth band used while the gate is open; otherwise the (deep) species band applies
const WEATHER_TRAITS := {
	"european_anchovy": {"storm_dive_m": 24.0},
	"red_mullet": {"storm_dive_m": 8.0},
	"japanese_horse_mackerel": {"storm_dive_m": 12.0},
	"bluefish": {"storm_dive_m": 16.0},
	"european_seabass": {"storm_dive_m": 6.0},
	"gilthead_seabream": {"storm_dive_m": 5.0},
	"swordfish": {"gate_states": ["gale"], "open_depth_m": Vector2(2.0, 30.0)},
}

# ---------------------------------------------------------------- ZONES
# thermal bands in FISH are normalised 0..1 across a zone's water_temp_c range.
const ZONES := {
	"aegean_sea": {
		"name": "Aegean Sea (Cesme / Izmir)", "region": "Turkey", "lat_lon": Vector2(38.32, 26.30),
		"level_range": Vector2i(1, 5), "water_temp_c": Vector2(15.0, 26.0), "max_depth_m": 120.0,
		"current_px_s": 18.0, "wind_px_s": 14.0,
		"baits": ["live_sandworm", "cut_squid"], "rigs": ["light_bottom_rig"],
		"species": ["gilthead_seabream", "european_seabass", "red_mullet", "bluefish", "european_anchovy"],
		"description": "Sun-bleached bays, posidonia meadows and calm morning water. The perfect first cast.",
	},
	"tokyo_bay": {
		"name": "Tokyo Bay", "region": "Japan", "lat_lon": Vector2(35.40, 139.80),
		"level_range": Vector2i(6, 14), "water_temp_c": Vector2(11.0, 27.0), "max_depth_m": 70.0,
		"current_px_s": 26.0, "wind_px_s": 18.0,
		"baits": ["live_shrimp", "soft_plastic_shad"], "rigs": ["light_spinning_rig"],
		"species": ["japanese_seabass", "red_seabream", "japanese_horse_mackerel"],
		"description": "Neon harbours, tidal rips under bridges and legendary shore-to-boat seabass.",
	},
	"amazon_river": {
		"name": "Amazon River", "region": "Brazil", "lat_lon": Vector2(-3.12, -60.02),
		"level_range": Vector2i(10, 20), "water_temp_c": Vector2(26.0, 31.0), "max_depth_m": 50.0,
		"current_px_s": 34.0, "wind_px_s": 8.0,
		"baits": ["live_baitfish", "crankbait"], "rigs": ["light_spinning_rig", "heavy_river_baitcaster"],
		"species": ["peacock_bass", "red_tailed_catfish", "arapaima"],
		"description": "Black-water lagoons and flooded forest where giants hide under floating meadows.",
	},
	"north_sea_fjords": {
		"name": "North Sea (Norway Fjords)", "region": "Norway", "lat_lon": Vector2(60.20, 6.50),
		"level_range": Vector2i(15, 25), "water_temp_c": Vector2(4.0, 14.0), "max_depth_m": 500.0,
		"current_px_s": 30.0, "wind_px_s": 32.0,
		"baits": ["heavy_jig", "cut_squid"], "rigs": ["deep_sea_boat_rig"],
		"species": ["atlantic_cod", "haddock", "atlantic_halibut"],
		"description": "Cold, deep, wind-hammered water. Long drops and heavy fish.",
	},
	"great_barrier_reef": {
		"name": "Great Barrier Reef", "region": "Australia", "lat_lon": Vector2(-18.29, 147.70),
		"level_range": Vector2i(20, 30), "water_temp_c": Vector2(23.0, 30.0), "max_depth_m": 200.0,
		"current_px_s": 28.0, "wind_px_s": 20.0,
		"baits": ["surface_popper", "sinking_stickbait", "heavy_jig"], "rigs": ["heavy_saltwater_spinning"],
		"species": ["giant_trevally", "coral_trout", "spanish_mackerel", "swordfish"],
		"description": "Turquoise flats, coral bommies and apex predators that smash poppers at the surface.",
	},
}

var fish: Dictionary = {}


func _init() -> void:
	fish = _build_fish()


func _ready() -> void:
	validate()


# ---------------------------------------------------------------- FISH
static func _fish(display: String, sci: String, role: String, kg: Vector2, thermal: Vector2,
		depth: Vector2, schooling: bool, pull_n: float, drain: float,
		burst_every: Vector2, burst_mult: Vector2, price: int) -> Dictionary:
	return {
		"name": display, "scientific": sci, "role": role,
		"weight_kg": kg, "thermal_band": thermal, "depth_m": depth,
		"schooling": schooling, "base_price": price,
		"fight": {
			"pull_n": pull_n,                    # peak pull of a max-size fish
			"stamina_drain": drain,              # stamina lost per newton per second
			"burst_every_s": burst_every,        # random gap between runs
			"burst_mult": burst_mult,            # pull multiplier during a run
			"burst_len_s": Vector2(0.5, 1.4),
			"rest_recovery": 0.02,               # stamina/s regained while line is slack
		},
	}


func _build_fish() -> Dictionary:
	return {
		# Aegean
		"gilthead_seabream": _fish("Gilthead Seabream", "Sparus aurata", "prey", Vector2(0.4, 4.0), Vector2(0.35, 0.80), Vector2(2, 40), true, 13.0, 0.0035, Vector2(3.0, 6.0), Vector2(1.5, 2.1), 40),
		"european_seabass": _fish("European Seabass", "Dicentrarchus labrax", "predator", Vector2(0.5, 8.0), Vector2(0.30, 0.70), Vector2(1, 30), false, 17.0, 0.0032, Vector2(3.0, 6.0), Vector2(1.6, 2.2), 65),
		"red_mullet": _fish("Red Mullet", "Mullus barbatus", "prey", Vector2(0.1, 0.6), Vector2(0.30, 0.75), Vector2(5, 60), true, 6.0, 0.0045, Vector2(4.0, 8.0), Vector2(1.3, 1.7), 25),
		"european_anchovy": _fish("European Anchovy", "Engraulis encrasicolus", "prey", Vector2(0.01, 0.05), Vector2(0.35, 0.75), Vector2(0.5, 15), true, 1.5, 0.006, Vector2(3.0, 6.0), Vector2(1.2, 1.4), 8),
		"bluefish": _fish("Bluefish (Lufer)", "Pomatomus saltatrix", "predator", Vector2(0.3, 14.0), Vector2(0.40, 0.90), Vector2(0.5, 40), true, 26.0, 0.0030, Vector2(2.5, 5.0), Vector2(1.7, 2.4), 70),
		# Tokyo Bay
		"japanese_seabass": _fish("Japanese Seabass", "Lateolabrax japonicus", "predator", Vector2(0.5, 9.0), Vector2(0.35, 0.80), Vector2(1, 30), false, 18.0, 0.0030, Vector2(3.0, 5.5), Vector2(1.6, 2.3), 90),
		"red_seabream": _fish("Red Seabream", "Pagrus major", "prey", Vector2(0.5, 10.0), Vector2(0.30, 0.70), Vector2(10, 60), false, 20.0, 0.0030, Vector2(3.5, 6.0), Vector2(1.5, 2.0), 120),
		"japanese_horse_mackerel": _fish("Japanese Horse Mackerel", "Trachurus japonicus", "prey", Vector2(0.05, 0.5), Vector2(0.40, 0.85), Vector2(2, 50), true, 4.0, 0.0050, Vector2(2.5, 5.0), Vector2(1.3, 1.6), 15),
		# Amazon
		"peacock_bass": _fish("Peacock Bass", "Cichla ocellaris", "predator", Vector2(0.5, 6.0), Vector2(0.40, 0.90), Vector2(1, 12), false, 30.0, 0.0028, Vector2(2.5, 4.5), Vector2(1.7, 2.4), 150),
		"red_tailed_catfish": _fish("Red-tailed Catfish", "Phractocephalus hemioliopterus", "predator", Vector2(3.0, 40.0), Vector2(0.30, 0.80), Vector2(5, 40), false, 42.0, 0.0022, Vector2(4.0, 7.0), Vector2(1.5, 2.0), 320),
		"arapaima": _fish("Arapaima", "Arapaima gigas", "predator", Vector2(10.0, 120.0), Vector2(0.40, 0.90), Vector2(1, 15), false, 62.0, 0.0018, Vector2(4.0, 8.0), Vector2(1.6, 2.2), 900),
		# North Sea
		"atlantic_cod": _fish("Atlantic Cod", "Gadus morhua", "predator", Vector2(1.0, 35.0), Vector2(0.20, 0.65), Vector2(20, 300), true, 30.0, 0.0026, Vector2(4.0, 7.0), Vector2(1.4, 1.9), 200),
		"haddock": _fish("Haddock", "Melanogrammus aeglefinus", "prey", Vector2(0.5, 8.0), Vector2(0.20, 0.60), Vector2(30, 300), true, 20.0, 0.0030, Vector2(3.5, 6.5), Vector2(1.4, 1.8), 110),
		"atlantic_halibut": _fish("Atlantic Halibut", "Hippoglossus hippoglossus", "predator", Vector2(5.0, 150.0), Vector2(0.10, 0.50), Vector2(50, 500), false, 50.0, 0.0020, Vector2(5.0, 9.0), Vector2(1.5, 2.1), 650),
		# Great Barrier Reef
		"giant_trevally": _fish("Giant Trevally", "Caranx ignobilis", "predator", Vector2(2.0, 60.0), Vector2(0.40, 0.90), Vector2(1, 80), false, 55.0, 0.0020, Vector2(2.0, 4.0), Vector2(1.8, 2.5), 700),
		"coral_trout": _fish("Coral Trout", "Plectropomus leopardus", "predator", Vector2(0.8, 10.0), Vector2(0.40, 0.85), Vector2(3, 60), false, 36.0, 0.0026, Vector2(3.0, 5.0), Vector2(1.6, 2.2), 380),
		"swordfish": _fish("Swordfish", "Xiphias gladius", "predator", Vector2(40.0, 450.0), Vector2(0.30, 0.80), Vector2(150, 600), false, 80.0, 0.0016, Vector2(2.5, 5.0), Vector2(1.6, 2.2), 2600),
		"spanish_mackerel": _fish("Spanish Mackerel", "Scomberomorus commerson", "predator", Vector2(1.0, 30.0), Vector2(0.30, 0.80), Vector2(2, 70), false, 40.0, 0.0024, Vector2(2.0, 4.0), Vector2(1.7, 2.4), 420),
	}


# ---------------------------------------------------------------- LOOKUPS
func get_zone(id: String) -> Dictionary:
	return ZONES.get(id, {})


func get_species(id: String) -> Dictionary:
	return fish.get(id, {})


func get_rig(id: String) -> Dictionary:
	return RIGS.get(id, {})


func get_bait(id: String) -> Dictionary:
	return BAITS.get(id, {})


## Weather reactions of a species (storm_dive_m, gate_states, open_depth_m), {} if it has none.
func get_weather_traits(species_id: String) -> Dictionary:
	return WEATHER_TRAITS.get(species_id, {})


## BITE_DEFAULT with the species' overrides merged on top.
func get_bite_profile(species_id: String) -> Dictionary:
	var p := BITE_DEFAULT.duplicate()
	p.merge(BITE_PROFILES.get(species_id, {}), true)
	return p


func zones_for_level(level: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in ZONES:
		var r: Vector2i = ZONES[id]["level_range"]
		if level >= r.x:
			out.append(id)
	return out


## Random species of a zone, weighted by rarity (more expensive = rarer).
func roll_species(zone_id: String, rng: RandomNumberGenerator) -> String:
	var zone := get_zone(zone_id)
	var ids: Array = zone.get("species", [])
	if ids.is_empty():
		return ""
	var weights: Array[float] = []
	var total := 0.0
	for id: String in ids:
		var w := 1.0 / sqrt(float(fish[id]["base_price"]))
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	for i in ids.size():
		pick -= weights[i]
		if pick <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


## Weight in kg for a hooked fish (skewed to small fish, trophies are rare).
func roll_weight_kg(species_id: String, rng: RandomNumberGenerator) -> float:
	var r: Vector2 = fish[species_id]["weight_kg"]
	return lerpf(r.x, r.y, pow(rng.randf(), 2.2))


## Temperature in Celsius for a normalised 0..1 thermal value inside a zone.
func zone_temp_c(zone_id: String, t01: float) -> float:
	var r: Vector2 = ZONES[zone_id]["water_temp_c"]
	return lerpf(r.x, r.y, clampf(t01, 0.0, 1.0))


# ---------------------------------------------------------------- VALIDATION
func validate() -> bool:
	var ok := true
	for zid: String in ZONES:
		var z: Dictionary = ZONES[zid]
		for b: String in z["baits"]:
			if not BAITS.has(b):
				push_error("[BiomeDB] zone '%s' references unknown bait '%s'" % [zid, b]); ok = false
		for r: String in z["rigs"]:
			if not RIGS.has(r):
				push_error("[BiomeDB] zone '%s' references unknown rig '%s'" % [zid, r]); ok = false
		for s: String in z["species"]:
			if not fish.has(s):
				push_error("[BiomeDB] zone '%s' references unknown species '%s'" % [zid, s]); ok = false
	for sid: String in BITE_PROFILES:
		if not fish.has(sid):
			push_error("[BiomeDB] bite profile for unknown species '%s'" % sid); ok = false
	for sid: String in fish:
		if not BITE_PROFILES.has(sid):
			push_warning("[BiomeDB] species '%s' has no bite profile, using BITE_DEFAULT" % sid)
	for sid: String in WEATHER_TRAITS:
		if not fish.has(sid):
			push_error("[BiomeDB] weather traits for unknown species '%s'" % sid); ok = false
	print("[BiomeDB] %d zones, %d species, %d rigs, %d baits - %s" % [ZONES.size(), fish.size(), RIGS.size(), BAITS.size(), "OK" if ok else "ERRORS"])
	return ok
