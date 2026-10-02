echo "hv-update-check"
# Seed a fake install with a plugin.json so detection has something to find.
mkdir -p fake-install/.claude-plugin
cat > fake-install/.claude-plugin/plugin.json <<'EOF'
{"name":"hv-skills","version":"1.2.0"}
EOF

OUT=$(HV_INSTALL_ROOT="$TMP/fake-install" HV_LATEST_VERSION=1.3.0 "$BIN/hv-update-check")
grep -q '"currentVersion": "1.2.0"' <<<"$OUT" || fail "update-check didn't read current version"
grep -q '"latestVersion": "1.3.0"' <<<"$OUT" || fail "update-check didn't use override latest"
grep -q '"status": "behind"' <<<"$OUT" || fail "update-check didn't mark behind"
pass "update-check reports behind when current < latest"

OUT=$(HV_INSTALL_ROOT="$TMP/fake-install" HV_LATEST_VERSION=1.2.0 "$BIN/hv-update-check")
grep -q '"status": "current"' <<<"$OUT" || fail "update-check didn't mark current"
pass "update-check reports current when equal"

OUT=$(HV_INSTALL_ROOT="$TMP/fake-install" HV_LATEST_VERSION=1.1.0 "$BIN/hv-update-check")
grep -q '"status": "ahead"' <<<"$OUT" || fail "update-check didn't mark ahead"
pass "update-check reports ahead when current > latest"

rm -rf fake-install

echo "hv-update-check Claude Code plugin cache layout"
# Build a fake Claude Code plugin cache with two installed versions so we can
# verify the resolver picks the newest by `sort -Vr` and reports it as plugin.
XX_TMP="$(mktemp -d)"
(
  cd "$XX_TMP"
  mkdir -p .hv/bin
  install_helpers

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
  OUT=$(unset HV_INSTALL_ROOT; HOME="$XX_TMP/fake-home" HV_LATEST_VERSION=2.0.0 .hv/bin/hv-update-check)
  grep -q '"installType": "plugin"' <<<"$OUT" || fail "cache-layout: installType != plugin: $OUT"
  grep -q '"currentVersion": "2.0.0"' <<<"$OUT" || fail "cache-layout: currentVersion != 2.0.0: $OUT"
  grep -q '/2.0.0' <<<"$OUT" || fail "cache-layout: installRoot missing /2.0.0/: $OUT"
  pass "hv-update-check resolves Claude Code plugin cache and picks newest version"

  # [B05] CLAUDE_PLUGIN_ROOT pointing at a non-hv-skills plugin must NOT be
  # honored — Claude Code sets it to whatever plugin is the active context, so
  # a cross-plugin invocation would otherwise resolve to the wrong install.
  # Resolver must validate plugin.json's `name` and fall through on mismatch.
  mkdir -p "$XX_TMP/wrong-plugin/.claude-plugin"
  cat > "$XX_TMP/wrong-plugin/.claude-plugin/plugin.json" <<'EOF2'
{"name":"context-mode","version":"1.0.89"}
EOF2
  OUT=$(unset HV_INSTALL_ROOT; CLAUDE_PLUGIN_ROOT="$XX_TMP/wrong-plugin" HOME="$XX_TMP/fake-home" \
        HV_LATEST_VERSION=2.0.0 .hv/bin/hv-update-check)
  grep -q '"currentVersion": "2.0.0"' <<<"$OUT" || fail "cache-layout: wrong CLAUDE_PLUGIN_ROOT leaked through: $OUT"
  if grep -q 'context-mode' <<<"$OUT"; then fail "cache-layout: installRoot points at non-hv-skills plugin: $OUT"; fi
  pass "hv-update-check ignores CLAUDE_PLUGIN_ROOT when its plugin.json name != hv-skills"
)
rm -rf "$XX_TMP"

echo "hv-version-check"
XX_TMP="$(mktemp -d)"
(
  cd "$XX_TMP"
  mkdir -p .hv/bin
  install_helpers

  # Test 1: no .hv/config.json → silent, exit 0.
  rm -f .hv/config.json
  OUT=$(.hv/bin/hv-version-check 2>/dev/null || fail "hv-version-check exited non-zero with no config")
  [ -z "$OUT" ] || fail "hv-version-check: expected silence with no config, got: $OUT"
  pass "hv-version-check is silent when .hv/config.json is missing"

  # Test 2: drift between stamped 1.0.0 and installed 2.0.0.
  mkdir -p "fake-home/.claude/plugins/cache/hv-skills/hv-skills/2.0.0/.claude-plugin"
  cat > "fake-home/.claude/plugins/cache/hv-skills/hv-skills/2.0.0/.claude-plugin/plugin.json" <<'EOF2'
{"name":"hv-skills","version":"2.0.0"}
EOF2
  cat > .hv/config.json <<'EOF2'
{"hvSkills":{"version":"1.0.0"}}
EOF2
  OUT=$(unset HV_INSTALL_ROOT; HOME="$XX_TMP/fake-home" .hv/bin/hv-version-check)
  grep -q '1.0.0' <<<"$OUT" || fail "drift: missing stamped 1.0.0: $OUT"
  grep -q '2.0.0' <<<"$OUT" || fail "drift: missing installed 2.0.0: $OUT"
  grep -q '/hv-init' <<<"$OUT" || fail "drift: missing /hv-init nudge: $OUT"
  pass "hv-version-check prints drift line when stamped != installed"

  # Test 3: match between stamped 2.0.0 and installed 2.0.0 → silent.
  cat > .hv/config.json <<'EOF2'
{"hvSkills":{"version":"2.0.0"}}
EOF2
  OUT=$(unset HV_INSTALL_ROOT; HOME="$XX_TMP/fake-home" .hv/bin/hv-version-check)
  [ -z "$OUT" ] || fail "match: expected silence, got: $OUT"
  pass "hv-version-check is silent when stamped == installed"

  # Test 4: --json always emits JSON with required keys.
  OUT=$(unset HV_INSTALL_ROOT; HOME="$XX_TMP/fake-home" .hv/bin/hv-version-check --json)
  grep -q '"stamped"' <<<"$OUT" || fail "--json: missing stamped key: $OUT"
  grep -q '"installed"' <<<"$OUT" || fail "--json: missing installed key: $OUT"
  grep -q '"status"' <<<"$OUT" || fail "--json: missing status key: $OUT"
  grep -q '"status": "match"' <<<"$OUT" || fail "--json: expected match status: $OUT"
  pass "hv-version-check --json emits stamped/installed/status keys"
)
rm -rf "$XX_TMP"
