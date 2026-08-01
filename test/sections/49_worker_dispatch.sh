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
# Every pane capture in the tree must join wrapped lines. hv-worker-dispatch's
# captures live in the shared library, so assert against whichever files
# actually call capture-pane rather than a fixed list that rots on refactor.
CAPTURERS=$( grep -l 'capture-pane' "$BIN"/hv-worker-* "$BIN"/hv-tmux-send.sh 2>/dev/null || true )
[ -n "$CAPTURERS" ] || fail "no helper calls capture-pane — the pane classifier has gone missing"
for H in $CAPTURERS; do
  if grep -q 'capture-pane -p ' "$H"; then
    fail "$(basename "$H") captures panes without -J; long sentinels silently truncate at pane width"
  fi
  grep -q 'capture-pane -pJ' "$H" \
    || fail "$(basename "$H") calls capture-pane but not with -J (join wrapped lines)"
done
pass "hv-worker-poll preserves questions longer than the pane is wide (capture-pane -J)"

# ── (b1) tmux precondition ──────────────────────────────────────────────────
# Being inside tmux is load-bearing: outside it, worker windows land in a
# detached session nobody reads and every escalation goes unanswered. The check
# must key on $TMUX (are WE in a session) and not on `tmux has-session` (does
# one EXIST) — conflating them is what produces the silent failure.
RC=0
( cd "$TMP_WD" && env -u TMUX "$BIN/hv-worker-session" check ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "1" ] || fail "hv-worker-session check should exit 1 outside tmux, got $RC"
OUT=$( cd "$TMP_WD" && env -u TMUX "$BIN/hv-worker-session" check 2>&1 || true )
[ "$OUT" = "outside" ] || fail "hv-worker-session check should print 'outside', got '$OUT'"

# A session existing is NOT the same as being inside it. With TMUX unset the
# verdict must still be 'outside' even when a session by that name is up.
if command -v tmux >/dev/null 2>&1; then
  tmux new-session -d -s hvsmoke -c "$TMP_WD" 2>/dev/null || true
  RC=0
  ( cd "$TMP_WD" && env -u TMUX "$BIN/hv-worker-session" check --session hvsmoke ) >/dev/null 2>&1 || RC=$?
  [ "$RC" = "1" ] \
    || fail "check must key on \$TMUX, not on whether a session exists (got exit $RC with hvsmoke up)"
  tmux kill-session -t hvsmoke 2>/dev/null || true
fi
# Inside a pane, $TMUX is set — simulate that without needing a live server.
OUT=$( cd "$TMP_WD" && TMUX="/tmp/fake,1,0" "$BIN/hv-worker-session" check 2>&1 || true )
case "$OUT" in
  inside*) : ;;
  *) fail "hv-worker-session check should report 'inside ...' when \$TMUX is set, got '$OUT'" ;;
esac
RC=0
( cd "$TMP_WD" && "$BIN/hv-worker-session" bogus ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] || fail "hv-worker-session unknown verb should exit 2, got $RC"
pass "hv-worker-session detects tmux membership via \$TMUX, not session existence"

# The paste path is shared by hv-worker-dispatch and hv-worker-session. It
# carries three separate traps (bracketed-paste eating Enter, collapsed paste
# chips, unconfirmed pickup); two copies would drift.
[ -f "$BIN/hv-tmux-send.sh" ] || fail "bin/hv-tmux-send.sh (shared paste library) is missing"
for H in hv-worker-dispatch hv-worker-session; do
  grep -q 'hv-tmux-send.sh' "$BIN/$H" \
    || fail "$H does not source the shared hv-tmux-send.sh paste library"
done
# Strip comments before grepping: the callers legitimately MENTION the paste
# path in prose, and matching that reports a defect where none exists.
if sed 's/#.*//' "$BIN/hv-worker-dispatch" | grep -q 'paste-buffer'; then
  fail "hv-worker-dispatch still pastes inline; it must go through hv-tmux-send.sh"
fi
sed 's/#.*//' "$BIN/hv-tmux-send.sh" | grep -q 'paste-buffer' \
  || fail "hv-tmux-send.sh does not actually paste — the shared library is hollow"
pass "hv-worker-dispatch and hv-worker-session share one paste-and-confirm path"

# ── (b2) accounts + LIMITED ─────────────────────────────────────────────────
# Meters come from per-account fixture payloads via HV_ACCOUNT_USAGE_DIR, which
# mirrors the real OAuth usage shape. The three cases that are easy to get wrong
# are all pinned: extra_usage rescuing a spent weekly, a past reset not parking
# an account forever, and an unreadable meter rotating rather than guessing.
AFX="$TMP_WD/afx"
mkdir -p "$AFX"
python3 - "$TMP_WD/.hv/config.json" "$AFX" <<'PYEOF' || fail "could not write accounts fixture"
import json, os, sys
cfg_path, afx = sys.argv[1], sys.argv[2]
# The merge-gate block later in this section writes this file; at this point it
# may not exist yet, so start from whatever is (or isn't) there.
cfg = json.load(open(cfg_path)) if os.path.exists(cfg_path) else {}
cfg.setdefault("work", {})["accounts"] = [
    {"name": "alpha", "configDir": "/nonexistent/alpha"},
    {"name": "beta",  "configDir": "/nonexistent/beta"},
    {"name": "gamma", "configDir": "/nonexistent/gamma"},
    {"name": "delta", "configDir": "/nonexistent/delta"},
]
json.dump(cfg, open(cfg_path, "w"))
def w(name, five, five_r, seven, seven_r, extra):
    json.dump({"five_hour": {"utilization": five, "resets_at": five_r},
               "seven_day": {"utilization": seven, "resets_at": seven_r},
               "extra_usage": extra}, open(f"{afx}/{name}.json", "w"))
