echo "hv-worker-* — tmux dispatch pool, pane classifier, and merge gate"
# Covers the deterministic half of the work.dispatch=tmux backend. The TUI-facing
# half (hv-worker-dispatch driving a live session) is NOT tested here — it needs a
# real tmux server and a real Claude Code session, so it stays a manual gate. What
# IS testable:
#   (a) hv-worker-pool init/list/reap round-trip + idempotency + debris recovery;
#   (b) hv-worker-poll's classifier, fed captured pane text via --fixture;
#   (c) hv-worker-gate's freshness check and, most importantly, its post-merge
#       re-verify catching a break that BOTH branches verified green against.
#
# (c) is the section's reason for existing. Two workers with disjoint file sets,
# each honestly green, merging without a git conflict, producing a broken tree —
# that is the exact failure per-branch verification cannot structurally see, and
# it is why the gate re-verifies the MERGED tree rather than the branch.

TMP_WD="$(mktemp -d)"
trap 'rm -rf "$TMP_WD"' EXIT

mkdir -p "$TMP_WD/.hv"
(
  cd "$TMP_WD"
  git init -q -b main .
  git config user.email t@t
  git config user.name t
  printf '__pycache__/\n' > .gitignore
  cat > lib.py <<'PYEOF'
def greet(name):
    return "hi " + name
PYEOF
  cat > main.py <<'PYEOF'
from lib import greet
greet("world")
PYEOF
  git add -A
  git commit -q -m seed
) || fail "hv-worker-* fixture repo setup failed"

# ── (a) pool lifecycle ──────────────────────────────────────────────────────
( cd "$TMP_WD" && "$BIN/hv-worker-pool" init --slots 2 --base main ) \
  || fail "hv-worker-pool init failed"

ROWS=$( cd "$TMP_WD" && "$BIN/hv-worker-pool" list | wc -l | tr -d ' ' )
[ "$ROWS" = "2" ] || fail "hv-worker-pool list: expected 2 slots, got $ROWS"

[ -d "$TMP_WD/.claude/worktrees/hv-worker/w1" ] \
  || fail "hv-worker-pool init did not create the w1 worktree"
WT_BRANCH=$( git -C "$TMP_WD/.claude/worktrees/hv-worker/w1" rev-parse --abbrev-ref HEAD )
[ "$WT_BRANCH" = "hv-worker/w1" ] \
  || fail "w1 worktree is on '$WT_BRANCH', expected hv-worker/w1"
pass "hv-worker-pool init creates one worktree + branch per slot"

# Registry shape — every field /hv-work and phase 2 read must be present.
SHAPE=$( cd "$TMP_WD" && python3 -c '
import json
d = json.load(open(".hv/workers.json"))
s = d["slots"][0]
need = {"name","branch","worktree","base","window","state","task","pr","configDir"}
missing = need - set(s)
print("MISSING:" + ",".join(sorted(missing)) if missing else "OK:" + s["state"])
' )
[ "$SHAPE" = "OK:idle" ] || fail "workers.json slot shape wrong: $SHAPE"
pass "workers.json carries the full slot shape, seeded idle"

BEFORE=$( cat "$TMP_WD/.hv/workers.json" )
( cd "$TMP_WD" && "$BIN/hv-worker-pool" init --slots 2 --base main ) >/dev/null 2>&1 \
  || fail "hv-worker-pool init is not re-runnable"
AFTER=$( cat "$TMP_WD/.hv/workers.json" )
[ "$BEFORE" = "$AFTER" ] || fail "hv-worker-pool init is not idempotent — registry changed on re-run"
pass "hv-worker-pool init is idempotent on an unchanged pool"

# Debris recovery: an interrupted reap leaves a directory with no git dir.
rm -rf "$TMP_WD/.claude/worktrees/hv-worker/w2"
( cd "$TMP_WD" && "$BIN/hv-worker-pool" init --slots 2 --base main ) >/dev/null 2>&1 \
  || fail "hv-worker-pool init did not recover from a missing worktree directory"
git -C "$TMP_WD/.claude/worktrees/hv-worker/w2" rev-parse --git-dir >/dev/null 2>&1 \
  || fail "hv-worker-pool init did not rebuild the w2 worktree"
pass "hv-worker-pool init rebuilds a slot whose worktree went missing"

# ── (b) pane classifier ─────────────────────────────────────────────────────
# The critical pair is dead_overload vs alive_retry. A bare `Overloaded` on a
# static pane is a headstone; only `Retrying in` proves a retry is in flight.
# A watcher that treats them alike waits forever on a session that already died.
FX="$TMP_WD/fx"
mkdir -p "$FX"
printf 'out\nAPI Error: 529 Overloaded\n'                              > "$FX/dead_overload.txt"
printf 'out\nAPI Error: 529 Overloaded - Retrying in 8s\n'             > "$FX/alive_retry.txt"
printf 'Resume this session with claude --resume abc\n'                > "$FX/dead_resume.txt"
printf 'built\nHV-DONE w1 https://example.invalid/pull/42\n'           > "$FX/done.txt"
printf 'HV-BLOCKED w2: Show the badge on finished games or only live?\n' > "$FX/blocked.txt"
printf 'idle prompt only\n'                                            > "$FX/idle.txt"
# A worker that asked a question and THEN hit an API error is still blocked on
# the question — the sentinel is a stronger signal than the crash heuristic.
printf 'HV-BLOCKED w3: which shape?\nAPI Error: 529 Overloaded\n'      > "$FX/blocked_over_dead.txt"

classify_fixture() {
  ( cd "$TMP_WD" && "$BIN/hv-worker-poll" --fixture "$1" --slot t ) \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["state"])'
}

