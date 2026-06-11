echo "F25 T1 hvlib export sentinel — caller-imported public names resolve via from hvlib import X"

# Enumerates every public name actively imported by `bin/hv-*` helpers
# via `from hvlib import …`. Each name MUST resolve through the shim,
# whether defined in bin/hvlib.py directly or re-exported from a flat
# bin/hvlib_<name>.py module.
#
# Maintenance: when a helper adds a new `from hvlib import X` line,
# append X to NAMES below in alphabetical order. The list is the
# must-preserve public surface — any future decomposition commit that
# accidentally drops a name fails this sentinel before reaching ship.

PYTHONPATH="$BIN" python3 - <<'PY'
import hvlib

NAMES = [
    "COUNTABLE_TYPES",
    "VERSION_KIND_REGISTRY",
    "active_items",
    "append_to_section",
    "apply_cross_ref_strips",
    "build_glossary_entry",
    "collect_cross_refs",
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
    "iter_open_sections",
    "iter_topics",
    "load_backlog_corpus",
    "load_config",
    "load_json",
    "load_repos",
    "locked",
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
    "replace_section",
    "resolve_plugin_root",
    "section",
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

print(f"OK: {len(NAMES)} public names resolve via from hvlib import X")
PY

pass "hvlib export sentinel — caller-imported public names resolve via shim"
