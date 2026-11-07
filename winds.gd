## The named winds of the Turkish coast. Every outing has one: it sets the direction and strength of
## the wind on the shore, and a strong poyraz or lodos makes the water rough and the bites fewer.
##
## Names and directions: Turkish State Meteorological Service glossary (mgm.gov.tr, "Meteoroloji
## Sözlüğü"), which also describes lodos as the warm south-westerly that matters to seafarers. Press
## reports from Tekirdağ describe poyraz keeping fishermen in harbour until it drops. How much each
## wind changes the bite (`bite`), the strength ranges and how often each blows (`weight`) are
## game-design fill.
class_name Winds
extends RefCounted

## from_deg: the compass direction the wind blows FROM (0 north, 90 east). ms: range of speed (m/s).
const KINDS := {
	"calm": {"name": "Calm", "tr": "Limanlık", "from_deg": 0.0, "ms": Vector2(0.0, 1.0), "bite": 1.08, "weight": 2.0,
		"note": "Flat water: the float shows every touch."},
	"yildiz": {"name": "Yıldız", "tr": "Yıldız (N)", "from_deg": 0.0, "ms": Vector2(2.0, 7.0), "bite": 1.0, "weight": 1.0,
		"note": "A cool northerly."},
	"poyraz": {"name": "Poyraz", "tr": "Poyraz (NE)", "from_deg": 45.0, "ms": Vector2(4.0, 12.0), "bite": 0.85, "weight": 3.0,
		"note": "Cold and rough: the boats stay in harbour until it drops."},
	"gundogusu": {"name": "Gündoğusu", "tr": "Gündoğusu (E)", "from_deg": 90.0, "ms": Vector2(2.0, 7.0), "bite": 1.0, "weight": 1.0,
		"note": "An easterly from the sunrise."},
	"kesisleme": {"name": "Keşişleme", "tr": "Keşişleme (SE)", "from_deg": 135.0, "ms": Vector2(2.0, 8.0), "bite": 0.95, "weight": 1.0,
		"note": "A warm south-easterly."},
	"kible": {"name": "Kıble", "tr": "Kıble (S)", "from_deg": 180.0, "ms": Vector2(2.0, 8.0), "bite": 0.95, "weight": 1.0,
		"note": "A warm southerly."},
	"lodos": {"name": "Lodos", "tr": "Lodos (SW)", "from_deg": 225.0, "ms": Vector2(4.0, 12.0), "bite": 0.9, "weight": 2.0,
		"note": "The warm south-westerly: big swell, murky water."},
	"bati": {"name": "Günbatısı", "tr": "Günbatısı (W)", "from_deg": 270.0, "ms": Vector2(2.0, 7.0), "bite": 1.0, "weight": 1.0,
		"note": "A westerly from the sunset."},
	"karayel": {"name": "Karayel", "tr": "Karayel (NW)", "from_deg": 315.0, "ms": Vector2(3.0, 9.0), "bite": 0.95, "weight": 2.0,
		"note": "A cold north-westerly."},
}
const PX_PER_MS := 7.0                 ## screen wind (px/s) per m/s, matching the old random wind range


## Picks a wind for an outing: {id, ms}.
static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for k: String in KINDS:
		total += float(KINDS[k]["weight"])
	var pick := rng.randf() * total
	var id := "calm"
	for k: String in KINDS:
		pick -= float(KINDS[k]["weight"])
		if pick <= 0.0:
			id = k
			break
	var r: Vector2 = KINDS[id]["ms"]
	return {"id": id, "ms": rng.randf_range(r.x, r.y)}


## The wind as a screen vector (px/s) in the top-down view, north up: it blows toward the opposite of
## where it comes from. The shoreward part is kept small, as the old wind did.
static func vector(id: String, ms: float) -> Vector2:
	var from := deg_to_rad(float(KINDS.get(id, KINDS["calm"])["from_deg"]))
	var toward := -Vector2(sin(from), -cos(from))       # north is -y on screen
	return Vector2(toward.x, toward.y * 0.3) * ms * PX_PER_MS


## Multiplier on bites. A strong wind (over 8 m/s) makes it a little worse still.
static func bite_factor(id: String, ms: float) -> float:
	var f := float(KINDS.get(id, KINDS["calm"])["bite"])
	return f * (0.92 if ms > 8.0 else 1.0)


## "Poyraz (NE) 7 m/s" for the HUD.
static func label(id: String, ms: float) -> String:
	if id == "calm":
		return "Calm (limanlık)"
	return "%s %.0f m/s" % [String(KINDS.get(id, KINDS["calm"])["tr"]), ms]
