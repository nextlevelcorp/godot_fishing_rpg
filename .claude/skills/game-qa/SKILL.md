---
name: game-qa
description: "Test this Godot web game honestly: CI parse-check and headless smoke run, gameplay test cases, edge cases, regression list, mobile browser checklist. Use after any gameplay change, before a release, or when the user reports a bug."
argument-hint: "[feature, bug report, or 'release']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion
---

# Game QA (project layer)

## What can and cannot be verified
| Check | Where | Proves |
|---|---|---|
| Parse-check (`.claude/scripts/godot-parse-check.gd`) | CI, every push | every `.gd` loads in Godot 4.4 |
| BiomeDB validate line | CI log | data cross-references are consistent |
| Headless smoke run of `turkey_map.tscn` and `shore_fishing.tscn` | CI, every push | scenes run ~600 frames without SCRIPT ERROR |
| Touch, feel, visuals, audio | **real phone only** | nothing in CI covers them |

Godot cannot be downloaded into the cloud session, so nothing runs locally. Never report a
check as passed unless its CI log line was read. If a check did not run, say NOT ASSESSED.

## Procedure
1. Read the CI run for the commit: parse-check lines (`ok:` per script), BiomeDB line, smoke
   output. Quote the decisive lines.
2. Write test cases for the change: steps, expected result, device(s).
3. Add each fixed bug to the regression list in `RELEASE_CHECKLIST.md`.
4. Ask the user to test on their phone with the build label shown on screen
   (`GameSession.BUILD`); collect screenshots.

## Mobile browser checklist (minimum)
iPhone Safari and Android Chrome; portrait and landscape; first-touch audio unlock; joystick and
two-finger press (walk + cast); app switch and back (pause/resume); slow network first load.

## Related template skills
`/qa-plan`, `/smoke-check`, `/regression-suite`, `/bug-report`, `/playtest-report`.

## Example
`/game-qa joystick on the pier`
