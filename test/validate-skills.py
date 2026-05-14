"""
validate-skills.py — static schema validator for hv-skills SKILL.md files.
Stdlib only. Exit 0 on all-pass, exit 1 on any failure, exit 2 on unexpected error.
"""

import json
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


def main():
    issues = []

    skill_files = sorted(Path(".").glob("hv-*/SKILL.md"))

    for skill_path in skill_files:
        text = skill_path.read_text(encoding="utf-8")
        check_frontmatter(skill_path, text, issues)
        check_banner(skill_path, text, issues)
        check_references(skill_path, text, issues)

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
