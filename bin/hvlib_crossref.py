"""TODO cross-reference / Related: field utilities. Pure stdlib +
direct imports from hvlib_section, hvlib_bullet. Re-exported by hvlib
for backward compat.

remove_id_from_related_field uses _TODO_FIELD_NAMES as the end-lookahead
boundary builder — co-imported from hvlib_bullet (single source of truth
for TODO field names).
"""
import re

from hvlib_section import find_section
from hvlib_bullet import parse_todo_fields, _TODO_FIELD_NAMES


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
