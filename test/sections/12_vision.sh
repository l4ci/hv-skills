echo "hv-vision-add / hv-vision-status / hv-vision-active / hv-vision-list / hv-vision-index"
# Reset milestones counter so the next mint is M01.
python3 -c "
import json
p='.hv/counters.json'
d=json.load(open(p)); d['milestones']=0; json.dump(d,open(p,'w'))
"
# Re-seed MILESTONES.md (earlier hv-knowledge-index test rewrote CLAUDE.md, but
# MILESTONES.md is untouched).
cat > .hv/MILESTONES.md <<'EOF'
# Vision

Test project vision.

## Active milestones

_(none active — set with `/hv-vision`)_

## Milestones
EOF
mkdir -p .hv/milestones

ID_M1=$("$BIN/hv-vision-add" "Auth foundation" "OAuth + sessions for end users.")
[ "$ID_M1" = "M01" ] || fail "expected M01 from vision-add, got $ID_M1"
[ -f .hv/milestones/M01.md ] || fail "M01 detail file not created"
grep -q "^id: M01$" .hv/milestones/M01.md || fail "M01 frontmatter missing id"
grep -q "^status: planned$" .hv/milestones/M01.md || fail "M01 status not planned"
grep -q "### M01 — Auth foundation" .hv/MILESTONES.md || fail "M01 not in MILESTONES.md"
grep -q "Status:\*\* planned" .hv/MILESTONES.md || fail "M01 overview missing status"
pass "vision-add creates detail file + overview entry"

ID_M2=$("$BIN/hv-vision-add" "Multi-tenant" "Org isolation for B2B." "M01")
[ "$ID_M2" = "M02" ] || fail "expected M02, got $ID_M2"
grep -q "^depends: \[M01\]$" .hv/milestones/M02.md || fail "M02 depends not [M01]"
grep -q "Depends:\*\* M01" .hv/MILESTONES.md || fail "M02 overview missing depends"
pass "vision-add records dependencies"

"$BIN/hv-vision-status" M01 active
grep -q "^status: active$" .hv/milestones/M01.md || fail "M01 status not updated to active in detail"
grep -q "### M01 — Auth foundation" .hv/MILESTONES.md || fail "M01 section gone"
# Confirm overview status line for M01 is now active
python3 -c "
import re, sys
ms = open('.hv/MILESTONES.md').read()
m = re.search(r'### M01 — Auth foundation\n\n\*\*Status:\*\* (\w+)', ms)
sys.exit(0 if (m and m.group(1) == 'active') else 1)
" || fail "M01 overview status not updated to active"
pass "vision-status updates frontmatter and overview"

ACTIVE=$("$BIN/hv-vision-active")
[ "$ACTIVE" = "M01" ] || fail "expected active=M01, got '$ACTIVE'"
pass "vision-active lists only active IDs"

LIST=$("$BIN/hv-vision-list")
echo "$LIST" | python3 -c "
import json, sys
data = json.load(sys.stdin)
ids = {i['id']: i for i in data}
assert 'M01' in ids and 'M02' in ids, f'missing IDs: {ids.keys()}'
assert ids['M02']['depends'] == ['M01'], f'M02 depends: {ids[\"M02\"][\"depends\"]}'
assert ids['M02']['ready'] is False, 'M02 should not be ready (M01 not shipped)'
assert ids['M01']['ready'] is True, 'M01 has no deps; should be ready'
" || fail "vision-list output did not match expectations"
pass "vision-list emits JSON with status, depends, ready"

"$BIN/hv-vision-index" >/dev/null
grep -q "<!-- hv-vision-start -->" CLAUDE.md || fail "vision block not in CLAUDE.md"
grep -q "M01.*Auth foundation" CLAUDE.md || fail "active milestone not in CLAUDE.md vision block"
# Re-running idempotent
"$BIN/hv-vision-index" >/dev/null
COUNT_VISION=$(grep -c "hv-vision-start" CLAUDE.md)
[ "$COUNT_VISION" = "1" ] || fail "vision block duplicated"
pass "vision-index updates CLAUDE.md and active section in MILESTONES.md"

