#!/usr/bin/env bash
# Smoke test for .hv/bin/ helpers. Creates a throwaway .hv/ in a tmpdir,
# runs each helper, and asserts the expected state.
# Usage: bash test/smoke.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
mkdir -p .hv/bugs .hv/features .hv/tasks .hv/milestones

cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
cat > .hv/MILESTONES.md <<'EOF'
# Vision

_(no vision yet — run `/hv-vision` to brainstorm milestones)_

## Active milestones

_(none active — set with `/hv-vision`)_

## Milestones
EOF
echo '{"bugs":0,"features":0,"tasks":0,"milestones":0}' > .hv/counters.json
echo '{"active":[]}' > .hv/status.json

git init -q
git config user.email t@t && git config user.name t
git checkout -q -b main 2>/dev/null || git branch -m main
git add -A && git commit -q -m "seed"

pass() { printf '  \033[32mOK\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

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

echo "hv-status-add / hv-status-remove"
"$BIN/hv-status-add" hv/test-branch B02,F01
grep -q '"branch": "hv/test-branch"' .hv/status.json || fail "status-add did not write entry"
grep -q '"items"' .hv/status.json || fail "items field missing"
pass "status-add wrote entry"

"$BIN/hv-status-remove" hv/test-branch
grep -q '"branch": "hv/test-branch"' .hv/status.json && fail "status-remove did not remove"
pass "status-remove cleared entry"

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

echo "hv-knowledge-index"
mkdir -p .hv
cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Architecture
- something

## Testing
- another thing
EOF
"$BIN/hv-knowledge-index" >/dev/null
grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || fail "managed block not in CLAUDE.md"
grep -q "^- Architecture" CLAUDE.md || fail "Architecture topic missing"
grep -q "^- Testing" CLAUDE.md || fail "Testing topic missing"
pass "CLAUDE.md managed block created with topics"

# Re-running should update in place, not duplicate
"$BIN/hv-knowledge-index" >/dev/null
COUNT_START=$(grep -c "hv-knowledge-start" CLAUDE.md)
[ "$COUNT_START" = "1" ] || fail "managed block duplicated"
pass "managed block updated in place"

# Legacy colon markers in CLAUDE.md must migrate to new dashed markers in place
cat > CLAUDE.md <<'EOF'
# Preamble

<!-- hv:knowledge:start -->
## Project Knowledge
- OldTopic
<!-- hv:knowledge:end -->

# Postamble
EOF
"$BIN/hv-knowledge-index" >/dev/null
grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || fail "legacy markers not migrated to new format"
grep -q "hv:knowledge:start" CLAUDE.md && fail "legacy colon markers still present after migration"
grep -q "^# Preamble" CLAUDE.md || fail "preamble lost during migration"
grep -q "^# Postamble" CLAUDE.md || fail "postamble lost during migration"
pass "legacy colon markers migrated to dashed format in place"

echo "hv-reconcile"
# Seed an entry whose branch doesn't exist — should be cleaned
"$BIN/hv-status-add" hv/dead-branch B05
OUTPUT=$("$BIN/hv-reconcile")
echo "$OUTPUT" | grep -q '"reason": "branch_gone"' || fail "reconcile did not flag dead branch"
pass "reconcile cleans stale branch entry"

# Seed an entry with a real branch
git checkout -q -b hv/real-branch
echo "work" > work.txt && git add -A && git commit -q -m "wip"
git checkout -q main
"$BIN/hv-status-add" hv/real-branch F02
OUTPUT=$("$BIN/hv-reconcile")
echo "$OUTPUT" | grep -q '"branch": "hv/real-branch"' || fail "real branch not in needsAction"
echo "$OUTPUT" | grep -q '"hasCommits": true' || fail "hasCommits should be true"
pass "reconcile reports real branch with commits"

echo "hv-knowledge-query"
cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Architecture
- arch bullet one
- arch bullet two

## Testing
- testing bullet

## Networking
- net bullet
EOF
OUT=$("$BIN/hv-knowledge-query" "Testing" "Networking")
echo "$OUT" | grep -q "testing bullet" || fail "testing topic missing from query"
echo "$OUT" | grep -q "net bullet" || fail "networking topic missing from query"
echo "$OUT" | grep -q "arch bullet" && fail "architecture topic leaked into query"
pass "knowledge-query returns only requested topics"

echo "hv-backlog"
# Seed a mix of items in TODO.md
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B10] [P2] Minor glitch.** Desc.
- **[B11] [P0] Crash on launch.** Desc. Related: [F20]

## Features
- **[F20] [Minor] Quick-switch.** Desc. Related: [B11]
- **[F21] [Cosmetic] Tweak spacing.** Desc.

## Tasks
- **[T30] Update toolchain.** Desc.

