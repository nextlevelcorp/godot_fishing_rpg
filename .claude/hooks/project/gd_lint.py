#!/usr/bin/env python3
"""PostToolUse: fast static checks on an edited .gd file, without running Godot.

Flags the two GDScript mistakes that pass the export step but stop a script from loading:
  1. mixed tabs and spaces in indentation;
  2. `var x := <expr>` where <expr> reads a Dictionary/Variant (["key"], .get(, .data[)
     without a cast, so Godot cannot infer the type ("Cannot infer the type of ...").
Reports findings as context for the session; never blocks, never edits."""
import json
import re
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
path = str((data.get("tool_input") or {}).get("file_path", ""))
if not path.endswith(".gd"):
    sys.exit(0)
try:
    with open(path, encoding="utf-8") as f:
        src = f.read().splitlines()
except OSError:
    sys.exit(0)

CASTS = ("float(", "int(", "str(", "String(", "bool(", "Vector2(", "Vector2i(", "Vector3(", "Color(",
         "Rect2(", "Array(", "Dictionary(", "PackedVector2Array(", "PackedStringArray(", "StringName(")
issues = []
for i, line in enumerate(src, 1):
    lead = re.match(r"[ \t]*", line).group(0)
    if " " in lead and "\t" in lead:
        issues.append(f"{path}:{i}: mixed tabs and spaces in indentation")
    m = re.match(r"\s*var\s+\w+\s*:=\s*(.+)$", line)
    if m:
        rhs = m.group(1).split("#")[0].strip()
        # Only a bare read is a problem: the whole value is an access chain ending in a subscript or
        # .get(...), optionally followed directly by arithmetic. Reads wrapped in float()/clampf()/...
        # or used inside a condition have a known type and load fine.
        # Typed arrays indexed by a number (pts[i]) have a known type; Dictionary reads do not.
        chain = r'[A-Za-z_][\w\.]*(\s*\[\s*"[^"]*"\s*\]|\.data\[[^\[\]]*\]|\.get\([^()]*\))(\s*\[[^\[\]]*\])*'
        reads_variant = re.fullmatch(chain + r"\s*", rhs) or re.match(chain + r"\s*[-+*/%]", rhs)
        if reads_variant and not rhs.startswith(CASTS) and not re.search(r"\bas\s+\w+\s*$", rhs):
            issues.append(f"{path}:{i}: `:=` infers from a Dictionary/Variant read; give an explicit type "
                          f"(var x: Type = ...) or wrap in a cast, or Godot may refuse to load the script")
if issues:
    msg = "gd_lint (static, Godot not run):\n" + "\n".join(issues[:15])
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}))
sys.exit(0)
