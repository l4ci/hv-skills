echo "F36: hv-rm helper"
# Behaviour guard for bin/hv-rm across all modes.
# See [F36] — /hv-rm backlog-removal command.

# ── fixture builder ──────────────────────────────────────────────────────────
# Creates (or re-creates) the standard F36 fixture inside RM_TMP.
build_rm_fixture() {
  local root="$1"
  rm -rf "$root/.hv"
  mkdir -p "$root/.hv/features" "$root/.hv/tasks" "$root/.hv/bugs" "$root/.hv/plans"

  cat > "$root/.hv/BACKLOG.md" <<'FIXEOF'
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
  ORIG_TODO=$(cat .hv/BACKLOG.md)
  set +e
  OUT=$("$BIN/hv-rm" F01 2>/dev/null)
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F36(a): dry-run should exit 0, got $RC"; exit 1; }
  echo "$OUT" | grep -q '\[F01\] removal plan:' \
    || { echo "FAIL F36(a): stdout missing '[F01] removal plan:': $OUT"; exit 1; }
  echo "$OUT" | grep -q 'dry-run — no files modified\.' \
    || { echo "FAIL F36(a): stdout missing 'dry-run — no files modified.': $OUT"; exit 1; }
  NEW_TODO=$(cat .hv/BACKLOG.md)
  [ "$ORIG_TODO" = "$NEW_TODO" ] \
    || { echo "FAIL F36(a): dry-run must not modify BACKLOG.md"; exit 1; }
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
  grep -q '\[F01\]' .hv/BACKLOG.md \
    && { echo "FAIL F36(d): [F01] entry still in BACKLOG.md after --force"; exit 1; }
  # Related: [F01] cross-ref on B01 stripped.
  grep -q 'Related:.*\[F01\]' .hv/BACKLOG.md \
    && { echo "FAIL F36(d): Related: [F01] cross-ref still present in BACKLOG.md"; exit 1; }
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
  grep -q '\[B01\]' .hv/BACKLOG.md \
    && { echo "FAIL F36(f): [B01] still in BACKLOG.md after batch removal"; exit 1; }
  grep -q '\[T01\]' .hv/BACKLOG.md \
    && { echo "FAIL F36(f): [T01] still in BACKLOG.md after batch removal"; exit 1; }
  # F01 must still be present.
  grep -q '\[F01\]' .hv/BACKLOG.md \
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
