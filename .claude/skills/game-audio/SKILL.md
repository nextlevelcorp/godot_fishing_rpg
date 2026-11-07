---
name: game-audio
description: "Sound for this game: procedural ambience (surf on Perlin noise, gulls), one-shots (splash, plop, reel click, snap), music, audio feedback timing, web audio unlock and lifecycle, audio CPU cost on phones. Use when adding a sound or when audio stutters or is silent on mobile."
argument-hint: "[sound or problem, e.g. 'reel click' or 'no sound on iPhone']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, WebSearch, WebFetch, AskUserQuestion
---

# Game audio (project layer)

## Facts
- Sounds are **rendered offline** by `tools/audio/render_sfx.py` (numpy only, one fixed seed per
  sound) into `assets/audio/*.wav` (mono, 16-bit, 32 kHz) and played by `ambience.gd` from samples.
  Nothing is synthesised on the phone. Models: water = impact + Minnaert bubbles, reel and clutch =
  metallic click trains, gulls = harmonic glide through formants, surf/wind/rain = shaped noise,
  engine = firing pulses, steps = grains and board resonance. No recordings, nothing to license.
- Beds (`set_bed`): surf, engine, cicada, cricket, rain, wind. Loops (`set_loop`): reel, drag.
  One-shots (`play`). Distance (`play_at`): 1/r level, a little softer and lower beyond 30 m, 343 m/s delay.
  No custom audio bus (a risk on the web export); sound problems are traced with the SOUND TEST
  button in the title Settings and `tests/smoke_features.gd` in CI.
- Browsers start audio only after the first touch or click; Godot resumes the context itself.
- Master is muted for pause, background and "sound off".

## Rules
- Every player action gets feedback within one frame: cast whoosh, splash on landing, bloop or bell
  on nibble, harder on bite, reel loop while cranking, drag ratchet when the clutch gives, snap on
  break, footsteps on the ground you walk on, oar strokes in a boat, flop when a fish lands.
- Mix: beds well under the cues (about -25 dB RMS at full), cues about -18 to -22 dB RMS; never
  louder than the strike cue.
- Loops must join without a click and one-shots must end smoothly (taper to zero). Check both
  after every render: linear-prediction residual at the join, and the level step at the end.
- Sounds that come from far away use `play_at`, not a lower volume alone.
- Pause, background and focus loss must silence audio (lifecycle, see `game-ui-ux`).
- Never claim a sound "sounds right": CI cannot hear it. Say what was measured (spectrogram,
  loop join, tail) and ask for a listen on the phone.

## Procedure
1. Read `render_sfx.py` for the sound and the `_amb.play(...)` call sites for the area.
2. Specify the sound: trigger, duration, envelope, level, priority, what real thing it models.
3. Change the model in `render_sfx.py`, re-render, then measure: spectrogram image, loop join, end step.
4. Wire it in `ambience.gd` and the scene. Bump `GameSession.BUILD`.
5. Ask `game-qa` for an on-device listen test; audio cannot be verified in CI.

## Related template skills
`/team-audio`.

## Example
`/game-audio cast whoosh`
