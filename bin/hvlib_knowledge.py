"""Umbrella-aware KNOWLEDGE.md and tier-sidecar path resolution. Pure stdlib +
hvlib_repos. Re-exported by hvlib for backward compat.

resolve_knowledge_target() and resolve_tier_sidecar() are the single source of
truth for where KNOWLEDGE.md and knowledge-tier.json live — both for the
umbrella-level scope and for per-sub-repo scopes introduced in F21.
"""
import os

from hvlib_repos import load_repos


def _resolve_repo_dir(repo) -> "str | None":
    """Return the directory that should contain the knowledge files for `repo`.

    Returns None for the umbrella scope (no sub-directory needed).
    For a named sub-repo scope, validates umbrella mode is on and the name is
    registered, creates the directory on demand, and returns the path string.

    Raises ValueError with an actionable message on any validation failure.
    """
    # Treat None, "", and "umbrella" as the umbrella scope.
    if repo is None or repo == "" or repo == "umbrella":
        return None

    repos = load_repos()

    if not repos:
        raise ValueError(
            f"sub-repo scope '{repo}' requested but umbrella mode is off"
            " (no sub-repos registered); run /hv-init from the umbrella root"
        )

    if repo not in repos:
        raise ValueError(
            f"sub-repo '{repo}' not registered in .hv/repos.json;"
            f" registered: {sorted(repos)}"
        )

    d = os.path.join(".hv", "knowledge", repo)
    os.makedirs(d, exist_ok=True)
    return d


def resolve_knowledge_target(repo: str = "umbrella") -> str:
    """Resolve the KNOWLEDGE.md path for a given scope.

    repo == "umbrella" (default) -> ".hv/KNOWLEDGE.md"
    repo == "<name>"             -> ".hv/knowledge/<name>/KNOWLEDGE.md"

    For a sub-repo scope:
      - Umbrella mode MUST be on (load_repos() non-empty); raises ValueError
        if a sub-repo scope is requested while umbrella mode is off.
      - <name> MUST be a registered sub-repo (present in load_repos());
        raises ValueError naming the bad name and listing registered names.
      - The parent directory (.hv/knowledge/<name>/) is created on demand
        (os.makedirs(..., exist_ok=True)) so first write succeeds.

    Returns the path as a string (relative, ".hv/..." — callers run from
    the umbrella/project root, matching every other hv-knowledge-* helper).
    """
    d = _resolve_repo_dir(repo)
    if d is None:
        return ".hv/KNOWLEDGE.md"
    return os.path.join(d, "KNOWLEDGE.md")


def resolve_tier_sidecar(repo: str = "umbrella") -> str:
    """Resolve the F03 tier-sidecar path parallel to resolve_knowledge_target.

    repo == "umbrella" -> ".hv/knowledge-tier.json"
    repo == "<name>"   -> ".hv/knowledge/<name>/knowledge-tier.json"

    Same validation + lazy-mkdir contract as resolve_knowledge_target.
    """
    d = _resolve_repo_dir(repo)
    if d is None:
        return ".hv/knowledge-tier.json"
    return os.path.join(d, "knowledge-tier.json")
