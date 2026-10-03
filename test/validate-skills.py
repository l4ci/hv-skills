"""
validate-skills.py — static schema validator for hv-skills SKILL.md files,
plus the legacy-name doclint over skills and references (A9, #53).
Stdlib only. `--list-legacy` prints the frozen legacy helper names and exits. Exit 0 on all-pass, exit 1 on any failure, exit 2 on unexpected error.
"""

import json
import os
import re
import sys
from pathlib import Path


def parse_frontmatter(text):
    """Return (dict_of_keys, post_frontmatter_text) or (None, text) if no frontmatter."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text
    end = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end = i
            break
    if end is None:
        return None, text
    fm_lines = lines[1:end]
    post = "\n".join(lines[end + 1:])
    keys = {}
    for line in fm_lines:
        m = re.match(r'^(\w[\w-]*):\s*(.*)', line)
        if m:
            k, v = m.group(1), m.group(2).strip()
            # strip surrounding quotes if present
            if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                v = v[1:-1]
            keys[k] = v
    return keys, post


def check_frontmatter(path, text, issues):
    fm, _ = parse_frontmatter(text)
    if fm is None:
        issues.append(f"{path}: no frontmatter block found")
        return
    for key in ("name", "description"):
        if key not in fm or not fm[key]:
            issues.append(f"{path}: frontmatter missing required key '{key}'")


def check_banner(path, text, issues):
    # Only validate banner for skills that declare one (delegation/alias stubs omit it by design)
    if "Print the banner" not in text:
        return

    _, post = parse_frontmatter(text)
    post_lines = post.splitlines()
    # Search within first 30 lines of post-frontmatter content
    window = post_lines[:30]
    # Find opening fence
    in_block = False
    block_lines = []
    found_block = False
    for line in window:
        if not in_block:
            if line.strip().startswith("```"):
                in_block = True
                block_lines = []
                found_block = True
        else:
            if line.strip().startswith("```"):
                in_block = False
                break
            block_lines.append(line)

    if not found_block or not block_lines:
        issues.append(f"{path}: banner block missing or malformed")
        return

    has_box = any("═" in l for l in block_lines)
    has_triggers_pairs = any("triggers:" in l and "pairs:" in l for l in block_lines)
    if not has_box or not has_triggers_pairs:
        issues.append(f"{path}: banner block missing or malformed")


def check_references(path, text, issues):
    skill_dir = Path(path).parent
    # Match markdown links pointing at references/*.md (relative paths, with or without ../)
    pattern = re.compile(r'\((\.\./references/[^)\s]+\.md|references/[^)\s]+\.md)\)')
    for m in pattern.finditer(text):
        target = m.group(1)
        resolved = (skill_dir / target).resolve()
        if not resolved.exists():
            issues.append(f"{path}: broken reference '{target}' -> '{resolved}'")


def check_version(issues):
    plugin_path = Path(".claude-plugin/plugin.json")
    changelog_path = Path("CHANGELOG.md")

    if not plugin_path.exists():
        issues.append("version mismatch: plugin.json not found")
        return
    if not changelog_path.exists():
        issues.append("version mismatch: CHANGELOG.md not found")
        return

    with plugin_path.open() as f:
        plugin_data = json.load(f)
    plugin_version = plugin_data.get("version", "")

    changelog_version = None
    with changelog_path.open() as f:
        for line in f:
            m = re.match(r'^## v(\S+)', line)
            if m:
                changelog_version = m.group(1)
                break

    if changelog_version is None:
        issues.append("version mismatch: no version heading found in CHANGELOG.md")
        return

    # plugin.json uses bare semver (e.g. "3.1.0"), CHANGELOG uses "v3.1.0" — strip v
    plugin_v = plugin_version.lstrip("v")
    changelog_v = changelog_version.lstrip("v")

    if plugin_v != changelog_v:
        issues.append(
            f"version mismatch: plugin.json={plugin_version} CHANGELOG.md=v{changelog_version}"
        )


# Legacy-name doclint (A9, #53). After the cutover no skill or shared reference
# may name an old bin/ helper, the .hv/bin mirror or hvlib: skills call `hv
# <verb>`. The name list is frozen from bin/ at the start of A9, so the check
# keeps working once S7 deletes bin/. hv-migrate is left out because it is also
# a skill name. A name preceded by "/" is a slash command, not a helper call;
# bin/ paths are caught by the bin/hv- and .hv/bin patterns instead.
LEGACY_HELPERS = """
    hv-append hv-archive-old hv-artifact-amend.sh hv-artifact-rm.sh
    hv-artifact-show.sh hv-auto-decision-log hv-auto-decisions-since
    hv-backfill-since hv-backlog hv-base-branch hv-bootstrap hv-capture-audit
    hv-codex-verify hv-complete hv-config-schema-check hv-config-set hv-config-show
    hv-debug-counter hv-decisions-query hv-design-add hv-design-amend hv-design-list
    hv-design-put hv-design-rm hv-design-show hv-find-milestone-for-items hv-fm-list
    hv-glossary-import hv-glossary-read hv-glossary-write hv-guard-clean
    hv-guard-feature-branch hv-host-herdr.sh hv-host-select.sh hv-host-tmux.sh
    hv-instructions-init hv-issue-suggest hv-issues-close hv-issues-common.sh
    hv-issues-imported hv-issues-label hv-issues-list hv-issues-provider
    hv-item-claim hv-item-comment hv-item-create hv-item-note hv-item-ready
    hv-item-release hv-item-show hv-item-state hv-knowledge-amend
    hv-knowledge-contradiction hv-knowledge-hit hv-knowledge-merge
    hv-knowledge-migrate hv-knowledge-query hv-knowledge-rename-topic
    hv-knowledge-scope.sh hv-knowledge-stats hv-knowledge-tier hv-loop-stamp
    hv-managed-block hv-managed-block-strip-deprecated hv-map-cap-check hv-map-index
    hv-map-query hv-map-stats hv-merge hv-migrate-issues hv-multi-branch-create
    hv-next-id hv-plan-add hv-plan-list hv-plan-put hv-plan-rename-check hv-plan-rm
    hv-plan-show hv-plan-validate-docs hv-pr hv-pr-merge hv-preamble.sh hv-preflight
    hv-proof-add hv-proof-show hv-qa-index hv-qa-query hv-reconcile hv-refactor-age
    hv-refactor-reset hv-refactor-targets hv-release-bump-version
    hv-release-changelog-from-commits hv-release-close-milestone
    hv-release-detect-host hv-release-detect-version hv-release-milestone-check
    hv-release-notes-from-issues hv-release-pending hv-release-update-changelog
    hv-repo-flag.sh hv-require-git-context hv-resolve-handoff hv-resolve-plugin-root
    hv-resolve-repo hv-resolve-repo-path hv-resolve-repos hv-resolve-umbrella
    hv-review-queue hv-review-scaffolding hv-review-scope hv-rm
    hv-second-opinion-brief hv-section-query hv-self-locate.sh hv-ship-body
    hv-skills-index hv-spike-add hv-spike-finish hv-spike-list hv-spike-show
    hv-stale-summary hv-staleness hv-status-add hv-status-add-multi hv-status-remove
    hv-status-repo-for hv-summary hv-todo-by-milestone hv-todo-drift hv-todo-field
    hv-todo-set-field hv-tracker-call hv-types.sh hv-umbrella-init hv-umbrella-on
    hv-uncertain hv-uncomplete hv-undo hv-update-check hv-version-check
    hv-vision-active hv-vision-add hv-vision-empty-active hv-vision-index
    hv-vision-list hv-vision-put hv-vision-show hv-vision-status hv-walk-up
    hv-worker-account hv-worker-dispatch hv-worker-gate hv-worker-poll
    hv-worker-pool hv-worker-reset hv-worker-session hv-worktree-clear
    hv-worktree-path
