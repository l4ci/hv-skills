echo "update"
# Seed a fake install with a plugin.json so detection has something to find.
mkdir -p fake-install/.claude-plugin
cat > fake-install/.claude-plugin/plugin.json <<'EOF'
{"name":"hv-skills","version":"1.2.0"}
EOF

# HV_INSTALL_ROOT is the real install override; HV_TEST_LATEST_VERSION skips the network.
OUT=$(env HV_INSTALL_ROOT="$TMP/fake-install" HV_TEST_LATEST_VERSION=1.3.0 "$HV_BIN" --json update) \
  || fail "update exited non-zero"
[ "$(echo "$OUT" | jget data.currentVersion)" = "1.2.0" ] || fail "update didn't read current version: $OUT"
[ "$(echo "$OUT" | jget data.latestVersion)" = "1.3.0" ] || fail "update didn't use override latest: $OUT"
[ "$(echo "$OUT" | jget data.status)" = "behind" ] || fail "update didn't mark behind: $OUT"
[ "$(echo "$OUT" | jget data.installType)" = "override" ] || fail "update didn't report override install: $OUT"
pass "update reports behind when current < latest"

OUT=$(env HV_INSTALL_ROOT="$TMP/fake-install" HV_TEST_LATEST_VERSION=1.2.0 "$HV_BIN" --json update) \
  || fail "update exited non-zero"
[ "$(echo "$OUT" | jget data.status)" = "current" ] || fail "update didn't mark current: $OUT"
pass "update reports current when equal"

OUT=$(env HV_INSTALL_ROOT="$TMP/fake-install" HV_TEST_LATEST_VERSION=1.1.0 "$HV_BIN" --json update) \
  || fail "update exited non-zero"
[ "$(echo "$OUT" | jget data.status)" = "ahead" ] || fail "update didn't mark ahead: $OUT"
pass "update reports ahead when current > latest"

rm -rf fake-install

