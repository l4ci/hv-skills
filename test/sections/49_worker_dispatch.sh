echo "worker verbs — tmux dispatch pool, pane classifier, and merge gate"
# Covers the deterministic half of the work.dispatch=tmux backend. The TUI-facing
# half (`hv worker dispatch` driving a live session) is NOT tested here — it needs a
# real tmux server and a real Claude Code session, so it stays a manual gate. What
# IS testable:
#   (a) `worker pool` init/list/reap round-trip + idempotency + debris recovery;
#   (b) `worker poll`'s classifier, fed captured pane text via --fixture;
#   (c) `worker gate`'s freshness check and, most importantly, its post-merge
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
) || fail "worker verbs fixture repo setup failed"

# ── (a) pool lifecycle ──────────────────────────────────────────────────────
( cd "$TMP_WD" && "$HV_BIN" worker pool init --slots 2 --base main ) \
  || fail "worker pool init failed"

ROWS=$( cd "$TMP_WD" && "$HV_BIN" --json worker pool list \
        | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["slots"]))' )
[ "$ROWS" = "2" ] || fail "worker pool list: expected 2 slots, got $ROWS"

[ -d "$TMP_WD/.worktrees/w1" ] \
  || fail "worker pool init did not create the w1 worktree"
WT_BRANCH=$( git -C "$TMP_WD/.worktrees/w1" rev-parse --abbrev-ref HEAD )
[ "$WT_BRANCH" = "hv-worker/w1" ] \
  || fail "w1 worktree is on '$WT_BRANCH', expected hv-worker/w1"
pass "worker pool init creates one worktree + branch per slot"

# Registry shape — every field /hv-work and phase 2 read must be present.
SHAPE=$( cd "$TMP_WD" && python3 -c '
import json
d = json.load(open(".hv/workers.json"))
s = d["slots"][0]
need = {"name","branch","worktree","base","handle","state","task","pr","configDir"}
missing = need - set(s)
print("MISSING:" + ",".join(sorted(missing)) if missing else "OK:" + s["state"] + ":" + s["handle"])
' )
[ "$SHAPE" = "OK:idle:hv:w1" ] || fail "workers.json slot shape wrong: $SHAPE"
pass "workers.json carries the full slot shape, seeded idle, tmux handle <session>:<slot>"

BEFORE=$( cat "$TMP_WD/.hv/workers.json" )
( cd "$TMP_WD" && "$HV_BIN" worker pool init --slots 2 --base main ) >/dev/null 2>&1 \
  || fail "worker pool init is not re-runnable"
AFTER=$( cat "$TMP_WD/.hv/workers.json" )
[ "$BEFORE" = "$AFTER" ] || fail "worker pool init is not idempotent — registry changed on re-run"
pass "worker pool init is idempotent on an unchanged pool"

# Debris recovery: an interrupted reap leaves a directory with no git dir.
rm -rf "$TMP_WD/.worktrees/w2"
( cd "$TMP_WD" && "$HV_BIN" worker pool init --slots 2 --base main ) >/dev/null 2>&1 \
  || fail "worker pool init did not recover from a missing worktree directory"
git -C "$TMP_WD/.worktrees/w2" rev-parse --git-dir >/dev/null 2>&1 \
  || fail "worker pool init did not rebuild the w2 worktree"
pass "worker pool init rebuilds a slot whose worktree went missing"

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
  ( cd "$TMP_WD" && HV_TEST_POLL_FIXTURE="$1" "$HV_BIN" --json worker poll t ) \
    | jget 'data.slots[0].state'
}

for CASE in "dead_overload:dead" "alive_retry:busy" "dead_resume:dead" \
            "done:done" "blocked:blocked" "idle:idle" "blocked_over_dead:blocked"; do
  NAME="${CASE%%:*}"
  WANT="${CASE#*:}"
  GOT=$( classify_fixture "$FX/$NAME.txt" )
  [ "$GOT" = "$WANT" ] || fail "worker poll classified $NAME as $GOT, expected $WANT"
