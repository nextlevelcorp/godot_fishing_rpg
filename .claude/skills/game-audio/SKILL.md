---
name: game-audio
description: "Sound for this game: procedural ambience (surf on Perlin noise, gulls), one-shots (splash, plop, reel click, snap), music, audio feedback timing, web audio unlock and lifecycle, audio CPU cost on phones. Use when adding a sound or when audio stutters or is silent on mobile."
argument-hint: "[sound or problem, e.g. 'reel click' or 'no sound on iPhone']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, WebSearch, WebFetch, AskUserQuestion
---

# Game audio (project layer)

## Facts
- `ambience.gd` synthesises everything at 22 050 Hz in GDScript through
  `AudioStreamGenerator`: brown-noise surf modulated by Perlin noise, gull glides, splash, plop,
  click, snap. No audio files, no music, no audio buses.
- Browsers start audio only after the first touch or click; Godot resumes the context itself.
- Per-sample GDScript synthesis costs main-thread time on phones. Measure before adding layers.

## Rules
- Every player action gets feedback within one frame: cast whoosh, splash on landing, plop on
  nibble, louder plop on bite, click while reeling, snap on break.
- Mix: ambience under -12 dBFS equivalent, feedback on top; never louder than the strike cue.
- Pause, background and focus loss must silence audio (lifecycle, see `game-ui-ux`).
- Prefer short CC0 samples (`.ogg`) over synthesis when a sound is played often or must be rich;
  record licences like art assets.

## Procedure
1. Read `ambience.gd` and the call sites (`_amb.play(...)`) for the area.
2. Specify the sound: trigger, duration, envelope, volume, priority.
3. Implement; keep synthesis loops allocation-free.
4. Ask `game-qa` for an on-device listen test; audio cannot be verified in CI.

## Related template skills
`/team-audio`.

## Example
`/game-audio cast whoosh`