# Active section in MILESTONES.md should now reflect M01
grep -q "^- M01 — Auth foundation" .hv/MILESTONES.md || fail "## Active milestones not updated"
pass "vision-index regenerates ## Active milestones section"

# Marking M01 shipped should mark M02 as ready
"$BIN/hv-vision-status" M01 shipped
LIST=$("$BIN/hv-vision-list")
echo "$LIST" | python3 -c "
import json, sys
data = json.load(sys.stdin)
m02 = next(i for i in data if i['id'] == 'M02')
sys.exit(0 if m02['ready'] else 1)
" || fail "M02 should be ready once M01 shipped"
pass "vision-list marks ready when dependencies are shipped"

echo "hv-todo-by-milestone / Milestone field on entries"
# Reactivate M01 and tag a couple of TODO entries.
"$BIN/hv-vision-status" M01 active >/dev/null
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B60] [P1] Auth flicker.** Sign-in card flashes on render. Related: [F60] Milestone: M01

## Features
- **[F60] [Minor] OAuth rotation.** Refresh tokens before expiry. Milestone: M01, M02
- **[F61] [Cosmetic] Untagged feature.** Just a tweak.

## Tasks

## Completed
EOF
TAGGED=$("$BIN/hv-todo-by-milestone" M01)
echo "$TAGGED" | grep -qx "B60" || fail "hv-todo-by-milestone missed B60 (M01): '$TAGGED'"
echo "$TAGGED" | grep -qx "F60" || fail "hv-todo-by-milestone missed F60 (M01): '$TAGGED'"
echo "$TAGGED" | grep -qx "F61" && fail "hv-todo-by-milestone returned untagged F61"
pass "hv-todo-by-milestone returns only tagged items"
TAGGED2=$("$BIN/hv-todo-by-milestone" M02)
echo "$TAGGED2" | grep -qx "F60" || fail "hv-todo-by-milestone missed F60 (M02 multi-tag)"
pass "hv-todo-by-milestone handles multi-milestone tags"

echo "hv-backlog regression: Milestone field doesn't leak into Related"
OUT=$("$BIN/hv-backlog")
B60_ROW=$(echo "$OUT" | grep " B60 ")
# Related cell should be exactly "[F60]" (no Milestone bleed)
echo "$B60_ROW" | grep -q "| \[F60\] |" || fail "B60 row Related cell looks wrong: $B60_ROW"
echo "$B60_ROW" | grep -q "Milestone:" && fail "Milestone: leaked into a backlog row"
# Milestone column should appear when any item carries the field
echo "$OUT" | grep -q "| Milestone |" || fail "backlog header missing Milestone column"
echo "$OUT" | grep -q " M01, M02 " || fail "F60 multi-milestone cell missing"
pass "backlog adds Milestone column without breaking Related parsing"

echo "hv-summary surfaces active milestones"
OUT=$("$BIN/hv-summary")
echo "$OUT" | grep -q "Active milestones: M01" || fail "summary missing active milestone line: $OUT"
pass "summary lists active milestones"

# Reset summary fixtures (no Milestone field) to keep later assertions clean.
"$BIN/hv-vision-status" M01 shipped >/dev/null