done
pass "worker poll classifies all 7 pane states (bare Overloaded=DEAD, Retrying in=BUSY)"

EVID=$( ( cd "$TMP_WD" && HV_TEST_POLL_FIXTURE="$FX/blocked.txt" "$HV_BIN" --json worker poll w2 ) \
        | jget 'data.slots[0].evidence' )
case "$EVID" in
  *"badge on finished games"*) : ;;
  *) fail "worker poll did not carry the BLOCKED question into evidence: '$EVID'" ;;
esac
pass "worker poll surfaces the blocking question as evidence for relay"

# A question longer than the pane is wide must survive whole. `tmux capture-pane`
# hard-wraps at pane width, so without -J a long sentinel arrives split across
# physical lines and the classifier's `(.+)$` captures only the first — observed
# truncating a 118-char question to 42 in a 57-column pane. The user then gets
# relayed half a question, silently. Two assertions: the classifier handles a
# long single line, and both helpers actually pass -J.
LONGQ="Should finished games show the training row, or only live ones, and does that also apply to replays of ranked matches?"
printf 'HV-BLOCKED w4: %s\n' "$LONGQ" > "$FX/blocked_long.txt"
EVID=$( ( cd "$TMP_WD" && HV_TEST_POLL_FIXTURE="$FX/blocked_long.txt" "$HV_BIN" --json worker poll w4 ) \
        | jget 'data.slots[0].evidence' )
[ "$EVID" = "$LONGQ" ] \
  || fail "worker poll truncated a long BLOCKED question: got ${#EVID} chars, expected ${#LONGQ}"
# Every pane capture in the tree must join wrapped lines. hv-worker-dispatch's
# captures live in the shared library, so assert against whichever files
# actually call capture-pane rather than a fixed list that rots on refactor.
# white-box-begin: go-unit A7 #51
CAPTURERS=$( grep -l 'capture-pane' "$BIN"/hv-worker-* "$BIN"/hv-host-tmux.sh 2>/dev/null || true )
[ -n "$CAPTURERS" ] || fail "no helper calls capture-pane — the pane classifier has gone missing"
for H in $CAPTURERS; do
  if grep -q 'capture-pane -p ' "$H"; then
    fail "$(basename "$H") captures panes without -J; long sentinels silently truncate at pane width"
  fi
  grep -q 'capture-pane -pJ' "$H" \
    || fail "$(basename "$H") calls capture-pane but not with -J (join wrapped lines)"
done
pass "worker poll preserves questions longer than the pane is wide (capture-pane -J)"
# white-box-end

# ── (b1) tmux precondition ──────────────────────────────────────────────────
# Being inside tmux is load-bearing: outside it, worker windows land in a
# detached session nobody reads and every escalation goes unanswered. The check
# must key on $TMUX (are WE in a session) and not on `tmux has-session` (does
# one EXIST) — conflating them is what produces the silent failure.
RC=0
OUT=$( cd "$TMP_WD" && env -u TMUX "$HV_BIN" --json worker session check 2>/dev/null ) || RC=$?
[ "$RC" = "1" ] || fail "worker session check should exit 1 outside tmux, got $RC"
[ "$(jget data.inside <<<"$OUT")" = "false" ] || fail "worker session check should answer inside=false outside tmux, got '$OUT'"

# A session existing is NOT the same as being inside it. With TMUX unset the
# verdict must still be 'outside' even when a session by that name is up. A fake
# tmux answers every call with success (so has-session says the session
# exists); the real tmux server is never touched (the runner's guard fails the
# run if it is).
mkdir -p "$TMP_WD/faketmux"
printf '#!/bin/sh\necho "$*" >> "%s/faketmux/log"\nexit 0\n' "$TMP_WD" > "$TMP_WD/faketmux/tmux"
chmod +x "$TMP_WD/faketmux/tmux"
RC=0
( cd "$TMP_WD" && PATH="$TMP_WD/faketmux:$PATH" env -u TMUX "$HV_BIN" worker session check --session hvsmoke ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "1" ] \
  || fail "check must key on \$TMUX, not on whether a session exists (got exit $RC with hvsmoke up)"
