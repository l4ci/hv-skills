"""Shared utilities for hv-* helpers. Imported by python3 heredocs in bin/.

Loaded via PYTHONPATH = $(dirname "$0") set by the bash wrapper. Do NOT import
this from outside bin/.

After F25 this module is a thin re-export shim. Every public name resolves
to a flat hvlib_<concern>.py module below; the only function defined here
is git_mtime (small, subprocess-only, no concern-shaped sibling). Inter-module
imports follow the direct-path rule (never `from hvlib import ...` inside
an hvlib_<name>.py) — keeps the import DAG acyclic so future cuts stay
single-file edits.
"""
import subprocess

# Re-exports — keep `from hvlib import X` working for callers.
from hvlib_io import (
    load_json, load_config, read_or_empty, write_text_atomic, dump_json_atomic, update_json,
    load_sidecar,
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
    iter_topics, load_backlog_corpus, upsert_block, managed_block_regex,
)
from hvlib_bullet import (
    _TODO_FIELD_NAMES, _DONE_LINE_RE,
    find_item_ids, find_origin_bullet, parse_todo_fields, set_todo_field,
    open_bullet_re, parse_open_bullet, format_done_line, parse_done_line,
    find_bullet_in_content, find_open_bullet, strip_bullet_from_content,
    resolve_cycle_ids,
)
from hvlib_frontmatter import parse_frontmatter, update_frontmatter_field
from hvlib_paths import (
    resolve_plugin_root, iter_map_entries,
    infer_type_from_section, detail_dir_for_id,
    section_name_for_id, section_name_for_dir,
)
from hvlib_repos import (
    parse_repos_csv, validate_repos, load_repos, active_items,
    parse_milestones, update_milestone_status_line,
)
from hvlib_knowledge import (
    resolve_knowledge_target, resolve_tier_sidecar, compute_managed_block_inputs,
)
from hvlib_glossary import (
    parse_term_entry, first_sentence,
    parse_glossary_entries, build_glossary_entry, split_csv_list,
    check_alias_collisions, merge_into_by_key, render_glossary_body,
)
from hvlib_crossref import (
    parse_related_ids, remove_id_from_related_field,
    collect_cross_refs, apply_cross_ref_strips,
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
