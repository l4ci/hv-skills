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
#   2. else delegate walk-up from BASH_SOURCE[1] to bin/hv-walk-up
#      (subprocess), then cd to the resolved umbrella root.
#   3. on exhaustion, return 1 with an error.
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
  # Delegate the walk-up to bin/hv-walk-up. We invoke it as a subprocess from
  # the caller's helper directory (BASH_SOURCE[1] anchor) — hv-walk-up itself
  # walks from its own cwd, so we cd to caller_dir first via the subprocess's
  # own cwd. Resolve the bin path through the same caller_dir (siblings).
  if result="$(cd "$caller_dir" && "$caller_dir/hv-walk-up" 2>/dev/null)"; then
    cd "$result"
    return 0
  fi
  echo "error: hv_self_locate: no .hv/ found in ancestors of ${BASH_SOURCE[1]:-$0} or in cwd $HV_ORIG_PWD" >&2
  return 1
}