w("alpha", 12.0, None, 40.0, None, {"is_enabled": False})
# 5-hour spent with a FUTURE reset -> cooling
w("beta", 100.0, "2090-01-01T00:00:00+00:00", 50.0, None, {"is_enabled": False})
# weekly spent but extra usage live and under its cap -> still usable
w("gamma", 5.0, None, 100.0, "2090-01-01T00:00:00+00:00",
  {"is_enabled": True, "spend_limit_reached": False})
# 5-hour spent but the reset is in the PAST -> the window already cleared
w("delta", 100.0, "2020-01-01T00:00:00+00:00", 10.0, None, {"is_enabled": False})
PYEOF

acct() { ( cd "$TMP_WD" && HV_ACCOUNT_USAGE_DIR="$AFX" "$BIN/hv-worker-account" "$@" ); }

VERDICTS=$( acct list --json | python3 -c '
import json, sys
print(",".join(r["name"] + "=" + r["verdict"] for r in json.load(sys.stdin)))' )
[ "$VERDICTS" = "alpha=free,beta=cooling,gamma=free,delta=free" ] \
  || fail "hv-worker-account verdicts wrong: $VERDICTS"
pass "hv-worker-account: extra_usage rescues a spent weekly; a past reset does not park an account"

# gamma's weekly is discounted, so its headroom must come from the 5-hour
# window (95), not from the spent weekly (0) — otherwise a working account
# ranks last among free ones forever.
GH=$( acct list --json | python3 -c '
import json, sys
print(next(r["headroom"] for r in json.load(sys.stdin) if r["name"] == "gamma"))' )
[ "$GH" = "95.0" ] || fail "gamma headroom should be 95.0 (5h window), got $GH"
pass "hv-worker-account discounts an extra-usage-covered window from headroom"

PICKED=$( acct pick )
[ "$PICKED" = "gamma" ] || fail "pick should choose gamma (95 headroom), got $PICKED"
# An account with no readable meter is 'unknown': eligible for rotation, but
# never preferred over one with real headroom, and never treated as cooling.
rm -f "$AFX/alpha.json" "$AFX/gamma.json" "$AFX/delta.json"
UNK=$( acct list --json | python3 -c '
import json, sys
print(next(r["verdict"] for r in json.load(sys.stdin) if r["name"] == "alpha"))' )
[ "$UNK" = "unknown" ] || fail "missing meter should be unknown, got $UNK"
RC=0
acct pick >/dev/null 2>&1 || RC=$?
[ "$RC" = "0" ] || fail "pick should still rotate onto an unknown-meter account, got exit $RC"
# Every account cooling is the one case that must refuse rather than guess.
python3 - "$AFX" <<'PYEOF'
import json, sys
for n in ("alpha", "beta", "gamma", "delta"):
    json.dump({"five_hour": {"utilization": 100.0, "resets_at": "2090-01-01T00:00:00+00:00"},
               "seven_day": {"utilization": 10.0, "resets_at": None},
               "extra_usage": {"is_enabled": False}}, open(f"{sys.argv[1]}/{n}.json", "w"))
PYEOF
RC=0
acct pick >/dev/null 2>&1 || RC=$?
[ "$RC" = "3" ] || fail "pick should exit 3 when every account is cooling, got $RC"
pass "hv-worker-account rotates on unknown meters and refuses (exit 3) when all are cooling"

# LIMITED must outrank movement — a limited session can still animate a prompt,
# and reading that as BUSY strands the wave on work that cannot resume.
printf 'You have reached your usage limit. Your limit will reset at 3:00pm.\n' > "$FX/limited.txt"
printf 'You have reached your usage limit.\n 1. Stop and wait\n 2. Add funds\n'  > "$FX/limited_funds.txt"
# A worker echoing source code that happens to mention limits is NOT limited.
printf 'reading src/limits.py: MAX_LIMIT reached the cap here\n'                 > "$FX/limit_false_positive.txt"
[ "$( classify_fixture "$FX/limited.txt" )" = "LIMITED" ] \
  || fail "hv-worker-poll did not classify a usage-limit pane as LIMITED"
[ "$( classify_fixture "$FX/limit_false_positive.txt" )" = "IDLE" ] \
  || fail "hv-worker-poll false-positived LIMITED on source text mentioning limits"
FUNDS=$( ( cd "$TMP_WD" && "$BIN/hv-worker-poll" --fixture "$FX/limited_funds.txt" --slot t ) \
         | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["evidence"])' )
case "$FUNDS" in
  *"Add funds"*) : ;;
  *) fail "an 'Add funds' prompt must be flagged in the evidence (it spends money): '$FUNDS'" ;;
esac
pass "hv-worker-poll detects LIMITED, flags the money-spending prompt, and ignores lookalike prose"

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