# Inside a pane, $TMUX is set — simulate that without needing a live server.
OUT=$( cd "$TMP_WD" && PATH="$TMP_WD/faketmux:$PATH" TMUX="/tmp/fake,1,0" "$HV_BIN" --json worker session check ) \
  || fail "worker session check should exit 0 when \$TMUX is set"
[ "$(jget data.inside <<<"$OUT")" = "true" ] || fail "worker session check should report inside when \$TMUX is set, got '$OUT'"
RC=0
( cd "$TMP_WD" && "$HV_BIN" worker session bogus ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] || fail "worker session unknown verb should exit 2, got $RC"
pass "worker session detects tmux membership via \$TMUX, not session existence"

# The paste path is shared by hv-worker-dispatch and hv-worker-session through
# the host libs. It carries three separate traps (bracketed-paste eating Enter,
# collapsed paste chips, unconfirmed pickup); two copies would drift.
# white-box-begin: A9 #53 keep
[ -f "$BIN/hv-host-tmux.sh" ] || fail "bin/hv-host-tmux.sh (tmux host library) is missing"
if [ -e "$BIN/hv-tmux-send.sh" ]; then
  fail "bin/hv-tmux-send.sh is back; hv-host-tmux.sh absorbed it"
fi
# white-box-end
# white-box-begin: go-unit A7 #51
for H in hv-worker-dispatch hv-worker-session hv-worker-poll; do
  grep -q 'hv-host-select.sh' "$BIN/$H" \
    || fail "$H does not pick its host through hv-host-select.sh"
done
# Strip comments before grepping: the callers legitimately MENTION the paste
# path in prose, and matching that reports a defect where none exists.
for H in hv-worker-dispatch hv-worker-session hv-worker-poll; do
  SRC=$(sed 's/#.*//' "$BIN/$H") || fail "cannot read $H"
  if grep -q 'paste-buffer\|capture-pane\|herdr \(tab\|agent\|notification\)' <<<"$SRC"; then
    fail "$H talks to a host directly; it must go through the hv_host_* primitives"
  fi
done
SRC=$(sed 's/#.*//' "$BIN/hv-host-tmux.sh") || fail "cannot read hv-host-tmux.sh"
grep -q 'paste-buffer' <<<"$SRC" \
  || fail "hv-host-tmux.sh does not actually paste — the shared library is hollow"
pass "worker helpers share one paste-and-confirm path through the host libs"
# white-box-end

# Workers and the operator run at deliberately different trust levels. Both
# defaults are pinned because a silent drift either way is bad: narrowing the
# worker stalls it mid-task on an unattended pane, and widening the operator
# removes the gate on the process that merges into the cycle branch.
# white-box-begin: go-unit A7 #51
grep -q 'dangerously-skip-permissions' "$BIN/hv-worker-dispatch" \
  || fail "worker default must skip permissions — a narrower mode stalls an unattended worker mid-task"
if grep -q 'dangerously-skip-permissions' "$BIN/hv-worker-session"; then
  fail "the operator must NOT skip permissions; it merges into the cycle branch and a human watches it"
fi
grep -q 'permission-mode auto' "$BIN/hv-worker-session" \
  || fail "operator default must set --permission-mode auto"
grep -q 'continue' "$BIN/hv-worker-session" \
  || fail "operator default must use --continue so the handoff keeps the cycle's context"
# Both are overridable, or a project could never narrow the grant.
grep -q 'workerCommand' "$BIN/hv-worker-dispatch" \
  || fail "work.workerCommand override missing from worker dispatch"
