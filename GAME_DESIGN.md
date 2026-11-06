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

## Progression (build 15)
- **XP per catch** = `sqrt(base_price) x kg^0.4 x 4`, +25 for a species logged for the first time, +10 for a new personal record. Knobs: `GameSession.XP_*`.
- **Level n** needs `40 x (n-1)^1.7` XP in total, max level 30 (`LEVEL_K`, `LEVEL_POW`).
- **Spot unlocks** by level, `unlock_level` in `fishing_spots.gd`: Dikili 1, Antalya 1, Teos 2, Çeşme 3, Galata 4, Sinop 5, Trabzon 6, Fethiye 8, Kaş 10. Locked pins are grey on the map and the button reads "LOCKED - LEVEL N". (Unlock levels are game-design fill.)
- **Outing goals** (3 per visit, `ShoreFishing._make_goals`): catch 3 fish (40 coins); log a new species (60 coins + 15 XP) or catch 2 different species; land one fish of at least 0.45 x the heaviest weight a spot species can reach (80 coins).
- **Outing summary** when leaving with progress: catches, coins, XP, new species, records, goals, unlocks.
- **Test:** catch a fish, XP bar grows; reach level 2, Teos unlocks; leave the shore, summary shows; reload page, level and XP persist.

## Weather (build 19)
Each outing rolls one weather (`weather_fx.gd`, `KINDS`): clear 45%, overcast 25%, light rain 15%, windy 15%. It multiplies fish activity (overcast 1.15, light rain 1.25, windy 0.9) and the wind on the cast (windy x2.2). Rain is drawn as particles pushed by Perlin gusts, with a grey tint. The label sits next to the clock. Values are game-design fill, loosely based on common angling lore. Test: enter a spot several times; the label changes, rain falls in "Light rain", casts drift more in "Windy".

## Night lamp (build 20)
After dark the angler carries a lamp: a warm, flickering pool of light (two oscillators plus Perlin noise). Standing on the pier at night raises fish activity by 15% (`LAMP_PIER_BONUS`, game-design fill; real pier anglers use lights to draw baitfish). Test: set the clock to night with "+1 hour"; the glow appears, and the quiet-water hint is rarer on the pier than on the beach.

## Fight styles (build 22)
A hooked fish is no longer drawn during the fight. The angler sees the line, bubbles and the rod bend, and the fish only when it shows itself. `BiomeDB.FIGHT_STYLES` / `FISH_STYLE` give each species a family of behaviour: jumper (clears the water: garfish, seabass, mullet, mackerel), thrasher (bluefish), runner (long fast runs: bonito, amberjack, trevally, leerfish), diver (dives, no surface show: dentex, red seabream), bulldog (dogged heavy pull, never shows: groupers, turbot, halibut), puller (default), gentle (small, light), clinger (cephalopods, crab). Style scales run length, gap, strength and dive depth; bigger fish for their species jump less (surface chance x0.4 at max size) and run 1.5x longer. When a run ends the fish may break the surface (`fish_surfaced`): a jump is a projectile under gravity, a thrash or roll is an oscillation. The catch is still shown when landed. Style assignment is game-design fill from general angling knowledge. Test: hook a bluefish (thrash), a garfish (jump), a dusky grouper (never visible, long pulls); the side view shows no fish between events.

## First-person view (build 23)
From the moment the cast is released until the fish is landed or lost, the screen switches to a first-person view from the angler's eyes (`pov_view.gd`, replaces the side view). Pinhole projection at eye height (2.6 m on rocks or beach, 4.5 m on a pier, 8 m on a bridge): the float, the flying bait and the fish are placed in metres along the aim line, using the same simulation as the top-down scene. The rod is held in front (bottom right): a damped spring pulled by line tension, the reel handle turns while reeling. The fish is hidden; it shows only when it jumps, thrashes or rolls (fight styles), and is lifted into view when landed. Around it: sky by time of day (sun, moon, stars, clouds), the far shore with a small town, a mosque and lit windows at night, boats on the horizon, gulls (steering agents), sun or moon glitter on the water, wave rows, foam at the near edge, and other anglers' rods nodding beside you (one bends on a fish now and then). The top-down world is hidden while the view is open, so it costs no drawing.

Sound (`ambience.gd`) was rebuilt: splash is band-passed noise with a falling pitch plus bubble drops; the float going under is a rising-pitch bubble bloop; cast and strike are a rod swish; a run plays the clutch ratchet; a snapped line cracks and twangs; output is soft-limited.

