echo "hv-bootstrap seeds CONTEXT.md"
TMP_BOOT="$(mktemp -d)"
( cd "$TMP_BOOT" && "$BIN/hv-bootstrap" >/dev/null )
[ -f "$TMP_BOOT/.hv/CONTEXT.md" ] || fail "hv-bootstrap: missing .hv/CONTEXT.md"
grep -q "^# Context$" "$TMP_BOOT/.hv/CONTEXT.md" || fail "CONTEXT.md missing header"
grep -q "no terms yet" "$TMP_BOOT/.hv/CONTEXT.md" || fail "CONTEXT.md missing placeholder"
# Idempotency: re-running doesn't overwrite existing content
echo "manual marker" >> "$TMP_BOOT/.hv/CONTEXT.md"
( cd "$TMP_BOOT" && "$BIN/hv-bootstrap" >/dev/null )
grep -q "manual marker" "$TMP_BOOT/.hv/CONTEXT.md" || fail "hv-bootstrap clobbered existing CONTEXT.md"
rm -rf "$TMP_BOOT"
pass "hv-bootstrap seeds CONTEXT.md and is idempotent"

echo "hv-context-query"
mkdir -p "$TMP/.hv"
cat > "$TMP/.hv/CONTEXT.md" <<'EOF'
# Context

## backlog

The canonical project queue — `.hv/TODO.md`.

**Aliases:** task list
<!-- 2026-05-10 -->

## decision

A hard project boundary captured in `DECISIONS.md`.

**Aliases:** _none_
<!-- 2026-05-10 -->
EOF
OUT=$( cd "$TMP" && "$BIN/hv-context-query" backlog )
echo "$OUT" | grep -q "^## backlog$" || fail "hv-context-query missing heading"
echo "$OUT" | grep -q "canonical project queue" || fail "hv-context-query missing body"
# Case-insensitive
OUT2=$( cd "$TMP" && "$BIN/hv-context-query" Backlog )
echo "$OUT2" | grep -q "canonical project queue" || fail "hv-context-query case-insensitive"
# Unknown term returns empty + exit 0
OUT3=$( cd "$TMP" && "$BIN/hv-context-query" nonexistent )
[ -z "$OUT3" ] || fail "hv-context-query unknown term should be empty"
# `> from:` prefix is always present, in single-repo mode too
OUT4=$( cd "$TMP" && "$BIN/hv-context-query" backlog )
echo "$OUT4" | grep -q "^> from: " || fail "hv-context-query missing > from: prefix"
echo "$OUT4" | grep -q "^> from: .hv/CONTEXT.md$" || fail "hv-context-query single-repo prefix wrong"

# Document order preserved when querying multiple terms (decision is later in the file than backlog)
OUT5=$( cd "$TMP" && "$BIN/hv-context-query" decision backlog )
B_LINE=$(echo "$OUT5" | grep -n "^## backlog$" | head -1 | cut -d: -f1)
D_LINE=$(echo "$OUT5" | grep -n "^## decision$" | head -1 | cut -d: -f1)
[ -n "$B_LINE" ] && [ -n "$D_LINE" ] && [ "$B_LINE" -lt "$D_LINE" ] || fail "hv-context-query document order not preserved"
pass "hv-context-query"

echo "hv-context-index"
( cd "$TMP" && "$BIN/hv-context-index" >/dev/null )
grep -q "<!-- hv-context-start -->" "$TMP/CLAUDE.md" || fail "hv-context-index didn't write block"
grep -q "## Project Context" "$TMP/CLAUDE.md" || fail "hv-context-index missing heading"
grep -q "\*\*backlog\*\* \*(aka task list)\*" "$TMP/CLAUDE.md" || fail "block missing aka parenthetical"
grep -q "\*\*decision\*\* —" "$TMP/CLAUDE.md" || fail "block missing decision entry"
# decision has Aliases _none_ → NO parenthetical
grep -q "\*\*decision\*\* \*(aka" "$TMP/CLAUDE.md" && fail "decision should have no aka"
grep -q "<!-- hv-context-end -->" "$TMP/CLAUDE.md" || fail "hv-context-index didn't close block"
pass "hv-context-index single-repo block"