grep -q 'operatorCommand' "$BIN/hv-worker-session" \
  || fail "work.operatorCommand override missing from worker session"
pass "worker skips permissions, operator runs auto, both overridable via config"
# white-box-end

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

acct() { ( cd "$TMP_WD" && HV_ACCOUNT_USAGE_DIR="$AFX" "$HV_BIN" --json worker account "$@" ); }

VERDICTS=$( acct list | python3 -c '
import json, sys
print(",".join(r["name"] + "=" + r["verdict"] for r in json.load(sys.stdin)["data"]["accounts"]))' )
[ "$VERDICTS" = "alpha=free,beta=cooling,gamma=free,delta=free" ] \
  || fail "worker account verdicts wrong: $VERDICTS"
pass "worker account list: extra_usage rescues a spent weekly; a past reset does not park an account"

# gamma's weekly is discounted, so its headroom must come from the 5-hour
# window (95), not from the spent weekly (0) — otherwise a working account
# ranks last among free ones forever.
GH=$( acct list | python3 -c '
import json, sys
print(next(r["headroom"] for r in json.load(sys.stdin)["data"]["accounts"] if r["name"] == "gamma"))' )
[ "$GH" = "95.0" ] || fail "gamma headroom should be 95.0 (5h window), got $GH"
pass "worker account list discounts an extra-usage-covered window from headroom"

PICKED=$( acct pick | jget data.account )
[ "$PICKED" = "gamma" ] || fail "pick should choose gamma (95 headroom), got $PICKED"
# An account with no readable meter is 'unknown': eligible for rotation, but
# never preferred over one with real headroom, and never treated as cooling.
rm -f "$AFX/alpha.json" "$AFX/gamma.json" "$AFX/delta.json"
UNK=$( acct list | python3 -c '
import json, sys
print(next(r["verdict"] for r in json.load(sys.stdin)["data"]["accounts"] if r["name"] == "alpha"))' )
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
OUT=$(acct pick 2>/dev/null) || RC=$?
[ "$RC" = "1" ] || fail "pick should exit 1 when every account is cooling, got $RC"
[ "$(jget data.found <<<"$OUT")" = "false" ] || fail "pick must answer found=false when every account is cooling, got '$OUT'"
pass "worker account pick rotates on unknown meters and refuses (exit 1, found=false) when all are cooling"

# LIMITED must outrank movement — a limited session can still animate a prompt,
# and reading that as BUSY strands the wave on work that cannot resume.
printf 'You have reached your usage limit. Your limit will reset at 3:00pm.\n' > "$FX/limited.txt"
printf 'You have reached your usage limit.\n 1. Stop and wait\n 2. Add funds\n'  > "$FX/limited_funds.txt"
# A worker echoing source code that happens to mention limits is NOT limited.
printf 'reading src/limits.py: MAX_LIMIT reached the cap here\n'                 > "$FX/limit_false_positive.txt"
[ "$( classify_fixture "$FX/limited.txt" )" = "limited" ] \
  || fail "worker poll did not classify a usage-limit pane as LIMITED"
[ "$( classify_fixture "$FX/limit_false_positive.txt" )" = "idle" ] \
  || fail "worker poll false-positived LIMITED on source text mentioning limits"
FUNDS=$( ( cd "$TMP_WD" && HV_TEST_POLL_FIXTURE="$FX/limited_funds.txt" "$HV_BIN" --json worker poll t ) \
         | jget 'data.slots[0].evidence' )
case "$FUNDS" in
  *"Add funds"*) : ;;
  *) fail "an 'Add funds' prompt must be flagged in the evidence (it spends money): '$FUNDS'" ;;
esac
pass "worker poll detects LIMITED, flags the money-spending prompt, and ignores lookalike prose"

# A worker stopped at a permission prompt is indistinguishable from an idle one
# by shape: static pane, no sentinel, no error. Reported as IDLE, the
# orchestrator waits forever on a worker that is itself waiting on a human.
printf 'Bash(git commit -m "feat: x")\n\nDo you want to proceed?\n 1. Yes\n 2. No, and tell Claude what to do differently\n' > "$FX/perm.txt"
printf 'Allow Bash to run `gh pr create`?\n 1. Yes\n 2. No\n' > "$FX/perm_allow.txt"
[ "$( classify_fixture "$FX/perm.txt" )" = "needs-permission" ] \
  || fail "a pane stopped at a permission prompt must not report IDLE"
[ "$( classify_fixture "$FX/perm_allow.txt" )" = "needs-permission" ] \
  || fail "an 'Allow ... to run' prompt must report NEEDS-PERMISSION"
# The design-question sentinel still outranks it: a worker that asked something
# AND hit a prompt needs its question answered, which unblocks both.
printf 'HV-BLOCKED w1: which shape?\nDo you want to proceed?\n' > "$FX/perm_vs_blocked.txt"
[ "$( classify_fixture "$FX/perm_vs_blocked.txt" )" = "blocked" ] \
  || fail "HV-BLOCKED must outrank a permission prompt"
pass "worker poll reports NEEDS-PERMISSION instead of mistaking a stalled worker for idle"

# ── (c) merge gate ──────────────────────────────────────────────────────────
# Verification command imports every module present, so it naturally covers
# files that only exist after a merge.
python3 - "$TMP_WD/.hv/config.json" <<'PYEOF' || fail "could not write verifyCommands fixture config"
import json, sys
json.dump({"refactor": {"verifyCommands": [
    'for f in *.py; do python3 -c "import ${f%.py}" || exit 1; done'
]}}, open(sys.argv[1], "w"))
PYEOF

W1="$TMP_WD/.worktrees/w1"
W2="$TMP_WD/.worktrees/w2"

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

GATE_OUT=$( cd "$TMP_WD" && "$HV_BIN" --json worker gate w1 --base main 2>/dev/null ) \
  || fail "worker gate rejected w1, which should pass cleanly: $GATE_OUT"
[ "$(jget data.verdict <<<"$GATE_OUT")" = "pass" ] || fail "worker gate should pass w1, got: $GATE_OUT"
pass "worker gate merges a fresh slot and passes post-merge verification"

# main has moved; w2 branched before that, so its green is stale.
# `RC=$?` on its own line would never be reached — set -e aborts the section on
# the non-zero exit first. Capture through `|| RC=$?` so the failure is tested,
# not fatal (same trap as the inverted-grep rule in KNOWLEDGE.md).
RC=0
GATE_OUT=$( cd "$TMP_WD" && "$HV_BIN" --json worker gate w2 --base main --check-only 2>/dev/null ) || RC=$?
[ "$RC" = "1" ] || fail "worker gate should exit 1 for a slot behind base, got $RC"
[ "$(jget data.verdict <<<"$GATE_OUT")" = "stale" ] || fail "worker gate should answer verdict=stale for a slot behind base, got: $GATE_OUT"
pass "worker gate bounces a stale slot (exit 1, verdict stale) instead of merging it"

# w2 syncs. git reports no conflict — the file sets never overlapped.
( cd "$W2" && git merge -q main -m sync ) >/dev/null 2>&1 \
  || fail "w2 sync conflicted; the fixture is supposed to merge cleanly"
GATE_OUT=$( cd "$TMP_WD" && "$HV_BIN" --json worker gate w2 --base main --check-only 2>/dev/null ) \
  || fail "worker gate should report fresh after w2 merged main: $GATE_OUT"
[ "$(jget data.verdict <<<"$GATE_OUT")" = "fresh" ] || fail "worker gate should answer verdict=fresh after w2 merged main, got: $GATE_OUT"
[ "$(jget data.sha <<<"$GATE_OUT")" = "$(git -C "$W2" rev-parse --short=7 HEAD)" ] \
  || fail "worker gate fresh should report the checked branch tip as data.sha, got: $GATE_OUT"
pass "worker gate reports FRESH once the slot has merged its base"

# The payoff: clean merge, both branches were green, merged tree is broken.
RC=0
GATE_OUT=$( cd "$TMP_WD" && "$HV_BIN" --json worker gate w2 --base main 2>/dev/null ) || RC=$?
[ "$RC" = "1" ] || fail "worker gate missed the green-on-green break: expected exit 1, got $RC"
[ "$(jget data.verdict <<<"$GATE_OUT")" = "verify-failed" ] || fail "worker gate should answer verdict=verify-failed on the merged-tree break, got: $GATE_OUT"
pass "worker gate catches a merged-tree break both branches verified green against"

# Empty verifyCommands must say so rather than claim a pass it did not earn.
python3 - "$TMP_WD/.hv/config.json" <<'PYEOF' || fail "could not clear verifyCommands"
import json, sys
json.dump({"refactor": {"verifyCommands": []}}, open(sys.argv[1], "w"))
PYEOF
( cd "$TMP_WD" && "$HV_BIN" worker pool init --slots 3 --base main ) >/dev/null 2>&1 \
  || fail "could not add slot w3"
GATE_OUT=$( cd "$TMP_WD" && "$HV_BIN" --json worker gate w3 --base main 2>/dev/null )
[ "$(jget data.verifySkipped <<<"$GATE_OUT")" = "true" ] \
  || fail "worker gate with empty verifyCommands must report verifySkipped, got: $GATE_OUT"
pass "worker gate reports verifySkipped rather than a pass it cannot back"

# ── (c1) provenance check ───────────────────────────────────────────────────
# The PR body comes from a fake `gh`; the relay log is written straight into the
# registry, the way worker dispatch --relay does. Slot w3 is fresh against main.
FAKEBIN="$TMP_WD/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gh" <<'SH'
#!/usr/bin/env bash
if [ "$1 $2" = "pr view" ]; then
  case "$*" in
    *headRefName*) printf '{"headRefName":"%s","headRefOid":"%s","baseRefName":"main","state":"OPEN","mergeCommit":null}\n' "$FAKE_PR_HEAD" "$FAKE_PR_SHA" ;;
    *) cat "$FAKE_PR_BODY" ;;
  esac
