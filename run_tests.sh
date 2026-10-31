#!/usr/bin/env bash
# Run every GUT test headless. Set GODOT to your Godot 4 binary if it isn't on PATH.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
# First run (or after adding a class_name) needs an import so global classes resolve.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
