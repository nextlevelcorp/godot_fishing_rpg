---
name: game-performance
description: "Performance for this Godot 4.4 web export on phones: frame time, immediate-mode _draw cost, procedural audio cost, agent/flocking cost, asset loading, memory. Use before adding heavy visuals or agents, when the game stutters on a phone, or before release."
argument-hint: "[area or symptom, e.g. 'town redraw' or 'stutter on Android']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion
---

# Game performance (project layer)

## Budget
60 fps target (16.6 ms), 30 fps floor on low-end Android; WebGL 2 (Compatibility renderer);
single-threaded web export (no thread support enabled).

## Known hot spots
- `shore_fishing.gd` `_draw()` redraws the whole shore every frame (rocks, pier, foam, crowd,
  ripples, particles, line). `shore_world.gd` `_dyn` redraws trees, walkers, cats each frame.
- `ambience.gd` synthesises audio per sample in GDScript.
- `Noc.flock` is O(n^2) per group (walkers 34, gulls 12, shoals 6x10).

## Rules
- Cull: draw only what is near the camera (the world is 8000 px wide).
- Static things draw once (like ShoreWorld `_static`); move per-frame work to the few nodes
  that truly animate.
- Cap agents and particles; reuse arrays instead of allocating each frame.
- Measure before and after: Godot's `Performance` monitors (`TIME_PROCESS`,
  `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`) logged by a debug overlay, or the browser's profiler on a
  real phone. Never claim a speed-up without a measurement.

## Procedure
1. Read the hot code by function.
2. Estimate cost (items x draw calls) and propose culling/caching.
3. Implement behind no visible change; ask `game-qa` for an on-device check.

## Related template skills
`/perf-profile`, `/team-polish`.

## Example
`/game-performance cull shore drawing to the camera`
