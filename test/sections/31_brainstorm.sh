echo "## hv-design-add / hv-design-show / hv-design-rm / hv-design-list (brainstorm family)"

DSN_TMP="$(mktemp -d)"
trap 'rm -rf "$DSN_TMP"' EXIT
(
  cd "$DSN_TMP"
  mkdir -p .hv

  # 1. hv-design-add positive — exit 0, prints F00, file lands with id frontmatter
  OUT=$("$BIN/hv-design-add" F00 "smoke design") || { echo "FAIL: hv-design-add F00 exited non-zero"; exit 1; }
  [ "$OUT" = "F00" ] || { echo "FAIL: hv-design-add did not print 'F00', got '$OUT'"; exit 1; }
  [ -f .hv/designs/F00.md ] || { echo "FAIL: .hv/designs/F00.md not created"; exit 1; }
  grep -q "^id: F00$" .hv/designs/F00.md || { echo "FAIL: frontmatter missing id: F00"; exit 1; }
  grep -q "^title: smoke design$" .hv/designs/F00.md || { echo "FAIL: frontmatter missing title"; exit 1; }

  # 2. hv-design-add rejects slice-shape ID — exit 1, stderr names the regex
  ERR=$("$BIN/hv-design-add" S01 "x" 2>&1 >/dev/null) && { echo "FAIL: S01 should be rejected"; exit 1; }
  echo "$ERR" | grep -qE '\[BFT\]\\d\{2,\}' || { echo "FAIL: stderr missing [BFT]\\d{2,} regex hint for S01: '$ERR'"; exit 1; }

  # 3. hv-design-add rejects milestone-shape ID — exit 1
  ERR=$("$BIN/hv-design-add" M01 "x" 2>&1 >/dev/null) && { echo "FAIL: M01 should be rejected"; exit 1; }
  echo "$ERR" | grep -qE '\[BFT\]\\d\{2,\}' || { echo "FAIL: stderr missing regex hint for M01: '$ERR'"; exit 1; }

  # 4. hv-design-add conflict — exit 1, stderr says already exists
  ERR=$("$BIN/hv-design-add" F00 "again" 2>&1 >/dev/null) && { echo "FAIL: conflict on existing F00 should exit 1"; exit 1; }
  echo "$ERR" | grep -q "already exists" || { echo "FAIL: conflict stderr missing 'already exists': '$ERR'"; exit 1; }

  # 5. hv-design-show positive — exit 0, contains id frontmatter
  OUT=$("$BIN/hv-design-show" F00) || { echo "FAIL: hv-design-show F00 exited non-zero"; exit 1; }
  echo "$OUT" | grep -q "^id: F00$" || { echo "FAIL: hv-design-show did not print id: F00"; exit 1; }

  # 6. hv-design-show miss — exit 1
  if "$BIN/hv-design-show" F99 2>/dev/null; then
    echo "FAIL: hv-design-show F99 (missing) should exit 1"; exit 1
  fi

  # 6b. F26: hv-design-show sources the shared lib
  grep -q "hv-artifact-show.sh" "$BIN/hv-design-show" || { echo "FAIL: hv-design-show should source hv-artifact-show.sh after F26"; exit 1; }

  # 7. hv-design-list non-empty — valid JSON containing F00 entry
  OUT=$("$BIN/hv-design-list") || { echo "FAIL: hv-design-list exited non-zero"; exit 1; }
  echo "$OUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert isinstance(data, list), f'expected list, got {type(data).__name__}'
assert len(data) == 1, f'expected 1 entry, got {len(data)}: {data}'
assert data[0]['id'] == 'F00', f'id wrong: {data[0]}'
assert data[0]['title'] == 'smoke design', f'title wrong: {data[0]}'
assert data[0]['status'] == 'draft', f'status wrong: {data[0]}'
" || { echo "FAIL: hv-design-list JSON shape wrong"; exit 1; }

  # 8. hv-design-rm positive — exit 0, file removed
  "$BIN/hv-design-rm" F00 || { echo "FAIL: hv-design-rm F00 exited non-zero"; exit 1; }
  [ ! -f .hv/designs/F00.md ] || { echo "FAIL: .hv/designs/F00.md still present after rm"; exit 1; }

  # 9. hv-design-rm miss — exit 1
  if "$BIN/hv-design-rm" F99 2>/dev/null; then
    echo "FAIL: hv-design-rm F99 (missing) should exit 1"; exit 1
  fi

  # 10. hv-design-list empty after rm — emits []
  OUT=$("$BIN/hv-design-list") || { echo "FAIL: hv-design-list (empty) exited non-zero"; exit 1; }
  echo "$OUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data == [], f'expected [], got {data!r}'
" || { echo "FAIL: hv-design-list did not emit [] after rm"; exit 1; }
) || fail "hv-design-* family assertions"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$DSN_TMP"
pass "hv-design-add / show / rm / list: writer + resolve + lookup contracts hold under happy + error paths"

echo "## hv-design-amend (T110 — section amend via shared hv-artifact-amend lib)"

