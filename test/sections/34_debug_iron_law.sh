echo "F02: hv-debug-counter Iron Law gate"

# ── standalone fallbacks (runner.sh sets these; define here for direct bash invocation) ──
_SECTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "$_SECTION_DIR/../.." && pwd)"
: "${BIN:=$_REPO_ROOT/bin}"
: "${TMP:=$(mktemp -d)}"
# Define pass/fail if not sourced from lib.sh
if ! declare -f pass >/dev/null 2>&1; then
  pass() { printf '  \033[32mOK\033[0m  %s\n' "$1"; }
  fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }
fi

# ── fixture ─────────────────────────────────────────────────────────────────
TMP_DEBUG="$(mktemp -d)"
trap 'rm -rf "$TMP_DEBUG"' EXIT

(
  cd "$TMP_DEBUG"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit -q --allow-empty -m "seed"
  git checkout -q -b hv/F02-smoke

  mkdir -p .hv/bin
  # Copy only the flat files in $BIN (avoid recursive system dirs)
  find "$BIN" -maxdepth 1 -type f -exec cp {} .hv/bin/ \;

  COUNTER=".hv/bin/hv-debug-counter"

  # ── (a) init creates the file with expected schema ───────────────────────
  "$COUNTER" init F02
  [ -f ".hv/debug/hv-F02-smoke.json" ] || { echo "FAIL: session file missing"; exit 1; }
  python3 -c "
import json, sys
d = json.load(open('.hv/debug/hv-F02-smoke.json'))
assert d['session'] == 'hv-F02-smoke', f\"session={d['session']}\"
assert d['bug_id'] == 'F02', f\"bug_id={d['bug_id']}\"
assert d['failed_fixes'] == 0, f\"failed_fixes={d['failed_fixes']}\"
assert d['attempts'] == [], f\"attempts={d['attempts']}\"
" || { echo "FAIL: schema check"; exit 1; }

  # ── (b) init is idempotent ────────────────────────────────────────────────
  started_before="$(python3 -c "import json; print(json.load(open('.hv/debug/hv-F02-smoke.json'))['started_at'])")"
  "$COUNTER" init F02
  started_after="$(python3 -c "import json; print(json.load(open('.hv/debug/hv-F02-smoke.json'))['started_at'])")"
  [ "$started_before" = "$started_after" ] || { echo "FAIL: init not idempotent (timestamp changed)"; exit 1; }

  # ── (c) record-attempt prints attempt number and (d) fail marks outcome ───
  # Pattern: record → fail → record → fail → record → fail (one pending at a time)
  n1="$("$COUNTER" record-attempt --hypothesis "hyp-one" --commit "abc1111")"
  [ "$n1" = "1" ] || { echo "FAIL: first attempt number expected 1, got $n1"; exit 1; }
  f1="$("$COUNTER" fail)"
  [ "$f1" = "1" ] || { echo "FAIL: fail#1 expected 1, got $f1"; exit 1; }
  python3 -c "
import json
d = json.load(open('.hv/debug/hv-F02-smoke.json'))
a = d['attempts'][0]
assert a['outcome'] == 'failed', a
assert 'ended_at' in a, a
" || { echo "FAIL: attempt[0] not marked failed"; exit 1; }

  n2="$("$COUNTER" record-attempt --hypothesis "hyp-two" --commit "abc2222")"
  [ "$n2" = "2" ] || { echo "FAIL: second attempt number expected 2, got $n2"; exit 1; }
  f2="$("$COUNTER" fail)"
  [ "$f2" = "2" ] || { echo "FAIL: fail#2 expected 2, got $f2"; exit 1; }

  n3="$("$COUNTER" record-attempt --hypothesis "hyp-three" --commit "abc3333")"
  [ "$n3" = "3" ] || { echo "FAIL: third attempt number expected 3, got $n3"; exit 1; }
  f3="$("$COUNTER" fail)"
  [ "$f3" = "3" ] || { echo "FAIL: fail#3 expected 3, got $f3"; exit 1; }

  # verify attempts array has 3 entries all failed
  python3 -c "
import json
d = json.load(open('.hv/debug/hv-F02-smoke.json'))
assert len(d['attempts']) == 3, f\"expected 3 attempts, got {len(d['attempts'])}\"
assert all(a['outcome'] == 'failed' for a in d['attempts']), d['attempts']
assert d['failed_fixes'] == 3, f\"failed_fixes={d['failed_fixes']}\"
" || { echo "FAIL: attempts array or failed_fixes wrong"; exit 1; }

  # ── (e) summary renders Iron Law markdown ─────────────────────────────────
  SUMMARY="$("$COUNTER" summary)"
  echo "$SUMMARY" | grep -q "Iron Law triggered for \[F02\]" || { echo "FAIL: summary missing Iron Law header"; exit 1; }
  echo "$SUMMARY" | grep -q "abc1111" || { echo "FAIL: summary missing commit abc1111"; exit 1; }
  echo "$SUMMARY" | grep -q "abc2222" || { echo "FAIL: summary missing commit abc2222"; exit 1; }
  echo "$SUMMARY" | grep -q "abc3333" || { echo "FAIL: summary missing commit abc3333"; exit 1; }
  echo "$SUMMARY" | grep -q "hyp-one" || { echo "FAIL: summary missing hypothesis hyp-one"; exit 1; }
  echo "$SUMMARY" | grep -q "hyp-two" || { echo "FAIL: summary missing hypothesis hyp-two"; exit 1; }
  echo "$SUMMARY" | grep -q "hyp-three" || { echo "FAIL: summary missing hypothesis hyp-three"; exit 1; }
  echo "$SUMMARY" | grep -q "Next steps" || { echo "FAIL: summary missing Next steps section"; exit 1; }

  # ── (f) pass flow (clear + re-init to start fresh) ────────────────────────
  "$COUNTER" clear
  [ ! -f ".hv/debug/hv-F02-smoke.json" ] || { echo "FAIL: clear did not remove file"; exit 1; }

  "$COUNTER" init F02
  "$COUNTER" record-attempt --hypothesis "clean-hyp" --commit "cccc000" > /dev/null
  "$COUNTER" pass
  python3 -c "
import json
d = json.load(open('.hv/debug/hv-F02-smoke.json'))
a = d['attempts'][-1]
assert a['outcome'] == 'passed', f\"outcome={a['outcome']}\"
assert d['failed_fixes'] == 0, f\"failed_fixes should be 0 for pass flow, got {d['failed_fixes']}\"
" || { echo "FAIL: pass outcome or failed_fixes wrong"; exit 1; }

  # ── (g) clear removes file and is idempotent ──────────────────────────────
  "$COUNTER" clear
  [ ! -f ".hv/debug/hv-F02-smoke.json" ] || { echo "FAIL: second clear left file"; exit 1; }
  "$COUNTER" clear 2>/dev/null  # idempotent — must exit 0

  # ── (h) show exits non-zero when no session exists ────────────────────────
  if "$COUNTER" show 2>/dev/null; then
    echo "FAIL: show should exit non-zero when no session"; exit 1
  fi

  # ── (i) inc-cycle is separate from failed_fixes ───────────────────────────
  "$COUNTER" init F02
  "$COUNTER" inc-cycle > /dev/null
  c2="$("$COUNTER" inc-cycle)"
  [ "$c2" = "2" ] || { echo "FAIL: inc-cycle second call expected 2, got $c2"; exit 1; }
  python3 -c "
import json
d = json.load(open('.hv/debug/hv-F02-smoke.json'))
assert d['hypothesis_cycles'] == 2, f\"hypothesis_cycles={d['hypothesis_cycles']}\"
assert d['failed_fixes'] == 0, f\"failed_fixes should be 0, got {d['failed_fixes']}\"
" || { echo "FAIL: inc-cycle counter or failed_fixes wrong"; exit 1; }
) || exit 1

trap 'rm -rf "$TMP"' EXIT
pass "hv-debug-counter: init/idempotent/record-attempt/fail/pass/summary/clear/show/inc-cycle all correct"
