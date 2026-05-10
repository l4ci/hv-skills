echo "hv-release-detect-version"
# Case 1: .claude-plugin/plugin.json (priority candidate)
DV1="$(mktemp -d)"
(
  cd "$DV1"
  mkdir -p .claude-plugin
  printf '{"version":"1.0.0"}\n' > .claude-plugin/plugin.json
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"version": "1.0.0"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"kind": "plugin-json"' || { echo "FAIL: kind wrong: $OUT"; exit 1; }
)
pass "hv-release-detect-version detects plugin.json"

# Case 2: config override via .hv/config.json
(
  cd "$DV1"
  mkdir -p .hv
  printf '{"release":{"versionFile":"package.json"}}\n' > .hv/config.json
  printf '{"version":"2.5.0"}\n' > package.json
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"file": "package.json"' || { echo "FAIL: file wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"version": "2.5.0"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
)
pass "hv-release-detect-version respects release.versionFile config override"
rm -rf "$DV1"

# Case 3: pyproject.toml
DV2="$(mktemp -d)"
(
  cd "$DV2"
  printf '[project]\nversion = "0.1.2"\n' > pyproject.toml
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"kind": "pyproject"' || { echo "FAIL: kind wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"version": "0.1.2"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
)
rm -rf "$DV2"
pass "hv-release-detect-version detects pyproject.toml"

# Case 4: Cargo.toml
DV3="$(mktemp -d)"
(
  cd "$DV3"
  printf '[package]\nversion = "3.4.5"\n' > Cargo.toml
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"kind": "cargo"' || { echo "FAIL: kind wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"version": "3.4.5"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
)
rm -rf "$DV3"
pass "hv-release-detect-version detects Cargo.toml"

# Case 5: plain VERSION file
DV4="$(mktemp -d)"
(
  cd "$DV4"
  printf '9.9.9\n' > VERSION
  OUT=$("$BIN/hv-release-detect-version")
  echo "$OUT" | grep -q '"kind": "plain"' || { echo "FAIL: kind wrong: $OUT"; exit 1; }
  echo "$OUT" | grep -q '"version": "9.9.9"' || { echo "FAIL: version wrong: $OUT"; exit 1; }
)
rm -rf "$DV4"
pass "hv-release-detect-version detects plain VERSION file"

# Case 6: no version files → exit non-zero + stderr message
DV5="$(mktemp -d)"
(
  cd "$DV5"
  rc=0
  ERR=$("$BIN/hv-release-detect-version" 2>&1 >/dev/null) || rc=$?
  [ "$rc" != "0" ] || { echo "FAIL: expected non-zero exit, got 0"; exit 1; }
  echo "$ERR" | grep -q "no version file detected" || { echo "FAIL: stderr missing expected message: $ERR"; exit 1; }
)
rm -rf "$DV5"
pass "hv-release-detect-version exits non-zero with no version files"

echo "hv-release-bump-version"
# Case 1: package.json patch bump
BV1="$(mktemp -d)"
(
  cd "$BV1"
  printf '{"version":"1.0.0"}\n' > package.json
  NEW=$("$BIN/hv-release-bump-version" package.json package-json patch)
  [ "$NEW" = "1.0.1" ] || { echo "FAIL: expected 1.0.1, got $NEW"; exit 1; }
  grep -q '"version": "1.0.1"' package.json || { echo "FAIL: file not updated"; exit 1; }
)
pass "hv-release-bump-version bumps package.json patch"

# Case 2: minor and major bumps
(
  cd "$BV1"
  NEW=$("$BIN/hv-release-bump-version" package.json package-json minor)
  [ "$NEW" = "1.1.0" ] || { echo "FAIL: expected 1.1.0, got $NEW"; exit 1; }
  NEW=$("$BIN/hv-release-bump-version" package.json package-json major)
  [ "$NEW" = "2.0.0" ] || { echo "FAIL: expected 2.0.0, got $NEW"; exit 1; }
)
pass "hv-release-bump-version bumps minor and major"

# Case 3: explicit version bump; reject lower version
(
  cd "$BV1"
  NEW=$("$BIN/hv-release-bump-version" package.json package-json 5.0.0)
  [ "$NEW" = "5.0.0" ] || { echo "FAIL: expected 5.0.0, got $NEW"; exit 1; }
  rc=0
  ERR=$("$BIN/hv-release-bump-version" package.json package-json 1.0.0 2>&1 >/dev/null) || rc=$?
  [ "$rc" != "0" ] || { echo "FAIL: expected non-zero exit for lower version"; exit 1; }
  echo "$ERR" | grep -q "strictly greater" || { echo "FAIL: stderr missing 'strictly greater': $ERR"; exit 1; }
)
rm -rf "$BV1"
pass "hv-release-bump-version explicit version: allows higher, rejects lower"

