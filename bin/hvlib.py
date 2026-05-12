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

# Canonical filename for the typed-item backlog (bugs / features / tasks).
BACKLOG_FILE = "BACKLOG.md"


def find_section(content: str, name: str) -> tuple[int, int] | None:
    """Locate the body of ## <name> in `content`. Return (start, end) byte
    offsets — both into `content`, body excludes the heading line itself,
    end is the start of the next ## heading or len(content) if none.
    Returns None if the heading is missing.

    Note: the body slice `content[start:end]` may include leading and trailing
    whitespace; callers should `.strip()` if they care about exact content.

    Warning: if a body line begins with `## ` at column 0 (e.g. a literal
    `## Foo` inside a code fence or quoted block), the section will be
    truncated there. Do not put column-0 `## ` lines in section bodies.
    """
    m = re.search(rf"^## {re.escape(name)}\s*$", content, re.MULTILINE)
    if not m:
        return None
    start = m.end()
    nxt = re.search(r"^## ", content[start:], re.MULTILINE)
    end = start + nxt.start() if nxt else len(content)
    return (start, end)


def section(content: str, name: str) -> str:
    """Return the body of ## <name>, or '' if missing."""
    span = find_section(content, name)
    return content[span[0]:span[1]] if span else ""


def print_matching_sections(content: str, wanted: set[str], out=None) -> None:
    """Print each `## Topic` section whose (case-insensitive) title is in
    `wanted`, in document order. Sections are separated by a blank line.
    Bodies are rstripped before printing. `out` defaults to sys.stdout.
    """
    if out is None:
        out = sys.stdout
    first = True
    for name, body in iter_topics(content):
        if name.lower() in wanted:
            if not first:
                print(file=out)
            print(f"## {name}", file=out)
            print(body.rstrip(), file=out)
            first = False


def replace_section(content: str, name: str, new_body: str) -> str:
    """Replace the body of `## <name>` in `content` with `new_body`. Preserves
    the heading line itself and surrounding whitespace. If the section is
    missing, appends a new `## <name>` section at end (with a blank-line
    separator). `new_body` should NOT include the heading; it's the content
    that goes after it.

    Designed for managed sections like `## Active milestones` in MILESTONES.md.
    Returns the updated text.
    """
    span = find_section(content, name)
    if span is None:
        sep = "" if content.endswith("\n\n") else ("\n" if content.endswith("\n") else "\n\n")
        return content.rstrip("\n") + "\n\n## " + name + "\n" + new_body
    start, end = span
    return content[:start] + new_body + content[end:]


def append_to_section(content: str, name: str, addition: str) -> str:
    """Append `addition` to the body of `## <name>`, splicing it just before
    the next `## ` heading (or at EOF if last). If the section is missing,
    appends `## <name>\\n\\n<addition>` at end. Returns the updated text.

    The caller controls layout via `addition` — typically `"\\n- new bullet\\n"`
    or `"\\n### new milestone — Title\\n\\n**Status:** planned\\n…\\n"`.
    """
    span = find_section(content, name)
    if span is None:
        sep = "" if content.endswith("\n") else "\n"
        return content.rstrip("\n") + "\n\n## " + name + "\n" + addition
    start, end = span
    body = content[start:end]
    # Splice addition just before the next ## heading. If the body ends
    # without a newline, ensure one is added; let `addition` control the
    # rest of the layout.
    if body.endswith("\n"):
        return content[:start] + body + addition + content[end:]
    else:
        return content[:start] + body + "\n" + addition + content[end:]


def iter_open_sections(content: str):
    """Yield (section_name, body) pairs for each open-work section in
    `content`, in the order defined by HV_OPEN_SECTIONS env var (default
    "Bugs|Features|Tasks"). Sections that don't exist are skipped silently.

    Body is the same string `find_section`/`section` would return — the
    contents between the `## <name>` heading and the next `## ` heading or
    EOF, with leading and trailing whitespace preserved.

    Use this instead of hardcoding ("Bugs", "Features", "Tasks") in helpers
    that scan the open backlog.
    """
    names = os.environ.get("HV_OPEN_SECTIONS", "Bugs|Features|Tasks").split("|")
    for name in names:
        span = find_section(content, name)
        if span is not None:
            yield name, content[span[0]:span[1]]


