# F03 — Knowledge promotion lifecycle (tier sidecar + auto-promotion + contradictions)
echo "F03: knowledge-tier sidecar"

# Clean any stale state from prior sections
rm -f .hv/knowledge-tier.json .hv/knowledge-contradictions.json

# Seed KNOWLEDGE.md with three titled bullets and verify migration stamps them
cat > .hv/KNOWLEDGE.md <<'EOF'
# Knowledge

## Architecture

- **Foo rule** — body text for foo. <!-- 2026-05-15 -->
- **Bar rule** — body text for bar. <!-- 2026-05-15 -->

## Build and Tooling

- **Baz rule** — body text for baz. <!-- 2026-05-15 -->
EOF

# --- hv-knowledge-tier subcommands ---
OUT=$("$BIN/hv-knowledge-tier" --get --topic "Architecture" --title "Nonexistent")
[ "$(echo "$OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin))')" = "{}" ] \
  || fail "hv-knowledge-tier --get on missing returns non-empty: $OUT"
pass "hv-knowledge-tier --get on missing entry returns {}"

"$BIN/hv-knowledge-tier" --init --topic "Architecture" --title "Foo rule" >/dev/null
OUT=$("$BIN/hv-knowledge-tier" --get --topic "Architecture" --title "Foo rule" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["tier"]+"/"+str(d["hits"]))')
[ "$OUT" = "provisional/0" ] || fail "hv-knowledge-tier --init wrong shape: $OUT"
pass "hv-knowledge-tier --init creates provisional/0"

"$BIN/hv-knowledge-tier" --inc --topic "Architecture" --title "Foo rule" >/dev/null
"$BIN/hv-knowledge-tier" --inc --topic "Architecture" --title "Foo rule" >/dev/null
HITS=$("$BIN/hv-knowledge-tier" --get --topic "Architecture" --title "Foo rule" | python3 -c 'import json,sys;print(json.load(sys.stdin)["hits"])')
[ "$HITS" = "2" ] || fail "hv-knowledge-tier --inc twice; expected hits=2, got $HITS"
pass "hv-knowledge-tier --inc increments hits"

"$BIN/hv-knowledge-tier" --set --topic "Architecture" --title "Foo rule" --tier confirmed >/dev/null
TIER=$("$BIN/hv-knowledge-tier" --get --topic "Architecture" --title "Foo rule" | python3 -c 'import json,sys;print(json.load(sys.stdin)["tier"])')
[ "$TIER" = "confirmed" ] || fail "hv-knowledge-tier --set didn't update tier; got $TIER"
pass "hv-knowledge-tier --set updates tier"

if "$BIN/hv-knowledge-tier" --set --topic "Architecture" --title "Foo rule" --tier garbage 2>/dev/null; then
  fail "hv-knowledge-tier --set should reject invalid tier"
fi
pass "hv-knowledge-tier --set rejects invalid tier"

# --- hv-knowledge-migrate idempotency ---
rm -f .hv/knowledge-tier.json
OUT=$("$BIN/hv-knowledge-migrate")
echo "$OUT" | grep -q "migrated 3 entries" || fail "first migration didn't claim 3 entries: $OUT"
pass "hv-knowledge-migrate stamps all titled bullets on first run"

OUT2=$("$BIN/hv-knowledge-migrate")
echo "$OUT2" | grep -qi "nothing to migrate" || fail "second migration not idempotent: $OUT2"
pass "hv-knowledge-migrate is idempotent on re-run"

