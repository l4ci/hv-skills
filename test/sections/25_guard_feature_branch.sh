echo "hv-guard-feature-branch resolve helper"

GUARD_TMP="$(mktemp -d)"
trap 'rm -rf "$GUARD_TMP"' EXIT
(
  cd "$GUARD_TMP"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  echo seed > seed.txt && git add seed.txt && git commit -q -m "seed"

  # --- on main → exit 1 ---
  if "$BIN/hv-guard-feature-branch" 2>/dev/null; then
    echo "FAIL: should exit 1 on main"
    exit 1
  fi

  # --- on a feature branch → exit 0 ---
  git checkout -q -b hv/feature-x
  "$BIN/hv-guard-feature-branch" || { echo "FAIL: should exit 0 on feature branch"; exit 1; }

  # --- explicit branch arg: passes feature, refuses main ---
  "$BIN/hv-guard-feature-branch" hv/feature-x || { echo "FAIL: explicit feature branch should exit 0"; exit 1; }
  if "$BIN/hv-guard-feature-branch" main 2>/dev/null; then
    echo "FAIL: explicit main should exit 1"
    exit 1
  fi

  # --- master is also refused when it's the resolved base ---
  # hv-base-branch tries main first, then master — so to test master as base,
  # first delete main so master is the only conventional candidate left.
  git checkout -q -b master
  git branch -q -D main
  if "$BIN/hv-guard-feature-branch" 2>/dev/null; then
    echo "FAIL: should exit 1 on master when it's the base"
    exit 1
  fi
  # Restore main for the rest of the test
  git checkout -q -b main

  # --- custom git.baseBranch via config: the configured branch is the protected one ---
  git checkout -q main
  mkdir -p .hv
  echo '{"git":{"baseBranch":"develop"}}' > .hv/config.json
  git checkout -q -b develop
  if "$BIN/hv-guard-feature-branch" 2>/dev/null; then
    echo "FAIL: configured baseBranch 'develop' should refuse"
    exit 1
  fi
  # main is no longer the base now that develop is configured AND exists
  git checkout -q main
  "$BIN/hv-guard-feature-branch" || { echo "FAIL: main should be allowed when develop is configured base"; exit 1; }
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$GUARD_TMP"
pass "hv-guard-feature-branch refuses base / passes feature / honors git.baseBranch"

echo "hv-ship and hv-pause reference hv-guard-feature-branch"
grep -q "hv-guard-feature-branch" "$REPO/hv-ship/SKILL.md" || fail "hv-ship missing hv-guard-feature-branch call"
grep -q "hv-guard-feature-branch" "$REPO/hv-pause/SKILL.md" || fail "hv-pause missing hv-guard-feature-branch call"
pass "hv-ship and hv-pause both reference the new helper"
