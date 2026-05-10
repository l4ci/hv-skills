echo "hv-issue-suggest manual fallback when gh unavailable"
HI_TMP="$(mktemp -d)"
(
  cd "$HI_TMP"
  mkdir -p .hv/bin stub-bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
  # Stub `gh` to a script that always fails so the helper takes the manual-fallback path,
  # even on a host where the real gh is installed and authed.
  cat > stub-bin/gh <<'EOF'
#!/bin/sh
exit 7
EOF
  chmod +x stub-bin/gh
  set +e
  OUT=$(PATH="$HI_TMP/stub-bin:$PATH" .hv/bin/hv-issue-suggest --title "test title" <<<"test body" 2>&1)
  RC=$?
  set -e
  [ "$RC" = "1" ] || fail "expected exit 1 when gh fails: rc=$RC"
  echo "$OUT" | grep -q "test title" || fail "manual fallback missing title: $OUT"
  echo "$OUT" | grep -q "test body" || fail "manual fallback missing body: $OUT"
  echo "$OUT" | grep -q "github.com/l4ci/hv-skills" || fail "manual fallback missing repo URL: $OUT"
  pass "hv-issue-suggest prints manual fallback when gh unavailable"
)
rm -rf "$HI_TMP"

echo "hv-issue-suggest --upstream-repo override"
HI2_TMP="$(mktemp -d)"
(
  cd "$HI2_TMP"
  mkdir -p .hv/bin stub-bin
  cp "$BIN"/hv-* "$BIN"/hvlib.py .hv/bin/ && chmod +x .hv/bin/hv-*
  cat > stub-bin/gh <<'EOF'
#!/bin/sh
exit 7
EOF
  chmod +x stub-bin/gh
  set +e
  OUT=$(PATH="$HI2_TMP/stub-bin:$PATH" .hv/bin/hv-issue-suggest --title "x" --upstream-repo "fork/repo" <<<"y" 2>&1)
  set -e
  echo "$OUT" | grep -q "github.com/fork/repo" || fail "--upstream-repo override ignored: $OUT"
  pass "hv-issue-suggest --upstream-repo override flows through to manual fallback URL"
)
rm -rf "$HI2_TMP"

echo "hv-release-pending"
RP_TMP="$(mktemp -d)"

# Case 1: no tags → no nudge, lastTag empty.
(
  cd "$RP_TMP"
  mkdir no-tag && cd no-tag
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  OUT=$("$BIN/hv-release-pending")
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['lastTag'] == '', d
assert d['commits'] == 0, d
assert d['shouldNudge'] is False, d
assert d['reason'] == 'no-tag', d
assert d['message'] == '', d
" "$OUT" || fail "no-tag case: $OUT"
)
pass "hv-release-pending: no tag -> no nudge"

# Case 2: tag + 3 commits, default thresholds → no nudge.
(
  cd "$RP_TMP"
  mkdir below && cd below
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  git tag v0.0.1
  for i in 1 2 3; do git commit -q --allow-empty -m "c$i"; done
  OUT=$("$BIN/hv-release-pending")
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['lastTag'] == 'v0.0.1', d
assert d['commits'] == 3, d
assert d['shouldNudge'] is False, d
assert d['reason'] == '', d
assert d['message'] == '', d
" "$OUT" || fail "below-threshold case: $OUT"
)
pass "hv-release-pending: 3 commits past tag -> no nudge"

# Case 3: tag + 11 commits → nudge, reason=commits.
(
  cd "$RP_TMP"
  mkdir above && cd above
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  git tag v0.0.1
  for i in $(seq 1 11); do git commit -q --allow-empty -m "c$i"; done
  OUT=$("$BIN/hv-release-pending")
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['lastTag'] == 'v0.0.1', d
assert d['commits'] == 11, d
assert d['shouldNudge'] is True, d
assert d['reason'] == 'commits', d
assert d['message'] == '11 commits since v0.0.1; consider /hv-release.', d
" "$OUT" || fail "above-commit-threshold case: $OUT"
)
pass "hv-release-pending: 11 commits past tag -> nudge (reason=commits)"

# Case 4: custom commit threshold via .hv/config.json.
(
  cd "$RP_TMP"
  mkdir custom && cd custom
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  git tag v0.0.1
  for i in $(seq 1 6); do git commit -q --allow-empty -m "c$i"; done
  mkdir -p .hv
  echo '{"release":{"nudgeAfterCommits":5}}' > .hv/config.json
  OUT=$("$BIN/hv-release-pending")
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['thresholdCommits'] == 5, d
assert d['commits'] == 6, d
assert d['shouldNudge'] is True, d
assert d['reason'] == 'commits', d
assert d['message'] == '6 commits since v0.0.1; consider /hv-release.', d
" "$OUT" || fail "custom-threshold case: $OUT"
)
pass "hv-release-pending: custom nudgeAfterCommits=5 honored"

rm -rf "$RP_TMP"

echo "F29: --repo flag uses strict form"
# Structural guard: every helper that parses a literal --repo / --repos flag
# must extract the value with the loud form ${2:?usage:...} so a missing
# argument errors out instead of silently defaulting and corrupting state
# (e.g. status.json with repo:null when the caller meant a sub-repo).
# See [F29] — Converge --repo flag parsing across helpers.
for f in hv-merge hv-pr hv-review-scope hv-spike-add hv-status-add hv-status-remove hv-worktree-clear hv-worktree-path hv-plan-add; do
  helper="$BIN/$f"
  [ -f "$helper" ] || fail "F29: expected helper $f missing from bin/"
  grep -q -- '--repo' "$helper" || fail "F29: $f no longer references --repo (canonical list stale?)"
  grep -qE '\$\{2:\?usage:' "$helper" || fail "F29: $f --repo extraction must use \${2:?usage:...} strict form (no silent \${2:-})"
done
for f in hv-status-add-multi hv-multi-branch-create; do
  helper="$BIN/$f"
  [ -f "$helper" ] || fail "F29: expected helper $f missing from bin/"
  grep -q -- '--repos' "$helper" || fail "F29: $f no longer references --repos (canonical list stale?)"
  grep -qE '\$\{2:\?usage:' "$helper" || fail "F29: $f --repos extraction must use \${2:?usage:...} strict form (no silent \${2:-})"
done
pass "F29: all --repo / --repos helpers use the strict \${2:?usage:...} extraction"

echo "F30: walk-up helpers delegate to bin/hv-walk-up"
# Structural guard: helpers that need to walk upward from a caller directory
# must delegate to the canonical bin/hv-walk-up rather than reimplementing the
# loop inline. Reverting to an inline `while [ "$dir" != "/" ]` walk drifts
# masking semantics across callers.
# See [F30] — Consolidate walk-up logic behind bin/hv-walk-up.
for f in hv-self-locate.sh hv-resolve-umbrella; do
  helper="$BIN/$f"
  [ -f "$helper" ] || fail "F30: expected helper $f missing from bin/"
  grep -q 'hv-walk-up' "$helper" || fail "F30: $f must invoke hv-walk-up (no inline walk-up loops)"
done
pass "F30: hv-self-locate.sh and hv-resolve-umbrella delegate to bin/hv-walk-up"
