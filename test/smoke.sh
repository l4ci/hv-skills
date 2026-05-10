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

# todoDrift field is always present (empty when no drift)
echo "$OUTPUT" | grep -q '"todoDrift"' || fail "reconcile output missing todoDrift field"
pass "reconcile emits todoDrift field"

echo "hv-todo-drift"
TD_TMP="$(mktemp -d)"
(
  cd "$TD_TMP"
  mkdir -p .hv/bin
  cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B07] [P1] Pretend bug.** Desc.

## Features

## Tasks

## Completed
EOF
  echo '{"repos": []}' > .hv/repos.json
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  git commit -q --allow-empty -m "fix: do thing [B07]"
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
  OUT=$(.hv/bin/hv-todo-drift)
  echo "$OUT" | grep -q '"id": "B07"' || fail "drift missing B07: $OUT"
  pass "hv-todo-drift detects shipped-but-open ID"

  # Completed (strikethrough) IDs are NOT drift — even if they appear in commits.
  cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B07] [P1] Pretend bug.**~~ Done 2026-05-07 [`abc1234`]
EOF
  OUT2=$(.hv/bin/hv-todo-drift)
  if echo "$OUT2" | grep -q '"id": "B07"'; then
    fail "drift should not flag completed B07: $OUT2"
  fi
  pass "hv-todo-drift ignores completed IDs"
)
rm -rf "$TD_TMP"

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

echo "hv-knowledge-stats"
KS_TMP="$(mktemp -d)"
(
  cd "$KS_TMP"
  mkdir -p .hv
  cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Tiny

- one bullet

## Big

EOF
  # Append 30 bullets to ## Big so it crosses the threshold.
  for i in $(seq 1 30); do echo "- bullet $i" >> .hv/KNOWLEDGE.md; done
  mkdir -p .hv/bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
  OUT=$(.hv/bin/hv-knowledge-stats)
  echo "$OUT" | grep -q '"name": "Tiny"' || fail "stats missing Tiny: $OUT"
  echo "$OUT" | grep -q '"name": "Big"' || fail "stats missing Big: $OUT"
  BIG_BULLETS=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(t['bullets'] for t in d['topics'] if t['name']=='Big'))")
  [ "$BIG_BULLETS" = "30" ] || fail "Big bullet count != 30: $BIG_BULLETS"
  pass "hv-knowledge-stats counts bullets per topic"
  TINY_BULLETS=$(echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(t['bullets'] for t in d['topics'] if t['name']=='Tiny'))")
  [ "$TINY_BULLETS" = "1" ] || fail "Tiny bullet count != 1: $TINY_BULLETS"
  pass "hv-knowledge-stats handles tiny topics"
)
rm -rf "$KS_TMP"

echo "hv-knowledge-stats no KNOWLEDGE.md"
KS2_TMP="$(mktemp -d)"
(
  cd "$KS2_TMP"
  mkdir -p .hv/bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
  OUT=$(.hv/bin/hv-knowledge-stats)
  echo "$OUT" | grep -q '"topics": \[\]' || fail "missing-file should yield empty: $OUT"
  pass "hv-knowledge-stats silent-empty on missing KNOWLEDGE.md"
)
rm -rf "$KS2_TMP"

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

echo "hv-backlog --grep matches"
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B70] [P1] Database connection drops after timeout.** Network glitch handler.

## Features
- **[F70] [Cosmetic] Add loading spinner to dashboard.** Cosmetic UX polish.
- **[F71] [Minor] Implement export to CSV.** Need a button on the dashboard view.

## Tasks

## Completed
EOF
echo '{"active":[]}' > .hv/status.json

OUT=$("$BIN/hv-backlog" --grep dashboard)
echo "$OUT" | grep -q "F70" || fail "F70 (matches 'dashboard') missing: $OUT"
echo "$OUT" | grep -q "F71" || fail "F71 (matches 'dashboard') missing: $OUT"
echo "$OUT" | grep -q "B70" && fail "B70 (no match) leaked: $OUT"
pass "hv-backlog --grep filters by title/description substring"

echo "hv-backlog --grep case-insensitive"
OUT=$("$BIN/hv-backlog" --grep DASHBOARD)
echo "$OUT" | grep -q "F70" || fail "case-insensitive 'DASHBOARD' should match: $OUT"
pass "hv-backlog --grep is case-insensitive"

echo "hv-backlog --grep matches ID"
OUT=$("$BIN/hv-backlog" --grep B70)
echo "$OUT" | grep -q "B70" || fail "ID match B70 missing: $OUT"
echo "$OUT" | grep -q "F70" && fail "F70 leaked when grepping B70: $OUT"
pass "hv-backlog --grep matches by ID"

echo "hv-backlog --grep no matches"
OUT=$("$BIN/hv-backlog" --grep nonexistent_xyz)
echo "$OUT" | grep -q "No matches for pattern 'nonexistent_xyz'" || fail "expected 'No matches' message: $OUT"
echo "$OUT" | grep -q "### Bugs" && fail "Bugs section should be empty/absent on no-match: $OUT"
pass "hv-backlog --grep with no matches prints 'No matches' message"

echo "hv-backlog --grep cluster"
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features
- **[F80] [Minor] Auth refactor.** Wire OAuth. Related: [F81]
- **[F81] [Minor] Token rotation.** Refresh JWT. Related: [F80]
- **[F82] [Cosmetic] Unrelated thing.** Standalone.

## Tasks

## Completed
EOF
OUT=$("$BIN/hv-backlog" --grep "Auth refactor")
echo "$OUT" | grep -q "F80" || fail "F80 missing in filtered output: $OUT"
# Cluster section should show F80 ↔ F81 (both members, even though only F80 matched)
echo "$OUT" | grep -qE "F80.*F81|F81.*F80" || fail "cluster should preserve both members: $OUT"
echo "$OUT" | grep -q "F82" && fail "F82 (no match) should not appear: $OUT"
pass "hv-backlog --grep filters clusters but preserves all members"

echo "hv-backlog no-flag regression"
OUT_FILTERED=$("$BIN/hv-backlog" --grep "")
OUT_PLAIN=$("$BIN/hv-backlog")
[ "$OUT_FILTERED" = "$OUT_PLAIN" ] || fail "empty --grep should equal no-flag output"
pass "hv-backlog --grep '' equals unfiltered output"

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

# Scoped refactor subjects (refactor(scope):) also count as refactor commits.
cat >> .hv/TODO.md <<'EOF'
- **[F42] Scoped refactor feature.**
EOF
echo "r2" > r2.txt && git add r2.txt && git commit -q -m "refactor(hosts): consolidate"
"$BIN/hv-complete" F42
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 0' || fail "scoped refactor(scope): subject bumped counter, got: $OUT"
pass "hv-complete recognises scoped refactor(scope): subjects"

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

# ship-body emits Closes #N for GH refs in resolved item bullets
git checkout -q main
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B71] [P1] Has GH ref.** Something. GH: #42~~ Done 2026-04-18 [`ccc3333`]
- ~~**[F71] [Minor] No GH ref.** Plain.~~ Done 2026-04-18 [`ddd4444`]
EOF
git add -A && git commit -q -m "seed gh-closes test" || true
git checkout -q -b hv/ship-gh-closes
echo g1 > g1.txt && git add g1.txt && git commit -q -m "fix: thing [B71]"
echo g2 > g2.txt && git add g2.txt && git commit -q -m "feat: thing [F71]"
git checkout -q main
BODY=$("$BIN/hv-ship-body" hv/ship-gh-closes)
echo "$BODY" | grep -q "^Closes #42$" || fail "ship-body missing Closes #42 line: $BODY"
GH_LINES=$(echo "$BODY" | grep -c "^Closes #" || true)
[ "$GH_LINES" = "1" ] || fail "ship-body expected 1 Closes line, got $GH_LINES: $BODY"
pass "ship-body emits Closes #N from GH refs in TODO bullets"
git checkout -q main
git branch -D hv/ship-gh-closes >/dev/null 2>&1 || true
rm -f g1.txt g2.txt

# Negative case: no GH refs anywhere → no Closes lines.
git checkout -q main
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B72] [P1] No ref.** Plain.~~ Done 2026-04-18 [`eee5555`]
EOF
git add -A && git commit -q -m "seed gh-closes negative" || true
git checkout -q -b hv/ship-gh-noclose
echo g3 > g3.txt && git add g3.txt && git commit -q -m "fix: thing [B72]"
git checkout -q main
BODY=$("$BIN/hv-ship-body" hv/ship-gh-noclose)
if echo "$BODY" | grep -q "^Closes #"; then fail "ship-body emitted Closes line with no GH refs: $BODY"; fi
pass "ship-body emits no Closes lines when no GH refs present"
git checkout -q main
git branch -D hv/ship-gh-noclose >/dev/null 2>&1 || true
rm -f g3.txt

# Dedup: two commits referencing the same ID emit a single Closes #N line.
git checkout -q main
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B73] [P1] Has GH ref.** Something. GH: #99~~ Done 2026-04-18 [`fff6666`]
EOF
git add -A && git commit -q -m "seed gh-closes dedup" || true
git checkout -q -b hv/ship-gh-dedup
echo g4 > g4.txt && git add g4.txt && git commit -q -m "fix: thing one [B73]"
echo g5 > g5.txt && git add g5.txt && git commit -q -m "fix: thing two [B73]"
git checkout -q main
BODY=$("$BIN/hv-ship-body" hv/ship-gh-dedup)
DEDUP_LINES=$(echo "$BODY" | grep -c "^Closes #99$" || true)
[ "$DEDUP_LINES" = "1" ] || fail "ship-body expected 1 Closes #99 line (dedup), got $DEDUP_LINES: $BODY"
pass "ship-body dedups Closes #N across multiple commits referencing same ID"
git checkout -q main
git branch -D hv/ship-gh-dedup >/dev/null 2>&1 || true
rm -f g4.txt g5.txt

# Restore demo TODO state for downstream review-scope tests
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B70] [P1] Ship demo bug.** Broken badge.~~ Done 2026-04-18 [`aaa1111`]
- ~~**[F70] [Minor] Ship demo feature.** Overlay.~~ Done 2026-04-18 [`bbb2222`]
EOF
git add -A && git commit -q -m "restore ship demo TODO" || true

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

echo "hv-update-check Claude Code plugin cache layout"
# Build a fake Claude Code plugin cache with two installed versions so we can
# verify the resolver picks the newest by `sort -Vr` and reports it as plugin.
XX_TMP="$(mktemp -d)"
(
  cd "$XX_TMP"
  mkdir -p .hv/bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*

  # Two sibling versions; 2.0.0 must win over 1.0.0 (and over a 1.10.0-style
  # lexical winner — we use 2.0.0 to keep the assertion plain).
  for v in 1.0.0 2.0.0; do
    mkdir -p "fake-home/.claude/plugins/cache/hv-skills/hv-skills/$v/.claude-plugin"
    mkdir -p "fake-home/.claude/plugins/cache/hv-skills/hv-skills/$v/bin"
    cat > "fake-home/.claude/plugins/cache/hv-skills/hv-skills/$v/.claude-plugin/plugin.json" <<EOF2
{"name":"hv-skills","version":"$v"}
EOF2
  done

  OUT=$(HOME="$XX_TMP/fake-home" HV_LATEST_VERSION=2.0.0 .hv/bin/hv-update-check)
  echo "$OUT" | grep -q '"installType": "plugin"' || fail "cache-layout: installType != plugin: $OUT"
  echo "$OUT" | grep -q '"currentVersion": "2.0.0"' || fail "cache-layout: currentVersion != 2.0.0: $OUT"
  echo "$OUT" | grep -q '/2.0.0' || fail "cache-layout: installRoot missing /2.0.0/: $OUT"
  pass "hv-update-check resolves Claude Code plugin cache and picks newest version"
)
rm -rf "$XX_TMP"

