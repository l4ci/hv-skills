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
mkdir -p .hv/bugs .hv/features .hv/tasks

cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
echo '{"bugs":0,"features":0,"tasks":0}' > .hv/counters.json
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

COUNTERS=$(cat .hv/counters.json)
echo "$COUNTERS" | grep -q '"bugs": 2' || fail "counters.bugs != 2: $COUNTERS"
echo "$COUNTERS" | grep -q '"features": 1' || fail "counters.features != 1: $COUNTERS"
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
grep -q "<!-- hv:knowledge:start -->" CLAUDE.md || fail "managed block not in CLAUDE.md"
grep -q "^- Architecture" CLAUDE.md || fail "Architecture topic missing"
grep -q "^- Testing" CLAUDE.md || fail "Testing topic missing"
pass "CLAUDE.md managed block created with topics"

# Re-running should update in place, not duplicate
"$BIN/hv-knowledge-index" >/dev/null
COUNT_START=$(grep -c "hv:knowledge:start" CLAUDE.md)
[ "$COUNT_START" = "1" ] || fail "managed block duplicated"
pass "managed block updated in place"

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

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
