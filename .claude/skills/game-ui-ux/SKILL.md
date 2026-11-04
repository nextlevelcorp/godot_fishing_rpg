---
name: game-ui-ux
description: "Design or review mobile-first UI for this Godot web game: HUD, menus, touch buttons and joystick, responsive layout across aspect ratios, safe areas, readability, accessibility. Use when adding a screen or control, or when the user reports something hard to press or read on a phone."
argument-hint: "[screen or control, e.g. 'shore HUD' or 'touch buttons']"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, AskUserQuestion
---

# Game UI/UX (project layer)

## Facts about this project
- Godot 4.4, design space 1280x720, `window/stretch/mode = canvas_items`, landscape. Portrait
  phones letterbox. No safe-area handling yet.
- UI is built in code: `turkey_map.gd` (map, shop, journal), `shore_fishing.gd` `_build_hud`,
  `touch_controls.gd` (GUI buttons + analog joystick, Kenney Mobile Controls art).
- Touch must go through the **GUI path** (`_gui_input`). Raw `_input` did not receive touches on
  the player's phone; do not reintroduce raw-input buttons.
- Every build shows `GameSession.BUILD` on screen so a cached page can be told apart.

## Rules
- Touch targets at least 88 design px (about 44 pt); thumbs reach bottom-left (joystick) and
  bottom-right (actions); nothing important under the joystick or in the corners a notch covers.
- One status line tells the player what to do next; numbers (depth, tension) sit in a second line.
- Text: outlined labels on busy backgrounds; never colour as the only signal (tension bar also
  changes text). Turkish players: plan for localisation, keep strings in one place.
- Test portrait and landscape, 16:9, 19.5:9 and 4:3.

## Procedure
1. Read the screen's build code by function, not the whole file.
2. Sketch the layout in the design space (positions, sizes, anchors) and state each control's
   action.
3. Implement with anchors/presets, not absolute positions, where layout should stretch.
4. Hand `game-qa` a device checklist; never claim a control works on phones without a report
   from a real device.

## Related template skills
`/ux-design`, `/ux-review`, `/team-ui`.

## Example
`/game-ui-ux shore HUD on a 19.5:9 phone`
