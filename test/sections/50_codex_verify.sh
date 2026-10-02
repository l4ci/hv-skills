# white-box-begin: A9 #53 keep
echo "hv-codex-verify — Codex verdict classification against a fake codex binary"
# Live Codex is a manual gate (like tmux dispatch in section 49): the host sandbox may be
# broken and a live run costs tokens. This section fakes `codex` on PATH and checks the
# helper's classification only: PASS, FAIL, and every ERROR path (bwrap, no turn.completed,
# missing last.json, non-zero exit, dirty tree after the run), plus the sandbox-flag rule.

TMP_CV="$(mktemp -d)"
trap 'rm -rf "$TMP_CV"' EXIT

mkdir -p "$TMP_CV/proj/.hv" "$TMP_CV/fakebin" "$TMP_CV/wt"
(
  cd "$TMP_CV/wt"
  git init -q -b main .
  git config user.email t@t
  git config user.name t
  echo seed > a.txt
  git add -A
  git commit -q -m seed
) || fail "hv-codex-verify fixture repo setup failed"
echo "brief text" > "$TMP_CV/brief.md"

# Fake codex: FAKE_MODE picks the canned run; argv is logged for flag assertions.
cat > "$TMP_CV/fakebin/codex" <<'FAKE'
#!/usr/bin/env bash
[ "${1:-}" = "exec" ] || exit 0
echo "$*" > "$FAKE_ARGV_LOG"
OUT_FILE=""
while [ $# -gt 0 ]; do case "$1" in -o) OUT_FILE="$2"; shift 2 ;; *) shift ;; esac; done
cat >/dev/null
completed='{"type":"turn.completed","usage":{}}'
case "$FAKE_MODE" in
  pass)  echo '{"type":"thread.started"}'; echo "$completed"
         echo '{"verdict":"PASS","summary":"ok","findings":[],"next_steps":[]}' > "$OUT_FILE" ;;
  fail)  echo "$completed"
         echo '{"verdict":"FAIL","summary":"bad","findings":[{"severity":"high","file":"a.txt","line":1,"title":"t","body":"b"}],"next_steps":[]}' > "$OUT_FILE" ;;
  bwrap) echo '{"type":"item.completed","item":{"type":"command_execution","exit_code":1,"aggregated_output":"bwrap: loopback: Failed RTM_NEWADDR"}}'
         echo "$completed"
         echo '{"verdict":"FAIL","summary":"bogus","findings":[],"next_steps":[]}' > "$OUT_FILE" ;;
  bwrap-stderr) echo "bwrap: loopback: Failed RTM_NEWADDR" >&2; echo "$completed"
         echo '{"verdict":"FAIL","summary":"bogus","findings":[],"next_steps":[]}' > "$OUT_FILE" ;;
  prose-bwrap) echo '{"type":"item.completed","item":{"type":"agent_message","text":"the helper greps for bwrap"}}'; echo "$completed"
         echo '{"verdict":"PASS","summary":"ok","findings":[],"next_steps":[]}' > "$OUT_FILE" ;;
  noturn) echo '{"type":"thread.started"}'
         echo '{"verdict":"PASS","summary":"ok","findings":[],"next_steps":[]}' > "$OUT_FILE" ;;
  nolast) echo "$completed" ;;
  badjson) echo "$completed"; echo 'not json' > "$OUT_FILE" ;;
  exit3) echo "$completed"; echo '{"verdict":"PASS","summary":"ok","findings":[],"next_steps":[]}' > "$OUT_FILE"; exit 3 ;;
  dirty) echo "$completed"; echo touched >> a.txt
         echo '{"verdict":"PASS","summary":"ok","findings":[],"next_steps":[]}' > "$OUT_FILE" ;;
esac
FAKE
chmod +x "$TMP_CV/fakebin/codex"

run_cv() { # <mode> [extra args...] — sets CV_OUT (all stdout) and CV_RC
  local mode="$1"; shift
  CV_RC=0
  CV_OUT="$( cd "$TMP_CV/proj" && PATH="$TMP_CV/fakebin:$PATH" FAKE_MODE="$mode" FAKE_ARGV_LOG="$TMP_CV/argv" \
    "$BIN/hv-codex-verify" --worktree "$TMP_CV/wt" --brief "$TMP_CV/brief.md" "$@" 2>&1 )" || CV_RC=$?
  CV_LAST="$(printf '%s\n' "$CV_OUT" | tail -1)"
}
expect_cv() { # <mode> <verdict> <rc> [extra args...]
  local mode="$1" want="$2" rc="$3"; shift 3
  run_cv "$mode" "$@"
  [ "$CV_LAST" = "$want" ] || fail "hv-codex-verify $mode: last line '$CV_LAST', want $want"
  [ "$CV_RC" = "$rc" ] || fail "hv-codex-verify $mode: exit $CV_RC, want $rc"
  # undo the dirty fixture so modes stay independent
  git -C "$TMP_CV/wt" checkout -q -- a.txt
}

expect_cv pass         PASS  0
expect_cv fail         FAIL  1
expect_cv bwrap        ERROR 2
expect_cv bwrap-stderr ERROR 2
expect_cv prose-bwrap  PASS  0
expect_cv noturn       ERROR 2
expect_cv nolast       ERROR 2
expect_cv badjson      ERROR 2
expect_cv exit3        ERROR 2
expect_cv dirty        ERROR 2

# sandbox flag: absent by default, forwarded when asked
run_cv pass
if grep -q -- ' -s ' "$TMP_CV/argv"; then fail "hv-codex-verify passed -s without --sandbox"; fi
run_cv pass --sandbox read-only
grep -q -- '-s read-only' "$TMP_CV/argv" || fail "hv-codex-verify did not forward --sandbox"

# artifacts land under .hv/qa-runs/<ts>/codex/
ls "$TMP_CV"/proj/.hv/qa-runs/*/codex/last.json >/dev/null 2>&1 || fail "hv-codex-verify wrote no artifacts"

# bad usage exits 2 with a usage line
rc=0; ( cd "$TMP_CV/proj" && "$BIN/hv-codex-verify" --worktree ) >"$TMP_CV/u" 2>&1 || rc=$?
[ "$rc" != 0 ] && grep -q usage "$TMP_CV/u" || fail "hv-codex-verify bare --worktree should print usage and exit non-zero"

trap 'rm -rf "$TMP"' EXIT
pass "hv-codex-verify — PASS/FAIL and every ERROR path classified; sandbox flag only when asked"
# white-box-end
