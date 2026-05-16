echo "hv-bootstrap pins ## Glossary in KNOWLEDGE.md"
TMP_BOOT="$(mktemp -d)"
trap 'rm -rf "$TMP_BOOT"' EXIT
( cd "$TMP_BOOT" && "$BIN/hv-bootstrap" >/dev/null )
[ -f "$TMP_BOOT/.hv/KNOWLEDGE.md" ] || fail "hv-bootstrap: missing .hv/KNOWLEDGE.md"
grep -q "^## Glossary$" "$TMP_BOOT/.hv/KNOWLEDGE.md" || fail "KNOWLEDGE.md missing pinned Glossary topic"
grep -q "no terms yet" "$TMP_BOOT/.hv/KNOWLEDGE.md" || fail "KNOWLEDGE.md Glossary missing placeholder"
# Idempotency: re-running doesn't overwrite existing content
echo "manual marker" >> "$TMP_BOOT/.hv/KNOWLEDGE.md"
( cd "$TMP_BOOT" && "$BIN/hv-bootstrap" >/dev/null )
grep -q "manual marker" "$TMP_BOOT/.hv/KNOWLEDGE.md" || fail "hv-bootstrap clobbered existing KNOWLEDGE.md"
trap 'rm -rf "$TMP"' EXIT
pass "hv-bootstrap pins Glossary + is idempotent"

echo "hv-glossary-read"
mkdir -p "$TMP/.hv"
cat > "$TMP/.hv/KNOWLEDGE.md" <<'EOF'
# Knowledge

## Glossary

- **backlog** — The canonical project queue (.hv/BACKLOG.md).
  - **Aliases:** task list
  <!-- 2026-05-10 -->

- **decision** — A hard project boundary captured in DECISIONS.md.
  - **Aliases:** _none_
  <!-- 2026-05-10 -->
EOF
OUT=$( cd "$TMP" && "$BIN/hv-glossary-read" backlog )
echo "$OUT" | grep -q "^- \*\*backlog\*\*" || fail "hv-glossary-read missing entry header"
echo "$OUT" | grep -q "canonical project queue" || fail "hv-glossary-read missing body"
# Case-insensitive
OUT2=$( cd "$TMP" && "$BIN/hv-glossary-read" Backlog )
echo "$OUT2" | grep -q "canonical project queue" || fail "hv-glossary-read case-insensitive"
# Unknown term returns empty + exit 0
OUT3=$( cd "$TMP" && "$BIN/hv-glossary-read" nonexistent )
[ -z "$OUT3" ] || fail "hv-glossary-read unknown term should be empty"
# `> from:` prefix is always present and names KNOWLEDGE.md + ## Glossary
OUT4=$( cd "$TMP" && "$BIN/hv-glossary-read" backlog )
echo "$OUT4" | grep -q "^> from: " || fail "hv-glossary-read missing > from: prefix"
echo "$OUT4" | grep -q "^> from: .hv/KNOWLEDGE.md (## Glossary)$" || fail "hv-glossary-read prefix should name KNOWLEDGE.md (## Glossary)"

# Document order preserved when querying multiple terms (decision is later in the file than backlog)
OUT5=$( cd "$TMP" && "$BIN/hv-glossary-read" decision backlog )
B_LINE=$(echo "$OUT5" | grep -n "^- \*\*backlog\*\*" | head -1 | cut -d: -f1)
D_LINE=$(echo "$OUT5" | grep -n "^- \*\*decision\*\*" | head -1 | cut -d: -f1)
[ -n "$B_LINE" ] && [ -n "$D_LINE" ] && [ "$B_LINE" -lt "$D_LINE" ] || fail "hv-glossary-read document order not preserved"
pass "hv-glossary-read"

echo "hv-glossary-write — new term"
TMP_ADD="$(mktemp -d)"
trap 'rm -rf "$TMP_ADD"' EXIT
( cd "$TMP_ADD" && "$BIN/hv-bootstrap" >/dev/null )
( cd "$TMP_ADD" && "$BIN/hv-glossary-write" backlog \
    --def "The canonical project queue (.hv/BACKLOG.md). Items are zero-padded IDs." \
    --alias "task list,todo list" )
