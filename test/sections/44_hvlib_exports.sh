echo "F25 T1 hvlib export sentinel — caller-imported public names resolve via from hvlib import X"

# Enumerates every public name actively imported by `bin/hv-*` helpers
# via `from hvlib import …`. Each name MUST resolve through the shim,
# whether defined in bin/hvlib.py directly or re-exported from a flat
# bin/hvlib_<name>.py module.
#
# Maintenance: when a helper adds a new `from hvlib import X` line,
# append X to NAMES below in alphabetical order; when the last importer
# of a name drops it, remove the entry. The list is the must-preserve
# public surface — any future decomposition commit that accidentally
# drops a name fails this sentinel before reaching ship. The drift
# guard below rescans bin/hv-* on every run, so NAMES cannot silently
# diverge from the live import surface in either direction (T105).

PYTHONPATH="$BIN" python3 - <<'PY'
import re
from pathlib import Path

import hvlib

NAMES = [
    "ALL_BACKLOG_SECTIONS",
    "BACKLOG_FILE",
    "COUNTABLE_TYPES",
    "VERSION_KIND_REGISTRY",
    "active_items",
    "append_to_section",
    "apply_cross_ref_strips",
    "bump_hit",
    "check_alias_collisions",
    "collect_cross_refs",
    "compute_managed_block_inputs",
    "detail_dir_for_id",
    "detect_version_kind",
    "dump_json_atomic",
    "find_bullet_in_content",
    "find_item_ids",
    "find_open_bullet",
    "find_origin_bullet",
    "find_section",
    "format_done_line",
    "get_version_or_die",
    "git_mtime",
    "infer_version_kind",
    "iter_map_entries",
    "iter_open_bullets",
    "iter_open_sections",
    "iter_topics",
    "load_backlog_corpus",
    "load_config",
    "load_json",
    "load_repos",
    "load_sidecar",
    "load_tier_sidecar",
    "locked",
    "managed_block_regex",
    "merge_into_by_key",
    "open_bullet_re",
    "parse_done_line",
    "parse_frontmatter",
    "parse_glossary_entries",
    "parse_milestones",
    "parse_open_bullet",
    "parse_related_ids",
    "parse_repos_csv",
    "parse_term_entry",
    "parse_todo_fields",
    "print_matching_sections",
    "read_or_empty",
    "remove_id_from_related_field",
    "render_glossary_body",
    "replace_section",
    "resolve_cycle_ids",
    "resolve_knowledge_target",
    "resolve_plugin_root",
    "resolve_tier_sidecar",
    "save_tier_sidecar",
    "section",
    "section_name_for_dir",
    "section_name_for_id",
    "set_todo_field",
    "split_csv_list",
    "strip_bullet_from_content",
    "update_frontmatter_field",
    "update_json",
    "update_milestone_status_line",
    "upsert_block",
    "validate_repos",
    "write_text_atomic",
]

missing = [n for n in NAMES if not hasattr(hvlib, n)]
if missing:
    print(f"hvlib missing {len(missing)} caller-imported name(s): {missing}")
    raise SystemExit(1)

# Constants need a non-None resolution check; callables need to be callable.
# Semantic equality is out of scope — the sentinel asserts the surface, not
# behavior. Behavior is covered by the other smoke sections.
for n in NAMES:
    val = getattr(hvlib, n)
    if val is None:
        print(f"hvlib.{n} resolves to None")
        raise SystemExit(1)

# Drift guard (T105): NAMES must mirror the live import surface. Scan every
# bin/hv-* helper for `from hvlib import …` (single-line and parenthesized
# multiline forms) and fail on divergence in either direction. To regenerate
# NAMES, print `sorted(imported)` from this scan.
bin_dir = Path(hvlib.__file__).resolve().parent
imported = set()
for p in sorted(bin_dir.glob("hv-*")):
    if not p.is_file():
        continue
    try:
        text = p.read_text()
    except (OSError, UnicodeDecodeError):
        continue
    bodies = [m.group(1) for m in re.finditer(
        r"^[ \t]*from hvlib import \(([^)]*)\)", text, re.M | re.S)]
    bodies += [m.group(1) for m in re.finditer(
        r"^[ \t]*from hvlib import ([^(\n]+)$", text, re.M)]
    for body in bodies:
        for tok in re.split(r"[,\n]", body):
            tok = tok.split("#")[0].strip()
            if tok.isidentifier():
                imported.add(tok)

unregistered = sorted(imported - set(NAMES))
stale = sorted(set(NAMES) - imported)
if unregistered:
    print(f"NAMES missing {len(unregistered)} imported name(s): {unregistered}")
    raise SystemExit(1)
if stale:
    print(f"NAMES carries {len(stale)} name(s) no helper imports: {stale}")
    raise SystemExit(1)

print(f"OK: {len(NAMES)} public names resolve via from hvlib import X; NAMES matches live import surface")
PY

pass "hvlib export sentinel — caller-imported public names resolve via shim"
