echo "hv-tracker-call"

TMP_TC="$(mktemp -d)"
trap 'rm -rf "$TMP_TC"' EXIT
mkdir -p "$TMP_TC/proj/.hv" "$TMP_TC/fake"
echo '{"issues":{"provider":"github","retryWaitSeconds":0}}' > "$TMP_TC/proj/.hv/config.json"

# Fake gh/glab: log argv (+ cwd, stdin) per call; behavior from FAKE_MODE.
for cli in gh glab; do
  cat > "$TMP_TC/fake/$cli" <<FAKE
#!/usr/bin/env bash
echo "\$*" >> "\$FAKE_LOG"
echo "cwd:\$(pwd -P)" >> "\$FAKE_LOG.cwd"
[ -t 0 ] || cat > "\$FAKE_LOG.stdin"
case "\${FAKE_MODE:-ok}" in
  ok) python3 -c "import json,os; print(json.dumps([{'n':i} for i in range(int(os.environ.get('FAKE_N','2')))]))" ;;
  primary) echo "API rate limit exceeded for user" >&2; exit 1 ;;
  primary-once)
    n=\$(wc -l < "\$FAKE_LOG")
    if [ "\$n" -le 1 ]; then echo "HTTP 429: too many" >&2; exit 1; fi
    echo '[]' ;;
  secondary) echo "You have exceeded a secondary rate limit" >&2; exit 1 ;;
  auth) echo "To get started, please run: $cli auth login" >&2; exit 1 ;;
  fail) echo "boom: not found" >&2; exit 7 ;;
esac
FAKE
  chmod +x "$TMP_TC/fake/$cli"
done

