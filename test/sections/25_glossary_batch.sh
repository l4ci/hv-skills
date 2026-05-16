echo "hv-glossary-write --batch — atomic multi-term import"
TMP_BATCH="$(mktemp -d)"
trap 'rm -rf "$TMP_BATCH"' EXIT
( cd "$TMP_BATCH" && "$BIN/hv-bootstrap" >/dev/null )
git -C "$TMP_BATCH" init -q
git -C "$TMP_BATCH" config user.email t@t
git -C "$TMP_BATCH" config user.name t

# 1. Valid 3-term batch — all written, alphabetical order.
cat > "$TMP_BATCH/manifest.tsv" <<'EOF'
# header comment, skipped
backlog	The canonical project queue.	task list, todo list
decision	A hard project boundary.
session	An active work cycle.	cycle, run
EOF
( cd "$TMP_BATCH" && "$BIN/hv-glossary-write" --batch manifest.tsv >/dev/null 2>&1 ) || fail "valid batch should succeed"
ORDER=$(grep -E '^- \*\*' "$TMP_BATCH/.hv/KNOWLEDGE.md" | sed -E 's/^- \*\*([^*]+)\*\*.*/\1/')
EXPECTED=$'backlog\ndecision\nsession'
[ "$ORDER" = "$EXPECTED" ] || fail "batch order wrong: got '$ORDER'"
grep -q "^  - \*\*Aliases:\*\* task list, todo list$" "$TMP_BATCH/.hv/KNOWLEDGE.md" || fail "backlog aliases missing"
grep -q "^  - \*\*Aliases:\*\* _none_$" "$TMP_BATCH/.hv/KNOWLEDGE.md" || fail "decision _none_ missing"
pass "hv-glossary-write --batch — valid batch writes alphabetically"

# 2. Intra-batch alias collision — refusal with conflict line; KNOWLEDGE.md unchanged.
SNAPSHOT_BEFORE=$(cat "$TMP_BATCH/.hv/KNOWLEDGE.md")
cat > "$TMP_BATCH/manifest_intra.tsv" <<'EOF'
foo	Foo def.	shared
bar	Bar def.	shared
EOF
set +e
( cd "$TMP_BATCH" && "$BIN/hv-glossary-write" --batch manifest_intra.tsv 2>"$TMP_BATCH/err_intra" )
RC=$?
set -e
[ $RC -eq 3 ] || fail "intra-batch collision should exit 3, got $RC"
grep -q "intra-batch" "$TMP_BATCH/err_intra" || fail "missing intra-batch label"
grep -q "'foo'" "$TMP_BATCH/err_intra" || fail "error should name 'foo'"
grep -q "'bar'" "$TMP_BATCH/err_intra" || fail "error should name 'bar'"
grep -q "^- \*\*foo\*\*" "$TMP_BATCH/.hv/KNOWLEDGE.md" && fail "foo should NOT be written"
grep -q "^- \*\*bar\*\*" "$TMP_BATCH/.hv/KNOWLEDGE.md" && fail "bar should NOT be written"
SNAPSHOT_AFTER=$(cat "$TMP_BATCH/.hv/KNOWLEDGE.md")
[ "$SNAPSHOT_BEFORE" = "$SNAPSHOT_AFTER" ] || fail "KNOWLEDGE.md changed despite refusal"
pass "hv-glossary-write --batch — intra-batch collision refuses all"

# 3. Collision with pre-batch existing entry — same refusal shape.
cat > "$TMP_BATCH/manifest_existing.tsv" <<'EOF'
inbox	Inbox def.	task list
EOF
set +e
( cd "$TMP_BATCH" && "$BIN/hv-glossary-write" --batch manifest_existing.tsv 2>"$TMP_BATCH/err_pre" )
RC=$?
set -e
[ $RC -eq 3 ] || fail "pre-batch collision should exit 3, got $RC"
grep -q "existing term 'backlog'" "$TMP_BATCH/err_pre" || fail "error should name existing owner 'backlog'"
grep -q "^- \*\*inbox\*\*" "$TMP_BATCH/.hv/KNOWLEDGE.md" && fail "inbox should NOT be written"
pass "hv-glossary-write --batch — pre-batch collision refuses all"

echo "hv-knowledge-tier — Glossary topic is skipped (terms aren't tier-eligible)"
# --init on Glossary should be a silent no-op (no sidecar entry, no error)
"$BIN/hv-knowledge-tier" --init --topic "Glossary" --title "backlog" >/dev/null 2>&1 || fail "Glossary --init should exit 0"
# --get on Glossary returns empty object
OUT_TIER=$( "$BIN/hv-knowledge-tier" --get --topic "Glossary" --title "backlog" )
[ "$OUT_TIER" = "{}" ] || fail "Glossary --get should return empty, got '$OUT_TIER'"
# Even if we force-set a Glossary entry into the sidecar by hand, --list filters it out
mkdir -p "$TMP_BATCH/.hv"
cat > "$TMP_BATCH/.hv/knowledge-tier.json" <<'EOF'
{"version": 1, "entries": {"Glossary::leaked": {"tier": "provisional", "hits": 5, "lastSeen": "2026-05-10"}, "Architecture::real": {"tier": "confirmed", "hits": 3, "lastSeen": "2026-05-10"}}}
EOF
LIST_OUT=$( cd "$TMP_BATCH" && "$BIN/hv-knowledge-tier" --list )
echo "$LIST_OUT" | grep -q "Architecture" || fail "non-Glossary topic should appear in --list"
echo "$LIST_OUT" | grep -q "Glossary" && fail "--list should filter Glossary entries"
echo "$LIST_OUT" | grep -q "leaked" && fail "--list should filter leaked Glossary entries"
pass "hv-knowledge-tier — Glossary skip enforced on --init/--get/--list"

trap 'rm -rf "$TMP"' EXIT
