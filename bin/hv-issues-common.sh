#!/usr/bin/env bash
# Shared preamble for bin/hv-issues-* helpers. Sourced, never exec'd.
# Callers must have set HERE and sourced hv-self-locate.sh first.
#
# Exports:
#   hv_issues_parse_repo_flag  — parses --repo from "$@"; sets REPO
#   hv_issues_resolve_repo_path — resolves REPO → REPO_PATH (empty when no --repo)
#   hv_issues_cd_to_repo        — cd into resolved sub-repo (for mutators that need cwd change)
#   hv_issues_detect_provider   — detects provider; sets PROVIDER

# ---------------------------------------------------------------------------
# hv_issues_parse_repo_flag
#
# Parse the --repo flag out of a helpers's arg list.  Sets REPO (empty when
# absent).  Remaining flags are left for the caller's own loop.
#
# Usage:  hv_issues_parse_repo_flag "$@"
#         # Then re-parse $@ in your own while loop for helper-specific flags.
# ---------------------------------------------------------------------------
hv_issues_parse_repo_flag() {
  REPO=""
  local _args=("$@")
  local _i=0
  while [[ $_i -lt ${#_args[@]} ]]; do
    local _arg="${_args[$_i]}"
    if [[ "$_arg" == "--repo" ]]; then
      _i=$((_i + 1))
      REPO="${_args[$_i]:?--repo requires a name argument}"
    fi
    _i=$((_i + 1))
  done
}

# ---------------------------------------------------------------------------
# hv_issues_resolve_repo_path
#
# Resolve REPO (set by hv_issues_parse_repo_flag) to an absolute path via
# hv-resolve-repo-path. Sets REPO_PATH (empty string when REPO is empty).
# Does NOT cd — callers use REPO_PATH themselves (e.g. in subshells or via
# _run_in_repo).
# ---------------------------------------------------------------------------
hv_issues_resolve_repo_path() {
  REPO_PATH=""
  if [ -n "$REPO" ]; then
    REPO_PATH="$("$HERE/hv-resolve-repo-path" "$REPO")"
  fi
}

# ---------------------------------------------------------------------------
# hv_issues_cd_to_repo
#
# cd into the sub-repo when --repo was given. Used by mutator helpers that
# need the cwd to be inside the sub-repo (e.g. for git rev-parse).
# No-op when REPO is empty.
# ---------------------------------------------------------------------------
hv_issues_cd_to_repo() {
  if [ -n "$REPO" ]; then
    cd "$("$HERE/hv-resolve-repo-path" "$REPO")"
  fi
}

# ---------------------------------------------------------------------------
# hv_issues_detect_provider
#
# Detect the upstream provider by delegating to hv-issues-provider.
# Sets PROVIDER ("github", "gitlab", or "unknown").
# Passes --repo when REPO is set (preserves current helper behavior).
# ---------------------------------------------------------------------------
hv_issues_detect_provider() {
  PROVIDER="$("$HERE/hv-issues-provider" ${REPO:+--repo "$REPO"})"
}

# ---------------------------------------------------------------------------
# hv_issues_resolve_path_cached
#
# Cached, per-entry-friendly variant of hv_issues_resolve_repo_path. Resolves
# a sub-repo name to an absolute path via hv-resolve-repo-path, caching the
# result in HV_ISSUES_REPO_CACHE (associative array). Empty/"null" repo names
# emit an empty string. Resolution failure is swallowed (matches the
# documented "drop entries whose state cannot be resolved" contract of
# /hv-issues-imported --open-only); callers downstream treat empty paths as
# "use current cwd".
#
# Usage:
#   hv_issues_init_path_cache
#   path="$(hv_issues_resolve_path_cached "$repo_name")"
#
# Callers MUST call hv_issues_init_path_cache once before any lookup. The
# init is a separate call so the function itself can be -e safe (declare in
# a function body silently fails when the variable already exists).
# ---------------------------------------------------------------------------
hv_issues_init_path_cache() {
  declare -gA HV_ISSUES_REPO_CACHE=()
}

hv_issues_resolve_path_cached() {
  local _repo="${1:-}"
  if [ -z "$_repo" ] || [ "$_repo" = "null" ]; then
    printf ''
    return 0
  fi
  if [ -n "${HV_ISSUES_REPO_CACHE[$_repo]+x}" ]; then
    printf '%s' "${HV_ISSUES_REPO_CACHE[$_repo]}"
    return 0
  fi
  local _path
  _path="$("$HERE/hv-resolve-repo-path" "$_repo" 2>/dev/null || true)"
  HV_ISSUES_REPO_CACHE[$_repo]="$_path"
  printf '%s' "$_path"
}