for CASE in "dead_overload:DEAD" "alive_retry:BUSY" "dead_resume:DEAD" \
            "done:DONE" "blocked:BLOCKED" "idle:IDLE" "blocked_over_dead:BLOCKED"; do
  NAME="${CASE%%:*}"
  WANT="${CASE#*:}"
  GOT=$( classify_fixture "$FX/$NAME.txt" )
  [ "$GOT" = "$WANT" ] || fail "hv-worker-poll classified $NAME as $GOT, expected $WANT"
done
pass "hv-worker-poll classifies all 7 pane states (bare Overloaded=DEAD, Retrying in=BUSY)"

EVID=$( ( cd "$TMP_WD" && "$BIN/hv-worker-poll" --fixture "$FX/blocked.txt" --slot w2 ) \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["evidence"])' )
case "$EVID" in
  *"badge on finished games"*) : ;;
  *) fail "hv-worker-poll did not carry the BLOCKED question into evidence: '$EVID'" ;;
esac
pass "hv-worker-poll surfaces the blocking question as evidence for relay"

# A question longer than the pane is wide must survive whole. `tmux capture-pane`
# hard-wraps at pane width, so without -J a long sentinel arrives split across
# physical lines and the classifier's `(.+)$` captures only the first — observed
# truncating a 118-char question to 42 in a 57-column pane. The user then gets
# relayed half a question, silently. Two assertions: the classifier handles a
# long single line, and both helpers actually pass -J.
LONGQ="Should finished games show the training row, or only live ones, and does that also apply to replays of ranked matches?"
printf 'HV-BLOCKED w4: %s\n' "$LONGQ" > "$FX/blocked_long.txt"
EVID=$( ( cd "$TMP_WD" && "$BIN/hv-worker-poll" --fixture "$FX/blocked_long.txt" --slot w4 ) \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["evidence"])' )
[ "$EVID" = "$LONGQ" ] \
  || fail "hv-worker-poll truncated a long BLOCKED question: got ${#EVID} chars, expected ${#LONGQ}"
for H in hv-worker-poll hv-worker-dispatch; do
  if grep -q 'capture-pane -p ' "$BIN/$H"; then
    fail "$H captures panes without -J; long sentinels will silently truncate at pane width"
  fi
  grep -q 'capture-pane -pJ' "$BIN/$H" \
    || fail "$H does not use capture-pane -pJ (join wrapped lines)"
done
pass "hv-worker-poll preserves questions longer than the pane is wide (capture-pane -J)"

# ── (c) merge gate ──────────────────────────────────────────────────────────
# Verification command imports every module present, so it naturally covers
# files that only exist after a merge.
python3 - "$TMP_WD/.hv/config.json" <<'PYEOF' || fail "could not write verifyCommands fixture config"
import json, sys
json.dump({"refactor": {"verifyCommands": [
    'for f in *.py; do python3 -c "import ${f%.py}" || exit 1; done'
]}}, open(sys.argv[1], "w"))
PYEOF

W1="$TMP_WD/.claude/worktrees/hv-worker/w1"
W2="$TMP_WD/.claude/worktrees/hv-worker/w2"

# w1 widens greet and updates its only existing caller. Files: lib.py, main.py
cat > "$W1/lib.py" <<'PYEOF'
def greet(name, greeting):
    return greeting + " " + name
PYEOF
cat > "$W1/main.py" <<'PYEOF'
from lib import greet
greet("world", "hi")
PYEOF
( cd "$W1" && git add -A && git commit -q -m "feat: widen greet" ) \
  || fail "w1 commit failed"

# w2 adds a NEW caller of the OLD signature. Files: report.py only — disjoint.
cat > "$W2/report.py" <<'PYEOF'
from lib import greet
greet("report")
PYEOF
( cd "$W2" && git add -A && git commit -q -m "feat: report" ) \
  || fail "w2 commit failed"

# Both branch trees must be independently green, or the test proves nothing.
VERIFY='for f in *.py; do python3 -c "import ${f%.py}" || exit 1; done'
( cd "$W1" && sh -c "$VERIFY" ) >/dev/null 2>&1 \
  || fail "w1 branch tree is not green — the green-on-green assertion below would be vacuous"
