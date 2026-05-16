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