(
  cd "$TMP_TC/proj"
  export FAKE_LOG="$TMP_TC/log"
  TC() { : > "$FAKE_LOG"; rm -f "$FAKE_LOG.cwd" "$FAKE_LOG.stdin"; PATH="$TMP_TC/fake:$PATH" "$BIN/hv-tracker-call" "$@" </dev/null; }
  calls() { wc -l < "$FAKE_LOG" | tr -d ' '; }

  # provider resolution
  TC -- issue list >/dev/null
  [ "$(cat "$FAKE_LOG")" = "issue list --limit 1000" ] || fail "config provider github should run gh with --limit 1000 (got: $(cat "$FAKE_LOG"))"
  TC --provider gitlab -- issue list >/dev/null
  [ "$(cat "$FAKE_LOG")" = "issue list --per-page 100" ] || fail "--provider gitlab should add --per-page 100"
  pass "provider from config and --provider flag; list limits injected"

  # no double injection
  TC -- issue list -L 5 >/dev/null
  [ "$(cat "$FAKE_LOG")" = "issue list -L 5" ] || fail "explicit -L must not get --limit"
  TC --provider gitlab -- mr list --per-page 20 >/dev/null
  [ "$(cat "$FAKE_LOG")" = "mr list --per-page 20" ] || fail "explicit --per-page must not be doubled"
  TC -- issue view 3 >/dev/null
  [ "$(cat "$FAKE_LOG")" = "issue view 3" ] || fail "non-list commands untouched"
  pass "limits only injected when absent"

  # api paginate
  TC -- api repos/o/r/issues >/dev/null
  [ "$(cat "$FAKE_LOG")" = "api repos/o/r/issues --paginate" ] || fail "GET api should paginate"
  TC -- api -X POST repos/o/r/issues >/dev/null
  if grep -q paginate "$FAKE_LOG"; then fail "POST api must not paginate"; fi
  TC -- api repos/o/r/issues -f title=x >/dev/null
  if grep -q paginate "$FAKE_LOG"; then fail "api with -f must not paginate"; fi
  TC -- api repos/o/r/issues --paginate >/dev/null
  [ "$(cat "$FAKE_LOG")" = "api repos/o/r/issues --paginate" ] || fail "--paginate must not be doubled"
  pass "--paginate only on GET api"

  # stdin forwarded; cwd restored to caller's
  mkdir -p sub; : > "$FAKE_LOG"; rm -f "$FAKE_LOG.cwd"
  (cd sub && echo "body text" | PATH="$TMP_TC/fake:$PATH" "$BIN/hv-tracker-call" -- issue create -F - >/dev/null)
  [ "$(cat "$FAKE_LOG.stdin")" = "body text" ] || fail "stdin should reach the CLI"
  [ "$(cat "$FAKE_LOG.cwd")" = "cwd:$(pwd -P)/sub" ] || fail "CLI must run in the caller's cwd (got $(cat "$FAKE_LOG.cwd"))"
  pass "stdin forwarded; CLI runs in caller's cwd"

  # An inherited stdin that never closes must not block a call that takes no `-` argument.
  mkfifo "$TMP_TC/held"; exec 9<>"$TMP_TC/held"
  rc=0; PATH="$TMP_TC/fake:$PATH" timeout 10 "$BIN/hv-tracker-call" -- issue view 3 <"$TMP_TC/held" >/dev/null || rc=$?
  exec 9>&-
  [ "$rc" = 0 ] || fail "open stdin pipe should not block a call without '-' (rc=$rc)"
  pass "stdin only read when an argument takes it"

  # truncation warning
  FAKE_N=1000 TC -- issue list 2>"$TMP_TC/err" >/dev/null
  grep -q "hit the list limit (1000)" "$TMP_TC/err" || fail "expected truncation warning"
  FAKE_N=3 TC -- issue list 2>"$TMP_TC/err" >/dev/null
  if grep -q "list limit" "$TMP_TC/err"; then fail "no warning below the limit"; fi
  pass "truncation warning at the limit only"

  # rate limits
  rc=0; FAKE_MODE=primary-once TC -- issue list >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ] && [ "$(calls)" = 2 ] || fail "primary-once: want success after 2 calls (rc=$rc, calls=$(calls))"
  rc=0; FAKE_MODE=primary TC -- issue list >/dev/null 2>"$TMP_TC/err" || rc=$?
  [ "$rc" = 4 ] && [ "$(calls)" = 2 ] || fail "primary: want exit 4 after 2 calls (rc=$rc, calls=$(calls))"
  grep -q "rate limit — stopped after one retry" "$TMP_TC/err" || fail "primary message"
  rc=0; FAKE_MODE=secondary TC -- issue list >/dev/null 2>"$TMP_TC/err" || rc=$?
  [ "$rc" = 4 ] && [ "$(calls)" = 1 ] || fail "secondary: want exit 4 after 1 call (rc=$rc, calls=$(calls))"
  grep -q "secondary rate limit" "$TMP_TC/err" || fail "secondary message"
  pass "primary retries once; secondary stops at once; both exit 4"

  # auth, plain failure
  rc=0; FAKE_MODE=auth TC -- issue list >/dev/null 2>"$TMP_TC/err" || rc=$?
  [ "$rc" = 3 ] || fail "auth failure should exit 3 (got $rc)"
  grep -q "gh is not authenticated; run 'gh auth login'" "$TMP_TC/err" || fail "auth message"
  rc=0; FAKE_MODE=fail TC -- issue view 9 >/dev/null 2>"$TMP_TC/err" || rc=$?
  [ "$rc" = 7 ] && [ "$(calls)" = 1 ] || fail "plain failure should pass through exit 7 once (rc=$rc)"
  grep -q "boom: not found" "$TMP_TC/err" || fail "stderr should be forwarded"
  pass "auth failure exits 3; plain failure keeps CLI exit code and stderr"

  # missing CLI: PATH with python3/coreutils but no gh/glab
  mkdir -p "$TMP_TC/nobin"
  for t in python3 bash env dirname cat wc tr git; do ln -sf "$(command -v $t)" "$TMP_TC/nobin/$t"; done
  rc=0; PATH="$TMP_TC/nobin" "$BIN/hv-tracker-call" -- issue list </dev/null >/dev/null 2>"$TMP_TC/err" || rc=$?
  [ "$rc" = 3 ] || fail "missing CLI should exit 3 (got $rc)"
  grep -q "gh is not installed" "$TMP_TC/err" || fail "missing CLI message"
  pass "missing CLI exits 3"

  # usage errors
  rc=0; "$BIN/hv-tracker-call" </dev/null --provider 2>/dev/null || rc=$?
  [ "$rc" != 0 ] || fail "bare trailing --provider must fail"
  rc=0; "$BIN/hv-tracker-call" </dev/null --provider github 2>"$TMP_TC/err" || rc=$?
  [ "$rc" != 0 ] && grep -q "usage:" "$TMP_TC/err" || fail "missing CLI args should print usage"
  pass "usage errors rejected"
)

trap 'rm -rf "$TMP"' EXIT