echo "hv-version-check"
XX_TMP="$(mktemp -d)"
(
  cd "$XX_TMP"
  mkdir -p .hv/bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*

  # Test 1: no .hv/config.json → silent, exit 0.
  rm -f .hv/config.json
  OUT=$(.hv/bin/hv-version-check 2>/dev/null || fail "hv-version-check exited non-zero with no config")
  [ -z "$OUT" ] || fail "hv-version-check: expected silence with no config, got: $OUT"
  pass "hv-version-check is silent when .hv/config.json is missing"

  # Test 2: drift between stamped 1.0.0 and installed 2.0.0.
  mkdir -p "fake-home/.claude/plugins/cache/hv-skills/hv-skills/2.0.0/.claude-plugin"
  cat > "fake-home/.claude/plugins/cache/hv-skills/hv-skills/2.0.0/.claude-plugin/plugin.json" <<'EOF2'
{"name":"hv-skills","version":"2.0.0"}
EOF2
  cat > .hv/config.json <<'EOF2'
{"hvSkills":{"version":"1.0.0"}}
EOF2
  OUT=$(HOME="$XX_TMP/fake-home" .hv/bin/hv-version-check)
  echo "$OUT" | grep -q '1.0.0' || fail "drift: missing stamped 1.0.0: $OUT"
  echo "$OUT" | grep -q '2.0.0' || fail "drift: missing installed 2.0.0: $OUT"
  echo "$OUT" | grep -q '/hv-init' || fail "drift: missing /hv-init nudge: $OUT"
  pass "hv-version-check prints drift line when stamped != installed"

  # Test 3: match between stamped 2.0.0 and installed 2.0.0 → silent.
  cat > .hv/config.json <<'EOF2'
{"hvSkills":{"version":"2.0.0"}}
EOF2
  OUT=$(HOME="$XX_TMP/fake-home" .hv/bin/hv-version-check)
  [ -z "$OUT" ] || fail "match: expected silence, got: $OUT"
  pass "hv-version-check is silent when stamped == installed"

  # Test 4: --json always emits JSON with required keys.
  OUT=$(HOME="$XX_TMP/fake-home" .hv/bin/hv-version-check --json)
  echo "$OUT" | grep -q '"stamped"' || fail "--json: missing stamped key: $OUT"
  echo "$OUT" | grep -q '"installed"' || fail "--json: missing installed key: $OUT"
  echo "$OUT" | grep -q '"status"' || fail "--json: missing status key: $OUT"
  echo "$OUT" | grep -q '"status": "match"' || fail "--json: expected match status: $OUT"
  pass "hv-version-check --json emits stamped/installed/status keys"
)
rm -rf "$XX_TMP"

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
  [ "$HV_OPEN_SECTIONS" = "Bugs|Features|Tasks" ] || { echo "HV_OPEN_SECTIONS=$HV_OPEN_SECTIONS"; exit 1; }
) || fail "hv-types.sh did not export expected values"
pass "hv-types.sh exports HV_ITEM_TYPES=BFT and HV_OPEN_SECTIONS=Bugs|Features|Tasks"

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
  mkdir -p .hv
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
  mkdir -p .hv
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

# M03-T1: hv-resolve-repos parses CSV and resolves names
(cd "$UMB" && "$BIN/hv-resolve-repos" "web, api" > "$TMP/resolved.json")
python3 -c "
import json
d = json.load(open('$TMP/resolved.json'))
assert isinstance(d, list) and len(d) == 2, d
names = sorted(r['name'] for r in d)
assert names == ['api', 'web'], names
for r in d:
    assert r['path'].startswith('/'), r
" || fail "hv-resolve-repos output schema wrong"
pass "M03-T1: hv-resolve-repos returns JSON array of {name, path}"

# M03-T1: single-name CSV returns 1-element array
(cd "$UMB" && "$BIN/hv-resolve-repos" "web" > "$TMP/resolved-single.json")
python3 -c "
import json
d = json.load(open('$TMP/resolved-single.json'))
assert len(d) == 1 and d[0]['name'] == 'web', d
" || fail "hv-resolve-repos single-name output wrong"
pass "M03-T1: hv-resolve-repos accepts single name"

# M03-T1: unregistered name exits 1 with clear stderr
if (cd "$UMB" && "$BIN/hv-resolve-repos" "web, nonexistent" 2>"$TMP/err" >/dev/null); then
  fail "hv-resolve-repos should exit 1 on unregistered name"
fi
grep -q "nonexistent" "$TMP/err" || fail "hv-resolve-repos error must name the missing sub-repo"
pass "M03-T1: hv-resolve-repos exits 1 and names missing sub-repo"

# M03-T1: empty CSV returns empty array, exit 0
(cd "$UMB" && "$BIN/hv-resolve-repos" "" > "$TMP/resolved-empty.json")
python3 -c "import json; d=json.load(open('$TMP/resolved-empty.json')); assert d == [], d" \
  || fail "hv-resolve-repos empty CSV must return []"
pass "M03-T1: hv-resolve-repos handles empty CSV"

# M03-T2: hv-multi-branch-create succeeds when branch is absent in all repos
(cd "$UMB" && "$BIN/hv-multi-branch-create" --branch hv/m3-test --repos "web, api")
git -C "$UMB/web" show-ref --verify --quiet refs/heads/hv/m3-test \
  || fail "hv-multi-branch-create did not create branch in web"
git -C "$UMB/api" show-ref --verify --quiet refs/heads/hv/m3-test \
  || fail "hv-multi-branch-create did not create branch in api"
pass "M03-T2: hv-multi-branch-create creates branch in every named repo"

# Cleanup the branches before the collision test below
git -C "$UMB/web" branch -D hv/m3-test >/dev/null
git -C "$UMB/api" branch -D hv/m3-test >/dev/null

# M03-T2: pre-existing branch in ANY named repo aborts before creating any
git -C "$UMB/web" branch hv/m3-collide >/dev/null
if (cd "$UMB" && "$BIN/hv-multi-branch-create" --branch hv/m3-collide --repos "web, api" 2>"$TMP/err" >/dev/null); then
  fail "hv-multi-branch-create should exit 1 when branch exists in any repo"
fi
grep -q "web" "$TMP/err" || fail "hv-multi-branch-create error must name the colliding repo"
if git -C "$UMB/api" show-ref --verify --quiet refs/heads/hv/m3-collide; then
  fail "hv-multi-branch-create created branch in api despite collision in web"
fi
pass "M03-T2: hv-multi-branch-create aborts atomically on collision"

# Cleanup
git -C "$UMB/web" branch -D hv/m3-collide >/dev/null

# M03-T2: unregistered repo name exits non-zero (delegated to hv-resolve-repos)
if (cd "$UMB" && "$BIN/hv-multi-branch-create" --branch hv/m3-bad --repos "web, nonexistent" 2>/dev/null); then
  fail "hv-multi-branch-create should fail on unregistered repo"
fi
pass "M03-T2: hv-multi-branch-create rejects unregistered repos"

# M03-T3: hv-status-add-multi creates one status entry per (branch, repo)
rm -f "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add-multi" --branch hv/m3-foo --items M03-S01 --repos "web, api")
python3 -c "
import json
d = json.load(open('$UMB/.hv/status.json'))
active = d.get('active', [])
keys = sorted((e['branch'], e['repo']) for e in active if e['branch'] == 'hv/m3-foo')
assert keys == [('hv/m3-foo', 'api'), ('hv/m3-foo', 'web')], keys
for e in active:
    if e['branch'] == 'hv/m3-foo':
        assert e['items'] == ['M03-S01'], e
        assert e.get('worktree') is None, e
" || fail "hv-status-add-multi did not create one entry per (branch, repo)"
pass "M03-T3: hv-status-add-multi creates one status entry per repo"

# M03-T3: --worktrees pairs paths with repos by index
rm -f "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add-multi" --branch hv/m3-bar --items M03-S01 \
  --repos "web, api" --worktrees "/tmp/wt-web, /tmp/wt-api")
python3 -c "
import json
d = json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['repo'], e['worktree']) for e in d['active'] if e['branch'] == 'hv/m3-bar')
assert pairs == [('api', '/tmp/wt-api'), ('web', '/tmp/wt-web')], pairs
" || fail "hv-status-add-multi worktree pairing wrong"
pass "M03-T3: hv-status-add-multi pairs --worktrees with --repos by index"

# M03-T3: mismatched --worktrees length is a usage error
rm -f "$UMB/.hv/status.json"
if (cd "$UMB" && "$BIN/hv-status-add-multi" --branch hv/m3-baz --items M03-S01 \
     --repos "web, api" --worktrees "/tmp/only-one" 2>/dev/null); then
  fail "hv-status-add-multi should reject mismatched --worktrees length"
fi
pass "M03-T3: hv-status-add-multi rejects mismatched --worktrees length"

# M03-T3: unregistered repo name exits non-zero
rm -f "$UMB/.hv/status.json"
if (cd "$UMB" && "$BIN/hv-status-add-multi" --branch hv/m3-bad --items M03-S01 --repos "web, nonexistent" 2>/dev/null); then
  fail "hv-status-add-multi should reject unregistered repos"
fi
pass "M03-T3: hv-status-add-multi rejects unregistered repos"

# M03-T5: hv-capture/SKILL.md Step 4.6 declares multi-select for Repos
grep -q "multiSelect:.*true" "$REPO/hv-capture/SKILL.md" \
  || fail "hv-capture Step 4.6 must declare multiSelect: true for the Repos question"
grep -q "comma-separated list of registered sub-repos" "$REPO/hv-capture/SKILL.md" \
  || fail "hv-capture field-order line must say 'comma-separated list of registered sub-repos'"
if grep -q "single name in V1" "$REPO/hv-capture/SKILL.md"; then
  fail "hv-capture must no longer carry the 'single name in V1' qualifier"
fi
pass "M03-T5: hv-capture/SKILL.md Step 4.6 supports multi-repo Repos tagging"

# M03-T6: hv-plan-add accepts comma-separated --repo and validates each name
PLANS_TMP=$(mktemp -d)
mkdir -p "$PLANS_TMP/.hv"
cp -r "$UMB/.hv/repos.json" "$PLANS_TMP/.hv/repos.json"

