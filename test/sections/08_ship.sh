echo "hv-merge / hv-pr"
# Check syntactic integrity — they should error cleanly without stdin input
if echo "" | "$BIN/hv-merge" hv/real-branch 2>/dev/null; then
  fail "hv-merge should reject empty message"
fi
pass "hv-merge rejects empty message"
# Don't actually run hv-pr — no remote

echo "regression: hv-backlog preserves periods in titles"
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Features
- **[F50] [Minor] Add v1.2 support.** Desc here.

## Bugs

## Tasks

## Completed
EOF
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "Add v1.2 support" || fail "title with period was truncated: $(echo "$OUT" | grep F50)"
pass "backlog keeps mid-title periods intact"

echo "regression: hv-archive-old always prints count"
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
COUNT=$("$BIN/hv-archive-old" 5)
[ "$COUNT" = "0" ] || fail "expected '0' when nothing to archive, got '$COUNT'"
pass "archive-old prints 0 when no items to move"

echo "regression: hv-archive-old only archives canonical completed shape"
FAKE_HASH="abc1234"
OLD_DATE="2024-01-01"
cat > .hv/BACKLOG.md <<EOF
# TODO

## Bugs

## Features

## Tasks

## Completed

- ~~**[B01] Fix login crash.**~~ Done ${OLD_DATE} [\`${FAKE_HASH}\`]
- Note: see issue [B05] which was Done 2024-01-01 by accident.
EOF
COUNT=$("$BIN/hv-archive-old" 1)
[ "$COUNT" = "1" ] || fail "expected 1 item archived, got '$COUNT'"
grep -q "Fix login crash" .hv/ARCHIVE.md || fail "canonical bullet not found in ARCHIVE.md"
grep -q "by accident" .hv/BACKLOG.md || fail "free-form note was wrongly removed from BACKLOG.md"
! grep -q "Fix login crash" .hv/BACKLOG.md || fail "canonical bullet still present in BACKLOG.md"
pass "archive-old only moves canonical completed bullets"

echo "hv-ship-body"
# Fresh branch state for ship-body + review-scope
git checkout -q main 2>/dev/null || true
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B70] [P1] Ship demo bug.** Broken badge.~~ Done 2026-04-18 [`aaa1111`]
- ~~**[F70] [Minor] Ship demo feature.** Overlay.~~ Done 2026-04-18 [`bbb2222`]
EOF
git add -A && git commit -q -m "seed ship demo" || true
git checkout -q -b hv/ship-demo
echo ship1 > ship1.txt && git add ship1.txt && git commit -q -m "fix: badge invalidation [B70]"
echo ship2 > ship2.txt && git add ship2.txt && git commit -q -m "feat: overlay [F70]"
git checkout -q main

BODY=$("$BIN/hv-ship-body" hv/ship-demo)
echo "$BODY" | grep -q "^## Summary" || fail "ship-body missing Summary section"
echo "$BODY" | grep -q "^## Items resolved" || fail "ship-body missing Items resolved section"
echo "$BODY" | grep -q "\[B70\] Ship demo bug" || fail "ship-body missing B70 title"
echo "$BODY" | grep -q "\[F70\] Ship demo feature" || fail "ship-body missing F70 title"
pass "ship-body emits Summary + Items resolved with resolved titles"

if "$BIN/hv-ship-body" main 2>/dev/null; then fail "ship-body should reject main (no commits vs base)"; fi
pass "ship-body errors when base has no commits"

# ship-body emits Closes #N for GH refs in resolved item bullets
git checkout -q main
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B71] [P1] Has GH ref.** Something. GH: #42~~ Done 2026-04-18 [`ccc3333`]
- ~~**[F71] [Minor] No GH ref.** Plain.~~ Done 2026-04-18 [`ddd4444`]
EOF
git add -A && git commit -q -m "seed gh-closes test" || true
git checkout -q -b hv/ship-gh-closes
echo g1 > g1.txt && git add g1.txt && git commit -q -m "fix: thing [B71]"
echo g2 > g2.txt && git add g2.txt && git commit -q -m "feat: thing [F71]"
git checkout -q main
BODY=$("$BIN/hv-ship-body" hv/ship-gh-closes)
echo "$BODY" | grep -q "^Closes #42$" || fail "ship-body missing Closes #42 line: $BODY"
GH_LINES=$(echo "$BODY" | grep -c "^Closes #" || true)
[ "$GH_LINES" = "1" ] || fail "ship-body expected 1 Closes line, got $GH_LINES: $BODY"
pass "ship-body emits Closes #N from GH refs in TODO bullets"
git checkout -q main
git branch -D hv/ship-gh-closes >/dev/null 2>&1 || true
rm -f g1.txt g2.txt

# Negative case: no GH refs anywhere → no Closes lines.
git checkout -q main
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B72] [P1] No ref.** Plain.~~ Done 2026-04-18 [`eee5555`]
EOF
git add -A && git commit -q -m "seed gh-closes negative" || true
git checkout -q -b hv/ship-gh-noclose
echo g3 > g3.txt && git add g3.txt && git commit -q -m "fix: thing [B72]"
git checkout -q main
BODY=$("$BIN/hv-ship-body" hv/ship-gh-noclose)
if echo "$BODY" | grep -q "^Closes #"; then fail "ship-body emitted Closes line with no GH refs: $BODY"; fi
pass "ship-body emits no Closes lines when no GH refs present"
git checkout -q main
git branch -D hv/ship-gh-noclose >/dev/null 2>&1 || true
rm -f g3.txt

# Dedup: two commits referencing the same ID emit a single Closes #N line.
git checkout -q main
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B73] [P1] Has GH ref.** Something. GH: #99~~ Done 2026-04-18 [`fff6666`]
EOF
git add -A && git commit -q -m "seed gh-closes dedup" || true
git checkout -q -b hv/ship-gh-dedup
echo g4 > g4.txt && git add g4.txt && git commit -q -m "fix: thing one [B73]"
echo g5 > g5.txt && git add g5.txt && git commit -q -m "fix: thing two [B73]"
git checkout -q main
BODY=$("$BIN/hv-ship-body" hv/ship-gh-dedup)
DEDUP_LINES=$(echo "$BODY" | grep -c "^Closes #99$" || true)
[ "$DEDUP_LINES" = "1" ] || fail "ship-body expected 1 Closes #99 line (dedup), got $DEDUP_LINES: $BODY"
pass "ship-body dedups Closes #N across multiple commits referencing same ID"
git checkout -q main
git branch -D hv/ship-gh-dedup >/dev/null 2>&1 || true
rm -f g4.txt g5.txt

# Restore demo TODO state for downstream review-scope tests
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B70] [P1] Ship demo bug.** Broken badge.~~ Done 2026-04-18 [`aaa1111`]
- ~~**[F70] [Minor] Ship demo feature.** Overlay.~~ Done 2026-04-18 [`bbb2222`]
EOF
git add -A && git commit -q -m "restore ship demo TODO" || true

echo "hv-review-scope"
OUT=$("$BIN/hv-review-scope" hv/ship-demo)
echo "$OUT" | grep -q '"commitCount": 2' || fail "review-scope commitCount != 2: $OUT"
echo "$OUT" | grep -q '"B70"' || fail "review-scope missing B70"
echo "$OUT" | grep -q '"F70"' || fail "review-scope missing F70"
echo "$OUT" | grep -q '"title": "Ship demo bug"' || fail "review-scope missing B70 title"
echo "$OUT" | grep -q '"ship1.txt"' || fail "review-scope missing touched file"
pass "review-scope emits commits, IDs, titles, and files"

if "$BIN/hv-review-scope" main 2>/dev/null; then fail "review-scope should reject base branch"; fi
pass "review-scope rejects base branch"

# Regression: review-scope must attribute an ID to its OWN bullet, not to
# another item that mentions the ID in a `Related:` suffix.
git checkout -q main
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features
- **[F80] [Minor] Refers to B70.** Something else. Related: [B70]

## Tasks

## Completed
EOF
cat > .hv/ARCHIVE.md <<'EOF'
# Archive

- ~~**[B70] [P1] Ship demo bug.** Broken badge.~~ Done 2026-04-10 [`aaa1111`]
EOF
git add -A && git commit -q -m "seed related-link test" || true
git checkout -q -b hv/scope-regression
echo r > r.txt && git add r.txt && git commit -q -m "fix: badge [B70]"
git checkout -q main
OUT=$("$BIN/hv-review-scope" hv/scope-regression)
echo "$OUT" | grep -q '"title": "Ship demo bug"' || fail "review-scope picked wrong bullet for B70 (Related-link regression): $OUT"
pass "review-scope picks origin bullet, ignores Related-link references"
git branch -D hv/scope-regression >/dev/null 2>&1 || true
rm -f r.txt

# Regression: hv-ship-body must attribute an ID to its OWN bullet, not to
# another item that mentions the ID in a `Related:` suffix.
git checkout -q main
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features
- **[F80] [Minor] Refers to B70.** Something else. Related: [B70]

## Tasks

## Completed
EOF
cat > .hv/ARCHIVE.md <<'EOF'
# Archive

- ~~**[B70] [P1] Ship demo bug.** Broken badge.~~ Done 2026-04-10 [`aaa1111`]
EOF
git add -A && git commit -q -m "seed ship-body related-link test" || true
git checkout -q -b hv/ship-body-regression
echo r > r2.txt && git add r2.txt && git commit -q -m "fix: badge [B70]"
git checkout -q main
BODY=$("$BIN/hv-ship-body" hv/ship-body-regression)
echo "$BODY" | grep -q "\[B70\] Ship demo bug" || fail "ship-body picked wrong bullet for B70 (Related-link regression): $BODY"
pass "ship-body picks origin bullet, ignores Related-link references"
git checkout -q main
git branch -D hv/ship-body-regression >/dev/null 2>&1 || true
rm -f r2.txt

# Cleanup demo branch before later tests
git branch -D hv/ship-demo >/dev/null 2>&1 || true
rm -f ship1.txt ship2.txt

echo "hv-second-opinion-brief"
# Re-seed the ship-demo branch + TODO state for the second-opinion brief test.
git checkout -q main
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B70] [P1] Ship demo bug.** Broken badge.~~ Done 2026-04-18 [`aaa1111`]
- ~~**[F70] [Minor] Ship demo feature.** Overlay.~~ Done 2026-04-18 [`bbb2222`]
EOF
git add -A && git commit -q -m "seed second-opinion demo" || true
git checkout -q -b hv/second-opinion-demo
echo so1 > so1.txt && git add so1.txt && git commit -q -m "fix: badge invalidation [B70]"
echo so2 > so2.txt && git add so2.txt && git commit -q -m "feat: overlay [F70]"
git checkout -q main

BRIEF=$("$BIN/hv-second-opinion-brief" hv/second-opinion-demo)
echo "$BRIEF" | grep -qi "no prior conversation context" \
  || fail "second-opinion-brief missing fresh-context framing"
echo "$BRIEF" | grep -q "^\*\*Goal" \
  || fail "second-opinion-brief missing Goal section"
echo "$BRIEF" | grep -q "\[B70\] Ship demo bug" \
  || fail "second-opinion-brief missing B70 in goal"
echo "$BRIEF" | grep -q "\[F70\] Ship demo feature" \
  || fail "second-opinion-brief missing F70 in goal"
echo "$BRIEF" | grep -q "^\*\*Commits" \
  || fail "second-opinion-brief missing Commits section"
echo "$BRIEF" | grep -q "fix: badge invalidation" \
  || fail "second-opinion-brief missing commit subject"
echo "$BRIEF" | grep -q "^\*\*Diff" \
  || fail "second-opinion-brief missing Diff section"
echo "$BRIEF" | grep -q "so1.txt" \
  || fail "second-opinion-brief missing per-file diff path"
echo "$BRIEF" | grep -q "PASS | CONCERNS | FAIL" \
  || fail "second-opinion-brief missing verdict-instruction"
if echo "$BRIEF" | grep -qi "KNOWLEDGE\.md\|DECISIONS\.md\|hard boundaries\|known gotchas"; then
  fail "second-opinion-brief leaked KNOWLEDGE/DECISIONS context (must be diff+goal only)"
fi
pass "second-opinion-brief emits goal+commits+diff with no project-context leak"

if "$BIN/hv-second-opinion-brief" main 2>/dev/null; then
  fail "second-opinion-brief should reject base branch"
fi
pass "second-opinion-brief rejects base branch"

# Zero-commit branch — helper exits 2 with a clear error
git checkout -q -b hv/second-opinion-empty
git checkout -q main
if "$BIN/hv-second-opinion-brief" hv/second-opinion-empty 2>/dev/null; then
  fail "second-opinion-brief should reject zero-commit branch"
fi
pass "second-opinion-brief rejects branch with no commits beyond base"
git branch -D hv/second-opinion-empty >/dev/null 2>&1 || true

# Cleanup
git branch -D hv/second-opinion-demo >/dev/null 2>&1 || true
rm -f so1.txt so2.txt

