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
from hvlib_paths import (
    resolve_plugin_root, iter_map_entries,
    infer_type_from_section, infer_type_from_id, detail_dir_for_id,
)
from hvlib_repos import (
    parse_repos_csv, validate_repos, load_repos, active_items,
    parse_milestones, update_milestone_status_line,
)
from hvlib_glossary import (
    parse_term_entry, first_sentence,
    parse_glossary_entries, build_glossary_entry, split_csv_list,
)


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