echo "hv-context-add — single-repo new term"
TMP_ADD="$(mktemp -d)"
( cd "$TMP_ADD" && "$BIN/hv-bootstrap" >/dev/null )
( cd "$TMP_ADD" && "$BIN/hv-context-add" backlog \
    --def "The canonical project queue (.hv/TODO.md). Items are zero-padded IDs." \
    --alias "task list,todo list" )
grep -q "^## backlog$" "$TMP_ADD/.hv/CONTEXT.md" || fail "missing ## backlog"
grep -q "^\*\*Aliases:\*\* task list, todo list$" "$TMP_ADD/.hv/CONTEXT.md" || fail "aliases line wrong"
grep -q "^<!-- $(date +%Y-%m-%d) -->$" "$TMP_ADD/.hv/CONTEXT.md" || fail "date stamp missing"
grep -q "<!-- hv-context-start -->" "$TMP_ADD/CLAUDE.md" || fail "index not regenerated"
grep -q "\*\*backlog\*\* \*(aka task list, todo list)\*" "$TMP_ADD/CLAUDE.md" || fail "block missing entry"
grep -q "no terms yet" "$TMP_ADD/.hv/CONTEXT.md" && fail "placeholder should be stripped after first term added"
pass "hv-context-add — new term inserts + indexes"

echo "hv-context-add — no aliases writes _none_"
( cd "$TMP_ADD" && "$BIN/hv-context-add" session --def "An active hv-skills work cycle." )
grep -A4 "^## session$" "$TMP_ADD/.hv/CONTEXT.md" | grep -q "^\*\*Aliases:\*\* _none_$" || fail "missing _none_"
pass "hv-context-add — empty aliases produce _none_"

echo "hv-context-add — alphabetical insertion"
( cd "$TMP_ADD" && "$BIN/hv-context-add" alpha --def "First alphabetically." )
ORDER=$(grep -E '^## ' "$TMP_ADD/.hv/CONTEXT.md" | sed 's/^## //')
EXPECTED=$'alpha\nbacklog\nsession'
[ "$ORDER" = "$EXPECTED" ] || fail "alphabetical insertion failed: got '$ORDER'"
pass "hv-context-add — alphabetical insertion"

echo "hv-context-add — update existing (def replace, alias union, date preserved)"
ORIG_DATE=$(grep -A8 "^## backlog$" "$TMP_ADD/.hv/CONTEXT.md" | grep -oE '<!-- [0-9-]+ -->' | head -1)
( cd "$TMP_ADD" && "$BIN/hv-context-add" backlog \
    --def "The canonical project queue, refined." \
    --alias "queue" )
grep -A8 "^## backlog$" "$TMP_ADD/.hv/CONTEXT.md" | grep -q "queue, refined" || fail "def not replaced"
grep -A8 "^## backlog$" "$TMP_ADD/.hv/CONTEXT.md" | grep -q "\*\*Aliases:\*\* task list, todo list, queue" || fail "aliases not unioned"
grep -A8 "^## backlog$" "$TMP_ADD/.hv/CONTEXT.md" | grep -q "$ORIG_DATE" || fail "date should be preserved without --touch"
pass "hv-context-add — update preserves date, unions aliases"

echo "hv-context-add — --touch updates the date"
TODAY=$(date +%Y-%m-%d)
( cd "$TMP_ADD" && "$BIN/hv-context-add" backlog --def "X." --touch )
grep -A8 "^## backlog$" "$TMP_ADD/.hv/CONTEXT.md" | grep -q "<!-- $TODAY -->" || fail "--touch didn't bump date"
pass "hv-context-add --touch"

