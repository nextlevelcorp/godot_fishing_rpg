# Skills, Subagents and Hooks

The repo carries the Claude Code Game Studios template (`.claude/`) plus a thin project layer
added on 2026-11-04. Hooks and project settings load only when Claude Code is started in this
folder (`godot_fishing_rpg`); a session started elsewhere does not run them.

## Project skills (`.claude/skills/<name>/SKILL.md`)
| Skill | Use it to | Example |
|---|---|---|
| `game-design` | design or review a mechanic against the pillars | `/game-design bite window feels unfair on phones` |
| `level-design` | add or rebalance a real fishing spot | `/level-design new spot Bodrum Marina` |
| `game-ui-ux` | HUD, menus, touch controls, layouts, safe areas | `/game-ui-ux shore HUD on a 19.5:9 phone` |
| `game-art` | visuals, CC0 asset sourcing and licences | `/game-art Aegean town houses` |
| `game-audio` | sounds, mix, web audio lifecycle | `/game-audio cast whoosh` |
| `game-qa` | honest testing: CI evidence, test cases, device checklist | `/game-qa joystick on the pier` |
| `game-performance` | frame time on phones, culling, audio cost | `/game-performance cull shore drawing to the camera` |
| `game-release` | MVP gate, web deploy, iOS/Android readiness | `/game-release mvp` |

Each points to the template skills that go deeper (for example `/qa-plan`, `/perf-profile`,
`/release-checklist`, `/ux-design`, `/art-bible`, `/balance-check`).

## Project subagents (`.claude/agents/`), all read-only
| Agent | Tools | Job |
|---|---|---|
| `game-analyst` | Read, Glob, Grep, WebSearch, WebFetch | comparable games and opportunities, facts vs hypotheses |
| `game-architect` | Read, Glob, Grep | architecture, technical debt, platform readiness |
| `game-qa-tester` | Read, Glob, Grep | bugs, edge cases, device test lists; never claims an unrun test passed |
| `visual-designer` | Read, Glob, Grep | aesthetics, hierarchy, motion, UI consistency |
| `monetization-analyst` | Read, Glob, Grep, WebSearch, WebFetch | ethical monetization, retention, analytics events and KPIs |

Only the main session edits files, so no two agents change the same file. Removed from the
template on 2026-11-04 as unused: Unity, Unreal and Godot C# specialists.

## Project hooks (`.claude/hooks/project/`, registered in `.claude/settings.json`)
| Event | Script | What it does |
|---|---|---|
| SessionStart | `project_status.py` | branch, uncommitted files, build label, stage, next roadmap items |
| PreToolUse | `guard_critical.py` | asks before edits to `project.godot`, `export_presets.cfg`, CI workflows, licences, hook settings, addons; asks before package installs and pushes to `main` (a deploy); denies `rm -rf`, force push, `reset --hard`, `clean -f` |
| PostToolUse | `gd_lint.py` | static check of an edited `.gd`: mixed indentation, `:=` inferred from a Dictionary read |
| Stop | `stop_report.py` | reports uncommitted files, unpushed commits, build label not bumped; never claims a check passed |

The template's own hooks (session start, commit and push validation, write guards, logging)
stay registered alongside these.

Verified on 2026-11-04: each project hook run with sample inputs (ask/deny/allow decisions as
listed; lint silent on all 28 game scripts and catching 5 seeded errors); template
`skill-lint.sh` reports `frontmatter=ok name=match` for all 8 skills; agent frontmatter parsed.
