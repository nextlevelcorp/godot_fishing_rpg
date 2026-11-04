#!/usr/bin/env python3
"""PreToolUse: protect critical files and block destructive commands.

- Edits to engine settings, export presets, CI workflows, asset licences, hook settings, or an
  addon (a dependency) -> ask the user.
- Destructive shell commands (rm -rf, force push, reset --hard, clean -f) -> deny.
- Package installs and pushes to main (main deploys to GitHub Pages) -> ask the user.
Everything else passes silently. Never edits anything itself."""
import json
import re
import subprocess
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tool = data.get("tool_name", "")
inp = data.get("tool_input") or {}
cwd = data.get("cwd") or "."

CRITICAL = ("project.godot", "export_presets.cfg", ".github/workflows/", "License.txt", ".claude/settings.json")


def decide(decision, reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": decision,
                                             "permissionDecisionReason": reason}}))
    sys.exit(0)


if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
    path = str(inp.get("file_path", ""))
    for c in CRITICAL:
        if c in path:
            decide("ask", f"{path} is a protected file (engine settings, export, CI, licence or hook config). Confirm this change.")
    if "/addons/" in path or path.endswith(".gdextension"):
        decide("ask", "Adding or changing a Godot addon is a dependency change. Confirm it.")
elif tool == "Bash":
    cmd = str(inp.get("command", ""))
    destructive = [
        r"\brm\s+-[A-Za-z]*r[A-Za-z]*f", r"\brm\s+-[A-Za-z]*f[A-Za-z]*r", r"\brm\s+--recursive\s+--force",
        r"\bgit\s+push\b[^\n]*(\s--force\b|\s-f\b|\s\+\S)", r"\bgit\s+reset\s+--hard\b", r"\bgit\s+clean\s+-[A-Za-z]*f",
    ]
    if any(re.search(p, cmd) for p in destructive):
        decide("deny", "Destructive command blocked by the project hook. Run it yourself if you really mean it.")
    if re.search(r"\b(pip3?|npm|pnpm|yarn|gem|cargo)\s+(install|add|i)\b|\b(apt|apt-get|brew)\s+install\b", cmd):
        decide("ask", "Installing a package is a dependency change. Confirm it.")
    m = re.search(r"\bgit\s+push\b([^;&|]*)", cmd)
    if m:
        # Positional arguments after `git push`: remote, then refspecs. With a refspec, its
        # destination decides; with none, the current branch is pushed.
        args = [a for a in m.group(1).split() if not a.startswith("-")]
        refspecs = args[1:]
        target_main = any(r.split(":")[-1].removeprefix("refs/heads/") in ("main", "master") for r in refspecs)
        if not refspecs:
            try:
                branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd,
                                        capture_output=True, text=True, timeout=5).stdout.strip()
            except Exception:
                branch = ""
            target_main = branch in ("main", "master")
        if target_main:
            decide("ask", "Pushing to main deploys the game to GitHub Pages. Confirm the deploy.")
sys.exit(0)