fi
SH
chmod +x "$FAKEBIN/gh"
# A recorded PR needs an origin (the gate refuses a local merge of a PR), and the
# fake gh must report the pushed branch as the PR head.
git init -q --bare -b main "$TMP_WD/.hv/origin.git"
W3_BRANCH="$(python3 -c 'import json,sys; print([s for s in json.load(open(sys.argv[1]))["slots"] if s["name"]=="w3"][0]["branch"])' "$TMP_WD/.hv/workers.json")"
( cd "$TMP_WD" && git remote add origin "$TMP_WD/.hv/origin.git" && git push -q origin main "$W3_BRANCH" ) \
  || fail "could not push the provenance fixture to its origin"
FAKE_PR_HEAD="$W3_BRANCH"; FAKE_PR_SHA="$(git -C "$TMP_WD" rev-parse "$W3_BRANCH")"
set_relays() {
  python3 - "$TMP_WD/.hv/workers.json" "$1" <<'PYEOF' || fail "could not write relays fixture"
import json, sys
d = json.load(open(sys.argv[1]))
s = [s for s in d["slots"] if s["name"] == "w3"][0]
s["pr"] = "7"
s["relays"] = json.loads(sys.argv[2])
json.dump(d, open(sys.argv[1], "w"))
PYEOF
}
prov() {  # prov <body> -> "<exit code>:<verdict>" of the check
  printf '%s' "$1" > "$TMP_WD/pr_body.md"
  local rc=0
  ( cd "$TMP_WD" && PATH="$FAKEBIN:$PATH" FAKE_PR_BODY="$TMP_WD/pr_body.md" FAKE_PR_HEAD="$FAKE_PR_HEAD" FAKE_PR_SHA="$FAKE_PR_SHA" \
      "$HV_BIN" --json worker gate w3 --base main --check-only ) >"$TMP_WD/prov.out" 2>"$TMP_WD/prov.err" || rc=$?
  echo "$rc:$(jget data.verdict <"$TMP_WD/prov.out" || true)"
}
RELAYS='[{"round":2,"ts":"2026-10-01T08:00:00Z","summary":"use the per-user cache"}]'
set_relays "$RELAYS"
[ "$(prov $'## Summary\nx\n\n## Approvals\n- per-user cache: orchestrator relay round 2\n- naming of flag: my call, unratified\n')" = "0:fresh" ] \
  || fail "a correctly cited relay must pass: $(cat "$TMP_WD/prov.out")"
