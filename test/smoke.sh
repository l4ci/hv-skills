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

echo "hv-decisions-index"
mkdir -p .hv
cat > .hv/DECISIONS.md <<'EOF'
# Decisions

## Architecture

### No background queues
Background jobs run in-process.
*Why.* Operational simplicity.
**Forbids.** Adding Sidekiq, RabbitMQ, etc.
**Permits.** In-process Goroutines, threads.

## Testing

### No mocked DB in integration tests
Integration tests must hit a real database.
*Why.* Past mock/prod divergence.
**Forbids.** Mock DB libraries in tests/integration.
**Permits.** Mocks elsewhere.
EOF
"$BIN/hv-decisions-index" >/dev/null
grep -q "<!-- hv-decisions-start -->" CLAUDE.md || fail "hv-decisions managed block not in CLAUDE.md"
grep -q "## Project Decisions" CLAUDE.md || fail "Project Decisions heading missing"
grep -A 20 "<!-- hv-decisions-start -->" CLAUDE.md | grep -q "^- Architecture" || fail "Architecture topic missing in decisions block"
grep -A 20 "<!-- hv-decisions-start -->" CLAUDE.md | grep -q "^- Testing" || fail "Testing topic missing in decisions block"
pass "decisions managed block created with topics"

# Re-running should update in place, not duplicate
"$BIN/hv-decisions-index" >/dev/null
COUNT_DEC=$(grep -c "hv-decisions-start" CLAUDE.md)
[ "$COUNT_DEC" = "1" ] || fail "decisions managed block duplicated"
pass "decisions block updated in place"

# Empty .hv/DECISIONS.md (no topics) — block should still appear with placeholder
cat > .hv/DECISIONS.md <<'EOF'
# Decisions

Hard boundaries for this project.
EOF
"$BIN/hv-decisions-index" >/dev/null
grep -A 10 "<!-- hv-decisions-start -->" CLAUDE.md | grep -q "no decisions yet" || fail "empty-state placeholder missing"
pass "decisions block handles empty file"

echo "hv-skills-index"
# Fresh CLAUDE.md — first run should create the block.
rm -f CLAUDE.md
"$BIN/hv-skills-index" >/dev/null
grep -q "<!-- hv-skills-start -->" CLAUDE.md || fail "hv-skills-index didn't write start marker"
grep -q "<!-- hv-skills-end -->" CLAUDE.md || fail "hv-skills-index didn't write end marker"
grep -q "Capture & pick" CLAUDE.md || fail "hv-skills body missing canonical sections"
grep -q "hv-knowledge-query" CLAUDE.md || fail "hv-skills body missing consult-points"
pass "hv-skills-index creates managed block with canonical body"

# Second run on existing CLAUDE.md with prior content — must update in place,
# not duplicate, and must preserve unrelated content above and below.
cat > CLAUDE.md <<'EOF'
# Project notes

Some pre-existing content.

<!-- hv-skills-start -->
## hv-skills

stale body — should be replaced.
<!-- hv-skills-end -->

Trailing content that must survive.
EOF
"$BIN/hv-skills-index" >/dev/null
[ "$(grep -c '<!-- hv-skills-start -->' CLAUDE.md)" = "1" ] || fail "hv-skills-index duplicated start marker"
grep -q "stale body" CLAUDE.md && fail "hv-skills-index didn't replace stale body"
grep -q "Some pre-existing content" CLAUDE.md || fail "hv-skills-index clobbered pre-block content"
grep -q "Trailing content that must survive" CLAUDE.md || fail "hv-skills-index clobbered post-block content"
grep -q "Capture & pick" CLAUDE.md || fail "hv-skills-index didn't write fresh body on update"
pass "hv-skills-index updates in place and preserves unrelated content"

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

echo "hv-decisions-query"
cat > .hv/DECISIONS.md <<'EOF'
# Decisions

## Architecture

### No background queues
Jobs run in-process.
*Why.* Simplicity.
**Forbids.** External queues.
**Permits.** Goroutines.

## Testing

### No mocked DB
Integration tests hit real DB.
*Why.* Mock divergence.
**Forbids.** Mock DB.
**Permits.** Other mocks.

## Networking
### Strict TLS
Only TLS 1.3+.
*Why.* Compliance.
**Forbids.** TLS 1.2 fallback.
**Permits.** Cert pinning.
EOF
OUT_D=$("$BIN/hv-decisions-query" "Testing" "Networking")
echo "$OUT_D" | grep -q "No mocked DB" || fail "Testing decision missing from query"
echo "$OUT_D" | grep -q "Strict TLS" || fail "Networking decision missing from query"
echo "$OUT_D" | grep -q "No background queues" && fail "Architecture decision leaked into query"
pass "decisions-query returns only requested topics"

# Forbids/permits content must come through verbatim
echo "$OUT_D" | grep -q "Forbids.*Mock DB" || fail "Forbids line missing for Testing decision"
echo "$OUT_D" | grep -q "Permits.*Cert pinning" || fail "Permits line missing for Networking decision"
pass "decisions-query preserves forbids/permits structure"

# Empty/missing file is silent (exit 0, no output)
rm -f .hv/DECISIONS.md
OUT_EMPTY=$("$BIN/hv-decisions-query" "Anything")
[ -z "$OUT_EMPTY" ] || fail "decisions-query should be silent when DECISIONS.md missing"
pass "decisions-query silent when file missing"

# Restore .hv/DECISIONS.md so subsequent tests have a known state
cat > .hv/DECISIONS.md <<'EOF'
# Decisions
EOF

echo "hv-bootstrap (DECISIONS.md seed)"
# Fresh tmpdir so we test bootstrap on a truly clean slate
BOOT_TMP="$(mktemp -d)"
cd "$BOOT_TMP"
git init -q
git config user.email t@t && git config user.name t
"$BIN/hv-bootstrap"
[ -f .hv/DECISIONS.md ] || fail "bootstrap did not create .hv/DECISIONS.md"
grep -q "^# Decisions" .hv/DECISIONS.md || fail "DECISIONS.md missing # Decisions header"
grep -q "Hard boundaries" .hv/DECISIONS.md || fail "DECISIONS.md missing framing sentence"
pass "bootstrap creates .hv/DECISIONS.md with header preamble"

# Re-running bootstrap must NOT overwrite existing DECISIONS.md
echo "user content marker" >> .hv/DECISIONS.md
"$BIN/hv-bootstrap"
grep -q "user content marker" .hv/DECISIONS.md || fail "bootstrap overwrote existing DECISIONS.md"
pass "bootstrap idempotent — preserves existing DECISIONS.md content"

cd "$TMP"
rm -rf "$BOOT_TMP"

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

