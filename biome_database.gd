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
	"titan_tackle_rig": {"name": "Titan Tackle Rig", "rod_stiffness": 230.0, "line_stiffness": 2100.0, "line_break_force_n": 240.0, "drag_max_n": 150.0, "spool_m": 300.0, "min_level": 30},
	"shore_spinning_rig": {"name": "Shore Spinning Rig", "rod_stiffness": 100.0, "line_stiffness": 1000.0, "line_break_force_n": 55.0, "drag_max_n": 34.0, "spool_m": 140.0, "min_level": 1},
	"shore_medium_rig": {"name": "Shore Medium Rig", "rod_stiffness": 140.0, "line_stiffness": 1300.0, "line_break_force_n": 85.0, "drag_max_n": 55.0, "spool_m": 180.0, "min_level": 1, "price": 400},
	"shore_heavy_rig": {"name": "Shore Heavy Rig", "rod_stiffness": 190.0, "line_stiffness": 1700.0, "line_break_force_n": 140.0, "drag_max_n": 95.0, "spool_m": 220.0, "min_level": 1, "price": 1500},
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

# ---------------------------------------------------------------- FIGHT STYLES
# How a hooked fish fights, by family of behaviour (game-design fill from general angling knowledge).
#   run_len / run_gap / run_pull   multipliers on the species burst length, gap between runs and run strength
#   surface                        what the angler sees when a run ends: "jump" (clears the water),
#                                  "thrash" (head and tail break the surface), "roll" (back or flank turns
#                                  at the surface), "" (never shows itself)
#   surface_chance                 chance per run, for the smallest fish of the species; big fish show less
#   dive                           extra metres the fish dives during a run
const FIGHT_STYLES := {
	"puller": {"run_len": 1.0, "run_gap": 1.0, "run_pull": 1.0, "surface": "roll", "surface_chance": 0.25, "dive": 3.0},
	"jumper": {"run_len": 0.8, "run_gap": 0.8, "run_pull": 1.1, "surface": "jump", "surface_chance": 0.75, "dive": 2.0},
	"thrasher": {"run_len": 0.7, "run_gap": 0.6, "run_pull": 1.0, "surface": "thrash", "surface_chance": 0.7, "dive": 2.0},
	"runner": {"run_len": 1.8, "run_gap": 1.2, "run_pull": 1.15, "surface": "roll", "surface_chance": 0.3, "dive": 4.0},
	"diver": {"run_len": 1.3, "run_gap": 1.0, "run_pull": 1.05, "surface": "", "surface_chance": 0.0, "dive": 7.0},
	"bulldog": {"run_len": 2.2, "run_gap": 1.6, "run_pull": 0.85, "surface": "", "surface_chance": 0.0, "dive": 8.0},
	"gentle": {"run_len": 0.6, "run_gap": 1.3, "run_pull": 0.8, "surface": "thrash", "surface_chance": 0.35, "dive": 1.0},
	"clinger": {"run_len": 0.5, "run_gap": 2.0, "run_pull": 0.7, "surface": "", "surface_chance": 0.0, "dive": 0.5},
}
const FISH_STYLE := {
	"bluefish": "thrasher", "garfish": "jumper", "european_seabass": "jumper", "japanese_seabass": "jumper",
	"flathead_grey_mullet": "jumper", "peacock_bass": "jumper", "swordfish": "jumper", "spanish_mackerel": "jumper",
	"atlantic_mackerel": "jumper", "ember_barracuda": "jumper", "atlantic_bonito": "runner",
	"greater_amberjack": "runner", "giant_trevally": "runner", "leerfish": "runner",
	"mediterranean_horse_mackerel": "gentle", "japanese_horse_mackerel": "gentle", "european_anchovy": "gentle",
	"whiting": "gentle", "red_mullet": "gentle", "saddled_bream": "puller", "gilthead_seabream": "puller",
	"white_seabream": "puller", "striped_sea_bream": "puller", "red_seabream": "diver", "common_dentex": "diver",
	"black_scorpionfish": "diver", "atlantic_cod": "diver", "haddock": "diver", "dusky_grouper": "bulldog",
	"lagoon_grouper": "bulldog", "coral_trout": "bulldog", "turbot": "bulldog", "atlantic_halibut": "bulldog",
	"greater_weever": "diver", "ornate_wrasse": "diver", "common_octopus": "clinger", "common_cuttlefish": "clinger",
	"european_squid": "clinger", "blue_crab": "clinger",
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
	# Glass Lagoon (invented)
	"glass_snapper": {"caution": 0.35, "noise_hz": 2.2, "nibble_force_n": 1.2, "nibbles": Vector2i(2, 4), "strike_force_n": 5.0, "bite_window_s": 1.0, "spook_chance": 0.4, "appetite": 1.0},
	"lagoon_grouper": {"caution": 0.45, "noise_hz": 0.6, "nibble_force_n": 6.0, "nibbles": Vector2i(1, 2), "strike_force_n": 45.0, "bite_window_s": 1.3, "spook_chance": 0.4, "max_nibble_s": 18.0},
	"ember_barracuda": {"caution": 0.10, "noise_hz": 3.0, "nibble_force_n": 4.0, "nibbles": Vector2i(0, 0), "strike_force_n": 40.0, "bite_window_s": 0.6, "spook_chance": 0.1, "self_hook_chance": 0.3, "max_nibble_s": 4.0, "appetite": 1.0},
	# Turkey shore spots (species names from the sourced spot notes; numbers are game-design values)
	"mediterranean_horse_mackerel": {"caution": 0.25, "noise_hz": 3.0, "nibble_force_n": 0.8, "nibbles": Vector2i(1, 4), "strike_force_n": 3.0, "bite_window_s": 1.0, "spook_chance": 0.2, "appetite": 1.0},
	"atlantic_bonito": {"caution": 0.08, "noise_hz": 3.2, "nibble_force_n": 4.0, "nibbles": Vector2i(0, 0), "strike_force_n": 22.0, "bite_window_s": 0.6, "spook_chance": 0.1, "self_hook_chance": 0.3, "max_nibble_s": 4.0, "appetite": 1.0},
	"black_scorpionfish": {"caution": 0.60, "noise_hz": 0.8, "nibble_force_n": 1.5, "nibbles": Vector2i(1, 3), "strike_force_n": 6.0, "bite_window_s": 1.2, "spook_chance": 0.5, "appetite": 0.8},
	"striped_sea_bream": {"caution": 0.65, "noise_hz": 1.0, "nibble_force_n": 1.6, "nibbles": Vector2i(2, 5), "strike_force_n": 8.0, "bite_window_s": 0.9, "spook_chance": 0.9, "max_nibble_s": 22.0, "appetite": 0.85},
	"dusky_grouper": {"caution": 0.45, "noise_hz": 0.6, "nibble_force_n": 6.0, "nibbles": Vector2i(1, 2), "strike_force_n": 40.0, "bite_window_s": 1.2, "spook_chance": 0.4, "max_nibble_s": 18.0, "appetite": 0.8},
	"common_dentex": {"caution": 0.20, "noise_hz": 2.0, "nibble_force_n": 4.0, "nibbles": Vector2i(0, 1), "strike_force_n": 26.0, "bite_window_s": 0.7, "spook_chance": 0.3, "self_hook_chance": 0.2, "max_nibble_s": 8.0, "appetite": 0.9},
	"greater_amberjack": {"caution": 0.10, "noise_hz": 3.0, "nibble_force_n": 5.0, "nibbles": Vector2i(0, 0), "strike_force_n": 36.0, "bite_window_s": 0.6, "spook_chance": 0.2, "self_hook_chance": 0.25, "max_nibble_s": 5.0, "appetite": 1.0},
	"leerfish": {"caution": 0.12, "noise_hz": 2.8, "nibble_force_n": 4.0, "nibbles": Vector2i(0, 1), "strike_force_n": 32.0, "bite_window_s": 0.6, "spook_chance": 0.2, "self_hook_chance": 0.25, "max_nibble_s": 6.0, "appetite": 1.0},
	"saddled_bream": {"caution": 0.40, "noise_hz": 2.2, "nibble_force_n": 1.0, "nibbles": Vector2i(2, 4), "strike_force_n": 4.0, "bite_window_s": 1.0, "spook_chance": 0.5, "appetite": 1.0},
	"garfish": {"caution": 0.30, "noise_hz": 2.6, "nibble_force_n": 0.8, "nibbles": Vector2i(1, 3), "strike_force_n": 3.0, "bite_window_s": 0.9, "spook_chance": 0.3, "appetite": 0.95},
	# More shore species and other sea creatures (numbers are game-design values)
	"flathead_grey_mullet": {"caution": 0.80, "noise_hz": 1.2, "nibble_force_n": 1.0, "nibbles": Vector2i(3, 7), "strike_force_n": 6.0, "bite_window_s": 0.7, "spook_chance": 0.9, "max_nibble_s": 25.0, "appetite": 0.7},
	"white_seabream": {"caution": 0.60, "noise_hz": 1.5, "nibble_force_n": 1.6, "nibbles": Vector2i(2, 5), "strike_force_n": 7.0, "bite_window_s": 0.8, "spook_chance": 0.8, "appetite": 0.85},
	"atlantic_mackerel": {"caution": 0.10, "noise_hz": 3.0, "nibble_force_n": 2.0, "nibbles": Vector2i(0, 1), "strike_force_n": 6.0, "bite_window_s": 0.8, "spook_chance": 0.1, "self_hook_chance": 0.4, "appetite": 1.1},
	"whiting": {"caution": 0.30, "noise_hz": 1.8, "nibble_force_n": 1.0, "nibbles": Vector2i(1, 3), "strike_force_n": 3.0, "bite_window_s": 1.0, "spook_chance": 0.3, "appetite": 1.0},
	"turbot": {"caution": 0.55, "noise_hz": 0.5, "nibble_force_n": 4.0, "nibbles": Vector2i(1, 2), "strike_force_n": 30.0, "bite_window_s": 1.4, "spook_chance": 0.4, "max_nibble_s": 20.0, "appetite": 0.7},
	"greater_weever": {"caution": 0.20, "noise_hz": 2.2, "nibble_force_n": 1.2, "nibbles": Vector2i(0, 2), "strike_force_n": 4.0, "bite_window_s": 1.0, "spook_chance": 0.2, "appetite": 1.0},
	"ornate_wrasse": {"caution": 0.25, "noise_hz": 3.0, "nibble_force_n": 0.6, "nibbles": Vector2i(2, 5), "strike_force_n": 2.0, "bite_window_s": 0.8, "spook_chance": 0.3, "appetite": 1.2},
	"common_octopus": {"caution": 0.50, "noise_hz": 0.4, "nibble_force_n": 3.0, "nibbles": Vector2i(1, 2), "strike_force_n": 14.0, "bite_window_s": 2.0, "spook_chance": 0.3, "max_nibble_s": 30.0, "appetite": 0.8},
	"common_cuttlefish": {"caution": 0.45, "noise_hz": 0.8, "nibble_force_n": 1.5, "nibbles": Vector2i(1, 3), "strike_force_n": 5.0, "bite_window_s": 1.4, "spook_chance": 0.5, "appetite": 0.9},
	"european_squid": {"caution": 0.35, "noise_hz": 2.0, "nibble_force_n": 1.2, "nibbles": Vector2i(1, 2), "strike_force_n": 5.0, "bite_window_s": 1.0, "spook_chance": 0.5, "appetite": 1.0},
	"blue_crab": {"caution": 0.30, "noise_hz": 1.0, "nibble_force_n": 2.0, "nibbles": Vector2i(2, 4), "strike_force_n": 4.0, "bite_window_s": 1.6, "spook_chance": 0.4, "appetite": 1.1},
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
	"glass_lagoon": {
		"name": "Glass Lagoon (invented)", "region": "Sunken Archipelago", "lat_lon": Vector2(10.00, 120.00),
		"level_range": Vector2i(30, 40), "water_temp_c": Vector2(24.0, 29.0), "max_depth_m": 150.0,
		"current_px_s": 22.0, "wind_px_s": 12.0,
		"baits": ["surface_popper", "heavy_jig"], "rigs": ["titan_tackle_rig"],
		"species": ["glass_snapper", "ember_barracuda", "lagoon_grouper"],
		"description": "Invented: a drowned village under still, glassy water. Things down there are very large and very patient.",
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
		# Glass Lagoon (invented)
		"glass_snapper": _fish("Glass Snapper (invented)", "Lutjanus vitreus", "prey", Vector2(0.3, 3.0), Vector2(0.40, 0.80), Vector2(3, 30), true, 9.0, 0.004, Vector2(3.0, 6.0), Vector2(1.4, 1.8), 55),
		"ember_barracuda": _fish("Ember Barracuda (invented)", "Sphyraena ignea", "predator", Vector2(1.0, 15.0), Vector2(0.40, 0.85), Vector2(1, 25), true, 55.0, 0.0035, Vector2(2.5, 5.0), Vector2(1.9, 2.2), 110),
		"lagoon_grouper": _fish("Lagoon Grouper (invented)", "Epinephelus lagunaris", "predator", Vector2(5.0, 60.0), Vector2(0.35, 0.75), Vector2(5, 40), false, 150.0, 0.0028, Vector2(4.0, 8.0), Vector2(1.7, 1.9), 180),
		# Turkey shore spots (see fishing_spots.gd for the sources behind each spot's species list)
		"mediterranean_horse_mackerel": _fish("Mediterranean Horse Mackerel (Istavrit)", "Trachurus mediterraneus", "prey", Vector2(0.03, 0.35), Vector2(0.30, 0.80), Vector2(1, 60), true, 3.0, 0.005, Vector2(3.0, 6.0), Vector2(1.3, 1.6), 14),
		"atlantic_bonito": _fish("Atlantic Bonito (Palamut)", "Sarda sarda", "predator", Vector2(0.5, 6.0), Vector2(0.35, 0.80), Vector2(0.5, 40), true, 22.0, 0.0032, Vector2(2.5, 5.0), Vector2(1.8, 2.3), 55),
		"black_scorpionfish": _fish("Black Scorpionfish (Iskorpit)", "Scorpaena porcus", "predator", Vector2(0.05, 0.8), Vector2(0.30, 0.80), Vector2(1, 50), false, 5.0, 0.0045, Vector2(4.0, 8.0), Vector2(1.2, 1.5), 30),
		"striped_sea_bream": _fish("Striped Seabream (Mirmir)", "Lithognathus mormyrus", "prey", Vector2(0.1, 1.5), Vector2(0.35, 0.80), Vector2(1, 40), false, 7.0, 0.004, Vector2(3.0, 6.0), Vector2(1.3, 1.7), 35),
		"dusky_grouper": _fish("Dusky Grouper (Lagos)", "Epinephelus marginatus", "predator", Vector2(2.0, 40.0), Vector2(0.40, 0.80), Vector2(5, 200), false, 85.0, 0.0030, Vector2(3.0, 7.0), Vector2(1.7, 2.1), 150),
		"common_dentex": _fish("Common Dentex (Sinarit)", "Dentex dentex", "predator", Vector2(0.8, 12.0), Vector2(0.35, 0.75), Vector2(5, 100), false, 32.0, 0.0032, Vector2(3.0, 6.0), Vector2(1.6, 2.0), 95),
		"greater_amberjack": _fish("Greater Amberjack (Akya)", "Seriola dumerili", "predator", Vector2(2.0, 40.0), Vector2(0.40, 0.85), Vector2(5, 120), false, 60.0, 0.0030, Vector2(2.5, 5.0), Vector2(1.8, 2.3), 110),
		"leerfish": _fish("Leerfish (Sarikuyruk)", "Lichia amia", "predator", Vector2(1.0, 25.0), Vector2(0.40, 0.85), Vector2(1, 40), false, 45.0, 0.0032, Vector2(2.5, 5.0), Vector2(1.8, 2.2), 85),
		"saddled_bream": _fish("Saddled Bream (Karagoz)", "Oblada melanura", "prey", Vector2(0.05, 0.8), Vector2(0.30, 0.80), Vector2(1, 30), true, 4.0, 0.0045, Vector2(3.0, 6.0), Vector2(1.3, 1.6), 22),
		"garfish": _fish("Garfish (Zargana)", "Belone belone", "prey", Vector2(0.1, 1.0), Vector2(0.30, 0.80), Vector2(0.3, 10), true, 3.0, 0.005, Vector2(2.0, 5.0), Vector2(1.4, 1.8), 18),
		# More shore species and other sea creatures (numbers are game-design values)
		"flathead_grey_mullet": _fish("Flathead Grey Mullet (Kefal)", "Mugil cephalus", "prey", Vector2(0.3, 4.0), Vector2(0.30, 0.85), Vector2(0.3, 10), true, 14.0, 0.0035, Vector2(3.0, 6.0), Vector2(1.6, 1.9), 25),
		"white_seabream": _fish("White Seabream (Sargoz)", "Diplodus sargus", "prey", Vector2(0.1, 1.5), Vector2(0.35, 0.80), Vector2(1, 30), false, 9.0, 0.004, Vector2(3.0, 6.0), Vector2(1.4, 1.8), 45),
		"atlantic_mackerel": _fish("Atlantic Mackerel (Uskumru)", "Scomber scombrus", "prey", Vector2(0.1, 1.2), Vector2(0.25, 0.70), Vector2(1, 40), true, 6.0, 0.004, Vector2(2.0, 4.0), Vector2(1.6, 2.0), 20),
		"whiting": _fish("Whiting (Mezgit)", "Merlangius merlangus", "prey", Vector2(0.05, 0.8), Vector2(0.15, 0.60), Vector2(5, 60), true, 3.0, 0.005, Vector2(4.0, 8.0), Vector2(1.2, 1.5), 18),
		"turbot": _fish("Turbot (Kalkan)", "Scophthalmus maximus", "predator", Vector2(1.0, 12.0), Vector2(0.15, 0.60), Vector2(5, 70), false, 35.0, 0.0028, Vector2(5.0, 9.0), Vector2(1.3, 1.6), 160),
		"greater_weever": _fish("Greater Weever (Trakonya)", "Trachinus draco", "predator", Vector2(0.05, 0.6), Vector2(0.30, 0.80), Vector2(1, 50), false, 4.0, 0.0045, Vector2(4.0, 7.0), Vector2(1.2, 1.5), 15),
		"ornate_wrasse": _fish("Ornate Wrasse (Hanim Baligi)", "Thalassoma pavo", "prey", Vector2(0.02, 0.15), Vector2(0.40, 0.90), Vector2(1, 20), false, 2.0, 0.006, Vector2(2.0, 4.0), Vector2(1.3, 1.6), 8),
		"common_octopus": _fish("Common Octopus (Ahtapot)", "Octopus vulgaris", "predator", Vector2(0.3, 6.0), Vector2(0.30, 0.80), Vector2(1, 40), false, 30.0, 0.0020, Vector2(6.0, 10.0), Vector2(1.2, 1.4), 90),
		"common_cuttlefish": _fish("Common Cuttlefish (Murekkep Baligi)", "Sepia officinalis", "predator", Vector2(0.2, 2.5), Vector2(0.30, 0.80), Vector2(2, 40), false, 8.0, 0.0035, Vector2(4.0, 7.0), Vector2(1.5, 1.9), 60),
		"european_squid": _fish("European Squid (Kalamar)", "Loligo vulgaris", "predator", Vector2(0.1, 1.5), Vector2(0.30, 0.80), Vector2(5, 60), true, 6.0, 0.004, Vector2(2.0, 4.0), Vector2(1.8, 2.3), 70),
		"blue_crab": _fish("Blue Crab (Mavi Yengec)", "Callinectes sapidus", "predator", Vector2(0.1, 0.6), Vector2(0.40, 0.90), Vector2(0.5, 20), false, 4.0, 0.004, Vector2(5.0, 9.0), Vector2(1.1, 1.3), 35),
	}


# ---------------------------------------------------------------- ACTIVITY
# When a species feeds most (game rule from general angling knowledge, not sourced per spot):
#   night     squid, cuttlefish, octopus and whiting come up and feed after dark
#   day       wrasse sleep at night; mullet, garfish and bream feed in daylight
#   twilight  predators hunt hardest at dawn and dusk (the default)
const ACTIVITY := {
	"european_squid": "night", "common_cuttlefish": "night", "common_octopus": "night", "whiting": "night",
	"ornate_wrasse": "day", "flathead_grey_mullet": "day", "garfish": "day", "saddled_bream": "day",
	"gilthead_seabream": "day", "white_seabream": "day", "striped_sea_bream": "day",
}


## "day", "night" or "twilight": when this species feeds most.
func activity_kind(species_id: String) -> String:
	return String(ACTIVITY.get(species_id, "twilight"))


## How hungry a species is at time_of_day (0 = midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset).
func activity_factor(species_id: String, time_of_day: float) -> float:
	var sun := sin((time_of_day - 0.25) * TAU)                       # -1 midnight .. +1 noon
	var twilight := clampf(1.0 - absf(sun) * 2.5, 0.0, 1.0)         # 1 near sunrise and sunset
	match String(ACTIVITY.get(species_id, "twilight")):
		"night":
			return 0.15 + 1.6 * clampf(-sun, 0.0, 1.0) + 0.6 * twilight
		"day":
			return 0.1 + 1.1 * clampf(sun + 0.2, 0.0, 1.0) + 0.3 * twilight
	return 0.45 + 1.4 * twilight + 0.15 * clampf(sun, 0.0, 1.0)


# ---------------------------------------------------------------- LOOKUPS
func get_zone(id: String) -> Dictionary:
	return ZONES.get(id, {})


func get_species(id: String) -> Dictionary:
	return fish.get(id, {})


## Common Turkish names of the shore species, as anglers and fish markets use them. Shown next to the
## English name on the catch card and in the journal.
const TR_NAMES := {
	"european_seabass": "levrek", "gilthead_seabream": "çipura", "white_seabream": "sargoz (karagöz)",
	"striped_sea_bream": "mırmır", "saddled_bream": "melanurya", "red_mullet": "barbunya",
	"flathead_grey_mullet": "has kefal", "bluefish": "lüfer", "garfish": "zargana",
	"atlantic_bonito": "palamut", "atlantic_mackerel": "uskumru", "mediterranean_horse_mackerel": "istavrit",
	"european_anchovy": "hamsi", "whiting": "mezgit", "common_dentex": "sinarit", "greater_amberjack": "sarıkuyruk (avcı)",
	"leerfish": "akya", "dusky_grouper": "orfoz (lahos)", "black_scorpionfish": "iskorpit", "greater_weever": "trakonya",
	"ornate_wrasse": "gelin balığı", "turbot": "kalkan", "common_octopus": "ahtapot", "common_cuttlefish": "mürekkep balığı (sübye)",
	"european_squid": "kalamar", "blue_crab": "mavi yengeç",
}


## "Bluefish (lüfer)", or the English name alone when no Turkish name is listed.
func display_name(id: String) -> String:
	var en := String(get_species(id).get("name", id))
	if not TR_NAMES.has(id):
		return en
	var paren := en.find(" (")              # older names carry an ASCII Turkish name: replace it
	if paren > 0:
		en = en.substr(0, paren)
	return "%s (%s)" % [en, String(TR_NAMES[id])]


func get_rig(id: String) -> Dictionary:
	return RIGS.get(id, {})


func get_bait(id: String) -> Dictionary:
	return BAITS.get(id, {})


## Fight style parameters of a species (see FIGHT_STYLES); "puller" when the species has none listed.
func get_fight_style(species_id: String) -> Dictionary:
	return FIGHT_STYLES[FISH_STYLE.get(species_id, "puller")]


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
	for sid: String in FISH_STYLE:
		if not fish.has(sid):
			push_error("[BiomeDB] fight style for unknown species '%s'" % sid); ok = false
		if not FIGHT_STYLES.has(FISH_STYLE[sid]):
			push_error("[BiomeDB] species '%s' uses unknown fight style '%s'" % [sid, FISH_STYLE[sid]]); ok = false
	for sid: String in WEATHER_TRAITS:
		if not fish.has(sid):
			push_error("[BiomeDB] weather traits for unknown species '%s'" % sid); ok = false
	print("[BiomeDB] %d zones, %d species, %d rigs, %d baits - %s" % [ZONES.size(), fish.size(), RIGS.size(), BAITS.size(), "OK" if ok else "ERRORS"])
	return ok
