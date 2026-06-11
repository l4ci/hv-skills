echo "F65 — SKILL.md ↔ helper docstring drift check"

# Each entry: helper, citing SKILL.md (relative to $REPO), key term that
# must appear in BOTH the helper's header comment block AND the SKILL.md
# prose. The term is the canonical contract anchor — if either side drops
# it, drift is real and the test fails.
#
# Adding new entries: pick a helper whose contract is non-trivial enough
# that drift would matter, identify its primary call-site SKILL.md, and
# pick a term that uniquely names the helper's invariant. Don't pad —
# more entries = more friction; the value is catching real drift, not
# breadth of coverage.

drift_check() {
  local helper="$1"
  local skill="$2"
  local term="$3"

  local helper_path="$REPO/bin/$helper"
  local skill_path="$REPO/$skill"

  [ -f "$helper_path" ] || { fail "F65 — helper not found: bin/$helper"; }
  [ -f "$skill_path" ] || { fail "F65 — SKILL.md not found: $skill"; }

  # Helper's header: comment block before `set -...` / first non-comment line.
  # Grep for the term within the first 40 lines (covers any reasonable header).
  if ! head -40 "$helper_path" | grep -qF "$term"; then
    fail "F65 drift — bin/$helper header missing term: \"$term\""
  fi

  # SKILL.md prose: term must appear somewhere in the file.
  if ! grep -qF "$term" "$skill_path"; then
    fail "F65 drift — $skill missing term: \"$term\" (helper bin/$helper's header pins it)"
  fi
}

# Sample set — small and selective. Each line is one (helper, SKILL.md,
# anchor term) triple. Add entries as future drift-prone contracts surface.
drift_check "hv-umbrella-on"          "hv-work/SKILL.md"   ".hv/repos.json"
drift_check "hv-preflight"            "hv-init/SKILL.md"   "hv-init"
drift_check "hv-config-set"           "hv-config/SKILL.md" "hv-config-set"
drift_check "hv-resolve-handoff"      "hv-next/SKILL.md"   "hv-resolve-handoff"
drift_check "hv-guard-feature-branch" "hv-ship/SKILL.md"   "hv-guard-feature-branch"

pass "F65 — sampled helper docstrings align with citing SKILL.md prose"
