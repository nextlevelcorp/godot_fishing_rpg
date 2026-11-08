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
Use the tool, never hand steps: `python3 tools/art/import_sprites.py species_id=picture.png ...`
(`tools/art/import_sprites.py` explains itself). It skips empty pictures, keeps real transparency,
floods a light or checkerboard background away from the edges, trims, scales to at most 1024 px wide
and writes `assets/art/fish/<species id>.png`. Then:
1. Check which species each picture is (the owner's file names are not reliable) and that it faces right.
2. Look at the contact sheet the tool writes (default `/tmp/sprite_sheet/sheet.png`, outside the project).
3. Record the batch in `assets/art/SOURCE.md` (tool, plan, date, what was done, what was skipped).
4. Sprites bend like swimming fish in `RealFish`; a species seen from above goes into `RealFish.NO_BEND`.
   Cephalopods and the crab use their sprite when one exists, else the procedural drawing.
5. With TEST TOOLS on (title Settings) the shore has a TEST button: hook the species at once and use
   JUMP, THRASH, ROLL and LAND to see the picture on the phone in seconds.

## Seeing the game (screenshots in the cloud session)
Godot runs in the cloud container under a virtual display; check every visual change by eye:
```
curl -sSL -o /tmp/g.zip https://github.com/godotengine/godot/releases/download/4.4-stable/Godot_v4.4-stable_linux.x86_64.zip && unzip -oq /tmp/g.zip -d /tmp/godot
/tmp/godot/Godot_v4.4-stable_linux.x86_64 --headless --path . --import
xvfb-run -a -s "-screen 0 1560x720x24" /tmp/godot/Godot_v4.4-stable_linux.x86_64 --path . --rendering-driver opengl3 --resolution 1560x720 -s res://tools/shots/shot.gd -- spot=cesme_cove hour=0.35 out=/tmp/shots/x
```
`tools/shots/shot.gd` writes `<out>_shore.png`, `_fight.png` and `_catch.png` (or `scene=title|map`,
`shore_only=1`, `fish=<id>`, water shader overrides `p:<uniform>=<value>`). Read the PNGs. The same
binary runs `tests/smoke_features.gd` locally before a push. Rendering is software (llvmpipe), so the
fps shown is not the phone's. Re-import after adding a PNG.

## Painted ground tiles
`assets/art/ground/*.png` come from `tools/art/make_ground_textures.py` (seamless, procedural, no
third-party art). Draw them with `draw_texture_rect(tex, rect, true, ShoreWorld.tile_tint(colour))`
on a node with `texture_repeat` enabled, only where the camera looks (`ShoreFishing._tiled`).

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
