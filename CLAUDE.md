# Shore Fishing Türkiye — project rules (read first)

Casual, realistic shore fishing at real Turkish spots. Godot 4.4 + GDScript, web first
(GitHub Pages), iOS and Android later through Godot's own exporters (not Capacitor).

- **Docs:** `GAME_DESIGN.md`, `TECHNICAL_ARCHITECTURE.md`, `MVP_ROADMAP.md`,
  `RELEASE_CHECKLIST.md`, `SKILLS_README.md` (skills, agents, hooks).
- **Verification:** Godot does not run in the cloud session. Every push to `main` runs CI:
  parse-check of every `.gd` and a headless smoke run of the map and shore scenes, then deploys.
  Never claim something works without the CI line or a device report that shows it.
- **Pushing to `main` deploys.** Bump `GameSession.BUILD` in `game_session.gd` with every
  behaviour change so the player can tell a fresh build from a cached page.
- **Touch input** goes through GUI Controls only (`touch_controls.gd`), never raw `_input`.
- **Motion** follows Nature of Code (`noc.gd`): forces, springs, particles, agents, oscillation.
- **Facts about real spots** cite a source in `fishing_spots.gd`; invented content is labelled
  "game-design fill".
- **GDScript pitfall:** never `var x := dict["key"]` (type cannot be inferred and the script
  fails to load); give the type or cast.
- **Project skills:** `/game-design`, `/level-design`, `/game-ui-ux`, `/game-art`, `/game-audio`,
  `/game-qa`, `/game-performance`, `/game-release`. **Read-only agents:** game-analyst,
  game-architect, game-qa-tester, visual-designer, monetization-analyst.

# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 49 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Godot 4.4
- **Language**: GDScript
- **Version Control**: Git with trunk-based development
- **Build System**: SCons (engine), Godot Export Templates
- **Asset Pipeline**: Godot Import System + custom resource pipeline

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Use the set matching your engine.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

<!-- ENGINE-REFERENCE-IMPORT: the line below is engine-specific. /setup-engine
     rewrites it to @docs/engine-reference/<engine>/VERSION.md for the chosen
     engine, so a Unity or Unreal project stops loading the Godot reference every
     session. It defaults to Godot (the template's example engine); skills that
     need the pinned version read docs/engine-reference/<engine>/VERSION.md on
     demand regardless of this import. -->
@docs/engine-reference/godot/VERSION.md


## Technical Preferences

`project.yaml` at the repo root is the primary config store — engine, specialists,
naming, platform, performance, modes. Skills resolve it via `resolve_config`
(see `.claude/docs/config-resolution.md`).

`.claude/docs/technical-preferences.md` is the **legacy fallback**, read on demand
when a key is absent from `project.yaml`. It is not imported here: before
`/setup-engine` runs it is almost entirely `[TO BE CONFIGURED]` placeholders, and
after it runs `project.yaml` holds the real values.

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
  (exempt: `active.md` appends, agent memory, a subagent's new file at the path
  its orchestrating skill named; see `.claude/rules/agent-memory.md`)
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction
- A skipped or dismissed question is not an answer: act on nothing, re-ask in
  plain text and wait
- Started outside this file's folder? Warn first: hooks, deny rules and the
  ask-first mode load only when Claude Code starts here

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

Read `.claude/docs/context-management.md` on demand — it is a reference, not
session context. Two of its conventions are load-bearing and cited by name
elsewhere in the repo, so they are restated here rather than lost:

- **`production/session-state/active.md` is the session checkpoint.** The file is
  the memory, not the conversation. Read it first after any compaction, crash, or
  `/clear`.
- **Helpers in `.claude/scripts/` emit observations, never verdicts.** A script
  that scores or judges will eventually contradict a mode or override it cannot
  see. (Cited by `artifact-check.sh` and `adr-dep-graph.sh`.)
