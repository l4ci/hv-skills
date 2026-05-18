"""TODO bullet parsing and ID-extraction primitives. Pure stdlib +
hvlib_section. Re-exported by hvlib for backward compat.

_TODO_FIELD_NAMES is the single source of truth for TODO field names —
the regex builder for parse_todo_fields and the end-lookahead in
remove_id_from_related_field both consume it. Co-located with
parse_todo_fields so future field additions can't desync the tuple
from its consumers. Per KNOWLEDGE: adding a field also requires
updating the `fields` dict initializer and the valid-fields set in
bin/hv-todo-field — see test/sections/05_reconcile.sh.
"""
import os
import re

from hvlib_section import find_section, iter_open_sections


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


# Single source of truth for TODO field names recognised by parse_todo_fields
# and used by remove_id_from_related_field. Add new fields here only.
_TODO_FIELD_NAMES = ("Detail", "Related", "Milestone", "Repos", "Subsystem", "Captured", "Since")


def parse_todo_fields(line: str) -> dict[str, str]:
    """Extract Detail/Related/Milestone/Repos/Subsystem/Captured/Since fields from a TODO bullet line.

    Each field starts with `<Field>: ` and runs until the next field marker
    or end of line. Order-agnostic. Returns a dict with keys 'detail',
    'related', 'milestone', 'repos', 'subsystem', 'captured', 'since' — missing fields map to ''.

    `Since:` holds the short commit hash of HEAD at capture time; hv-todo-drift
    uses it to ignore commits older than capture, preventing false-positives
    when IDs are reused across machine syncs.

    Example: parse_todo_fields("- **[B01] [P1] Title.** Body. Detail: foo. Related: [F02]. Milestone: M01")
        => {"detail": "foo.", "related": "[F02].", "milestone": "M01", "repos": "", "subsystem": "", "since": ""}
    Example: parse_todo_fields("- **[F01] [Major] Title.** D. Milestone: M02 Repos: web Since: a1b2c3d")
        => {"detail": "", "related": "", "milestone": "M02", "repos": "web", "subsystem": "", "since": "a1b2c3d"}
    Example: parse_todo_fields("- **[B07] [P1] Title.** D. Repos: web Subsystem: capture Captured: 2026-05-09")
        => {"detail": "", "related": "", "milestone": "", "repos": "web", "subsystem": "capture", "captured": "2026-05-09", "since": ""}
    """
    fields = {"detail": "", "related": "", "milestone": "", "repos": "", "subsystem": "", "captured": "", "since": ""}
    for key in fields:
        cap = key.capitalize()
        end_lookahead = "|".join(n for n in _TODO_FIELD_NAMES if n != cap)
        pat = re.compile(rf"\b{cap}:\s*(.+?)(?=\s+(?:{end_lookahead}):|$)")
        m = pat.search(line)
        if m:
            fields[key] = m.group(1).strip()
    return fields


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


def strip_bullet_from_content(content: str, bullet_line: str, sec_name: str) -> str:
    """Remove `bullet_line` from `content` (re.MULTILINE escape) along
    with one trailing blank line if present, to avoid double-blank-lines."""
    # We need to remove the bullet and the trailing newline; if followed by a
    # blank line, remove that too to avoid double-blank-lines.
    escaped = re.escape(bullet_line)
    # Match the line plus optional trailing blank line.
    pat = re.compile(rf"^{escaped}\n(\n)?", re.MULTILINE)
    return pat.sub(lambda m: "\n" if m.group(1) else "", content, count=1)
