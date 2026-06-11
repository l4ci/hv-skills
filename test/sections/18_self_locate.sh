echo "hv-refactor-targets"
mkdir rt-test && cd rt-test
mkdir -p .hv/bin
cp "$BIN"/hvlib*.py .hv/bin/
# hvlib_types.py reads the registry from hv-types.sh next to itself at import
# time, so the data file must travel with the hvlib*.py modules.
cp "$BIN/hv-types.sh" .hv/bin/
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
install_helpers
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

echo "F42 self-locate: cwd-anchored walk-up wins over BASH_SOURCE[1]"
F42_TMP="$(mktemp -d)"
trap 'rm -rf "$F42_TMP"' EXIT
mkdir -p "$F42_TMP/.hv" "$F42_TMP/repo-a"
echo '{"bugs":7,"features":0,"tasks":0,"milestones":0}' > "$F42_TMP/.hv/counters.json"
(
  cd "$F42_TMP/repo-a"
  ID=$("$BIN/hv-next-id" bugs)
  [ "$ID" = "B08" ] || { echo "FAIL: F42: hv-next-id from sub-cwd: expected B08 (test umbrella), got '$ID'"; exit 1; }
)
AFTER_BUGS=$(python3 -c 'import json; print(json.load(open("'"$F42_TMP/.hv/counters.json"'"))["bugs"])')
[ "$AFTER_BUGS" = "8" ] || fail "F42: test umbrella counters.json not incremented (expected 8, got $AFTER_BUGS)"
trap 'rm -rf "$TMP"' EXIT
pass "hv-self-locate prefers cwd-anchored walk-up over BASH_SOURCE[1]"