""".split()

LEGACY_RE = re.compile(
    r"(?<![\w/.-])(?:"
    + "|".join(re.escape(n) for n in sorted(LEGACY_HELPERS, key=len, reverse=True))
    + r")(?![\w-])"
    + r"|\.hv/bin|hvlib|(?<![\w.-])bin/hv-"
)

# Files not yet converted to hv verbs. Each A9 slice deletes its own lines in
# the PR that converts the files; the groups are kept apart so two slices'
# deletions never touch adjacent lines. An entry whose file is already clean
# (or gone) fails the check, so the list can only shrink. It is empty after S5.
UNCONVERTED = {
    # S2 leftovers: hv-codex-verify lines wait on the E1 decision (#68)
    "hv-qa/SKILL.md",
    "hv-ship/SKILL.md",

    # S5 lifecycle
    "hv-config/SKILL.md",
    "hv-init/SKILL.md",
    "hv-migrate/SKILL.md",
    "hv-update/SKILL.md",
    "references/update-verdicts.md",
}


def doclint_files():
    # One level each: a recursive walk would reach .worktrees/ checkouts (section 70).
    files = list(Path(".").glob("hv-*/*.md")) + list(Path("references").glob("*.md"))
    return sorted(p.as_posix() for p in files)


def unconverted():
    # HV_DOCLINT_UNCONVERTED (whitespace-separated paths) replaces the list, so
    # smoke section 29 can test the check on a fixture tree.
    override = os.environ.get("HV_DOCLINT_UNCONVERTED")
    return set(override.split()) if override is not None else UNCONVERTED


def check_legacy_names(issues):
    allow = unconverted()
    for path in doclint_files():
        text = Path(path).read_text(encoding="utf-8")
        hits = [(n, m.group(0)) for n, line in enumerate(text.splitlines(), 1)
                for m in LEGACY_RE.finditer(line)]
        if path in allow:
            if not hits:
                issues.append(f"{path}: no legacy names left; remove it from UNCONVERTED")
            continue
        for n, name in hits:
            issues.append(f"{path}:{n}: names legacy '{name}'; call the hv verb instead")
    for path in sorted(allow - set(doclint_files())):
        issues.append(f"{path}: listed in UNCONVERTED but missing; remove the entry")


def main():
    if "--list-legacy" in sys.argv[1:]:
        print("\n".join(LEGACY_HELPERS))
        sys.exit(0)
    issues = []

    skill_files = sorted(Path(".").glob("hv-*/SKILL.md"))

    for skill_path in skill_files:
        text = skill_path.read_text(encoding="utf-8")
        check_frontmatter(skill_path, text, issues)
        check_banner(skill_path, text, issues)
        check_references(skill_path, text, issues)

    check_legacy_names(issues)
    check_version(issues)

    n = len(skill_files)
    if issues:
        for line in issues:
            print(line, file=sys.stderr)
        print(f"validate-skills: FAIL ({len(issues)} issues)")
        sys.exit(1)
    else:
        print(f"validate-skills: PASS ({n} SKILL.md files checked)")
        sys.exit(0)


try:
    main()
except Exception as exc:
    print(f"validate-skills: ERROR {exc}", file=sys.stderr)
    sys.exit(2)