# Clusters: B11 ↔ F20 (mutual Related). Isolated items must not appear.
echo "$OUT" | grep -q "^### Clusters" || fail "Clusters section missing: $OUT"
echo "$OUT" | grep -qF "[B11] Crash on launch ↔ [F20] Quick-switch" \
  || fail "expected B11↔F20 cluster line: $(echo "$OUT" | awk '/^### Clusters/,0')"
CLUSTER_BLOCK=$(echo "$OUT" | awk '/^### Clusters/,0')
echo "$CLUSTER_BLOCK" | grep -q "B10\|F21\|T30" \
  && fail "isolated item leaked into Clusters: $CLUSTER_BLOCK"
pass "backlog emits Clusters section for related items"

# Triple cluster + isolated item: F22↔F23↔T30 form one component, comma-separated.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B90] [P1] Solo bug.** Desc.

## Features
- **[F90] [Minor] Hub.** Desc. Related: [F91], [T90]
- **[F91] [Minor] Spoke.** Desc. Related: [F90]

## Tasks
- **[T90] Toolchain.** Desc. Related: [F90]

## Completed
EOF
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -qF "[F90] Hub, [F91] Spoke, [T90] Toolchain" \
  || fail "triple cluster not rendered with comma separator: $(echo "$OUT" | awk '/^### Clusters/,0')"
pass "backlog renders 3+ member clusters with comma separator"

# No-cluster fixture: must omit the section entirely.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B95] [P2] Lone bug.** Desc.

## Features

## Tasks

## Completed
EOF
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "^### Clusters" \
  && fail "Clusters section appeared with no related items: $OUT"
pass "backlog omits Clusters section when nothing is related"

# Restore the original fixture for the In-Progress assertions below.
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

# Active items should move to In Progress
"$BIN/hv-status-add" hv/real-branch F20
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "### In Progress" || fail "In Progress section missing"
# F20 should no longer appear in ### Features section
FEAT_BLOCK=$(echo "$OUT" | awk '/^### Features/,/^### Tasks/')
echo "$FEAT_BLOCK" | grep -q "F20" && fail "active F20 leaked into Features table"
pass "active items excluded from Features section"
"$BIN/hv-status-remove" hv/real-branch

echo "hv-refactor-age / hv-complete counter / hv-refactor-reset"
git checkout -q main
# Reset to isolate this section from prior hv-complete calls in the suite.
"$BIN/hv-refactor-reset"
# Seed three active entries, then complete each against a real commit.
cat >> .hv/TODO.md <<'EOF'
- **[F40] Feature done.**
- **[B40] Bug fixed.**
- **[F41] Refactor-driven feature.**
EOF
echo "f1" > f1.txt && git add f1.txt && git commit -q -m "feat: add f1"
"$BIN/hv-complete" F40
echo "b1" > b1.txt && git add b1.txt && git commit -q -m "fix: resolve b1"
"$BIN/hv-complete" B40
echo "r1" > r1.txt && git add r1.txt && git commit -q -m "refactor: clean up"
"$BIN/hv-complete" F41
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 1' || fail "expected 1 non-refactor feature, got: $OUT"
echo "$OUT" | grep -q '"bugs": 1' || fail "expected 1 non-refactor bug, got: $OUT"
pass "refactor-age counts non-refactor completions only"

# Re-completing an already-completed item must not re-bump.
"$BIN/hv-complete" F40
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 1' || fail "idempotent re-completion bumped counter, got: $OUT"
pass "hv-complete is idempotent (no double-bump)"

# hv-refactor-reset zeros the field.
"$BIN/hv-refactor-reset"
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 0' || fail "reset failed, features != 0: $OUT"
echo "$OUT" | grep -q '"bugs": 0' || fail "reset failed, bugs != 0: $OUT"
pass "hv-refactor-reset zeros since_refactor"

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

echo "regression: hv-archive-old only archives canonical completed shape"
FAKE_HASH="abc1234"
OLD_DATE="2024-01-01"
cat > .hv/TODO.md <<EOF
# TODO

## Bugs

## Features

## Tasks

## Completed

