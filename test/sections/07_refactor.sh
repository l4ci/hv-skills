echo "hv-refactor-age / hv-complete counter / hv-refactor-reset"
git checkout -q main
# Reset to isolate this section from prior hv-complete calls in the suite.
"$BIN/hv-refactor-reset"
# Seed three active entries, then complete each against a real commit.
cat >> .hv/TODO.md <<'EOF'
- **[F40] Feature done.**
- **[B40] Bug fixed.**
- **[F41] Refactor-driven feature.**
EOF
echo "f1" > f1.txt && git add f1.txt && git commit -q -m "feat: add f1"
"$BIN/hv-complete" F40
echo "b1" > b1.txt && git add b1.txt && git commit -q -m "fix: resolve b1"
"$BIN/hv-complete" B40
echo "r1" > r1.txt && git add r1.txt && git commit -q -m "refactor: clean up"
"$BIN/hv-complete" F41
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 1' || fail "expected 1 non-refactor feature, got: $OUT"
echo "$OUT" | grep -q '"bugs": 1' || fail "expected 1 non-refactor bug, got: $OUT"
pass "refactor-age counts non-refactor completions only"

# Re-completing an already-completed item must not re-bump.
"$BIN/hv-complete" F40
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 1' || fail "idempotent re-completion bumped counter, got: $OUT"
pass "hv-complete is idempotent (no double-bump)"

# hv-refactor-reset zeros the field.
"$BIN/hv-refactor-reset"
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 0' || fail "reset failed, features != 0: $OUT"
echo "$OUT" | grep -q '"bugs": 0' || fail "reset failed, bugs != 0: $OUT"
pass "hv-refactor-reset zeros since_refactor"

# Scoped refactor subjects (refactor(scope):) also count as refactor commits.
cat >> .hv/TODO.md <<'EOF'
- **[F42] Scoped refactor feature.**
EOF
echo "r2" > r2.txt && git add r2.txt && git commit -q -m "refactor(hosts): consolidate"
"$BIN/hv-complete" F42
OUT=$("$BIN/hv-refactor-age")
echo "$OUT" | grep -q '"features": 0' || fail "scoped refactor(scope): subject bumped counter, got: $OUT"
pass "hv-complete recognises scoped refactor(scope): subjects"

echo "hv-merge / hv-pr"
# Check syntactic integrity — they should error cleanly without stdin input
if echo "" | "$BIN/hv-merge" hv/real-branch 2>/dev/null; then
  fail "hv-merge should reject empty message"
fi
pass "hv-merge rejects empty message"
# Don't actually run hv-pr — no remote

