# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.4 |
| **Installed at pin time** | NOT DETERMINED — `godot` was not on PATH in the environment where `/setup-engine` ran (2026-11-04); this does not establish that no editor is installed. |
| **Release Date** | 4.4: Mar 3 2025 (see dates below; latest upstream: 4.7.2, Aug 18 2026) |
| **Project Pinned** | 2026-11-04 (reference set originally pinned to 4.7 on 2026-10-17; re-pinned to 4.4) |
| **Last Docs Verified** | 2026-10-17 (release timeline and 4.7 changes); 2026-02-12 (4.4-4.6 content) |
| **LLM Knowledge Cutoff** | May 2025 |

## Pin Note — this project is on 4.4

The curated files in this directory were written for 4.7 and describe changes
through 4.5, 4.6 and 4.7. **This project is pinned to 4.4, so those changes are
upgrade notes, not available APIs.** Do not suggest an API, node, setting or
workflow that `breaking-changes.md`, `current-best-practices.md` or `modules/`
attribute to 4.5, 4.6 or 4.7 (for example `@abstract`, AccessKit accessibility,
`VirtualJoystick`, `AreaLight3D`). Where those files do not state which
version introduced something, treat it as unverified for 4.4. The export CI
(`.github/workflows/web-pages.yml`) also uses 4.4-stable.

## Knowledge Gap Warning

The LLM's training data likely covers Godot up to ~4.3. Versions 4.5, 4.6
and 4.7 were released after the cutoff and introduced significant changes that
the model does NOT know about; 4.4 came out shortly before it and may be thinly
covered. Always cross-reference this directory before suggesting Godot API calls.

## Installed-Version Gap Warning

The warning above is one-directional — it covers the **model** knowing less than
this pin. The reverse gap is real and `/setup-engine` §3 creates it deliberately
("pin the newer one and upgrade later"): this reference can sit **ahead of the
installed editor**, and an agent citing it correctly then emits APIs that do not
compile locally. **Check `Installed at pin time` above before trusting a
version-qualified claim** — `NOT DETERMINED` means the gap is unknown, not absent.

## Post-Cutoff Version Timeline

| Version | Release | Risk Level | Key Theme |
|---------|---------|------------|-----------|
| 4.5 | Sep 2025 | HIGH | Accessibility (AccessKit), variadic args, @abstract, shader baker, SMAA |
| 4.6 | Jan 2026 | HIGH | Jolt default, glow rework, D3D12 default on Windows, IK restored |
| 4.7 | Jun 2026 | HIGH | AreaLight3D, HDR output, Asset Store replaces the Asset Library, VirtualJoystick, Jolt soft-body and world-boundary changes, typed-return overrides |

## Before the Cutoff

4.4 (Mar 2025, Jolt option, FileAccess return types) predates the May 2025
cutoff; the Knowledge Gap Warning still applies to it.

Dates from https://github.com/godotengine/godot/releases, checked 2026-10-17:
4.4 Mar 3 2025, 4.5 Sep 15 2025, 4.6 Jan 26 2026, 4.7 Jun 18 2026, 4.7.2 Aug 18
2026. Migration guides and release notes: `breaking-changes.md` § Sources.
