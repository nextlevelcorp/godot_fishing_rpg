#!/usr/bin/env python3
"""SessionStart: print repository status, the on-screen build label, the development stage and the
next open roadmap items. Read-only; prints context for the session and always exits 0."""
import os
import re
import subprocess

root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def sh(*args):
    try:
        return subprocess.run(args, cwd=root, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""


def read(path):
    try:
        with open(os.path.join(root, path), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


lines = ["== Project status (project hook) =="]
branch = sh("git", "rev-parse", "--abbrev-ref", "HEAD") or "unknown"
dirty = [l for l in sh("git", "status", "--porcelain").splitlines() if l.strip()]
lines.append(f"Branch: {branch}   uncommitted files: {len(dirty)}   last commit: {sh('git', 'log', '-1', '--format=%h %s')[:90]}")
m = re.search(r'const BUILD := "([^"]+)"', read("game_session.gd"))
lines.append(f"On-screen build label: {m.group(1) if m else 'NOT FOUND (game_session.gd)'}")
stage = read("production/stage.txt").strip() or "unknown"
lines.append(f"Stage: {stage}   Positioning: casual realistic shore fishing (GAME_DESIGN.md)")
todo = [l.strip() for l in read("MVP_ROADMAP.md").splitlines() if l.strip().startswith("- [ ]")][:5]
if todo:
    lines.append("Next open roadmap items:")
    lines += ["  " + t for t in todo]
lines.append("Docs: CLAUDE.md, GAME_DESIGN.md, TECHNICAL_ARCHITECTURE.md, MVP_ROADMAP.md, RELEASE_CHECKLIST.md, SKILLS_README.md")
lines.append("Godot does not run in the cloud session: verification is the CI parse-check + smoke run after a push.")
print("\n".join(lines))