# Single name still works (backwards compat)
(cd "$PLANS_TMP" && "$BIN/hv-plan-add" --repo web M99 B01 "single repo plan" >/dev/null)
grep -q "^repo: web$" "$PLANS_TMP/.hv/plans/M99-B01.md" \
  || fail "hv-plan-add single --repo did not write 'repo: web' frontmatter"
pass "M03-T6: hv-plan-add accepts a single --repo name"

# Multi-repo list writes joined frontmatter
(cd "$PLANS_TMP" && "$BIN/hv-plan-add" --repo "web, api" M99 B02 "multi repo plan" >/dev/null)
grep -q "^repo: web, api$" "$PLANS_TMP/.hv/plans/M99-B02.md" \
  || fail "hv-plan-add multi --repo did not write 'repo: web, api' frontmatter"
pass "M03-T6: hv-plan-add accepts comma-separated --repo and writes joined value"

# Unregistered name in CSV is rejected; no plan file written
if (cd "$PLANS_TMP" && "$BIN/hv-plan-add" --repo "web, nonexistent" M99 B03 "bad plan" 2>"$TMP/err" >/dev/null); then
  fail "hv-plan-add should reject unregistered name in --repo CSV"
fi
[ -f "$PLANS_TMP/.hv/plans/M99-B03.md" ] && fail "hv-plan-add wrote plan file despite invalid --repo"
grep -q "nonexistent" "$TMP/err" || fail "hv-plan-add error must name the unregistered sub-repo"
pass "M03-T6: hv-plan-add rejects unregistered name in --repo CSV"

rm -rf "$PLANS_TMP"

# M03-T6: hv-plan/SKILL.md prose mentions multi-repo flow
grep -q 'multi-repo items pass the full comma-list' "$REPO/hv-plan/SKILL.md" \
  || fail "hv-plan/SKILL.md must explain multi-repo --repo flow"
pass "M03-T6: hv-plan/SKILL.md documents multi-repo --repo"

# M03-T6: hv-assume/SKILL.md peek shape supports multiple sub-repo lines
grep -q "one line per repo for multi-repo items" "$REPO/hv-assume/SKILL.md" \
  || fail "hv-assume/SKILL.md peek must show one Repo line per sub-repo for multi-repo items"
pass "M03-T6: hv-assume/SKILL.md peek renders one line per repo"

# M03-T4: hv-work/SKILL.md documents multi-repo dispatch via the helpers
grep -q "hv-multi-branch-create" "$REPO/hv-work/SKILL.md" \
  || fail "hv-work/SKILL.md must reference bin/hv-multi-branch-create for multi-repo branch creation"
grep -q "hv-status-add-multi" "$REPO/hv-work/SKILL.md" \
  || fail "hv-work/SKILL.md must reference bin/hv-status-add-multi for multi-repo status entries"
grep -q "hv-resolve-repos" "$REPO/hv-work/SKILL.md" \
  || fail "hv-work/SKILL.md must reference bin/hv-resolve-repos for multi-repo validation"
if grep -q "M03 (deferred)" "$REPO/hv-work/SKILL.md"; then
  fail "hv-work/SKILL.md must no longer say 'M03 (deferred)'"
fi
if grep -q "wait for M03 multi-repo support" "$REPO/hv-work/SKILL.md"; then
  fail "hv-work/SKILL.md must no longer say 'wait for M03 multi-repo support'"
fi
pass "M03-T4: hv-work/SKILL.md documents multi-repo dispatch flow"

# Cleanup status.json so it doesn't pollute later assertions
rm -f "$UMB/.hv/status.json"

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

echo "parse_todo_fields Repos field"
RESULT=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import parse_todo_fields
r = parse_todo_fields('- **[F01] [Major] T.** D. Detail: x. Milestone: M02 Repos: web')
import json
print(json.dumps(r, sort_keys=True))
")
EXPECTED='{"detail": "x.", "milestone": "M02", "related": "", "repos": "web", "subsystem": ""}'
[ "$RESULT" = "$EXPECTED" ] || fail "parse_todo_fields Repos: expected $EXPECTED, got $RESULT"
pass "parse_todo_fields captures Repos field without bleeding into Milestone"

RESULT2=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import parse_todo_fields
r = parse_todo_fields('- **[B07] [P1] T.** D. Milestone: M01')
print(r['milestone'])
")
[ "$RESULT2" = "M01" ] || fail "parse_todo_fields Milestone without Repos: expected M01, got '$RESULT2'"
pass "parse_todo_fields Milestone capture without Repos field unchanged"

echo "hvlib.load_repos"
mkdir lr-test && cd lr-test
mkdir -p .hv web api
cat > .hv/repos.json <<'EOF'
{"repos": [{"name": "web", "path": "./web"}, {"name": "api", "path": "./api"}]}
EOF
RESULT=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import load_repos
r = load_repos()
print(sorted(r.keys()))
")
[ "$RESULT" = "['api', 'web']" ] || fail "load_repos keys: expected ['api', 'web'], got $RESULT"
pass "load_repos returns name → path mapping"

# Empty registry case
echo '{"repos": []}' > .hv/repos.json
EMPTY=$(PYTHONPATH="$BIN" python3 -c "from hvlib import load_repos; print(load_repos())")
[ "$EMPTY" = "{}" ] || fail "load_repos empty registry: expected {}, got '$EMPTY'"
pass "load_repos returns {} for empty registry"

cd ..

echo "hv-base-branch walks up to umbrella config"
mkdir bb-walk && cd bb-walk
# Create a fake umbrella with config.json, no git
mkdir -p .hv subrepo
cat > .hv/config.json <<'EOF'
{"git": {"baseBranch": "develop"}}
EOF
# Create a sub-repo with its own git tree, no .hv/
cd subrepo
git init -q
git config user.email t@t && git config user.name t
git checkout -q -b develop 2>/dev/null || git branch -m develop
echo "x" > f && git add f && git commit -q -m "seed"
# From inside the sub-repo (no .hv/), hv-base-branch should find umbrella's develop
RESULT=$("$BIN/hv-base-branch")
[ "$RESULT" = "develop" ] || fail "hv-base-branch from sub-repo: expected develop, got '$RESULT'"
pass "hv-base-branch walks up to umbrella .hv/config.json from sub-repo"
cd ../..

echo "hv-summary shows repo for umbrella active entries"
mkdir sum-test && cd sum-test
mkdir -p .hv
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
cat > .hv/MILESTONES.md <<'EOF'
# Vision

## Active milestones

## Milestones
EOF
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z", "repo": "web"}]}
EOF
echo '{"bugs":0,"features":0,"tasks":0,"milestones":0}' > .hv/counters.json
OUT=$("$BIN/hv-summary")
echo "$OUT" | grep -q "(repo: web)" || fail "hv-summary missing (repo: web): $OUT"
pass "hv-summary shows (repo: <name>) for umbrella active entry"

# And: legacy entry without repo doesn't show parenthetical
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z"}]}
EOF
OUT=$("$BIN/hv-summary")
if echo "$OUT" | grep -q "repo:"; then fail "hv-summary unexpectedly shows 'repo:' for non-umbrella entry: $OUT"; fi
pass "hv-summary does not show repo: for legacy active entries"
cd ..

echo "hv-backlog In Progress Repo column"
mkdir bl-test && cd bl-test
mkdir -p .hv
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

- **[B01] [P1] Title.** Body.

## Features

## Tasks

## Completed
EOF
cat > .hv/MILESTONES.md <<'EOF'
# Vision

## Active milestones

## Milestones
EOF
echo '{"bugs":1,"features":0,"tasks":0,"milestones":0}' > .hv/counters.json

# With umbrella entry: column should appear
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z", "repo": "web"}]}
EOF
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "| Repo |" || fail "hv-backlog missing Repo column: $OUT"
pass "hv-backlog adds Repo column when active entry has repo"

# Legacy entry: column should NOT appear
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z"}]}
EOF
OUT=$("$BIN/hv-backlog")
if echo "$OUT" | grep -q "| Repo |"; then fail "hv-backlog unexpectedly shows Repo column: $OUT"; fi
pass "hv-backlog omits Repo column when no active entry has repo"
cd ..

echo "hv-preflight gates on repos.json under umbrella mode"
mkdir pf-test && cd pf-test
mkdir -p .hv/bin
# Seed minimal required files
echo "" > .hv/DECISIONS.md
echo "" > .hv/TODO.md
echo "" > .hv/KNOWLEDGE.md
echo "" > .hv/MILESTONES.md
echo "{}" > .hv/counters.json
echo '{"active":[]}' > .hv/status.json
# Copy hvlib.py + hv-preflight (preflight discovers helpers from its own dir's siblings)
cp "$BIN/hvlib.py" .hv/bin/
for f in "$BIN"/hv-*; do cp "$f" .hv/bin/ && chmod +x ".hv/bin/$(basename $f)"; done

# Single-repo: no repos.json needed
echo '{"umbrella": {"enabled": false}}' > .hv/config.json
.hv/bin/hv-preflight && pass "hv-preflight passes single-repo without repos.json" || fail "hv-preflight failed single-repo"

# Umbrella enabled, repos.json missing: exit 2
echo '{"umbrella": {"enabled": true}}' > .hv/config.json
if .hv/bin/hv-preflight 2>/dev/null; then fail "hv-preflight should fail with umbrella.enabled and missing repos.json"; fi
RC=0; .hv/bin/hv-preflight 2>/dev/null || RC=$?
[ "$RC" = "2" ] || fail "hv-preflight expected exit 2, got $RC"
pass "hv-preflight exits 2 when umbrella.enabled and repos.json missing"

# Umbrella enabled, repos.json with at least one entry: pass
echo '{"repos": [{"name": "web", "path": "./web"}]}' > .hv/repos.json
.hv/bin/hv-preflight && pass "hv-preflight passes with umbrella.enabled and valid repos.json" || fail "hv-preflight failed with valid repos.json"

# Umbrella enabled, repos.json empty: exit 2
echo '{"repos": []}' > .hv/repos.json
if .hv/bin/hv-preflight 2>/dev/null; then fail "hv-preflight should fail with umbrella.enabled and empty repos.json"; fi
RC=0; .hv/bin/hv-preflight 2>/dev/null || RC=$?
[ "$RC" = "2" ] || fail "hv-preflight expected exit 2 for empty repos.json, got $RC"
pass "hv-preflight exits 2 when umbrella.enabled and repos.json empty"

# Umbrella DISABLED but repos.json valid: pass (data is truth; flag is informational).
# Exercises the B15 fix — /hv-next must reconcile when repos.json is present
# even if a stale config has umbrella.enabled: false.
echo '{"umbrella": {"enabled": false}}' > .hv/config.json
echo '{"repos": [{"name": "web", "path": "./web"}]}' > .hv/repos.json
.hv/bin/hv-preflight && pass "hv-preflight passes with umbrella.enabled:false but valid repos.json (data is truth)" || fail "hv-preflight failed when repos.json valid but flag false"

# Direct test of hv-umbrella-on: repos.json wins over the config flag.
OUT=$(.hv/bin/hv-umbrella-on)
[ "$OUT" = "yes" ] || fail "hv-umbrella-on expected 'yes' from repos.json regardless of config flag, got '$OUT'"
pass "hv-umbrella-on returns 'yes' from repos.json regardless of config flag"
cd ..