def find_item_ids(text: str, prefixes: str = "BFT") -> list[str]:
    """Find all bracketed IDs like [B07], [F12], [T03] in `text`.
    `prefixes` is typically os.environ.get("HV_ITEM_TYPES", "BFT") at the caller.
    Returns a deduplicated list of full IDs (e.g. ["B07", "F12"]) in order of appearance.
    """
    pat = re.compile(r"\[([" + re.escape(prefixes) + r"])(\d{2,})\]")
    seen: dict[str, None] = {}
    for m in pat.finditer(text):
        iid = m.group(1) + m.group(2)
        seen[iid] = None
    return list(seen.keys())


def find_origin_bullet(corpus: str, iid: str) -> tuple[str, str | None] | None:
    """Find the origin bullet for `iid` in `corpus` (typically BACKLOG.md +
    ARCHIVE.md concatenated). The origin bullet is the line that introduces
    the item (`- **[ID] ...`), not a `Related: [ID]` reference inside another
    bullet.

    Returns (cleaned_line, title) or None if no origin bullet exists.
    `cleaned_line` has the leading `- `, any `~~strikethrough~~` wrapper,
    and any trailing ` Done YYYY-MM-DD [`hash`]` suffix removed.
    `title` is None if the cleaned line lacks the standard `[ID] [tag] Title.`
    pattern.
    """
    bullet = re.compile(
        rf"^- (?:~~)?\*\*\[{re.escape(iid)}\].*$",
        re.MULTILINE,
    )
    m = bullet.search(corpus)
    if not m:
        return None
    line = m.group(0).strip()
    if line.startswith("- "):
        line = line[2:]
    line = re.sub(r"\s*Done\s+\d{4}-\d{2}-\d{2}\s+\[`[^`]+`\]\s*$", "", line)
    strike = re.match(r"~~(.+?)~~$", line)
    if strike:
        line = strike.group(1)
    title_m = re.search(
        rf"\[{re.escape(iid)}\](?:\s+\[[^\]]+\])?\s+(?P<t>[^.\n]+)\.",
        line,
    )
    title = title_m.group("t").strip() if title_m else None
    return (line, title)


def parse_todo_fields(line: str) -> dict[str, str]:
    """Extract Detail/Related/Milestone/Repos/Subsystem/Captured fields from a TODO bullet line.

    Each field starts with `<Field>: ` and runs until the next field marker
    or end of line. Order-agnostic. Returns a dict with keys 'detail',
    'related', 'milestone', 'repos', 'subsystem', 'captured' — missing fields map to ''.

    Example: parse_todo_fields("- **[B01] [P1] Title.** Body. Detail: foo. Related: [F02]. Milestone: M01")
        => {"detail": "foo.", "related": "[F02].", "milestone": "M01", "repos": "", "subsystem": ""}
    Example: parse_todo_fields("- **[F01] [Major] Title.** D. Detail: x. Milestone: M02 Repos: web")
        => {"detail": "x.", "related": "", "milestone": "M02", "repos": "web", "subsystem": ""}
    Example: parse_todo_fields("- **[B07] [P1] Title.** D. Repos: web Subsystem: capture Captured: 2026-05-09")
        => {"detail": "", "related": "", "milestone": "", "repos": "web", "subsystem": "capture", "captured": "2026-05-09"}
    """
    fields = {"detail": "", "related": "", "milestone": "", "repos": "", "subsystem": "", "captured": ""}
    others = {
        "detail": ["Related", "Milestone", "Repos", "Subsystem", "Captured"],
        "related": ["Detail", "Milestone", "Repos", "Subsystem", "Captured"],
        "milestone": ["Detail", "Related", "Repos", "Subsystem", "Captured"],
        "repos": ["Detail", "Related", "Milestone", "Subsystem", "Captured"],
        "subsystem": ["Detail", "Related", "Milestone", "Repos", "Captured"],
        "captured": ["Detail", "Related", "Milestone", "Repos", "Subsystem"],
    }
    for key in fields:
        cap = key.capitalize()
        end_lookahead = "|".join(others[key])
        pat = re.compile(rf"\b{cap}:\s*(.+?)(?=\s+(?:{end_lookahead}):|$)")
        m = pat.search(line)
        if m:
            fields[key] = m.group(1).strip()
    return fields


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


def load_json(path, default):
    """Read JSON from `path`. Return `default` if the file is missing or corrupt.
    Never raises. `path` may be a str or Path.
    """
    p = Path(path)
    if not p.exists():
        return default
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return default


def read_or_empty(path) -> str:
    """Read a file's text, or return '' if it doesn't exist.
    `path` may be a str or os.PathLike. Never raises on missing file.
    """
    try:
        return Path(path).read_text()
    except FileNotFoundError:
        return ""


