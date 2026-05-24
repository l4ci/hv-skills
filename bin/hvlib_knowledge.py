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


def compute_managed_block_inputs(key: str, scope: str = "") -> "tuple[list[str], Path]":
    """For a managed-block key + scope, return (topics, target_path).

    `key`:   "knowledge" or "decisions"
    `scope`: empty | "umbrella" | sub-repo name (only meaningful for "knowledge")

    Knowledge with umbrella scope (empty or "umbrella"):
      - source = resolve_knowledge_target("umbrella")
      - topics = iter_topics(source) names, doc order
      - target_path = Path("CLAUDE.md")
    Knowledge with sub-repo scope:
      - sources = umbrella + sub-repo KNOWLEDGE.md
      - topics = first-seen union across both, doc order per file
      - target_path = repos[scope] / "CLAUDE.md"
    Decisions (umbrella-only — caller is responsible for rejecting --repo
    before calling this function):
      - source = .hv/DECISIONS.md
      - topics = iter_topics(source) names, doc order
      - target_path = Path("CLAUDE.md")

    Raises ValueError on unknown key, on scope mismatch (sub-repo name not
    in .hv/repos.json), or on knowledge-target resolution failure. Missing
    source files are NOT an error — they just yield an empty topics list.
    """
    from pathlib import Path

    from hvlib_repos import load_repos
    from hvlib_section import iter_topics

    if key == "knowledge":
        if not scope or scope == "umbrella":
            source = Path(resolve_knowledge_target("umbrella"))
            topics: list[str] = []
            if source.exists():
                for name, _body in iter_topics(source.read_text()):
                    topics.append(name)
            return topics, Path("CLAUDE.md")
        # Sub-repo scope: union umbrella ∪ sub-repo, first-seen order.
        repos = load_repos()
        if scope not in repos:
            raise ValueError(f"sub-repo '{scope}' not registered in .hv/repos.json")
        umbrella_src = Path(resolve_knowledge_target("umbrella"))
        subrepo_src = Path(resolve_knowledge_target(scope))
        seen: set[str] = set()
        topics = []
        for src in (umbrella_src, subrepo_src):
            if src.exists():
                for name, _body in iter_topics(src.read_text()):
                    if name not in seen:
                        seen.add(name)
                        topics.append(name)
        return topics, Path(repos[scope]) / "CLAUDE.md"

    if key == "decisions":
        source = Path(".hv/DECISIONS.md")
        topics = []
        if source.exists():
            for name, _body in iter_topics(source.read_text()):
                topics.append(name)
        return topics, Path("CLAUDE.md")

    raise ValueError(f"unknown key '{key}' (known: knowledge, decisions)")
