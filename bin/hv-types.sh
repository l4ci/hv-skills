# shellcheck shell=bash
# Single source of truth for the item-type registry.
# Sourced — not executed — by helpers that need to scan BACKLOG.md / ARCHIVE.md
# for backlog item IDs (B/F/T) and surface them in regex.
#
# Usage from a sibling helper:
#   . "$(dirname "$0")/hv-types.sh"
#   # bash regex:  use "[$HV_ITEM_TYPES]"
#   # python:      import hvlib_types (parses this file directly; heredocs
#   #              must NOT rely on the env vars — most don't source this)
#
# HV_ITEM_TYPES        — backlog items only: Bugs / Features / Tasks.
#                        Used by hv-backlog, hv-summary, hv-ship-body,
#                        hv-review-scope, hv-todo-by-milestone.
# HV_OPEN_SECTIONS     — canonical "## <name>" headings under which open
#                        backlog items live in BACKLOG.md. Consumers iterate
#                        this set rather than re-deriving
#                        ("Bugs", "Features", "Tasks") inline.
# HV_MILESTONE_STATUSES — pipe-separated milestone status enum.
#                        Used by hv-vision-status (validation) and
#                        hv-vision-index (drift heal regex).
# HV_MILESTONE_PREFIX  — single-letter prefix for milestone IDs (current "M").
#                        Used by hvlib.parse_milestones, which extracts every
#                        `<prefix>\d+` ID from arbitrary text (Milestone: field,
#                        frontmatter depends:, etc.).
#
# HV_COUNTABLE_TYPES   — types tracked in counters.json since_refactor (B,F).
#                        (hv-complete consumes COUNTABLE_TYPES via
#                        hvlib_types, not this env var.)
# HV_PLANNABLE_TYPES   — types that can carry a milestone plan (B,F,T,S=Slice).
#                        Used by: hv-plan-add (validates plan-key format).
#
# Naming note: this file is "hv-types.sh" (not "_hv-types.sh") so that
# `cp hv-* .hv/bin/` in /hv-init Step 2 picks it up. hv-preflight discovers
# helpers via a `hv-*` glob and skips itself; this file is verified by the
# same glob (it's a sourced lib, but `/hv-init` chmods it +x alongside the
# executables, so the `[ -x ]` check passes).

# one row per item type: <prefix>:<open-section>:<detail-dir>:<flags>
# flags: C=countable (counters.json), P=plannable (plan keys)
# S (Slice) has no section/dir — plan-key-only type.
# When a new item type lands, add ONE row; bash vars below and
# hvlib_types.py both derive from this line.
HV_TYPE_REGISTRY="B:Bugs:bugs:CP F:Features:features:CP T:Tasks:tasks:P S:::P"

HV_ITEM_TYPES=""
HV_OPEN_SECTIONS=""
HV_COUNTABLE_TYPES=""
HV_PLANNABLE_TYPES=""
for _hv_row in $HV_TYPE_REGISTRY; do
  IFS=: read -r _hv_prefix _hv_section _hv_dir _hv_flags <<<"$_hv_row"
  if [ -n "$_hv_section" ]; then
    HV_ITEM_TYPES="${HV_ITEM_TYPES}${_hv_prefix}"
    HV_OPEN_SECTIONS="${HV_OPEN_SECTIONS:+${HV_OPEN_SECTIONS}|}${_hv_section}"
  fi
  case "$_hv_flags" in *C*) HV_COUNTABLE_TYPES="${HV_COUNTABLE_TYPES}${_hv_prefix}" ;; esac
  case "$_hv_flags" in *P*) HV_PLANNABLE_TYPES="${HV_PLANNABLE_TYPES}${_hv_prefix}" ;; esac
done
unset _hv_row _hv_prefix _hv_section _hv_dir _hv_flags

HV_MILESTONE_STATUSES="planned|active|shipped|archived"
HV_MILESTONE_PREFIX="M"
export HV_ITEM_TYPES HV_COUNTABLE_TYPES HV_PLANNABLE_TYPES HV_OPEN_SECTIONS HV_MILESTONE_STATUSES HV_MILESTONE_PREFIX
