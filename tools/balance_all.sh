#!/usr/bin/env bash
# Run tools/balance_run.gd for each class in parallel (one process per class).
#   GODOT=~/bin/godot ./tools/balance_all.sh [runs] [outdir]
set -u
cd "$(dirname "$0")/.."
RUNS=${1:-150}
OUT=${2:-/tmp/balance}
mkdir -p "$OUT"
for c in warrior thief mage knifer; do
	"${GODOT:-godot}" --headless --path . -s tools/balance_run.gd -- --runs "$RUNS" --classes "$c" > "$OUT/$c.txt" 2>&1 &
done
wait
for c in warrior thief mage knifer; do grep -E "^$c " "$OUT/$c.txt"; done
