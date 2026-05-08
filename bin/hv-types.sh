# shellcheck shell=bash
# Single source of truth for the item-type regex character class.
# Sourced — not executed — by helpers that need to scan TODO.md / ARCHIVE.md
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
#                        backlog items live in TODO.md. Used by
#                        hvlib.iter_open_sections; consumers iterate this set
#                        rather than re-deriving ("Bugs", "Features", "Tasks")
#                        inline.
# HV_MILESTONE_STATUSES — pipe-separated milestone status enum.
#                        Used by hv-vision-status (validation) and
#                        hv-vision-index (drift heal regex).
#
# Deliberately distinct from these helper-local classes (left untouched):
#   - hv-complete keys on [BF] when bumping counters.json#since_refactor —
#     only countable work types pressure the next refactor cycle.
#   - hv-plan-add uses [BFTS] — accepts a Slice prefix not present in TODO.md.
#
# Naming note: this file is "hv-types.sh" (not "_hv-types.sh") so that
# `cp hv-* .hv/bin/` in /hv-init Step 2 picks it up. hv-preflight discovers
# helpers via a `hv-*` glob and skips itself; this file is verified by the
# same glob (it's a sourced lib, but `/hv-init` chmods it +x alongside the
# executables, so the `[ -x ]` check passes).
HV_ITEM_TYPES="BFT"
HV_OPEN_SECTIONS="Bugs|Features|Tasks"
HV_MILESTONE_STATUSES="planned|active|shipped|archived"
export HV_ITEM_TYPES HV_OPEN_SECTIONS HV_MILESTONE_STATUSES
