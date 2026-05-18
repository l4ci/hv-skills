"""Path resolution + ID-to-section/dir mapping for hv-* helpers.
Pure stdlib + hvlib_io (for load_json in resolve_plugin_root) +
hvlib_frontmatter (for iter_map_entries). Re-exported by hvlib for
backward compat.

resolve_plugin_root() is the single source of truth for plugin-root
discovery — bin/hv-update-check and bin/hv-version-check both call
through here so the resolution walk stays in sync (B12 lesson).
"""
import os
import re

from hvlib_io import load_json
from hvlib_frontmatter import parse_frontmatter
from pathlib import Path


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