echo "hv-resolve-umbrella detects deep stray .hv/"
mkdir ru-deep && cd ru-deep
# umbrella + sub-repo registered + DEEP stray .hv/ inside sub-repo's source tree
mkdir -p .hv web/src/.hv
cat > .hv/repos.json <<'EOF'
{"repos": [{"name": "web", "path": "./web"}]}
EOF
cd web/src
RC=0; "$BIN/hv-resolve-umbrella" 2>/dev/null || RC=$?
[ "$RC" = "2" ] || fail "hv-resolve-umbrella deep stray expected exit 2, got $RC"
pass "hv-resolve-umbrella exits 2 on deep stray .hv/ inside registered sub-repo"
cd ../../..

echo "hvlib.parse_toml_version"
mkdir ptv-test && cd ptv-test
RESULT=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import parse_toml_version
text1 = '[project]\nname = \"foo\"\nversion = \"1.2.3\"\n'
text2 = '[tool.poetry]\nname = \"foo\"\nversion = \"2.0.0\"\n'
text3 = '[package]\nname = \"foo\"\nversion = \"0.1.0\"\nedition = \"2021\"\n'
text4 = '[other]\nfoo = 1\n'  # no version field
text5 = '[project]\nname = \"foo\"\nversion = \"\"\n'  # empty version
print(parse_toml_version(text1, ['project']))
print(parse_toml_version(text2, ['project', 'tool.poetry']))
print(parse_toml_version(text3, ['package']))
print(repr(parse_toml_version(text4, ['project'])))
print(repr(parse_toml_version(text5, ['project'])))
")
EXPECTED=$'1.2.3\n2.0.0\n0.1.0\nNone\n\'\''
[ "$RESULT" = "$EXPECTED" ] || fail "parse_toml_version: expected:
$EXPECTED
got:
$RESULT"
pass "parse_toml_version handles project, tool.poetry, package, missing-section, and empty-string version"
cd ..

echo "hv-release-bump-version --dry-run"
mkdir bv-dry && cd bv-dry

# Create a plugin.json
echo '{"name": "foo", "version": "1.2.3"}' > plugin.json
ORIG_HASH=$(sha256sum plugin.json | cut -c1-16)

# --dry-run patch
NEW=$("$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json patch)
[ "$NEW" = "1.2.4" ] || fail "--dry-run patch: expected 1.2.4, got '$NEW'"
NEW_HASH=$(sha256sum plugin.json | cut -c1-16)
[ "$ORIG_HASH" = "$NEW_HASH" ] || fail "--dry-run patch should not modify the file"
pass "--dry-run patch prints new version, leaves file unchanged"

# --dry-run minor
NEW=$("$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json minor)
[ "$NEW" = "1.3.0" ] || fail "--dry-run minor: expected 1.3.0, got '$NEW'"
pass "--dry-run minor prints 1.3.0"

# --dry-run major
NEW=$("$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json major)
[ "$NEW" = "2.0.0" ] || fail "--dry-run major: expected 2.0.0, got '$NEW'"
pass "--dry-run major prints 2.0.0"

# --dry-run explicit semver
NEW=$("$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json 1.5.0)
[ "$NEW" = "1.5.0" ] || fail "--dry-run explicit 1.5.0: expected 1.5.0, got '$NEW'"
pass "--dry-run explicit semver prints 1.5.0"

# --dry-run rejects backwards explicit
if "$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json 1.0.0 2>/dev/null; then
  fail "--dry-run should reject backwards explicit version"
fi
pass "--dry-run rejects backwards explicit version"

# Now actually bump (no --dry-run) and verify file changes
NEW=$("$BIN/hv-release-bump-version" plugin.json plugin-json patch)
[ "$NEW" = "1.2.4" ] || fail "real bump patch: expected 1.2.4, got '$NEW'"
WRITTEN=$(python3 -c "import json; print(json.loads(open('plugin.json').read())['version'])")
[ "$WRITTEN" = "1.2.4" ] || fail "real bump should write 1.2.4 to file, got '$WRITTEN'"
pass "real bump (without --dry-run) writes the new version to plugin.json"

# Test --dry-run on pyproject.toml (uses parse_toml_version path)
cat > pyproject.toml <<'EOF'
[project]
name = "foo"
version = "0.5.0"
EOF
NEW=$("$BIN/hv-release-bump-version" --dry-run pyproject.toml pyproject minor)
[ "$NEW" = "0.6.0" ] || fail "--dry-run pyproject minor: expected 0.6.0, got '$NEW'"
pass "--dry-run pyproject reads via hvlib.parse_toml_version"

# Confirm pyproject not modified
grep -q '"0.5.0"' pyproject.toml || fail "--dry-run pyproject should not modify file"
pass "--dry-run pyproject leaves file unchanged"

cd ..

echo "hv-spike-add no orphan branch on file-collision"
mkdir spike-orphan && cd spike-orphan
git init -q
git config user.email t@t && git config user.name t
git checkout -q -b main 2>/dev/null || git branch -m main
echo "x" > f && git add f && git commit -q -m "seed"
mkdir -p .hv/spikes

# Create the spike file BUT NO branch (simulating partial-state retry)
echo "leftover" > .hv/spikes/foo.md

# hv-spike-add should fail at the file-existence check, NOT create the branch
if "$BIN/hv-spike-add" foo "?" 2>/dev/null; then
  fail "hv-spike-add should fail when .hv/spikes/foo.md already exists"
fi

# CRITICAL: branch must NOT exist (orphan-branch regression test)
if git rev-parse --verify spike/foo >/dev/null 2>&1; then
  fail "hv-spike-add created branch despite file-collision — orphan branch regression"
fi
pass "hv-spike-add does not create branch when spike file already exists"
cd ..

echo "hv-refactor-targets"
mkdir rt-test && cd rt-test
mkdir -p .hv/bin
cp "$BIN/hvlib.py" .hv/bin/
cp "$BIN/hv-refactor-targets" .hv/bin/
chmod +x .hv/bin/hv-refactor-targets

# 1. Single-repo (umbrella.enabled = false): emits umbrella=null, subRepos=[]
echo '{"umbrella": {"enabled": false}}' > .hv/config.json
RESULT=$(.hv/bin/hv-refactor-targets)
UMBRELLA=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['umbrella'])")
[ "$UMBRELLA" = "None" ] || fail "single-repo: expected umbrella=null, got '$UMBRELLA'"
SUB_COUNT=$(echo "$RESULT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['subRepos']))")
[ "$SUB_COUNT" = "0" ] || fail "single-repo: expected subRepos=[], got count=$SUB_COUNT"
pass "hv-refactor-targets returns umbrella=null when umbrella.enabled is false"

# 2. Umbrella with sub-repos: emits the registered list
mkdir -p web api
echo '{"umbrella": {"enabled": true}}' > .hv/config.json
echo '{"repos": [{"name": "web", "path": "./web"}, {"name": "api", "path": "./api"}]}' > .hv/repos.json
RESULT=$(.hv/bin/hv-refactor-targets)
SUB_COUNT=$(echo "$RESULT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['subRepos']))")
[ "$SUB_COUNT" = "2" ] || fail "umbrella: expected 2 sub-repos, got $SUB_COUNT"
NAMES=$(echo "$RESULT" | python3 -c "import json,sys; print(','.join(sorted(r['name'] for r in json.load(sys.stdin)['subRepos'])))")
[ "$NAMES" = "api,web" ] || fail "umbrella: expected names api,web, got '$NAMES'"
pass "hv-refactor-targets lists registered sub-repos in umbrella mode"

# 3. Umbrella with no own code (only .hv/, registered sub-repos)
HAS_CODE=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['umbrella']['hasCode'])")
[ "$HAS_CODE" = "False" ] || fail "no-code umbrella: expected hasCode=false, got '$HAS_CODE'"
pass "hv-refactor-targets reports hasCode=false when umbrella has only scaffolding + sub-repos"

# 4. Add umbrella-level code → hasCode flips
echo "x" > umbrella-thing.py
RESULT=$(.hv/bin/hv-refactor-targets)
HAS_CODE=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['umbrella']['hasCode'])")
[ "$HAS_CODE" = "True" ] || fail "umbrella with code: expected hasCode=true, got '$HAS_CODE'"
pass "hv-refactor-targets reports hasCode=true when umbrella has its own code file"

# 5. Standard scaffolding (.gitignore) doesn't trigger hasCode by itself
rm umbrella-thing.py
echo "ignored-stuff" > .gitignore
RESULT=$(.hv/bin/hv-refactor-targets)
HAS_CODE=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['umbrella']['hasCode'])")
[ "$HAS_CODE" = "False" ] || fail "scaffolding-only umbrella: expected hasCode=false, got '$HAS_CODE'"
pass "hv-refactor-targets ignores standard scaffolding (.gitignore) when computing hasCode"

cd ..

echo "F10 self-locate: helpers work from a sub-cwd"
# Install helpers at production-like .hv/bin/ so walk-up from BASH_SOURCE
# lands on the test umbrella's .hv/, not the dev tree's .hv/.
mkdir -p .hv/bin
cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
mkdir -p subdir
BEFORE_BUGS=$(python3 -c 'import json; print(json.load(open(".hv/counters.json"))["bugs"])')
(
  cd subdir
  ID=$(../.hv/bin/hv-next-id bugs)
  [ -n "$ID" ] || { echo "FAIL: hv-next-id from subdir produced empty"; exit 1; }
  # The new ID lands in the umbrella's counters.json, not the subdir's.
  [ ! -f .hv/counters.json ] || { echo "FAIL: hv-next-id created subdir/.hv/"; exit 1; }
)
[ -f .hv/counters.json ] || fail "self-locate: umbrella counters.json missing"
AFTER_BUGS=$(python3 -c 'import json; print(json.load(open(".hv/counters.json"))["bugs"])')
[ "$AFTER_BUGS" -gt "$BEFORE_BUGS" ] || fail "self-locate: umbrella counters.json bugs did not increment ($BEFORE_BUGS -> $AFTER_BUGS)"
pass "hv-next-id self-locates from sub-cwd"

(
  cd subdir
  ../.hv/bin/hv-summary >/dev/null
)
pass "hv-summary self-locates from sub-cwd"

(
  cd subdir
  ../.hv/bin/hv-backlog >/dev/null
)
pass "hv-backlog self-locates from sub-cwd"

rm -rf subdir .hv/bin

