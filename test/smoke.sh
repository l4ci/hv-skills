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

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
