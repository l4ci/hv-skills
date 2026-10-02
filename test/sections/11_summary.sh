echo "hv-summary"
# Reset to a known state and check the summary lines
rm -f .hv/ARCHIVE.md
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs
- **[B60] [P1] Active bug.** Desc.

## Features
- **[F60] [Minor] Pending feature.** Desc.
- **[F61] [Cosmetic] Another feature.** Desc.

## Tasks

## Completed
- ~~**[B01] Resolved bug.**~~ Done 2026-04-18 [`abc1234`]
EOF
cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Architecture
- a

## Testing
- t
EOF
OUT=$("$BIN/hv-summary")
grep -q "1 bug," <<<"$OUT" || fail "bug count wrong: $OUT"
grep -q "2 features," <<<"$OUT" || fail "feature count wrong: $OUT"
grep -q "0 tasks" <<<"$OUT" || fail "task count wrong: $OUT"
grep -q "Recent: \[B01\]" <<<"$OUT" || fail "recent completion missing: $OUT"
grep -q "Knowledge: 2 topics" <<<"$OUT" || fail "knowledge topic count wrong: $OUT"
pass "summary reports backlog/recent/knowledge correctly"

