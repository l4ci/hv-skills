"""Markdown section/topic scanning + open-section iteration + block upsert
for hv-* helpers. Pure stdlib + hvlib_io. No dependency on bin/hvlib.py
(re-exported by hvlib for backward compat).

iter_topics lives here (not in hvlib_glossary) because it's a generic
heading scanner that yields (name, body) for every `## Topic` heading —
glossary uses it, but so do knowledge/decisions/summary callers, and
print_matching_sections (below) calls it directly. Inter-module imports
follow the direct-path rule (no circular routing through hvlib).
"""
import os
import re
import sys
from pathlib import Path

from hvlib_io import read_or_empty, write_text_atomic


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


def load_backlog_corpus(base_dir=".") -> str:
    """Return BACKLOG.md + ARCHIVE.md concatenated from <base_dir>/.hv/.
    Used by ship-body, todo-field, and review-scope to look up an item ID
    across active and archived backlog in one pass.
    """
    hv = Path(base_dir) / ".hv"
    primary = read_or_empty(hv / BACKLOG_FILE)
    return primary.rstrip("\n") + "\n" + read_or_empty(hv / "ARCHIVE.md")


def managed_block_regex(
    key: str,
    legacy_marker: "str | None" = None,
    *,
    consume_trailing_newline: bool = False,
) -> "re.Pattern[str]":
    """Build the regex matching a managed CLAUDE.md block.

    Matches both canonical `<!-- hv-<key>-start --> ... <!-- hv-<key>-end -->`
    and, when `legacy_marker` is given, the legacy `<!-- hv:<legacy_marker>:start --> ... <!-- hv:<legacy_marker>:end -->`
    form. Use legacy_marker=key for symmetric stripping of obsolete keys.

    `consume_trailing_newline=True` extends the match with `\\n?` after the end
    delimiter so callers that want to remove the block (vs. replace it in
    place) don't leave a blank line behind.
    """
    tail = r"\n?" if consume_trailing_newline else ""
    if legacy_marker:
        return re.compile(
            rf"<!-- hv(?:-{re.escape(key)}-start|:{re.escape(legacy_marker)}:start) -->"
            rf".*?"
            rf"<!-- hv(?:-{re.escape(key)}-end|:{re.escape(legacy_marker)}:end) -->"
            rf"{tail}",
            re.DOTALL,
        )
    return re.compile(
        rf"<!-- hv-{re.escape(key)}-start -->.*?<!-- hv-{re.escape(key)}-end -->{tail}",
        re.DOTALL,
    )


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
    pattern = managed_block_regex(key, legacy_marker=legacy_marker)
    if pattern.search(content):
        new_content = pattern.sub(block, content)
        if new_content == content:
            return "unchanged"
        write_text_atomic(claude_path, new_content)
        return "updated"
    new_content = content.rstrip() + "\n\n" + block + "\n"
    if new_content == content:
        return "unchanged"
    write_text_atomic(claude_path, new_content)
    return "appended"
