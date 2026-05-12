echo "hv-uncertain"
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
- **[F53] [Major] Certain item.** Use `helper` and `hvlib` to do X. Milestone: M01
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

Use `helper` and `hvlib`. Concrete plan, no uncertainty.
EOF

  # F54: detail file present with backticks; should still exit 1 (Minor).
  cat > .hv/features/F54.md <<'EOF'
# F54 detail

Use `something` to do Y.
EOF

  # Item not in TODO -> exit 2.
  set +e
  out=$("$BIN/hv-uncertain" F99 2>&1); rc=$?
  set -e
  [ "$rc" = "2" ] || fail "hv-uncertain F99: expected exit 2, got $rc"
  echo "$out" | grep -q "not found" || fail "hv-uncertain F99: missing 'not found' in stderr: $out"
  pass "hv-uncertain returns 2 when item missing"

  # F50: Major, no detail file -> exit 0 with "no detail file".
  set +e
  out=$("$BIN/hv-uncertain" F50); rc=$?
  set -e
  [ "$rc" = "0" ] || fail "hv-uncertain F50: expected exit 0, got $rc"
  echo "$out" | grep -q "no detail file" || fail "hv-uncertain F50: missing 'no detail file': $out"
  # F50 also has zero backticks, so unknown-surface should also fire.
  echo "$out" | grep -q "no concrete identifiers" || fail "hv-uncertain F50: missing unknown-surface gate: $out"
  pass "hv-uncertain F50 fires no-detail-file gate"

  # F51: Major, detail file but zero backticks -> exit 0 with unknown-surface.
  set +e
  out=$("$BIN/hv-uncertain" F51); rc=$?
  set -e
  [ "$rc" = "0" ] || fail "hv-uncertain F51: expected exit 0, got $rc"
  echo "$out" | grep -q "no concrete identifiers" || fail "hv-uncertain F51: missing unknown-surface: $out"
  echo "$out" | grep -q "no detail file" && fail "hv-uncertain F51: should not fire no-detail-file: $out"
  pass "hv-uncertain F51 fires unknown-surface gate"

  # F52: Major, detail file + backticks but >=2 ? -> exit 0 with open-question signals.
  set +e
  out=$("$BIN/hv-uncertain" F52); rc=$?
  set -e
  [ "$rc" = "0" ] || fail "hv-uncertain F52: expected exit 0, got $rc"
  echo "$out" | grep -q "multiple open-question signals" || fail "hv-uncertain F52: missing open-question gate: $out"
  pass "hv-uncertain F52 fires multiple-open-question-signals gate"

  # F53: Major, detail file + backticks + 0 ? + no markers -> exit 1 (certain).
  set +e
  out=$("$BIN/hv-uncertain" F53); rc=$?
  set -e
  [ "$rc" = "1" ] || fail "hv-uncertain F53: expected exit 1 (certain), got $rc; out=$out"
  pass "hv-uncertain F53 returns 1 when certain"

  # F54: Minor, regardless of other gates -> exit 1.
  set +e
  out=$("$BIN/hv-uncertain" F54); rc=$?
  set -e
  [ "$rc" = "1" ] || fail "hv-uncertain F54: expected exit 1 (Minor), got $rc; out=$out"
  pass "hv-uncertain F54 returns 1 for Minor regardless of other gates"
)
echo "ok hv-uncertain"

echo "F37: TaskCreate progress-checklist convention"
TIER_SAB_F37=(hv-init hv-work hv-debug hv-ship hv-release \
              hv-docs hv-refactor hv-learn hv-decide hv-spike hv-vision \
              hv-capture hv-next hv-pause hv-review hv-plan hv-config hv-rm)
TIER_C_F37=(hv-assume hv-go hv-update hv-c hv-map)

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
echo "ok F37"

echo "hvlib parse_term_entry / first_sentence"
PYTHONPATH="$BIN" python3 - <<'PY'
import sys
from hvlib import parse_term_entry, first_sentence

# Term body with all three fields
body = """
The canonical project queue — `.hv/BACKLOG.md`. Items are zero-padded IDs
([B01]/[F01]/[T01]).

**Aliases:** task list, todo list
**Not:** session state, handoff
<!-- 2026-05-10 -->
"""
parsed = parse_term_entry(body)
assert parsed["definition"].startswith("The canonical project queue"), \
    f"definition wrong: {parsed['definition']!r}"
assert parsed["aliases"] == ["task list", "todo list"], parsed["aliases"]
assert parsed["nots"] == ["session state", "handoff"], parsed["nots"]

# Term body with only definition + Aliases _none_
body2 = """
A signed Ed25519 cross-org registry entry.

**Aliases:** _none_
<!-- 2026-05-10 -->
"""
p2 = parse_term_entry(body2)
assert p2["aliases"] == [], p2["aliases"]
assert p2["nots"] == [], p2["nots"]
assert "Ed25519" in p2["definition"]

# first_sentence — short, fits in budget
assert first_sentence("Hello world. Second.") == "Hello world."
# first_sentence — over budget, ellipsis at word boundary
long = "A" + " banana" * 40 + "."
out = first_sentence(long, max_chars=40)
assert out.endswith("…"), out
assert len(out) <= 41, len(out)
# first_sentence — no terminator
assert first_sentence("no period here") == "no period here"
# first_sentence — empty
assert first_sentence("") == ""

# first_sentence — trailing comma stripped at cut boundary
# Text with no sentence terminator → full text is the "sentence"
# max_chars=12: sentence[:12]="alpha beta, " → rsplit→ cut="alpha beta,"
# rstrip(",;") strips the comma → "alpha beta…"
comma_text = "alpha beta, gamma " + ("word " * 40)
out_comma = first_sentence(comma_text, max_chars=12)
assert out_comma == "alpha beta…", f"comma not stripped: {out_comma!r}"

# Verify period NOT stripped: the narrowed rstrip(",;") preserves "." and ":"
# where the old rstrip(".,;:") would have stripped them.
# (Sentence-boundary "." is intercepted by the regex before reaching rstrip;
#  this exercises the rstrip contract directly on hypothetical cut values.)
assert "foo Mr.".rstrip(",;") == "foo Mr.", "trailing period must be preserved"
assert "foo Mr.".rstrip(".,;:") == "foo Mr", "sanity: old rstrip strips trailing period"
assert "bar:".rstrip(",;") == "bar:", "colon must be preserved"
assert "bar:".rstrip(".,;:") == "bar", "sanity: old rstrip strips trailing colon"

print("OK hvlib context helpers")
PY
pass "hvlib parse_term_entry + first_sentence"
