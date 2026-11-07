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
  per-sea palette (`fishing_spots.gd` `water`), soft shadows, day-night grade (`shore_world.gd`),
  a three-quarter farm-sim view with upright people (`figure.gd`).
- **First-person fishing view** (`pov_view.gd`): from the cast to the catch; the fish is hidden
  until it surfaces.
- **Fish:** painted sprites in `assets/art/fish/<species id>.png` (made by the owner with an AI
  image tool from `docs/ART_BRIEF_AI.md`, recorded in `assets/art/SOURCE.md`); species without a
  sprite fall back to the procedural `real_fish.gd` drawing. Cephalopods and crabs are still
  drawn procedurally in the fight and catch (`fight_view.gd` `CREATURES`).
- No pixel art (user decision). Smooth, painted look throughout.

## Importing a painted sprite
1. Check the upload is not empty (all-transparent) and is the species it claims to be.
2. Remove a white or checkerboard background by flood fill from the edges; keep the largest
   piece; soften the edge 1 px. Keep real transparency as it is.
3. Trim to the subject, scale to at most 1024 px wide, save as `<species id>.png`.
4. Look at a contact sheet of the result on a sea-blue background before committing.
5. Record the batch in `assets/art/SOURCE.md` (tool, plan, date, what was done).

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
