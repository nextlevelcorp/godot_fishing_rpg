## When each species is around Turkish shores through the year. The game uses the real month on the
## player's device, so autumn brings the bluefish and bonito runs and winter the anchovy.
##
## Peak and low months follow the common Turkish angling calendar (lüfer and palamut runs in autumn
## through the Bosphorus, hamsi in the Black Sea winter, barbunya in late summer); the factors
## (PEAK, LOW) are game-design fill.
class_name Season
extends RefCounted

const PEAK := 1.7
const LOW := 0.35
const MONTHS: Array[String] = ["January", "February", "March", "April", "May", "June", "July",
	"August", "September", "October", "November", "December"]

## species -> {peak: months 1..12, low: months}
const CAL := {
	"bluefish": {"peak": [9, 10, 11, 12], "low": [4, 5, 6]},
	"atlantic_bonito": {"peak": [8, 9, 10, 11], "low": [1, 2, 3, 4, 5]},
	"european_anchovy": {"peak": [11, 12, 1, 2], "low": [5, 6, 7, 8]},
	"atlantic_mackerel": {"peak": [10, 11, 12, 1], "low": [6, 7, 8]},
	"mediterranean_horse_mackerel": {"peak": [9, 10, 11], "low": []},
	"garfish": {"peak": [3, 4, 5, 10, 11], "low": [7, 8]},
	"red_mullet": {"peak": [7, 8, 9, 10], "low": [1, 2, 3]},
	"european_seabass": {"peak": [10, 11, 12, 1, 2], "low": [6, 7]},
	"gilthead_seabream": {"peak": [9, 10, 11], "low": [1, 2]},
	"common_dentex": {"peak": [5, 6, 7, 8, 9], "low": [12, 1, 2]},
	"greater_amberjack": {"peak": [7, 8, 9, 10], "low": [1, 2, 3, 4]},
	"leerfish": {"peak": [6, 7, 8, 9], "low": [12, 1, 2, 3]},
	"flathead_grey_mullet": {"peak": [3, 4, 5, 9, 10], "low": [1, 2]},
	"european_squid": {"peak": [11, 12, 1, 2, 3], "low": [6, 7, 8]},
	"common_cuttlefish": {"peak": [3, 4, 5], "low": [8, 9]},
	"common_octopus": {"peak": [5, 6, 7, 8, 9], "low": [1, 2]},
	"whiting": {"peak": [11, 12, 1, 2, 3], "low": [7, 8]},
	"turbot": {"peak": [3, 4, 5], "low": [7, 8, 9]},
	"blue_crab": {"peak": [6, 7, 8, 9], "low": [12, 1, 2, 3]},
}


## Month 1..12 from the device clock.
static func month() -> int:
	return int(Time.get_date_dict_from_system()["month"])


static func month_name(m: int = 0) -> String:
	return MONTHS[clampi((m if m > 0 else month()) - 1, 0, 11)]


## Multiplier on how often this species bites this month.
static func factor(species: String, m: int = 0) -> float:
	var mm := m if m > 0 else month()
	var c: Dictionary = CAL.get(species, {})
	if (c.get("peak", []) as Array).has(mm):
		return PEAK
	if (c.get("low", []) as Array).has(mm):
		return LOW
	return 1.0


## "in season", "out of season" or "" for this month.
static func label(species: String, m: int = 0) -> String:
	var f := factor(species, m)
	if f > 1.0:
		return "in season"
	if f < 1.0:
		return "out of season"
	return ""
