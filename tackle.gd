## Bait and hook for shore fishing in Türkiye: what each species takes, which hook size fits its
## mouth, how easily the bait is stolen, and how strong each hook is before it straightens.
##
## Sources for the bait choices: common Turkish shore-angling practice (mussel and sea worm for
## bream, bread dough for mullet, live bait and lures for bluefish, çapari strings for horse
## mackerel). The numbers (preference factors, steal chances, hook strengths) are game-design fill.
class_name Tackle
extends RefCounted

## kind: natural, live or lure. steal: chance a nibble strips the bait off. lure: only fishes while
## you reel it. tr: Turkish name shown to the player.
const BAITS := {
	"mussel": {"name": "Mussel", "tr": "Midye", "kind": "natural", "steal": 0.25},
	"sea_worm": {"name": "Sea worm", "tr": "Mukoz / deniz kurdu", "kind": "natural", "steal": 0.22},
	"shrimp": {"name": "Shrimp", "tr": "Karides", "kind": "natural", "steal": 0.20},
	"squid_strip": {"name": "Squid strip", "tr": "Kalamar şerit", "kind": "natural", "steal": 0.08},
	"sardine": {"name": "Sardine fillet", "tr": "Sardalya", "kind": "natural", "steal": 0.25},
	"bread": {"name": "Bread dough", "tr": "Ekmek hamuru", "kind": "natural", "steal": 0.35},
	"live_fish": {"name": "Live baitfish", "tr": "Canlı yem", "kind": "live", "steal": 0.05},
	"spoon": {"name": "Spoon lure", "tr": "Kaşık", "kind": "lure", "steal": 0.0},
	"capari": {"name": "Çapari string", "tr": "Çapari", "kind": "lure", "steal": 0.0},
	"squid_jig": {"name": "Squid jig", "tr": "Kalamar zokası", "kind": "lure", "steal": 0.0},
}
const BAIT_ORDER: Array[String] = ["mussel", "sea_worm", "shrimp", "squid_strip", "sardine", "bread", "live_fish", "spoon", "capari", "squid_jig"]

## Hook sizes, smallest first. strength_n: pull at which the wire opens up and the fish is lost.
const HOOKS := {
	"h12": {"name": "No. 12", "strength_n": 14.0},
	"h8": {"name": "No. 8", "strength_n": 24.0},
	"h4": {"name": "No. 4", "strength_n": 42.0},
	"h1": {"name": "No. 1", "strength_n": 70.0},
	"h1_0": {"name": "1/0", "strength_n": 105.0},
	"h3_0": {"name": "3/0", "strength_n": 170.0},
}
const HOOK_ORDER: Array[String] = ["h12", "h8", "h4", "h1", "h1_0", "h3_0"]

## Species -> {bait: liking 0..1.5}. Missing baits count as PREF_OTHER.
const PREF := {
	"gilthead_seabream": {"mussel": 1.4, "sea_worm": 1.0, "shrimp": 1.0, "squid_strip": 0.3},
	"white_seabream": {"mussel": 1.2, "sea_worm": 1.2, "shrimp": 0.9, "bread": 0.4},
	"striped_sea_bream": {"sea_worm": 1.3, "mussel": 1.0, "shrimp": 0.8},
	"saddled_bream": {"bread": 1.1, "sea_worm": 1.0, "shrimp": 0.9, "capari": 0.6},
	"red_mullet": {"sea_worm": 1.4, "shrimp": 0.8, "mussel": 0.5},
	"flathead_grey_mullet": {"bread": 1.5, "sea_worm": 0.5},
	"european_seabass": {"live_fish": 1.4, "shrimp": 1.2, "squid_strip": 0.9, "spoon": 0.9, "sea_worm": 0.7},
	"bluefish": {"live_fish": 1.4, "sardine": 1.3, "spoon": 1.2, "squid_strip": 0.6},
	"garfish": {"spoon": 1.1, "sardine": 1.0, "squid_strip": 0.4},
	"atlantic_bonito": {"spoon": 1.3, "live_fish": 1.1, "sardine": 0.9},
	"atlantic_mackerel": {"capari": 1.4, "spoon": 0.8, "sardine": 0.8},
	"mediterranean_horse_mackerel": {"capari": 1.5, "shrimp": 0.6, "sardine": 0.6},
	"european_anchovy": {"capari": 0.7},
	"whiting": {"sea_worm": 1.2, "shrimp": 0.9, "sardine": 0.8},
	"common_dentex": {"live_fish": 1.4, "squid_strip": 1.2, "shrimp": 0.9},
	"greater_amberjack": {"live_fish": 1.5, "spoon": 0.9},
	"leerfish": {"live_fish": 1.5, "spoon": 0.8},
	"dusky_grouper": {"live_fish": 1.3, "squid_strip": 1.2, "sardine": 0.7},
	"black_scorpionfish": {"squid_strip": 1.2, "sardine": 1.0, "shrimp": 0.9, "sea_worm": 0.7},
	"greater_weever": {"sea_worm": 1.0, "shrimp": 1.0, "sardine": 0.8},
	"ornate_wrasse": {"sea_worm": 1.2, "shrimp": 1.0, "mussel": 0.9},
	"turbot": {"live_fish": 1.1, "sardine": 1.0, "squid_strip": 0.8},
	"common_octopus": {"squid_jig": 1.2, "sardine": 1.0, "squid_strip": 0.8},
	"common_cuttlefish": {"squid_jig": 1.4, "shrimp": 1.0, "live_fish": 0.8},
	"european_squid": {"squid_jig": 1.6, "sardine": 0.6, "shrimp": 0.6},
	"blue_crab": {"sardine": 1.1, "mussel": 0.9},
}
const PREF_OTHER := 0.15

