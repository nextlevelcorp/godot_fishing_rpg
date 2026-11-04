## Real-world shore fishing spots in Turkey ("mera" list), with where each claim comes from.
##
## How to read this data:
##   species        what the game spawns here. Each id exists in BiomeDB.
##   species_note   which species the sources actually mention, and which ones are a game-design fill.
##   evidence       how strong the sources are: "survey" (peer-reviewed study), "press/guide"
##                  (news or travel articles), "user listing" (Fishbrain/Fishbox user pages, may have
##                  location errors), "charter listing" (marketing pages, not catch data).
##   lat_lon        town or harbour level, NOT the exact fishing mark. Good enough for a stylised map.
##   kind           the scene style the game draws (bridge, harbor, rocky, beach). It is a visual
##                  choice, not a survey of the exact mark.
##   sources        web pages the notes are based on, found through web search. Search summaries were
##                  used; the pages were not all read in full.
## Always check the current Turkish rules before fishing for real: closed seasons and gear limits apply.
class_name FishingSpots
extends RefCounted

const RULES_NOTE := "Game data only. Check current Turkish Ministry of Agriculture and Forestry rules before fishing: closed seasons and gear limits apply."

const SPOTS := {
	"galata_bridge": {
		"name": "Galata Bridge", "local_name": "Galata Köprüsü", "region": "Istanbul / Marmara",
		"lat_lon": Vector2(41.0204, 28.9740), "kind": "bridge",
		"species": ["mediterranean_horse_mackerel", "atlantic_bonito", "bluefish", "black_scorpionfish", "european_anchovy"],
		"species_note": "Horse mackerel is the most common catch. Bluefish and bonito are the prized fish, but anglers say big runs have declined. Scorpionfish is reported near the bridge. Anchovy: game-design fill.",
		"evidence": "survey + press/guide",
		"sources": [
			"https://blackmeditjournal.org/volumes-archive/vol18-2012/vol-18-2012-no-2/fishing-at-the-galata-bridge-istanbul-in-2011-2012/",
			"https://www.trtworld.com/article/12864698",
			"https://www.theguideistanbul.com/article/fishing-istanbul/",
		],
		"blurb": "Anglers line the rails above the Golden Horn all year. Small fish are steady; the big runs are rare.",
		"water": {"shallow": Color(0.20, 0.62, 0.66), "mid": Color(0.04, 0.34, 0.52), "deep": Color(0.02, 0.12, 0.30)},
		"shore_color": Color(0.30, 0.31, 0.34),
	},
	"teos_harbor": {
		"name": "Teos Harbor", "local_name": "Teos Limanı", "region": "Izmir / Aegean",
		"lat_lon": Vector2(38.1747, 26.7853), "kind": "harbor",
		"species": ["european_seabass", "gilthead_seabream", "red_mullet"],
		"species_note": "A user listing names European sea bass here. Gilthead bream and red mullet: game-design fill.",
		"evidence": "user listing",
		"sources": ["https://fishbrain.com/fishing-waters/x4-hw0cq/teos-limani"],
		"blurb": "A quiet ancient harbour on the Seferihisar coast with clear, shallow water.",
		"water": {"shallow": Color(0.14, 0.82, 0.84), "mid": Color(0.02, 0.46, 0.68), "deep": Color(0.01, 0.12, 0.34)},
		"shore_color": Color(0.62, 0.62, 0.60),
	},
	"dikili_bay": {
		"name": "Dikili Bay", "local_name": "Dikili Körfezi", "region": "Izmir / Aegean",
		"lat_lon": Vector2(39.0700, 26.8900), "kind": "beach",
		"species": ["gilthead_seabream", "striped_sea_bream", "european_seabass"],
		"species_note": "A user listing names striped sea bream and gilthead sea bream. Sea bass: game-design fill.",
		"evidence": "user listing",
		"sources": ["https://fishbrain.com/fishing-waters/H2zRtEcJ/dikili-korfezi"],
		"blurb": "A wide, sandy bay. Bream feed along the sand edge in the early morning.",
		"water": {"shallow": Color(0.14, 0.82, 0.84), "mid": Color(0.02, 0.46, 0.68), "deep": Color(0.01, 0.12, 0.34)},
		"shore_color": Color(0.90, 0.80, 0.58),
	},
	"cesme_cove": {
		"name": "Cesme Cove", "local_name": "Çeşme Koyu", "region": "Izmir / Aegean",
		"lat_lon": Vector2(38.3200, 26.3000), "kind": "rocky",
		"species": ["european_seabass", "gilthead_seabream", "saddled_bream"],
		"species_note": "A user listing exists for Cesme Koyu. A snorkelling guide reports bream and wrasse over the rocky coves nearby. Species mix is a loose match.",
		"evidence": "user listing + guide",
		"sources": [
			"https://fishbrain.com/fishing-waters/uKN5iQGG/cesme-koyu",
			"https://beachesforkings.pages.dev/cesme/snorkelling/",
		],
		"blurb": "Rocky points and clear coves on the tip of the Cesme peninsula.",
		"water": {"shallow": Color(0.14, 0.82, 0.84), "mid": Color(0.02, 0.46, 0.68), "deep": Color(0.01, 0.12, 0.34)},
		"shore_color": Color(0.40, 0.34, 0.28),
	},
	"sinop_harbor": {
		"name": "Sinop", "local_name": "Sinop", "region": "Black Sea",
		"lat_lon": Vector2(42.0300, 35.1500), "kind": "harbor",
		"species": ["atlantic_bonito", "bluefish", "european_anchovy", "mediterranean_horse_mackerel"],
		"species_note": "A university study of Sinop fishing and press reports mention anchovy, bonito, bluefish and horse mackerel. Anchovy peaks in winter in the study; other seasons are not modelled yet.",
		"evidence": "survey + press/guide",
		"sources": [
			"https://acikerisim.sinop.edu.tr/items/0513a875-1cff-4a5a-9800-894a94354881/full",
			"https://www.dailysabah.com/turkiye/climate-change-shifts-fish-as-anchovy-season-thrives-in-turkiye/news",
		],
		"blurb": "A cold, dark sea off the northernmost point of Turkey. Anchovy shoals pull the predators in.",
		"water": {"shallow": Color(0.18, 0.55, 0.55), "mid": Color(0.03, 0.28, 0.40), "deep": Color(0.01, 0.09, 0.20)},
		"shore_color": Color(0.62, 0.62, 0.60),
	},
	"trabzon_coast": {
		"name": "Trabzon Coast", "local_name": "Trabzon", "region": "Black Sea",
		"lat_lon": Vector2(41.0000, 39.7200), "kind": "harbor",
		"species": ["atlantic_bonito", "european_anchovy", "mediterranean_horse_mackerel", "bluefish"],
		"species_note": "Press reports bonito first in the season, then anchovy, horse mackerel, bluefish and others.",
		"evidence": "press/guide",
		"sources": ["https://hurriyetdailynews.com/anchovy-time-in-trabzon-12182"],
		"blurb": "Season opens on 1 September. Bonito runs come first, then the anchovy.",
		"water": {"shallow": Color(0.18, 0.55, 0.55), "mid": Color(0.03, 0.28, 0.40), "deep": Color(0.01, 0.09, 0.20)},
		"shore_color": Color(0.62, 0.62, 0.60),
	},
	"fethiye_bay": {
		"name": "Fethiye Bay", "local_name": "Fethiye", "region": "Mediterranean",
		"lat_lon": Vector2(36.6200, 29.1200), "kind": "rocky",
		"species": ["european_seabass", "gilthead_seabream", "common_dentex", "leerfish", "dusky_grouper"],
		"species_note": "One guide says shore anglers reach sea bass and sea bream from beaches and rocky headlands. Dentex, grouper, amberjack and leerfish are listed as local species, mostly from boats, so they are rare here.",
		"evidence": "guide + charter listing",
		"sources": [
			"https://www.fishingworldguide.com/en/blog/angeln-in-tuerkei",
			"https://fishingbooker.com/destinations/location/tr/fethiye",
		],
		"blurb": "Deep blue water right off the rocks. Most big fish live out of reach, but not all of them.",
		"water": {"shallow": Color(0.10, 0.85, 0.88), "mid": Color(0.00, 0.50, 0.75), "deep": Color(0.00, 0.14, 0.40)},
		"shore_color": Color(0.40, 0.34, 0.28),
	},
	"kas_coast": {
		"name": "Kas Coast", "local_name": "Kaş", "region": "Mediterranean",
		"lat_lon": Vector2(36.2000, 29.6400), "kind": "rocky",
		"species": ["greater_amberjack", "common_dentex", "dusky_grouper", "saddled_bream"],
		"species_note": "Charter listings advertise amberjack, grouper and dentex around Kas. These are marketing pages and mostly boat fishing, so treat the shore version as a game version.",
		"evidence": "charter listing",
		"sources": ["https://fishanywhere.com/locations/antalya/kas/species/amberjack"],
		"blurb": "Steep rock into very deep, clear water. A hard place to land anything big.",
		"water": {"shallow": Color(0.10, 0.85, 0.88), "mid": Color(0.00, 0.50, 0.75), "deep": Color(0.00, 0.14, 0.40)},
		"shore_color": Color(0.40, 0.34, 0.28),
	},
	"antalya_gulf": {
		"name": "Antalya Gulf", "local_name": "Antalya Körfezi", "region": "Mediterranean",
		"lat_lon": Vector2(36.8800, 30.7000), "kind": "beach",
		"species": ["saddled_bream", "garfish", "european_seabass", "red_mullet"],
		"species_note": "A guide names saddled bream, mullet, wrasse and garfish as common and fun on light shore tackle. Sea bass: game-design fill. Red mullet stands in for mullet.",
		"evidence": "guide",
		"sources": ["https://www.baityourhook.com/fishing-in-antalya-region-tr"],
		"blurb": "Light tackle and busy water. A friendly place to learn the feel of a bite.",
		"water": {"shallow": Color(0.10, 0.85, 0.88), "mid": Color(0.00, 0.50, 0.75), "deep": Color(0.00, 0.14, 0.40)},
		"shore_color": Color(0.90, 0.80, 0.58),
	},
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in SPOTS:
		out.append(id)
	return out


static func get_spot(id: String) -> Dictionary:
	return SPOTS.get(id, {})
