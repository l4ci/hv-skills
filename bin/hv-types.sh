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
# HV_ITEM_TYPES   — backlog items only: Bugs / Features / Tasks.
#                   Used by hv-backlog, hv-summary, hv-ship-body,
#                   hv-review-scope, hv-todo-by-milestone.
# HV_ALL_PREFIXES — everything that owns an ID counter (B/F/T plus
#                   Milestones). Use when you want to scan ALL prefixes.
#
# Deliberately distinct from these helper-local classes (left untouched):
#   - hv-refactor-age uses [BF] — counts shipped countable work only.
#   - hv-plan-add uses [BFTS]    — accepts a Slice prefix not present in TODO.md.
#
# Naming note: this file is "hv-types.sh" (not "_hv-types.sh") so that
# `cp hv-* .hv/bin/` in /hv-init Step 2 picks it up. hv-preflight's
# discoverability check is an explicit allow-list, so it ignores this file
# regardless of name.
HV_ITEM_TYPES="BFT"
HV_ALL_PREFIXES="BFTM"
export HV_ITEM_TYPES HV_ALL_PREFIXES
