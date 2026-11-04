# Game Design — Shore Fishing Türkiye (working title)

Status: living document. Owner: the user. Last updated 2026-11-04 (build 11).

## Positioning (decided 2026-11-04)
**Casual, realistic shore fishing at real Turkish spots.** Phone first (web, later iOS and
Android). Sessions of 3-10 minutes. Collection and mastery, not hypercasual one-tap rounds.

## Pillars
1. **Real places, honestly sourced.** Every spot is a real place; species lists and tips cite
   sources (`fishing_spots.gd`) and say when something is a game-design fill.
2. **Realism you can read.** Depth, feeding time and line tension decide the outcome, and the
   screen always shows enough to reason about them (float, rings, depth line, tension bar).
3. **A living shore.** Everything that moves follows Nature of Code rules (`noc.gd`): forces,
   springs, particles, steering agents, oscillation, Perlin noise.
4. **Calm, then tense.** Walking and waiting are relaxed; the bite and the fight are short and
   intense, with sound, vibration and a side view.

## Core loop
Map: pick a spot -> walk the shore or pier -> read the water (rings, shoals) -> set float depth
-> cast (charge, aim, release) -> wait -> nibbles -> bite window -> strike -> fight (side view)
-> catch card -> coins and journal -> tackle shop -> next spot or next hour of the day.

## Systems (as built)
| System | Where | Rule |
|---|---|---|
| Spots | `fishing_spots.gd` | 9 real Turkish spots, kind (bridge/harbor/rocky/beach), slope, max depth, species, sources, tips |
| Walking | `shore_fishing.gd` `_walk` | analog stick, shore band plus a 42 m pier (not on the bridge spot) |
| Depth | `_water_depth` | depth = distance out x spot slope, capped at max depth |
| Bite odds | `_species_weight` | rarity x depth match (exp falloff, 2.5 m) x feeding time (`BiomeDB.activity_factor`) |
| Wait | `_activity` | base wait / feeding activity, so a bad depth or hour means a long wait |
| Nibble and bite | `BITE_PROFILES` | per species caution, nibble count, bite window, spook and self-hook chance |
| Fight | `fishing_controller.gd` | spring-mass line, reel, clutch (drag), fatigue, snap, slack escape |
| Side view | `fight_view.gd` | depth spring toward a Perlin target; runs dive, tired fish rise |
| Progression | `game_session.gd`, `turkey_map.gd` | coins, 3 shore rigs, journal (best weight, count), saved |
| Town and life | `shore_world.gd` | per-sea town, day-night, walkers, cats, gulls, clouds |
| Sound | `ambience.gd` | procedural surf, gulls, splash, plop, click, snap |

## Content
42 species in BiomeDB; about 25 used by shore spots (fish, octopus, cuttlefish, squid, blue
crab). Feeding times: twilight (default), day, night (game rule from general angling knowledge).

## Known design gaps (see MVP_ROADMAP.md)
No onboarding; no main menu or settings; no goals beyond coins and the journal; no session
summary; English-only text for a Turkish audience; portrait phones letterboxed.

## Out of scope for the MVP
Monetization, accounts, backend, multiplayer, the legacy boat game.