echo "hv-bootstrap"
# Self-contained: run in a fresh subdir so the existing .hv/ in TMP isn't touched.
BOOT_DIR="$TMP/boot-test"
mkdir -p "$BOOT_DIR"
( cd "$BOOT_DIR" && "$BIN/hv-bootstrap" )
[ -f "$BOOT_DIR/.hv/TODO.md" ] || fail "hv-bootstrap did not seed TODO.md"
[ -f "$BOOT_DIR/.hv/KNOWLEDGE.md" ] || fail "hv-bootstrap did not seed KNOWLEDGE.md"
[ -f "$BOOT_DIR/.hv/MILESTONES.md" ] || fail "hv-bootstrap did not seed MILESTONES.md"
[ -f "$BOOT_DIR/.hv/counters.json" ] || fail "hv-bootstrap did not seed counters.json"
[ -f "$BOOT_DIR/.hv/status.json" ] || fail "hv-bootstrap did not seed status.json"
[ -d "$BOOT_DIR/.hv/bin" ] || fail "hv-bootstrap did not create .hv/bin"
grep -q '^\.hv/' "$BOOT_DIR/.gitignore" || fail "hv-bootstrap did not add .hv/ to .gitignore"
grep -q '"milestones": *0' "$BOOT_DIR/.hv/counters.json" || fail "hv-bootstrap counters.json missing milestones key"
pass "hv-bootstrap seeds dirs, data files, and .gitignore"

# Idempotency: re-running must not overwrite existing data.
echo "user content" > "$BOOT_DIR/.hv/TODO.md"
( cd "$BOOT_DIR" && "$BIN/hv-bootstrap" )
grep -q "^user content$" "$BOOT_DIR/.hv/TODO.md" || fail "hv-bootstrap overwrote existing TODO.md"
pass "hv-bootstrap is idempotent (preserves existing files)"

# Counters migration: older counters.json without milestones key must gain it.
echo '{"bugs":3,"features":1,"tasks":0}' > "$BOOT_DIR/.hv/counters.json"
( cd "$BOOT_DIR" && "$BIN/hv-bootstrap" )
grep -q '"milestones": *0' "$BOOT_DIR/.hv/counters.json" || fail "hv-bootstrap did not migrate counters.json to add milestones key"
grep -q '"bugs": *3' "$BOOT_DIR/.hv/counters.json" || fail "hv-bootstrap dropped existing counters during migration"
pass "hv-bootstrap migrates legacy counters.json"

rm -rf "$BOOT_DIR"

echo "hv-preflight"
# Ensure all core data files exist (smoke setup creates TODO.md/counters.json/status.json;
# KNOWLEDGE.md got written by hv-knowledge-index; config.json is needed by preflight).
[ -f .hv/config.json ] || echo '{}' > .hv/config.json

# 1. Helpers not yet installed in .hv/bin → exit 3 (partial install).
rc=0
"$BIN/hv-preflight" 2>/dev/null || rc=$?
[ "$rc" = "3" ] || fail "expected exit 3 (partial install), got $rc"
pass "preflight exits 3 when helpers missing from .hv/bin"

# 2. Install all helpers into .hv/bin, everything present → exit 0.
mkdir -p .hv/bin
cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
"$BIN/hv-preflight" >/dev/null 2>&1 || fail "preflight failed on fully initialized project"
pass "preflight exits 0 when fully initialized"

# 3. Missing core data file → exit 2 (uninitialized).
mv .hv/TODO.md .hv/TODO.md.bak
rc=0
"$BIN/hv-preflight" 2>/dev/null || rc=$?
[ "$rc" = "2" ] || fail "expected exit 2 (uninitialized), got $rc"
pass "preflight exits 2 when a data file is missing"
mv .hv/TODO.md.bak .hv/TODO.md

# 4. Missing helper → exit 3 (stale install after plugin upgrade).
rm .hv/bin/hv-summary
rc=0
"$BIN/hv-preflight" 2>/dev/null || rc=$?
[ "$rc" = "3" ] || fail "expected exit 3 (missing helper), got $rc"
pass "preflight exits 3 when a helper is missing"

echo "hv-plan-add / hv-plan-list / hv-plan-show / hv-plan-rm"
KEY1=$("$BIN/hv-plan-add" M01 slice "Auth foundation")
[ "$KEY1" = "M01-S01" ] || fail "expected M01-S01, got $KEY1"
[ -f .hv/plans/M01-S01.md ] || fail "M01-S01.md not created"
grep -q "^key: M01-S01$" .hv/plans/M01-S01.md || fail "key field missing"
grep -q "^unitKind: slice$" .hv/plans/M01-S01.md || fail "unitKind not slice"
grep -q "title: Auth foundation" .hv/plans/M01-S01.md || fail "title missing from plan"
pass "first slice plan = M01-S01"

