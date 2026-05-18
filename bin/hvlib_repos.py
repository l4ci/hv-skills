"""Sub-repo registry + milestone status utilities. Pure stdlib +
hvlib_io. Re-exported by hvlib for backward compat.

Milestone helpers fold into this module per the plan (registry-shaped
siblings): parse_milestones and update_milestone_status_line are tiny
and live next to the umbrella sub-repo loaders that share the same
metadata-registry shape.
"""
import os
import re

from hvlib_io import load_json


def parse_repos_csv(value: str) -> list[str]:
    """Split a Repos: field value (comma-separated, optional spaces) into a
    clean list of sub-repo names. Empty/whitespace-only inputs return [].
    Duplicates are preserved in input order — caller dedupes if needed.

    Example: parse_repos_csv("web, api") => ["web", "api"]
    Example: parse_repos_csv("web,api,web") => ["web", "api", "web"]
    Example: parse_repos_csv("") => []
    """
    return [s.strip() for s in value.split(",") if s.strip()]


def load_repos(repos_path=".hv/repos.json") -> dict[str, str]:
    """Load the umbrella sub-repo registry. Return a dict mapping each
    registered name to its resolved absolute path. Empty dict if the file
    is missing, unreadable, or has no entries.

    `path` values in repos.json are stored relative to the umbrella root;
    this helper resolves them via os.path.realpath against the cwd from
    which the helper is called. Callers that may run from a different cwd
    should resolve paths themselves and pass the absolute base.

    Never raises — returns {} on any error.
    """
    data = load_json(repos_path, {"repos": []})
    out: dict[str, str] = {}
    for entry in data.get("repos", []) or []:
        name = entry.get("name", "")
        rel = entry.get("path", "")
        if name and rel:
            out[name] = os.path.realpath(rel)
    return out


def validate_repos(csv: str) -> tuple[list[str], list[str], dict[str, str]]:
    """Parse a Repos: CSV and validate every name against `.hv/repos.json`.
    Returns (names, missing, repos) where:
      - names    is the parsed list (may be empty if csv is whitespace-only)
      - missing  is the subset of names not registered in repos.json
      - repos    is the registry dict {name: abs-path} (empty if names is empty)

    Side-effect-free — caller decides how to surface errors. Typical usage:

        names, missing, repos = validate_repos(csv)
        if not names: ...   # csv was empty
        if missing: ...     # one or more names unregistered
        # else: proceed with names + repos[name] for paths
    """
    names = parse_repos_csv(csv)
    repos = load_repos() if names else {}
    missing = [n for n in names if n not in repos]
    return names, missing, repos


def active_items(entry: dict) -> list[str]:
    """Normalize entry["items"] to a list of strings.
    Handles: list already → as-is; str (CSV) → split/strip; None/missing → [].
    Consolidates isinstance(items_raw, list) branching in hv-rm / hv-summary.
    """
    raw = entry.get("items")
    if isinstance(raw, list):
        return list(raw)
    if isinstance(raw, str):
        return [s for s in (s.strip() for s in raw.split(",")) if s]
    return []


def parse_milestones(text: str) -> list[str]:
    """Extract every milestone ID (e.g. M01, M03) from arbitrary text.

    Reads the prefix from the HV_MILESTONE_PREFIX env var (default 'M'),
    which `bin/hv-types.sh` exports. Returns IDs in document order with
    duplicates preserved; callers dedupe if needed.

    Example: parse_milestones("M01, M03")        => ["M01", "M03"]
    Example: parse_milestones("Milestone: M02")  => ["M02"]
    Example: parse_milestones("")                => []
    """
    prefix = os.environ.get("HV_MILESTONE_PREFIX", "M")
    return re.findall(rf"{re.escape(prefix)}\d+", text)


def update_milestone_status_line(content: str, mid: str, new_status: str) -> str:
    """Update the **Status:** line for milestone `mid` in `content` (typically
    the body of .hv/MILESTONES.md) to `new_status`. Returns the updated text;
    if the milestone's section or status line isn't present, returns `content`
    unchanged.

    The regex matches the canonical milestone block shape:
        ### MID — Title
        \\n
        **Status:** <one of HV_MILESTONE_STATUSES>
    Only the FIRST occurrence is replaced (count=1); the heading line and
    surrounding whitespace are preserved.

    `new_status` is not validated here — callers (hv-vision-status) validate
    against HV_MILESTONE_STATUSES before invoking this helper.
    """
    statuses = os.environ.get("HV_MILESTONE_STATUSES", "planned|active|shipped|archived")
    pattern = re.compile(
        rf"(### {re.escape(mid)} — [^\n]+\n\n\*\*Status:\*\* )(?:{statuses})",
        re.MULTILINE,
    )
    return pattern.sub(rf"\g<1>{new_status}", content, count=1)
