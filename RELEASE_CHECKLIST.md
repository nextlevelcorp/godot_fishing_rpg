# Release Checklist

Mark each item **done**, **open** or **NOT ASSESSED**, with evidence (CI line, device report,
file). CI evidence alone never makes a build releasable: touch, feel, audio and layout need a
real phone.

## Every build (automatic in CI)
- [ ] Parse-check: every `.gd` prints `ok:` (CI step "Parse-check every game script")
- [ ] BiomeDB line prints `OK`
- [ ] Smoke run: map and shore scenes, no SCRIPT ERROR / ERROR lines
- [ ] `GameSession.BUILD` bumped when behaviour changed

## Web MVP
- [ ] iPhone Safari and Android Chrome: game loads on mobile data in under 15 s
- [ ] Portrait and landscape: text, pins and buttons readable and tappable
- [ ] Joystick + CAST with two thumbs; quick taps register; nothing sticks after an app switch
- [ ] Audio starts after the first touch; no crackle on a mid-range Android; silent in background
- [ ] Catch a fish, close the tab, reopen: coins and journal kept
- [ ] 10-minute session without a stutter on a low-end Android
- [ ] Credits show Kenney (CC0) and the spot sources

## Android
- [ ] Godot Android export preset, package name, version code
- [ ] Mobile texture compression (ETC2/ASTC) enabled
- [ ] Adaptive icon, splash, landscape orientation
- [ ] Release keystore created and backed up (by the user)
- [ ] Play Console listing, content rating, data-safety form
- [ ] Tested on at least one low-end and one recent device

## iOS
- [ ] Godot iOS export preset, bundle id, version
- [ ] Xcode build and signing with the user's Apple Developer account
- [ ] App icons, launch screen, landscape orientation, safe areas checked on a notched iPhone
- [ ] App Store Connect listing, age rating, privacy nutrition label
- [ ] TestFlight round with testers

## Store and legal
- [ ] Privacy policy URL (required once analytics or ads exist)
- [ ] Screenshots and a short video per platform, TR and EN descriptions
- [ ] Licences: `assets/*/License.txt` present; sources listed in credits

## Regression list (add every fixed bug)
| Bug | Fixed in | Check |
|---|---|---|
| Touch buttons ignored on phones (raw `_input`) | build 8 (GUI Controls) | press CAST/REEL on a phone, tap ring appears |
| `:=` inferred from a Dictionary read stops a script loading | build 4b39341 era | CI parse-check, gd_lint hook |