echo "B02 umbrella-cwd guards"
UMB_TMP="$(mktemp -d)"
(
  cd "$UMB_TMP"
  mkdir -p .hv/bin
  echo '{"umbrella":{"enabled":true},"git":{"baseBranch":""}}' > .hv/config.json
  # Umbrella signal of record is repos.json with >=1 entry (B15). The path
  # need not exist on disk for this fixture — the helpers under test here
  # don't dereference it; they just check whether umbrella mode is on.
  echo '{"repos":[{"name":"web","path":"./web"}]}' > .hv/repos.json
  echo '{"bugs":0,"features":0,"tasks":0,"milestones":0}' > .hv/counters.json
  echo '{"active":[]}' > .hv/status.json

  # hv-base-branch: should error with umbrella hint
  if OUT=$("$BIN/hv-base-branch" 2>&1); then echo "FAIL: hv-base-branch should fail on umbrella"; exit 1; fi
  echo "$OUT" | grep -q "umbrella" || { echo "FAIL: hv-base-branch error missing 'umbrella': $OUT"; exit 1; }

  # hv-merge: should refuse without --repo
  if OUT=$(echo "msg" | "$BIN/hv-merge" feat-x 2>&1); then echo "FAIL: hv-merge should fail on umbrella"; exit 1; fi
  echo "$OUT" | grep -q "requires --repo" || { echo "FAIL: hv-merge error missing '--repo': $OUT"; exit 1; }

  # hv-pr: should refuse without --repo
  if OUT=$(echo "body" | "$BIN/hv-pr" feat-x "title" 2>&1); then echo "FAIL: hv-pr should fail on umbrella"; exit 1; fi
  echo "$OUT" | grep -q "requires --repo" || { echo "FAIL: hv-pr error missing '--repo': $OUT"; exit 1; }

  # hv-ship-body: should error with umbrella hint
  if OUT=$("$BIN/hv-ship-body" feat-x 2>&1); then echo "FAIL: hv-ship-body should fail on umbrella"; exit 1; fi
  echo "$OUT" | grep -q "umbrella" || { echo "FAIL: hv-ship-body error missing 'umbrella': $OUT"; exit 1; }

  # hv-review-scope: should error with umbrella hint
  if OUT=$("$BIN/hv-review-scope" feat-x 2>&1); then echo "FAIL: hv-review-scope should fail on umbrella"; exit 1; fi
  echo "$OUT" | grep -q "umbrella" || { echo "FAIL: hv-review-scope error missing 'umbrella': $OUT"; exit 1; }

  # hv-reconcile: should NOT abort at the upfront hv-base-branch call
  # (it should print valid JSON for an empty active list)
  OUT=$("$BIN/hv-reconcile" 2>&1) || { echo "FAIL: hv-reconcile aborted on umbrella: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"cleaned"' || { echo "FAIL: hv-reconcile didn't emit JSON: $OUT"; exit 1; }
)
rm -rf "$UMB_TMP"
pass "B02 umbrella-cwd guards: 6 helpers refuse cleanly or operate correctly"

echo "hv-issue-suggest manual fallback when gh unavailable"
HI_TMP="$(mktemp -d)"
(
  cd "$HI_TMP"
  mkdir -p .hv/bin stub-bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
  # Stub `gh` to a script that always fails so the helper takes the manual-fallback path,
  # even on a host where the real gh is installed and authed.
  cat > stub-bin/gh <<'EOF'
#!/bin/sh
exit 7
EOF
  chmod +x stub-bin/gh
  set +e
  OUT=$(PATH="$HI_TMP/stub-bin:$PATH" .hv/bin/hv-issue-suggest --title "test title" <<<"test body" 2>&1)
  RC=$?
  set -e
  [ "$RC" = "1" ] || fail "expected exit 1 when gh fails: rc=$RC"
  echo "$OUT" | grep -q "test title" || fail "manual fallback missing title: $OUT"
  echo "$OUT" | grep -q "test body" || fail "manual fallback missing body: $OUT"
  echo "$OUT" | grep -q "github.com/l4ci/hv-skills" || fail "manual fallback missing repo URL: $OUT"
  pass "hv-issue-suggest prints manual fallback when gh unavailable"
)
rm -rf "$HI_TMP"

echo "hv-issue-suggest --upstream-repo override"
HI2_TMP="$(mktemp -d)"
(
  cd "$HI2_TMP"
  mkdir -p .hv/bin stub-bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
  cat > stub-bin/gh <<'EOF'
#!/bin/sh
exit 7
EOF
  chmod +x stub-bin/gh
  set +e
  OUT=$(PATH="$HI2_TMP/stub-bin:$PATH" .hv/bin/hv-issue-suggest --title "x" --upstream-repo "fork/repo" <<<"y" 2>&1)
  set -e
  echo "$OUT" | grep -q "github.com/fork/repo" || fail "--upstream-repo override ignored: $OUT"
  pass "hv-issue-suggest --upstream-repo override flows through to manual fallback URL"
)
rm -rf "$HI2_TMP"

echo "hv-release-pending"
RP_TMP="$(mktemp -d)"

# Case 1: no tags → no nudge, lastTag empty.
(
  cd "$RP_TMP"
  mkdir no-tag && cd no-tag
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  OUT=$("$BIN/hv-release-pending")
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['lastTag'] == '', d
assert d['commits'] == 0, d
assert d['shouldNudge'] is False, d
assert d['reason'] == 'no-tag', d
assert d['message'] == '', d
" "$OUT" || fail "no-tag case: $OUT"
)
pass "hv-release-pending: no tag -> no nudge"

# Case 2: tag + 3 commits, default thresholds → no nudge.
(
  cd "$RP_TMP"
  mkdir below && cd below
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  git tag v0.0.1
  for i in 1 2 3; do git commit -q --allow-empty -m "c$i"; done
  OUT=$("$BIN/hv-release-pending")
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['lastTag'] == 'v0.0.1', d
assert d['commits'] == 3, d
assert d['shouldNudge'] is False, d
assert d['reason'] == '', d
assert d['message'] == '', d
" "$OUT" || fail "below-threshold case: $OUT"
)
pass "hv-release-pending: 3 commits past tag -> no nudge"

# Case 3: tag + 11 commits → nudge, reason=commits.
(
  cd "$RP_TMP"
  mkdir above && cd above
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  git tag v0.0.1
  for i in $(seq 1 11); do git commit -q --allow-empty -m "c$i"; done
  OUT=$("$BIN/hv-release-pending")
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['lastTag'] == 'v0.0.1', d
assert d['commits'] == 11, d
assert d['shouldNudge'] is True, d
assert d['reason'] == 'commits', d
assert d['message'] == '11 commits since v0.0.1; consider /hv-release.', d
" "$OUT" || fail "above-commit-threshold case: $OUT"
)
pass "hv-release-pending: 11 commits past tag -> nudge (reason=commits)"

# Case 4: custom commit threshold via .hv/config.json.
(
  cd "$RP_TMP"
  mkdir custom && cd custom
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  git tag v0.0.1
  for i in $(seq 1 6); do git commit -q --allow-empty -m "c$i"; done
  mkdir -p .hv
  echo '{"release":{"nudgeAfterCommits":5}}' > .hv/config.json
  OUT=$("$BIN/hv-release-pending")
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['thresholdCommits'] == 5, d
assert d['commits'] == 6, d
assert d['shouldNudge'] is True, d
assert d['reason'] == 'commits', d
assert d['message'] == '6 commits since v0.0.1; consider /hv-release.', d
" "$OUT" || fail "custom-threshold case: $OUT"
)
pass "hv-release-pending: custom nudgeAfterCommits=5 honored"

rm -rf "$RP_TMP"

echo "F29: --repo flag uses strict form"
# Structural guard: every helper that parses a literal --repo / --repos flag
# must extract the value with the loud form ${2:?usage:...} so a missing
# argument errors out instead of silently defaulting and corrupting state
# (e.g. status.json with repo:null when the caller meant a sub-repo).
# See [F29] — Converge --repo flag parsing across helpers.
for f in hv-merge hv-pr hv-review-scope hv-spike-add hv-status-add hv-status-remove hv-worktree-clear hv-worktree-path hv-plan-add; do
  helper="$BIN/$f"
  [ -f "$helper" ] || fail "F29: expected helper $f missing from bin/"
  grep -q -- '--repo' "$helper" || fail "F29: $f no longer references --repo (canonical list stale?)"
  grep -qE '\$\{2:\?usage:' "$helper" || fail "F29: $f --repo extraction must use \${2:?usage:...} strict form (no silent \${2:-})"
done
for f in hv-status-add-multi hv-multi-branch-create; do
  helper="$BIN/$f"
  [ -f "$helper" ] || fail "F29: expected helper $f missing from bin/"
  grep -q -- '--repos' "$helper" || fail "F29: $f no longer references --repos (canonical list stale?)"
  grep -qE '\$\{2:\?usage:' "$helper" || fail "F29: $f --repos extraction must use \${2:?usage:...} strict form (no silent \${2:-})"
done
pass "F29: all --repo / --repos helpers use the strict \${2:?usage:...} extraction"

echo "F30: walk-up helpers delegate to bin/hv-walk-up"
# Structural guard: helpers that need to walk upward from a caller directory
# must delegate to the canonical bin/hv-walk-up rather than reimplementing the
# loop inline. Reverting to an inline `while [ "$dir" != "/" ]` walk drifts
# masking semantics across callers.
# See [F30] — Consolidate walk-up logic behind bin/hv-walk-up.
for f in hv-self-locate.sh hv-resolve-umbrella; do
  helper="$BIN/$f"
  [ -f "$helper" ] || fail "F30: expected helper $f missing from bin/"
  grep -q 'hv-walk-up' "$helper" || fail "F30: $f must invoke hv-walk-up (no inline walk-up loops)"
done
pass "F30: hv-self-locate.sh and hv-resolve-umbrella delegate to bin/hv-walk-up"

echo "F36: hv-rm helper"
# Behaviour guard for bin/hv-rm across all modes.
# See [F36] — /hv-rm backlog-removal command.

# ── fixture builder ──────────────────────────────────────────────────────────
# Creates (or re-creates) the standard F36 fixture inside RM_TMP.
build_rm_fixture() {
  local root="$1"
  rm -rf "$root/.hv"
  mkdir -p "$root/.hv/features" "$root/.hv/tasks" "$root/.hv/bugs" "$root/.hv/plans"

  cat > "$root/.hv/TODO.md" <<'FIXEOF'
# TODO

## Bugs
- **[B01] [P2] Crash on startup.** Repro: always. Related: [F01]

## Features
- **[F01] [Minor] Add dark mode.** Would be nice.
- **[F02] [Minor] Export to CSV.** Active feature.

## Tasks
- **[T01] [S] Write release notes.** Due soon.

## Completed
FIXEOF

  printf '# F01\n\nDark mode detail.\n' > "$root/.hv/features/F01.md"
  printf '# F02\n\nExport detail.\n'    > "$root/.hv/features/F02.md"
  printf '# Plan for F01\n\nApproach.\n' > "$root/.hv/plans/M01-F01.md"

  # status.json: F02 is active on branch hv/feature-f02.
  printf '{"active":[{"branch":"hv/feature-f02","items":["F02"]}]}\n' \
    > "$root/.hv/status.json"
}

RM_TMP="$(mktemp -d)"
build_rm_fixture "$RM_TMP"

# ── (a) dry-run exits 0, prints plan header and footer, TODO unchanged ───────
(
  cd "$RM_TMP"
  ORIG_TODO=$(cat .hv/TODO.md)
  set +e
  OUT=$("$BIN/hv-rm" F01 2>/dev/null)
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F36(a): dry-run should exit 0, got $RC"; exit 1; }
  echo "$OUT" | grep -q '\[F01\] removal plan:' \
    || { echo "FAIL F36(a): stdout missing '[F01] removal plan:': $OUT"; exit 1; }
  echo "$OUT" | grep -q 'dry-run — no files modified\.' \
    || { echo "FAIL F36(a): stdout missing 'dry-run — no files modified.': $OUT"; exit 1; }
  NEW_TODO=$(cat .hv/TODO.md)
  [ "$ORIG_TODO" = "$NEW_TODO" ] \
    || { echo "FAIL F36(a): dry-run must not modify TODO.md"; exit 1; }
)

# ── (b) not-found exits 1, stderr contains 'not found' ──────────────────────
(
  cd "$RM_TMP"
  set +e
  ERR=$("$BIN/hv-rm" BX99 2>&1 >/dev/null)
  RC=$?
  set -e
  [ "$RC" = "1" ] || { echo "FAIL F36(b): not-found should exit 1, got $RC"; exit 1; }
  echo "$ERR" | grep -q 'not found' \
    || { echo "FAIL F36(b): stderr missing 'not found': $ERR"; exit 1; }
)

# ── (c) active-stream guard exits 2, stderr contains branch name ─────────────
(
  cd "$RM_TMP"
  set +e
  ERR=$("$BIN/hv-rm" F02 2>&1 >/dev/null)
  RC=$?
  set -e
  [ "$RC" = "2" ] || { echo "FAIL F36(c): active-stream guard should exit 2, got $RC"; exit 1; }
  echo "$ERR" | grep -q 'is active on branch hv/feature-f02' \
    || { echo "FAIL F36(c): stderr missing branch name: $ERR"; exit 1; }
)

# ── (d) --force F01: entry gone, cross-ref gone, detail+plan deleted ─────────
(
  cd "$RM_TMP"
  set +e
  OUT=$("$BIN/hv-rm" --force F01 2>/dev/null)
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F36(d): --force should exit 0, got $RC"; exit 1; }
  # F01 entry removed from TODO.
  grep -q '\[F01\]' .hv/TODO.md \
    && { echo "FAIL F36(d): [F01] entry still in TODO.md after --force"; exit 1; }
  # Related: [F01] cross-ref on B01 stripped.
  grep -q 'Related:.*\[F01\]' .hv/TODO.md \
    && { echo "FAIL F36(d): Related: [F01] cross-ref still present in TODO.md"; exit 1; }
  # Detail file deleted.
  [ ! -f .hv/features/F01.md ] \
    || { echo "FAIL F36(d): .hv/features/F01.md still exists after --force"; exit 1; }
  # Plan file deleted.
  [ ! -f .hv/plans/M01-F01.md ] \
    || { echo "FAIL F36(d): .hv/plans/M01-F01.md still exists after --force"; exit 1; }
)

# ── (e) --force F02 (active stream + force): exits 0, warning on stderr,
#        status.json entry dropped ────────────────────────────────────────────
build_rm_fixture "$RM_TMP"
(
  cd "$RM_TMP"
  set +e
  ERR=$("$BIN/hv-rm" --force F02 2>&1 >/dev/null)
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F36(e): --force active-stream should exit 0, got $RC"; exit 1; }
  echo "$ERR" | grep -q 'warning: \[F02\] was active' \
    || { echo "FAIL F36(e): stderr missing 'warning: [F02] was active': $ERR"; exit 1; }
  # The active entry whose only item was F02 must be dropped from status.json.
  python3 -c "
import json, sys
d = json.load(open('.hv/status.json'))
for e in d.get('active', []):
    items = e.get('items', [])
    if isinstance(items, list):
        ids = [i.strip() for i in items]
    else:
        ids = [i.strip() for i in str(items).split(',')]
    if 'F02' in ids:
        print('FAIL F36(e): F02 still present in status.json active entry')
        sys.exit(1)
" || exit 1
)

# ── (f) --force B01,T01 (CSV batch): both removed, F01 untouched ─────────────
build_rm_fixture "$RM_TMP"
(
  cd "$RM_TMP"
  set +e
  OUT=$("$BIN/hv-rm" --force B01,T01 2>/dev/null)
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F36(f): CSV batch should exit 0, got $RC"; exit 1; }
  grep -q '\[B01\]' .hv/TODO.md \
    && { echo "FAIL F36(f): [B01] still in TODO.md after batch removal"; exit 1; }
  grep -q '\[T01\]' .hv/TODO.md \
    && { echo "FAIL F36(f): [T01] still in TODO.md after batch removal"; exit 1; }
  # F01 must still be present.
  grep -q '\[F01\]' .hv/TODO.md \
    || { echo "FAIL F36(f): [F01] was unexpectedly removed during B01,T01 batch"; exit 1; }
)

# ── (g) --scrub-archive: archive entry removed ───────────────────────────────
build_rm_fixture "$RM_TMP"
(
  cd "$RM_TMP"
  # Add F09 to ARCHIVE.md so it can be scrubbed.
  cat > .hv/ARCHIVE.md <<'ARCHEOF'
# Archive

## Features
- ~~**[F09] [Minor] Old archived feature.** Done.~~ Done 2026-01-01 [`abc1234`]
ARCHEOF

  set +e
  OUT=$("$BIN/hv-rm" --force --scrub-archive F09 2>/dev/null)
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F36(g): --scrub-archive should exit 0, got $RC"; exit 1; }
  grep -q '\[F09\]' .hv/ARCHIVE.md \
    && { echo "FAIL F36(g): [F09] entry still in ARCHIVE.md after --scrub-archive"; exit 1; } \
    || true
)

rm -rf "$RM_TMP"
pass "F36 hv-rm helper smoke"

# ── F32: loop-mode auto-planning helpers + wiring ────────────────────────────
echo "F32: loop-mode auto-planning helpers"

# (a) /hv-plan SKILL.md exposes --auto-loop with the inline dispatch language.
grep -q -- '--auto-loop' "$REPO/hv-plan/SKILL.md" \
  || fail "F32: hv-plan/SKILL.md must document the --auto-loop flag"
grep -q 'Auto-loop mode' "$REPO/hv-plan/SKILL.md" \
  || fail "F32: hv-plan/SKILL.md must include the dedicated 'Auto-loop mode' section"

# (b) /hv-work Step 4 carries the inline loop-mode auto-plan dispatch directive.
grep -q 'Loop-mode auto-plan dispatch' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must contain the loop-mode auto-plan dispatch language"
grep -q '/hv-plan --auto-loop' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must reference /hv-plan --auto-loop"

# (c) Surfacing call sites — exactly /hv-next, /hv-pause, /hv-work invoke hv-auto-decisions-since.
# (hv-plan/SKILL.md mentions the helper in prose only; the test below is for actual `.hv/bin/`-prefixed invocations.)
SURFACING_SITES=$(grep -l '\.hv/bin/hv-auto-decisions-since' "$REPO"/hv-*/SKILL.md \
  | sed -E 's@.*/(hv-[a-z-]+)/SKILL\.md@\1@' \
  | sort -u | tr '\n' ' ' | sed 's/ $//')
[ "$SURFACING_SITES" = "hv-next hv-pause hv-work" ] \
  || fail "F32: .hv/bin/hv-auto-decisions-since invocation expected in exactly hv-next/hv-pause/hv-work, got '$SURFACING_SITES'"

# (d) hv-loop-stamp wired into /hv-next (start) and /hv-pause + /hv-work (clear).
grep -q 'hv-loop-stamp start' "$REPO/hv-next/SKILL.md" \
  || fail "F32: hv-next/SKILL.md must call hv-loop-stamp start"
grep -q 'hv-loop-stamp clear' "$REPO/hv-pause/SKILL.md" \
  || fail "F32: hv-pause/SKILL.md must call hv-loop-stamp clear"
grep -q 'hv-loop-stamp clear' "$REPO/hv-work/SKILL.md" \
  || fail "F32: hv-work/SKILL.md must call hv-loop-stamp clear"

# (e) hv-init seeds loop.webResearch=False in both fresh + STALE config paths.
grep -q '"loop":.*"webResearch": False' "$REPO/hv-init/SKILL.md" \
  || fail "F32: hv-init must seed loop.webResearch in the fresh config block"
grep -q 'cfg.setdefault("loop", {}).setdefault("webResearch", False)' "$REPO/hv-init/SKILL.md" \
  || fail "F32: hv-init must seed loop.webResearch in the STALE migration block"
pass "F32: SKILL.md wiring + config defaults"

# (f) hv-loop-stamp: start writes ISO timestamp; idempotent first-write; clear removes; read is silent-empty.
F32_TMP="$(mktemp -d)"
(
  cd "$F32_TMP"
  mkdir .hv
  echo '{"active": []}' > .hv/status.json
  # read on empty
  OUT=$("$BIN/hv-loop-stamp" read)
  [ -z "$OUT" ] || fail "F32(f): hv-loop-stamp read on unset must be empty, got '$OUT'"
  # start writes
  "$BIN/hv-loop-stamp" start
  T1=$("$BIN/hv-loop-stamp" read)
  echo "$T1" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
    || fail "F32(f): hv-loop-stamp start must write ISO timestamp, got '$T1'"
  # idempotent first-write — second start must not overwrite
  sleep 1
  "$BIN/hv-loop-stamp" start
  T2=$("$BIN/hv-loop-stamp" read)
  [ "$T1" = "$T2" ] || fail "F32(f): hv-loop-stamp start must be idempotent first-write (T1='$T1' T2='$T2')"
  # active array preserved
  grep -q '"active": \[\]' .hv/status.json \
    || fail "F32(f): hv-loop-stamp must preserve the active array"
  # clear removes
  "$BIN/hv-loop-stamp" clear
  OUT=$("$BIN/hv-loop-stamp" read)
  [ -z "$OUT" ] || fail "F32(f): hv-loop-stamp clear must remove loopStartedAt, got '$OUT'"
)
rm -rf "$F32_TMP"
pass "F32(f): hv-loop-stamp start/clear/read"

# (g) hv-auto-decision-log: writes placeholder template + footer; idempotent on (topic, rule-title).
F32_TMP="$(mktemp -d)"
(
  cd "$F32_TMP"
  mkdir .hv
  echo "# Decisions" > .hv/DECISIONS.md
  echo "" >> .hv/DECISIONS.md
  "$BIN/hv-auto-decision-log" "Test Topic" "Test rule" "Because reasons" "M04-F32" "2026-05-09"
  grep -q '## Test Topic' .hv/DECISIONS.md \
    || fail "F32(g): topic header missing"
  grep -q '### Test rule' .hv/DECISIONS.md \
    || fail "F32(g): rule heading missing"
  grep -q '_(Unresolved — user must articulate)_' .hv/DECISIONS.md \
    || fail "F32(g): placeholder Forbids/Permits missing"
  grep -q '\[Auto:Loop\] M04-F32 2026-05-09' .hv/DECISIONS.md \
    || fail "F32(g): provenance footer missing or malformed"
  # idempotent — second run must not duplicate the entry
  "$BIN/hv-auto-decision-log" "Test Topic" "Test rule" "Because reasons" "M04-F32" "2026-05-09"
  COUNT=$(grep -c '### Test rule' .hv/DECISIONS.md)
  [ "$COUNT" = "1" ] || fail "F32(g): hv-auto-decision-log must be idempotent on (topic, rule-title), got $COUNT entries"
)
rm -rf "$F32_TMP"
pass "F32(g): hv-auto-decision-log placeholder template + idempotent"

# (h) hv-auto-decisions-since: filters by loopStartedAt date; lookup-empty when no match.
F32_TMP="$(mktemp -d)"
(
  cd "$F32_TMP"
  mkdir .hv
  cat > .hv/status.json <<'EOFJ'
{"active": [], "loopStartedAt": "2026-05-09T00:00:00Z"}
EOFJ
  cat > .hv/DECISIONS.md <<'EOFD'
# Decisions

## Topic A

### Pre-loop rule

*Why.* Decided yesterday.

**Forbids.**
- Specific thing.

**Permits.**
- Other thing.

<!-- [Auto:Loop] M04-F32 2026-05-08 — review and articulate Forbids/Permits -->

### In-loop rule

*Why.* Decided today.

**Forbids.**
- _(Unresolved — user must articulate)_

**Permits.**
- _(Unresolved — user must articulate)_

<!-- [Auto:Loop] M04-F32 2026-05-09 — review and articulate Forbids/Permits -->
EOFD
  OUT=$("$BIN/hv-auto-decisions-since")
  echo "$OUT" | grep -q 'In-loop rule' \
    || fail "F32(h): post-loopStart entry missing from output: $OUT"
  echo "$OUT" | grep -q 'Pre-loop rule' \
    && fail "F32(h): pre-loopStart entry must be filtered out: $OUT"
  echo "$OUT" | grep -q 'Forbids/Permits unresolved' \
    || fail "F32(h): unresolved status tag missing: $OUT"
  # lookup-empty when loopStartedAt is unset
  echo '{"active": []}' > .hv/status.json
  OUT=$("$BIN/hv-auto-decisions-since")
  [ -z "$OUT" ] || fail "F32(h): empty when loopStartedAt unset, got '$OUT'"
)
rm -rf "$F32_TMP"
pass "F32(h): hv-auto-decisions-since filter + lookup-empty"

# --- hvlib: parse_frontmatter & iter_map_entries -------------------
mkdir -p .hv/map
cat > .hv/map/capture.md <<'EOF'
---
subsystem: capture
summary: Captures items into TODO.md
touched: 2026-05-09
related-topics: [Skill Authoring]
---

## Purpose
One paragraph.
EOF
cat > .hv/map/plan.md <<'EOF'
---
subsystem: plan
summary: Plans before execution
touched: 2026-04-01
---
body
EOF
# malformed: no frontmatter
echo "no frontmatter here" > .hv/map/broken.md

PYTHONPATH="$BIN" python3 - <<'PY'
from hvlib import parse_frontmatter, iter_map_entries
fm, body = parse_frontmatter(open(".hv/map/capture.md").read())
assert fm["subsystem"] == "capture", fm
assert fm["summary"] == "Captures items into TODO.md", fm
assert "## Purpose" in body, body
assert fm["related-topics"] == ["Skill Authoring"], fm

# malformed body: empty frontmatter dict, full content as body
fm2, body2 = parse_frontmatter(open(".hv/map/broken.md").read())
assert fm2 == {}, fm2
assert body2.strip() == "no frontmatter here", body2

entries = list(iter_map_entries(".hv/map"))
names = sorted(e[0] for e in entries)
assert names == ["capture", "plan"], names  # malformed file is skipped
PY
echo "ok hvlib parse_frontmatter / iter_map_entries"

# --- hv-map-query --------------------------------------------------
out="$("$BIN/hv-map-query" capture)"
[[ "$out" == *"## Purpose"* ]] || { echo "FAIL: hv-map-query body missing"; exit 1; }
out="$("$BIN/hv-map-query" capture plan)"
[[ "$out" == *"## Purpose"* && "$out" == *"body"* ]] || { echo "FAIL: hv-map-query multi"; exit 1; }
out="$("$BIN/hv-map-query" nonexistent)"
[[ -z "$out" ]] || { echo "FAIL: hv-map-query missing should be empty, got: $out"; exit 1; }
echo "ok hv-map-query"

# --- hv-map-stats --------------------------------------------------
# Add an entry-point referencing this very file to test the file:line check
mkdir -p src
echo "line1" > src/sample.txt
echo "line2" >> src/sample.txt
cat > .hv/map/work.md <<'EOF'
---
subsystem: work
summary: Orchestrator-driven execution
touched: 2026-05-09
---

## Entry points
- src/sample.txt:2 — second line
- src/missing.txt:42 — broken ref
EOF
out="$("$BIN/hv-map-stats")"
echo "$out" | grep -q '"name": "capture"' || { echo "FAIL: stats missing capture"; exit 1; }
echo "$out" | grep -q '"broken_refs"' || { echo "FAIL: stats missing broken_refs"; exit 1; }
# work has 1 broken ref out of 2 entry points
echo "$out" | python3 -c '
import json, sys
data = json.load(sys.stdin)
work = next(s for s in data["subsystems"] if s["name"] == "work")
assert work["broken_refs"] == 1, work
assert work["entry_points"] == 2, work
'
echo "ok hv-map-stats"

# --- hv-map-index --------------------------------------------------
[ -f CLAUDE.md ] || : > CLAUDE.md
"$BIN/hv-map-index" >/dev/null
grep -q '<!-- hv-map-start -->' CLAUDE.md || { echo "FAIL: map block not in CLAUDE.md"; exit 1; }
grep -q '## Project Map' CLAUDE.md || { echo "FAIL: heading missing"; exit 1; }
grep -q '\*\*capture\*\* — Captures items into TODO.md' CLAUDE.md || { echo "FAIL: capture summary missing"; exit 1; }
# Idempotence
sha1=$(sha1sum CLAUDE.md | cut -d' ' -f1)
"$BIN/hv-map-index" >/dev/null
sha2=$(sha1sum CLAUDE.md | cut -d' ' -f1)
[ "$sha1" = "$sha2" ] || { echo "FAIL: hv-map-index not idempotent"; exit 1; }
# Empty case: hide the block when .hv/map/ has no valid entries
mv .hv/map .hv/map.bak
mkdir .hv/map
"$BIN/hv-map-index" >/dev/null
grep -q '_(no subsystems yet' CLAUDE.md || { echo "FAIL: empty placeholder missing"; exit 1; }
mv .hv/map .hv/map.empty
mv .hv/map.bak .hv/map
echo "ok hv-map-index"

# --- hv-staleness --------------------------------------------------
# Capture (touched 2026-04-01) is older than 30 days from "today=2026-05-09";
# work is touched 2026-05-09 and should not be flagged at days=30.
out="$("$BIN/hv-staleness" map --days 30 --today 2026-05-09)"
echo "$out" | grep -q '^plan ' || { echo "FAIL: plan should be stale"; exit 1; }
echo "$out" | grep -q '^work ' && { echo "FAIL: work should NOT be stale"; exit 1; }
# days=0 lists all
out="$("$BIN/hv-staleness" map --days 0 --today 2026-05-09)"
[ "$(echo "$out" | wc -l)" -ge 2 ] || { echo "FAIL: days=0 should list all"; exit 1; }
# Knowledge: KNOWLEDGE.md exists from bootstrap-style fixture; should not error
"$BIN/hv-staleness" knowledge --days 0 >/dev/null
echo "ok hv-staleness"

# --- hv-bootstrap seeds map ---------------------------------------
TMP2=$(mktemp -d)
trap 'rm -rf "$TMP" "$TMP2"' EXIT
(
  cd "$TMP2"
  git init -q
  "$BIN/hv-bootstrap" >/dev/null
  [ -d .hv/map ] || { echo "FAIL: .hv/map not created"; exit 1; }
  [ -f .hv/MAP.md ] || { echo "FAIL: .hv/MAP.md not seeded"; exit 1; }
  grep -q "Project map" .hv/MAP.md || { echo "FAIL: .hv/MAP.md content missing"; exit 1; }
)
echo "ok hv-bootstrap seeds map"

# --- skill touchpoints reference map ------------------------------
grep -q "hv-map-stats\|hv-map after-work" "$REPO/hv-work/SKILL.md" || { echo "FAIL: hv-work has no map touchpoint"; exit 1; }
grep -q "hv-map after-work" "$REPO/hv-debug/SKILL.md" || { echo "FAIL: hv-debug has no map after-work"; exit 1; }
grep -q "hv-map after-work" "$REPO/hv-go/SKILL.md" || { echo "FAIL: hv-go has no map after-work"; exit 1; }
echo "ok skill touchpoints (work/debug/go)"

# --- status/next/resume reference hv-staleness --------------------
# Note: hv-status and hv-resume were merged into hv-next (F26).
# All three staleness checks now target hv-next/SKILL.md.
grep -q "hv-staleness map" "$REPO/hv-next/SKILL.md"       || { echo "FAIL: hv-next missing staleness map"; exit 1; }
grep -q "hv-staleness knowledge" "$REPO/hv-next/SKILL.md" || { echo "FAIL: hv-next missing staleness knowledge"; exit 1; }
grep -q "hv-staleness todo" "$REPO/hv-next/SKILL.md"      || { echo "FAIL: hv-next missing staleness todo"; exit 1; }
grep -q "Subsystem:" "$REPO/hv-capture/SKILL.md"          || { echo "FAIL: hv-capture missing Subsystem field"; exit 1; }
echo "ok status/next/resume/capture touchpoints"

# --- end-to-end: scaffold + after-work bump + consolidate prep ----
TMP3=$(mktemp -d)
trap 'rm -rf "$TMP3" "$TMP" "$TMP2"' EXIT
(
  cd "$TMP3"
  git init -q
  git config user.email test@example.com
  git config user.name Test
  "$BIN/hv-bootstrap" >/dev/null
  : > CLAUDE.md
  cat > .hv/map/capture.md <<'EOF'
---
subsystem: capture
summary: Captures items into TODO.md
touched: 2026-05-09
created: 2026-05-09
---

## Purpose
Capture flow.

## Entry points
- bin/hv-bootstrap:1 — broken ref (file does not exist in fixture)
EOF
  cat > .hv/map/work.md <<'EOF'
---
subsystem: work
summary: Captures items into TODO.md  # near-duplicate summary
touched: 2025-12-01
created: 2025-12-01
---

## Purpose
Work flow.
EOF
  "$BIN/hv-map-index" >/dev/null

  python3 - <<'PY'
from pathlib import Path
p = Path(".hv/map/capture.md")
text = p.read_text().replace("touched: 2026-05-09", "touched: 2026-05-10")
p.write_text(text)
PY
  grep -q "touched: 2026-05-10" .hv/map/capture.md || { echo "FAIL: after-work bump"; exit 1; }

  out="$("$BIN/hv-staleness" map --days 30 --today 2026-05-10)"
  echo "$out" | grep -q "^work " || { echo "FAIL: work should be stale at days=30"; exit 1; }

  count=$("$BIN/hv-map-stats" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["subsystems"]))')
  [ "$count" = "2" ] || { echo "FAIL: stats count $count != 2"; exit 1; }

  "$BIN/hv-map-index" >/dev/null
  sha1=$(sha1sum CLAUDE.md | cut -d' ' -f1)
  "$BIN/hv-map-index" >/dev/null
  sha2=$(sha1sum CLAUDE.md | cut -d' ' -f1)
  [ "$sha1" = "$sha2" ] || { echo "FAIL: integration idempotence"; exit 1; }
)
echo "ok end-to-end map flow"

