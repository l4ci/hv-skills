echo "hv-knowledge-merge preserves nested bullets in non-Glossary topics"
TMP_NEST="$(mktemp -d)"
trap 'rm -rf "$TMP_NEST"' EXIT
mkdir -p "$TMP_NEST/.hv"

cat > "$TMP_NEST/.hv/KNOWLEDGE.md" <<'EOF'
# Knowledge

Durable learnings captured from sessions.

## Architecture

- **Existing constraint** — Parent body.
  - sub-bullet detail one
  - sub-bullet detail two
  <!-- 2026-05-10 -->

## Build & Tooling

- **Existing build note** — Body. <!-- 2026-05-12 -->
EOF

# Insert a new bullet under ## Architecture. The hv-knowledge-merge parser
# uses column-0 `## ` regex via hvlib.find_section — nested bullets (which
# start with whitespace) MUST NOT be treated as topic boundaries.
( cd "$TMP_NEST" && "$BIN/hv-knowledge-merge" \
    --topic "Architecture" \
    --title "New constraint" \
    --date "2026-05-16" \
    --body "Body of the new constraint." >/dev/null )

grep -q "New constraint" "$TMP_NEST/.hv/KNOWLEDGE.md" || fail "new bullet not inserted"
grep -q "Existing constraint" "$TMP_NEST/.hv/KNOWLEDGE.md" || fail "existing bullet lost"
grep -q "sub-bullet detail one" "$TMP_NEST/.hv/KNOWLEDGE.md" || fail "nested sub-bullet one lost"
grep -q "sub-bullet detail two" "$TMP_NEST/.hv/KNOWLEDGE.md" || fail "nested sub-bullet two lost"
grep -q "Existing build note" "$TMP_NEST/.hv/KNOWLEDGE.md" || fail "Build & Tooling topic lost"

# Verify nested bullets did not migrate out of their parent — the new bullet
# must land BEFORE "Existing constraint" (prepend semantics), and the nested
# detail lines must stay attached to "Existing constraint", not the new one.
NEW_LINE=$(grep -n "New constraint" "$TMP_NEST/.hv/KNOWLEDGE.md" | head -1 | cut -d: -f1)
EXISTING_LINE=$(grep -n "Existing constraint" "$TMP_NEST/.hv/KNOWLEDGE.md" | head -1 | cut -d: -f1)
NESTED_ONE_LINE=$(grep -n "sub-bullet detail one" "$TMP_NEST/.hv/KNOWLEDGE.md" | head -1 | cut -d: -f1)
[ "$NEW_LINE" -lt "$EXISTING_LINE" ] || fail "new bullet should prepend, not append"
[ "$EXISTING_LINE" -lt "$NESTED_ONE_LINE" ] || fail "nested bullet detached from parent"

# Verify the `## Build & Tooling` topic still exists in document order after Architecture.
BUILD_LINE=$(grep -n "^## Build & Tooling$" "$TMP_NEST/.hv/KNOWLEDGE.md" | head -1 | cut -d: -f1)
[ "$NESTED_ONE_LINE" -lt "$BUILD_LINE" ] || fail "topic order disturbed"

trap 'rm -rf "$TMP"' EXIT
pass "hv-knowledge-merge preserves nested bullets in non-Glossary topics"
