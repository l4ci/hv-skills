echo "F24: hv-uncomplete + hv-undo helpers"
# Behaviour guard for bin/hv-uncomplete and bin/hv-undo.
# See [F24] — `/hv-ship --undo` guided rollback of the last /hv-work cycle.

UNDO_TMP="$(mktemp -d)"
trap 'rm -rf "$UNDO_TMP"' EXIT

# ── fixture builder ──────────────────────────────────────────────────────────
# Builds a fresh miniature project at $root with:
#   - .hv/BACKLOG.md   one staged Bug, one staged Feature, empty Completed/Tasks
#   - .hv/counters.json with since_refactor.{features,bugs} = 0
#   - .hv/status.json  empty active list
#   - git init on main with a seed commit so future commits have a parent
build_undo_fixture() {
  local root="$1"
  rm -rf "$root/.hv" "$root/.git" "$root"/*.txt 2>/dev/null || true
  mkdir -p "$root/.hv"

  cat > "$root/.hv/BACKLOG.md" <<'FIXEOF'
# TODO

## Bugs
- **[B01] [P1] Sample bug.** Body.

## Features
- **[F03] [Minor] Sample feature.** Body.

## Tasks

## Completed
FIXEOF

  cat > "$root/.hv/counters.json" <<'FIXEOF'
{
  "bugs": 1,
  "features": 3,
  "tasks": 0,
  "milestones": 0,
  "since_refactor": {"features": 0, "bugs": 0, "tasks": 0}
}
FIXEOF
  echo '{"active":[]}' > "$root/.hv/status.json"

  (
    cd "$root"
    git init -q
    git config user.email t@t && git config user.name t
    git checkout -q -b main 2>/dev/null || git branch -m main
    echo seed > seed.txt
    git add -A
    git commit -q -m "seed"
  )
}

# Build a complete /hv-work cycle on $root: a feature branch hv/F03-test with
# two commits, then a no-ff merge into main with subject `merge: F03 …`.
# Writes a Completed line for F03 referencing the real implementation commit's
# short hash so hv-undo's done-line lookup succeeds.
build_undo_cycle() {
  local root="$1"
  build_undo_fixture "$root"
  (
    cd "$root"
    git checkout -q -b hv/F03-test
    echo prep > prep.txt
    git add prep.txt
    git commit -q -m "chore: prep for F03"
    echo impl > impl.txt
    git add impl.txt
    git commit -q -m "feat: implement F03"
    local SHORT
    SHORT=$(git rev-parse --short HEAD)
    git checkout -q main
    git merge --no-ff hv/F03-test -q -m "merge: F03 — test cycle"
    git branch -q -d hv/F03-test
    # F03 is now in Completed referencing the impl commit short hash.
    # Remove it from the active ## Features section and append to Completed.
    python3 - "$SHORT" <<'PYEOF'
import sys, pathlib
short = sys.argv[1]
p = pathlib.Path(".hv/BACKLOG.md")
text = p.read_text()
active = "- **[F03] [Minor] Sample feature.** Body.\n"
text = text.replace(active, "")
done = f"- ~~**[F03] [Minor] Sample feature.** Body.~~ Done 2026-01-15 [`{short}`]\n"
# Append after the ## Completed header.
text = text.replace("## Completed\n", "## Completed\n" + done)
p.write_text(text)
PYEOF
    git add .hv/BACKLOG.md
    git commit -q --amend --no-edit
  )
}

# ── (a) hv-uncomplete: restore from BACKLOG.md ## Completed, decrement counter ─
(
  cd "$UNDO_TMP"
  build_undo_fixture "$UNDO_TMP"
  # Create a real non-refactor commit so the helper can read its subject.
  echo bugfix > fix.txt
  git add fix.txt
  git commit -q -m "feat: bug fix"
  SHORT=$(git rev-parse --short HEAD)
  # Move B01 from ## Bugs into ## Completed referencing the real short hash.
  python3 - "$SHORT" <<'PYEOF'
import sys, pathlib
short = sys.argv[1]
p = pathlib.Path(".hv/BACKLOG.md")
text = p.read_text()
text = text.replace("- **[B01] [P1] Sample bug.** Body.\n", "")
done = f"- ~~**[B01] [P1] Sample bug.** Body.~~ Done 2026-01-15 [`{short}`]\n"
text = text.replace("## Completed\n", "## Completed\n" + done)
p.write_text(text)
PYEOF
  # Bump since_refactor.bugs to 1 (what hv-complete would have done).
  python3 - <<'PYEOF'
import json, pathlib
p = pathlib.Path(".hv/counters.json")
d = json.loads(p.read_text())
d["since_refactor"]["bugs"] = 1
p.write_text(json.dumps(d, indent=2) + "\n")
PYEOF

  set +e
  "$BIN/hv-uncomplete" B01 >/dev/null 2>&1
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F24(a): expected exit 0, got $RC"; exit 1; }

  # Active line restored under ## Bugs.
  grep -qE '^- \*\*\[B01\] \[P1\] Sample bug\.\*\* Body\.$' .hv/BACKLOG.md \
    || { echo "FAIL F24(a): [B01] active line not restored"; exit 1; }
  # ## Completed no longer references B01.
  if awk '/^## Completed/{f=1;next} /^## /{f=0} f' .hv/BACKLOG.md | grep -q '\[B01\]'; then
    echo "FAIL F24(a): [B01] still present under ## Completed"; exit 1
  fi
  # since_refactor.bugs decremented 1 -> 0.
  NEW=$(python3 -c "import json; print(json.load(open('.hv/counters.json'))['since_refactor']['bugs'])")
  [ "$NEW" = "0" ] || { echo "FAIL F24(a): since_refactor.bugs expected 0, got $NEW"; exit 1; }
) || exit 1

# ── (b) hv-uncomplete: restore from .hv/ARCHIVE.md ───────────────────────────
(
  cd "$UNDO_TMP"
  build_undo_fixture "$UNDO_TMP"
  # Clear the staged Feature so we can prove the active line is appended, not pre-existing.
  python3 - <<'PYEOF'
import pathlib
p = pathlib.Path(".hv/BACKLOG.md")
text = p.read_text()
text = text.replace("- **[F03] [Minor] Sample feature.** Body.\n", "")
p.write_text(text)
PYEOF
  cat > .hv/ARCHIVE.md <<'ARCHEOF'
# Archive

## Features
- ~~**[F02] [Minor] Feature title.** Detail.~~ Done 2026-01-10 [`def5678`]
ARCHEOF

  set +e
  "$BIN/hv-uncomplete" F02 >/dev/null 2>&1
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F24(b): expected exit 0, got $RC"; exit 1; }

  grep -qE '^- \*\*\[F02\] \[Minor\] Feature title\.\*\* Detail\.$' .hv/BACKLOG.md \
    || { echo "FAIL F24(b): [F02] active line not restored under ## Features"; exit 1; }
  grep -q '\[F02\]' .hv/ARCHIVE.md \
    && { echo "FAIL F24(b): [F02] still present in ARCHIVE.md"; exit 1; } \
    || true
) || exit 1

# ── (c) hv-uncomplete idempotent no-op: active already, no writes ────────────
(
  cd "$UNDO_TMP"
  build_undo_fixture "$UNDO_TMP"
  # Add B07 as already-active so uncomplete is a no-op.
  python3 - <<'PYEOF'
import pathlib
p = pathlib.Path(".hv/BACKLOG.md")
text = p.read_text()
text = text.replace("## Bugs\n- **[B01]", "## Bugs\n- **[B07] [P2] Already active.**\n- **[B01]")
p.write_text(text)
PYEOF
  BL_BEFORE=$(cat .hv/BACKLOG.md)
  CT_BEFORE=$(cat .hv/counters.json)

  set +e
  ERR=$("$BIN/hv-uncomplete" B07 2>&1 >/dev/null)
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F24(c): expected exit 0, got $RC"; exit 1; }

  [ "$BL_BEFORE" = "$(cat .hv/BACKLOG.md)" ] \
    || { echo "FAIL F24(c): BACKLOG.md changed on no-op restore"; exit 1; }
  [ "$CT_BEFORE" = "$(cat .hv/counters.json)" ] \
    || { echo "FAIL F24(c): counters.json changed on no-op restore"; exit 1; }
  echo "$ERR" | grep -qi 'noop\|no-op\|already' \
    || { echo "FAIL F24(c): stderr missing noop hint: '$ERR'"; exit 1; }
) || exit 1

# ── (d) hv-uncomplete: ID not found anywhere → exit 1, stderr 'not found' ────
(
  cd "$UNDO_TMP"
  build_undo_fixture "$UNDO_TMP"
  set +e
  ERR=$("$BIN/hv-uncomplete" B99 2>&1 >/dev/null)
  RC=$?
  set -e
  [ "$RC" = "1" ] || { echo "FAIL F24(d): expected exit 1, got $RC"; exit 1; }
  echo "$ERR" | grep -q 'not found' \
    || { echo "FAIL F24(d): stderr missing 'not found': '$ERR'"; exit 1; }
) || exit 1

# ── (e) hv-uncomplete: refactor commit subject → counter NOT decremented ────
(
  cd "$UNDO_TMP"
  build_undo_fixture "$UNDO_TMP"
  # Real refactor commit so the helper's git lookup succeeds.
  echo refac > refac.txt
  git add refac.txt
  git commit -q -m "refactor: simplify foo"
  SHORT=$(git rev-parse --short HEAD)
  # Seed Completed with F08 (NOT pre-staged in fixture) referencing the refactor short hash.
  python3 - "$SHORT" <<'PYEOF'
import sys, pathlib
short = sys.argv[1]
p = pathlib.Path(".hv/BACKLOG.md")
text = p.read_text()
done = f"- ~~**[F08] [Minor] Refactor feature.** Body.~~ Done 2026-01-15 [`{short}`]\n"
text = text.replace("## Completed\n", "## Completed\n" + done)
p.write_text(text)
PYEOF
  # Ensure since_refactor.features starts at 0 (default — refactor commits do
  # not bump on the way in, so the inverse path must skip the decrement, not
  # take features negative).
  python3 - <<'PYEOF'
import json, pathlib
p = pathlib.Path(".hv/counters.json")
d = json.loads(p.read_text())
d["since_refactor"]["features"] = 0
p.write_text(json.dumps(d, indent=2) + "\n")
PYEOF

  set +e
  "$BIN/hv-uncomplete" F08 >/dev/null 2>&1
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F24(e): expected exit 0, got $RC"; exit 1; }
  NEW=$(python3 -c "import json; print(json.load(open('.hv/counters.json'))['since_refactor']['features'])")
  [ "$NEW" = "0" ] \
    || { echo "FAIL F24(e): since_refactor.features expected 0 (decrement skipped on refactor:), got $NEW"; exit 1; }
) || exit 1

# ── (f) hv-undo dry-run: plan printed, BACKLOG + HEAD untouched ──────────────
(
  cd "$UNDO_TMP"
  build_undo_cycle "$UNDO_TMP"
  MERGE_SHORT=$(git rev-parse --short HEAD)
  BL_BEFORE=$(cat .hv/BACKLOG.md)
  HEAD_BEFORE=$(git rev-parse HEAD)

  set +e
  OUT=$("$BIN/hv-undo" 2>/dev/null)
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F24(f): dry-run expected exit 0, got $RC"; exit 1; }

  echo "$OUT" | grep -qi 'Undo plan' \
    || { echo "FAIL F24(f): stdout missing 'Undo plan': $OUT"; exit 1; }
  echo "$OUT" | grep -q "$MERGE_SHORT" \
    || { echo "FAIL F24(f): stdout missing merge short hash $MERGE_SHORT: $OUT"; exit 1; }
  echo "$OUT" | grep -q 'F03' \
    || { echo "FAIL F24(f): stdout missing 'F03' id: $OUT"; exit 1; }
  echo "$OUT" | grep -q 'Re-run with --force to apply' \
    || { echo "FAIL F24(f): stdout missing 'Re-run with --force to apply': $OUT"; exit 1; }

  [ "$BL_BEFORE" = "$(cat .hv/BACKLOG.md)" ] \
    || { echo "FAIL F24(f): dry-run modified BACKLOG.md"; exit 1; }
  [ "$(git rev-parse HEAD)" = "$HEAD_BEFORE" ] \
    || { echo "FAIL F24(f): dry-run moved HEAD"; exit 1; }
) || exit 1

# ── (g) hv-undo: no merge commit on base → exit 1, stderr 'no merge' ────────
(
  cd "$UNDO_TMP"
  build_undo_fixture "$UNDO_TMP"
  set +e
  ERR=$("$BIN/hv-undo" 2>&1 >/dev/null)
  RC=$?
  set -e
  [ "$RC" = "1" ] || { echo "FAIL F24(g): expected exit 1, got $RC"; exit 1; }
  echo "$ERR" | grep -qi 'no merge' \
    || { echo "FAIL F24(g): stderr missing 'no merge': '$ERR'"; exit 1; }
) || exit 1

# ── (h) hv-undo: dirty tree → exit 2 ─────────────────────────────────────────
(
  cd "$UNDO_TMP"
  build_undo_cycle "$UNDO_TMP"
  echo dirty >> seed.txt
  set +e
  "$BIN/hv-undo" >/dev/null 2>&1
  RC=$?
  set -e
  [ "$RC" = "2" ] || { echo "FAIL F24(h): dirty tree expected exit 2, got $RC"; exit 1; }
) || exit 1

# ── (i) hv-undo --force round-trip: HEAD rolled back, BACKLOG restored ──────
# ── (j) hv-undo idempotent no-op after apply: exit 1 + 'no merge' ───────────
(
  cd "$UNDO_TMP"
  build_undo_cycle "$UNDO_TMP"
  BEFORE_HEAD=$(git rev-parse HEAD)
  EXPECTED_HEAD=$(git rev-parse HEAD^1)

  set +e
  "$BIN/hv-undo" --force >/dev/null 2>&1
  RC=$?
  set -e
  [ "$RC" = "0" ] || { echo "FAIL F24(i): --force expected exit 0, got $RC"; exit 1; }

  AFTER=$(git rev-parse HEAD)
  [ "$AFTER" = "$EXPECTED_HEAD" ] \
    || { echo "FAIL F24(i): HEAD expected $EXPECTED_HEAD (pre-merge), got $AFTER (was $BEFORE_HEAD)"; exit 1; }

  grep -qE '^- \*\*\[F03\]' .hv/BACKLOG.md \
    || { echo "FAIL F24(i): [F03] active line not restored under ## Features"; exit 1; }
  if awk '/^## Completed/{f=1;next} /^## /{f=0} f' .hv/BACKLOG.md | grep -q '\[F03\]'; then
    echo "FAIL F24(i): [F03] still present under ## Completed after rollback"; exit 1
  fi

  # (j) Re-run on the now-rolled-back tree: no merge commit remains, exit 1.
  set +e
  ERR=$("$BIN/hv-undo" 2>&1 >/dev/null)
  RC=$?
  set -e
  [ "$RC" = "1" ] || { echo "FAIL F24(j): post-apply expected exit 1, got $RC"; exit 1; }
  echo "$ERR" | grep -qi 'no merge' \
    || { echo "FAIL F24(j): stderr missing 'no merge' on post-apply re-run: '$ERR'"; exit 1; }
) || exit 1

# ── (k) hv-undo: non-`merge:` subject refused → exit 1 ──────────────────────
(
  cd "$UNDO_TMP"
  build_undo_fixture "$UNDO_TMP"
  git checkout -q -b hv/F99-other
  echo other > other.txt
  git add other.txt
  git commit -q -m "feat: other branch"
  git checkout -q main
  # GitHub-style merge commit subject — NOT 'merge: '.
  git merge --no-ff hv/F99-other -q -m "Merge pull request #1 from foo"
  git branch -q -d hv/F99-other

  set +e
  ERR=$("$BIN/hv-undo" 2>&1 >/dev/null)
  RC=$?
  set -e
  [ "$RC" = "1" ] || { echo "FAIL F24(k): non-hv merge expected exit 1, got $RC"; exit 1; }
  echo "$ERR" | grep -qEi 'merge:|not an hv-skills|no merge' \
    || { echo "FAIL F24(k): stderr missing merge:/not-an-hv-skills hint: '$ERR'"; exit 1; }
) || exit 1

trap 'rm -rf "$TMP"' EXIT
rm -rf "$UNDO_TMP"
pass "F24 hv-uncomplete + hv-undo helper smoke"
