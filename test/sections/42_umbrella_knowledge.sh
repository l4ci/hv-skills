# F21 — umbrella-aware KNOWLEDGE.md: scoped writes, hybrid query, tier sidecars, amend guard, glossary, CLAUDE.md blocks, migrate, decisions guard
echo "F21: umbrella-aware KNOWLEDGE.md — end-to-end"

# ── Build primary fixture ───────────────────────────────────────────────────
TMP_UK="$(mktemp -d)"
trap 'rm -rf "$TMP_UK"' EXIT
(
  cd "$TMP_UK"
  git init -q .
  git config user.email t@t && git config user.name t
  mkdir -p .hv .hv/contexts/web web api
  ( cd web && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m i )
  ( cd api && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m i )
  printf '{"repos":[{"name":"web","path":"./web"},{"name":"api","path":"./api"}]}' > .hv/repos.json
  printf '{"hvSkills":{"version":"3.0.0"}}' > .hv/config.json
  printf '# Knowledge\n\n## Architecture\n\n- **umbrella rule** — cross-repo body <!-- 2026-05-19 -->\n\n## Glossary\n\n' > .hv/KNOWLEDGE.md
  mkdir -p .hv/knowledge/web .hv/knowledge/api
  printf '# Knowledge\n\n## Architecture\n\n## Glossary\n\n' > .hv/knowledge/web/KNOWLEDGE.md
  printf '# Knowledge\n\n## Architecture\n\n## Glossary\n\n' > .hv/knowledge/api/KNOWLEDGE.md
  printf '# Context\n\n## Widget\n\nA web widget.\n' > .hv/contexts/web/CONTEXT.md
  printf '/web/\n/api/\n' > .gitignore
  git -c user.email=t@t -c user.name=t add -A
  git -c user.email=t@t -c user.name=t commit -qm init
)

# ── 1. Scoped write: from web subdir, merge lands in sub-repo KNOWLEDGE.md ──
echo "F21: scoped write — hv-knowledge-merge from sub-repo"
( cd "$TMP_UK/web" && "$BIN/hv-knowledge-merge" --topic Architecture --title "web rule" --body "web-local" 2>/dev/null )
grep -q "web rule" "$TMP_UK/.hv/knowledge/web/KNOWLEDGE.md" \
  || fail "F21[1]: 'web rule' must appear in .hv/knowledge/web/KNOWLEDGE.md"
grep -q "web rule" "$TMP_UK/.hv/KNOWLEDGE.md" \
  && fail "F21[1]: 'web rule' must NOT appear in umbrella .hv/KNOWLEDGE.md"
pass "F21[1]: scoped write lands in sub-repo KNOWLEDGE.md only"

# ── 2. Hybrid query: sub-repo scope shows both files with > from:; umbrella shows only its own ──
echo "F21: hybrid query"
QUERY_WEB="$( cd "$TMP_UK/web" && "$BIN/hv-knowledge-query" Architecture )"
echo "$QUERY_WEB" | grep -q "umbrella rule" \
  || fail "F21[2]: hybrid query from web must include 'umbrella rule'"
echo "$QUERY_WEB" | grep -q "web rule" \
  || fail "F21[2]: hybrid query from web must include 'web rule'"
echo "$QUERY_WEB" | grep -q "> from:" \
  || fail "F21[2]: hybrid query from web must include a '> from:' provenance line"

QUERY_UMBRELLA="$( cd "$TMP_UK" && "$BIN/hv-knowledge-query" Architecture )"
echo "$QUERY_UMBRELLA" | grep -q "umbrella rule" \
  || fail "F21[2]: umbrella-scope query must include 'umbrella rule'"
echo "$QUERY_UMBRELLA" | grep -q "web rule" \
  && fail "F21[2]: umbrella-scope query must NOT include 'web rule'"
echo "$QUERY_UMBRELLA" | grep -q "> from:" \
  && fail "F21[2]: umbrella-scope query must NOT include a '> from:' line"
pass "F21[2]: hybrid query shows correct provenance per scope"

# ── 3. Per-file tier sidecar ────────────────────────────────────────────────
echo "F21: per-file tier sidecar"
( cd "$TMP_UK/web" && "$BIN/hv-knowledge-tier" --set --topic Architecture --title "web rule" --tier confirmed 2>/dev/null )
[ -f "$TMP_UK/.hv/knowledge/web/knowledge-tier.json" ] \
  || fail "F21[3]: .hv/knowledge/web/knowledge-tier.json must exist after --set"