( cd "$W2" && sh -c "$VERIFY" ) >/dev/null 2>&1 \
  || fail "w2 branch tree is not green — the green-on-green assertion below would be vacuous"
pass "both worker branches verify green on their own trees (disjoint file sets)"

( cd "$TMP_WD" && "$BIN/hv-worker-gate" --slot w1 --base main ) >/dev/null 2>&1 \
  || fail "hv-worker-gate rejected w1, which should pass cleanly"
pass "hv-worker-gate merges a fresh slot and passes post-merge verification"

# main has moved; w2 branched before that, so its green is stale.
# `RC=$?` on its own line would never be reached — set -e aborts the section on
# the non-zero exit first. Capture through `|| RC=$?` so the failure is tested,
# not fatal (same trap as the inverted-grep rule in KNOWLEDGE.md).
RC=0
( cd "$TMP_WD" && "$BIN/hv-worker-gate" --slot w2 --base main --check-only ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "3" ] || fail "hv-worker-gate should exit 3 STALE for a slot behind base, got $RC"
pass "hv-worker-gate bounces a stale slot (exit 3) instead of merging it"

# w2 syncs. git reports no conflict — the file sets never overlapped.
( cd "$W2" && git merge -q main -m sync ) >/dev/null 2>&1 \
  || fail "w2 sync conflicted; the fixture is supposed to merge cleanly"
( cd "$TMP_WD" && "$BIN/hv-worker-gate" --slot w2 --base main --check-only ) >/dev/null 2>&1 \
  || fail "hv-worker-gate should report FRESH after w2 merged main"
pass "hv-worker-gate reports FRESH once the slot has merged its base"

# The payoff: clean merge, both branches were green, merged tree is broken.
RC=0
( cd "$TMP_WD" && "$BIN/hv-worker-gate" --slot w2 --base main ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "4" ] || fail "hv-worker-gate missed the green-on-green break: expected exit 4, got $RC"
pass "hv-worker-gate catches a merged-tree break both branches verified green against"

# Empty verifyCommands must say so rather than claim a pass it did not earn.
python3 - "$TMP_WD/.hv/config.json" <<'PYEOF' || fail "could not clear verifyCommands"
import json, sys
json.dump({"refactor": {"verifyCommands": []}}, open(sys.argv[1], "w"))
PYEOF
( cd "$TMP_WD" && "$BIN/hv-worker-pool" init --slots 3 --base main ) >/dev/null 2>&1 \
  || fail "could not add slot w3"
GATE_OUT=$( cd "$TMP_WD" && "$BIN/hv-worker-gate" --slot w3 --base main 2>/dev/null )
case "$GATE_OUT" in
  *NO-VERIFY*) : ;;
  *) fail "hv-worker-gate with empty verifyCommands must report NO-VERIFY, got: $GATE_OUT" ;;
esac
pass "hv-worker-gate reports NO-VERIFY rather than a pass it cannot back"

# ── usage contract ──────────────────────────────────────────────────────────
# Bare invocation is a usage error for pool/gate/dispatch. It is NOT one for
# hv-worker-poll — polling every slot is its default — so that helper is
# probed with a bad flag value instead.
for CMD in hv-worker-pool hv-worker-gate hv-worker-dispatch; do
  RC=0
  ( cd "$TMP_WD" && "$BIN/$CMD" ) >/dev/null 2>&1 || RC=$?
  [ "$RC" = "2" ] || fail "$CMD with no args: expected usage exit 2, got $RC"
done
RC=0
( cd "$TMP_WD" && "$BIN/hv-worker-poll" --fixture /nonexistent/pane.txt ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] || fail "hv-worker-poll with a missing fixture: expected exit 2, got $RC"
RC=0
( cd "$TMP_WD" && "$BIN/hv-worker-pool" bogus-verb ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] || fail "hv-worker-pool with an unknown verb: expected exit 2, got $RC"
pass "hv-worker-* helpers exit 2 on usage errors"

# ── reap ────────────────────────────────────────────────────────────────────
( cd "$TMP_WD" && "$BIN/hv-worker-pool" reap --all ) || fail "hv-worker-pool reap --all failed"
LEFT=$( cd "$TMP_WD" && "$BIN/hv-worker-pool" list | wc -l | tr -d ' ' )
[ "$LEFT" = "0" ] || fail "reap --all left $LEFT slots in the registry"
BRANCHES=$( git -C "$TMP_WD" branch --list 'hv-worker/*' | wc -l | tr -d ' ' )
[ "$BRANCHES" = "0" ] || fail "reap --all left $BRANCHES hv-worker/* branches behind"
if [ -d "$TMP_WD/.claude/worktrees/hv-worker/w1" ]; then
  fail "reap --all left the w1 worktree on disk"
fi
pass "hv-worker-pool reap --all removes worktrees, branches, and registry entries"

trap 'rm -rf "$TMP"' EXIT
pass "hv-worker-* tmux dispatch contract"
