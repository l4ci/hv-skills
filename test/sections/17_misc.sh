echo "hvlib.parse_toml_version"
mkdir ptv-test && cd ptv-test
RESULT=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import parse_toml_version
text1 = '[project]\nname = \"foo\"\nversion = \"1.2.3\"\n'
text2 = '[tool.poetry]\nname = \"foo\"\nversion = \"2.0.0\"\n'
text3 = '[package]\nname = \"foo\"\nversion = \"0.1.0\"\nedition = \"2021\"\n'
text4 = '[other]\nfoo = 1\n'  # no version field
text5 = '[project]\nname = \"foo\"\nversion = \"\"\n'  # empty version
print(parse_toml_version(text1, ['project']))
print(parse_toml_version(text2, ['project', 'tool.poetry']))
print(parse_toml_version(text3, ['package']))
print(repr(parse_toml_version(text4, ['project'])))
print(repr(parse_toml_version(text5, ['project'])))
")
EXPECTED=$'1.2.3\n2.0.0\n0.1.0\nNone\n\'\''
[ "$RESULT" = "$EXPECTED" ] || fail "parse_toml_version: expected:
$EXPECTED
got:
$RESULT"
pass "parse_toml_version handles project, tool.poetry, package, missing-section, and empty-string version"
cd ..

echo "hv-release-bump-version --dry-run"
mkdir bv-dry && cd bv-dry

# Create a plugin.json
echo '{"name": "foo", "version": "1.2.3"}' > plugin.json
ORIG_HASH=$(sha256sum plugin.json | cut -c1-16)

# --dry-run patch
NEW=$("$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json patch)
[ "$NEW" = "1.2.4" ] || fail "--dry-run patch: expected 1.2.4, got '$NEW'"
NEW_HASH=$(sha256sum plugin.json | cut -c1-16)
[ "$ORIG_HASH" = "$NEW_HASH" ] || fail "--dry-run patch should not modify the file"
pass "--dry-run patch prints new version, leaves file unchanged"

# --dry-run minor
NEW=$("$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json minor)
[ "$NEW" = "1.3.0" ] || fail "--dry-run minor: expected 1.3.0, got '$NEW'"
pass "--dry-run minor prints 1.3.0"

# --dry-run major
NEW=$("$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json major)
[ "$NEW" = "2.0.0" ] || fail "--dry-run major: expected 2.0.0, got '$NEW'"
pass "--dry-run major prints 2.0.0"

# --dry-run explicit semver
NEW=$("$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json 1.5.0)
[ "$NEW" = "1.5.0" ] || fail "--dry-run explicit 1.5.0: expected 1.5.0, got '$NEW'"
pass "--dry-run explicit semver prints 1.5.0"

# --dry-run rejects backwards explicit
if "$BIN/hv-release-bump-version" --dry-run plugin.json plugin-json 1.0.0 2>/dev/null; then
  fail "--dry-run should reject backwards explicit version"
fi
pass "--dry-run rejects backwards explicit version"

# Now actually bump (no --dry-run) and verify file changes
NEW=$("$BIN/hv-release-bump-version" plugin.json plugin-json patch)
[ "$NEW" = "1.2.4" ] || fail "real bump patch: expected 1.2.4, got '$NEW'"
WRITTEN=$(python3 -c "import json; print(json.loads(open('plugin.json').read())['version'])")
[ "$WRITTEN" = "1.2.4" ] || fail "real bump should write 1.2.4 to file, got '$WRITTEN'"
pass "real bump (without --dry-run) writes the new version to plugin.json"

# Test --dry-run on pyproject.toml (uses parse_toml_version path)
cat > pyproject.toml <<'EOF'
[project]
name = "foo"
version = "0.5.0"
EOF
NEW=$("$BIN/hv-release-bump-version" --dry-run pyproject.toml pyproject minor)
[ "$NEW" = "0.6.0" ] || fail "--dry-run pyproject minor: expected 0.6.0, got '$NEW'"
pass "--dry-run pyproject reads via hvlib.parse_toml_version"

# Confirm pyproject not modified
grep -q '"0.5.0"' pyproject.toml || fail "--dry-run pyproject should not modify file"
pass "--dry-run pyproject leaves file unchanged"

cd ..

echo "hv-spike-add no orphan branch on file-collision"
mkdir spike-orphan && cd spike-orphan
git init -q
git config user.email t@t && git config user.name t
git checkout -q -b main 2>/dev/null || git branch -m main
echo "x" > f && git add f && git commit -q -m "seed"
mkdir -p .hv/spikes

# Create the spike file BUT NO branch (simulating partial-state retry)
echo "leftover" > .hv/spikes/foo.md

# hv-spike-add should fail at the file-existence check, NOT create the branch
if "$BIN/hv-spike-add" foo "?" 2>/dev/null; then
  fail "hv-spike-add should fail when .hv/spikes/foo.md already exists"
fi

# CRITICAL: branch must NOT exist (orphan-branch regression test)
if git rev-parse --verify spike/foo >/dev/null 2>&1; then
  fail "hv-spike-add created branch despite file-collision — orphan branch regression"
fi
pass "hv-spike-add does not create branch when spike file already exists"
cd ..