## Species -> hook sizes that fit its mouth, as indexes into HOOK_ORDER [smallest, largest].
const MOUTH := {
	"european_anchovy": Vector2i(0, 0), "mediterranean_horse_mackerel": Vector2i(0, 1), "atlantic_mackerel": Vector2i(0, 2),
	"red_mullet": Vector2i(0, 1), "flathead_grey_mullet": Vector2i(0, 1), "saddled_bream": Vector2i(0, 1),
	"garfish": Vector2i(0, 2), "whiting": Vector2i(1, 2), "ornate_wrasse": Vector2i(0, 2), "greater_weever": Vector2i(1, 2),
	"white_seabream": Vector2i(1, 2), "striped_sea_bream": Vector2i(1, 2), "gilthead_seabream": Vector2i(1, 3),
	"black_scorpionfish": Vector2i(2, 3), "european_seabass": Vector2i(2, 4), "bluefish": Vector2i(2, 4),
	"atlantic_bonito": Vector2i(2, 4), "common_dentex": Vector2i(3, 5), "turbot": Vector2i(3, 5),
	"leerfish": Vector2i(3, 5), "greater_amberjack": Vector2i(3, 5), "dusky_grouper": Vector2i(3, 5),
	"common_octopus": Vector2i(2, 5), "common_cuttlefish": Vector2i(1, 3), "european_squid": Vector2i(1, 3), "blue_crab": Vector2i(1, 4),
}
## The çapari string carries its own small feathered hooks, about No. 8.
const CAPARI_HOOK := 1


## The n baits this species likes best, as display names.
static func best_baits(species: String, n: int = 2) -> PackedStringArray:
	var pref: Dictionary = PREF.get(species, {})
	var ids := pref.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return float(pref[a]) > float(pref[b]))
	var out := PackedStringArray()
	for i in mini(n, ids.size()):
		out.append(String(BAITS[ids[i]]["name"]).to_lower())
	return out


## Hook sizes that fit this species' mouth, for example "No. 8 to No. 1".
static func hook_range(species: String) -> String:
	var m: Vector2i = MOUTH.get(species, Vector2i(1, 3))
	var a := hook_name(HOOK_ORDER[m.x])
	return a if m.x == m.y else "%s to %s" % [a, hook_name(HOOK_ORDER[m.y])]


static func bait_name(id: String) -> String:
	var b: Dictionary = BAITS.get(id, {})
	return "%s (%s)" % [b.get("name", id), b.get("tr", "")]


static func hook_name(id: String) -> String:
	return String(HOOKS.get(id, {}).get("name", id))


static func is_lure(bait: String) -> bool:
	return String(BAITS.get(bait, {}).get("kind", "")) == "lure"


static func steal_chance(bait: String) -> float:
	return float(BAITS.get(bait, {}).get("steal", 0.2))


static func hook_strength(hook: String, bait: String) -> float:
	var id := HOOK_ORDER[CAPARI_HOOK] if bait == "capari" else hook
	return float(HOOKS.get(id, {}).get("strength_n", 40.0))


static func _hook_index(hook: String, bait: String) -> int:
	if bait == "squid_jig":
		return 2                     # a jig carries its own crown of pins, sized for squid
	return CAPARI_HOOK if bait == "capari" else maxi(0, HOOK_ORDER.find(hook))


## How many sizes the hook is too big (+) or too small (-) for this mouth; 0 = fits.
static func hook_misfit(species: String, hook: String, bait: String) -> int:
	var m: Vector2i = MOUTH.get(species, Vector2i(1, 3))
	var i := _hook_index(hook, bait)
	if i > m.y:
		return i - m.y
	if i < m.x:
		return i - m.x
	return 0


## Multiplies how likely this species is to come to the bait: its liking for the bait, and a hook too
## big for its mouth puts small fish off.
static func bite_factor(species: String, bait: String, hook: String) -> float:
	var pref: Dictionary = PREF.get(species, {})
	var f := float(pref.get(bait, PREF_OTHER))
	var mis := hook_misfit(species, hook, bait)
	if mis > 0:
		f *= pow(0.35, float(mis))
	return f


## Chance that striking on the bite sets the hook. Too big: the fish has it only by the lips. Too
## small: the point does not find a hold in a big mouth.
static func hookup_chance(species: String, hook: String, bait: String) -> float:
	var mis := hook_misfit(species, hook, bait)
	var p := 0.9
	if mis > 0:
		p *= pow(0.55, float(mis))
	elif mis < 0:
		p *= pow(0.75, float(-mis))
	return p
