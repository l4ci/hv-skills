# T03 — hv-knowledge-rename-topic: atomic heading move + tier sidecar re-key
echo "T03: hv-knowledge-rename-topic — atomic re-key on heading move"

TMP_KR="$(mktemp -d)"
trap 'rm -rf "$TMP_KR"' EXIT
mkdir -p "$TMP_KR/.hv"

# Seed KNOWLEDGE.md with two topics, three titled bullets, and prime the
# tier sidecar with confirmed/hits state — exactly what auto-split would
# orphan today.
cat > "$TMP_KR/.hv/KNOWLEDGE.md" <<'EOF'
# Knowledge

## Architecture

- **Foo rule** — body of foo. <!-- 2026-05-15 -->
- **Bar rule** — body of bar. <!-- 2026-05-15 -->

## Build & Tooling

- **Baz rule** — body of baz. <!-- 2026-05-15 -->
EOF

# Prime sidecar with non-default state so re-key wins/losses are visible.
( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --set --topic "Architecture" --title "Foo rule" --tier confirmed >/dev/null )
( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --inc --topic "Architecture" --title "Foo rule" >/dev/null )
( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --inc --topic "Architecture" --title "Foo rule" >/dev/null )
( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --set --topic "Architecture" --title "Bar rule" --tier deprecated >/dev/null )
( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --init --topic "Build & Tooling" --title "Baz rule" >/dev/null )

# ---------- Per-bullet move ----------
# Append the target heading first (matches Step 8 auto-split step 3).
cat >> "$TMP_KR/.hv/KNOWLEDGE.md" <<'EOF'

## Architecture: Foundations

EOF

( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" \
    --from "Architecture" \
    --to "Architecture: Foundations" \
    --title "Foo rule" ) || fail "per-bullet rename returned non-zero"

# Foo rule moved out of Architecture, into Foundations.
grep -A2 "^## Architecture$" "$TMP_KR/.hv/KNOWLEDGE.md" | grep -q "Foo rule" \
  && fail "Foo rule still under Architecture after per-bullet move"
grep -A2 "^## Architecture: Foundations$" "$TMP_KR/.hv/KNOWLEDGE.md" | grep -q "Foo rule" \
  || fail "Foo rule not under Architecture: Foundations after per-bullet move"
grep -A2 "^## Architecture$" "$TMP_KR/.hv/KNOWLEDGE.md" | grep -q "Bar rule" \
  || fail "Bar rule lost from Architecture after Foo move"
pass "per-bullet move: bullet relocated, siblings untouched"

# Sidecar re-keyed: Foundations carries confirmed/2-hits state, old key gone.
TIER=$( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --get --topic "Architecture: Foundations" --title "Foo rule" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["tier"]+"/"+str(d["hits"]))' )
[ "$TIER" = "confirmed/2" ] || fail "Foo rule sidecar lost tier/hits after move: $TIER"
pass "per-bullet move: sidecar tier+hits follow to new key"

OLD=$( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --get --topic "Architecture" --title "Foo rule" )
[ "$OLD" = "{}" ] || fail "old sidecar key 'Architecture::Foo rule' not cleared: $OLD"
pass "per-bullet move: old sidecar key removed"

# ---------- Per-bullet error: missing target heading ----------
if ( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" \
      --from "Architecture" --to "Architecture: Nonexistent" --title "Bar rule" 2>/dev/null ); then
  fail "per-bullet rename should reject missing target heading"
fi
pass "per-bullet move rejects missing target heading"

# ---------- Per-bullet error: bullet title not found ----------
if ( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" \
      --from "Architecture" --to "Architecture: Foundations" --title "Quux rule" 2>/dev/null ); then
  fail "per-bullet rename should reject unknown title"
fi
pass "per-bullet move rejects unknown bullet title"

# ---------- Whole-topic rename ----------
( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" \
    --from "Build & Tooling" \
    --to "Tooling & Build" ) || fail "whole-topic rename returned non-zero"

grep -q "^## Tooling & Build$" "$TMP_KR/.hv/KNOWLEDGE.md" \
  || fail "renamed heading '## Tooling & Build' not present"
grep -q "^## Build & Tooling$" "$TMP_KR/.hv/KNOWLEDGE.md" \
  && fail "old heading '## Build & Tooling' still present after rename"
grep -A2 "^## Tooling & Build$" "$TMP_KR/.hv/KNOWLEDGE.md" | grep -q "Baz rule" \
  || fail "Baz rule did not follow whole-topic rename"
pass "whole-topic rename: heading renamed, bullets follow"

NEW=$( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --get --topic "Tooling & Build" --title "Baz rule" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("tier","missing"))' )
[ "$NEW" = "provisional" ] || fail "Baz rule sidecar entry missing under new topic: $NEW"
OLD=$( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --get --topic "Build & Tooling" --title "Baz rule" )
[ "$OLD" = "{}" ] || fail "old 'Build & Tooling::Baz rule' sidecar key not cleared: $OLD"
pass "whole-topic rename: sidecar entries follow to new topic prefix"

# ---------- Whole-topic error: target heading already exists ----------
# Architecture and Architecture: Foundations both exist; renaming X→Y when
# Y exists is a merge, not a rename. Reject.
if ( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" \
      --from "Architecture" --to "Architecture: Foundations" 2>/dev/null ); then
  fail "whole-topic rename should reject pre-existing target heading"
fi
pass "whole-topic rename rejects pre-existing target"

# ---------- Whole-topic error: source heading missing ----------
if ( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" \
      --from "NoSuchTopic" --to "Anything" 2>/dev/null ); then
  fail "rename should reject missing source heading"
fi
pass "rename rejects missing source heading"

# ---------- Same-name no-op ----------
( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" \
    --from "Architecture" --to "Architecture" ) \
  || fail "same-name rename should be silent no-op (exit 0)"
grep -q "^## Architecture$" "$TMP_KR/.hv/KNOWLEDGE.md" \
  || fail "Architecture heading disappeared after same-name no-op"
pass "same-name rename is silent no-op"

# ---------- Argv validation ----------
if ( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" --from "Architecture" 2>/dev/null ); then
  fail "missing --to should error"
fi
pass "missing --to flag rejected"

if ( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" --to "X" 2>/dev/null ); then
  fail "missing --from should error"
fi
pass "missing --from flag rejected"

# ---------- Auto-split end-to-end shape ----------
# Mirror the /hv-learn Step 8 auto-split flow on a fresh fixture: large topic
# with 3 bullets split into 2 facets, each call atomic.
rm -f "$TMP_KR/.hv/knowledge-tier.json"
cat > "$TMP_KR/.hv/KNOWLEDGE.md" <<'EOF'
# Knowledge

## Networking

- **Retry rule** — body. <!-- 2026-05-15 -->
- **Timeout rule** — body. <!-- 2026-05-15 -->
- **TLS rule** — body. <!-- 2026-05-15 -->
EOF

( cd "$TMP_KR" && "$BIN/hv-knowledge-migrate" >/dev/null )

# Step 3: append facet headings before old topic.
cat >> "$TMP_KR/.hv/KNOWLEDGE.md" <<'EOF'

## Networking: Reliability

## Networking: Security

EOF

# Step 4: per-bullet moves (parallel-safe — each call is atomic per file).
( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" --from "Networking" --to "Networking: Reliability" --title "Retry rule" )
( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" --from "Networking" --to "Networking: Reliability" --title "Timeout rule" )
( cd "$TMP_KR" && "$BIN/hv-knowledge-rename-topic" --from "Networking" --to "Networking: Security" --title "TLS rule" )

# All three sidecar keys re-anchored under the new facets.
T1=$( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --get --topic "Networking: Reliability" --title "Retry rule" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("tier","missing"))' )
T2=$( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --get --topic "Networking: Reliability" --title "Timeout rule" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("tier","missing"))' )
T3=$( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --get --topic "Networking: Security" --title "TLS rule" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("tier","missing"))' )
[ "$T1" = "provisional" ] && [ "$T2" = "provisional" ] && [ "$T3" = "provisional" ] \
  || fail "auto-split flow lost sidecar entries: T1=$T1 T2=$T2 T3=$T3"
pass "auto-split flow: 3 bullets across 2 facets, all sidecar entries follow"

# Old `Networking::*` keys all gone.
COUNT=$( cd "$TMP_KR" && "$BIN/hv-knowledge-tier" --list | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(sum(1 for e in data if e["topic"] == "Networking"))' )
[ "$COUNT" = "0" ] || fail "auto-split flow left $COUNT orphan 'Networking::*' keys"
pass "auto-split flow: no orphan sidecar entries under old topic"

# Restore the global trap before the next section runs.
trap 'rm -rf "$TMP"' EXIT
