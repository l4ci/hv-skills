#!/usr/bin/env bash
# Regenerates the golden files from the OLD bin/ helpers (proof add/show,
# uncertain). Usage: gen_golden.sh <repo> <outdir>. Run from anywhere.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$1/bin"; OUT="$2"
W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"; cd "$W"
mkdir -p .hv/bugs .hv/features .hv/tasks "$OUT"
cp -R "$HERE/fixture/." .hv/
mask() { sed -E 's/^- [0-9]{4}-[0-9]{2}-[0-9]{2} · /- DATE · /' "$1"; }
"$BIN/hv-proof-add" B07 --check "unit  tests" --result PASS --evidence "go test ./... ok" --sha abc1234 >/dev/null
"$BIN/hv-proof-add" B07 --check "unit  tests" --result PASS --evidence "go test ./... ok" --sha abc1234 >/dev/null   # idempotent
"$BIN/hv-proof-add" B07 --check smoke --result FAIL --evidence "a · b · c" --sha - >/dev/null
"$BIN/hv-proof-add" F13 --check lint --result PASS --evidence "clean" --sha def5678 >/dev/null
"$BIN/hv-proof-add" T03 --check manual --result PASS --evidence "looked" --sha 111 >/dev/null
"$BIN/hv-proof-add" B05 --check archived --result PASS --evidence "x" --sha 222 >/dev/null
for f in bugs/B07 features/F13 tasks/T03 bugs/B05; do mask ".hv/$f.md" > "$OUT/$(basename "$f").md"; done
for id in B07 F13 T03 B05 B09; do
  { "$BIN/hv-proof-show" "$id" || true; } | sed -E 's/^- [0-9]{4}-[0-9]{2}-[0-9]{2} · /- DATE · /' > "$OUT/show-$id.txt"
  "$BIN/hv-proof-show" "$id" --count > "$OUT/count-$id.txt"
done
for id in B07 B08 B09 F12 F13 T03; do
  rc=0; "$BIN/hv-uncertain" "$id" > "$OUT/uncertain-$id.txt" 2>/dev/null || rc=$?
  echo "$rc" > "$OUT/uncertain-$id.rc"
done
