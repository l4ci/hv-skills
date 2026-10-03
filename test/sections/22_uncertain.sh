echo "plan uncertain"
(
  UTMP="$(mktemp -d)"
  trap 'rm -rf "$UTMP"' EXIT
  mkdir -p "$UTMP/.hv/bugs" "$UTMP/.hv/features" "$UTMP/.hv/tasks"
  cd "$UTMP"

  cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features
- **[F50] [Major] Major no detail file.** Just a brief.
- **[F51] [Major] Major zero backticks.** Plain prose with no identifiers. Milestone: M01
- **[F52] [Major] Major with questions?** What about this? And this? Detail: see `code`. Milestone: M01
- **[F53] [Major] Certain item.** Use `helper` and `lib` to do X. Milestone: M01
- **[F54] [Minor] Minor item.** No detail file no backticks no markers. Milestone: M01

## Tasks

## Completed
EOF

  # F51: detail file present but contains zero backticks anywhere.
  cat > .hv/features/F51.md <<'EOF'
# F51 detail

Plain prose. No code spans. Just words.
EOF

  # F52: detail file present with backticks; brief already has 2+ question marks.
  cat > .hv/features/F52.md <<'EOF'
# F52 detail

Use `widget` and explain. Why?
EOF

  # F53: detail file present with backticks, no markers, 0 question marks.
  cat > .hv/features/F53.md <<'EOF'
# F53 detail

Use `helper` and `lib`. Concrete plan, no uncertainty.
EOF

  # F54: detail file present with backticks; should still exit 1 (Minor).
  cat > .hv/features/F54.md <<'EOF'
# F54 detail

Use `something` to do Y.
EOF

  # Item not in TODO -> exit 3 (resolution).
  rc=0; out=$(hvj plan uncertain F99 2>/dev/null) || rc=$?
  [ "$rc" = "3" ] || fail "plan uncertain F99: expected exit 3, got $rc"
  [ "$(jget error.code <<<"$out")" = "resolution" ] || fail "plan uncertain F99: expected code resolution: $out"
  pass "plan uncertain returns 3 when item missing"

  # F50: Major, no detail file -> exit 0 (uncertain) with "no detail file".
  rc=0; out=$(hvj plan uncertain F50) || rc=$?
  [ "$rc" = "0" ] || fail "plan uncertain F50: expected exit 0, got $rc"
  [ "$(jget data.uncertain <<<"$out")" = "true" ] || fail "plan uncertain F50: expected uncertain true: $out"
  [ "$(jget data.id <<<"$out")" = "F50" ] || fail "plan uncertain F50: wrong id: $out"
  [ "$(jget data.type <<<"$out")" = "F" ] || fail "plan uncertain F50: wrong type: $out"
  FIELD=$(jget data.reasons <<<"$out")
  grep -q "no detail file" <<<"$FIELD" || fail "plan uncertain F50: missing 'no detail file': $out"
  # F50 also has zero backticks, so unknown-surface should also fire.
  FIELD=$(jget data.reasons <<<"$out")
  grep -q "no concrete identifiers" <<<"$FIELD" || fail "plan uncertain F50: missing unknown-surface gate: $out"
  pass "plan uncertain F50 fires no-detail-file gate"

  # F51: Major, detail file but zero backticks -> exit 0 with unknown-surface.
  rc=0; out=$(hvj plan uncertain F51) || rc=$?
  [ "$rc" = "0" ] || fail "plan uncertain F51: expected exit 0, got $rc"
  reasons=$(jget data.reasons <<<"$out")
  grep -q "no concrete identifiers" <<<"$reasons" || fail "plan uncertain F51: missing unknown-surface: $out"
  if grep -q "no detail file" <<<"$reasons"; then fail "plan uncertain F51: should not fire no-detail-file: $out"; fi
  pass "plan uncertain F51 fires unknown-surface gate"

  # F52: Major, detail file + backticks but >=2 ? -> exit 0 with open-question signals.
  rc=0; out=$(hvj plan uncertain F52) || rc=$?
  [ "$rc" = "0" ] || fail "plan uncertain F52: expected exit 0, got $rc"
  FIELD=$(jget data.reasons <<<"$out")
  grep -q "multiple open-question signals" <<<"$FIELD" || fail "plan uncertain F52: missing open-question gate: $out"
  pass "plan uncertain F52 fires multiple-open-question-signals gate"

  # F53: Major, detail file + backticks + 0 ? + no markers -> exit 1 (certain).
  rc=0; out=$(hvj plan uncertain F53 2>/dev/null) || rc=$?
  [ "$rc" = "1" ] || fail "plan uncertain F53: expected exit 1 (certain), got $rc; out=$out"
  [ "$(jget data.uncertain <<<"$out")" = "false" ] || fail "plan uncertain F53: expected uncertain false: $out"
  [ "$(jget data.reasons <<<"$out")" = "[]" ] || fail "plan uncertain F53: expected no reasons: $out"
  pass "plan uncertain F53 returns 1 when certain"

  # F54: Minor, regardless of other gates -> exit 1.
  rc=0; out=$(hvj plan uncertain F54 2>/dev/null) || rc=$?
  [ "$rc" = "1" ] || fail "plan uncertain F54: expected exit 1 (Minor), got $rc; out=$out"
  [ "$(jget data.uncertain <<<"$out")" = "false" ] || fail "plan uncertain F54: expected uncertain false: $out"
  pass "plan uncertain F54 returns 1 for Minor regardless of other gates"
)
echo "ok plan uncertain"

# white-box-begin: A9 #53 doclint
echo "F37: TaskCreate progress-checklist convention"
TIER_SAB_F37=(hv-init hv-work hv-debug hv-ship hv-release \
              hv-refactor hv-learn hv-decide hv-spike hv-vision \
              hv-capture hv-next hv-pause hv-review hv-plan hv-config)
TIER_C_F37=(hv-go hv-update)

for skill in "${TIER_SAB_F37[@]}"; do
  grep -q "TaskCreate(" "$REPO/$skill/SKILL.md" \
    || fail "F37: Tier S/A/B skill $skill/SKILL.md missing TaskCreate( reference"
done
pass "Tier S/A/B SKILL.md files reference TaskCreate("

for skill in "${TIER_C_F37[@]}"; do
  if grep -q "TaskCreate(" "$REPO/$skill/SKILL.md"; then
    fail "F37: Tier C skill $skill/SKILL.md unexpectedly has TaskCreate( (should be unchanged per F37 plan)"
  fi
done
pass "Tier C SKILL.md files do not reference TaskCreate("
# white-box-end
echo "ok F37"