KEY2=$("$BIN/hv-plan-add" M01 slice "Auth refresh")
[ "$KEY2" = "M01-S02" ] || fail "expected M01-S02, got $KEY2"
pass "second slice plan auto-mints M01-S02"

KEY3=$("$BIN/hv-plan-add" M01 B07 "Sign-in flicker")
[ "$KEY3" = "M01-B07" ] || fail "expected M01-B07, got $KEY3"
[ -f .hv/plans/M01-B07.md ] || fail "M01-B07.md not created"
grep -q "^unitKind: item$" .hv/plans/M01-B07.md || fail "unitKind not item"
pass "item plan uses item ID verbatim"

if "$BIN/hv-plan-add" M01 B07 "Duplicate" 2>/dev/null; then
  fail "hv-plan-add should reject existing key"
fi
pass "hv-plan-add rejects existing key"

if "$BIN/hv-plan-add" not-a-milestone slice "x" 2>/dev/null; then
  fail "hv-plan-add should reject malformed milestone"
fi
pass "hv-plan-add rejects malformed milestone"

if "$BIN/hv-plan-add" M01 bogus "x" 2>/dev/null; then
  fail "hv-plan-add should reject malformed unit"
fi
pass "hv-plan-add rejects malformed unit"

"$BIN/hv-plan-add" M02 slice "Multi-tenant" >/dev/null
LIST=$("$BIN/hv-plan-list")
echo "$LIST" | python3 -c "
import json, sys
data = json.load(sys.stdin)
keys = {i['key']: i for i in data}
for k in ('M01-S01', 'M01-S02', 'M01-B07', 'M02-S01'):
    assert k in keys, f'missing {k}'
assert keys['M01-S01']['unitKind'] == 'slice'
assert keys['M01-B07']['unitKind'] == 'item'
assert keys['M01-B07']['milestone'] == 'M01'
" || fail "hv-plan-list output did not match"
pass "hv-plan-list emits all plans with correct fields"

LIST_M01=$("$BIN/hv-plan-list" M01)
echo "$LIST_M01" | python3 -c "
import json, sys
data = json.load(sys.stdin)
mss = {i['milestone'] for i in data}
assert mss == {'M01'}, f'leak: {mss}'
" || fail "hv-plan-list M01 leaked other milestones"
pass "hv-plan-list filters by milestone"

SHOW=$("$BIN/hv-plan-show" M01-S01)
echo "$SHOW" | grep -q "^# M01-S01 — Auth foundation" || fail "show output missing title"
pass "hv-plan-show prints content"

if "$BIN/hv-plan-show" M99-S99 2>/dev/null; then
  fail "hv-plan-show should reject unknown key"
fi
pass "hv-plan-show rejects unknown key"

"$BIN/hv-plan-rm" M01-B07
[ -f .hv/plans/M01-B07.md ] && fail "M01-B07 not removed"
pass "hv-plan-rm deletes plan"

if "$BIN/hv-plan-rm" M99-S99 2>/dev/null; then
  fail "hv-plan-rm should reject unknown key"
fi
pass "hv-plan-rm rejects unknown key"

echo "hv-spike-add / hv-spike-list / hv-spike-finish"
git checkout -q main 2>/dev/null || true

