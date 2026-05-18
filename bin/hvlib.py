"""Shared utilities for hv-* helpers. Imported by python3 heredocs in bin/.

Loaded via PYTHONPATH = $(dirname "$0") set by the bash wrapper. Do NOT import
this from outside bin/. The functions here are stdlib-only and side-effect-free
(except write_text_atomic / dump_json_atomic / update_json, which write).
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Re-exports — keep `from hvlib import X` working for callers.
from hvlib_io import (
    load_json, load_config, read_or_empty, write_text_atomic, dump_json_atomic, update_json,
)
from hvlib_version import (
    parse_toml_version, infer_version_kind, get_version_or_die, read_version,
    detect_version_kind, write_version_for_kind, write_version,
    VERSION_KIND_REGISTRY,
)
from hvlib_section import (
    BACKLOG_FILE,
    find_section, section, print_matching_sections,
    replace_section, append_to_section, iter_open_sections,
    iter_topics, load_backlog_corpus, upsert_block,
)
from hvlib_bullet import (
    _TODO_FIELD_NAMES, _DONE_LINE_RE,
    find_item_ids, find_origin_bullet, parse_todo_fields,
    open_bullet_re, parse_open_bullet, format_done_line, parse_done_line,
    find_bullet_in_content, find_open_bullet, strip_bullet_from_content,
)
from hvlib_frontmatter import parse_frontmatter, update_frontmatter_field


def parse_repos_csv(value: str) -> list[str]:
    """Split a Repos: field value (comma-separated, optional spaces) into a
    clean list of sub-repo names. Empty/whitespace-only inputs return [].
    Duplicates are preserved in input order — caller dedupes if needed.

    Example: parse_repos_csv("web, api") => ["web", "api"]
    Example: parse_repos_csv("web,api,web") => ["web", "api", "web"]
    Example: parse_repos_csv("") => []
    """
    return [s.strip() for s in value.split(",") if s.strip()]


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


def git_mtime(path) -> "str | None":
    """Return YYYY-MM-DD of the last git commit touching `path`, or None.
    Returns None if git fails, the path is untracked, or the result is empty.
    Callers that need a date object should parse via datetime.date.fromisoformat.
    """
    result = subprocess.run(
        ["git", "log", "-1", "--format=%cs", "--", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    out = result.stdout.strip()
    return out if out else None


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


def parse_term_entry(body: str) -> dict:
    """Extract definition, aliases, nots from a CONTEXT.md term section body.

    Body is the text after `## <term>` up to the next `## ` heading (the same
    string `iter_topics` yields). Recognized markers in the body:

      - `**Aliases:** a, b, c`  (or `_none_` for empty list)
      - `**Not:** x, y, z`      (optional; absent → empty list)
      - `<!-- YYYY-MM-DD -->`   (date stamp; ignored here, parsed by callers)

    Everything before the first marker line is the definition (whitespace-
    stripped). The HTML date comment is treated as a marker (definition ends
    above it) but its value is not parsed by this helper.

    Returns: {"definition": str, "aliases": list[str], "nots": list[str]}
    """
    aliases: list[str] = []
    nots: list[str] = []
    def_lines: list[str] = []
    seen_marker = False
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("**Aliases:**"):
            value = stripped[len("**Aliases:**"):].strip()
            if value and value != "_none_":
                aliases = [a.strip() for a in value.split(",") if a.strip()]
            seen_marker = True
            continue
        if stripped.startswith("**Not:**"):
            value = stripped[len("**Not:**"):].strip()
            if value:
                nots = [n.strip() for n in value.split(",") if n.strip()]
            seen_marker = True
            continue
        if stripped.startswith("<!--") and stripped.endswith("-->"):
            seen_marker = True
            continue
        if not seen_marker:
            def_lines.append(line)
    definition = "\n".join(def_lines).strip()
    return {"definition": definition, "aliases": aliases, "nots": nots}


def first_sentence(text: str, max_chars: int = 160) -> str:
    """Return the leading sentence of `text` (up to the first `.`, `!`, or `?`
    followed by whitespace or EOL). If the result exceeds `max_chars`, hard-cut
    at the last word boundary <= max_chars and append `…`. Never raises;
    returns `""` for empty input.

    Used by the CLAUDE.md `## Project Context` block renderer to derive a
    one-line gloss from a term's full definition paragraph.
    """
    if not text:
        return ""
    text = text.strip()
    m = re.search(r"[.!?](?:\s|$)", text)
    sentence = text[:m.end()].rstrip() if m else text
    if len(sentence) <= max_chars:
        return sentence
    cut = sentence[:max_chars].rsplit(" ", 1)[0]
    return cut.rstrip(",;") + "…"


def resolve_plugin_root() -> tuple[str, str]:
    """Locate the installed hv-skills plugin root. Returns (root, kind) where
    `kind` is one of "override", "plugin", "stow", or "none" and `root` is the
    absolute path (or "" when kind == "none").

    Resolution order, matching the historical shell resolvers in
    bin/hv-update-check and bin/hv-version-check (which had drifted apart —
    B12 was caused by the cache fallback being added to one but not the
    other; this function consolidates the walk):

      1. HV_INSTALL_ROOT env var (existing dir)         → ("override", root)
         Note: this branch does NOT require .claude-plugin/plugin.json — it
         matches hv-update-check's looser legacy behavior, used for tests
         and airgapped overrides.
      2. CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json  → ("plugin",   root)
      3. ~/.claude/plugins/<marketplace>/hv-skills/.claude-plugin/plugin.json
         and ~/.claude/plugins/hv-skills/.claude-plugin/plugin.json
                                                        → ("plugin",   root)
      4. ~/.claude/plugins/cache/hv-skills/hv-skills/<version>/, newest by
         `pkg_resources`-style version sort, with plugin.json present
                                                        → ("plugin",   root)
      5. ~/.agents/skills/hv-skills/.claude-plugin/plugin.json
         and ~/.agents/skills/.claude-plugin/plugin.json
                                                        → ("stow",     root)
      6. otherwise                                      → ("",         "none")

    Never raises on missing dirs.
    """
    import glob

    # 1. HV_INSTALL_ROOT override — matches hv-update-check's loose check
    #    (just dir-exists, NOT plugin.json-required).
    override = os.environ.get("HV_INSTALL_ROOT", "")
    if override and os.path.isdir(override):
        return (override, "override")

    # 2. CLAUDE_PLUGIN_ROOT — only when the manifest's `name` is hv-skills.
    #    Claude Code points CLAUDE_PLUGIN_ROOT at whatever plugin owns the
    #    current invocation; a session driven by another plugin (e.g.
    #    context-mode) must not be mistaken for an hv-skills install root.
    cpr = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if cpr:
        mf = os.path.join(cpr, ".claude-plugin", "plugin.json")
        if os.path.isfile(mf) and load_json(mf, {}).get("name") == "hv-skills":
            return (cpr, "plugin")

    home = os.path.expanduser("~")

    # 3. Glob and literal under ~/.claude/plugins/.
    candidates = sorted(glob.glob(os.path.join(home, ".claude/plugins/*/hv-skills")))
    candidates.append(os.path.join(home, ".claude/plugins/hv-skills"))
    for cand in candidates:
        if os.path.isfile(os.path.join(cand, ".claude-plugin", "plugin.json")):
            return (cand, "plugin")

    # 4. Plugin cache: ~/.claude/plugins/cache/hv-skills/hv-skills/<version>/.
    #    Sort versions descending (sort -V semantics) and pick the newest with
    #    .claude-plugin/plugin.json. Use a tuple-of-ints sort over numeric
    #    runs in the version string — stdlib-only, matches sort -V well
    #    enough for typical semver-ish names.
    cache_root = os.path.join(home, ".claude/plugins/cache/hv-skills/hv-skills")
    if os.path.isdir(cache_root):
        try:
            versions = [v for v in os.listdir(cache_root)
                        if os.path.isdir(os.path.join(cache_root, v))]
        except OSError:
            versions = []

        def _vkey(v: str):
            return tuple(int(p) for p in re.findall(r"\d+", v)) or (0,)

        versions.sort(key=_vkey, reverse=True)
        for v in versions:
            cand = os.path.join(cache_root, v)
            if os.path.isfile(os.path.join(cand, ".claude-plugin", "plugin.json")):
                return (cand, "plugin")

    # 5. ~/.agents/skills.
    for cand in (
        os.path.join(home, ".agents/skills/hv-skills"),
        os.path.join(home, ".agents/skills"),
    ):
        if os.path.isfile(os.path.join(cand, ".claude-plugin", "plugin.json")):
            return (cand, "stow")

    return ("", "none")


def iter_map_entries(map_dir):
    """Yield (subsystem, frontmatter_dict, body, path) for each *.md file
    in `map_dir` whose frontmatter has a `subsystem:` key. Files without
    valid frontmatter are skipped silently. Sorted by subsystem name.
    """
    p = Path(map_dir)
    if not p.is_dir():
        return
    entries = []
    for md in sorted(p.glob("*.md")):
        try:
            text = md.read_text()
        except OSError:
            continue
        fm, body = parse_frontmatter(text)
        name = fm.get("subsystem")
        if not name:
            continue
        entries.append((name, fm, body, md))
    entries.sort(key=lambda e: e[0])
    for entry in entries:
        yield entry


# ── TODO mutation helpers (extracted from bin/hv-rm) ──────────────────────────


def infer_type_from_section(sec_name: str) -> str:
    """Map a TODO section name to an item-type label.
    Bugs→bug, Features→feature, Tasks→task, Completed→completed,
    anything else→unknown."""
    mapping = {"Bugs": "bug", "Features": "feature", "Tasks": "task", "Completed": "completed"}
    return mapping.get(sec_name, "unknown")


def infer_type_from_id(iid: str, prefix_to_section: dict[str, str]) -> str:
    """Map an ID's first letter to an item-type label via the supplied
    prefix-to-section mapping (e.g. {'B': 'Bugs', 'F': 'Features', 'T': 'Tasks'}).
    Returns 'unknown' if the prefix isn't in the map."""
    prefix = iid[0].upper() if iid else ""
    sec = prefix_to_section.get(prefix)
    if sec is None:
        return "unknown"
    return infer_type_from_section(sec)


