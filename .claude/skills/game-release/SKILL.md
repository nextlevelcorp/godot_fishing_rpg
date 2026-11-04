---
name: game-release
description: "Release readiness for this Godot game: MVP gate, web deploy via GitHub Pages, validation of the deployed build, and preparation for iOS and Android (Godot native export, signing, store assets, privacy policy). Use before announcing a build, before store submission, or when the user asks if the game is ready."
argument-hint: "[mvp | web | ios | android]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, AskUserQuestion
---

# Game release (project layer)

## Pipeline today
Push to `main` -> GitHub Actions (`.github/workflows/web-pages.yml`): Godot 4.4 import,
parse-check, smoke run, Web export -> GitHub Pages
(https://nextlevelcorp.github.io/godot_fishing_rpg/). Pushing to `main` **is** a deploy.

## Native apps
Use Godot's own iOS and Android export (not Capacitor: it would wrap the web build, lose native
performance, and add a JS layer the game does not need). Needs, on the user's side: Xcode and an
Apple Developer account, Android SDK/JDK and a Play Console account, signing keys, export
templates, store listings, a privacy policy URL. These cannot be produced from the cloud session.

## Procedure
1. Walk `RELEASE_CHECKLIST.md` for the target; mark each item done, open or NOT ASSESSED with
   evidence (CI line, device report, file).
2. MVP gate: every MVP item in `MVP_ROADMAP.md` done and confirmed on a real phone.
3. Report blockers first; never call a build releasable on CI evidence alone.

## Related template skills
`/release-checklist`, `/launch-checklist`, `/gate-check`, `/team-release`.

## Example
`/game-release mvp`
