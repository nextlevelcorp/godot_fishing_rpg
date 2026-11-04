---
name: level-design
description: "Design or review a fishing spot (level): layout of shore, pier and town, depth profile, species mix, progression between spots, onboarding at the first spot. Use when adding a spot, rebalancing one, or changing spot unlocks."
argument-hint: "[spot id or 'new spot <name>' or 'progression']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, WebSearch, WebFetch, AskUserQuestion
---

# Level design (project layer)

A "level" is a fishing spot: an entry in `fishing_spots.gd` plus how `shore_fishing.gd` and
`shore_world.gd` build it (kind, pier, slope, max depth, town style, species list, tips).

## Checklist for a spot
- **Real place, sourced.** Name, region, town-level lat/lon, `sources` URLs and an `evidence`
  level (survey, press/guide, user listing, charter listing). Never invent a source.
- **Depth profile.** `slope` (m depth per m out) and `max_depth_m` give a distinct feel:
  steep rocks (deep water close), sandy bays (walk the pier for depth). Mark as approximation.
- **Species mix.** 5-9 species spanning shallow/deep and day/night/twilight so depth and time
  choices matter. Every id must exist in BiomeDB; CI's BiomeDB validate must print OK.
- **Readable tips.** 2-3 spot tips from the sources plus the general tips.
- **Difficulty.** Shallow, forgiving spots first (Antalya, Dikili); deep, strong-fish spots later
  (Kas, Fethiye). Check the rig rule: drag_max < line_break < peak pull of the spot's top fish.
- **Onboarding.** The first spot a new player opens must teach: walk, edge, depth, cast, wait,
  strike, fight. One new idea per minute.

## Procedure
1. Read the spot entry and the BiomeDB entries for its species (by section).
2. Research with WebSearch when adding a real spot; record URLs; label search summaries.
3. Propose the entry as a diff; ask before writing.
4. Hand a test list to `game-qa` (walk the whole width, pier, cast from edge, each species
   reachable at some depth and hour).

## Related template skills
`/team-level`, `/balance-check`, `/content-audit`.

## Example
`/level-design new spot Bodrum Marina`
