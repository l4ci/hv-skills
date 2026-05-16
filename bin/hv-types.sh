# shellcheck shell=bash
# Single source of truth for the item-type regex character class.
# Sourced — not executed — by helpers that need to scan BACKLOG.md / ARCHIVE.md
# for backlog item IDs (B/F/T) and surface them in regex.
#
# When a 5th item type lands, edit ONE line below; every consumer picks it up
# via the exported env vars.
#
# Usage from a sibling helper:
#   . "$(dirname "$0")/hv-types.sh"
#   # bash regex:  use "[$HV_ITEM_TYPES]"
#   # python:      os.environ["HV_ITEM_TYPES"]   (re-emit as f"[{cls}]")
#
# HV_ITEM_TYPES        — backlog items only: Bugs / Features / Tasks.
#                        Used by hv-backlog, hv-summary, hv-ship-body,
#                        hv-review-scope, hv-todo-by-milestone.
# HV_OPEN_SECTIONS     — canonical "## <name>" headings under which open
#                        backlog items live in BACKLOG.md. Used by
#                        hvlib.iter_open_sections; consumers iterate this set
#                        rather than re-deriving ("Bugs", "Features", "Tasks")
#                        inline.
# HV_MILESTONE_STATUSES — pipe-separated milestone status enum.
#                        Used by hv-vision-status (validation) and
#                        hv-vision-index (drift heal regex).
# HV_MILESTONE_PREFIX  — single-letter prefix for milestone IDs (current "M").
#                        Used by hvlib.parse_milestones, which extracts every
#                        `<prefix>\d+` ID from arbitrary text (Milestone: field,
#                        frontmatter depends:, etc.).
#
# HV_COUNTABLE_TYPES   — types tracked in counters.json since_refactor (B,F).
#                        Used by: hv-complete (only B/F resolutions count).
# HV_PLANNABLE_TYPES   — types that can carry a milestone plan (B,F,T,S=Slice).
#                        Used by: hv-plan-add (validates plan-key format).
#
# Naming note: this file is "hv-types.sh" (not "_hv-types.sh") so that
# `cp hv-* .hv/bin/` in /hv-init Step 2 picks it up. hv-preflight discovers
# helpers via a `hv-*` glob and skips itself; this file is verified by the
# same glob (it's a sourced lib, but `/hv-init` chmods it +x alongside the
# executables, so the `[ -x ]` check passes).
HV_ITEM_TYPES="BFT"
HV_COUNTABLE_TYPES="BF"
HV_PLANNABLE_TYPES="BFTS"
HV_OPEN_SECTIONS="Bugs|Features|Tasks"
HV_MILESTONE_STATUSES="planned|active|shipped|archived"
HV_MILESTONE_PREFIX="M"
export HV_ITEM_TYPES HV_COUNTABLE_TYPES HV_PLANNABLE_TYPES HV_OPEN_SECTIONS HV_MILESTONE_STATUSES HV_MILESTONE_PREFIX
