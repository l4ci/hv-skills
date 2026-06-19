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
  cat > .hv/BACKLOG.md <<'EOF'
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
  install_helpers
  OUT=$(.hv/bin/hv-todo-drift)
  echo "$OUT" | grep -q '"id": "B07"' || fail "drift missing B07: $OUT"
  pass "hv-todo-drift detects shipped-but-open ID"

  # Completed (strikethrough) IDs are NOT drift — even if they appear in commits.
  cat > .hv/BACKLOG.md <<'EOF'
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

echo "hv-todo-drift Since-anchor"
SA_TMP="$(mktemp -d)"
(
  cd "$SA_TMP"
  mkdir -p .hv/bin
  install_helpers
  echo '{"repos": []}' > .hv/repos.json
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  git commit -q --allow-empty -m "init"

  # Scenario A: ID-reuse simulation. Old commit ships [B07], then a new
  # [B07] is captured AFTER. The new bullet's Since anchor must hide the
  # old commit from drift detection.
  git commit -q --allow-empty -m "feat: old shipment [B07]"
  git commit -q --allow-empty -m "chore: anchor pin"
  ANCHOR="$(git rev-parse --short HEAD)"
  cat > .hv/BACKLOG.md <<EOF
# TODO

## Bugs
- **[B07] [P1] Newcomer at this ID.** Body. Since: $ANCHOR

## Features

## Tasks

## Completed
EOF
  OUT=$(.hv/bin/hv-todo-drift)
  if echo "$OUT" | grep -q '"id": "B07"'; then
    fail "drift should NOT flag pre-anchor commit for new [B07]: $OUT"
  fi
  pass "hv-todo-drift skips commits older than Since: anchor"

  # Scenario B: a NEW commit referencing the same ID, AFTER the anchor,
  # MUST still trigger drift (the anchor is a floor, not a mute).
  git commit -q --allow-empty -m "feat: real shipment [B07]"
  OUT_B=$(.hv/bin/hv-todo-drift)
  echo "$OUT_B" | grep -q '"id": "B07"' || fail "drift missed post-anchor commit: $OUT_B"
  pass "hv-todo-drift detects commits newer than Since: anchor"

  # Scenario C: legacy entry (no Since:) preserves full-log behavior.
  cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs
- **[B07] [P1] Legacy entry.** No Since field.

## Features

## Tasks

## Completed
EOF
  OUT_C=$(.hv/bin/hv-todo-drift)
  echo "$OUT_C" | grep -q '"id": "B07"' || fail "legacy (no Since) should still drift: $OUT_C"
  pass "hv-todo-drift legacy entries keep full-log behavior"

  # Scenario D: hv-append auto-stamps Since on fresh captures.
  cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
  HEAD_AT_CAP="$(git rev-parse --short HEAD)"
  .hv/bin/hv-append "## Bugs" "- **[B08] [P2] Auto-stamp.** Body."
  grep -q "Since: $HEAD_AT_CAP" .hv/BACKLOG.md || { cat .hv/BACKLOG.md; fail "hv-append did not auto-stamp Since"; }
  pass "hv-append auto-stamps Since: <HEAD> on fresh bullets"

  # Scenario E: hv-backfill-since stamps open bullets lacking Since;
  # second invocation is idempotent (no output, no double-stamp).
  cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs
- **[B09] [P1] Needs backfill.** Body.

## Features

## Tasks

## Completed
- ~~**[B07] [P1] Completed item.**~~ Done 2026-05-07 [`abc1234`]
EOF
  COUNT=$(.hv/bin/hv-backfill-since)
  [ "$COUNT" = "1" ] || fail "backfill should report 1 stamped, got: $COUNT"
  HEAD_BF="$(git rev-parse --short HEAD)"
  grep -q "Since: $HEAD_BF" .hv/BACKLOG.md || { cat .hv/BACKLOG.md; fail "backfill did not write Since"; }
  # Completed items must NOT be touched
  grep -q "Since:.*Completed item" .hv/BACKLOG.md && fail "backfill touched ## Completed entry"
  pass "hv-backfill-since stamps open bullets lacking Since:"
  COUNT2=$(.hv/bin/hv-backfill-since)
  [ -z "$COUNT2" ] || fail "backfill not idempotent — re-ran with count: $COUNT2"
  pass "hv-backfill-since is idempotent"
)
rm -rf "$SA_TMP"