# Case 4: pyproject.toml — only bumps [project] version, not [tool.foo]
BV2="$(mktemp -d)"
(
  cd "$BV2"
  printf '[project]\nversion = "0.1.0"\nname = "x"\n\n[tool.foo]\nversion = "9.9.9"\n' > pyproject.toml
  NEW=$("$BIN/hv-release-bump-version" pyproject.toml pyproject patch)
  [ "$NEW" = "0.1.1" ] || { echo "FAIL: expected 0.1.1, got $NEW"; exit 1; }
  grep -q 'version = "0.1.1"' pyproject.toml || { echo "FAIL: [project] version not updated"; exit 1; }
  grep -q 'version = "9.9.9"' pyproject.toml || { echo "FAIL: [tool.foo] version was modified"; exit 1; }
)
rm -rf "$BV2"
pass "hv-release-bump-version bumps only [project] in pyproject.toml"

# Case 5: Cargo.toml major bump
BV3="$(mktemp -d)"
(
  cd "$BV3"
  printf '[package]\nversion = "1.2.3"\n' > Cargo.toml
  NEW=$("$BIN/hv-release-bump-version" Cargo.toml cargo major)
  [ "$NEW" = "2.0.0" ] || { echo "FAIL: expected 2.0.0, got $NEW"; exit 1; }
)
rm -rf "$BV3"
pass "hv-release-bump-version bumps Cargo.toml major"

# Case 6: plain VERSION file minor bump
BV4="$(mktemp -d)"
(
  cd "$BV4"
  printf '0.0.1\n' > VERSION
  NEW=$("$BIN/hv-release-bump-version" VERSION plain minor)
  [ "$NEW" = "0.1.0" ] || { echo "FAIL: expected 0.1.0, got $NEW"; exit 1; }
  CONTENT=$(cat VERSION)
  [ "$CONTENT" = "0.1.0" ] || { echo "FAIL: plain file content wrong: '$CONTENT'"; exit 1; }
)
rm -rf "$BV4"
pass "hv-release-bump-version bumps plain VERSION file"

echo "hv-release-changelog-from-commits"
CL1="$(mktemp -d)"
(
  cd "$CL1"
  git init -q
  git config user.email t@t && git config user.name t
  git checkout -q -b main 2>/dev/null || git branch -m main
  # Seed an initial empty commit so HEAD~N anchors work reliably
  git commit --allow-empty -q -m "chore: init"
  git tag v_cl1_base
  git commit --allow-empty -q -m "feat: new widget"
  git commit --allow-empty -q -m "fix: null pointer"
  git commit --allow-empty -q -m "refactor: clean up internals"
  git commit --allow-empty -q -m "chore: bump deps"
  git commit --allow-empty -q -m "docs: update readme"
  git commit --allow-empty -q -m "test: add unit test"
  git commit --allow-empty -q -m "perf: speed up parser"
  git commit --allow-empty -q -m "plain commit no prefix"

  OUT=$("$BIN/hv-release-changelog-from-commits" v_cl1_base..HEAD)
  echo "$OUT" | grep -q "^## New" || { echo "FAIL: ## New missing"; exit 1; }
  echo "$OUT" | grep -q "^## Fixed" || { echo "FAIL: ## Fixed missing"; exit 1; }
  echo "$OUT" | grep -q "^## Performance" || { echo "FAIL: ## Performance missing"; exit 1; }
  echo "$OUT" | grep -q "^## Changed" || { echo "FAIL: ## Changed missing"; exit 1; }
  echo "$OUT" | grep -q "^## Documentation" || { echo "FAIL: ## Documentation missing"; exit 1; }
  echo "$OUT" | grep -q "^## Other" || { echo "FAIL: ## Other missing"; exit 1; }
  echo "$OUT" | grep -q "^## Stats" || { echo "FAIL: ## Stats missing"; exit 1; }
  if echo "$OUT" | grep -qx "^## Test"; then echo "FAIL: ## Test heading should be absent"; exit 1; fi
)
pass "hv-release-changelog-from-commits emits expected sections, skips test commits"

# Breaking change detection
(
  cd "$CL1"
  git commit --allow-empty -q -m "feat: breaking change" -m "BREAKING CHANGE: api removed"
  OUT=$("$BIN/hv-release-changelog-from-commits" v_cl1_base..HEAD)
  echo "$OUT" | grep -q "^## Breaking" || { echo "FAIL: ## Breaking missing"; exit 1; }
)
pass "hv-release-changelog-from-commits emits ## Breaking for BREAKING CHANGE body"

# Empty range → exit 0, empty stdout, stderr message
(
  cd "$CL1"
  git tag v_cl1_tip
  rc=0
  OUT=$("$BIN/hv-release-changelog-from-commits" "v_cl1_tip..v_cl1_tip" 2>/tmp/cl1_err) || rc=$?
  [ "$rc" = "0" ] || { echo "FAIL: expected exit 0 on empty range, got $rc"; exit 1; }
  [ -z "$OUT" ] || { echo "FAIL: expected empty stdout, got: $OUT"; exit 1; }
  grep -q "no commits in range" /tmp/cl1_err || { echo "FAIL: stderr missing 'no commits in range': $(cat /tmp/cl1_err)"; exit 1; }
)
rm -f /tmp/cl1_err
rm -rf "$CL1"
pass "hv-release-changelog-from-commits exits 0 with empty stdout on empty range"

