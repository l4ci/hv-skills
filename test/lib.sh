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

# require_go_verb <verb words...>: a section for a verb that only Go serves
# (the old helpers never had it, or the shim's version lacks the flags) starts
#   require_go_verb init umbrella || return 0
# It succeeds when HV_BIN lists the verb in `hv __verbs` (the Go binary, or the
# hybrid when it routes the verb there). The plain shim has no __verbs, so the
# section prints a SKIP line and the caller returns. S7 (#53) deletes the shim
# and this helper with it.
require_go_verb() {
  local want="$*"
  if grep -qxF -- "$want" <<<"$("$HV_BIN" __verbs 2>/dev/null || true)"; then
    return 0
  fi
  printf '  \033[33mSKIP\033[0m hv %s is not served by %s (needs the Go binary)\n' "$want" "$HV_BIN"
  return 1
}

# Black-box helpers (#46). Callers check the exit code themselves:
#   rc=0; out=$(hvj item show B01) || rc=$?
# hvj runs `"$HV_BIN" --json "$@"`, prints the envelope and returns the verb's
# own exit code (stderr is left alone; redirect it where a failure is expected).
hvj() { "$HV_BIN" --json "$@"; }

# jget <path> reads one value from an envelope on stdin. The path is dotted
# with [n] indexes (data.items[0].id). Strings print raw, bools as true/false,
# everything else as compact JSON. A missing path prints nothing and fails.
jget() {
  python3 -c '
import json, re, sys
v = json.load(sys.stdin)
try:
    for k in re.findall(r"[^.\[\]]+|\[\d+\]", sys.argv[1]):
        v = v[int(k[1:-1])] if k[0] == "[" else v[k]
except (KeyError, IndexError, TypeError):
    sys.exit(1)
print(v if isinstance(v, str) else json.dumps(v, separators=(",", ":")))
' "$1"
}

# F22 canonical mirror — strips stale helpers before copying fresh from $BIN.
# Mirrors hv-init/SKILL.md Step 2. Callers must have $BIN set (runner provides it)
# and .hv/bin/ already mkdir'd. Two-step delete-then-copy is intentional; matches
# production semantics so smoke catches rename-regressions.
install_helpers() {
  find .hv/bin/ -maxdepth 1 \( -name 'hv-*' -o -name 'hvlib*.py' \) -type f -delete
  cp "$BIN"/hv-* "$BIN"/hvlib*.py .hv/bin/ && chmod +x .hv/bin/hv-*
}

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
