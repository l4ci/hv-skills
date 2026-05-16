# shellcheck shell=bash
# Sourceable preamble. Source from a helper's first executable line to
# initialize the canonical bootstrap state: derives HERE from BASH_SOURCE
# (works for both exec'd and sourced helpers), sources hv-self-locate.sh,
# and invokes hv_self_locate. Collapses the 3-line preamble idiom
# (HERE= + . hv-self-locate.sh + hv_self_locate) into one source line.
#
# Usage from a sibling helper:
#   . "$(dirname "${BASH_SOURCE[0]}")/hv-preamble.sh"
#
# After sourcing, HERE is exported and downstream `. "$HERE/<other>.sh"` and
# `"$HERE/hv-walk-up"` references resolve as before.
#
# Side effects (intentional — this is why the file is named *-preamble.sh,
# not *-self-locate.sh, which stays a pure define-only library that this
# preamble sources):
# - exports HERE (preamble's own bin/ dir, resolved via BASH_SOURCE)
# - exports HV_ORIG_PWD (caller's pre-cd cwd, physical path; set by hv_self_locate)
# - cds to umbrella root when cwd doesn't already contain .hv/ (delegated to hv_self_locate)
#
# Bootstrap helpers that must operate before .hv/ exists (hv-preflight,
# hv-bootstrap, hv-walk-up, hv-self-locate.sh itself, hv-resolve-*,
# hv-umbrella-*) do NOT source this file — they handle their own
# bootstrap without depending on a resolved umbrella.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HERE
. "$HERE/hv-self-locate.sh"
hv_self_locate