## Completed
EOF
OUT=$("$BIN/hv-backlog")
LINE_P0=$(echo "$OUT" | grep -n "| B11 " | head -1 | cut -d: -f1)
LINE_P2=$(echo "$OUT" | grep -n "| B10 " | head -1 | cut -d: -f1)
[ "$LINE_P0" -lt "$LINE_P2" ] || fail "P0 not sorted before P2 (B11 at $LINE_P0, B10 at $LINE_P2)"
LINE_COS=$(echo "$OUT" | grep -n "| F21 " | head -1 | cut -d: -f1)
LINE_MIN=$(echo "$OUT" | grep -n "| F20 " | head -1 | cut -d: -f1)
[ "$LINE_COS" -lt "$LINE_MIN" ] || fail "Cosmetic not sorted before Minor (F21 at $LINE_COS, F20 at $LINE_MIN)"
pass "backlog sorts bugs by priority and features by size"

# Active items should move to In Progress
"$BIN/hv-status-add" hv/real-branch F20
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "### In Progress" || fail "In Progress section missing"
# F20 should no longer appear in ### Features section
FEAT_BLOCK=$(echo "$OUT" | awk '/^### Features/,/^### Tasks/')
echo "$FEAT_BLOCK" | grep -q "F20" && fail "active F20 leaked into Features table"
pass "active items excluded from Features section"
"$BIN/hv-status-remove" hv/real-branch