# --- parse_todo_fields handles Subsystem ---------------------------
PYTHONPATH="$BIN" python3 - <<'PY'
from hvlib import parse_todo_fields
line = "- [B07] [P1] Title. Repos: web Subsystem: capture Captured: 2026-05-09"
fields = parse_todo_fields(line)
assert fields.get("repos") == "web", f"repos={fields.get('repos')!r}"
assert fields.get("subsystem") == "capture", f"subsystem={fields.get('subsystem')!r}"

line2 = "- [B07] [P1] Title. Milestone: M01 Subsystem: capture Captured: 2026-05-09"
fields2 = parse_todo_fields(line2)
assert fields2.get("milestone") == "M01", f"milestone={fields2.get('milestone')!r}"
assert fields2.get("subsystem") == "capture", f"subsystem={fields2.get('subsystem')!r}"
PY
echo "ok parse_todo_fields handles Subsystem"

echo "hv-uncertain"
(
  UTMP="$(mktemp -d)"
  trap 'rm -rf "$UTMP"' EXIT
  mkdir -p "$UTMP/.hv/bugs" "$UTMP/.hv/features" "$UTMP/.hv/tasks"
  cd "$UTMP"

  cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features
- **[F50] [Major] Major no detail file.** Just a brief.
- **[F51] [Major] Major zero backticks.** Plain prose with no identifiers. Milestone: M01
- **[F52] [Major] Major with questions?** What about this? And this? Detail: see `code`. Milestone: M01
- **[F53] [Major] Certain item.** Use `helper` and `hvlib` to do X. Milestone: M01
- **[F54] [Minor] Minor item.** No detail file no backticks no markers. Milestone: M01

## Tasks

## Completed
EOF

  # F51: detail file present but contains zero backticks anywhere.
  cat > .hv/features/F51.md <<'EOF'
# F51 detail

Plain prose. No code spans. Just words.
EOF

  # F52: detail file present with backticks; brief already has 2+ question marks.
  cat > .hv/features/F52.md <<'EOF'
# F52 detail

Use `widget` and explain. Why?
EOF

  # F53: detail file present with backticks, no markers, 0 question marks.
  cat > .hv/features/F53.md <<'EOF'
# F53 detail

Use `helper` and `hvlib`. Concrete plan, no uncertainty.
EOF

  # F54: detail file present with backticks; should still exit 1 (Minor).
  cat > .hv/features/F54.md <<'EOF'
# F54 detail

Use `something` to do Y.
EOF

  # Item not in TODO -> exit 2.
  set +e
  out=$("$BIN/hv-uncertain" F99 2>&1); rc=$?
  set -e
  [ "$rc" = "2" ] || fail "hv-uncertain F99: expected exit 2, got $rc"
  echo "$out" | grep -q "not found" || fail "hv-uncertain F99: missing 'not found' in stderr: $out"
  pass "hv-uncertain returns 2 when item missing"

  # F50: Major, no detail file -> exit 0 with "no detail file".
  set +e
  out=$("$BIN/hv-uncertain" F50); rc=$?
  set -e
  [ "$rc" = "0" ] || fail "hv-uncertain F50: expected exit 0, got $rc"
  echo "$out" | grep -q "no detail file" || fail "hv-uncertain F50: missing 'no detail file': $out"
  # F50 also has zero backticks, so unknown-surface should also fire.
  echo "$out" | grep -q "no concrete identifiers" || fail "hv-uncertain F50: missing unknown-surface gate: $out"
  pass "hv-uncertain F50 fires no-detail-file gate"

  # F51: Major, detail file but zero backticks -> exit 0 with unknown-surface.
  set +e
  out=$("$BIN/hv-uncertain" F51); rc=$?
  set -e
  [ "$rc" = "0" ] || fail "hv-uncertain F51: expected exit 0, got $rc"
  echo "$out" | grep -q "no concrete identifiers" || fail "hv-uncertain F51: missing unknown-surface: $out"
  echo "$out" | grep -q "no detail file" && fail "hv-uncertain F51: should not fire no-detail-file: $out"
  pass "hv-uncertain F51 fires unknown-surface gate"

  # F52: Major, detail file + backticks but >=2 ? -> exit 0 with open-question signals.
  set +e
  out=$("$BIN/hv-uncertain" F52); rc=$?
  set -e
  [ "$rc" = "0" ] || fail "hv-uncertain F52: expected exit 0, got $rc"
  echo "$out" | grep -q "multiple open-question signals" || fail "hv-uncertain F52: missing open-question gate: $out"
  pass "hv-uncertain F52 fires multiple-open-question-signals gate"

  # F53: Major, detail file + backticks + 0 ? + no markers -> exit 1 (certain).
  set +e
  out=$("$BIN/hv-uncertain" F53); rc=$?
  set -e
  [ "$rc" = "1" ] || fail "hv-uncertain F53: expected exit 1 (certain), got $rc; out=$out"
  pass "hv-uncertain F53 returns 1 when certain"

  # F54: Minor, regardless of other gates -> exit 1.
  set +e
  out=$("$BIN/hv-uncertain" F54); rc=$?
  set -e
  [ "$rc" = "1" ] || fail "hv-uncertain F54: expected exit 1 (Minor), got $rc; out=$out"
  pass "hv-uncertain F54 returns 1 for Minor regardless of other gates"
)
echo "ok hv-uncertain"