grep -q "^- \*\*backlog\*\* — " "$TMP_ADD/.hv/KNOWLEDGE.md" || fail "missing backlog entry"
grep -q "^  - \*\*Aliases:\*\* task list, todo list$" "$TMP_ADD/.hv/KNOWLEDGE.md" || fail "aliases line wrong"
grep -q "^  <!-- $(date +%Y-%m-%d) -->$" "$TMP_ADD/.hv/KNOWLEDGE.md" || fail "date stamp missing"
grep -q "no terms yet" "$TMP_ADD/.hv/KNOWLEDGE.md" && fail "placeholder should be stripped after first term added"
# CLAUDE.md picks up Glossary via the hv-managed-block knowledge regeneration
grep -q "<!-- hv-knowledge-start -->" "$TMP_ADD/CLAUDE.md" || fail "knowledge block missing"
grep -q "^- Glossary$" "$TMP_ADD/CLAUDE.md" || fail "Glossary topic not surfaced in CLAUDE.md"
pass "hv-glossary-write — new term inserts + indexes"

echo "hv-glossary-write — no aliases writes _none_"
( cd "$TMP_ADD" && "$BIN/hv-glossary-write" session --def "An active hv-skills work cycle." )
grep -A2 "^- \*\*session\*\*" "$TMP_ADD/.hv/KNOWLEDGE.md" | grep -q "^  - \*\*Aliases:\*\* _none_$" || fail "missing _none_"
pass "hv-glossary-write — empty aliases produce _none_"

echo "hv-glossary-write — alphabetical insertion"
( cd "$TMP_ADD" && "$BIN/hv-glossary-write" alpha --def "First alphabetically." )
ORDER=$(grep -E '^- \*\*' "$TMP_ADD/.hv/KNOWLEDGE.md" | sed -E 's/^- \*\*([^*]+)\*\*.*/\1/')
EXPECTED=$'alpha\nbacklog\nsession'
[ "$ORDER" = "$EXPECTED" ] || fail "alphabetical insertion failed: got '$ORDER'"
pass "hv-glossary-write — alphabetical insertion"

echo "hv-glossary-write — update existing (def replace, alias union, date preserved)"
ORIG_DATE=$(grep -A3 "^- \*\*backlog\*\*" "$TMP_ADD/.hv/KNOWLEDGE.md" | grep -oE '<!-- [0-9-]+ -->' | head -1)
( cd "$TMP_ADD" && "$BIN/hv-glossary-write" backlog \
    --def "The canonical project queue, refined." \
    --alias "queue" )
grep -A3 "^- \*\*backlog\*\*" "$TMP_ADD/.hv/KNOWLEDGE.md" | grep -q "queue, refined" || fail "def not replaced"
grep -A3 "^- \*\*backlog\*\*" "$TMP_ADD/.hv/KNOWLEDGE.md" | grep -q "\*\*Aliases:\*\* task list, todo list, queue" || fail "aliases not unioned"
grep -A3 "^- \*\*backlog\*\*" "$TMP_ADD/.hv/KNOWLEDGE.md" | grep -q "$ORIG_DATE" || fail "date should be preserved without --touch"
pass "hv-glossary-write — update preserves date, unions aliases"

echo "hv-glossary-write — --touch updates the date"
TODAY=$(date +%Y-%m-%d)
( cd "$TMP_ADD" && "$BIN/hv-glossary-write" backlog --def "X." --touch )
grep -A3 "^- \*\*backlog\*\*" "$TMP_ADD/.hv/KNOWLEDGE.md" | grep -q "<!-- $TODAY -->" || fail "--touch didn't bump date"
pass "hv-glossary-write --touch"

echo "hv-glossary-write — --not field"
( cd "$TMP_ADD" && "$BIN/hv-glossary-write" zterm --def "Z thing." --not "X, Y" )
grep -A3 "^- \*\*zterm\*\*" "$TMP_ADD/.hv/KNOWLEDGE.md" | grep -q "^  - \*\*Not:\*\* X, Y$" || fail "Not line missing"
pass "hv-glossary-write --not"

trap 'rm -rf "$TMP"' EXIT

echo "hv-glossary-write — alias collision refused"
TMP_CC="$(mktemp -d)"
trap 'rm -rf "$TMP_CC"' EXIT
( cd "$TMP_CC" && "$BIN/hv-bootstrap" >/dev/null )
( cd "$TMP_CC" && "$BIN/hv-glossary-write" backlog --def "Q." --alias "task list" )
set +e
( cd "$TMP_CC" && "$BIN/hv-glossary-write" inbox --def "I." --alias "task list" 2>"$TMP_CC/err" )
RC=$?
set -e
[ $RC -ne 0 ] || fail "alias collision should exit non-zero"
grep -q "already an alias of term 'backlog'" "$TMP_CC/err" || fail "missing collision error message"
# Source file should NOT have been mutated
grep -q "^- \*\*inbox\*\*" "$TMP_CC/.hv/KNOWLEDGE.md" && fail "inbox should not be written on collision"
trap 'rm -rf "$TMP"' EXIT
pass "hv-glossary-write — alias collision refused"
