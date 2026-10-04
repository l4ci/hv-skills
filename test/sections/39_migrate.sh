echo "migrate — version arg validation"
RC=0; hvj migrate 2>/dev/null >&2 || RC=$?
[ $RC -eq 2 ] || fail "missing version arg should exit 2, got $RC"
RC=0; hvj migrate v3 2>/dev/null >&2 || RC=$?
[ $RC -eq 2 ] || fail "unknown version should exit 2, got $RC"
pass "migrate — version arg validation"

echo "migrate v4 — refuses pre-3.0 project"
TMP_OLD="$(mktemp -d)"
trap 'rm -rf "$TMP_OLD"' EXIT
( cd "$TMP_OLD" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_OLD/.hv"
echo '{"version":"2.9.0"}' > "$TMP_OLD/.hv/config.json"
RC=0
OUT=$( cd "$TMP_OLD" && hvj migrate v4 2>/dev/null ) || RC=$?
[ $RC -eq 4 ] || fail "pre-3.0 should exit 4, got $RC"
[ "$(jget data.blockedBy <<<"$OUT")" = "pre-3.0" ] || fail "pre-3.0 refusal data: $OUT"
[ "$(jget data.changed <<<"$OUT")" = "false" ] || fail "refusal must report changed=false: $OUT"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — refuses pre-3.0 project"

echo "migrate v4 — umbrella project no longer refused (F21)"
TMP_UMB="$(mktemp -d)"
trap 'rm -rf "$TMP_UMB"' EXIT
( cd "$TMP_UMB" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_UMB/.hv"
echo '{"version":"3.4.0"}' > "$TMP_UMB/.hv/config.json"
echo '{"repos":[{"name":"web","path":"./web"},{"name":"api","path":"./api"}]}' > "$TMP_UMB/.hv/repos.json"
RC=0
OUT=$( cd "$TMP_UMB" && hvj migrate v4 2>/dev/null ) || RC=$?
# F21 lifted the umbrella refusal — migrate proceeds. With no per-sub-repo
# CONTEXT.md in this fixture there is nothing to migrate, so it's a clean
# no-op dry-run (exit 0). The deep umbrella migration path is covered by
# test/sections/46_umbrella_knowledge.sh.
[ $RC -eq 0 ] || fail "umbrella should no longer refuse (expected exit 0, got $RC)"
[ "$(jget data.noop <<<"$OUT")" = "true" ] || fail "umbrella with nothing to migrate should be a noop: $OUT"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — umbrella project no longer refused (F21)"

echo "migrate v4 — refuses dirty tree outside .hv/"
TMP_DIRTY="$(mktemp -d)"
trap 'rm -rf "$TMP_DIRTY"' EXIT
( cd "$TMP_DIRTY" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_DIRTY/.hv" "$TMP_DIRTY/src"
echo '{"version":"3.4.0"}' > "$TMP_DIRTY/.hv/config.json"
echo "x" > "$TMP_DIRTY/src/foo.txt"
( cd "$TMP_DIRTY" && git add -A && git commit -q -m init )
echo "dirty" >> "$TMP_DIRTY/src/foo.txt"
RC=0
OUT=$( cd "$TMP_DIRTY" && hvj migrate v4 2>/dev/null ) || RC=$?
[ $RC -eq 4 ] || fail "dirty tree should exit 4, got $RC"
[ "$(jget data.blockedBy <<<"$OUT")" = "dirty-tree" ] || fail "dirty-tree refusal data: $OUT"
RC=0
( cd "$TMP_DIRTY" && hvj migrate v4 --apply >/dev/null 2>&1 ) || RC=$?
[ $RC -eq 4 ] || fail "dirty tree should also refuse --apply with exit 4, got $RC"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — refuses dirty tree outside .hv/"

echo "migrate v4 — dry-run reports rewrites; --apply writes; idempotent"
TMP_REW="$(mktemp -d)"
trap 'rm -rf "$TMP_REW"' EXIT
( cd "$TMP_REW" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_REW/.hv/plans" "$TMP_REW/.hv/designs"
echo '{"version":"3.4.0"}' > "$TMP_REW/.hv/config.json"
cat > "$TMP_REW/.hv/BACKLOG.md" <<'EOF'
# TODO
## Bugs
- **[B07] [P2] Sample.** Use /hv-context to lookup, then /hv-rm B07 if obsolete. Also /hv-undo, /hv-docs, /hv-assume, /hv-c.
EOF
cat > "$TMP_REW/CLAUDE.md" <<'EOF'
# Project
Run /hv-context for terms. /hv-capture is the new way to capture.
EOF
( cd "$TMP_REW" && git add -A && git commit -q -m init )

# Dry-run: should report 6 references rewritten, file unchanged on disk.
OUT_DRY=$( cd "$TMP_REW" && hvj migrate v4 )
[ "$(jget data.applied <<<"$OUT_DRY")" = "false" ] || fail "dry-run must not report applied: $OUT_DRY"
[ "$(jget data.changed <<<"$OUT_DRY")" = "false" ] || fail "dry-run must report changed=false: $OUT_DRY"
[ "$(jget data.referencesRewritten <<<"$OUT_DRY")" = "7" ] || fail "dry-run should count 7 references (6 in BACKLOG + 1 in CLAUDE): $OUT_DRY"
[ "$(jget data.filesRewritten <<<"$OUT_DRY")" = "2" ] || fail "dry-run should count 2 files: $OUT_DRY"
grep -q "preview only" <<<"$(jget warnings <<<"$OUT_DRY")" || fail "dry-run should warn to pass --apply: $OUT_DRY"
OUT_VERB=$( cd "$TMP_REW" && hvj migrate v4 --verbose )
[ "$(jget data.diffs <<<"$OUT_VERB" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" = "2" ] || fail "--verbose should add one diff per rewritten file: $OUT_VERB"
grep -q "/hv-context" "$TMP_REW/.hv/BACKLOG.md" || fail "dry-run wrote to disk (must not)"

# Apply.
OUT_APPLY=$( cd "$TMP_REW" && hvj migrate v4 --apply )
[ "$(jget data.applied <<<"$OUT_APPLY")" = "true" ] || fail "--apply should report applied: $OUT_APPLY"
[ "$(jget data.changed <<<"$OUT_APPLY")" = "true" ] || fail "--apply should report changed: $OUT_APPLY"
[ -d "$TMP_REW/$(jget data.backup <<<"$OUT_APPLY")" ] || fail "--apply should report the backup path: $OUT_APPLY"

# Verify rewrites.
grep -q "/hv-learn --term" "$TMP_REW/.hv/BACKLOG.md" || fail "/hv-context not rewritten"
grep -q "/hv-capture --remove" "$TMP_REW/.hv/BACKLOG.md" || fail "/hv-rm not rewritten"
grep -q "/hv-ship --undo" "$TMP_REW/.hv/BACKLOG.md" || fail "/hv-undo not rewritten"
grep -q "/hv-ship --docs" "$TMP_REW/.hv/BACKLOG.md" || fail "/hv-docs not rewritten"
grep -q "/hv-work --preview" "$TMP_REW/.hv/BACKLOG.md" || fail "/hv-assume not rewritten"
grep -q "/hv-capture is the new" "$TMP_REW/CLAUDE.md" || fail "/hv-capture (already correct) should survive"
# Word-boundary check: /hv-c rewrites to /hv-capture, but /hv-capture itself is untouched.
[ "$(grep -c "/hv-capture" "$TMP_REW/CLAUDE.md")" -ge 1 ] || fail "/hv-capture should appear in CLAUDE.md"
grep -q "/hv-context" "$TMP_REW/.hv/BACKLOG.md" && fail "stale /hv-context left after rewrite"
grep -q "/hv-rm\b" "$TMP_REW/.hv/BACKLOG.md" && fail "stale /hv-rm left after rewrite"

# Backup tree preserves original.
BACKUP_DIR=$(ls -d "$TMP_REW"/.hv/migrate-backup/*/ 2>/dev/null | head -1)
[ -n "$BACKUP_DIR" ] || fail "no backup directory created"
grep -q "/hv-context" "$BACKUP_DIR/.hv/BACKLOG.md" || fail "backup didn't preserve original BACKLOG.md"

# Idempotency — commit the apply's writes first (realistic UX), then re-run.
( cd "$TMP_REW" && git add -A && git commit -q -m "v4 migration" )
OUT_AGAIN=$( cd "$TMP_REW" && hvj migrate v4 --apply )
[ "$(jget data.noop <<<"$OUT_AGAIN")" = "true" ] || fail "second --apply should be noop: $OUT_AGAIN"
[ "$(jget data.changed <<<"$OUT_AGAIN")" = "false" ] || fail "second --apply should report changed=false: $OUT_AGAIN"
[ "$(jget data.filesRewritten <<<"$OUT_AGAIN")" = "0" ] || fail "second --apply should rewrite zero files: $OUT_AGAIN"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — dry-run + apply + idempotency"

echo "migrate v4 — flags /hv-issues and /hv-map for manual review"
TMP_AMB="$(mktemp -d)"
trap 'rm -rf "$TMP_AMB"' EXIT
( cd "$TMP_AMB" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_AMB/.hv"
echo '{"version":"3.4.0"}' > "$TMP_AMB/.hv/config.json"
cat > "$TMP_AMB/.hv/BACKLOG.md" <<'EOF'
# TODO
## Tasks
- **[T11]** Run /hv-issues to import, then /hv-map for layout.
EOF
( cd "$TMP_AMB" && git add -A && git commit -q -m init )

RC=0
OUT_AMB=$( cd "$TMP_AMB" && hvj migrate v4 ) || RC=$?
[ $RC -eq 0 ] || fail "a preview with manual-review items is still exit 0, got $RC"
[ "$(jget data.manualReview <<<"$OUT_AMB")" = "2" ] || fail "should report 2 manual-review items: $OUT_AMB"
[ "$(jget data.referencesRewritten <<<"$OUT_AMB")" = "0" ] || fail "ambiguous references must not count as rewritten: $OUT_AMB"

# Apply should NOT rewrite ambiguous ones.
( cd "$TMP_AMB" && "$HV_BIN" migrate v4 --apply >/dev/null )
grep -q "/hv-issues" "$TMP_AMB/.hv/BACKLOG.md" || fail "/hv-issues should be preserved (manual review)"
grep -q "/hv-map" "$TMP_AMB/.hv/BACKLOG.md" || fail "/hv-map should be preserved (manual review)"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — /hv-issues and /hv-map flagged, not rewritten"

echo "migrate v4 — migrates CONTEXT.md terms into Glossary; deletes CONTEXT.md"
TMP_CTX="$(mktemp -d)"
trap 'rm -rf "$TMP_CTX"' EXIT
( cd "$TMP_CTX" && git init -q && git config user.email t@t && git config user.name t )
( cd "$TMP_CTX" && "$HV_BIN" init >/dev/null )
echo '{"version":"3.4.0"}' > "$TMP_CTX/.hv/config.json"
cat > "$TMP_CTX/.hv/CONTEXT.md" <<'EOF'
# Context

Domain terminology.

## backlog

The canonical project queue (.hv/BACKLOG.md). Items are zero-padded.

**Aliases:** task list, todo list

## decision

A hard project boundary captured in DECISIONS.md.

**Aliases:** _none_
**Not:** preference, learning
EOF
( cd "$TMP_CTX" && git add -A && git commit -q -m init )

( cd "$TMP_CTX" && "$HV_BIN" migrate v4 --apply >/dev/null )
[ ! -f "$TMP_CTX/.hv/CONTEXT.md" ] || fail "CONTEXT.md should be deleted after migration"
grep -q "^- \*\*backlog\*\* — " "$TMP_CTX/.hv/KNOWLEDGE.md" || fail "backlog term missing from KNOWLEDGE.md Glossary"
grep -q "^- \*\*decision\*\* — " "$TMP_CTX/.hv/KNOWLEDGE.md" || fail "decision term missing from KNOWLEDGE.md Glossary"
grep -q "task list, todo list" "$TMP_CTX/.hv/KNOWLEDGE.md" || fail "backlog aliases missing"
grep -q "preference, learning" "$TMP_CTX/.hv/KNOWLEDGE.md" || fail "decision nots missing"

# Backup preserves CONTEXT.md
BACKUP_CTX=$(ls -d "$TMP_CTX"/.hv/migrate-backup/*/ 2>/dev/null | head -1)
[ -f "$BACKUP_CTX/CONTEXT.md" ] || fail "CONTEXT.md backup missing"
grep -q "^## backlog$" "$BACKUP_CTX/CONTEXT.md" || fail "CONTEXT.md backup content corrupted"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — CONTEXT.md → KNOWLEDGE.md Glossary migration"

echo "migrate v4 — empty CONTEXT.md is deleted, no batch call"
TMP_CTX_EMPTY="$(mktemp -d)"
trap 'rm -rf "$TMP_CTX_EMPTY"' EXIT
( cd "$TMP_CTX_EMPTY" && git init -q && git config user.email t@t && git config user.name t )
( cd "$TMP_CTX_EMPTY" && "$HV_BIN" init >/dev/null )
echo '{"version":"3.4.0"}' > "$TMP_CTX_EMPTY/.hv/config.json"
cat > "$TMP_CTX_EMPTY/.hv/CONTEXT.md" <<'EOF'
# Context

_(no terms yet)_
EOF
( cd "$TMP_CTX_EMPTY" && git add -A && git commit -q -m init )
( cd "$TMP_CTX_EMPTY" && "$HV_BIN" migrate v4 --apply >/dev/null )
[ ! -f "$TMP_CTX_EMPTY/.hv/CONTEXT.md" ] || fail "empty CONTEXT.md should be deleted"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — empty CONTEXT.md deleted with no batch call"


echo "migrate v4 — word boundary: /hv-capture is NOT rewritten by /hv-c\\b rule"
TMP_WB="$(mktemp -d)"
trap 'rm -rf "$TMP_WB"' EXIT
( cd "$TMP_WB" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_WB/.hv"
echo '{"version":"3.4.0"}' > "$TMP_WB/.hv/config.json"
cat > "$TMP_WB/.hv/BACKLOG.md" <<'EOF'
# TODO
## Bugs
- **[B01]** /hv-capture is correct; /hv-c is the old alias.
EOF
( cd "$TMP_WB" && git add -A && git commit -q -m init )

( cd "$TMP_WB" && "$HV_BIN" migrate v4 --apply >/dev/null )
# Expected after rewrite: "/hv-capture is correct; /hv-capture is the old alias."
[ "$(grep -c "/hv-capture is correct" "$TMP_WB/.hv/BACKLOG.md")" = "1" ] || fail "/hv-capture survived unscathed"
[ "$(grep -c "/hv-capture is the old alias" "$TMP_WB/.hv/BACKLOG.md")" = "1" ] || fail "/hv-c should rewrite to /hv-capture"
grep -q "/hv-c is" "$TMP_WB/.hv/BACKLOG.md" && fail "stale /hv-c left after rewrite"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — word boundary: /hv-capture preserved, /hv-c rewritten"

echo "migrate v4 — B07: reads hvSkills.version when top-level 'version' absent"
TMP_B07="$(mktemp -d)"
trap 'rm -rf "$TMP_B07"' EXIT
( cd "$TMP_B07" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_B07/.hv"
# Fresh v4 init shape: ONLY hvSkills.version, no top-level "version" field.
echo '{"hvSkills":{"version":"4.0.0"}}' > "$TMP_B07/.hv/config.json"
( cd "$TMP_B07" && git add -A && git commit -q -m init )
# Should pass the safety precondition: exit 3 (config has no version) is B07 still firing.
RC=0
OUT=$( cd "$TMP_B07" && hvj migrate v4 2>/dev/null ) || RC=$?
[ $RC -eq 0 ] || fail "B07: nested hvSkills.version should not trigger the missing-version refusal, got exit $RC"
[ "$(jget data.noop <<<"$OUT")" = "true" ] || fail "B07: a v4 project with nothing to rewrite should be a noop: $OUT"
# A config with no version at all is exit 3.
echo '{}' > "$TMP_B07/.hv/config.json"
RC=0; ( cd "$TMP_B07" && hvj migrate v4 >/dev/null 2>&1 ) || RC=$?
[ $RC -eq 3 ] || fail "B07: a config with no version should exit 3, got $RC"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — B07: reads hvSkills.version when top-level 'version' absent"

echo "migrate v4 — B08: --apply bumps hvSkills.version to installed plugin"
TMP_B08="$(mktemp -d)"
trap 'rm -rf "$TMP_B08"' EXIT
( cd "$TMP_B08" && git init -q && git config user.email t@t && git config user.name t )
( cd "$TMP_B08" && "$HV_BIN" init >/dev/null )
echo '{"version":"3.4.0","hvSkills":{"version":"3.4.0"}}' > "$TMP_B08/.hv/config.json"
( cd "$TMP_B08" && git add -A && git commit -q -m init )

OUT=$( cd "$TMP_B08" && hvj migrate v4 --apply )

# Legacy top-level "version" should be cleaned up.
HAS_LEGACY=$(python3 -c "import json; print('yes' if 'version' in json.load(open('$TMP_B08/.hv/config.json')) else 'no')")
[ "$HAS_LEGACY" = "no" ] || fail "B08: legacy top-level 'version' should be removed after migration"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — B08: --apply bumps hvSkills.version"

echo "migrate v4 — B09: strips orphan v3 blocks"
cd "$TMP"
trap 'rm -rf "$TMP"' EXIT

# The same strip through the verb: the preview names the block, --apply removes it.
TMP_STRIP2="$(mktemp -d)"
trap 'rm -rf "$TMP_STRIP2"' EXIT
( cd "$TMP_STRIP2" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_STRIP2/.hv"
echo '{"version":"3.4.0"}' > "$TMP_STRIP2/.hv/config.json"
# A /hv-rm reference gives the run something to rewrite. The contract strips on every call, but
# the old helper (behind the shim) skips the strip on an otherwise-noop project, so this fixture
# avoids that case rather than assert either behaviour.
cat > "$TMP_STRIP2/CLAUDE.md" <<'EOF'
# Project

Use /hv-rm to delete.

<!-- hv-knowledge-start -->
## Project Knowledge
Live block — must survive.
<!-- hv-knowledge-end -->

<!-- hv-context-start -->
## Project Context
Orphan block — must be stripped.
<!-- hv-context-end -->

Regular prose stays.
EOF
( cd "$TMP_STRIP2" && git add -A && git commit -q -m init )
OUT=$( cd "$TMP_STRIP2" && hvj migrate v4 )
[ "$(jget data.strippedBlocks <<<"$OUT")" = '["context"]' ] || fail "B09-d1: preview should name the context block: $OUT"
grep -q "hv-context-start" "$TMP_STRIP2/CLAUDE.md" || fail "B09-d1: preview must not strip the block"
OUT=$( cd "$TMP_STRIP2" && hvj migrate v4 --apply )
[ "$(jget data.strippedBlocks <<<"$OUT")" = '["context"]' ] || fail "B09-d1: --apply should report the stripped block: $OUT"
grep -q "hv-context-start" "$TMP_STRIP2/CLAUDE.md" && fail "B09-d1: --apply should strip the orphan hv-context block"
grep -q "hv-knowledge-start" "$TMP_STRIP2/CLAUDE.md" || fail "B09-d1: live hv-knowledge block should survive --apply"
grep -q "Regular prose stays" "$TMP_STRIP2/CLAUDE.md" || fail "B09-d1: surrounding prose must survive --apply"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — B09: strips orphan v3 blocks"

echo "migrate v4 — B09: rewrite_text skips fenced/inline code + helper-path tokens"
TMP_B09D2="$(mktemp -d)"
trap 'rm -rf "$TMP_B09D2"' EXIT
( cd "$TMP_B09D2" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_B09D2/.hv"
echo '{"version":"3.4.0"}' > "$TMP_B09D2/.hv/config.json"
# Fixture covers four cases:
#   (a) `/hv-context` inside inline code — must NOT be rewritten
#   (b) `/hv-context` in a fenced block — must NOT be rewritten
#   (c) `hv-map-query` substring inside a helper-path token — must NOT be rewritten
#   (d) bare `/hv-context` in prose — must be rewritten (control case)
cat > "$TMP_B09D2/.hv/BACKLOG.md" <<'EOF'
# TODO
## Bugs
- **[B01]** Mention `/hv-context` inline — preserve as a literal name.

  ```
  This fenced block names /hv-context literally.
  ```

  Use `scripts/hv-map-query` to query the map — substring `hv-map` is part of a helper path.

  Bare /hv-context in prose should still rewrite (control).
EOF
( cd "$TMP_B09D2" && git add -A && git commit -q -m init )

( cd "$TMP_B09D2" && "$HV_BIN" migrate v4 --apply >/dev/null )

# (a) inline-code mention preserved
grep -q '`/hv-context`' "$TMP_B09D2/.hv/BACKLOG.md" || fail "B09-d2: inline-code /hv-context should be preserved"
# (b) fenced-block mention preserved
grep -q 'fenced block names /hv-context literally' "$TMP_B09D2/.hv/BACKLOG.md" || fail "B09-d2: fenced /hv-context should be preserved"
# (c) helper-path token preserved (no rewrite of the embedded "/hv-map" inside the path-like token)
grep -q 'hv-map-query' "$TMP_B09D2/.hv/BACKLOG.md" || fail "B09-d2: hv-map-query helper-path token should be preserved verbatim"
# (d) bare prose mention rewritten to /hv-learn --term (control — proves rewriting still works outside masks)
grep -q 'Bare /hv-learn --term in prose' "$TMP_B09D2/.hv/BACKLOG.md" || fail "B09-d2: bare /hv-context in prose should rewrite to /hv-learn --term"
trap 'rm -rf "$TMP"' EXIT
pass "migrate v4 — B09: rewrite_text skips fenced/inline code + helper-path tokens"