def detail_dir_for_id(iid: str) -> str:
    """Map an ID's prefix to its detail directory under .hv/.
    B→bugs, F→features, T→tasks, otherwise empty string."""
    prefix = iid[0].upper() if iid else ""
    mapping = {"B": "bugs", "F": "features", "T": "tasks"}
    return mapping.get(prefix, "")


def parse_related_ids(related_val: str) -> list[str]:
    """Extract bracket IDs (e.g. F02, B05) from a Related: field value."""
    return re.findall(r"\[([A-Z]\d+)\]", related_val)


def remove_id_from_related_field(line: str, iid: str) -> str:
    """Strip `[iid]` from the Related: field of `line`. If Related becomes
    empty, drop the entire ` Related: ...` segment from the line.
    Uses parse_todo_fields (already in hvlib)."""
    fields = parse_todo_fields(line)
    related_val = fields.get("related", "")
    if not related_val:
        return line

    ids_in_related = parse_related_ids(related_val)
    if iid not in ids_in_related:
        return line

    # Remove the ID from the list.
    new_ids = [x for x in ids_in_related if x != iid]

    _related_end = "|".join(n for n in _TODO_FIELD_NAMES if n != "Related")
    if not new_ids:
        # Drop the entire Related: segment.
        # Match " Related: <value>" where <value> ends at the next field or EOL.
        pat = re.compile(
            rf"\s+Related:\s+.+?(?=\s+(?:{_related_end}):|$)",
        )
        return pat.sub("", line).rstrip()
    else:
        # Rebuild Related value preserving spacing: "[A01], [B02]" style.
        new_val = ", ".join(f"[{x}]" for x in new_ids)
        # Replace the bracketed IDs in the existing Related: value.
        # Strategy: replace the raw bracket-id sequence in the field substring.
        old_pat = re.compile(rf"(Related:\s+)(.+?)(?=\s+(?:{_related_end}):|$)")
        def repl(m):
            return m.group(1) + new_val
        return old_pat.sub(repl, line)


