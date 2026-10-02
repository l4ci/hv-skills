echo "hv-managed-block decisions"
mkdir -p .hv
cat > .hv/DECISIONS.md <<'EOF'
# Decisions

## Architecture

### No background queues
Background jobs run in-process.
*Why.* Operational simplicity.
**Forbids.** Adding Sidekiq, RabbitMQ, etc.
**Permits.** In-process Goroutines, threads.

## Testing

### No mocked DB in integration tests
Integration tests must hit a real database.
*Why.* Past mock/prod divergence.
**Forbids.** Mock DB libraries in tests/integration.
**Permits.** Mocks elsewhere.
EOF
"$BIN/hv-managed-block" decisions >/dev/null
grep -q "<!-- hv-decisions-start -->" CLAUDE.md || fail "hv-decisions managed block not in CLAUDE.md"
grep -q "## Project Decisions" CLAUDE.md || fail "Project Decisions heading missing"
_grep_in=$(grep -A 20 "<!-- hv-decisions-start -->" CLAUDE.md || true)
grep -q "^- Architecture" <<<"$_grep_in" || fail "Architecture topic missing in decisions block"
_grep_in=$(grep -A 20 "<!-- hv-decisions-start -->" CLAUDE.md || true)
grep -q "^- Testing" <<<"$_grep_in" || fail "Testing topic missing in decisions block"
pass "decisions managed block created with topics"

# Re-running should update in place, not duplicate
"$BIN/hv-managed-block" decisions >/dev/null
COUNT_DEC=$(grep -c "hv-decisions-start" CLAUDE.md)
[ "$COUNT_DEC" = "1" ] || fail "decisions managed block duplicated"
pass "decisions block updated in place"

# Empty .hv/DECISIONS.md (no topics) — block should still appear with placeholder
cat > .hv/DECISIONS.md <<'EOF'
# Decisions

Hard boundaries for this project.
EOF
"$BIN/hv-managed-block" decisions >/dev/null
_grep_in=$(grep -A 10 "<!-- hv-decisions-start -->" CLAUDE.md || true)
grep -q "no decisions yet" <<<"$_grep_in" || fail "empty-state placeholder missing"
pass "decisions block handles empty file"