BRANCH=$("$BIN/hv-spike-add" sse-feasibility "Can SSE work over our nginx without proxy buffering?")
[ "$BRANCH" = "spike/sse-feasibility" ] || fail "expected spike/sse-feasibility, got $BRANCH"
[ -f .hv/spikes/sse-feasibility.md ] || fail "spike file not created"
git rev-parse --verify spike/sse-feasibility >/dev/null 2>&1 || fail "spike branch not created"
grep -q "^name: sse-feasibility$" .hv/spikes/sse-feasibility.md || fail "spike name missing"
grep -q "^status: open$" .hv/spikes/sse-feasibility.md || fail "spike status not open"
grep -q "Can SSE work" .hv/spikes/sse-feasibility.md || fail "question not embedded"
pass "spike-add creates branch and file"

if "$BIN/hv-spike-add" "Bad Name" "?" 2>/dev/null; then
  fail "hv-spike-add should reject bad name"
fi
pass "hv-spike-add rejects bad name"

if "$BIN/hv-spike-add" sse-feasibility "?" 2>/dev/null; then
  fail "hv-spike-add should reject existing branch"
fi
pass "hv-spike-add rejects existing branch"

SLIST=$("$BIN/hv-spike-list")
echo "$SLIST" | python3 -c "
import json, sys
data = json.load(sys.stdin)
sse = next((s for s in data if s['name'] == 'sse-feasibility'), None)
assert sse is not None, 'sse-feasibility missing'
assert sse['branch'] == 'spike/sse-feasibility', f'wrong branch: {sse[\"branch\"]}'
assert sse['status'] == 'open', f'wrong status: {sse[\"status\"]}'
assert sse['branchExists'] is True, 'branchExists should be True'
" || fail "spike-list output did not match"
pass "spike-list emits spikes with branch state"

"$BIN/hv-spike-finish" sse-feasibility
grep -q "^status: done$" .hv/spikes/sse-feasibility.md || fail "spike status not done"
grep -q "^finished:" .hv/spikes/sse-feasibility.md || fail "spike finished date missing"
pass "spike-finish flips status to done"

if "$BIN/hv-spike-finish" not-a-spike 2>/dev/null; then
  fail "hv-spike-finish should reject unknown name"
fi
pass "hv-spike-finish rejects unknown name"

git branch -D spike/sse-feasibility >/dev/null 2>&1 || true

echo "items <-> milestones <-> plans triangle"
# Reset TODO.md to a known state, mint a fresh bug ID via hv-next-id, append a
# Milestone-tagged entry, and verify the full chain: hv-todo-by-milestone picks
# it up, hv-plan-add mints a plan keyed under the same milestone, hv-plan-list
# surfaces it.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
TRI_BUG=$("$BIN/hv-next-id" bugs)
"$BIN/hv-append" "## Bugs" "- **[$TRI_BUG] [P1] Triangle bug.** Desc. Milestone: M01"
TAGGED=$("$BIN/hv-todo-by-milestone" M01)
echo "$TAGGED" | grep -qx "$TRI_BUG" || fail "triangle: $TRI_BUG not found in M01 items: '$TAGGED'"
pass "triangle: tagged bug surfaces in hv-todo-by-milestone M01"

TRI_KEY=$("$BIN/hv-plan-add" M01 "$TRI_BUG" "Triangle bug fix")
[ "$TRI_KEY" = "M01-$TRI_BUG" ] || fail "triangle: expected plan key M01-$TRI_BUG, got $TRI_KEY"
[ -f ".hv/plans/M01-$TRI_BUG.md" ] || fail "triangle: plan file .hv/plans/M01-$TRI_BUG.md missing"
pass "triangle: hv-plan-add minted plan keyed M01-$TRI_BUG"

LIST_M01=$("$BIN/hv-plan-list" M01)
echo "$LIST_M01" | TRI_BUG="$TRI_BUG" python3 -c "
import json, sys, os
key = 'M01-' + os.environ['TRI_BUG']
data = json.load(sys.stdin)
keys = {i['key']: i for i in data}
assert key in keys, f'missing {key} in {list(keys)}'
assert keys[key]['unitKind'] == 'item', f'unitKind: {keys[key][\"unitKind\"]}'
assert keys[key]['milestone'] == 'M01', f'milestone: {keys[key][\"milestone\"]}'
" || fail "triangle: hv-plan-list M01 missing $TRI_KEY entry"
pass "triangle: hv-plan-list M01 reports new plan with item unitKind"