echo "hv-context-add — --not field"
( cd "$TMP_ADD" && "$BIN/hv-context-add" zterm --def "Z thing." --not "X, Y" )
grep -A6 "^## zterm$" "$TMP_ADD/.hv/CONTEXT.md" | grep -q "^\*\*Not:\*\* X, Y$" || fail "Not line missing"
pass "hv-context-add --not"

rm -rf "$TMP_ADD"

echo "hv-context-add — alias collision refused"
TMP_CC="$(mktemp -d)"
( cd "$TMP_CC" && "$BIN/hv-bootstrap" >/dev/null )
( cd "$TMP_CC" && "$BIN/hv-context-add" backlog --def "Q." --alias "task list" )
set +e
( cd "$TMP_CC" && "$BIN/hv-context-add" inbox --def "I." --alias "task list" 2>"$TMP_CC/err" )
RC=$?
set -e
[ $RC -ne 0 ] || fail "alias collision should exit non-zero"
grep -q "already an alias of term 'backlog'" "$TMP_CC/err" || fail "missing collision error message"
# Source file should NOT have been mutated
grep -q "^## inbox$" "$TMP_CC/.hv/CONTEXT.md" && fail "inbox should not be written on collision"
rm -rf "$TMP_CC"
pass "hv-context-add — alias collision refused"

echo "hv-context-map + hv-context-add umbrella"
TMP_UMB="$(mktemp -d)"
trap 'rm -rf "$TMP_UMB"' EXIT
mkdir -p "$TMP_UMB/repo-a" "$TMP_UMB/repo-b"
git -C "$TMP_UMB/repo-a" init -q
git -C "$TMP_UMB/repo-a" config user.email t@t
git -C "$TMP_UMB/repo-a" config user.name t
git -C "$TMP_UMB/repo-b" init -q
git -C "$TMP_UMB/repo-b" config user.email t@t
git -C "$TMP_UMB/repo-b" config user.name t
( cd "$TMP_UMB" && "$BIN/hv-bootstrap" >/dev/null )
mkdir -p "$TMP_UMB/.hv/contexts/repo-a" "$TMP_UMB/.hv/contexts/repo-b"
printf '# Context\n\n' > "$TMP_UMB/.hv/contexts/repo-a/CONTEXT.md"
printf '# Context\n\n' > "$TMP_UMB/.hv/contexts/repo-b/CONTEXT.md"
cat > "$TMP_UMB/.hv/repos.json" <<EOF
{"repos":[{"name":"repo-a","path":"repo-a"},{"name":"repo-b","path":"repo-b"}]}
EOF

# 7a. Explicit --repo umbrella writes to .hv/CONTEXT.md
( cd "$TMP_UMB" && "$BIN/hv-context-add" session --def "An active work cycle." --repo umbrella )
grep -q "^## session$" "$TMP_UMB/.hv/CONTEXT.md" || fail "umbrella write missing"

# 7b. Explicit --repo repo-a writes to contexts/repo-a/CONTEXT.md
( cd "$TMP_UMB" && "$BIN/hv-context-add" agent-loop --def "Loop in repo-a." --repo repo-a )
grep -q "^## agent-loop$" "$TMP_UMB/.hv/contexts/repo-a/CONTEXT.md" || fail "repo-a write missing"
grep -q "^## agent-loop$" "$TMP_UMB/.hv/CONTEXT.md" && fail "agent-loop should NOT be in umbrella"

# 7c. Implicit (cwd inside repo-a) resolves via hv-resolve-repo
( cd "$TMP_UMB/repo-a" && "$BIN/hv-context-add" prompt-stage --def "Stage in repo-a." )
grep -q "^## prompt-stage$" "$TMP_UMB/.hv/contexts/repo-a/CONTEXT.md" || fail "implicit repo-a write missing"

