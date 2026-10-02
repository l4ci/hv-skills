#!/usr/bin/env bash
# Regenerates the golden files from the OLD bin/ helpers (hv-vision-*).
# Usage: gen_golden.sh <repo> <outdir>. The scenario is mirrored by
# TestMatchesOldHelpers in internal/milestone; keep the two in step.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$1/bin"; OUT="$2"
W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"; cd "$W"
trap 'cd /; rm -rf "$W"' EXIT
mkdir -p "$OUT"
cp -R "$HERE/fixture/." .
mask() { sed -E 's/^(created): [0-9]{4}-[0-9]{2}-[0-9]{2}$/\1: DATE/' "$1"; }
snap() { # <stage>
  cp CLAUDE.md "$OUT/$1.CLAUDE.md"; cp .hv/MILESTONES.md "$OUT/$1.MILESTONES.md"
}
# no milestones yet: index writes the "no milestones yet" block
"$BIN/hv-vision-index" >/dev/null; snap s0
"$BIN/hv-vision-add" "First: thing & é" "Summary line." >/dev/null
"$BIN/hv-vision-add" "Second" "Needs the first." "M01" >/dev/null
"$BIN/hv-vision-add" "Third" "Needs both." "M01, M02" >/dev/null
"$BIN/hv-vision-index" >/dev/null; snap s1            # three planned
"$BIN/hv-vision-status" M01 shipped >/dev/null
"$BIN/hv-vision-status" M02 active >/dev/null
"$BIN/hv-vision-status" M03 active >/dev/null; snap s2 # M03 blocked on M02
for m in M01 M02 M03; do mask ".hv/milestones/$m.md" > "$OUT/$m.md"; done
"$BIN/hv-vision-list" > "$OUT/list.json"
"$BIN/hv-vision-active" > "$OUT/active.txt"
"$BIN/hv-vision-status" M02 shipped >/dev/null
"$BIN/hv-vision-status" M03 archived >/dev/null; snap s3 # all shipped or archived
