"""YAML-ish frontmatter parsing for hv-* helpers. Pure stdlib; no
dependency on other hvlib_* modules. Re-exported by hvlib for backward
compat.

Used by design/spike/plan/qa/map artifacts which carry a `---` block at
the top — these helpers handle the flat key/value + inline-list subset
that those artifacts actually use, not full YAML.
"""
import re


def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Parse a YAML-ish frontmatter block delimited by `---` lines.

    Supports a flat key/value subset only:
      - `key: value`
      - `key: [a, b, c]` (inline list)
    Returns ({}, original_text) when no frontmatter is present or it is
    malformed. Never raises.
    """
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return {}, text
    # Find closing ---
    rest = text.split("\n", 1)[1] if "\n" in text else ""
    end = re.search(r"^---\s*$", rest, re.MULTILINE)
    if not end:
        return {}, text
    block = rest[: end.start()]
    body = rest[end.end():].lstrip("\n")
    fm: dict = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            fm[key] = [v.strip() for v in inner.split(",") if v.strip()] if inner else []
        else:
            fm[key] = value
    return fm, body


def update_frontmatter_field(content: str, field: str, value: str) -> "tuple[str, bool]":
    """Edit the first `<field>: <value>` pair in the YAML frontmatter block.
    Returns (new_content, True) on success, (content, False) if no frontmatter
    or the field is absent in the frontmatter. Substitution is confined to the
    slice between the first two `---` lines.
    """
    if not (content.startswith("---\n") or content.startswith("---\r\n")):
        return (content, False)
    # Locate the closing --- of the frontmatter.
    rest_start = content.index("\n") + 1
    rest = content[rest_start:]
    end_m = re.search(r"^---\s*$", rest, re.MULTILINE)
    if not end_m:
        return (content, False)
    fm_slice = rest[: end_m.start()]
    body_after = rest[end_m.start():]
    pat = re.compile(rf"^({re.escape(field)}:\s*)\S+", re.MULTILINE)
    new_fm, n = pat.subn(rf"\g<1>{value}", fm_slice, count=1)
    if not n:
        return (content, False)
    return (content[:rest_start] + new_fm + body_after, True)