def load_backlog_corpus(base_dir=".") -> str:
    """Return BACKLOG.md (or legacy TODO.md as a one-cycle fallback) + ARCHIVE.md
    concatenated from <base_dir>/.hv/.
    Used by ship-body, todo-field, and review-scope to look up an item ID
    across active and archived backlog in one pass.
    """
    base = Path(base_dir)
    hv = base / ".hv"
    backlog = hv / BACKLOG_FILE
    if backlog.exists():
        primary = read_or_empty(backlog)
    else:
        primary = read_or_empty(hv / "TODO.md")
    return primary + "\n" + read_or_empty(hv / "ARCHIVE.md")


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


def write_text_atomic(path, text: str) -> None:
    """Write `text` to `path` atomically (tmp + os.replace). Trailing
    newline is the caller's responsibility. `path` may be a str or Path.
    """
    p = Path(path)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, p)


def upsert_block(claude_path: Path, key: str, block: str, legacy_marker: str | None = None) -> str:
    """Write `block` into `claude_path`, replacing any existing
    <!-- hv-{key}-start -->...<!-- hv-{key}-end --> match (sub),
    appending if no match is found (append), or creating the file with
    just the block if it doesn't exist (create).

    When `legacy_marker` is provided, the lookup pattern also matches
    the legacy `hv:{legacy_marker}:start`/`hv:{legacy_marker}:end`
    delimiter shape, so callers can migrate older blocks to the
    canonical `hv-{key}-start`/`hv-{key}-end` form in-place.

    Returns 'created' | 'updated' | 'appended' so callers can print
    the same status string they did before.
    """
    if not claude_path.exists():
        write_text_atomic(claude_path, block + "\n")
        return "created"
    content = claude_path.read_text()
    if legacy_marker:
        pattern = re.compile(
            rf"<!-- hv(?:-{re.escape(key)}-start|:{re.escape(legacy_marker)}:start) -->"
            rf".*?"
            rf"<!-- hv(?:-{re.escape(key)}-end|:{re.escape(legacy_marker)}:end) -->",
            re.DOTALL,
        )
    else:
        pattern = re.compile(
            rf"<!-- hv-{re.escape(key)}-start -->.*?<!-- hv-{re.escape(key)}-end -->",
            re.DOTALL,
        )
    if pattern.search(content):
        write_text_atomic(claude_path, pattern.sub(block, content))
        return "updated"
    write_text_atomic(claude_path, content.rstrip() + "\n\n" + block + "\n")
    return "appended"


def dump_json_atomic(path, data) -> None:
    """Write `data` as pretty JSON to `path` atomically (tmp + os.replace).
    The tmp file is in the same directory as `path`. Trailing newline preserved.
    """
    p = Path(path)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, p)


def update_json(path, default, mutator) -> None:
    """Read JSON at `path` (with `default` fallback), pass it to mutator(),
    then atomically write the result. mutator may mutate in place and return None,
    or return a new object — both work.
    """
    data = load_json(path, default)
    result = mutator(data)
    dump_json_atomic(path, data if result is None else result)


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


def registered_repo_names(repos_path=".hv/repos.json") -> list[str]:
    """Return sorted list of registered sub-repo names from repos.json.
    Wraps load_repos; returns [] if the file is missing or empty.
    """
    return sorted(load_repos(repos_path).keys())


def parse_toml_version(text: str, sections: list[str]) -> str | None:
    """Find `version = "x.y.z"` inside one of the given [section] headings
    in `text` (TOML source). `sections` is checked in order; the first hit
    wins. Returns the version string or None if no section matches or no
    version field is present in any matching section.

    The section heading match is anchored at line start, allows leading
    whitespace, and tolerates trailing whitespace inside the brackets.
    The version regex is anchored at line start of the section body
    (after the heading, up to the next [heading] or EOF).

    Used by hv-release-detect-version (read path) and hv-release-bump-version
    (read path) to keep the regex/section-traversal logic identical.
    """
    for section in sections:
        pattern = re.compile(
            r"^\s*\[" + re.escape(section) + r"\s*\]\s*$",
            re.MULTILINE,
        )
        m = pattern.search(text)
        if not m:
            continue
        rest = text[m.end():]
        next_section = re.search(r"^\s*\[", rest, re.MULTILINE)
        block = rest[: next_section.start()] if next_section else rest
        v = re.search(r'^version\s*=\s*"([^"]*)"', block, re.MULTILINE)
        if v:
            return v.group(1)
    return None