AMD_TMP="$(mktemp -d)"
trap 'rm -rf "$AMD_TMP"' EXIT
(
  cd "$AMD_TMP"
  mkdir -p .hv

  "$BIN/hv-design-add" F00 "amend smoke" >/dev/null || { echo "FAIL: seeding design failed"; exit 1; }

  # a. --replace on an existing section — exit 0; new text shows, old placeholder gone, other section untouched
  "$BIN/hv-design-amend" F00 --section Goal --replace "Ship the amend helper." \
    || { echo "FAIL: hv-design-amend --replace exited non-zero"; exit 1; }
  OUT=$("$BIN/hv-design-show" F00) || { echo "FAIL: show after replace exited non-zero"; exit 1; }
  echo "$OUT" | grep -q "Ship the amend helper." || { echo "FAIL: replaced Goal text missing"; exit 1; }
  echo "$OUT" | grep -q "one sentence — what shipping" && { echo "FAIL: old Goal placeholder still present after replace"; exit 1; }
  echo "$OUT" | grep -q "the chosen shape, the moving parts" || { echo "FAIL: Design section was clobbered by Goal replace"; exit 1; }

  # b. --append to a section — exit 0; both prior content and appended text present; next heading intact
  "$BIN/hv-design-amend" F00 --section Goal --append "And keep it atomic." \
    || { echo "FAIL: hv-design-amend --append exited non-zero"; exit 1; }
  OUT=$("$BIN/hv-design-show" F00) || { echo "FAIL: show after append exited non-zero"; exit 1; }
  echo "$OUT" | grep -q "Ship the amend helper." || { echo "FAIL: prior Goal content lost after append"; exit 1; }
  echo "$OUT" | grep -q "And keep it atomic." || { echo "FAIL: appended Goal text missing"; exit 1; }
  echo "$OUT" | grep -q "^## Design$" || { echo "FAIL: ## Design heading not intact after append"; exit 1; }

  # c. non-existent section — exit 1, stderr mentions section not found
  ERR=$("$BIN/hv-design-amend" F00 --section Nope --replace "x" 2>&1 >/dev/null) && { echo "FAIL: amend bogus section should exit 1"; exit 1; }
  echo "$ERR" | grep -q "not found" || { echo "FAIL: stderr missing 'not found' for bogus section: '$ERR'"; exit 1; }

  # d. missing design ID (no file) — exit 1, stderr says not found
  ERR=$("$BIN/hv-design-amend" F99 --section Goal --replace "x" 2>&1 >/dev/null) && { echo "FAIL: amend missing design should exit 1"; exit 1; }
  echo "$ERR" | grep -q "not found" || { echo "FAIL: stderr missing 'not found' for missing design: '$ERR'"; exit 1; }

  # e. bad ID shape — exit 1
  if "$BIN/hv-design-amend" S01 --section Goal --replace "x" 2>/dev/null; then
    echo "FAIL: bad ID shape S01 should exit 1"; exit 1
  fi

  # f. wrapper sources the shared lib (mirrors F26 hv-design-show assertion)
  grep -q "hv-artifact-amend.sh" "$BIN/hv-design-amend" || { echo "FAIL: hv-design-amend should source hv-artifact-amend.sh"; exit 1; }
) || fail "hv-design-amend assertions"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$AMD_TMP"
pass "hv-design-amend: replace/append section contracts hold; rejects bad section, missing design, bad ID; sources shared lib"

echo "## /hv-plan integration with --design pointer"

PLN_TMP="$(mktemp -d)"
trap 'rm -rf "$PLN_TMP"' EXIT
(
  cd "$PLN_TMP"
  mkdir -p .hv

  # Seed a design artifact via the writer helper
  "$BIN/hv-design-add" F00 "design for F00" >/dev/null || { echo "FAIL: seeding design failed"; exit 1; }

  # 11. hv-plan-add --design writes a plan with design: frontmatter pointer
  KEY=$("$BIN/hv-plan-add" --design .hv/designs/F00.md M01 F00 "plan for F00") || { echo "FAIL: hv-plan-add --design exited non-zero"; exit 1; }
  [ "$KEY" = "M01-F00" ] || { echo "FAIL: plan key wrong: '$KEY'"; exit 1; }
  PLAN=".hv/plans/M01-F00.md"
  [ -f "$PLAN" ] || { echo "FAIL: plan file not created"; exit 1; }
  grep -q "^design: \.hv/designs/F00\.md$" "$PLAN" || { echo "FAIL: plan frontmatter missing design pointer"; exit 1; }

  # 12. hv-plan-add --design rejects missing design file
  if "$BIN/hv-plan-add" --design .hv/designs/nope.md M01 B99 "x" 2>/dev/null; then
    echo "FAIL: missing design file should exit 1"; exit 1
  fi
) || fail "/hv-plan --design integration assertions"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$PLN_TMP"
pass "hv-plan-add --design records design pointer in frontmatter; rejects missing design path"

echo "B28: hv-brainstorm --auto-loop frontmatter convention"

# Auto-loop mode marks the design artifact with auto: true frontmatter (per hv-plan F32 convention).
grep -q 'auto: true' "$REPO/hv-brainstorm/SKILL.md" \
  || fail "B28: hv-brainstorm/SKILL.md must document 'auto: true' frontmatter under --auto-loop"

# Auto-loop autonomy gate is wired in Step 1 (mode entered when flag is present under loop autonomy).
grep -q 'AUTO_LOOP' "$REPO/hv-brainstorm/SKILL.md" \
  || fail "B28: hv-brainstorm/SKILL.md must parse the --auto-loop flag in Step 1"

pass "B28: hv-brainstorm --auto-loop frontmatter + autonomy gate wired"
