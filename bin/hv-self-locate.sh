# shellcheck shell=bash
# Sourceable helper. cd to the umbrella root (the directory containing .hv/)
# so that helpers can reference .hv/<file> via cwd-relative paths regardless
# of where they were invoked from.
#
# Usage from a sibling helper:
#   HERE="$(cd "$(dirname "$0")" && pwd)"
#   . "$HERE/hv-self-locate.sh"
#   hv_self_locate
#
# Side effects:
# - Exports HV_ORIG_PWD (caller's pre-cd cwd, physical path) so helpers
#   that need cwd-aware git ops can `cd "$HV_ORIG_PWD"` or `git -C
#   "$HV_ORIG_PWD"` to recover.
# - cds to the resolved umbrella root if cwd doesn't already contain .hv/.
#
# Resolution order:
#   1. cwd has .hv/ → no cd, fast path. Preserves the smoke-test contract
#      (tests cd to $TMP and expect helpers to operate on $TMP/.hv/).
#   2. walk up from cwd via bin/hv-walk-up (subprocess inherits cwd). cd
#      to the result. This prefers the project the caller is *in* — when
#      a dev-tree helper is invoked from inside a test umbrella's sub-cwd
#      that lacks .hv/, the test's umbrella wins over the helper's own.
#   3. walk up from BASH_SOURCE[1] (caller helper's bin/ dir) via the same
#      subprocess. This is the fallback when cwd has no .hv/ ancestor —
#      installed helpers at <umbrella>/.hv/bin/<script> still find their
#      umbrella when the user runs them from an unrelated cwd.
#   4. on exhaustion, return 1 with an error.
#
# Uses `cd "$d" && pwd -P` rather than `realpath` for portability and to
# resolve through symlinks consistently (KNOWLEDGE.md 2026-05-02:
# "use `cd "$dir" 2>/dev/null && pwd -P`").
hv_self_locate() {
  HV_ORIG_PWD="$(pwd -P)"
  export HV_ORIG_PWD

  [ -d ".hv" ] && return 0

  local caller_dir result
  caller_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd -P)"

  # Try cwd-anchored walk-up first. hv-walk-up defaults to anchor=cwd; we
  # invoke it without changing the subprocess cwd, so it walks up from
  # $HV_ORIG_PWD.
  if result="$("$caller_dir/hv-walk-up" 2>/dev/null)"; then
    cd "$result"
    return 0
  fi

  # Fall back to walking up from the caller helper's directory.
  if result="$(cd "$caller_dir" && "$caller_dir/hv-walk-up" 2>/dev/null)"; then
    cd "$result"
    return 0
  fi

  echo "error: hv_self_locate: no .hv/ found in ancestors of $HV_ORIG_PWD or ${BASH_SOURCE[1]:-$0}" >&2
  return 1
}
