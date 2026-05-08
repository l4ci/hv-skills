"""Shared utilities for hv-* helpers. Imported by python3 heredocs in bin/.

Loaded via PYTHONPATH = $(dirname "$0") set by the bash wrapper. Do NOT import
this from outside bin/. The functions here are stdlib-only and side-effect-free
(except write_text_atomic / dump_json_atomic / update_json, which write).
"""
import json
import os
import re
import sys
from pathlib import Path


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


def find_origin_bullet(corpus: str, iid: str) -> tuple[str, str | None] | None:
    """Find the origin bullet for `iid` in `corpus` (typically TODO.md +
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
    """Extract Detail/Related/Milestone/Repos fields from a TODO bullet line.

    Each field starts with `<Field>: ` and runs until the next field marker
    or end of line. Order-agnostic. Returns a dict with keys 'detail',
    'related', 'milestone', 'repos' — missing fields map to ''.

    Example: parse_todo_fields("- **[B01] [P1] Title.** Body. Detail: foo. Related: [F02]. Milestone: M01")
        => {"detail": "foo.", "related": "[F02].", "milestone": "M01", "repos": ""}
    Example: parse_todo_fields("- **[F01] [Major] Title.** D. Detail: x. Milestone: M02 Repos: web")
        => {"detail": "x.", "related": "", "milestone": "M02", "repos": "web"}
    """
    fields = {"detail": "", "related": "", "milestone": "", "repos": ""}
    others = {
        "detail": ["Related", "Milestone", "Repos"],
        "related": ["Detail", "Milestone", "Repos"],
        "milestone": ["Detail", "Related", "Repos"],
        "repos": ["Detail", "Related", "Milestone"],
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


def write_text_atomic(path, text: str) -> None:
    """Write `text` to `path` atomically (tmp + os.replace). Trailing
    newline is the caller's responsibility. `path` may be a str or Path.
    """
    p = Path(path)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, p)


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
