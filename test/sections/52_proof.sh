echo "hv-proof-add / hv-proof-show / hv-complete proof gate"

TMP_PF="$(mktemp -d)"
trap 'rm -rf "$TMP_PF"' EXIT
mkdir -p "$TMP_PF/proj"
(
  cd "$TMP_PF/proj"
  git init -q -b main .
  git config user.email t@t
  git config user.name t
  mkdir -p .hv
  printf '## Bugs\n\n- **[B01] [P1] Proven bug.** Desc.\n- **[B02] [P1] Bare bug.** Desc.\n- **[B03] [P1] Dropped bug.** Desc.\n\n## Features\n\n## Tasks\n\n## Completed\n' > .hv/BACKLOG.md
  echo '{}' > .hv/counters.json
  git add -A && git commit -q -m "seed"
)

(
  cd "$TMP_PF/proj"
  H=$(git log -1 --format=%h)

  [ "$("$BIN/hv-proof-show" B01 --count)" = "0" ] || fail "no proof yet: count should be 0"
  "$BIN/hv-proof-add" B01 --check unit --result PASS --evidence "12 passed · 0 failed" --sha "$H"
  [ -f .hv/bugs/B01.md ] || fail "hv-proof-add should create the detail file"
  grep -q '^## Proof$' .hv/bugs/B01.md || fail "missing ## Proof section"
  grep -q "^# B01: Proven bug" .hv/bugs/B01.md || fail "new detail file should carry the item title"
  pass "hv-proof-add creates the detail file and Proof section"

  "$BIN/hv-proof-add" B01 --check unit --result PASS --evidence "12 passed · 0 failed" --sha "$H"
  [ "$("$BIN/hv-proof-show" B01 --count)" = "1" ] || fail "identical row must be idempotent"
  "$BIN/hv-proof-add" B01 --check lint --result FAIL --evidence "lint.log" --sha "$H"
  [ "$("$BIN/hv-proof-show" B01 --count)" = "2" ] || fail "distinct row should append"
  "$BIN/hv-proof-show" B01 | grep -F "· unit · PASS · $H · 12 passed · 0 failed" >/dev/null || fail "row format"
  pass "hv-proof-add is idempotent on identical rows; hv-proof-show prints rows"

  rc=0; "$BIN/hv-proof-add" B01 --check x --result MAYBE --evidence e 2>/dev/null || rc=$?
  [ "$rc" = "1" ] || fail "bad --result should exit 1"
  rc=0; "$BIN/hv-proof-add" B99 --check x --result PASS --evidence e 2>/dev/null || rc=$?
  [ "$rc" = "1" ] || fail "unknown ID should exit 1"
  pass "hv-proof-add rejects bad result and unknown ID"

  # Existing detail file with content keeps it; Proof is appended.
  printf '# B02: Bare bug\n\n## Summary\n\nbody\n\n## Notes\n\nlater\n' > .hv/bugs/B02.md
  rc=0; "$BIN/hv-complete" B02 "$H" 2>"$TMP_PF/err" || rc=$?
  [ "$rc" = "3" ] || fail "no proof: expected exit 3, got $rc"
  grep -q "no proof recorded, pass --no-proof" "$TMP_PF/err" || fail "refusal message"
  grep -q '^- \*\*\[B02\]' .hv/BACKLOG.md || fail "refusal must not modify BACKLOG"
  "$BIN/hv-proof-add" B02 --check smoke --result PASS --evidence ok --sha "$H"
  grep -q '^## Summary' .hv/bugs/B02.md && grep -q '^later' .hv/bugs/B02.md || fail "existing sections lost"
  pass "hv-complete refuses without proof (exit 3), BACKLOG untouched"

  "$BIN/hv-complete" B02 "$H"
  grep -qF "~~**[B02] [P1] Bare bug.** Desc.~~ Done $(date +%Y-%m-%d) [\`$H\`]" .hv/BACKLOG.md || fail "proven close should render the plain marker"
  "$BIN/hv-complete" B02 "$H" || fail "already-completed must stay a no-op"
  pass "hv-complete with proof renders the unchanged marker"

  "$BIN/hv-complete" B03 "$H" --reason dropped
  grep -q '(dropped)' .hv/BACKLOG.md || fail "dropped close needs no proof"
  pass "non-done reasons skip the proof gate"
)

# T119: every skill that calls hv-complete must also give it a proof path.
callers=$(cd "$REPO" && grep -l 'hv-complete' hv-*/SKILL.md)
[ -n "$callers" ] || fail "expected at least one SKILL.md calling hv-complete"
for f in $callers; do
  grep -q 'hv-proof-add' "$REPO/$f" || fail "$f calls hv-complete without an hv-proof-add path"
done
pass "hv-complete callers document a proof path"

trap 'rm -rf "$TMP"' EXIT