def open_bullet_re() -> "re.Pattern":
    """Return a compiled regex matching an open TODO bullet line. The character
    class for the ID prefix is built from HV_ITEM_TYPES env (default "BFT"
    after stripping the M, since milestones don't appear as bullets in open
    sections). Captures four named groups:

        - id      e.g. "B07" (full id, no brackets)
        - tag     e.g. "P1" or "Major" (the bracketed tag after the id), or "" if absent
        - title   the human-readable title up to the closing `**`
        - rest    everything after the closing `**` (Detail/Related/Milestone/Repos blob)

    Anchored at line start; matches:
        - **[B07] [P1] Title.** Detail: ...
        - **[F12] Title.**
    Does NOT match strikethrough/done lines (those start with `- ~~**[`).
    """
    types = os.environ.get("HV_ITEM_TYPES", "BFT").replace("M", "")
    return re.compile(
        rf"^- \*\*\[(?P<id>[{types}]\d+)\](?:\s+\[(?P<tag>[^\]]+)\])?\s+(?P<title>[^*]+?)\*\*(?P<rest>.*)$",
        re.MULTILINE,
    )


def parse_open_bullet(line: str) -> dict | None:
    """Parse a single open bullet line. Returns a dict with id/tag/title/rest
    keys (matching open_bullet_re named groups), or None if the line isn't an
    open bullet. tag and rest default to "" when absent.
    """
    m = open_bullet_re().match(line.rstrip("\n"))
    if not m:
        return None
    return {
        "id": m.group("id"),
        "tag": (m.group("tag") or "").strip(),
        "title": m.group("title").strip().rstrip(".").strip(),
        "rest": (m.group("rest") or "").strip(),
    }


def format_done_line(open_line: str, date_str: str, hash_short: str) -> str:
    """Convert an open bullet line (starting with `- **[ID]...`) into the
    canonical Done line (`- ~~**[ID]...**~~ Done DATE [`hash`]`). The input
    must be an open bullet — the leading `- ` is preserved, the rest is
    wrapped in `~~...~~`, and the suffix is appended.

    No validation that `open_line` is well-formed; caller is responsible.
    """
    if not open_line.startswith("- "):
        raise ValueError("expected line starting with '- '")
    inner = open_line[2:].rstrip()
    return f"- ~~{inner}~~ Done {date_str} [`{hash_short}`]"


_DONE_LINE_RE = re.compile(
    r"^- ~~(?P<inner>.+?)~~ Done (?P<date>\d{4}-\d{2}-\d{2}) \[`(?P<hash>[^`]+)`\]\s*$"
)


def parse_done_line(line: str) -> dict | None:
    """Parse a Done line. Returns dict {id, inner, date, hash} or None.
    `inner` is the content between `~~ ... ~~` (the original bullet body
    without the leading `- ` and without the strikethrough wrapping).
    `id` is extracted from the leading `**[ID] ...` of `inner`; "" if absent.
    """
    m = _DONE_LINE_RE.match(line.rstrip("\n"))
    if not m:
        return None
    inner = m.group("inner")
    id_m = re.match(r"\*\*\[([A-Z]\d+)\]", inner)
    return {
        "id": id_m.group(1) if id_m else "",
        "inner": inner,
        "date": m.group("date"),
        "hash": m.group("hash"),
    }


def iter_topics(content: str):
    """Yield (name, body) pairs for each `## Topic` heading in `content`, in
    document order. `name` is the heading text with leading `## ` and trailing
    whitespace stripped. `body` is the text from after the heading line up to
    (but not including) the next `## ` heading or EOF — preserves leading
    and trailing whitespace.

    Use this instead of hand-rolling re.split / re.findall / re.match-per-line
    when scanning KNOWLEDGE.md, DECISIONS.md, or any other doc that uses ##
    headings as topic separators.

    See find_section for the same warning about column-0 `## ` lines inside
    code fences — they will be treated as topic boundaries here too.
    """
    parts = re.split(r"^(## .+)$", content, flags=re.MULTILINE)
    # parts alternates: [preamble, heading1, body1, heading2, body2, ...]
    for i in range(1, len(parts), 2):
        heading = parts[i]
        body = parts[i + 1] if i + 1 < len(parts) else ""
        name = heading[3:].strip()
        yield name, body


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