[ "$(prov $'## Approvals\n- use the per-user cache: maintainer in pane\n')" = "1:provenance-fail" ] \
  || fail "a relay cited as the maintainer must fail with verdict provenance-fail (inflation)"
[ "$(prov $'## Approvals\n- drop the legacy path: orchestrator relay round 9\n')" = "1:provenance-fail" ] \
  || fail "a relay round that was never logged must fail (deflation)"
[ "$(prov $'## Summary\nno approvals here\n')" = "1:provenance-fail" ] \
  || fail "no ## Approvals section with a relay recorded must fail"
[ "$(prov $'## Approvals\n- schema choice: maintainer in pane\n')" = "0:fresh" ] \
  || fail "a maintainer citation that matches no relay must pass"
set_relays '[]'
[ "$(prov $'## Summary\nno approvals needed\n')" = "0:fresh" ] \
  || fail "no relays and no section must pass: $(cat "$TMP_WD/prov.out")"
pass "worker gate --check-only exits 1 with verdict provenance-fail on inflation, deflation and a missing section"

# ── usage contract ──────────────────────────────────────────────────────────
# Bare invocation is a usage error for pool/gate/dispatch. It is NOT one for
# worker poll — polling every slot is its default — so that verb is
# probed with a missing fixture instead.
for CMD in "worker pool" "worker gate" "worker dispatch"; do
  RC=0
  ( cd "$TMP_WD" && "$HV_BIN" $CMD ) >/dev/null 2>&1 || RC=$?
  [ "$RC" = "2" ] || fail "$CMD with no args: expected usage exit 2, got $RC"