echo "F37: TaskCreate progress-checklist convention"
TIER_SAB_F37=(hv-init hv-work hv-debug hv-ship hv-release \
              hv-docs hv-refactor hv-learn hv-decide hv-spike hv-vision \
              hv-capture hv-next hv-pause hv-review hv-plan hv-config hv-rm)
TIER_C_F37=(hv-assume hv-go hv-update hv-c hv-map)

for skill in "${TIER_SAB_F37[@]}"; do
  grep -q "TaskCreate(" "$REPO/$skill/SKILL.md" \
    || fail "F37: Tier S/A/B skill $skill/SKILL.md missing TaskCreate( reference"
done
pass "Tier S/A/B SKILL.md files reference TaskCreate("

for skill in "${TIER_C_F37[@]}"; do
  if grep -q "TaskCreate(" "$REPO/$skill/SKILL.md"; then
    fail "F37: Tier C skill $skill/SKILL.md unexpectedly has TaskCreate( (should be unchanged per F37 plan)"
  fi
done
pass "Tier C SKILL.md files do not reference TaskCreate("
echo "ok F37"

echo "hvlib parse_term_entry / first_sentence"
PYTHONPATH="$BIN" python3 - <<'PY'
import sys
from hvlib import parse_term_entry, first_sentence

# Term body with all three fields
body = """
The canonical project queue — `.hv/TODO.md`. Items are zero-padded IDs
([B01]/[F01]/[T01]).

**Aliases:** task list, todo list
**Not:** session state, handoff
<!-- 2026-05-10 -->
"""
parsed = parse_term_entry(body)
assert parsed["definition"].startswith("The canonical project queue"), \
    f"definition wrong: {parsed['definition']!r}"