def collect_cross_refs(content: str, iid: str, sections: list[str]) -> list[tuple[str, str, str]]:
    """For each ## section in `sections`, find bullets that reference `iid`
    in their Related: field (excluding the iid's own origin bullet). Return
    (sec_name, old_line, new_line) tuples — new_line is old_line with
    `[iid]` stripped via remove_id_from_related_field."""
    hits = []
    origin_pat = re.compile(rf"^- (?:~~)?\*\*\[{re.escape(iid)}\]", re.MULTILINE)
    for sec_name in sections:
        span = find_section(content, sec_name)
        if span is None:
            continue
        body = content[span[0]:span[1]]
        for line in body.splitlines():
            line_s = line.strip()
            if not line_s.startswith("- "):
                continue
            # Skip the origin bullet itself.
            if origin_pat.match(line_s):
                continue
            fields = parse_todo_fields(line_s)
            related_ids = parse_related_ids(fields.get("related", ""))
            if iid in related_ids:
                new_line = remove_id_from_related_field(line_s, iid)
                hits.append((sec_name, line_s, new_line))
    return hits


def apply_cross_ref_strips(content: str, xrefs: list[tuple[str, str, str]]) -> str:
    """Apply cross-reference strips to `content`, replacing each old_line
    with new_line.rstrip() in one pass per (sec, old, new) tuple."""
    for _sec, old_line, new_line in xrefs:
        # Replace the old line with new line (exact match, once).
        escaped = re.escape(old_line)
        content = re.sub(rf"^{escaped}$", new_line.rstrip(), content, count=1, flags=re.MULTILINE)
    return content


