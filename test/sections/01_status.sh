echo "hv-next-id"
ID=$("$BIN/hv-next-id" bugs)
[ "$ID" = "B01" ] || fail "expected B01, got $ID"
pass "first bug id = B01"

ID2=$("$BIN/hv-next-id" bugs)
[ "$ID2" = "B02" ] || fail "expected B02, got $ID2"
pass "second bug id = B02"

ID3=$("$BIN/hv-next-id" features)
[ "$ID3" = "F01" ] || fail "expected F01, got $ID3"
pass "first feature id = F01"

ID4=$("$BIN/hv-next-id" milestones)
[ "$ID4" = "M01" ] || fail "expected M01, got $ID4"
pass "first milestone id = M01"

COUNTERS=$(cat .hv/counters.json)
echo "$COUNTERS" | grep -q '"bugs": 2' || fail "counters.bugs != 2: $COUNTERS"
echo "$COUNTERS" | grep -q '"features": 1' || fail "counters.features != 1: $COUNTERS"
echo "$COUNTERS" | grep -q '"milestones": 1' || fail "counters.milestones != 1: $COUNTERS"
pass "counters persisted"

# Self-heal: counter=2, but TODO has [B07] → next mint should be B08, not B03.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B07] [P1] Imported bug.** Desc.

## Features

## Tasks

## Completed
EOF
ID5=$("$BIN/hv-next-id" bugs)
[ "$ID5" = "B08" ] || fail "self-heal: expected B08 (max(2,7)+1), got $ID5"
pass "hv-next-id self-heals when TODO has higher IDs than counter"

# Self-heal: ARCHIVE.md is also scanned.
cat > .hv/ARCHIVE.md <<'EOF'
# Archive

- ~~**[B15] [P1] Old bug.** Desc.~~ Done 2026-01-01 [`abc1234`]
EOF
ID6=$("$BIN/hv-next-id" bugs)
[ "$ID6" = "B16" ] || fail "self-heal: expected B16 (ARCHIVE max=15), got $ID6"
pass "hv-next-id scans ARCHIVE.md for self-heal"

# Self-heal is per-prefix: features counter is unaffected by bugs traffic.
ID7=$("$BIN/hv-next-id" features)
[ "$ID7" = "F02" ] || fail "self-heal per-prefix: expected F02 (features counter still=1), got $ID7"
pass "hv-next-id self-heal is per-prefix"

# Reset state for downstream tests that expect a clean slate.
rm -f .hv/ARCHIVE.md
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
echo '{"bugs":0,"features":0,"tasks":0,"milestones":0}' > .hv/counters.json

echo "hv-append"
"$BIN/hv-append" "## Bugs" "- **[B01] [P1] First bug.** Desc."
grep -q "\[B01\] \[P1\] First bug" .hv/TODO.md || fail "B01 not found in TODO.md"
pass "bug appended to ## Bugs"

"$BIN/hv-append" "## Features" "- **[F01] [Minor] First feature.** Desc."
grep -q "\[F01\] \[Minor\] First feature" .hv/TODO.md || fail "F01 not found in TODO.md"
pass "feature appended to ## Features"

echo "hv-complete"
git add -A && git commit -q -m "add B01"
HASH=$(git log --oneline -1 --format='%h')
"$BIN/hv-complete" B01 "$HASH"
grep -q "~~.*\[B01\].*~~ Done" .hv/TODO.md || fail "B01 not marked completed"
grep -q "^- \*\*\[B01\]" .hv/TODO.md && fail "B01 still in active section"
pass "B01 moved to Completed with strikethrough"

# Idempotent: running hv-complete again on an already-completed ID is a no-op.
"$BIN/hv-complete" B01 "$HASH" >/dev/null 2>&1 || fail "second hv-complete errored on already-completed ID"
COMPLETED_COUNT=$(grep -c "~~.*\[B01\].*~~ Done" .hv/TODO.md || true)
[ "$COMPLETED_COUNT" = "1" ] || fail "re-running hv-complete duplicated B01: found $COMPLETED_COUNT rows"
pass "hv-complete is idempotent on already-completed ID"

# Typo guard: an ID that is nowhere in TODO.md still errors out.
if "$BIN/hv-complete" B99 "$HASH" 2>/dev/null; then
  fail "hv-complete should error on an unknown ID"
fi
pass "hv-complete rejects unknown ID"

echo "hv-guard-clean"
git add -A && git commit -q -m "progress"
"$BIN/hv-guard-clean" test >/dev/null 2>&1 || fail "guard rejected clean tree"
pass "clean tree passes"
echo "dirty" > dirtyfile
if "$BIN/hv-guard-clean" test 2>/dev/null; then fail "guard should have rejected dirty tree"; fi
pass "dirty tree rejected"
rm dirtyfile

echo "hv-guard-clean greenfield"
GF_TMP=$(mktemp -d)
(
  cd "$GF_TMP"
  git init -q
  echo "spec" > briefing.md
  out=$("$BIN/hv-guard-clean" test 2>&1 || true)
  case "$out" in
    *baseline*) ;;
    *) echo "[FAIL] greenfield message missing 'baseline': $out"; exit 1 ;;
  esac
) || fail "greenfield guard did not surface baseline-commit hint"
rm -rf "$GF_TMP"
pass "greenfield tree surfaces baseline-commit hint"

echo "hv-status-add / hv-status-remove"
"$BIN/hv-status-add" hv/test-branch B02,F01
grep -q '"branch": "hv/test-branch"' .hv/status.json || fail "status-add did not write entry"
grep -q '"items"' .hv/status.json || fail "items field missing"
pass "status-add wrote entry"

