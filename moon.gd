## The real moon on the player's device date, and what it does to night fishing.
##
## Phase: the mean synodic month (29.530588853 days) counted from the new moon of 2000-01-06 18:14 UTC.
## That is the standard low-precision method and is right to within about half a day, which is plenty
## for a game. Effect: common angling lore says squid, cuttlefish and octopus come to the lamp best on
## dark nights, and that other night feeders such as bass bite better in moonlight. The factors
## (DARK_BONUS, LIGHT_BONUS) are game-design fill, not surveyed.
class_name Moon
extends RefCounted

const SYNODIC_DAYS := 29.530588853
const NEW_MOON_UNIX := 947182440.0            ## 2000-01-06 18:14 UTC
const DARK_BONUS := 0.15                       ## cephalopods at new moon: x1.15; full moon: x0.85
const LIGHT_BONUS := 0.10                      ## other night feeders at full moon: x1.10; new moon: x0.90
const NAMES: Array[String] = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
	"Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]


## 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter, for a Unix time in seconds.
static func phase_at(unix: float) -> float:
	var days := (unix - NEW_MOON_UNIX) / 86400.0
	return fposmod(days, SYNODIC_DAYS) / SYNODIC_DAYS


static func phase() -> float:
	return phase_at(Time.get_unix_time_from_system())


## 0 (dark) .. 1 (full) share of the disc that is lit.
static func illumination(p: float = -1.0) -> float:
	var ph := phase() if p < 0.0 else p
	return (1.0 - cos(ph * TAU)) * 0.5


static func phase_name(p: float = -1.0) -> String:
	var ph := phase() if p < 0.0 else p
	return NAMES[int(floor(ph * 8.0 + 0.5)) % 8]


## Multiplier on how often a night feeder bites. night01: 0 day .. 1 full dark. Day is unaffected.
static func night_factor(cephalopod: bool, night01: float, p: float = -1.0) -> float:
	var lit := illumination(p)
	var f := 1.0 + DARK_BONUS * (1.0 - 2.0 * lit) if cephalopod else 1.0 + LIGHT_BONUS * (2.0 * lit - 1.0)
	return lerpf(1.0, f, clampf(night01, 0.0, 1.0))
