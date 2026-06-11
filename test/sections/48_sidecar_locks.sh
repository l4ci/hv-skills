echo "hvlib_io.locked — sidecar read-modify-write survives concurrent writers"
# locked() (bin/hvlib_io.py) serializes sidecar read-modify-write cycles via
# fcntl.flock on a sibling <path>.lock file. These assertions pin the contract:
# (a) N concurrent hv-knowledge-hit calls lose no increments;
# (b) N concurrent hv-knowledge-contradiction --add calls lose no entries;
# (c) a leftover .lock file (left in place by design — unlink-after-release
#     races with the next acquirer) never blocks a subsequent call.

TMP_LCK="$(mktemp -d)"
trap 'rm -rf "$TMP_LCK"' EXIT
mkdir -p "$TMP_LCK/.hv"
# Keep auto-promotion out of the way: threshold far above the hit counts
# below, so every concurrent writer takes the plain increment path.
printf '{"learn":{"promoteThreshold":99}}\n' > "$TMP_LCK/.hv/config.json"

# ── (a) 8 concurrent hits on one topic/title — hits must equal exactly 8 ─────
for _ in 1 2 3 4 5 6 7 8; do
  ( cd "$TMP_LCK" && "$BIN/hv-knowledge-hit" \
      --topic "Concurrency" --title "Lock rule" ) >/dev/null 2>&1 &
done
wait

HITS=$( cd "$TMP_LCK" && "$BIN/hv-knowledge-tier" --get \
          --topic "Concurrency" --title "Lock rule" \
        | python3 -c 'import json,sys;print(json.load(sys.stdin).get("hits"))' )
[ "$HITS" = "8" ] || fail "concurrent hv-knowledge-hit lost increments: expected hits=8, got $HITS"
pass "8 concurrent hv-knowledge-hit calls record exactly 8 hits (no lost increments)"

# ── (b) 6 concurrent --add with distinct texts — queue length must be 6 ──────
for i in 1 2 3 4 5 6; do
  ( cd "$TMP_LCK" && "$BIN/hv-knowledge-contradiction" --add \
      --topic "Concurrency" --title "Lock rule" \
      --text "concurrent correction $i" ) >/dev/null 2>&1 &
done
wait

QLEN=$( cd "$TMP_LCK" && "$BIN/hv-knowledge-contradiction" --list \
        | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' )
[ "$QLEN" = "6" ] || fail "concurrent --add lost entries: expected 6 pending, got $QLEN"
pass "6 concurrent hv-knowledge-contradiction --add calls keep all 6 entries"

# ── (c) leftover .lock file does not block a subsequent call ─────────────────
# Simulate a crashed writer's residue: a pre-existing empty lockfile. flock
# locks are kernel-held per open fd, so a stale file carries no lock — the
# next acquirer must proceed within the timeout, not hang or fail.
rm -f "$TMP_LCK/.hv/knowledge-tier.json.lock"
touch "$TMP_LCK/.hv/knowledge-tier.json.lock"
( cd "$TMP_LCK" && "$BIN/hv-knowledge-hit" \
    --topic "Concurrency" --title "Lock rule" ) >/dev/null 2>&1 \
  || fail "leftover .lock file blocked a subsequent hv-knowledge-hit call"
HITS=$( cd "$TMP_LCK" && "$BIN/hv-knowledge-tier" --get \
          --topic "Concurrency" --title "Lock rule" \
        | python3 -c 'import json,sys;print(json.load(sys.stdin).get("hits"))' )
[ "$HITS" = "9" ] || fail "post-leftover-lock hit did not land: expected hits=9, got $HITS"
pass "leftover .lock file does not block subsequent sidecar writes"

trap 'rm -rf "$TMP"' EXIT
pass "hvlib_io.locked sidecar concurrency contract"