# Cleanup the triangle plan to avoid polluting later assertions.
"$BIN/hv-plan-rm" "$TRI_KEY" >/dev/null

echo "hv-todo-by-milestone field-order regression"
# Wave 1 made the regex order-agnostic. Guard against a future regression by
# tagging Milestone: in three different positions: first, middle, last.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B71] [P1] Milestone first.** Milestone: M01 Detail: `.hv/bugs/B71.md` Related: [F71]
- **[B72] [P1] Milestone middle.** Detail: `.hv/bugs/B72.md` Milestone: M01 Related: [F71]
- **[B73] [P1] Milestone last.** Detail: `.hv/bugs/B73.md` Related: [F71] Milestone: M01

## Features

## Tasks

## Completed
EOF
TAGGED=$("$BIN/hv-todo-by-milestone" M01)
for ID in B71 B72 B73; do
  echo "$TAGGED" | grep -qx "$ID" || fail "field-order: $ID missing from M01 items (regex regressed?): '$TAGGED'"
done
pass "hv-todo-by-milestone is order-agnostic across Detail/Related/Milestone"

echo "hv-backlog field-order regression"
# Guard against parse_todo_fields regressions: Milestone before Related, and after.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B74] [P1] MS before Related.** Desc. Milestone: M01 Related: [F02]
- **[B75] [P1] MS after Related.** Desc. Related: [F02] Milestone: M01

## Features

## Tasks

## Completed
EOF
BL_OUT=$("$BIN/hv-backlog")
echo "$BL_OUT" | grep -q "M01" || fail "hv-backlog field-order: Milestone column missing from output: '$BL_OUT'"
echo "$BL_OUT" | grep "B74" | grep -q "M01" || fail "hv-backlog field-order: B74 (MS before Related) missing M01: '$BL_OUT'"
echo "$BL_OUT" | grep "B75" | grep -q "M01" || fail "hv-backlog field-order: B75 (MS after Related) missing M01: '$BL_OUT'"
pass "hv-backlog Milestone column correct regardless of field order"

echo "archived milestone status"
# Mint a fresh milestone, archive it, and verify exclusion + frontmatter + overview.
ARCH_ID=$("$BIN/hv-vision-add" "Throwaway prototype" "Will be abandoned for testing.")
ACTIVE_BEFORE=$("$BIN/hv-vision-active")
echo "$ACTIVE_BEFORE" | grep -qx "$ARCH_ID" && fail "archived test: $ARCH_ID was active before archival (unexpected)"

"$BIN/hv-vision-status" "$ARCH_ID" archived
ACTIVE_AFTER=$("$BIN/hv-vision-active")
echo "$ACTIVE_AFTER" | grep -qx "$ARCH_ID" && fail "archived: $ARCH_ID still appears in hv-vision-active"
pass "archived milestone excluded from hv-vision-active"

grep -q "^status: archived$" ".hv/milestones/$ARCH_ID.md" || fail "archived: frontmatter status not 'archived'"
pass "archived milestone frontmatter status updated"

ARCH_ID="$ARCH_ID" python3 -c "
import re, sys, os
mid = os.environ['ARCH_ID']
ms = open('.hv/MILESTONES.md').read()
m = re.search(rf'### {mid} — Throwaway prototype\n\n\*\*Status:\*\* (\w+)', ms)
sys.exit(0 if (m and m.group(1) == 'archived') else 1)
" || fail "archived: MILESTONES.md overview not 'archived'"
pass "archived milestone overview line reflects status"

# Reject unknown status values with the new four-option error message.
if "$BIN/hv-vision-status" "$ARCH_ID" bogus 2>/dev/null; then
  fail "archived: hv-vision-status accepted a bogus status value"
fi
pass "hv-vision-status rejects unknown status values"