# 7d. CONTEXT-MAP.md regenerated
[ -f "$TMP_UMB/.hv/CONTEXT-MAP.md" ] || fail "CONTEXT-MAP.md missing"
grep -q "^# Context Map$" "$TMP_UMB/.hv/CONTEXT-MAP.md" || fail "CONTEXT-MAP missing header"
grep -q "Umbrella-shared" "$TMP_UMB/.hv/CONTEXT-MAP.md" || fail "CONTEXT-MAP missing umbrella heading"
grep -q "^## repo-a" "$TMP_UMB/.hv/CONTEXT-MAP.md" || fail "CONTEXT-MAP missing repo-a heading"
grep -q "agent-loop" "$TMP_UMB/.hv/CONTEXT-MAP.md" || fail "CONTEXT-MAP missing repo-a term"
grep -q "session" "$TMP_UMB/.hv/CONTEXT-MAP.md" || fail "CONTEXT-MAP missing umbrella term"

# 7e. Block ordering in CLAUDE.md from inside repo-a: shared first, then ### repo-a
( cd "$TMP_UMB/repo-a" && "$BIN/hv-context-index" >/dev/null )
SHARED_LINE=$(grep -n "\*\*session\*\*" "$TMP_UMB/CLAUDE.md" | head -1 | cut -d: -f1)
SUBHEAD_LINE=$(grep -n "^### repo-a" "$TMP_UMB/CLAUDE.md" | head -1 | cut -d: -f1)
[ -n "$SHARED_LINE" ] && [ -n "$SUBHEAD_LINE" ] && [ "$SHARED_LINE" -lt "$SUBHEAD_LINE" ] || fail "umbrella-shared not before ### repo-a"

# 7f. Unregistered --repo errors out
set +e
( cd "$TMP_UMB" && "$BIN/hv-context-add" foo --def "x." --repo nonexistent 2>"$TMP_UMB/err" )
RC=$?
set -e
[ $RC -ne 0 ] || fail "unregistered --repo should fail"
grep -q "not registered" "$TMP_UMB/err" || fail "missing 'not registered' message"

# 7g. Implicit at umbrella root (no --repo, not in a sub-repo) errors with hint
set +e
( cd "$TMP_UMB" && "$BIN/hv-context-add" foo --def "x." 2>"$TMP_UMB/err2" )
RC2=$?
set -e
[ $RC2 -ne 0 ] || fail "implicit at umbrella root should fail without --repo"
grep -q "pass --repo umbrella" "$TMP_UMB/err2" || fail "missing 'pass --repo umbrella' hint"

trap 'rm -rf "$TMP"' EXIT
pass "hv-context umbrella mode (map + add --repo + implicit resolve)"

echo "hv-context-add — cross-file alias collision (umbrella, both directions + same-name shadow allowed)"
TMP_XCC="$(mktemp -d)"
trap 'rm -rf "$TMP_XCC"' EXIT
mkdir -p "$TMP_XCC/repo-a"
git -C "$TMP_XCC/repo-a" init -q
git -C "$TMP_XCC/repo-a" config user.email t@t
git -C "$TMP_XCC/repo-a" config user.name t
( cd "$TMP_XCC" && "$BIN/hv-bootstrap" >/dev/null )
mkdir -p "$TMP_XCC/.hv/contexts/repo-a"
printf '# Context\n\n' > "$TMP_XCC/.hv/CONTEXT.md"
printf '# Context\n\n' > "$TMP_XCC/.hv/contexts/repo-a/CONTEXT.md"
cat > "$TMP_XCC/.hv/repos.json" <<EOF
{"repos":[{"name":"repo-a","path":"repo-a"}]}
EOF

# Direction A — umbrella-then-sub-repo:
# Write alias on umbrella term, then attempt same alias on a different sub-repo term.
( cd "$TMP_XCC" && "$BIN/hv-context-add" backlog --def "Umbrella backlog." --alias "task list" --repo umbrella )
set +e
( cd "$TMP_XCC" && "$BIN/hv-context-add" inbox --def "Sub-repo inbox." --alias "task list" --repo repo-a 2>"$TMP_XCC/err_a" )
RC=$?
set -e
[ $RC -eq 3 ] || fail "cross-file collision (direction A) should exit 3, got $RC"
grep -q "already an alias of term 'backlog'" "$TMP_XCC/err_a" || fail "direction A: missing collision error referencing 'backlog'"
grep -q "^## inbox$" "$TMP_XCC/.hv/contexts/repo-a/CONTEXT.md" && fail "direction A: inbox should not be written on cross-file collision"