grep -q "web rule" "$TMP_UK/.hv/knowledge/web/knowledge-tier.json" \
  || fail "F21[3]: sub-repo tier sidecar must contain 'web rule'"
# Umbrella sidecar must NOT have "web rule"
if [ -f "$TMP_UK/.hv/knowledge-tier.json" ]; then
  grep -q "web rule" "$TMP_UK/.hv/knowledge-tier.json" \
    && fail "F21[3]: umbrella tier sidecar must NOT contain 'web rule'"
fi
pass "F21[3]: tier sidecar is scoped per sub-repo"

# ── 4. Cross-file amend guard ───────────────────────────────────────────────
echo "F21: cross-file amend guard"
# Seed "shared rule" in BOTH files
( cd "$TMP_UK" && "$BIN/hv-knowledge-merge" --topic Architecture --title "shared rule" --body "in umbrella" --repo umbrella 2>/dev/null )
( cd "$TMP_UK" && "$BIN/hv-knowledge-merge" --topic Architecture --title "shared rule" --body "in web" --repo web 2>/dev/null )

# Without --repo: ambiguous → exit non-zero, mention multiple files
set +e
AMEND_ERR="$( cd "$TMP_UK/web" && "$BIN/hv-knowledge-amend" --topic Architecture --fragment "shared rule" --append "(x)" 2>&1 >/dev/null )"; AMEND_RC=$?
set -e
[ "$AMEND_RC" -ne 0 ] \
  || fail "F21[4]: amend without --repo must exit non-zero when fragment matches in multiple files"
echo "$AMEND_ERR" | grep -qiE "multiple|disambiguate|both" \
  || fail "F21[4]: amend error must mention multiple files or disambiguation; got: $AMEND_ERR"

# With --repo web: unambiguous → exit 0, amends only web file
( cd "$TMP_UK/web" && "$BIN/hv-knowledge-amend" --topic Architecture --fragment "shared rule" --append "(x)" --repo web 2>/dev/null )
grep -q "(x)" "$TMP_UK/.hv/knowledge/web/KNOWLEDGE.md" \
  || fail "F21[4]: --repo web amend must append to web file"
grep -q "(x)" "$TMP_UK/.hv/KNOWLEDGE.md" \
  && fail "F21[4]: --repo web amend must NOT touch umbrella file"
pass "F21[4]: cross-file amend guard blocks ambiguous; --repo web resolves it"

# ── 5. Glossary parity ──────────────────────────────────────────────────────
echo "F21: glossary parity"
( cd "$TMP_UK/web" && "$BIN/hv-glossary-write" webterm --def "a web term" 2>/dev/null )
grep -q "webterm" "$TMP_UK/.hv/knowledge/web/KNOWLEDGE.md" \
  || fail "F21[5]: webterm must land in .hv/knowledge/web/KNOWLEDGE.md Glossary"
GLOSS_READ="$( cd "$TMP_UK/web" && "$BIN/hv-glossary-read" webterm )"
echo "$GLOSS_READ" | grep -q "a web term" \
  || fail "F21[5]: hv-glossary-read must print the term definition"
echo "$GLOSS_READ" | grep -q "> from: .hv/knowledge/web/KNOWLEDGE.md (## Glossary)" \
  || fail "F21[5]: hv-glossary-read must include provenance line for web scope; got: $GLOSS_READ"
pass "F21[5]: glossary write scoped to sub-repo; read shows provenance"

# ── 6. Per-sub-repo CLAUDE.md block ─────────────────────────────────────────
echo "F21: per-sub-repo CLAUDE.md block"
( cd "$TMP_UK" && "$BIN/hv-managed-block" knowledge --repo web >/dev/null )
[ -f "$TMP_UK/web/CLAUDE.md" ] \
  || fail "F21[6]: web/CLAUDE.md must exist after hv-managed-block knowledge --repo web"
grep -q "Architecture" "$TMP_UK/web/CLAUDE.md" \
  || fail "F21[6]: web/CLAUDE.md knowledge block must list 'Architecture'"
# --repo umbrella: must write to umbrella CLAUDE.md, not error
set +e
UMBRELLA_BLOCK_RC=0
( cd "$TMP_UK" && "$BIN/hv-managed-block" knowledge --repo umbrella >/dev/null 2>&1 ) || UMBRELLA_BLOCK_RC=$?
set -e
[ "$UMBRELLA_BLOCK_RC" -eq 0 ] \
  || fail "F21[6]: hv-managed-block knowledge --repo umbrella must exit 0"
[ -f "$TMP_UK/CLAUDE.md" ] \
  || fail "F21[6]: umbrella CLAUDE.md must exist after --repo umbrella"