echo "hv-release-update-changelog"
UC1="$(mktemp -d)"
TODAY=$(date +%Y-%m-%d)
(
  cd "$UC1"
  printf '## Highlights\n\n- thing 1\n' > notes.md
  "$BIN/hv-release-update-changelog" 1.0.0 notes.md
  [ -f CHANGELOG.md ] || { echo "FAIL: CHANGELOG.md not created"; exit 1; }
  head -1 CHANGELOG.md | grep -q "^# Changelog" || { echo "FAIL: missing # Changelog header"; exit 1; }
  grep -q "^## v1.0.0 — $TODAY" CHANGELOG.md || { echo "FAIL: missing v1.0.0 section with today's date"; exit 1; }
)
pass "hv-release-update-changelog creates CHANGELOG.md with correct header and date"

# Second version appears above first
(
  cd "$UC1"
  printf '## Notes\n\n- thing 2\n' > notes2.md
  "$BIN/hv-release-update-changelog" 1.1.0 notes2.md
  LINE110=$(grep -n "^## v1.1.0" CHANGELOG.md | cut -d: -f1)
  LINE100=$(grep -n "^## v1.0.0" CHANGELOG.md | cut -d: -f1)
  [ "$LINE110" -lt "$LINE100" ] || { echo "FAIL: v1.1.0 ($LINE110) not above v1.0.0 ($LINE100)"; exit 1; }
)
pass "hv-release-update-changelog prepends newer version above older one"

# Duplicate version → exit 1 with stderr message
(
  cd "$UC1"
  rc=0
  ERR=$("$BIN/hv-release-update-changelog" 1.1.0 notes.md 2>&1 >/dev/null) || rc=$?
  [ "$rc" != "0" ] || { echo "FAIL: expected non-zero exit for duplicate version"; exit 1; }
  echo "$ERR" | grep -q "already has a section for v1.1.0" || { echo "FAIL: stderr missing expected message: $ERR"; exit 1; }
)
pass "hv-release-update-changelog rejects duplicate version"

# --path flag
(
  cd "$UC1"
  mkdir -p docs
  "$BIN/hv-release-update-changelog" 0.0.1 notes.md --path docs/CHANGELOG.md
  [ -f docs/CHANGELOG.md ] || { echo "FAIL: docs/CHANGELOG.md not created"; exit 1; }
)
pass "hv-release-update-changelog --path writes to custom path"

# Invalid version → exit 1
(
  cd "$UC1"
  rc=0
  "$BIN/hv-release-update-changelog" 1.0 notes.md 2>/dev/null || rc=$?
  [ "$rc" != "0" ] || { echo "FAIL: expected non-zero exit for invalid version '1.0'"; exit 1; }
)
rm -rf "$UC1"
pass "hv-release-update-changelog rejects invalid version format"

echo "hv-release-detect-host"
DH1="$(mktemp -d)"
(
  cd "$DH1"
  git init -q
  git config user.email t@t && git config user.name t

  # No origin → none
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "none" ] || { echo "FAIL: expected 'none' with no origin, got '$OUT'"; exit 1; }
)
pass "hv-release-detect-host returns none with no origin"

(
  cd "$DH1"
  # SSH github.com → github
  git remote add origin git@github.com:foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "github" ] || { echo "FAIL: expected 'github' for git@github.com, got '$OUT'"; exit 1; }

  # HTTPS github.com → github
  git remote set-url origin https://github.com/foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "github" ] || { echo "FAIL: expected 'github' for https://github.com, got '$OUT'"; exit 1; }

  # gitlab.com → gitlab
  git remote set-url origin git@gitlab.com:foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "gitlab" ] || { echo "FAIL: expected 'gitlab', got '$OUT'"; exit 1; }

  # self-hosted gitlab → gitlab-self-hosted
  git remote set-url origin https://gitlab.example.com/foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "gitlab-self-hosted" ] || { echo "FAIL: expected 'gitlab-self-hosted', got '$OUT'"; exit 1; }

  # GitHub Enterprise → github-enterprise
  git remote set-url origin https://github.example.com/foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "github-enterprise" ] || { echo "FAIL: expected 'github-enterprise', got '$OUT'"; exit 1; }

  # Bitbucket (unrecognised) → none
  git remote set-url origin https://bitbucket.org/foo/bar.git
  OUT=$("$BIN/hv-release-detect-host")
  [ "$OUT" = "none" ] || { echo "FAIL: expected 'none' for bitbucket.org, got '$OUT'"; exit 1; }
)
rm -rf "$DH1"
pass "hv-release-detect-host classifies github/gitlab/github-enterprise/gitlab-self-hosted/none"