# ── Glossary nested-bullet entries (## Glossary topic) ───────────────────────


def parse_glossary_entries(body: str) -> "tuple[list[dict], str]":
    """Parse nested-bullet term entries from a `## Glossary` topic body.

    Each entry shape:
        - **<term>** — <definition>
          - **Aliases:** X, Y
          - **Not:** Z              (optional)
          <!-- YYYY-MM-DD -->       (optional but conventional)

    Returns (entries, leading) where leading is the prose between the
    heading and the first entry (or the "(no terms yet)" placeholder).
    Entries preserve document order. Shared by hv-glossary-write (single)
    and hv-glossary-import (batch) so the on-disk format stays
    byte-identical across both paths.
    """
    lines = body.splitlines(keepends=True)
    i = 0
    leading: list[str] = []
    while i < len(lines):
        if re.match(r"^- \*\*", lines[i]):
            break
        leading.append(lines[i])
        i += 1
    entries: list[dict] = []
    while i < len(lines):
        m = re.match(r"^- \*\*([^*]+)\*\*\s*(?:—\s*(.*))?\s*$", lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1).strip()
        first_line_rest = (m.group(2) or "").rstrip()
        def_parts: list[str] = []
        if first_line_rest:
            def_parts.append(first_line_rest)
        aliases: list[str] = []
        nots: list[str] = []
        date: "str | None" = None
        i += 1
        while i < len(lines):
            sub = lines[i]
            if re.match(r"^- \*\*", sub):
                break
            stripped = sub.strip()
            if not stripped:
                i += 1
                continue
            m_al = re.match(r"^- \*\*Aliases:\*\*\s*(.*)$", stripped)
            if m_al:
                value = m_al.group(1).strip()
                if value and value != "_none_":
                    aliases = [a.strip() for a in value.split(",") if a.strip()]
                i += 1
                continue
            m_no = re.match(r"^- \*\*Not:\*\*\s*(.*)$", stripped)
            if m_no:
                value = m_no.group(1).strip()
                if value:
                    nots = [n.strip() for n in value.split(",") if n.strip()]
                i += 1
                continue
            m_dt = re.match(r"^<!--\s*(\d{4}-\d{2}-\d{2})\s*-->\s*$", stripped)
            if m_dt:
                date = m_dt.group(1)
                i += 1
                continue
            def_parts.append(stripped)
            i += 1
        entries.append({
            "name": name,
            "definition": " ".join(def_parts).strip(),
            "aliases": aliases,
            "nots": nots,
            "date": date,
        })
    return entries, "".join(leading)


def build_glossary_entry(e: dict, today: str) -> str:
    """Render one entry dict to its nested-bullet markdown form.

    Mirror of parse_glossary_entries — fields in, markdown out. Uses
    `e['date']` when set, else `today`. Both writers feed the same `today`
    string so renders are deterministic across the batch + single paths.
    """
    lines = [f"- **{e['name']}** — {e['definition']}"]
    aliases_value = ", ".join(e["aliases"]) if e["aliases"] else "_none_"
    lines.append(f"  - **Aliases:** {aliases_value}")
    if e["nots"]:
        lines.append(f"  - **Not:** {', '.join(e['nots'])}")
    lines.append(f"  <!-- {e['date'] or today} -->")
    return "\n".join(lines)


def split_csv_list(s: str) -> "list[str]":
    """Split a comma-separated string into stripped non-empty tokens.
    Shared CSV-cell parser for Glossary alias/not fields."""
    return [x.strip() for x in s.split(",") if x.strip()]