- ~~**[B01] Fix login crash.**~~ Done ${OLD_DATE} [\`${FAKE_HASH}\`]
- Note: see issue [B05] which was Done 2024-01-01 by accident.
EOF
COUNT=$("$BIN/hv-archive-old" 1)
[ "$COUNT" = "1" ] || fail "expected 1 item archived, got '$COUNT'"
grep -q "Fix login crash" .hv/ARCHIVE.md || fail "canonical bullet not found in ARCHIVE.md"
grep -q "by accident" .hv/TODO.md || fail "free-form note was wrongly removed from TODO.md"
! grep -q "Fix login crash" .hv/TODO.md || fail "canonical bullet still present in TODO.md"
pass "archive-old only moves canonical completed bullets"

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

# Regression: hv-ship-body must attribute an ID to its OWN bullet, not to
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
git add -A && git commit -q -m "seed ship-body related-link test" || true
git checkout -q -b hv/ship-body-regression
echo r > r2.txt && git add r2.txt && git commit -q -m "fix: badge [B70]"
git checkout -q main
BODY=$("$BIN/hv-ship-body" hv/ship-body-regression)
echo "$BODY" | grep -q "\[B70\] Ship demo bug" || fail "ship-body picked wrong bullet for B70 (Related-link regression): $BODY"
pass "ship-body picks origin bullet, ignores Related-link references"
git checkout -q main
git branch -D hv/ship-body-regression >/dev/null 2>&1 || true
rm -f r2.txt

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

echo "hv-types.sh source contract"
# Source the file in a subshell and assert the exported env vars.
( . "$BIN/hv-types.sh"
  [ "$HV_ITEM_TYPES" = "BFT" ] || { echo "HV_ITEM_TYPES=$HV_ITEM_TYPES"; exit 1; }
  [ "$HV_ALL_PREFIXES" = "BFTM" ] || { echo "HV_ALL_PREFIXES=$HV_ALL_PREFIXES"; exit 1; }
) || fail "hv-types.sh did not export expected values"
pass "hv-types.sh exports HV_ITEM_TYPES=BFT and HV_ALL_PREFIXES=BFTM"

echo "## hv-base-branch + hv-worktree-clear + hv-managed-block + hv-fm-list (refactor)"

# 1. hv-base-branch
BB_TMP="$(mktemp -d)"
(
  cd "$BB_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo seed > seed.txt && git add seed.txt && git commit -q -m "seed"
  OUT=$("$BIN/hv-base-branch")
  [ "$OUT" = "main" ] || { echo "FAIL hv-base-branch: expected 'main', got '$OUT'"; exit 1; }
)
rm -rf "$BB_TMP"
pass "hv-base-branch resolves 'main' in a fresh git repo"

# 1b. hv-base-branch respects git.baseBranch from config
BB2_TMP="$(mktemp -d)"
(
  cd "$BB2_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo seed > seed.txt && git add seed.txt && git commit -q -m "seed"
  git checkout -q -b develop
  echo dev > dev.txt && git add dev.txt && git commit -q -m "dev"
  git checkout -q main
  mkdir -p .hv
  printf '{"git":{"baseBranch":"develop"}}\n' > .hv/config.json
  OUT=$("$BIN/hv-base-branch")
  [ "$OUT" = "develop" ] || { echo "FAIL hv-base-branch config override: expected 'develop', got '$OUT'"; exit 1; }
)
rm -rf "$BB2_TMP"
pass "hv-base-branch respects git.baseBranch config override"

# 2. hv-worktree-clear
WC_TMP="$(mktemp -d)"
(
  cd "$WC_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo seed > seed.txt && git add seed.txt && git commit -q -m "seed"
  "$BIN/hv-worktree-clear" nonexistent-branch
  git checkout -q -b feat-x
  echo wip > wip.txt && git add wip.txt && git commit -q -m "wip"
  git checkout -q main
  WT_PATH="$WC_TMP/wt-feat-x"
  git worktree add "$WT_PATH" feat-x -q
  "$BIN/hv-worktree-clear" feat-x
  git worktree list | grep -q "$WT_PATH" && { echo "FAIL: worktree still present"; exit 1; }
  true
)
rm -rf "$WC_TMP"
pass "hv-worktree-clear silently exits on missing branch; removes non-main worktree"

# 3. hv-managed-block knowledge (flat-list mode)
MB_TMP="$(mktemp -d)"
(
  cd "$MB_TMP"
  git init -q && git config user.email t@t && git config user.name t
  OUT=$("$BIN/hv-managed-block" knowledge)
  [ "$OUT" = "created" ] || { echo "FAIL: expected 'created', got '$OUT'"; exit 1; }
  grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || { echo "FAIL: marker missing"; exit 1; }
  grep -q "no topics yet" CLAUDE.md || { echo "FAIL: empty msg missing"; exit 1; }

  mkdir -p .hv
  printf '# Knowledge\n\n## Build\n- details\n\n## Testing\n- more\n' > .hv/KNOWLEDGE.md
  OUT=$("$BIN/hv-managed-block" knowledge)
  [ "$OUT" = "updated" ] || { echo "FAIL: expected 'updated', got '$OUT'"; exit 1; }
  grep -q "^- Build" CLAUDE.md || { echo "FAIL: Build topic missing"; exit 1; }
  grep -q "^- Testing" CLAUDE.md || { echo "FAIL: Testing topic missing"; exit 1; }

  printf '# Preamble\n\n<!-- hv:knowledge:start -->\n## Project Knowledge\n- OldTopic\n<!-- hv:knowledge:end -->\n\n# Postamble\n' > CLAUDE.md
  "$BIN/hv-managed-block" knowledge >/dev/null
  grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || { echo "FAIL: legacy markers not migrated"; exit 1; }
  grep -q "hv:knowledge:start" CLAUDE.md && { echo "FAIL: legacy colon markers still present"; exit 1; }
  grep -q "^# Preamble" CLAUDE.md || { echo "FAIL: preamble lost"; exit 1; }
)
rm -rf "$MB_TMP"
pass "hv-managed-block knowledge: creates, updates, and migrates legacy markers"

# 4. hv-managed-block decisions --body-stdin
BS_TMP="$(mktemp -d)"
(
  cd "$BS_TMP"
  CUSTOM_BODY="## Project Decisions

Custom intro.

- Topic A"
  OUT=$(printf '%s' "$CUSTOM_BODY" | "$BIN/hv-managed-block" decisions --body-stdin)
  [ "$OUT" = "created" ] || { echo "FAIL: expected 'created', got '$OUT'"; exit 1; }
  grep -q "<!-- hv-decisions-start -->" CLAUDE.md || { echo "FAIL: start marker missing"; exit 1; }
  grep -q "<!-- hv-decisions-end -->" CLAUDE.md || { echo "FAIL: end marker missing"; exit 1; }
  grep -q "Topic A" CLAUDE.md || { echo "FAIL: body content missing"; exit 1; }
)
rm -rf "$BS_TMP"
pass "hv-managed-block decisions --body-stdin writes stdin body wrapped in markers"

# 5. hv-fm-list
FM_TMP="$(mktemp -d)"
(
  mkdir -p "$FM_TMP/docs"
  printf -- '---\nid: X01\ntitle: Alpha\nstatus: active\n---\nBody here.\n' > "$FM_TMP/docs/X01.md"
  printf 'No frontmatter here.\n' > "$FM_TMP/docs/X02.md"
  OUT=$("$BIN/hv-fm-list" "$FM_TMP/docs" id title status)
  echo "$OUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data) == 1, f'expected 1, got {len(data)}: {data}'
assert data[0]['id'] == 'X01', f'id: {data[0][\"id\"]}'
assert data[0]['title'] == 'Alpha', f'title: {data[0][\"title\"]}'
assert data[0]['status'] == 'active', f'status: {data[0][\"status\"]}'
assert '_path' in data[0], '_path missing'
" || { echo "FAIL: fm-list output wrong"; exit 1; }
)
rm -rf "$FM_TMP"
pass "hv-fm-list extracts FM fields, skips files without frontmatter, includes _path"

echo "hv-vision-index heals archived Status line"
# Seed MILESTONES.md with a stale archived line; frontmatter says planned.
# hv-vision-index must overwrite the archived line with planned.
HEAL_TMP="$(mktemp -d)"
(
  cd "$HEAL_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  mkdir -p .hv/milestones
  printf -- '---\nid: M99\ntitle: Foo\nstatus: planned\ndepends: []\n---\nBody.\n' > .hv/milestones/M99.md
  printf '# MILESTONES\n\n## Active milestones\n\n_(none)_\n\n## Milestones\n\n### M99 — Foo\n\n**Status:** archived\n' > .hv/MILESTONES.md
  touch CLAUDE.md
  git add . && git commit -q -m "seed"
  "$BIN/hv-vision-index"
  python3 -c "
import re, sys
ms = open('.hv/MILESTONES.md').read()
m = re.search(r'### M99 — Foo\n\n\*\*Status:\*\* (\w+)', ms)
if not (m and m.group(1) == 'planned'):
    print('heal failed; Status line:', m.group(0) if m else 'not found', file=sys.stderr)
    sys.exit(1)
" || { echo "FAIL: hv-vision-index did not heal archived -> planned"; exit 1; }
)
rm -rf "$HEAL_TMP"
pass "hv-vision-index heals stale 'archived' Status line to match frontmatter"

## hv-fm-list (CRLF tolerance)
CRLF_TMP="$(mktemp -d)"
(
  mkdir -p "$CRLF_TMP/ms"
  python3 -c "
from pathlib import Path
Path('$CRLF_TMP/ms/M01.md').write_bytes(
  b'---\r\nid: M01\r\ntitle: CRLF Milestone\r\nstatus: planned\r\n---\r\nBody.\r\n'
)
"
  OUT=$("$BIN/hv-fm-list" "$CRLF_TMP/ms" id title)
  echo "$OUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data) == 1, f'file skipped (CRLF not tolerated): {data}'
assert data[0]['id'] == 'M01', f'id wrong: {data[0][\"id\"]}'
assert data[0]['title'] == 'CRLF Milestone', f'title wrong: {data[0][\"title\"]}'
" || { echo "FAIL: hv-fm-list skipped CRLF file or extracted garbled values"; exit 1; }
)
rm -rf "$CRLF_TMP"
pass "hv-fm-list parses frontmatter with CRLF line endings"

echo "## hvlib.py (find_section, section, load_json, dump_json_atomic, update_json)"

# 1. find_section finds known section
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import find_section
content = '## A\nbody-a\n\n## B\nbody-b\n'
span = find_section(content, 'A')
assert span is not None, 'find_section returned None'
assert content[span[0]:span[1]].strip() == 'body-a', f'got: {content[span[0]:span[1]]!r}'
" || fail "find_section did not locate known section body"
pass "find_section returns correct (start, end) for known section"

# 2. section returns empty string for missing heading
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import section
result = section('foo', 'Bar')
assert result == '', f'expected empty string, got {result!r}'
" || fail "section did not return '' for missing heading"
pass "section returns '' for missing heading"

# 3. load_json returns default on corrupt file
HVLIB_CORRUPT="$(mktemp)"
printf 'not-json' > "$HVLIB_CORRUPT"
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import load_json
result = load_json('$HVLIB_CORRUPT', {'x': 1})
assert result == {'x': 1}, f'expected default, got {result!r}'
" || fail "load_json did not return default on corrupt file"
rm -f "$HVLIB_CORRUPT"
pass "load_json returns default on corrupt file"

# 4. dump_json_atomic writes pretty JSON with trailing newline; no .tmp leftover
HVLIB_ATOMIC="$(mktemp -d)"
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import dump_json_atomic
import os
path = '$HVLIB_ATOMIC/out.json'
dump_json_atomic(path, {'k': 'v'})
content = open(path).read()
assert content == '{' + chr(10) + '  \"k\": \"v\"' + chr(10) + '}' + chr(10), f'got: {content!r}'
assert not os.path.exists(path + '.tmp'), '.tmp file was not cleaned up'
" || fail "dump_json_atomic did not write expected content or left .tmp"
rm -rf "$HVLIB_ATOMIC"
pass "dump_json_atomic writes indent=2 JSON with trailing newline; no .tmp leftover"

# 5. write_text_atomic writes text and cleans up .tmp
HVLIB_TXT="$(mktemp -d)"
python3 -c "
import sys, os; sys.path.insert(0, '$REPO/bin')
from hvlib import write_text_atomic
path = '$HVLIB_TXT/out.md'
write_text_atomic(path, '# Header\n')
content = open(path).read()
assert content == '# Header' + chr(10), f'got: {content!r}'
assert not os.path.exists(path + '.tmp'), '.tmp file was not cleaned up'
" || fail "write_text_atomic did not write expected content or left .tmp"
rm -rf "$HVLIB_TXT"
pass "write_text_atomic writes text atomically; no .tmp leftover"

# 6. update_json mutates and atomically writes
HVLIB_UPDATE="$(mktemp -d)"
python3 -c "
import sys, json; sys.path.insert(0, '$REPO/bin')
from hvlib import dump_json_atomic, update_json
path = '$HVLIB_UPDATE/data.json'
dump_json_atomic(path, {'n': 1})
update_json(path, {}, lambda data: data.update({'n': 2}) or None)
result = json.loads(open(path).read())
assert result == {'n': 2}, f'expected n=2, got {result!r}'
" || fail "update_json did not mutate and write correctly"
rm -rf "$HVLIB_UPDATE"
pass "update_json mutates in place and atomically writes result"

# 7. find_origin_bullet returns origin bullet, ignores Related: references
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import find_origin_bullet
corpus = '- **[F80] [Minor] Refers to B70.** Something. Related: [B70]\n- ~~**[B70] [P1] Real bug.** Description.~~ Done 2026-04-10 [\`abc1234\`]\n'
result = find_origin_bullet(corpus, 'B70')
assert result is not None, 'find_origin_bullet returned None for known ID'
line, title = result
assert title == 'Real bug', f'expected title \"Real bug\", got {title!r}'
assert 'Done' not in line, f'Done suffix not stripped: {line!r}'
assert '~~' not in line, f'strikethrough not unwrapped: {line!r}'
" || fail "find_origin_bullet did not return correct origin bullet"
pass "find_origin_bullet picks origin bullet over Related-link reference"

# 8. parse_todo_fields is order-agnostic
python3 -c "
import sys; sys.path.insert(0, '$REPO/bin')
from hvlib import parse_todo_fields
# Order: Detail, Related, Milestone
r = parse_todo_fields('Body. Detail: alpha. Related: [F02]. Milestone: M01')
assert r['detail'] == 'alpha.', f'detail wrong: {r}'
assert r['related'] == '[F02].', f'related wrong: {r}'
assert r['milestone'] == 'M01', f'milestone wrong: {r}'
# Order: Milestone, Related, Detail (reversed)
r = parse_todo_fields('Body. Milestone: M01 Related: [F02] Detail: alpha')
assert r['detail'] == 'alpha', f'detail wrong reversed: {r}'
assert r['related'] == '[F02]', f'related wrong reversed: {r}'
assert r['milestone'] == 'M01', f'milestone wrong reversed: {r}'
" || fail "parse_todo_fields not order-agnostic"
pass "parse_todo_fields extracts Detail/Related/Milestone in any order"

echo "hv-release-detect-version"
# Case 1: .claude-plugin/plugin.json (priority candidate)
DV1="$(mktemp -d)"
(
  cd "$DV1"
  mkdir -p .claude-plugin
  printf '{"version":"1.0.0"}\n' > .claude-plugin/plugin.json
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"version": "1.0.0"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"kind": "plugin-json"' || { echo "FAIL: kind wrong: $OUT"; exit 1; }
)
pass "hv-release-detect-version detects plugin.json"

# Case 2: config override via .hv/config.json
(
  cd "$DV1"
  mkdir -p .hv
  printf '{"release":{"versionFile":"package.json"}}\n' > .hv/config.json
  printf '{"version":"2.5.0"}\n' > package.json
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"file": "package.json"' || { echo "FAIL: file wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"version": "2.5.0"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
)
pass "hv-release-detect-version respects release.versionFile config override"
rm -rf "$DV1"

# Case 3: pyproject.toml
DV2="$(mktemp -d)"
(
  cd "$DV2"
  printf '[project]\nversion = "0.1.2"\n' > pyproject.toml
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"kind": "pyproject"' || { echo "FAIL: kind wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"version": "0.1.2"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
)
rm -rf "$DV2"
pass "hv-release-detect-version detects pyproject.toml"

# Case 4: Cargo.toml
DV3="$(mktemp -d)"
(
  cd "$DV3"
  printf '[package]\nversion = "3.4.5"\n' > Cargo.toml
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"kind": "cargo"' || { echo "FAIL: kind wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"version": "3.4.5"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
)
rm -rf "$DV3"
pass "hv-release-detect-version detects Cargo.toml"

# Case 5: plain VERSION file
DV4="$(mktemp -d)"
(
  cd "$DV4"
  printf '9.9.9\n' > VERSION
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"kind": "plain"' || { echo "FAIL: kind wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"version": "9.9.9"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
)
rm -rf "$DV4"
pass "hv-release-detect-version detects plain VERSION file"

# Case 6: no version files → exit non-zero + stderr message
DV5="$(mktemp -d)"
(
  cd "$DV5"
  rc=0
  ERR=$("$BIN/hv-release-detect-version" 2>&1 >/dev/null) || rc=$?
  [ "$rc" != "0" ] || { echo "FAIL: expected non-zero exit, got 0"; exit 1; }
  echo "$ERR" | grep -q "no version file detected" || { echo "FAIL: stderr missing expected message: $ERR"; exit 1; }
)
rm -rf "$DV5"
pass "hv-release-detect-version exits non-zero with no version files"

echo "hv-release-bump-version"
# Case 1: package.json patch bump
BV1="$(mktemp -d)"
(
  cd "$BV1"
  printf '{"version":"1.0.0"}\n' > package.json
  NEW=$("$BIN/hv-release-bump-version" package.json package-json patch)
  [ "$NEW" = "1.0.1" ] || { echo "FAIL: expected 1.0.1, got $NEW"; exit 1; }
  grep -q '"version": "1.0.1"' package.json || { echo "FAIL: file not updated"; exit 1; }
)
pass "hv-release-bump-version bumps package.json patch"

# Case 2: minor and major bumps
(
  cd "$BV1"
  NEW=$("$BIN/hv-release-bump-version" package.json package-json minor)
  [ "$NEW" = "1.1.0" ] || { echo "FAIL: expected 1.1.0, got $NEW"; exit 1; }
  NEW=$("$BIN/hv-release-bump-version" package.json package-json major)
  [ "$NEW" = "2.0.0" ] || { echo "FAIL: expected 2.0.0, got $NEW"; exit 1; }
)
pass "hv-release-bump-version bumps minor and major"

# Case 3: explicit version bump; reject lower version
(
  cd "$BV1"
  NEW=$("$BIN/hv-release-bump-version" package.json package-json 5.0.0)
  [ "$NEW" = "5.0.0" ] || { echo "FAIL: expected 5.0.0, got $NEW"; exit 1; }
  rc=0
  ERR=$("$BIN/hv-release-bump-version" package.json package-json 1.0.0 2>&1 >/dev/null) || rc=$?
  [ "$rc" != "0" ] || { echo "FAIL: expected non-zero exit for lower version"; exit 1; }
  echo "$ERR" | grep -q "strictly greater" || { echo "FAIL: stderr missing 'strictly greater': $ERR"; exit 1; }
)
rm -rf "$BV1"
pass "hv-release-bump-version explicit version: allows higher, rejects lower"

# Case 4: pyproject.toml — only bumps [project] version, not [tool.foo]
BV2="$(mktemp -d)"
(
  cd "$BV2"
  printf '[project]\nversion = "0.1.0"\nname = "x"\n\n[tool.foo]\nversion = "9.9.9"\n' > pyproject.toml
  NEW=$("$BIN/hv-release-bump-version" pyproject.toml pyproject patch)
  [ "$NEW" = "0.1.1" ] || { echo "FAIL: expected 0.1.1, got $NEW"; exit 1; }
  grep -q 'version = "0.1.1"' pyproject.toml || { echo "FAIL: [project] version not updated"; exit 1; }
  grep -q 'version = "9.9.9"' pyproject.toml || { echo "FAIL: [tool.foo] version was modified"; exit 1; }
)
rm -rf "$BV2"
pass "hv-release-bump-version bumps only [project] in pyproject.toml"

# Case 5: Cargo.toml major bump
BV3="$(mktemp -d)"
(
  cd "$BV3"
  printf '[package]\nversion = "1.2.3"\n' > Cargo.toml
  NEW=$("$BIN/hv-release-bump-version" Cargo.toml cargo major)
  [ "$NEW" = "2.0.0" ] || { echo "FAIL: expected 2.0.0, got $NEW"; exit 1; }
)
rm -rf "$BV3"
pass "hv-release-bump-version bumps Cargo.toml major"

# Case 6: plain VERSION file minor bump
BV4="$(mktemp -d)"
(
  cd "$BV4"
  printf '0.0.1\n' > VERSION
  NEW=$("$BIN/hv-release-bump-version" VERSION plain minor)
  [ "$NEW" = "0.1.0" ] || { echo "FAIL: expected 0.1.0, got $NEW"; exit 1; }
  CONTENT=$(cat VERSION)
  [ "$CONTENT" = "0.1.0" ] || { echo "FAIL: plain file content wrong: '$CONTENT'"; exit 1; }
)
rm -rf "$BV4"
pass "hv-release-bump-version bumps plain VERSION file"

echo "hv-release-changelog-from-commits"
CL1="$(mktemp -d)"
(
  cd "$CL1"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  # Seed an initial empty commit so HEAD~N anchors work reliably
  git commit --allow-empty -q -m "chore: init"
  git tag v_cl1_base
  git commit --allow-empty -q -m "feat: new widget"
  git commit --allow-empty -q -m "fix: null pointer"
  git commit --allow-empty -q -m "refactor: clean up internals"
  git commit --allow-empty -q -m "chore: bump deps"
  git commit --allow-empty -q -m "docs: update readme"
  git commit --allow-empty -q -m "test: add unit test"
  git commit --allow-empty -q -m "perf: speed up parser"
  git commit --allow-empty -q -m "plain commit no prefix"

  OUT=$("$BIN/hv-release-changelog-from-commits" v_cl1_base..HEAD)
  echo "$OUT" | grep -q "^## New" || { echo "FAIL: ## New missing"; exit 1; }
  echo "$OUT" | grep -q "^## Fixed" || { echo "FAIL: ## Fixed missing"; exit 1; }
  echo "$OUT" | grep -q "^## Performance" || { echo "FAIL: ## Performance missing"; exit 1; }
  echo "$OUT" | grep -q "^## Changed" || { echo "FAIL: ## Changed missing"; exit 1; }
  echo "$OUT" | grep -q "^## Documentation" || { echo "FAIL: ## Documentation missing"; exit 1; }
  echo "$OUT" | grep -q "^## Other" || { echo "FAIL: ## Other missing"; exit 1; }
  echo "$OUT" | grep -q "^## Stats" || { echo "FAIL: ## Stats missing"; exit 1; }
  if echo "$OUT" | grep -qx "^## Test"; then echo "FAIL: ## Test heading should be absent"; exit 1; fi
)
pass "hv-release-changelog-from-commits emits expected sections, skips test commits"

# Breaking change detection
(
  cd "$CL1"
  git commit --allow-empty -q -m "feat: breaking change" -m "BREAKING CHANGE: api removed"
  OUT=$("$BIN/hv-release-changelog-from-commits" v_cl1_base..HEAD)
  echo "$OUT" | grep -q "^## Breaking" || { echo "FAIL: ## Breaking missing"; exit 1; }
)
pass "hv-release-changelog-from-commits emits ## Breaking for BREAKING CHANGE body"

# Empty range → exit 0, empty stdout, stderr message
(
  cd "$CL1"
  git tag v_cl1_tip
  rc=0
  OUT=$("$BIN/hv-release-changelog-from-commits" "v_cl1_tip..v_cl1_tip" 2>/tmp/cl1_err) || rc=$?
  [ "$rc" = "0" ] || { echo "FAIL: expected exit 0 on empty range, got $rc"; exit 1; }
  [ -z "$OUT" ] || { echo "FAIL: expected empty stdout, got: $OUT"; exit 1; }
  grep -q "no commits in range" /tmp/cl1_err || { echo "FAIL: stderr missing 'no commits in range': $(cat /tmp/cl1_err)"; exit 1; }
)
rm -f /tmp/cl1_err
rm -rf "$CL1"
pass "hv-release-changelog-from-commits exits 0 with empty stdout on empty range"

echo "hv-release-update-changelog"
UC1="$(mktemp -d)"
TODAY=$(date +%Y-%m-%d)
(
  cd "$UC1"
  printf '## Highlights\n\n- thing 1\n' > notes.md
  "$BIN/hv-release-update-changelog" 1.0.0 notes.md
  [ -f CHANGELOG.md ] || { echo "FAIL: CHANGELOG.md not created"; exit 1; }
  head -1 CHANGELOG.md | grep -q "^# Changelog" || { echo "FAIL: missing # Changelog header"; exit 1; }
  grep -q "^## v1.0.0 — $TODAY" CHANGELOG.md || { echo "FAIL: missing v1.0.0 section with today's date"; exit 1; }
)
pass "hv-release-update-changelog creates CHANGELOG.md with correct header and date"

# Second version appears above first
(
  cd "$UC1"
  printf '## Notes\n\n- thing 2\n' > notes2.md
  "$BIN/hv-release-update-changelog" 1.1.0 notes2.md
  LINE110=$(grep -n "^## v1.1.0" CHANGELOG.md | cut -d: -f1)
  LINE100=$(grep -n "^## v1.0.0" CHANGELOG.md | cut -d: -f1)
  [ "$LINE110" -lt "$LINE100" ] || { echo "FAIL: v1.1.0 ($LINE110) not above v1.0.0 ($LINE100)"; exit 1; }
)
pass "hv-release-update-changelog prepends newer version above older one"

# Duplicate version → exit 1 with stderr message
(
  cd "$UC1"
  rc=0
  ERR=$("$BIN/hv-release-update-changelog" 1.1.0 notes.md 2>&1 >/dev/null) || rc=$?
  [ "$rc" != "0" ] || { echo "FAIL: expected non-zero exit for duplicate version"; exit 1; }
  echo "$ERR" | grep -q "already has a section for v1.1.0" || { echo "FAIL: stderr missing expected message: $ERR"; exit 1; }
)
pass "hv-release-update-changelog rejects duplicate version"

# --path flag
(
  cd "$UC1"
  mkdir -p docs
  "$BIN/hv-release-update-changelog" 0.0.1 notes.md --path docs/CHANGELOG.md
  [ -f docs/CHANGELOG.md ] || { echo "FAIL: docs/CHANGELOG.md not created"; exit 1; }
)
pass "hv-release-update-changelog --path writes to custom path"

# Invalid version → exit 1
(
  cd "$UC1"
  rc=0
  "$BIN/hv-release-update-changelog" 1.0 notes.md 2>/dev/null || rc=$?
  [ "$rc" != "0" ] || { echo "FAIL: expected non-zero exit for invalid version '1.0'"; exit 1; }
)
rm -rf "$UC1"
pass "hv-release-update-changelog rejects invalid version format"

echo "hv-release-detect-host"
DH1="$(mktemp -d)"
(
  cd "$DH1"
  git init -q
  git config user.email t@t && git config user.name t

  # No origin → none
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "none" ] || { echo "FAIL: expected 'none' with no origin, got '$OUT'"; exit 1; }
)
pass "hv-release-detect-host returns none with no origin"

(
  cd "$DH1"
  # SSH github.com → github
  git remote add origin git@github.com:foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "github" ] || { echo "FAIL: expected 'github' for git@github.com, got '$OUT'"; exit 1; }

  # HTTPS github.com → github
  git remote set-url origin https://github.com/foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "github" ] || { echo "FAIL: expected 'github' for https://github.com, got '$OUT'"; exit 1; }

  # gitlab.com → gitlab
  git remote set-url origin git@gitlab.com:foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "gitlab" ] || { echo "FAIL: expected 'gitlab', got '$OUT'"; exit 1; }

  # self-hosted gitlab → gitlab-self-hosted
  git remote set-url origin https://gitlab.example.com/foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "gitlab-self-hosted" ] || { echo "FAIL: expected 'gitlab-self-hosted', got '$OUT'"; exit 1; }

  # GitHub Enterprise → github-enterprise
  git remote set-url origin https://github.example.com/foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "github-enterprise" ] || { echo "FAIL: expected 'github-enterprise', got '$OUT'"; exit 1; }

  # Bitbucket (unrecognised) → none
  git remote set-url origin https://bitbucket.org/foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "none" ] || { echo "FAIL: expected 'none' for bitbucket.org, got '$OUT'"; exit 1; }
)
rm -rf "$DH1"
pass "hv-release-detect-host classifies github/gitlab/github-enterprise/gitlab-self-hosted/none"

echo "umbrella mode (T1-T4)"

# Build a synthetic umbrella with 3 independent git repos (NO submodules)
UMB="$TMP/umbrella"
mkdir -p "$UMB"/{web,api,shared} "$UMB/.hv"
for r in web api shared; do
  (cd "$UMB/$r" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init)
done

# T4: bootstrap seeds repos.json
SEEDED=$(mktemp -d)
(cd "$SEEDED" && bash "$BIN/hv-bootstrap" >/dev/null)
[ -f "$SEEDED/.hv/repos.json" ] || fail "hv-bootstrap did not seed .hv/repos.json"
python3 -c "import json; d=json.load(open('$SEEDED/.hv/repos.json')); assert d == {'repos':[]}, d" || fail "repos.json schema wrong"
pass "T4: hv-bootstrap seeds .hv/repos.json with {\"repos\":[]}"
rm -rf "$SEEDED"

# T3: hv-umbrella-init scans children and writes registry
echo "web,api" | (cd "$UMB" && "$BIN/hv-umbrella-init" >/dev/null)
python3 -c "import json; d=json.load(open('$UMB/.hv/repos.json')); names=sorted(r['name'] for r in d['repos']); assert names==['api','web'], names" || fail "registry schema wrong"
pass "T3: hv-umbrella-init writes sorted registry"

# T3: idempotent re-run
SHA_BEFORE=$(sha256sum "$UMB/.hv/repos.json" | cut -d' ' -f1)
echo "web,api" | (cd "$UMB" && "$BIN/hv-umbrella-init" >/dev/null)
SHA_AFTER=$(sha256sum "$UMB/.hv/repos.json" | cut -d' ' -f1)
[ "$SHA_BEFORE" = "$SHA_AFTER" ] || fail "hv-umbrella-init not idempotent"
pass "T3: hv-umbrella-init idempotent on repeat run"

# T3: empty children dir exits 1
EMPTY="$TMP/empty-umbrella" && mkdir -p "$EMPTY/.hv"
if (cd "$EMPTY" && "$BIN/hv-umbrella-init" <<<"" >/dev/null 2>&1); then
  fail "hv-umbrella-init should exit 1 on empty children"
fi
pass "T3: hv-umbrella-init exits 1 on empty children dir"

# T1: walk-up from various positions
[ "$(cd "$UMB" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from umbrella root"
[ "$(cd "$UMB/web" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from sub-repo"
mkdir -p "$UMB/web/src/components/deep"
[ "$(cd "$UMB/web/src/components/deep" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from deep nested"
pass "T1: hv-resolve-umbrella walks up correctly (3 cwd cases)"

# T1: not found
if (cd /tmp && "$BIN/hv-resolve-umbrella" >/dev/null 2>&1); then
  fail "hv-resolve-umbrella should exit 1 in /tmp"
fi
pass "T1: hv-resolve-umbrella exits 1 when no .hv/ above cwd"

# T1: symlink — pwd -P matters
ln -sfn "$UMB/web" "$TMP/symlink-web"
[ "$(cd "$TMP/symlink-web/src/components/deep" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up via symlink"
rm -f "$TMP/symlink-web"
pass "T1: hv-resolve-umbrella handles symlinked sub-repo paths"

# T1: masking — stray .hv/ inside a registered sub-repo
mkdir -p "$UMB/web/.hv"
if (cd "$UMB/web/src" 2>/dev/null && "$BIN/hv-resolve-umbrella" 2>&1 1>/dev/null) | grep -q "masking"; then
  pass "T1: hv-resolve-umbrella detects masking with stderr message"
else
  # stderr may not flow through subshell — check exit code instead
  EC=0
  (cd "$UMB/web" && "$BIN/hv-resolve-umbrella" >/dev/null 2>/dev/null) || EC=$?
  [ "$EC" = "2" ] || fail "masking should exit 2, got $EC"
  pass "T1: hv-resolve-umbrella detects masking (exit 2)"
fi
rmdir "$UMB/web/.hv"

# T2: hv-resolve-repo from sub-repo
[ "$(cd "$UMB/web" && "$BIN/hv-resolve-repo")" = "web" ] || fail "resolve-repo from web root"
[ "$(cd "$UMB/api" && "$BIN/hv-resolve-repo")" = "api" ] || fail "resolve-repo from api root"
pass "T2: hv-resolve-repo identifies registered sub-repo"

# T2: deep dir
[ "$(cd "$UMB/web/src/components/deep" && "$BIN/hv-resolve-repo")" = "web" ] || fail "resolve-repo from deep dir"
pass "T2: hv-resolve-repo works from sub-repo deep dir"

# T2: unregistered sub-repo (shared was not registered)
if (cd "$UMB/shared" && "$BIN/hv-resolve-repo" >/dev/null 2>&1); then
  fail "resolve-repo should exit 1 for shared (not registered)"
fi
pass "T2: hv-resolve-repo exits 1 for unregistered sub-repo"

# T2: cwd outside any sub-repo
if (cd "$UMB" && "$BIN/hv-resolve-repo" >/dev/null 2>&1); then
  fail "resolve-repo should exit 1 from umbrella root"
fi
pass "T2: hv-resolve-repo exits 1 outside any sub-repo's git"

# T1+T2: composition from Layout B worktree
(cd "$UMB/web" && git worktree add "$UMB/.claude/worktrees/web/feat-x" -b hv/feat-x >/dev/null 2>&1)
WT="$UMB/.claude/worktrees/web/feat-x"
[ "$(cd "$WT" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from Layout B worktree"
[ "$(cd "$WT" && "$BIN/hv-resolve-repo")" = "web" ] || fail "resolve-repo from Layout B worktree"
pass "T1+T2: composition from Layout B worktree path"
(cd "$UMB/web" && git worktree remove "$WT" >/dev/null 2>&1; git branch -D hv/feat-x >/dev/null 2>&1) || true

# Single-repo backwards compat — existing fixtures must still pass.
# This block runs in the parent $TMP (the original single-repo test fixture);
# verify hv-resolve-umbrella still works there with no umbrella in scope.
[ "$(cd "$TMP" && "$BIN/hv-resolve-umbrella")" = "$TMP" ] || fail "single-repo cwd still resolves to its own .hv/"
pass "single-repo backward compat: hv-resolve-umbrella still works"

echo "umbrella mode S02 (--repo flags + reconcile + worktree-clear)"

echo '{"active":[]}' > "$UMB/.hv/status.json"
echo "web,api" | (cd "$UMB" && "$BIN/hv-umbrella-init" >/dev/null)

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" hv/x B01)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
assert d['active'][0]['repo'] is None, d
assert d['active'][0]['branch'] == 'hv/x'
"
pass "T1: hv-status-add (no --repo) writes repo: null"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" --repo web hv/x B01)
(cd "$UMB" && "$BIN/hv-status-add" --repo api hv/x B02)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['branch'], e['repo']) for e in d['active'])
assert pairs == [('hv/x', 'api'), ('hv/x', 'web')], pairs
"
pass "T1: hv-status-add (--repo web) and (--repo api) coexist on same branch"

(cd "$UMB" && "$BIN/hv-status-add" --if-absent --repo web hv/x B01)
COUNT=$(python3 -c "import json; print(len(json.load(open('$UMB/.hv/status.json'))['active']))")
[ "$COUNT" = "2" ] || fail "if-absent should be no-op for existing (branch, repo); got count $COUNT"
pass "T1: hv-status-add --if-absent --repo respects (branch, repo) uniqueness"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" --repo web --if-absent hv/y B01)
(cd "$UMB" && "$BIN/hv-status-add" --if-absent --repo api hv/y B02)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['branch'], e['repo']) for e in d['active'])
assert pairs == [('hv/y', 'api'), ('hv/y', 'web')], pairs
"
pass "T1: hv-status-add accepts --repo and --if-absent in either order"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" hv/z B01)
(cd "$UMB" && "$BIN/hv-status-add" --repo web hv/z B02)
(cd "$UMB" && "$BIN/hv-status-remove" hv/z)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = [(e['branch'], e['repo']) for e in d['active']]
assert pairs == [('hv/z', 'web')], pairs
"
pass "T1: hv-status-remove (no --repo) preserves umbrella entries"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" --repo web hv/z B01)
(cd "$UMB" && "$BIN/hv-status-add" --repo api hv/z B02)
(cd "$UMB" && "$BIN/hv-status-remove" --repo web hv/z)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = [(e['branch'], e['repo']) for e in d['active']]
assert pairs == [('hv/z', 'api')], pairs
"
pass "T1: hv-status-remove --repo web only removes web entry"

(cd "$UMB/web" && git checkout -q -b hv/feat-merge && echo "x" > x.txt && git add x.txt && git -c user.email=t@t -c user.name=t commit -q -m "feat: x")
WEB_HEAD_BEFORE=$(cd "$UMB/web" && git -c init.defaultBranch=main rev-parse main)
(cd "$UMB" && printf 'merge: feat-merge\n\n- added x\n' | "$BIN/hv-merge" --repo web hv/feat-merge >/dev/null)
WEB_HEAD_AFTER=$(cd "$UMB/web" && git rev-parse main)
[ "$WEB_HEAD_BEFORE" != "$WEB_HEAD_AFTER" ] || fail "hv-merge --repo web did not advance web/main"
if (cd "$UMB/web" && git rev-parse --verify hv/feat-merge >/dev/null 2>&1); then
  fail "hv-merge --repo web did not delete the feature branch"
fi
[ ! -d "$UMB/.git" ] || fail "hv-merge --repo web should NOT create umbrella .git/"
pass "T2: hv-merge --repo web lands the merge in web/.git/, not umbrella"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB/web" && git checkout -q main && git branch hv/recon-live 2>/dev/null || true)
(cd "$UMB" && "$BIN/hv-status-add" --repo web hv/recon-live B01)
(cd "$UMB" && "$BIN/hv-status-add" --repo api hv/recon-dead B02)
OUT=$(cd "$UMB" && "$BIN/hv-reconcile")
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
na = d['needsAction']
cl = d['cleaned']
assert any(e['branch'] == 'hv/recon-live' and e.get('repo') == 'web' for e in na), na
assert any(e['branch'] == 'hv/recon-dead' and e.get('repo') == 'api' for e in cl), cl
"
pass "T3: hv-reconcile output entries carry repo field"

(cd "$UMB" && "$BIN/hv-status-add" --repo nonexistent hv/recon-x B03)
OUT=$(cd "$UMB" && "$BIN/hv-reconcile")
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
cl = d['cleaned']
assert any(e.get('reason') == 'repo_unregistered' and e.get('repo') == 'nonexistent' for e in cl), cl
"
pass "T3: hv-reconcile flags entries pointing at unregistered repos"

(cd "$UMB/web" && git checkout -q main && git branch hv/wt-x 2>/dev/null || true)
mkdir -p "$UMB/.claude/worktrees/web"
(cd "$UMB/web" && git worktree add "$UMB/.claude/worktrees/web/hv-wt-x" hv/wt-x >/dev/null 2>&1)
[ -d "$UMB/.claude/worktrees/web/hv-wt-x" ] || fail "Layout B worktree setup failed"
(cd "$UMB/web" && "$BIN/hv-worktree-clear" --repo web hv/wt-x)
[ ! -d "$UMB/.claude/worktrees/web/hv-wt-x" ] || fail "Layout B worktree was not cleaned up"
pass "T4: hv-worktree-clear --repo web removes Layout B worktree"
(cd "$UMB/web" && git branch -D hv/wt-x >/dev/null 2>&1) || true

OUT=$(cd "$TMP" && "$BIN/hv-reconcile")
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert 'cleaned' in d and 'needsAction' in d
for e in d['needsAction']:
    assert e.get('repo') in (None, ''), e
"
pass "single-repo backward compat: hv-reconcile schema unchanged"

cp "$TMP/.hv/status.json" "$TMP/.hv/status.json.bak"
echo '{"active":[]}' > "$TMP/.hv/status.json"
(cd "$TMP" && "$BIN/hv-status-add" hv/legacy L01)
python3 -c "
import json; d=json.load(open('$TMP/.hv/status.json'))
e = d['active'][0]
assert e['branch'] == 'hv/legacy' and e['repo'] is None, e
"
(cd "$TMP" && "$BIN/hv-status-remove" hv/legacy)
python3 -c "
import json; d=json.load(open('$TMP/.hv/status.json'))
assert d['active'] == [], d
"
mv "$TMP/.hv/status.json.bak" "$TMP/.hv/status.json"
pass "single-repo backward compat: hv-status-add and hv-status-remove without flags"

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
