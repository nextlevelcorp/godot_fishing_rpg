#!/usr/bin/env python3
"""Stop: report what is unresolved before the turn ends. Never blocks.

- uncommitted changes;
- game scripts changed but the on-screen build label (GameSession.BUILD) not bumped;
- commits not yet pushed (so CI has not validated them).
Godot validation (parse-check + smoke run) happens in CI after a push; this hook says so instead
of claiming anything passed."""
import json
import os
import subprocess
import sys

root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def sh(*args):
    try:
        return subprocess.run(args, cwd=root, capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return ""


notes = []
status = [l for l in sh("git", "status", "--porcelain").splitlines() if l.strip()]
if status:
    notes.append(f"{len(status)} uncommitted file(s).")
changed = set(sh("git", "diff", "--name-only", "HEAD").split())
upstream = sh("git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}").strip()
if upstream:
    changed |= set(sh("git", "diff", "--name-only", f"{upstream}..HEAD").split())
    ahead = sh("git", "rev-list", "--count", f"{upstream}..HEAD").strip()
    if ahead and ahead != "0":
        notes.append(f"{ahead} commit(s) not pushed: CI has not validated them.")
game_scripts = [c for c in changed if c.endswith(".gd") and not c.startswith(".claude/")]
if game_scripts and "game_session.gd" not in changed:
    notes.append("Game scripts changed but GameSession.BUILD was not bumped: the player cannot tell the new build from a cached one.")
if notes:
    print(json.dumps({"systemMessage": "Project check: " + " ".join(notes) + " (Godot is validated in CI after push, not locally.)"}))
sys.exit(0)
