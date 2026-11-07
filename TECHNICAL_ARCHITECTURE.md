# Technical Architecture

Last updated 2026-11-04 (build 11). Supersedes `ARCHITECTURE.md`, which describes the legacy
boat prototype.

## Stack
- **Engine:** Godot 4.4, GDScript. **Renderer:** Compatibility (WebGL 2 on the web).
- **Design space:** 1280x720, `window/stretch/mode = canvas_items`, aspect `keep` (default),
  landscape. Portrait phones letterbox; no safe-area handling yet.
- **Web:** single-threaded export, deployed to GitHub Pages by CI.
- **Native (planned):** Godot's own iOS and Android export. Capacitor is **not** recommended:
  it wraps a web build, adds a JS layer, and gives up native performance, native ad and store
  SDKs, and Godot's mobile features, for no gain over Godot's built-in exporters.

## Scenes and scripts
| File | Role |
|---|---|
| `turkey_map.tscn` / `turkey_map.gd` | main scene: stylised Turkey map, spot pins, info panel, tackle shop, journal |
| `shore_fishing.tscn` / `shore_fishing.gd` | gameplay: state machine (AIM, CHARGE, FLY, WAIT, BITE, FIGHT, RESULT), walking, depth, bite odds, HUD, top-down drawing |
| `fight_view.gd` | side-view fight overlay (CanvasLayer 3), catch card, procedural creatures |
| `shore_world.gd` | town, day-night grade, walkers, cats, gulls, clouds, additive glow layer |
| `fishing_controller.gd` | line physics for the fight (shared with the boat prototype) |
| `noc.gd` | Nature of Code toolkit: Vehicle (steering), Particle, Rope (Verlet), spring, flock |
| `touch_controls.gd` | touch buttons and analog joystick as GUI Controls (layer 10) |
| `ambience.gd` | procedural audio through AudioStreamGenerator |
| `biome_database.gd` (autoload `BiomeDB`) | species, rigs, baits, bite profiles, feeding times, validation |
| `fishing_spots.gd` | spot data with sources |
| `game_session.gd` | static cross-scene state; save/load via ConfigFile `user://save.cfg` |
| `water_surface.gd`, `nightshoal_water.gdshader` | water shader driven by the camera |
| `weather_manager.gd` | weather state the water shader can read (optional) |
| removed in build 58 (owner's choice, 2026-11-07): the legacy boat prototype `main_sandbox.*`, `boat*.gd`, `fish_school.gd`, `fish_interaction_ai.gd`, `sonar_*.gd`, `weather_dashboard.gd`, `progression_manager.gd`, `fishing_hud.*`, `debug_overlay.gd`, `cargo_hold.gd`, `day_night_cycle.gd`, `ocean_current_field.gd`, and the boat wake in `water_surface.gd` | nothing in the game opened them; they stay in git history |

## Input
Keyboard actions are registered at runtime by `input_defaults.gd`. Touch goes through
**GUI Controls** (`_gui_input`), never raw `_input`: raw input did not receive touches on the
player's phone. Buttons press the same actions as the keyboard; the joystick presses
steer/boat actions with analog strength; `TouchControls.presses` counts presses so a quick tap
is never lost between frames.

## Rendering
Mostly immediate-mode `_draw()` every frame, across an 8000 px wide world, without camera
culling (see the audit in MVP_ROADMAP.md). Static town parts draw once. Sprites only in the
fight view and the touch controls. A CanvasModulate grades day and night; lights use an additive
CanvasLayer the grade does not darken.

## Audio
Per-sample synthesis in GDScript at 22 050 Hz, 0.2 s buffer. No files, no buses, no music.

## Persistence
`ConfigFile` at `user://save.cfg` (IndexedDB on the web): coins, rigs, equipped rig, journal.
No backend.

## Build, deploy, verification
`.github/workflows/web-pages.yml` on every push to `main`: install Godot 4.4 and templates ->
import -> **parse-check** every `.gd` (`.claude/scripts/godot-parse-check.gd`) -> **smoke run**
`turkey_map.tscn` and `shore_fishing.tscn` headless for 600 frames, failing on any SCRIPT ERROR
or engine ERROR -> Web export -> GitHub Pages. Godot cannot run in the cloud development
session, so CI is the only automated check. The smoke run exercises idle scenes only (no input):
cast, bite and fight are not covered by any automated test yet.

## Platform readiness
Web: builds and runs headless in CI; touch is unconfirmed on a real phone. iOS/Android: no
export presets, mobile texture compression off, no icons or signing.
