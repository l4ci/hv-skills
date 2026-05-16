echo "hv-migrate — version arg validation"
set +e
"$BIN/hv-migrate" 2>"$TMP/.hv/err_no_ver"; RC=$?
set -e
[ $RC -eq 2 ] || fail "missing version arg should exit 2, got $RC"
grep -q "version arg required" "$TMP/.hv/err_no_ver" || fail "missing version arg message"

set +e
"$BIN/hv-migrate" v3 2>"$TMP/.hv/err_v3"; RC=$?
set -e
[ $RC -eq 2 ] || fail "unknown version should exit 2, got $RC"
grep -q "only 'v4' supported" "$TMP/.hv/err_v3" || fail "unknown version message"
pass "hv-migrate — version arg validation"

echo "hv-migrate — refuses pre-3.0 project"
TMP_OLD="$(mktemp -d)"
trap 'rm -rf "$TMP_OLD"' EXIT
( cd "$TMP_OLD" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_OLD/.hv"
echo '{"version":"2.9.0"}' > "$TMP_OLD/.hv/config.json"
set +e
( cd "$TMP_OLD" && "$BIN/hv-migrate" v4 2>"$TMP_OLD/.hv/err" ); RC=$?
set -e
[ $RC -eq 1 ] || fail "pre-3.0 should exit 1, got $RC"
grep -q "pre-3.0" "$TMP_OLD/.hv/err" || fail "pre-3.0 refusal message"
trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate — refuses pre-3.0 project"

echo "hv-migrate — refuses umbrella project"
TMP_UMB="$(mktemp -d)"
trap 'rm -rf "$TMP_UMB"' EXIT
( cd "$TMP_UMB" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_UMB/.hv"
echo '{"version":"3.4.0"}' > "$TMP_UMB/.hv/config.json"
echo '{"repos":[{"name":"web","path":"./web"},{"name":"api","path":"./api"}]}' > "$TMP_UMB/.hv/repos.json"
set +e
( cd "$TMP_UMB" && "$BIN/hv-migrate" v4 2>"$TMP_UMB/.hv/err" ); RC=$?
set -e
[ $RC -eq 1 ] || fail "umbrella should exit 1, got $RC"
grep -q "umbrella project detected" "$TMP_UMB/.hv/err" || fail "umbrella refusal message"
grep -q "F21" "$TMP_UMB/.hv/err" || fail "umbrella message should cite F21"
trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate — refuses umbrella project"

echo "hv-migrate — refuses dirty tree outside .hv/"
TMP_DIRTY="$(mktemp -d)"
trap 'rm -rf "$TMP_DIRTY"' EXIT
( cd "$TMP_DIRTY" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_DIRTY/.hv" "$TMP_DIRTY/src"
echo '{"version":"3.4.0"}' > "$TMP_DIRTY/.hv/config.json"
echo "x" > "$TMP_DIRTY/src/foo.txt"
( cd "$TMP_DIRTY" && git add -A && git commit -q -m init )
echo "dirty" >> "$TMP_DIRTY/src/foo.txt"
set +e
( cd "$TMP_DIRTY" && "$BIN/hv-migrate" v4 2>"$TMP_DIRTY/.hv/err" ); RC=$?
set -e
[ $RC -eq 1 ] || fail "dirty tree should exit 1, got $RC"
grep -q "uncommitted changes outside .hv/" "$TMP_DIRTY/.hv/err" || fail "dirty-tree refusal message"
trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate — refuses dirty tree outside .hv/"

echo "hv-migrate — dry-run reports rewrites; --apply writes; idempotent"
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
OUT_DRY=$( cd "$TMP_REW" && "$BIN/hv-migrate" v4 )
echo "$OUT_DRY" | grep -q "dry-run" || fail "dry-run header missing"
echo "$OUT_DRY" | grep -q "references rewritten: 7" || fail "dry-run should count 7 references (6 in BACKLOG + 1 in CLAUDE)"
echo "$OUT_DRY" | grep -q "Run with --apply" || fail "dry-run should suggest --apply"
grep -q "/hv-context" "$TMP_REW/.hv/BACKLOG.md" || fail "dry-run wrote to disk (must not)"

# Apply.
OUT_APPLY=$( cd "$TMP_REW" && "$BIN/hv-migrate" v4 --apply )
echo "$OUT_APPLY" | grep -q "applied. backup at:" || fail "--apply should report backup path"

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
OUT_AGAIN=$( cd "$TMP_REW" && "$BIN/hv-migrate" v4 --apply )
echo "$OUT_AGAIN" | grep -q "noop: project is already on v4" || fail "second --apply should be noop"
trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate — dry-run + apply + idempotency"

echo "hv-migrate — flags /hv-issues and /hv-map for manual review"
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

OUT_AMB=$( cd "$TMP_AMB" && "$BIN/hv-migrate" v4 )
echo "$OUT_AMB" | grep -q "manual review:" || fail "manual review section missing"
echo "$OUT_AMB" | grep -qE "manual review:.*2|manual review:\s+2" || fail "should report 2 manual-review items"
echo "$OUT_AMB" | grep -q "hv-issues" || fail "should flag /hv-issues"
echo "$OUT_AMB" | grep -q "hv-map" || fail "should flag /hv-map"
echo "$OUT_AMB" | grep -q "ambiguous" || fail "should call out ambiguity"

# Apply should NOT rewrite ambiguous ones.
( cd "$TMP_AMB" && "$BIN/hv-migrate" v4 --apply >/dev/null )
grep -q "/hv-issues" "$TMP_AMB/.hv/BACKLOG.md" || fail "/hv-issues should be preserved (manual review)"
grep -q "/hv-map" "$TMP_AMB/.hv/BACKLOG.md" || fail "/hv-map should be preserved (manual review)"
trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate — /hv-issues and /hv-map flagged, not rewritten"

echo "hv-migrate — migrates CONTEXT.md terms into Glossary; deletes CONTEXT.md"
TMP_CTX="$(mktemp -d)"
trap 'rm -rf "$TMP_CTX"' EXIT
( cd "$TMP_CTX" && git init -q && git config user.email t@t && git config user.name t )
( cd "$TMP_CTX" && "$BIN/hv-bootstrap" >/dev/null )
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

( cd "$TMP_CTX" && "$BIN/hv-migrate" v4 --apply >/dev/null )
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
pass "hv-migrate — CONTEXT.md → KNOWLEDGE.md Glossary migration"

echo "hv-migrate — empty CONTEXT.md is deleted, no batch call"
TMP_CTX_EMPTY="$(mktemp -d)"
trap 'rm -rf "$TMP_CTX_EMPTY"' EXIT
( cd "$TMP_CTX_EMPTY" && git init -q && git config user.email t@t && git config user.name t )
( cd "$TMP_CTX_EMPTY" && "$BIN/hv-bootstrap" >/dev/null )
echo '{"version":"3.4.0"}' > "$TMP_CTX_EMPTY/.hv/config.json"
cat > "$TMP_CTX_EMPTY/.hv/CONTEXT.md" <<'EOF'
# Context

_(no terms yet)_
EOF
( cd "$TMP_CTX_EMPTY" && git add -A && git commit -q -m init )
( cd "$TMP_CTX_EMPTY" && "$BIN/hv-migrate" v4 --apply >/dev/null )
[ ! -f "$TMP_CTX_EMPTY/.hv/CONTEXT.md" ] || fail "empty CONTEXT.md should be deleted"
trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate — empty CONTEXT.md deleted with no batch call"

echo "hv-migrate — removes stale .hv/bin/hv-context-* files"
TMP_BIN="$(mktemp -d)"
trap 'rm -rf "$TMP_BIN"' EXIT
( cd "$TMP_BIN" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$TMP_BIN/.hv/bin"
echo '{"version":"3.4.0"}' > "$TMP_BIN/.hv/config.json"
echo '#!/bin/sh' > "$TMP_BIN/.hv/bin/hv-context-add"
echo '#!/bin/sh' > "$TMP_BIN/.hv/bin/hv-context-query"
chmod +x "$TMP_BIN/.hv/bin/hv-context-add" "$TMP_BIN/.hv/bin/hv-context-query"
( cd "$TMP_BIN" && git add -A && git commit -q -m init )

OUT_BIN=$( cd "$TMP_BIN" && "$BIN/hv-migrate" v4 )
echo "$OUT_BIN" | grep -q "removed binaries:.*2\|removed binaries: \+2" || fail "should report 2 removed binaries in dry-run"

( cd "$TMP_BIN" && "$BIN/hv-migrate" v4 --apply >/dev/null )
[ ! -e "$TMP_BIN/.hv/bin/hv-context-add" ] || fail "hv-context-add should be removed"
[ ! -e "$TMP_BIN/.hv/bin/hv-context-query" ] || fail "hv-context-query should be removed"
# Backup tree
BACKUP_BIN=$(ls -d "$TMP_BIN"/.hv/migrate-backup/*/bin/ 2>/dev/null | head -1)
[ -f "$BACKUP_BIN/hv-context-add" ] || fail "hv-context-add backup missing"
trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate — removes stale .hv/bin/hv-context-* with backup"

echo "hv-migrate — word boundary: /hv-capture is NOT rewritten by /hv-c\\b rule"
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

( cd "$TMP_WB" && "$BIN/hv-migrate" v4 --apply >/dev/null )
# Expected after rewrite: "/hv-capture is correct; /hv-capture is the old alias."
[ "$(grep -c "/hv-capture is correct" "$TMP_WB/.hv/BACKLOG.md")" = "1" ] || fail "/hv-capture survived unscathed"
[ "$(grep -c "/hv-capture is the old alias" "$TMP_WB/.hv/BACKLOG.md")" = "1" ] || fail "/hv-c should rewrite to /hv-capture"
grep -q "/hv-c is" "$TMP_WB/.hv/BACKLOG.md" && fail "stale /hv-c left after rewrite"
trap 'rm -rf "$TMP"' EXIT
pass "hv-migrate — word boundary: /hv-capture preserved, /hv-c rewritten"
