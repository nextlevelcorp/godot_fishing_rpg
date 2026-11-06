## Turkish amateur sea-fishing rules the game enforces at the catch: minimum legal size, a count
## limit for turbot, and a daily weight limit per angler.
##
## Source: Tebliğ No. 2024/21, "6/2 Numaralı Amatör Amaçlı Su Ürünleri Avcılığının Düzenlenmesi
## Hakkında Tebliğ", Resmî Gazete 32629, 11 Aug 2024, valid 1 Sep 2024 - 31 Aug 2028
## (https://mevzuat.gov.tr/MevzuatMetin/yonetmelik/9.5.40946.pdf), as reported by search results on
## 2026-11-06; the official PDF itself could not be opened from the build environment. Only the
## species below were confirmed. A 2026 amendment (2026/26) reportedly lowered horse mackerel to
## 12 cm; not verified, so the 2024 value is kept. Other species have no size rule in the game yet.
class_name Regulations
extends RefCounted

const MIN_CM := {
	"european_seabass": 25.0,
	"gilthead_seabream": 20.0,
	"mediterranean_horse_mackerel": 13.0,
	"bluefish": 18.0,
	"turbot": 45.0,
}
const COUNT_LIMIT := {"turbot": 1}
const DAILY_KG := 5.0


## Total length in cm from weight, W = a * L^3 (grams, cm). `a` grows with how deep-bodied the
## species is (RealFish body depth), so a bream is shorter than a garfish of the same weight.
## Game-design fill: real length-weight tables differ per species and population.
static func length_cm(species: String, kg: float) -> float:
	var depth: float = RealFish.look(species).get("depth", 0.25)
	var a := 0.006 + 0.03 * depth
	return pow(maxf(kg, 0.001) * 1000.0 / a, 1.0 / 3.0)


static func min_cm(species: String) -> float:
	return float(MIN_CM.get(species, 0.0))
