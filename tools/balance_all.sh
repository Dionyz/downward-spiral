#!/usr/bin/env bash
# Run tools/balance_run.gd for each class in parallel (one process per class).
#   GODOT=~/bin/godot ./tools/balance_all.sh [runs] [outdir] [extra balance_run args...]
#   e.g. ./tools/balance_all.sh 150 /tmp/b --mastery 5 --seed0 90000
set -u
cd "$(dirname "$0")/.."
RUNS=${1:-150}
OUT=${2:-/tmp/balance}
shift 2 2>/dev/null || shift $#
mkdir -p "$OUT"
for c in warrior thief mage knifer; do
	"${GODOT:-godot}" --headless --path . -s tools/balance_run.gd -- --runs "$RUNS" --classes "$c" "$@" > "$OUT/$c.txt" 2>&1 &
done
wait
for c in warrior thief mage knifer; do grep -E "^$c +[0-9]" "$OUT/$c.txt"; done
