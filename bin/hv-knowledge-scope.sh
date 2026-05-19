#!/usr/bin/env bash
# Sourceable library: resolve the knowledge scope ("umbrella" or a sub-repo
# name) for the umbrella-aware hv-knowledge-* / hv-glossary-* helpers (F21).
# Pure library — sourcing defines a function and runs nothing.
#
# hv_resolve_knowledge_scope <explicit-repo-flag>
#   $1 : value of an explicit --repo flag, or "" if none was given
#   Resolution order:
#     1. explicit flag value (non-empty)   -> that value verbatim
#     2. cwd inside a registered sub-repo   -> that sub-repo's name
#        (sibling hv-resolve-repo, exit 0)
#     3. otherwise                          -> "umbrella"
#   Prints the resolved scope to stdout. Never fails — umbrella is the
#   always-safe fallback, so single-repo projects always resolve to
#   "umbrella" and behave byte-identically to pre-F21.
hv_resolve_knowledge_scope() {
  local explicit="${1:-}"
  if [ -n "$explicit" ]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  local _bin auto
  _bin="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  # Run hv-resolve-repo from the original (pre-preamble-cd) cwd when available,
  # so that cwd auto-resolve works even after hv_self_locate has changed cwd
  # to the umbrella root (hv-preamble.sh sets HV_ORIG_PWD before cding).
  if auto="$(
    if [ -n "${HV_ORIG_PWD:-}" ]; then cd "$HV_ORIG_PWD" || exit 0; fi
    "$_bin/hv-resolve-repo" 2>/dev/null
  )" && [ -n "$auto" ]; then
    printf '%s\n' "$auto"
    return 0
  fi
  printf '%s\n' "umbrella"
  return 0
}

# hv_resolve_knowledge_path <scope> [tier]
#   Resolve a scope string to its KNOWLEDGE.md path (default) or, when the
#   second arg is the literal "tier", its tier-sidecar path. Wraps the
#   hvlib resolver ONCE, passing scope via argv (never string-interpolated
#   into Python source) so sub-repo names with shell/quote metacharacters
#   are safe. Prints the resolved path on stdout. On the resolver's
#   ValueError (sub-repo scope while umbrella off, or unregistered name),
#   prints `error: <message>` to stderr and returns 2 — the single
#   canonical exit code for a scope-resolution failure across every
#   knowledge/glossary helper (F21 #4a unification). Never interpolates.
hv_resolve_knowledge_path() {
  local _scope="${1:?hv_resolve_knowledge_path: scope required}"
  local _which="${2:-knowledge}"
  local _bin
  _bin="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  PYTHONPATH="$_bin${PYTHONPATH:+:$PYTHONPATH}" python3 - "$_scope" "$_which" <<'PYR'
import sys
from hvlib import resolve_knowledge_target, resolve_tier_sidecar
scope, which = sys.argv[1], sys.argv[2]
try:
    print(resolve_tier_sidecar(scope) if which == "tier" else resolve_knowledge_target(scope))
except ValueError as e:
    sys.stderr.write(f"error: {e}\n")
    sys.exit(2)
PYR
}