assert parsed["aliases"] == ["task list", "todo list"], parsed["aliases"]
assert parsed["nots"] == ["session state", "handoff"], parsed["nots"]

# Term body with only definition + Aliases _none_
body2 = """
A signed Ed25519 cross-org registry entry.

**Aliases:** _none_
<!-- 2026-05-10 -->
"""
p2 = parse_term_entry(body2)
assert p2["aliases"] == [], p2["aliases"]
assert p2["nots"] == [], p2["nots"]
assert "Ed25519" in p2["definition"]

# first_sentence — short, fits in budget
assert first_sentence("Hello world. Second.") == "Hello world."
# first_sentence — over budget, ellipsis at word boundary
long = "A" + " banana" * 40 + "."
out = first_sentence(long, max_chars=40)
assert out.endswith("…"), out
assert len(out) <= 41, len(out)
# first_sentence — no terminator
assert first_sentence("no period here") == "no period here"
# first_sentence — empty
assert first_sentence("") == ""

# first_sentence — trailing comma stripped at cut boundary
# Text with no sentence terminator → full text is the "sentence"
# max_chars=12: sentence[:12]="alpha beta, " → rsplit→ cut="alpha beta,"
# rstrip(",;") strips the comma → "alpha beta…"
comma_text = "alpha beta, gamma " + ("word " * 40)
out_comma = first_sentence(comma_text, max_chars=12)
assert out_comma == "alpha beta…", f"comma not stripped: {out_comma!r}"

# Verify period NOT stripped: the narrowed rstrip(",;") preserves "." and ":"
# where the old rstrip(".,;:") would have stripped them.
# (Sentence-boundary "." is intercepted by the regex before reaching rstrip;
#  this exercises the rstrip contract directly on hypothetical cut values.)
assert "foo Mr.".rstrip(",;") == "foo Mr.", "trailing period must be preserved"
assert "foo Mr.".rstrip(".,;:") == "foo Mr", "sanity: old rstrip strips trailing period"
assert "bar:".rstrip(",;") == "bar:", "colon must be preserved"
assert "bar:".rstrip(".,;:") == "bar", "sanity: old rstrip strips trailing colon"

print("OK hvlib context helpers")
PY
pass "hvlib parse_term_entry + first_sentence"

echo "hv-bootstrap seeds CONTEXT.md"
TMP_BOOT="$(mktemp -d)"
( cd "$TMP_BOOT" && "$BIN/hv-bootstrap" >/dev/null )
[ -f "$TMP_BOOT/.hv/CONTEXT.md" ] || fail "hv-bootstrap: missing .hv/CONTEXT.md"
grep -q "^# Context$" "$TMP_BOOT/.hv/CONTEXT.md" || fail "CONTEXT.md missing header"
grep -q "no terms yet" "$TMP_BOOT/.hv/CONTEXT.md" || fail "CONTEXT.md missing placeholder"
# Idempotency: re-running doesn't overwrite existing content
echo "manual marker" >> "$TMP_BOOT/.hv/CONTEXT.md"
( cd "$TMP_BOOT" && "$BIN/hv-bootstrap" >/dev/null )
grep -q "manual marker" "$TMP_BOOT/.hv/CONTEXT.md" || fail "hv-bootstrap clobbered existing CONTEXT.md"
rm -rf "$TMP_BOOT"
pass "hv-bootstrap seeds CONTEXT.md and is idempotent"

printf '\n\033[32mAll smoke tests passed.\033[0m\n'