# Direction B — sub-repo-then-umbrella (vice versa):
# Reset both files, write alias on sub-repo term, then attempt same alias on a different umbrella term.
printf '# Context\n\n' > "$TMP_XCC/.hv/CONTEXT.md"
printf '# Context\n\n' > "$TMP_XCC/.hv/contexts/repo-a/CONTEXT.md"
( cd "$TMP_XCC" && "$BIN/hv-context-add" inbox --def "Sub-repo inbox." --alias "task list" --repo repo-a )
set +e
( cd "$TMP_XCC" && "$BIN/hv-context-add" backlog --def "Umbrella backlog." --alias "task list" --repo umbrella 2>"$TMP_XCC/err_b" )
RC=$?
set -e
[ $RC -eq 3 ] || fail "cross-file collision (direction B) should exit 3, got $RC"
grep -q "already an alias of term 'inbox'" "$TMP_XCC/err_b" || fail "direction B: missing collision error referencing 'inbox'"
grep -q "^## backlog$" "$TMP_XCC/.hv/CONTEXT.md" && fail "direction B: backlog should not be written on cross-file collision"

# Same-name shadow allowed:
# Reset both files. Write alias on umbrella term 'backlog', then write the same
# alias on sub-repo term 'backlog' (same term name = shadow, not a collision).
printf '# Context\n\n' > "$TMP_XCC/.hv/CONTEXT.md"
printf '# Context\n\n' > "$TMP_XCC/.hv/contexts/repo-a/CONTEXT.md"
( cd "$TMP_XCC" && "$BIN/hv-context-add" backlog --def "Umbrella backlog." --alias "task list" --repo umbrella )
( cd "$TMP_XCC" && "$BIN/hv-context-add" backlog --def "Sub-repo backlog (shadow)." --alias "task list" --repo repo-a )
grep -q "^## backlog$" "$TMP_XCC/.hv/contexts/repo-a/CONTEXT.md" || fail "same-name shadow: sub-repo backlog should be written"

trap 'rm -rf "$TMP"' EXIT
pass "hv-context-add — cross-file alias collision (umbrella, both directions + same-name shadow allowed)"

echo "hv-context-query — umbrella mode resolves sub-repo via ORIG_CWD"
TMP_UMQ="$(mktemp -d)"
trap 'rm -rf "$TMP_UMQ"' EXIT
mkdir -p "$TMP_UMQ/repo-a"
git -C "$TMP_UMQ/repo-a" init -q
git -C "$TMP_UMQ/repo-a" config user.email t@t
git -C "$TMP_UMQ/repo-a" config user.name t
( cd "$TMP_UMQ" && "$BIN/hv-bootstrap" >/dev/null )
mkdir -p "$TMP_UMQ/.hv/contexts/repo-a"
printf '# Context\n\n' > "$TMP_UMQ/.hv/contexts/repo-a/CONTEXT.md"
cat > "$TMP_UMQ/.hv/repos.json" <<EOF
{"repos":[{"name":"repo-a","path":"repo-a"}]}
EOF
( cd "$TMP_UMQ" && "$BIN/hv-context-add" shared-term --def "Lives in umbrella." --repo umbrella )
( cd "$TMP_UMQ" && "$BIN/hv-context-add" sub-term --def "Lives in repo-a." --repo repo-a )
# From inside repo-a, query should return BOTH umbrella-shared and sub-repo entries
OUT=$( cd "$TMP_UMQ/repo-a" && "$BIN/hv-context-query" shared-term sub-term )
echo "$OUT" | grep -q "^## shared-term$" || fail "hv-context-query missing umbrella term from sub-repo cwd"
echo "$OUT" | grep -q "^## sub-term$" || fail "hv-context-query missing sub-repo term from sub-repo cwd"
echo "$OUT" | grep -q "^> from: .hv/contexts/repo-a/CONTEXT.md$" || fail "hv-context-query missing sub-repo source attribution"
trap 'rm -rf "$TMP"' EXIT
pass "hv-context-query umbrella sub-repo cwd resolution"