def infer_version_kind(filepath) -> str:
    """Return the manifest kind for a version-bearing file path. Filename-based.
    Known kinds: plugin-json, package-json, pyproject, cargo, plain.
    Caller decides whether the kind is supported.
    """
    name = Path(filepath).name
    if name == "plugin.json":
        return "plugin-json"
    if name.endswith(".json"):
        return "package-json"
    if name == "pyproject.toml":
        return "pyproject"
    if name == "Cargo.toml":
        return "cargo"
    return "plain"


def get_version_or_die(filepath, kind: str) -> str:
    """Read the version from `filepath` (kind per `infer_version_kind`), or
    print a one-line error to stderr and `sys.exit(1)`. Wraps `read_version`
    so release helpers don't have to repeat the same try/except dance.

    Error messages match the prior inline implementation byte-for-byte:
      - missing file        → "error: <path>: file not found"
      - corrupt JSON / TOML → "error: <path>: <e>"
      - no version field    → "error: <path>: no version field found"
    """
    try:
        v = read_version(filepath, kind)
    except FileNotFoundError:
        print(f"error: {filepath}: file not found", file=sys.stderr)
        sys.exit(1)
    except (json.JSONDecodeError, ValueError) as e:
        print(f"error: {filepath}: {e}", file=sys.stderr)
        sys.exit(1)
    if v is None:
        print(f"error: {filepath}: no version field found", file=sys.stderr)
        sys.exit(1)
    return v


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

    # 2. CLAUDE_PLUGIN_ROOT.
    cpr = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if cpr and os.path.isfile(os.path.join(cpr, ".claude-plugin", "plugin.json")):
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


def read_version(filepath, kind: str) -> str | None:
    """Read the version string from a manifest. Returns the version, or None
    if the file has no version field. Raises FileNotFoundError if the path
    doesn't exist; raises json.JSONDecodeError if a JSON manifest is corrupt
    (callers that prefer silent failure should wrap with hvlib.load_json
    semantics — but for release-helper context, surfacing a hard error on
    corrupt JSON is preferable).
    """
    path = Path(filepath)
    text = path.read_text()
    if kind in ("plugin-json", "package-json"):
        data = json.loads(text)
        return data.get("version")
    if kind == "pyproject":
        return parse_toml_version(text, ["project", "tool.poetry"])
    if kind == "cargo":
        return parse_toml_version(text, ["package"])
    if kind == "plain":
        for line in text.splitlines():
            stripped = line.strip()
            if stripped:
                return stripped
        return None
    raise ValueError(f"unknown version kind: {kind!r}")