## Bait and hook (build 27)
The BAIT / HOOK button (shore HUD, only with the line in) chooses one of nine baits and six hook sizes (`tackle.gd`, saved in `GameSession`).
- **Which fish come:** each species' bite weight is multiplied by its liking for the bait (`Tackle.PREF`; e.g. gilthead seabream 1.4 on mussel, grey mullet 1.5 on bread dough, bluefish 1.4 on live bait, horse mackerel 1.5 on a çapari string; unlisted baits 0.15) and by the hook fit: each size too big for the mouth (`Tackle.MOUTH`) multiplies by 0.35. A poor choice also lengthens the wait, since activity drops.
- **Hook-up:** a strike sets the hook with chance 0.9, times 0.55 per size too big and 0.75 per size too small; a miss says why.
- **Hook strength:** each size opens up above a pull (No. 12 14 N ... 3/0 170 N). Tension above it for 0.35 s loses the fish ("The hook opened up").
- **Bait theft:** each nibble may strip a soft bait (bread 35 %, mussel 25 %, worm 22 %, squid 8 %, live bait 5 %). A bare hook gets no bites; reeling in shows the bait was gone and re-baits.
- **Lures** (spoon, çapari) fish only while you reel: waiting time runs 1.6x while reeling and 0.08x when still; predators hit them without nibbling. The çapari carries its own No. 8 hooks.
Bait choices follow common Turkish shore-angling practice; all numbers are game-design fill. Test: bread dough at a harbour catches mostly mullet; a 3/0 hook gets no horse mackerel; a No. 12 hook loses a big bluefish when the clutch is set high.

## Live bait and journal (build 29)
- **Live bait is a resource.** Live baitfish sit in a bucket (max 12, saved). Small istavrit, hamsi or uskumru (under 0.4 kg) caught go into the bucket, as Turkish shore anglers do before fishing for bluefish; the map's tackle shop sells 5 for 30 coins. A fish that takes it, or small fish stripping it, uses one; you cannot cast live bait with an empty bucket.
- **Journal** shows each species with its picture (painted sprite or drawing; a dark silhouette until caught). Caught: best weight, count, depth range, feeding time, two best baits and the hook range. Not caught: "Locals say: try ..." with the best baits and feeding time, so the hidden rules are learnable.

## Fight realism (build 30)
- **Head shakes:** jumpers and thrashers (bluefish, seabass, garfish, mullet, mackerels) shake their heads between runs (about every 4-5 s while stamina > 0.2): for 0.5-1 s the pull pulses at 8 Hz (+-70 %), the rod tip knocks in the first-person view and the phone buzzes. If the line is slack for more than 0.15 s during a shake, 35 % chance the hook is thrown.
- **Jumps:** a jumping fish pulls nothing for 0.9 s. If the line is slack for more than 0.3 s of that, 45 % chance it throws the hook. Keep reeling through the jump.
- **Landing:** a fish over 1.5 kg with stamina above 30 % will not be landed: at the edge it runs 4 m out again at full strength. Tire it first.
All numbers are game-design fill. Test: hook a bluefish, stop reeling during a jump; it often throws the hook. Reel a fresh 3 kg fish straight in; it runs at the edge.

## Seasons (build 31)
The game uses the real month from the device (`season.gd`). Each species has peak and low months from the common Turkish angling calendar: bluefish Sep-Dec, bonito Aug-Nov, anchovy Nov-Feb, mackerel Oct-Jan, red mullet Jul-Oct, seabass Oct-Feb, squid Nov-Mar, octopus May-Sep and others. Peak months multiply the bite weight by 1.7, low months by 0.35 (game-design fill). The month shows next to the clock, and the journal marks each species "in season" or "out of season". Test: in November, bluefish and bonito come far more often at Galata than in May.

## Legal sizes and limits (build 32)
Turkish amateur rules from Tebliğ 2024/21 (6/2, valid 2024-2028), via search results, the official PDF was not reachable from the build environment (`regulations.gd` has the citation): minimum sizes seabass 25 cm, gilthead seabream 20 cm, horse mackerel 13 cm, bluefish 18 cm, turbot 45 cm and one per day; a 5 kg daily total. Length comes from weight with W = a L^3, a set by body depth (game-design fill). A fish that breaks a rule is released at the catch: +3 XP, no coins, no journal entry, and the card says why. The journal shows the legal size. Other species have no size rule in the game until their values are confirmed.

## Bottom rig (build 33)
The BAIT / HOOK panel also chooses the rig: FLOAT (samandıra, bait at the float depth) or BOTTOM (dip takımı: a lead sinker holds the bait on the bottom). With a bottom rig the bait depth is the water depth at the landing point, DEEP/SHAL do nothing, the cast flies 15 % farther, there is no float: bites show as the rod tip nodding and a brass bell at the tip ringing (soft on nibbles, hard on the bite). Bottom feeders (bream, whiting, scorpionfish, turbot, weever) come through the existing depth match. Lures ignore the rig. Test: on a 10 m bottom at Çeşme, a bottom rig with sea worm brings bream; a float set at 2 m brings mostly mid-water fish.

## Content
42 species in BiomeDB; about 25 used by shore spots (fish, octopus, cuttlefish, squid, blue
crab). Feeding times: twilight (default), day, night (game rule from general angling knowledge).

## Known design gaps (see MVP_ROADMAP.md)
No onboarding; no main menu or settings; no goals beyond coins and the journal; no session
summary; English-only text for a Turkish audience; portrait phones letterboxed.

## Out of scope for the MVP
Monetization, accounts, backend, multiplayer, the legacy boat game.
