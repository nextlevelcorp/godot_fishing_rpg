# MVP Roadmap

Positioning: casual, realistic shore fishing at real Turkish spots (see GAME_DESIGN.md).
Rule: no monetization and no backend before the MVP is validated on real phones.

Sources for this plan (2026-11-04): CI run for 6214098 (parse-check all scripts ok; smoke run of
both scenes 600 frames, no script errors, BiomeDB 42 species OK); architecture review and QA
review by read-only subagents (code reading only, nothing run on a device).

## Top 10 improvements (impact vs effort)
| # | Improvement | Impact | Effort | Evidence |
|---|---|---|---|---|
| 1 | Mobile layout: stretch aspect `expand`, controls anchored to screen edges, safe-area offsets, portrait "rotate your phone" screen; then confirm touch on a real phone | Very high | M | aspect defaults to `keep`; portrait shrinks UI to ~30%; touch never confirmed on device |
| 2 | Pause/resume lifecycle: pause the tree, mute audio and release input on background; resume on return | High | S | no `NOTIFICATION_APPLICATION_PAUSED` handling anywhere |
| 3 | Draw only what the camera sees; move rocks, lamps, pebbles, tree bodies to draw-once layers | High | S-M | whole 8000 px world redrawn every frame (est. 1,100-1,900 draw calls) |
| 4 | Pre-rendered audio: surf loop and one-shots as WAV/OGG through a small player pool | High | M | per-sample GDScript synthesis on the main thread, 0.2 s buffer |
| 5 | Gameplay bug batch: float drifting onto land, CAST hit area overlapping REEL, DEEP/SHAL overlap and lost taps, landing on drawn rocks/boats, confirm before MAP mid-fight | High | S | QA review, file:line in the review notes |
| 6 | Scripted CI play-through: drive walk, cast, bite, strike and fight with simulated input in the headless run | High | M | smoke run only covers idle scenes |
| 7 | Onboarding at the first spot and feedback while waiting ("nothing feeds at 1 m right now") | High | M | no tutorial; waits up to ~70 s with no hint |
| 8 | Turkish text (default) with English option | Medium-high | M | all UI strings English, Turkish audience |
| 9 | Remove the legacy boat game from the build and the map button | Medium | S | `main_sandbox.tscn` reachable from the map, shipped in the pack |
| 10 | Robust save: type checks, save version, ignore bad values, report save errors | Medium | S | unchecked `cfg.save()`, untyped loads |

Also queued: starter-rig balance against grouper/amberjack (suspected impossible at default
clutch, needs a playtest), time-of-day control (night species need 3.5+ minutes in one visit),
HUD text overlap, object leak at exit (CI warning).

## M0 — Stabilise and verify (next)
- [x] Confirm touch buttons and joystick on the user's phone (build label on screen)
- [ ] Mobile layout: expand aspect, anchored controls, safe areas, portrait screen (#1)
- [x] Pause/resume and audio lifecycle (#2)
- [ ] Gameplay bug batch (#5)
- [ ] Camera culling and draw-once layers (#3)
- [ ] Remove legacy boat game from build (#9)
- [ ] Robust save (#10) (partly: type-checked load, version field)

## M1 — MVP feature-complete
- [x] Title screen with Play, Settings (sound, vibration), Credits (Kenney CC0, sources); language comes with Turkish localisation
- [ ] Onboarding at the first spot and waiting feedback (#7)
- [x] Session summary ("end of outing": catches, coins, records) and return to the map
- [x] Score and progression: angler level from catches; spots unlock by level (forgiving spots first)
- [ ] Time-of-day control (start at dawn or dusk, wait until evening)
- [ ] Pre-rendered audio (#4)
- [ ] Turkish localisation (#8)
- [ ] Scripted CI play-through (#6)
- [ ] Balance pass with playtest data (rigs vs fish, bite windows on touch)

## M2 — MVP validation
- [ ] 5-10 testers on their own phones, guided by the RELEASE_CHECKLIST device list
- [ ] Measure by hand first: session length, catches per session, where players quit
- [ ] Fix the top 5 findings; gate: MVP items done and confirmed on iPhone Safari and Android Chrome

## Growth (after MVP validation)
- [ ] Analytics events and KPIs (D1/D7 retention, session length, catches, spot usage)
- [ ] Daily challenge (a species, spot and hour) and streaks
- [ ] Rewarded ads, opt-in only, never during a fight (see monetization-analyst)
- [ ] Cloud save only if retention shows players return across devices

## Commercial release
- [ ] Android: Godot export preset, ETC2/ASTC textures, icons, signing, Play Console listing
- [ ] iOS: Godot export preset, Xcode build, signing, App Store Connect listing
- [ ] Store assets: icon, screenshots, short video, descriptions (TR and EN)
- [ ] Privacy policy URL and data-safety forms (needed once analytics or ads exist)
- [ ] Performance test on a low-end Android and an older iPhone
- [ ] RELEASE_CHECKLIST.md fully green with evidence