echo "hv-bootstrap umbrella scaffolding"
TMP_BOOT2="$(mktemp -d)"
trap 'rm -rf "$TMP_BOOT2"' EXIT
mkdir -p "$TMP_BOOT2/repo-a"
git -C "$TMP_BOOT2/repo-a" init -q
git -C "$TMP_BOOT2/repo-a" config user.email t@t
git -C "$TMP_BOOT2/repo-a" config user.name t
mkdir -p "$TMP_BOOT2/.hv"
cat > "$TMP_BOOT2/.hv/repos.json" <<EOF
{"repos":[{"name":"repo-a","path":"repo-a"}]}
EOF
( cd "$TMP_BOOT2" && "$BIN/hv-bootstrap" >/dev/null )
[ -f "$TMP_BOOT2/.hv/CONTEXT.md" ] || fail "umbrella bootstrap missing umbrella CONTEXT.md"
[ -f "$TMP_BOOT2/.hv/contexts/repo-a/CONTEXT.md" ] || fail "umbrella bootstrap missing repo-a CONTEXT.md"
[ -f "$TMP_BOOT2/.hv/CONTEXT-MAP.md" ] || fail "umbrella bootstrap missing CONTEXT-MAP.md"
grep -q "^# Context$" "$TMP_BOOT2/.hv/contexts/repo-a/CONTEXT.md" || fail "repo-a CONTEXT.md missing header"
trap 'rm -rf "$TMP"' EXIT
pass "hv-bootstrap umbrella scaffolding"

echo "/hv-context skill registered + SKILL.md present"
[ -f "$REPO/hv-context/SKILL.md" ] || fail "hv-context/SKILL.md missing"
grep -q "name: hv-context" "$REPO/hv-context/SKILL.md" || fail "SKILL.md frontmatter missing name"
grep -q "user-invocable: true" "$REPO/hv-context/SKILL.md" || fail "SKILL.md frontmatter missing user-invocable"
grep -q "/hv-context" "$REPO/bin/hv-skills-index" || fail "/hv-context not in skills-index"
grep -q "hv-context-query" "$REPO/bin/hv-skills-index" || fail "hv-context-query not in consult list"
pass "/hv-context skill registered"

echo "/hv-init Step 4 mentions hv-context-index"
grep -q "hv-context-index" "$REPO/hv-init/SKILL.md" || fail "/hv-init missing hv-context-index call"
pass "/hv-init Step 4 mentions hv-context-index"

echo "touchpoint skills consult CONTEXT"
for SK in hv-vision hv-work hv-debug hv-capture; do
  grep -q "hv-context-query\|## Project Context" "$REPO/$SK/SKILL.md" || fail "$SK SKILL.md missing CONTEXT consultation"
done
pass "touchpoint skills consult CONTEXT"

echo "hv-bootstrap single-repo doesn't create .hv/contexts/"
TMP_NOC="$(mktemp -d)"
trap 'rm -rf "$TMP_NOC"' EXIT
( cd "$TMP_NOC" && "$BIN/hv-bootstrap" >/dev/null )
[ ! -d "$TMP_NOC/.hv/contexts" ] || fail "single-repo should not create .hv/contexts/"
# Also verify empty repos array doesn't trigger
mkdir -p "$TMP_NOC/.hv"
echo '{"repos":[]}' > "$TMP_NOC/.hv/repos.json"
( cd "$TMP_NOC" && "$BIN/hv-bootstrap" >/dev/null )
[ ! -d "$TMP_NOC/.hv/contexts" ] || fail "empty repos.json should not create .hv/contexts/"
trap 'rm -rf "$TMP"' EXIT
pass "hv-bootstrap single-repo doesn't create .hv/contexts/"