def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Parse a YAML-ish frontmatter block delimited by `---` lines.

    Supports a flat key/value subset only:
      - `key: value`
      - `key: [a, b, c]` (inline list)
    Returns ({}, original_text) when no frontmatter is present or it is
    malformed. Never raises.
    """
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return {}, text
    # Find closing ---
    rest = text.split("\n", 1)[1] if "\n" in text else ""
    end = re.search(r"^---\s*$", rest, re.MULTILINE)
    if not end:
        return {}, text
    block = rest[: end.start()]
    body = rest[end.end():].lstrip("\n")
    fm: dict = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            fm[key] = [v.strip() for v in inner.split(",") if v.strip()] if inner else []
        else:
            fm[key] = value
    return fm, body


def update_frontmatter_field(content: str, field: str, value: str) -> "tuple[str, bool]":
    """Edit the first `<field>: <value>` pair in the YAML frontmatter block.
    Returns (new_content, True) on success, (content, False) if no frontmatter
    or the field is absent in the frontmatter. Substitution is confined to the
    slice between the first two `---` lines.
    """
    if not (content.startswith("---\n") or content.startswith("---\r\n")):
        return (content, False)
    # Locate the closing --- of the frontmatter.
    rest_start = content.index("\n") + 1
    rest = content[rest_start:]
    end_m = re.search(r"^---\s*$", rest, re.MULTILINE)
    if not end_m:
        return (content, False)
    fm_slice = rest[: end_m.start()]
    body_after = rest[end_m.start():]
    pat = re.compile(rf"^({re.escape(field)}:\s*)\S+", re.MULTILINE)
    new_fm, n = pat.subn(rf"\g<1>{value}", fm_slice, count=1)
    if not n:
        return (content, False)
    return (content[:rest_start] + new_fm + body_after, True)


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


def write_version(filepath, kind: str, new_version: str) -> None:
    """Write `new_version` into the manifest at `filepath` according to `kind`.
    JSON manifests are rewritten with dump_json_atomic; TOML manifests have
    only the `version = "..."` line in the relevant section replaced
    (write_text_atomic); `plain` rewrites the file with `new_version + "\\n"`.
    Raises FileNotFoundError if the file is missing; raises ValueError if the
    target section/field can't be located.
    """
    path = Path(filepath)
    if kind in ("plugin-json", "package-json"):
        data = load_json(path, {})
        data["version"] = new_version
        dump_json_atomic(path, data)
        return
    if kind == "plain":
        write_text_atomic(path, new_version + "\n")
        return
    if kind in ("pyproject", "cargo"):
        sections = ["project", "tool.poetry"] if kind == "pyproject" else ["package"]
        content = path.read_text()
        for section_name in sections:
            sec_pat = re.compile(
                r"^\s*\[" + re.escape(section_name) + r"\s*\]\s*$",
                re.MULTILINE,
            )
            sec_m = sec_pat.search(content)
            if not sec_m:
                continue
            next_m = re.search(r"^\s*\[", content[sec_m.end():], re.MULTILINE)
            end = sec_m.end() + next_m.start() if next_m else len(content)
            sec_body = content[sec_m.end():end]
            new_body, n = re.subn(
                r'(?m)^(version\s*=\s*)"[^"]*"',
                rf'\1"{new_version}"',
                sec_body,
                count=1,
            )
            if n:
                content = content[:sec_m.end()] + new_body + content[end:]
                write_text_atomic(path, content)
                return
        raise ValueError(f"{path}: no version field in section")
    raise ValueError(f"unknown version kind: {kind!r}")


# ── TODO mutation helpers (extracted from bin/hv-rm) ──────────────────────────


def find_bullet_in_content(content: str, iid: str, active_sections: list[str]) -> tuple[str | None, str | None]:
    """Return (section_name, bullet_line) for iid in content, or (None, None).
    `active_sections` is the ordered list of `## <name>` sections to scan
    (typically Bugs, Features, Tasks, Completed)."""
    # Match open bullets: - **[ID]...
    open_pat = re.compile(
        rf"^- \*\*\[{re.escape(iid)}\].*$",
        re.MULTILINE,
    )
    # Match done/strikethrough bullets: - ~~**[ID]...~~ Done ...
    done_pat = re.compile(
        rf"^- ~~\*\*\[{re.escape(iid)}\].*$",
        re.MULTILINE,
    )
    for sec_name in active_sections:
        span = find_section(content, sec_name)
        if span is None:
            continue
        body = content[span[0]:span[1]]
        m = open_pat.search(body) or done_pat.search(body)
        if m:
            return (sec_name, m.group(0))
    return (None, None)


def find_open_bullet(content: str, iid: str, active_sections: list[str]) -> "str | None":
    """Return the full open-bullet line for `iid` in any of `active_sections`.
    Differs from find_bullet_in_content: returns just the line (not a tuple),
    and scans open bullets only (not done/strikethrough lines).
    Returns None if no open bullet is found.
    """
    bullet_re = open_bullet_re()
    for sec_name, body in iter_open_sections(content):
        if sec_name not in active_sections:
            continue
        for m in bullet_re.finditer(body):
            if m.group("id") == iid:
                return m.group(0)
    return None


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


def strip_bullet_from_content(content: str, bullet_line: str, sec_name: str) -> str:
    """Remove `bullet_line` from `content` (re.MULTILINE escape) along
    with one trailing blank line if present, to avoid double-blank-lines."""
    # We need to remove the bullet and the trailing newline; if followed by a
    # blank line, remove that too to avoid double-blank-lines.
    escaped = re.escape(bullet_line)
    # Match the line plus optional trailing blank line.
    pat = re.compile(rf"^{escaped}\n(\n)?", re.MULTILINE)
    return pat.sub(lambda m: "\n" if m.group(1) else "", content, count=1)


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

    if not new_ids:
        # Drop the entire Related: segment.
        # Match " Related: <value>" where <value> ends at the next field or EOL.
        pat = re.compile(
            r"\s+Related:\s+.+?(?=\s+(?:Detail|Milestone|Repos):|$)",
        )
        return pat.sub("", line).rstrip()
    else:
        # Rebuild Related value preserving spacing: "[A01], [B02]" style.
        new_val = ", ".join(f"[{x}]" for x in new_ids)
        # Replace the bracketed IDs in the existing Related: value.
        # Strategy: replace the raw bracket-id sequence in the field substring.
        old_pat = re.compile(r"(Related:\s+)(.+?)(?=\s+(?:Detail|Milestone|Repos):|$)")
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