# Umbrella CLAUDE.md must not be the same file as web/CLAUDE.md
[ "$(realpath "$TMP_UK/CLAUDE.md")" != "$(realpath "$TMP_UK/web/CLAUDE.md")" ] \
  || fail "F21[6]: umbrella CLAUDE.md and web CLAUDE.md must be different files"
pass "F21[6]: per-sub-repo CLAUDE.md block written; umbrella block succeeds"

# ── 7. Migrate umbrella branch (fresh fixture) ───────────────────────────────
echo "F21: migrate umbrella branch"
TMP_UK2="$(mktemp -d)"
trap 'rm -rf "$TMP_UK2"' EXIT
(
  cd "$TMP_UK2"
  git init -q .
  git config user.email t@t && git config user.name t
  mkdir -p .hv .hv/contexts/web web api
  ( cd web && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m i )
  ( cd api && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m i )
  printf '{"repos":[{"name":"web","path":"./web"},{"name":"api","path":"./api"}]}' > .hv/repos.json
  printf '{"hvSkills":{"version":"3.0.0"}}' > .hv/config.json
  printf '# Knowledge\n\n## Architecture\n\n## Glossary\n\n' > .hv/KNOWLEDGE.md
  mkdir -p .hv/knowledge/web .hv/knowledge/api
  printf '# Knowledge\n\n## Architecture\n\n## Glossary\n\n' > .hv/knowledge/web/KNOWLEDGE.md
  printf '# Knowledge\n\n## Architecture\n\n## Glossary\n\n' > .hv/knowledge/api/KNOWLEDGE.md
  printf '# Context\n\n## Widget\n\nA web widget.\n' > .hv/contexts/web/CONTEXT.md
  printf '/web/\n/api/\n' > .gitignore
  git -c user.email=t@t -c user.name=t add -A
  git -c user.email=t@t -c user.name=t commit -qm init
)
set +e
MIGRATE_RC=0
( cd "$TMP_UK2" && "$BIN/hv-migrate" v4 --apply >/dev/null 2>&1 ) || MIGRATE_RC=$?
set -e
[ "$MIGRATE_RC" -eq 0 ] \
  || fail "F21[7]: hv-migrate v4 --apply must exit 0 on umbrella project with version 3.0.0; got RC=$MIGRATE_RC"
# CONTEXT.md migrated → Widget term lands in web KNOWLEDGE.md Glossary
grep -q "Widget" "$TMP_UK2/.hv/knowledge/web/KNOWLEDGE.md" \
  || fail "F21[7]: 'Widget' term must appear in .hv/knowledge/web/KNOWLEDGE.md after migrate"
# contexts/web/CONTEXT.md must be gone
[ ! -f "$TMP_UK2/.hv/contexts/web/CONTEXT.md" ] \
  || fail "F21[7]: .hv/contexts/web/CONTEXT.md must be deleted after migrate"
# Backup must exist
ls "$TMP_UK2/.hv/migrate-backup/" >/dev/null 2>&1 \
  || fail "F21[7]: .hv/migrate-backup/ must exist after --apply"
BACKUP_DIR="$(ls -d "$TMP_UK2"/.hv/migrate-backup/*/ 2>/dev/null | head -1)"
[ -n "$BACKUP_DIR" ] \
  || fail "F21[7]: no timestamped backup directory found under .hv/migrate-backup/"
pass "F21[7]: migrate umbrella branch exits 0; context migrated; backup exists"

# ── 8. Decisions stay umbrella-only ─────────────────────────────────────────
echo "F21: decisions umbrella-only guard"
set +e
DECISIONS_ERR=""
DECISIONS_RC=0
DECISIONS_ERR="$( cd "$TMP_UK" && "$BIN/hv-managed-block" decisions --repo web 2>&1 >/dev/null )" || DECISIONS_RC=$?
set -e
[ "$DECISIONS_RC" -ne 0 ] \
  || fail "F21[8]: hv-managed-block decisions --repo web must exit non-zero (Persistence-trio scoping boundary)"
echo "$DECISIONS_ERR" | grep -qiE "umbrella|decisions" \
  || fail "F21[8]: error message must mention 'umbrella' or 'decisions'; got: $DECISIONS_ERR"
pass "F21[8]: decisions block rejects non-umbrella --repo (Persistence-trio boundary)"

# ── Restore global trap and terminal pass ────────────────────────────────────
trap 'rm -rf "$TMP"' EXIT
pass "F21: umbrella-aware KNOWLEDGE.md end-to-end"
