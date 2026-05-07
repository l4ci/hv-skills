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
#   2. else walk up from the calling helper's location (BASH_SOURCE[1])
#      until a .hv/ sibling is found, then cd there. This works for the
#      common umbrella case: invoker is in a sub-repo, helper script lives
#      at <umbrella>/.hv/bin/<script>, walk-up of <umbrella>/.hv/bin yields
#      <umbrella>/, which has .hv/ → cd <umbrella>.
#   3. on exhaustion, return 1 with an error.
#
# Uses `cd "$d" && pwd -P` rather than `realpath` for portability and to
# resolve through symlinks consistently (KNOWLEDGE.md 2026-05-02:
# "use `cd "$dir" 2>/dev/null && pwd -P`").
hv_self_locate() {
  HV_ORIG_PWD="$(pwd -P)"
  export HV_ORIG_PWD

  [ -d ".hv" ] && return 0

  local caller_dir candidate
  caller_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd -P)"
  candidate="$caller_dir"
  while [ "$candidate" != "/" ]; do
    if [ -d "$candidate/.hv" ]; then
      cd "$candidate"
      return 0
    fi
    candidate="$(cd "$candidate/.." && pwd -P)"
  done
  echo "error: hv_self_locate: no .hv/ found in ancestors of ${BASH_SOURCE[1]:-$0} or in cwd $HV_ORIG_PWD" >&2
  return 1
}
