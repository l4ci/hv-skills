echo "tracker suggest-upstream manual fallback when gh unavailable"
HI_TMP="$(mktemp -d)"
trap 'rm -rf "$HI_TMP"' EXIT
(
  cd "$HI_TMP"
  mkdir -p .hv stub-bin
  # Stub `gh` to a script that always fails so the verb takes the unavailable path,
  # even on a host where the real gh is installed and authed.
  cat > stub-bin/gh <<'EOS'
#!/bin/sh
exit 7
EOS
  chmod +x stub-bin/gh
  rc=0
  OUT=$(PATH="$HI_TMP/stub-bin:$PATH" hvj tracker suggest-upstream --title "test title" --body-file - <<<"test body" 2>/dev/null) || rc=$?
  [ "$rc" = "5" ] || fail "expected exit 5 when gh fails: rc=$rc"
  [ "$(echo "$OUT" | jget ok)" = "false" ] || fail "expected ok:false envelope: $OUT"
  echo "$OUT" | jget error.hint | grep "github.com/l4ci/hv-skills/issues/new" >/dev/null || fail "unavailable hint missing repo URL: $OUT"
  pass "tracker suggest-upstream exits 5 with the manual issue URL when gh unavailable"
)
rm -rf "$HI_TMP"

echo "tracker suggest-upstream --upstream-repo override"
HI2_TMP="$(mktemp -d)"
trap 'rm -rf "$HI2_TMP"' EXIT
(
  cd "$HI2_TMP"
  mkdir -p .hv stub-bin
  cat > stub-bin/gh <<'EOS'
#!/bin/sh
exit 7
EOS
  chmod +x stub-bin/gh
  rc=0; OUT=$(PATH="$HI2_TMP/stub-bin:$PATH" hvj tracker suggest-upstream --title "x" --upstream-repo "fork/repo" --body-file - <<<"y" 2>/dev/null) || rc=$?
  [ "$rc" = 5 ] || fail "suggest-upstream with a failing gh should exit 5 (got $rc): $OUT"
  echo "$OUT" | jget error.hint | grep "github.com/fork/repo" >/dev/null || fail "--upstream-repo override ignored: $OUT"
  pass "tracker suggest-upstream --upstream-repo override flows through to the hint URL"
)
rm -rf "$HI2_TMP"

echo "release pending"
RP_TMP="$(mktemp -d)"
trap 'rm -rf "$RP_TMP"' EXIT

# Case 1: no tags -> no nudge, lastTag empty.
(
  cd "$RP_TMP"
  mkdir no-tag && cd no-tag
  mkdir -p .hv
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  OUT=$(hvj release pending)
  [ "$(echo "$OUT" | jget data.lastTag)" = "" ] || fail "no-tag case lastTag: $OUT"
  [ "$(echo "$OUT" | jget data.commits)" = "0" ] || fail "no-tag case commits: $OUT"
  [ "$(echo "$OUT" | jget data.shouldNudge)" = "false" ] || fail "no-tag case shouldNudge: $OUT"
  [ "$(echo "$OUT" | jget data.reason)" = "no-tag" ] || fail "no-tag case reason: $OUT"
  [ "$(echo "$OUT" | jget data.message)" = "" ] || fail "no-tag case message: $OUT"
)
pass "release pending: no tag -> no nudge"

# Case 2: tag + 3 commits, default thresholds -> no nudge.
(
  cd "$RP_TMP"
  mkdir below && cd below
  mkdir -p .hv
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  git tag v0.0.1
  for i in 1 2 3; do git commit -q --allow-empty -m "c$i"; done
  OUT=$(hvj release pending)
  [ "$(echo "$OUT" | jget data.lastTag)" = "v0.0.1" ] || fail "below-threshold lastTag: $OUT"
  [ "$(echo "$OUT" | jget data.commits)" = "3" ] || fail "below-threshold commits: $OUT"
  [ "$(echo "$OUT" | jget data.shouldNudge)" = "false" ] || fail "below-threshold shouldNudge: $OUT"
  [ "$(echo "$OUT" | jget data.reason)" = "" ] || fail "below-threshold reason: $OUT"
  [ "$(echo "$OUT" | jget data.message)" = "" ] || fail "below-threshold message: $OUT"
)
pass "release pending: 3 commits past tag -> no nudge"

# Case 3: tag + 11 commits -> nudge, reason=commits.
(
  cd "$RP_TMP"
  mkdir above && cd above
  mkdir -p .hv
  git init -q && git config user.email t@t && git config user.name t
  git commit -q --allow-empty -m "seed"
  git tag v0.0.1
  for i in $(seq 1 11); do git commit -q --allow-empty -m "c$i"; done
  OUT=$(hvj release pending)
  [ "$(echo "$OUT" | jget data.lastTag)" = "v0.0.1" ] || fail "above-threshold lastTag: $OUT"
  [ "$(echo "$OUT" | jget data.commits)" = "11" ] || fail "above-threshold commits: $OUT"
  [ "$(echo "$OUT" | jget data.shouldNudge)" = "true" ] || fail "above-threshold shouldNudge: $OUT"
  [ "$(echo "$OUT" | jget data.reason)" = "commits" ] || fail "above-threshold reason: $OUT"
  [ "$(echo "$OUT" | jget data.message)" = "11 commits since v0.0.1; consider /hv-release." ] || fail "above-threshold message: $OUT"
)
pass "release pending: 11 commits past tag -> nudge (reason=commits)"

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
  OUT=$(hvj release pending)
  [ "$(echo "$OUT" | jget data.thresholdCommits)" = "5" ] || fail "custom-threshold thresholdCommits: $OUT"
  [ "$(echo "$OUT" | jget data.commits)" = "6" ] || fail "custom-threshold commits: $OUT"
  [ "$(echo "$OUT" | jget data.shouldNudge)" = "true" ] || fail "custom-threshold shouldNudge: $OUT"
  [ "$(echo "$OUT" | jget data.reason)" = "commits" ] || fail "custom-threshold reason: $OUT"
  [ "$(echo "$OUT" | jget data.message)" = "6 commits since v0.0.1; consider /hv-release." ] || fail "custom-threshold message: $OUT"
)
pass "release pending: custom nudgeAfterCommits=5 honored"

rm -rf "$RP_TMP"
trap 'rm -rf "$TMP"' EXIT

# white-box: kept until A9 (#53)
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

# white-box: kept until A9 (#53)
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
