---
name: game-design
description: "Design or review a gameplay mechanic for this casual, realistic shore-fishing game: core loop, player motivation, difficulty, replayability. Use when a mechanic is added or changed, or the user asks why the game is or is not fun."
argument-hint: "[mechanic or question, e.g. 'bite timing' or 'why do sessions end early']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, WebSearch, WebFetch, AskUserQuestion
---

# Game design (project layer)

Positioning, decided 2026-11-04: **casual, realistic shore fishing** at real Turkish spots.
Sessions of 3-10 minutes, collection and mastery, no hypercasual simplification.

## Before designing
1. Read `GAME_DESIGN.md` (pillars, core loop) and the sections of `fishing_spots.gd` and
   `biome_database.gd` the mechanic touches. Read by section, not whole files.
2. State which pillar the change serves. If none, say so and ask before going on.

## Rules this game follows
- **Realism first, then readability.** Real behaviour (depth, feeding time, line tension) is
  the source of fun; every hidden rule must be readable on screen (rings, float, HUD line).
- **Nature of Code for anything that moves** (`noc.gd`): forces, springs, particles, steering
  agents, oscillation, Perlin noise. No canned tweens for living things.
- **Data-driven.** Tunables live in `biome_database.gd` / `fishing_spots.gd`, never inline.
- **Sourced facts are labelled.** A claim about a real spot or species cites a source in
  `fishing_spots.gd`; anything invented is marked "game-design fill".

## Procedure
1. Describe the player-facing loop the change sits in (walk -> read water -> set depth -> cast
   -> wait -> nibble -> strike -> fight -> catch card -> journal/shop).
2. Write the rule with numbers: inputs, formula, ranges, failure states, what the player sees.
3. Name the tuning knobs and where they live.
4. Name a test: what a player does, what must happen (feeds `game-qa`).
5. Update `GAME_DESIGN.md` in the matching section. Ask before writing.

## Related template skills
`/design-system`, `/quick-design`, `/balance-check`, `/brainstorm`.

## Example
`/game-design bite window feels unfair on phones`
