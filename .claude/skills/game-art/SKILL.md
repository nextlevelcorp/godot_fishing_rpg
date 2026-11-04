---
name: game-art
description: "Art direction and asset work for this game: smooth top-down Nightshoal-style water, side-view fight scene, Kenney CC0 sprites, procedural drawing, visual consistency, asset licences and size. Use when adding or replacing visuals or assets."
argument-hint: "[area, e.g. 'town houses' or 'fight view fish']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, WebSearch, WebFetch, AskUserQuestion
---

# Game art (project layer)

## Direction
- **Top-down shore:** smooth, vivid, Nightshoal-style water (`nightshoal_water.gdshader`),
  per-sea palette (`fishing_spots.gd` `water`), soft shadows, day-night grade (`shore_world.gd`).
- **Side-view fight:** cartoon-smooth Kenney Fish Pack sprites (`assets/kenney_fish_pack`),
  procedural cephalopods/crabs with oscillating limbs (`fight_view.gd`).
- No pixel art (user decision). Smooth vector-like look throughout.

## Sourcing assets
1. Prefer CC0. Record every pack in `assets/<pack>/SOURCE.md` (author, version, licence, where
   it came from, archive checksum) and keep the pack's own `License.txt` unchanged.
2. kenney.nl is not reachable from the cloud session; the verified mirror is
   `BeyondHarnessLab/longway-bench-assets` release `kenney-library-2026-10-19`
   (sha256 of `kenney-library-2d.tar.gz` recorded in SOURCE.md). Verify the checksum.
3. Look at the pack preview before choosing; reject packs whose theme does not fit
   (pirate ships, medieval houses, side-view trees for a top-down scene).
4. Copy only the files used; prefer `Double`/2x PNGs for phones; keep `assets/` small.

## Procedure
1. Read the drawing code for the area by function.
2. State the visual target in one paragraph and the assets or procedural method.
3. Keep every moving thing on Nature of Code rules (`noc.gd`).
4. Hand `game-performance` the draw-call impact and `game-qa` a visual check list.

## Related template skills
`/art-bible`, `/asset-spec`, `/asset-audit`.

## Example
`/game-art Aegean town houses`