echo "hv-refactor-age"
# Seed two completed entries with real commits
git checkout -q main
echo "f1" > f1.txt && git add f1.txt && git commit -q -m "feat: add f1"
HASH_F=$(git log -1 --format='%h')
echo "b1" > b1.txt && git add b1.txt && git commit -q -m "fix: resolve b1"
HASH_B=$(git log -1 --format='%h')
echo "r1" > r1.txt && git add r1.txt && git commit -q -m "refactor: clean up"
HASH_R=$(git log -1 --format='%h')
cat >> .hv/TODO.md <<EOF
- ~~**[F40] Feature done.**~~ Done 2026-04-18 [\`$HASH_F\`]
- ~~**[B40] Bug fixed.**~~ Done 2026-04-18 [\`$HASH_B\`]
- ~~**[F41] Refactor-driven feature.**~~ Done 2026-04-18 [\`$HASH_R\`]
EOF
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 1' || fail "expected 1 non-refactor feature, got: $OUT"
echo "$OUT" | grep -q '"bugs": 1' || fail "expected 1 non-refactor bug, got: $OUT"
pass "refactor-age excludes refactor: commits"

echo "hv-merge / hv-pr"
# Check syntactic integrity — they should error cleanly without stdin input
if echo "" | "$BIN/hv-merge" hv/real-branch 2>/dev/null; then
  fail "hv-merge should reject empty message"
fi
pass "hv-merge rejects empty message"
# Don't actually run hv-pr — no remote

echo "regression: hv-backlog preserves periods in titles"
cat > .hv/TODO.md <<'EOF'
# TODO

## Features
- **[F50] [Minor] Add v1.2 support.** Desc here.

## Bugs

## Tasks

## Completed
EOF
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "Add v1.2 support" || fail "title with period was truncated: $(echo "$OUT" | grep F50)"
pass "backlog keeps mid-title periods intact"

echo "regression: hv-archive-old always prints count"
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
COUNT=$("$BIN/hv-archive-old" 5)
[ "$COUNT" = "0" ] || fail "expected '0' when nothing to archive, got '$COUNT'"
pass "archive-old prints 0 when no items to move"

echo "hv-ship-body"
# Fresh branch state for ship-body + review-scope
git checkout -q main 2>/dev/null || true
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B70] [P1] Ship demo bug.** Broken badge.~~ Done 2026-04-18 [`aaa1111`]
- ~~**[F70] [Minor] Ship demo feature.** Overlay.~~ Done 2026-04-18 [`bbb2222`]
EOF
git add -A && git commit -q -m "seed ship demo" || true
git checkout -q -b hv/ship-demo
echo ship1 > ship1.txt && git add ship1.txt && git commit -q -m "fix: badge invalidation [B70]"
echo ship2 > ship2.txt && git add ship2.txt && git commit -q -m "feat: overlay [F70]"
git checkout -q main

BODY=$("$BIN/hv-ship-body" hv/ship-demo)
echo "$BODY" | grep -q "^## Summary" || fail "ship-body missing Summary section"
echo "$BODY" | grep -q "^## Items resolved" || fail "ship-body missing Items resolved section"
echo "$BODY" | grep -q "\[B70\] Ship demo bug" || fail "ship-body missing B70 title"
echo "$BODY" | grep -q "\[F70\] Ship demo feature" || fail "ship-body missing F70 title"
pass "ship-body emits Summary + Items resolved with resolved titles"

if "$BIN/hv-ship-body" main 2>/dev/null; then fail "ship-body should reject main (no commits vs base)"; fi
pass "ship-body errors when base has no commits"

echo "hv-review-scope"
OUT=$("$BIN/hv-review-scope" hv/ship-demo)
echo "$OUT" | grep -q '"commitCount": 2' || fail "review-scope commitCount != 2: $OUT"
echo "$OUT" | grep -q '"B70"' || fail "review-scope missing B70"
echo "$OUT" | grep -q '"F70"' || fail "review-scope missing F70"
echo "$OUT" | grep -q '"title": "Ship demo bug"' || fail "review-scope missing B70 title"
echo "$OUT" | grep -q '"ship1.txt"' || fail "review-scope missing touched file"
pass "review-scope emits commits, IDs, titles, and files"

if "$BIN/hv-review-scope" main 2>/dev/null; then fail "review-scope should reject base branch"; fi
pass "review-scope rejects base branch"

# Regression: review-scope must attribute an ID to its OWN bullet, not to
# another item that mentions the ID in a `Related:` suffix.
git checkout -q main
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features
- **[F80] [Minor] Refers to B70.** Something else. Related: [B70]

## Tasks

## Completed
EOF
cat > .hv/ARCHIVE.md <<'EOF'
# Archive

- ~~**[B70] [P1] Ship demo bug.** Broken badge.~~ Done 2026-04-10 [`aaa1111`]
EOF
git add -A && git commit -q -m "seed related-link test" || true
git checkout -q -b hv/scope-regression
echo r > r.txt && git add r.txt && git commit -q -m "fix: badge [B70]"
git checkout -q main
OUT=$("$BIN/hv-review-scope" hv/scope-regression)
echo "$OUT" | grep -q '"title": "Ship demo bug"' || fail "review-scope picked wrong bullet for B70 (Related-link regression): $OUT"
pass "review-scope picks origin bullet, ignores Related-link references"
git branch -D hv/scope-regression >/dev/null 2>&1 || true
rm -f r.txt

# Cleanup demo branch before later tests
git branch -D hv/ship-demo >/dev/null 2>&1 || true
rm -f ship1.txt ship2.txt

echo "hv-update-check"
# Seed a fake install with a plugin.json so detection has something to find.
mkdir -p fake-install/.claude-plugin
cat > fake-install/.claude-plugin/plugin.json <<'EOF'
{"name":"hv-skills","version":"1.2.0"}
EOF

OUT=$(HV_INSTALL_ROOT="$TMP/fake-install" HV_LATEST_VERSION=1.3.0 "$BIN/hv-update-check")
echo "$OUT" | grep -q '"currentVersion": "1.2.0"' || fail "update-check didn't read current version"
echo "$OUT" | grep -q '"latestVersion": "1.3.0"' || fail "update-check didn't use override latest"
echo "$OUT" | grep -q '"status": "behind"' || fail "update-check didn't mark behind"
pass "update-check reports behind when current < latest"

OUT=$(HV_INSTALL_ROOT="$TMP/fake-install" HV_LATEST_VERSION=1.2.0 "$BIN/hv-update-check")
echo "$OUT" | grep -q '"status": "current"' || fail "update-check didn't mark current"
pass "update-check reports current when equal"

OUT=$(HV_INSTALL_ROOT="$TMP/fake-install" HV_LATEST_VERSION=1.1.0 "$BIN/hv-update-check")
echo "$OUT" | grep -q '"status": "ahead"' || fail "update-check didn't mark ahead"
pass "update-check reports ahead when current > latest"

rm -rf fake-install

echo "hv-summary"
# Reset to a known state and check the summary lines
rm -f .hv/ARCHIVE.md
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B60] [P1] Active bug.** Desc.

## Features
- **[F60] [Minor] Pending feature.** Desc.
- **[F61] [Cosmetic] Another feature.** Desc.

## Tasks

## Completed
- ~~**[B01] Resolved bug.**~~ Done 2026-04-18 [`abc1234`]
EOF
cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Architecture
- a

## Testing
- t
EOF
OUT=$("$BIN/hv-summary")
echo "$OUT" | grep -q "1 bug," || fail "bug count wrong: $OUT"
echo "$OUT" | grep -q "2 features," || fail "feature count wrong: $OUT"
echo "$OUT" | grep -q "0 tasks" || fail "task count wrong: $OUT"
echo "$OUT" | grep -q "Recent: \[B01\]" || fail "recent completion missing: $OUT"
echo "$OUT" | grep -q "Knowledge: 2 topics" || fail "knowledge topic count wrong: $OUT"
pass "summary reports backlog/recent/knowledge correctly"

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
cp "$BIN"/hv-* .hv/bin/ && chmod +x .hv/bin/hv-*
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

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