"$BIN/hv-status-remove" hv/test-branch
grep -q '"branch": "hv/test-branch"' .hv/status.json && fail "status-remove did not remove"
pass "status-remove cleared entry"

echo "hv-status-remove no-op when branch absent"
MTIME_BEFORE=$(stat -c %Y .hv/status.json)
"$BIN/hv-status-remove" hv/no-such-branch
MTIME_AFTER=$(stat -c %Y .hv/status.json)
[ "$MTIME_BEFORE" = "$MTIME_AFTER" ] || fail "status-remove rewrote status.json for absent branch"
pass "status-remove skipped rewrite for absent branch"

echo "hv-status-add upsert (no flag) overwrites startedAt"
"$BIN/hv-status-add" hv/ts-branch X01
TS1=$(python3 -c "import json; d=json.load(open('.hv/status.json')); print(next(e['startedAt'] for e in d['active'] if e['branch']=='hv/ts-branch'))")
sleep 1
"$BIN/hv-status-add" hv/ts-branch X01
TS2=$(python3 -c "import json; d=json.load(open('.hv/status.json')); print(next(e['startedAt'] for e in d['active'] if e['branch']=='hv/ts-branch'))")
[ "$TS1" != "$TS2" ] || fail "second status-add should have updated startedAt but it did not"
pass "status-add (no flag) overwrites startedAt on second call"
"$BIN/hv-status-remove" hv/ts-branch

echo "hv-status-add --if-absent is no-op when entry exists"
"$BIN/hv-status-add" hv/ia-branch Y01
TS1=$(python3 -c "import json; d=json.load(open('.hv/status.json')); print(next(e['startedAt'] for e in d['active'] if e['branch']=='hv/ia-branch'))")
sleep 1
"$BIN/hv-status-add" --if-absent hv/ia-branch Y01
TS2=$(python3 -c "import json; d=json.load(open('.hv/status.json')); print(next(e['startedAt'] for e in d['active'] if e['branch']=='hv/ia-branch'))")
[ "$TS1" = "$TS2" ] || fail "--if-absent overwrote startedAt but should have been a no-op"
pass "status-add --if-absent preserved startedAt when entry already exists"
"$BIN/hv-status-remove" hv/ia-branch

echo "hv-status-remove sweeps handoff note (B13)"
mkdir -p .hv/handoff/hv
# Single-repo: handoff at .hv/handoff/<branch>.md is swept on remove
"$BIN/hv-status-add" hv/sw-single B01
echo "stale" > .hv/handoff/hv/sw-single.md
"$BIN/hv-status-remove" hv/sw-single
[ ! -f .hv/handoff/hv/sw-single.md ] || fail "status-remove did not sweep single-repo handoff"
pass "status-remove sweeps single-repo handoff at .hv/handoff/<branch>.md"

# Idempotent: status-remove on a branch with no handoff is a silent no-op
"$BIN/hv-status-add" hv/sw-no-handoff B02
"$BIN/hv-status-remove" hv/sw-no-handoff
pass "status-remove is silent when no handoff exists"

# Umbrella keying: --repo sweeps .hv/handoff/<branch>@<repo>.md (and only that)
mkdir -p .hv/handoff/hv
echo "umbrella-web" > .hv/handoff/hv/sw-umb@web.md
echo "single-fallback" > .hv/handoff/hv/sw-umb.md
# A bare-call without --repo only matches legacy (repo:null) entries — and for
# handoff sweep it must mirror that scope, touching only <branch>.md.
"$BIN/hv-status-add" hv/sw-umb B03
"$BIN/hv-status-remove" hv/sw-umb
[ ! -f .hv/handoff/hv/sw-umb.md ] || fail "status-remove (no --repo) did not sweep legacy handoff"
[ -f .hv/handoff/hv/sw-umb@web.md ] || fail "status-remove (no --repo) wrongly swept umbrella-keyed handoff"
pass "status-remove (no --repo) sweeps only the legacy <branch>.md handoff"

# --repo sweeps the umbrella-keyed handoff
"$BIN/hv-status-add" --repo web hv/sw-umb B03
"$BIN/hv-status-remove" --repo web hv/sw-umb
[ ! -f .hv/handoff/hv/sw-umb@web.md ] || fail "status-remove --repo did not sweep umbrella-keyed handoff"
pass "status-remove --repo sweeps the .hv/handoff/<branch>@<repo>.md handoff"
rm -rf .hv/handoff

echo "hv-archive-old"
# Inject two completed items: one old, one recent
python3 - <<'PY'
from pathlib import Path
from datetime import date, timedelta
p = Path(".hv/TODO.md")
c = p.read_text()
old = (date.today() - timedelta(days=10)).strftime("%Y-%m-%d")
recent = (date.today() - timedelta(days=1)).strftime("%Y-%m-%d")
c = c.rstrip() + f"\n- ~~**[B99] Old bug.**~~ Done {old} [`aaa`]\n- ~~**[F99] Recent feature.**~~ Done {recent} [`bbb`]\n"
p.write_text(c)
PY
COUNT=$("$BIN/hv-archive-old" 5)
[ "$COUNT" = "1" ] || fail "expected 1 archived, got '$COUNT'"
grep -q "B99" .hv/ARCHIVE.md || fail "B99 not in ARCHIVE.md"
grep -q "B99" .hv/TODO.md && fail "B99 still in TODO.md"
grep -q "F99" .hv/TODO.md || fail "F99 should still be in TODO.md"
pass "old item archived, recent item kept"