done
RC=0
( cd "$TMP_WD" && HV_TEST_POLL_FIXTURE=/nonexistent/pane.txt "$HV_BIN" worker poll ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] || fail "worker poll with a missing fixture: expected exit 2, got $RC"
RC=0
( cd "$TMP_WD" && "$HV_BIN" worker pool bogus-verb ) >/dev/null 2>&1 || RC=$?
[ "$RC" = "2" ] || fail "worker pool with an unknown verb: expected exit 2, got $RC"
pass "worker verbs helpers exit 2 on usage errors"

# ── reap ────────────────────────────────────────────────────────────────────
( cd "$TMP_WD" && "$HV_BIN" worker pool reap --all ) || fail "worker pool reap --all failed"
LEFT=$( cd "$TMP_WD" && "$HV_BIN" --json worker pool list \
        | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["slots"]))' )
[ "$LEFT" = "0" ] || fail "reap --all left $LEFT slots in the registry"
BRANCHES=$( git -C "$TMP_WD" branch --list 'hv-worker/*' | wc -l | tr -d ' ' )
[ "$BRANCHES" = "0" ] || fail "reap --all left $BRANCHES hv-worker/* branches behind"
if [ -d "$TMP_WD/.worktrees/w1" ]; then
  fail "reap --all left the w1 worktree on disk"
fi
pass "worker pool reap --all removes worktrees, branches, and registry entries"

trap 'rm -rf "$TMP"' EXIT
pass "worker verbs tmux dispatch contract"