COUNT=$("$BIN/hv-knowledge-tier" --list | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')
[ "$COUNT" = "3" ] || fail "expected 3 sidecar entries after migrate, got $COUNT"
pass "migrate populates sidecar with 3 entries"

# --- hv-knowledge-hit + auto-promote ---
echo '{"learn":{"verify":true,"promoteThreshold":3}}' > .hv/config.json

"$BIN/hv-knowledge-hit" --topic "Architecture" --title "Bar rule" >/dev/null 2>&1
"$BIN/hv-knowledge-hit" --topic "Architecture" --title "Bar rule" >/dev/null 2>&1
TIER=$("$BIN/hv-knowledge-tier" --get --topic "Architecture" --title "Bar rule" | python3 -c 'import json,sys;print(json.load(sys.stdin)["tier"])')
[ "$TIER" = "provisional" ] || fail "Bar rule should stay provisional at 2 hits; got $TIER"
pass "hv-knowledge-hit doesn't promote below threshold"

"$BIN/hv-knowledge-hit" --topic "Architecture" --title "Bar rule" 2>&1 | grep -q "auto-promoted" \
  || fail "third hit should print auto-promoted line"
TIER=$("$BIN/hv-knowledge-tier" --get --topic "Architecture" --title "Bar rule" | python3 -c 'import json,sys;print(json.load(sys.stdin)["tier"])')
[ "$TIER" = "confirmed" ] || fail "third hit should auto-promote to confirmed; got $TIER"
pass "hv-knowledge-hit auto-promotes at threshold"

# --- hv-knowledge-contradiction ---
"$BIN/hv-knowledge-contradiction" --add --topic "Build and Tooling" --title "Baz rule" --text "user said baz is wrong" >/dev/null
LIST=$("$BIN/hv-knowledge-contradiction" --list | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')
[ "$LIST" = "1" ] || fail "expected 1 contradiction, got $LIST"
pass "hv-knowledge-contradiction --add records a candidate"

if ! "$BIN/hv-knowledge-contradiction" --has --topic "Build and Tooling" --title "Baz rule"; then
  fail "--has should exit 0 for existing entry"
fi
pass "hv-knowledge-contradiction --has exits 0 for known entry"

if "$BIN/hv-knowledge-contradiction" --has --topic "Nope" --title "Nope" 2>/dev/null; then
  fail "--has should exit 1 for missing entry"
fi
pass "hv-knowledge-contradiction --has exits 1 for missing entry"

# --- auto-promote skips when contradiction pending ---
# Hit Baz rule three times; should NOT auto-promote because contradiction is pending.
for i in 1 2 3; do
  OUT=$("$BIN/hv-knowledge-hit" --topic "Build and Tooling" --title "Baz rule" 2>&1)
done
echo "$OUT" | grep -q "skip-auto-promote" || fail "third hit on Baz rule should print skip-auto-promote: $OUT"
TIER=$("$BIN/hv-knowledge-tier" --get --topic "Build and Tooling" --title "Baz rule" | python3 -c 'import json,sys;print(json.load(sys.stdin)["tier"])')
[ "$TIER" = "provisional" ] || fail "Baz rule should stay provisional under contradiction; got $TIER"
pass "hv-knowledge-hit skips auto-promote when contradiction pending"

# --- hv-knowledge-contradiction --clear ---
"$BIN/hv-knowledge-contradiction" --clear
LIST=$("$BIN/hv-knowledge-contradiction" --list | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')
[ "$LIST" = "0" ] || fail "queue should be empty after --clear; got $LIST"
pass "hv-knowledge-contradiction --clear wipes the queue"

# --- hv-knowledge-query tier-aware output ---
# Build a fresh state: Foo confirmed, Bar deprecated, Baz provisional.
"$BIN/hv-knowledge-tier" --set --topic "Architecture" --title "Foo rule" --tier confirmed >/dev/null
"$BIN/hv-knowledge-tier" --set --topic "Architecture" --title "Bar rule" --tier deprecated >/dev/null
"$BIN/hv-knowledge-tier" --set --topic "Build and Tooling" --title "Baz rule" --tier provisional >/dev/null

OUT=$("$BIN/hv-knowledge-query" Architecture)
echo "$OUT" | grep -q "Foo rule" || fail "confirmed Foo rule should appear in default query"
if echo "$OUT" | grep -q "Bar rule"; then
  fail "deprecated Bar rule should be hidden in default query: $OUT"
fi
pass "hv-knowledge-query hides deprecated bullets by default"

OUT=$("$BIN/hv-knowledge-query" --include-deprecated Architecture)
echo "$OUT" | grep -q "Bar rule" || fail "--include-deprecated should surface Bar rule"
pass "hv-knowledge-query --include-deprecated re-surfaces hidden bullets"

OUT=$("$BIN/hv-knowledge-query" "Build and Tooling")
echo "$OUT" | grep -q "(provisional)" || fail "provisional Baz rule should carry suffix: $OUT"
pass "hv-knowledge-query suffixes (provisional) on probation bullets"

OUT=$("$BIN/hv-knowledge-query" --tier confirmed Architecture)
echo "$OUT" | grep -q "Foo rule" || fail "--tier confirmed should keep Foo rule"
if echo "$OUT" | grep -q "Bar rule"; then
  fail "--tier confirmed should drop deprecated Bar rule: $OUT"
fi
pass "hv-knowledge-query --tier filter works"

# --- hv-knowledge-merge initializes sidecar on new bullet ---
printf '%s' "Body of qux rule" | "$BIN/hv-knowledge-merge" --topic "Architecture" --title "Qux rule" >/dev/null 2>&1
TIER=$("$BIN/hv-knowledge-tier" --get --topic "Architecture" --title "Qux rule" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("tier","missing"))')
[ "$TIER" = "provisional" ] || fail "new bullet from merge should be provisional in sidecar; got $TIER"
pass "hv-knowledge-merge initializes new bullet as provisional"

# Cleanup
rm -f .hv/knowledge-tier.json .hv/knowledge-contradictions.json
