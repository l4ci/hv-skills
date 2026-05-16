#!/usr/bin/env bash
# Shared --repo flag helpers for bin/hv-pr and bin/hv-merge. Sourced, never exec'd.
# Callers must have set BIN_DIR before sourcing. set -euo pipefail must be active.
#
# Exports:
#   hv_repo_flag_parse   — sets REPO from "$@" when --repo is first arg (else empty)
#   hv_repo_flag_prepare — runs guard + resolve + cd + worktree-clear bifurcation

# ---------------------------------------------------------------------------
# hv_repo_flag_parse
#
# Inspect "$@" for a leading --repo <name> pair. Sets REPO to the name when
# present, empty string when absent. Does NOT shift the caller's positional
# params — caller must `shift 2` itself when REPO is non-empty.
#
# Usage:  hv_repo_flag_parse "$@"
#         [ -n "$REPO" ] && shift 2
# ---------------------------------------------------------------------------
hv_repo_flag_parse() {
  REPO=""
  if [ "${1:-}" = "--repo" ]; then
    REPO="${2:?--repo requires a name argument}"
  fi
}

# ---------------------------------------------------------------------------
# hv_repo_flag_prepare
#
# Run the full umbrella-mode preparation: guard, resolve, cd, worktree-clear.
#
# Arguments:
#   $1  BIN_DIR     — absolute path to the directory containing hv-* helpers
#   $2  CALLER_NAME — name passed to hv-require-git-context (e.g. "hv-pr")
#   $3  BRANCH      — branch name forwarded to hv-worktree-clear
#
# Reads:  REPO (set by hv_repo_flag_parse or by the caller directly)
# Sets:   nothing (side-effects only: cd, helper invocations)
# ---------------------------------------------------------------------------
hv_repo_flag_prepare() {
  local _bin_dir="$1"
  local _caller="$2"
  local _branch="$3"

  if [ -z "$REPO" ]; then
    "$_bin_dir/hv-require-git-context" "$_caller" --repo-flag-supported
    "$_bin_dir/hv-worktree-clear" "$_branch"
  else
    REPO_PATH="$("$_bin_dir/hv-resolve-repo-path" "$REPO")"
    cd "$REPO_PATH"
    "$_bin_dir/hv-worktree-clear" --repo "$REPO" "$_branch"
  fi
}
