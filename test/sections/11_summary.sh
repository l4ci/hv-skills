echo "hv-summary"
# Reset to a known state and check the summary lines
rm -f .hv/ARCHIVE.md
cat > .hv/TODO.md <<'EOF'
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
echo "$OUT" | grep -q "1 bug," || fail "bug count wrong: $OUT"
echo "$OUT" | grep -q "2 features," || fail "feature count wrong: $OUT"
echo "$OUT" | grep -q "0 tasks" || fail "task count wrong: $OUT"
echo "$OUT" | grep -q "Recent: \[B01\]" || fail "recent completion missing: $OUT"
echo "$OUT" | grep -q "Knowledge: 2 topics" || fail "knowledge topic count wrong: $OUT"
pass "summary reports backlog/recent/knowledge correctly"