echo "update Claude Code plugin cache layout"
# Build a fake Claude Code plugin cache with two installed versions so we can
# verify the resolver picks the newest by `sort -Vr` and reports it as plugin.
XX_TMP="$(mktemp -d)"
trap 'rm -rf "$XX_TMP"' EXIT
(
  cd "$XX_TMP"

  # Two sibling versions; 2.0.0 must win over 1.0.0 (and over a 1.10.0-style
  # lexical winner — we use 2.0.0 to keep the assertion plain).
  for v in 1.0.0 2.0.0; do
    mkdir -p "fake-home/.claude/plugins/cache/hv-skills/hv-skills/$v/.claude-plugin"
    mkdir -p "fake-home/.claude/plugins/cache/hv-skills/hv-skills/$v/bin"
    cat > "fake-home/.claude/plugins/cache/hv-skills/hv-skills/$v/.claude-plugin/plugin.json" <<EOF2
{"name":"hv-skills","version":"$v"}
EOF2
  done

  # Unset HV_INSTALL_ROOT for this run — runner.sh exports it for preflight
  # comparisons, but here we want the cache-layout resolver to run unbiased
  # so it can pick up the fake-home/.claude/plugins/cache/... layout.
  OUT=$(env -u HV_INSTALL_ROOT HOME="$XX_TMP/fake-home" HV_TEST_LATEST_VERSION=2.0.0 "$HV_BIN" --json update)
  [ "$(echo "$OUT" | jget data.installType)" = "plugin" ] || fail "cache-layout: installType != plugin: $OUT"
  [ "$(echo "$OUT" | jget data.currentVersion)" = "2.0.0" ] || fail "cache-layout: currentVersion != 2.0.0: $OUT"
  echo "$OUT" | jget data.installRoot | grep -q '/2.0.0' || fail "cache-layout: installRoot missing /2.0.0/: $OUT"
  pass "update resolves Claude Code plugin cache and picks newest version"

  # [B05] CLAUDE_PLUGIN_ROOT pointing at a non-hv-skills plugin must NOT be
  # honored — Claude Code sets it to whatever plugin is the active context, so
  # a cross-plugin invocation would otherwise resolve to the wrong install.
  # Resolver must validate plugin.json's `name` and fall through on mismatch.
  mkdir -p "$XX_TMP/wrong-plugin/.claude-plugin"
  cat > "$XX_TMP/wrong-plugin/.claude-plugin/plugin.json" <<'EOF2'
{"name":"context-mode","version":"1.0.89"}
EOF2
  OUT=$(env -u HV_INSTALL_ROOT CLAUDE_PLUGIN_ROOT="$XX_TMP/wrong-plugin" HOME="$XX_TMP/fake-home" \
        HV_TEST_LATEST_VERSION=2.0.0 "$HV_BIN" --json update)
  [ "$(echo "$OUT" | jget data.currentVersion)" = "2.0.0" ] || fail "cache-layout: wrong CLAUDE_PLUGIN_ROOT leaked through: $OUT"
  echo "$OUT" | grep -q 'context-mode' && fail "cache-layout: installRoot points at non-hv-skills plugin: $OUT"
  pass "update ignores CLAUDE_PLUGIN_ROOT when its plugin.json name != hv-skills"
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$XX_TMP"

echo "version"
# Plain `version` needs no project: it reads plugin.json at the resolved plugin root.
EXPECTED=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' \
  "$REPO/.claude-plugin/plugin.json")
OUT=$(cd / && "$HV_BIN" --json version) || fail "version exited non-zero outside a project"
[ "$(echo "$OUT" | jget data.version)" = "$EXPECTED" ] || fail "version != plugin.json ($EXPECTED): $OUT"
pass "version prints the plugin version without a project"

echo "version --drift"
XX_TMP="$(mktemp -d)"
trap 'rm -rf "$XX_TMP"' EXIT
(
  cd "$XX_TMP"
  mkdir -p .hv

  # Test 1: no .hv/config.json → nothing stamped, so the status is unknown.
  rc=0; OUT=$("$HV_BIN" --json version --drift) || rc=$?
  [ "$rc" = 0 ] || fail "version --drift exited $rc with no config: $OUT"
  [ "$(echo "$OUT" | jget data.status)" = "unknown" ] || fail "no config: expected status unknown: $OUT"
  [ "$(echo "$OUT" | jget data.drift)" = "false" ] || fail "no config: expected drift false: $OUT"
  pass "version --drift reports unknown when .hv/config.json is missing"

  # Test 2: drift between stamped 1.0.0 and installed 2.0.0.
  mkdir -p "fake-home/.claude/plugins/cache/hv-skills/hv-skills/2.0.0/.claude-plugin"
  cat > "fake-home/.claude/plugins/cache/hv-skills/hv-skills/2.0.0/.claude-plugin/plugin.json" <<'EOF2'
{"name":"hv-skills","version":"2.0.0"}
EOF2
  cat > .hv/config.json <<'EOF2'
{"hvSkills":{"version":"1.0.0"}}
EOF2
  OUT=$(env -u HV_INSTALL_ROOT HOME="$XX_TMP/fake-home" "$HV_BIN" --json version --drift)
  [ "$(echo "$OUT" | jget data.stamped)" = "1.0.0" ] || fail "drift: wrong stamped: $OUT"
  [ "$(echo "$OUT" | jget data.installed)" = "2.0.0" ] || fail "drift: wrong installed: $OUT"
  [ "$(echo "$OUT" | jget data.version)" = "2.0.0" ] || fail "drift: version != installed: $OUT"
  [ "$(echo "$OUT" | jget data.status)" = "drift" ] || fail "drift: expected status drift: $OUT"
  [ "$(echo "$OUT" | jget data.drift)" = "true" ] || fail "drift: expected drift true: $OUT"
  pass "version --drift reports drift when stamped != installed"

  # Test 3: match between stamped 2.0.0 and installed 2.0.0.
  cat > .hv/config.json <<'EOF2'
{"hvSkills":{"version":"2.0.0"}}
EOF2
  OUT=$(env -u HV_INSTALL_ROOT HOME="$XX_TMP/fake-home" "$HV_BIN" --json version --drift)
  [ "$(echo "$OUT" | jget data.status)" = "match" ] || fail "match: expected status match: $OUT"
  [ "$(echo "$OUT" | jget data.drift)" = "false" ] || fail "match: expected drift false: $OUT"
  pass "version --drift reports match when stamped == installed"

  # Test 4: the envelope always carries the full key set.
  for k in version stamped installed status drift; do
    echo "$OUT" | jget "data.$k" >/dev/null || fail "--drift: missing $k: $OUT"
  done
  pass "version --drift carries version/stamped/installed/status/drift"
)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$XX_TMP"

# Without a project root, --drift has nothing to compare: exit 3 (resolution).
XX_TMP="$(mktemp -d)"
trap 'rm -rf "$XX_TMP"' EXIT
rc=0; (cd "$XX_TMP" && "$HV_BIN" --json version --drift >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "version --drift outside a project should exit 3, got $rc"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$XX_TMP"
pass "version --drift exits 3 outside a project"
