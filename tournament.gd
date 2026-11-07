## The weekly shore tournament: one spot a week (the same for everyone that week), five minutes,
## heaviest single legal fish wins. Your rivals are three anglers on the shore beside you, the
## spot's local among them; their landed fish count only if they are of legal size, like yours.
## Second slice of "angler life" (GAME_DESIGN.md, "Weekly shore tournament"). Entry fee, prizes,
## length and rival names are game-design fill.
class_name Tournament
extends RefCounted

const ENTRY := 30
const DURATION_S := 300.0
const PRIZES: Array[int] = [300, 150, 60]          ## coins for 1st, 2nd, 3rd
const PRIZE_XP: Array[int] = [80, 40, 20]
const RIVALS := 3
const NAMES: Array[String] = ["Murat", "Ayşe", "Cem", "Elif", "Kadir", "Burak", "Nazlı", "Sinan"]


## "2026-w45": a new tournament each Monday (weeks counted from the Unix epoch, Monday start).
static func week_key() -> String:
	var days := int(floor(Time.get_unix_time_from_system() / 86400.0))
	var week := int(floor(float(days + 3) / 7.0))            # 1970-01-01 was a Thursday
	return "w%d" % week


## This week's spot: picked from the spots you have unlocked, the same pick all week.
static func spot_this_week() -> String:
	var spots: Array[String] = []
	for id: String in FishingSpots.ids():
		if GameSession.is_unlocked(FishingSpots.get_spot(id)):
			spots.append(id)
	if spots.is_empty():
		return ""
	spots.sort()
	return spots[absi(hash(week_key())) % spots.size()]


## True if this week's prize has not been paid yet. Entering again after that is for fun.
static func prize_open() -> bool:
	return GameSession.tourney_week != week_key()


## Pays the prize for a place (0 = first) once a week. Returns {coins, xp}; empty if none.
static func pay(place: int) -> Dictionary:
	if not prize_open() or place < 0 or place >= PRIZES.size():
		return {}
	GameSession.tourney_week = week_key()
	GameSession.coins += PRIZES[place]
	GameSession.xp += PRIZE_XP[place]
	GameSession.tourney_wins += 1 if place == 0 else 0
	GameSession.save()
	return {"coins": PRIZES[place], "xp": PRIZE_XP[place]}


## "1st", "2nd", "3rd", "4th".
static func ordinal(place: int) -> String:
	var names: Array[String] = ["1st", "2nd", "3rd"]
	if place >= 0 and place < names.size():
		return names[place]
	return "%dth" % (place + 1)
