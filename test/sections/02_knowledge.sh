echo "hv-managed-block knowledge"
mkdir -p .hv
cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Architecture
- something

## Testing
- another thing
EOF
"$BIN/hv-managed-block" knowledge >/dev/null
grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || fail "managed block not in CLAUDE.md"
grep -q "^- Architecture" CLAUDE.md || fail "Architecture topic missing"
grep -q "^- Testing" CLAUDE.md || fail "Testing topic missing"
pass "CLAUDE.md managed block created with topics"

# Re-running should update in place, not duplicate
"$BIN/hv-managed-block" knowledge >/dev/null
COUNT_START=$(grep -c "hv-knowledge-start" CLAUDE.md)
[ "$COUNT_START" = "1" ] || fail "managed block duplicated"
pass "managed block updated in place"

# Legacy colon markers in CLAUDE.md must migrate to new dashed markers in place
cat > CLAUDE.md <<'EOF'
# Preamble

<!-- hv:knowledge:start -->
## Project Knowledge
- OldTopic
<!-- hv:knowledge:end -->

# Postamble
EOF
"$BIN/hv-managed-block" knowledge >/dev/null
grep -q "<!-- hv-knowledge-start -->" CLAUDE.md || fail "legacy markers not migrated to new format"
grep -q "hv:knowledge:start" CLAUDE.md && fail "legacy colon markers still present after migration"
grep -q "^# Preamble" CLAUDE.md || fail "preamble lost during migration"
grep -q "^# Postamble" CLAUDE.md || fail "postamble lost during migration"
pass "legacy colon markers migrated to dashed format in place"

# hv-knowledge-query — unmatched topic warns on stderr, exits 0, stdout untouched (T109/#16)
# No EXIT trap here — clean up explicitly so the runner's global `$TMP` trap
# stays intact (F38 local-trap convention).
KQ_TMP="$(mktemp -d)"
mkdir -p "$KQ_TMP/.hv"
cat > "$KQ_TMP/.hv/KNOWLEDGE.md" <<'EOF'
# Knowledge

## Some Topic
- **Rule one** — body text here <!-- 2026-01-01 -->
EOF

# (a) existing topic: bullets on stdout, NO warning on stderr, exit 0
OUT=$(cd "$KQ_TMP" && "$BIN/hv-knowledge-query" "Some Topic" 2>"$KQ_TMP/err.txt"); RC=$?
ERR=$(cat "$KQ_TMP/err.txt")
[ "$RC" = "0" ] || fail "knowledge-query existing topic exit $RC (want 0)"
printf '%s\n' "$OUT" | grep -q "^## Some Topic" || fail "existing topic missing '## Some Topic' on stdout"
printf '%s\n' "$OUT" | grep -q "Rule one" || fail "existing topic missing bullet on stdout"
[ -z "$ERR" ] || fail "existing topic emitted unexpected stderr: $ERR"

# (b) bogus topic: empty stdout, warning on stderr, exit 0
OUT=$(cd "$KQ_TMP" && "$BIN/hv-knowledge-query" "Bogus" 2>"$KQ_TMP/err.txt"); RC=$?
ERR=$(cat "$KQ_TMP/err.txt")
[ "$RC" = "0" ] || fail "knowledge-query bogus topic exit $RC (want 0)"
[ -z "$OUT" ] || fail "bogus topic produced stdout: $OUT"
printf '%s\n' "$ERR" | grep -q "warning:" || fail "bogus topic missing 'warning:' on stderr"
printf '%s\n' "$ERR" | grep -q "Bogus" || fail "bogus topic warning missing topic text"

# (c) mixed real + bogus: real section on stdout, warn only about bogus, exit 0
OUT=$(cd "$KQ_TMP" && "$BIN/hv-knowledge-query" "Some Topic" "Bogus" 2>"$KQ_TMP/err.txt"); RC=$?
ERR=$(cat "$KQ_TMP/err.txt")
[ "$RC" = "0" ] || fail "knowledge-query mixed topics exit $RC (want 0)"
printf '%s\n' "$OUT" | grep -q "^## Some Topic" || fail "mixed query missing real topic on stdout"
printf '%s\n' "$ERR" | grep -q "Bogus" || fail "mixed query missing warning for bogus topic"
printf '%s\n' "$ERR" | grep -q "Some Topic" && fail "mixed query warned about matched topic"
rm -rf "$KQ_TMP"
pass "hv-knowledge-query warns on unmatched topics, silent on matches, exits 0"

