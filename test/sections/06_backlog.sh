echo "hv-backlog"
# Seed a mix of items in TODO.md
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B10] [P2] Minor glitch.** Desc.
- **[B11] [P0] Crash on launch.** Desc. Related: [F20]

## Features
- **[F20] [Minor] Quick-switch.** Desc. Related: [B11]
- **[F21] [Cosmetic] Tweak spacing.** Desc.

## Tasks
- **[T30] Update toolchain.** Desc.

## Completed
EOF
OUT=$("$BIN/hv-backlog")
LINE_P0=$(echo "$OUT" | grep -n "| B11 " | head -1 | cut -d: -f1)
LINE_P2=$(echo "$OUT" | grep -n "| B10 " | head -1 | cut -d: -f1)
[ "$LINE_P0" -lt "$LINE_P2" ] || fail "P0 not sorted before P2 (B11 at $LINE_P0, B10 at $LINE_P2)"
LINE_COS=$(echo "$OUT" | grep -n "| F21 " | head -1 | cut -d: -f1)
LINE_MIN=$(echo "$OUT" | grep -n "| F20 " | head -1 | cut -d: -f1)
[ "$LINE_COS" -lt "$LINE_MIN" ] || fail "Cosmetic not sorted before Minor (F21 at $LINE_COS, F20 at $LINE_MIN)"
pass "backlog sorts bugs by priority and features by size"

# Clusters: B11 ↔ F20 (mutual Related). Isolated items must not appear.
echo "$OUT" | grep -q "^### Clusters" || fail "Clusters section missing: $OUT"
echo "$OUT" | grep -qF "[B11] Crash on launch ↔ [F20] Quick-switch" \
  || fail "expected B11↔F20 cluster line: $(echo "$OUT" | awk '/^### Clusters/,0')"
CLUSTER_BLOCK=$(echo "$OUT" | awk '/^### Clusters/,0')
echo "$CLUSTER_BLOCK" | grep -q "B10\|F21\|T30" \
  && fail "isolated item leaked into Clusters: $CLUSTER_BLOCK"
pass "backlog emits Clusters section for related items"

# Triple cluster + isolated item: F22↔F23↔T30 form one component, comma-separated.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B90] [P1] Solo bug.** Desc.

## Features
- **[F90] [Minor] Hub.** Desc. Related: [F91], [T90]
- **[F91] [Minor] Spoke.** Desc. Related: [F90]

## Tasks
- **[T90] Toolchain.** Desc. Related: [F90]

## Completed
EOF
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -qF "[F90] Hub, [F91] Spoke, [T90] Toolchain" \
  || fail "triple cluster not rendered with comma separator: $(echo "$OUT" | awk '/^### Clusters/,0')"
pass "backlog renders 3+ member clusters with comma separator"

# No-cluster fixture: must omit the section entirely.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B95] [P2] Lone bug.** Desc.

## Features

## Tasks

## Completed
EOF
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "^### Clusters" \
  && fail "Clusters section appeared with no related items: $OUT"
pass "backlog omits Clusters section when nothing is related"

# Restore the original fixture for the In-Progress assertions below.
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B10] [P2] Minor glitch.** Desc.
- **[B11] [P0] Crash on launch.** Desc. Related: [F20]

## Features
- **[F20] [Minor] Quick-switch.** Desc. Related: [B11]
- **[F21] [Cosmetic] Tweak spacing.** Desc.

## Tasks
- **[T30] Update toolchain.** Desc.

## Completed
EOF

# Active items should move to In Progress
"$BIN/hv-status-add" hv/real-branch F20
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "### In Progress" || fail "In Progress section missing"
# F20 should no longer appear in ### Features section
FEAT_BLOCK=$(echo "$OUT" | awk '/^### Features/,/^### Tasks/')
echo "$FEAT_BLOCK" | grep -q "F20" && fail "active F20 leaked into Features table"
pass "active items excluded from Features section"
"$BIN/hv-status-remove" hv/real-branch

echo "hv-backlog --grep matches"
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs
- **[B70] [P1] Database connection drops after timeout.** Network glitch handler.

## Features
- **[F70] [Cosmetic] Add loading spinner to dashboard.** Cosmetic UX polish.
- **[F71] [Minor] Implement export to CSV.** Need a button on the dashboard view.

## Tasks

## Completed
EOF
echo '{"active":[]}' > .hv/status.json

OUT=$("$BIN/hv-backlog" --grep dashboard)
echo "$OUT" | grep -q "F70" || fail "F70 (matches 'dashboard') missing: $OUT"
echo "$OUT" | grep -q "F71" || fail "F71 (matches 'dashboard') missing: $OUT"
echo "$OUT" | grep -q "B70" && fail "B70 (no match) leaked: $OUT"
pass "hv-backlog --grep filters by title/description substring"

echo "hv-backlog --grep case-insensitive"
OUT=$("$BIN/hv-backlog" --grep DASHBOARD)
echo "$OUT" | grep -q "F70" || fail "case-insensitive 'DASHBOARD' should match: $OUT"
pass "hv-backlog --grep is case-insensitive"

echo "hv-backlog --grep matches ID"
OUT=$("$BIN/hv-backlog" --grep B70)
echo "$OUT" | grep -q "B70" || fail "ID match B70 missing: $OUT"
echo "$OUT" | grep -q "F70" && fail "F70 leaked when grepping B70: $OUT"
pass "hv-backlog --grep matches by ID"

echo "hv-backlog --grep no matches"
OUT=$("$BIN/hv-backlog" --grep nonexistent_xyz)
echo "$OUT" | grep -q "No matches for pattern 'nonexistent_xyz'" || fail "expected 'No matches' message: $OUT"
echo "$OUT" | grep -q "### Bugs" && fail "Bugs section should be empty/absent on no-match: $OUT"
pass "hv-backlog --grep with no matches prints 'No matches' message"

echo "hv-backlog --grep cluster"
cat > .hv/TODO.md <<'EOF'
# TODO

## Bugs

## Features
- **[F80] [Minor] Auth refactor.** Wire OAuth. Related: [F81]
- **[F81] [Minor] Token rotation.** Refresh JWT. Related: [F80]
- **[F82] [Cosmetic] Unrelated thing.** Standalone.

## Tasks

## Completed
EOF
OUT=$("$BIN/hv-backlog" --grep "Auth refactor")
echo "$OUT" | grep -q "F80" || fail "F80 missing in filtered output: $OUT"
# Cluster section should show F80 ↔ F81 (both members, even though only F80 matched)
echo "$OUT" | grep -qE "F80.*F81|F81.*F80" || fail "cluster should preserve both members: $OUT"
echo "$OUT" | grep -q "F82" && fail "F82 (no match) should not appear: $OUT"
pass "hv-backlog --grep filters clusters but preserves all members"

echo "hv-backlog no-flag regression"
OUT_FILTERED=$("$BIN/hv-backlog" --grep "")
OUT_PLAIN=$("$BIN/hv-backlog")
[ "$OUT_FILTERED" = "$OUT_PLAIN" ] || fail "empty --grep should equal no-flag output"
pass "hv-backlog --grep '' equals unfiltered output"