echo "hv-todo-drift symbol-drift"
SY_TMP="$(mktemp -d)"
(
  cd "$SY_TMP"
  mkdir -p .hv/bin
  install_helpers
  echo '{"repos": []}' > .hv/repos.json
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main

  # Initial commit: contains a pre-existing symbol (negative case) but NOT
  # the to-be-shipped symbol. This is the capture point.
  echo "def already_here_helper(): pass" > existing.py
  git add -A && git commit -q -m "init"
  CAP="$(git rev-parse --short HEAD)"

  # Capture two open items anchored at CAP:
  #  - B20 names widget_transcribe_pipeline — NOT in tree at CAP (positive).
  #  - B21 names already_here_helper — already in tree at CAP (negative).
  cat > .hv/BACKLOG.md <<EOF
# TODO

## Bugs
- **[B20] [P1] Wire up widget_transcribe_pipeline.** Add the new symbol. Since: $CAP
- **[B21] [P1] Touch already_here_helper.** Pre-existing symbol. Since: $CAP

## Features

## Tasks

## Completed
EOF

  # LATER commit ships widget_transcribe_pipeline WITHOUT mentioning [B20]
  # in the subject — the silent-ship scenario.
  echo "def widget_transcribe_pipeline(): pass" > pipeline.py
  git add -A && git commit -q -m "refactor: rework pipeline internals"

  OUT=$(.hv/bin/hv-todo-drift)

  # Commit-subject drift must be empty — no [B20]/[B21] in any subject.
  DRIFT_IDS=$(echo "$OUT" | python3 -c "import json,sys; print(' '.join(d['id'] for d in json.load(sys.stdin)['drift']))")
  [ -z "$DRIFT_IDS" ] || fail "commit-drift should be empty, got: $DRIFT_IDS"

  # Symbol drift must flag B20 with the symbol + file, but NOT B21.
  echo "$OUT" | python3 -c "
import json, sys
sd = json.load(sys.stdin)['symbol_drift']
by = {e['id']: e for e in sd}
assert 'B20' in by, f'B20 missing from symbol_drift: {sd}'
assert 'widget_transcribe_pipeline' in by['B20']['symbols'], by['B20']
assert 'pipeline.py' in by['B20']['files'], by['B20']
assert 'B21' not in by, f'B21 (pre-existing symbol) should NOT be flagged: {sd}'
" || fail "symbol_drift assertions failed: $OUT"
  pass "hv-todo-drift flags symbol shipped after capture, skips pre-existing symbol"

  # hv-reconcile must surface todoSymbolDrift with the B20 entry.
  echo '{"active":[]}' > .hv/status.json
  ROUT=$(.hv/bin/hv-reconcile)
  echo "$ROUT" | grep -q '"todoSymbolDrift"' || fail "reconcile missing todoSymbolDrift field: $ROUT"
  echo "$ROUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ids = {e['id'] for e in d['todoSymbolDrift']}
assert 'B20' in ids, f'B20 missing from reconcile todoSymbolDrift: {d[\"todoSymbolDrift\"]}'
" || fail "reconcile did not surface B20 symbol drift: $ROUT"
  pass "hv-reconcile surfaces todoSymbolDrift"
)
rm -rf "$SY_TMP"

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
trap 'rm -rf "$KS_TMP"' EXIT
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
  install_helpers
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
trap 'rm -rf "$TMP"' EXIT

echo "hv-knowledge-stats no KNOWLEDGE.md"
KS2_TMP="$(mktemp -d)"
trap 'rm -rf "$KS2_TMP"' EXIT
(
  cd "$KS2_TMP"
  mkdir -p .hv/bin
  install_helpers
  OUT=$(.hv/bin/hv-knowledge-stats)
  echo "$OUT" | grep -q '"topics": \[\]' || fail "missing-file should yield empty: $OUT"
  pass "hv-knowledge-stats silent-empty on missing KNOWLEDGE.md"
)
trap 'rm -rf "$TMP"' EXIT

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
trap 'rm -rf "$BOOT_TMP"' EXIT
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
trap 'rm -rf "$TMP"' EXIT

