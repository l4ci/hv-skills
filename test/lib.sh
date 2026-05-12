#!/usr/bin/env bash
# Shared helpers for smoke test sections.
#
# Sourced by test/runner.sh. Defines pass/fail for assertion narration.
#
# Local-trap convention (F38) — when a section creates its own tmp tree,
# it MUST install a local trap immediately after mktemp -d and restore the
# global trap before its terminal `pass` line. Example:
#
#   TMP_X="$(mktemp -d)"
#   trap 'rm -rf "$TMP_X"' EXIT
#   ... assertions ...
#   trap 'rm -rf "$TMP"' EXIT
#   pass "..."
#
# This survives mid-block fail() under set -euo pipefail; the bare
# rm-at-end pattern leaks. Apply the same pattern in any new section.

pass() { printf '  \033[32mOK\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

# F62 — preamble convention scan. Reads every test/sections/*.sh and fails
# if any forbidden pattern is found. Catches the class of regressions where
# per-section drift would shadow runner state or violate the F38 local-trap
# convention. Called once by runner.sh before the section loop.
check_section_conventions() {
  local sections_dir="$1"
  local violations=0

  # B22-class — top-level `TMP=` assignment shadows runner's $TMP.
  # Permitted: `TMP_<SUFFIX>=` (e.g., TMP_X, TMP_CFG) per the F38 convention.
  # Also permitted inside comments and inside `local`/`readonly` declarations.
  local matches
  matches=$(grep -nE '^[[:space:]]*TMP=' "$sections_dir"/*.sh 2>/dev/null || true)
  if [ -n "$matches" ]; then
    printf '\033[31merror: section file shadows runner $TMP (use TMP_<SUFFIX>=$(mktemp -d) instead):\033[0m\n' >&2
    echo "$matches" >&2
    violations=$((violations + 1))
  fi

  # B19-class — bare `trap '... EXIT'` that doesn't restore the global trap
  # before the section's terminal `pass` line. Detect by looking for files
  # that install a local trap but never reset it back to the global form
  # (`trap 'rm -rf "$TMP"' EXIT`). This is a heuristic, not exhaustive —
  # a section that installs its own trap MUST also reset it.
  local file
  for file in "$sections_dir"/*.sh; do
    [ -f "$file" ] || continue
    # Only check sections that install a local trap.
    grep -qE "^[[:space:]]*trap[[:space:]]+'.*\\\$TMP_" "$file" 2>/dev/null || continue
    # Must reset to the global trap before the section ends.
    if ! grep -qE "^[[:space:]]*trap[[:space:]]+'rm -rf[[:space:]]+\"?\\\$TMP\"?'[[:space:]]+EXIT" "$file" 2>/dev/null; then
      printf '\033[31merror: section installs a local trap but never restores the global trap (F38 convention):\033[0m\n' >&2
      echo "  $file" >&2
      violations=$((violations + 1))
    fi
  done

  if [ "$violations" -gt 0 ]; then
    printf '\033[31merror: %d convention violation(s) in test/sections/ — fix before re-running smoke\033[0m\n' "$violations" >&2
    return 1
  fi
  return 0
}
