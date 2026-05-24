"""Version reading/writing helpers for hv-* helpers. Extracted from hvlib.py
to keep the main module under 800 LoC.

Imports IO primitives from hvlib_io (pure stdlib otherwise). Re-exported by
hvlib for backward compat: existing `from hvlib import write_version` imports
continue to work.
"""
import json
import re
import sys
from pathlib import Path

from hvlib_io import load_json, dump_json_atomic, write_text_atomic


def parse_toml_version(text: str, sections: list[str]) -> str | None:
    """Find `version = "x.y.z"` inside one of the given [section] headings
    in `text` (TOML source). `sections` is checked in order; the first hit
    wins. Returns the version string or None if no section matches or no
    version field is present in any matching section.

    The section heading match is anchored at line start, allows leading
    whitespace, and tolerates trailing whitespace inside the brackets.
    The version regex is anchored at line start of the section body
    (after the heading, up to the next [heading] or EOF).

    Used by hv-release-detect-version (read path) and hv-release-bump-version
    (read path) to keep the regex/section-traversal logic identical.
    """
    for section in sections:
        pattern = re.compile(
            r"^\s*\[" + re.escape(section) + r"\s*\]\s*$",
            re.MULTILINE,
        )
        m = pattern.search(text)
        if not m:
            continue
        rest = text[m.end():]
        next_section = re.search(r"^\s*\[", rest, re.MULTILINE)
        block = rest[: next_section.start()] if next_section else rest
        v = re.search(r'^version\s*=\s*"([^"]*)"', block, re.MULTILINE)
        if v:
            return v.group(1)
    return None


def infer_version_kind(filepath) -> str:
    """Return the manifest kind for a version-bearing file path. Filename-based.
    Known kinds: plugin-json, package-json, pyproject, cargo, plain.
    Caller decides whether the kind is supported.
    """
    name = Path(filepath).name
    if name == "plugin.json":
        return "plugin-json"
    if name.endswith(".json"):
        return "package-json"
    if name == "pyproject.toml":
        return "pyproject"
    if name == "Cargo.toml":
        return "cargo"
    return "plain"


def _read_version_json(filepath: str) -> "str | None":
    return json.loads(Path(filepath).read_text()).get("version")


def _write_version_json(filepath: str, new_version: str) -> None:
    data = load_json(filepath, {})
    data["version"] = new_version
    dump_json_atomic(filepath, data)


def _read_version_pyproject(filepath: str) -> "str | None":
    return parse_toml_version(Path(filepath).read_text(), ["project", "tool.poetry"])


def _write_version_toml(filepath: str, new_version: str, sections: list) -> None:
    path = Path(filepath)
    content = path.read_text()
    for section_name in sections:
        sec_pat = re.compile(
            r"^\s*\[" + re.escape(section_name) + r"\s*\]\s*$",
            re.MULTILINE,
        )
        sec_m = sec_pat.search(content)
        if not sec_m:
            continue
        next_m = re.search(r"^\s*\[", content[sec_m.end():], re.MULTILINE)
        end = sec_m.end() + next_m.start() if next_m else len(content)
        sec_body = content[sec_m.end():end]
        new_body, n = re.subn(
            r'(?m)^(version\s*=\s*)"[^"]*"',
            rf'\1"{new_version}"',
            sec_body,
            count=1,
        )
        if n:
            content = content[:sec_m.end()] + new_body + content[end:]
            write_text_atomic(path, content)
            return
    raise ValueError(f"{filepath}: no version field in section")


def _write_version_pyproject(filepath: str, new_version: str) -> None:
    _write_version_toml(filepath, new_version, ["project", "tool.poetry"])


def _read_version_cargo(filepath: str) -> "str | None":
    return parse_toml_version(Path(filepath).read_text(), ["package"])


def _write_version_cargo(filepath: str, new_version: str) -> None:
    _write_version_toml(filepath, new_version, ["package"])


def _read_version_plain(filepath: str) -> "str | None":
    for line in Path(filepath).read_text().splitlines():
        stripped = line.strip()
        if stripped:
            return stripped
    return None


def _write_version_plain(filepath: str, new_version: str) -> None:
    write_text_atomic(filepath, new_version + "\n")


# Version-file registry. Single source of truth for "what is a version file".
# Each entry: {filenames (tuple), parser, writer}.
# Adding a new kind = one entry here, no shell-side changes needed.
VERSION_KIND_REGISTRY = {
    "plugin-json": {
        "filenames": (".claude-plugin/plugin.json",),
        "parser": _read_version_json,
        "writer": _write_version_json,
    },
    "package-json": {
        "filenames": ("package.json",),
        "parser": _read_version_json,
        "writer": _write_version_json,
    },
    "pyproject": {
        "filenames": ("pyproject.toml",),
        "parser": _read_version_pyproject,
        "writer": _write_version_pyproject,
    },
    "cargo": {
        "filenames": ("Cargo.toml",),
        "parser": _read_version_cargo,
        "writer": _write_version_cargo,
    },
    "plain": {
        "filenames": ("VERSION", "version.txt"),
        "parser": _read_version_plain,
        "writer": _write_version_plain,
    },
}


def detect_version_kind(cwd=".") -> "tuple[str, str, str] | None":
    """Return (kind_name, filename, version_string) for the first kind that
    matches a file in cwd, in VERSION_KIND_REGISTRY order. Within a kind,
    the first matching filename wins (supports multi-filename kinds like plain).
    Returns None if no version file is present.
    """
    for name, entry in VERSION_KIND_REGISTRY.items():
        for fname in entry["filenames"]:
            path = Path(cwd) / fname
            if path.exists():
                version = entry["parser"](str(path))
                return (name, fname, version)
    return None


def write_version_for_kind(kind: str, new_version: str, cwd=".") -> None:
    """Write `new_version` to the kind's canonical (first) filename.
    Raises KeyError if kind is unknown.
    """
    entry = VERSION_KIND_REGISTRY[kind]
    fname = entry["filenames"][0]
    path = Path(cwd) / fname
    entry["writer"](str(path), new_version)


def get_version_or_die(filepath, kind: str) -> str:
    """Read the version from `filepath` (kind per `infer_version_kind`), or
    print a one-line error to stderr and `sys.exit(1)`. Wraps the per-kind
    parser registered in VERSION_KIND_REGISTRY so release helpers don't have
    to repeat the same try/except dance.

    Error messages:
      - missing file        → "error: <path>: file not found"
      - corrupt JSON / TOML → "error: <path>: <e>"
      - no version field    → "error: <path>: no version field found"
      - unknown kind        → "error: <path>: unknown version kind: <kind>"
    """
    try:
        entry = VERSION_KIND_REGISTRY[kind]
    except KeyError:
        print(f"error: {filepath}: unknown version kind: {kind!r}", file=sys.stderr)
        sys.exit(1)
    try:
        v = entry["parser"](str(filepath))
    except FileNotFoundError:
        print(f"error: {filepath}: file not found", file=sys.stderr)
        sys.exit(1)
    except (json.JSONDecodeError, ValueError) as e:
        print(f"error: {filepath}: {e}", file=sys.stderr)
        sys.exit(1)
    if v is None:
        print(f"error: {filepath}: no version field found", file=sys.stderr)
        sys.exit(1)
    return v


def write_version(filepath, kind: str, new_version: str) -> None:
    """Write `new_version` into the manifest at `filepath` according to `kind`.
    Delegates to the per-kind writer registered in VERSION_KIND_REGISTRY.
    """
    VERSION_KIND_REGISTRY[kind]["writer"](str(filepath), new_version)
