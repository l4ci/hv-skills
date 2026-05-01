"""Shared utilities for hv-* helpers. Imported by python3 heredocs in bin/.

Loaded via PYTHONPATH = $(dirname "$0") set by the bash wrapper. Do NOT import
this from outside bin/. The functions here are stdlib-only and side-effect-free
(except dump_json_atomic / update_json, which write).
"""
import json
import os
import re
from pathlib import Path


def find_section(content: str, name: str) -> tuple[int, int] | None:
    """Locate the body of ## <name> in `content`. Return (start, end) byte
    offsets — both into `content`, body excludes the heading line itself,
    end is the start of the next ## heading or len(content) if none.
    Returns None if the heading is missing.
    """
    m = re.search(rf"^## {re.escape(name)}\s*$", content, re.MULTILINE)
    if not m:
        return None
    start = m.end()
    nxt = re.search(r"^## ", content[start:], re.MULTILINE)
    end = start + nxt.start() if nxt else len(content)
    return (start, end)


def section(content: str, name: str) -> str:
    """Return the body of ## <name>, or '' if missing."""
    span = find_section(content, name)
    return content[span[0]:span[1]] if span else ""


def load_json(path, default):
    """Read JSON from `path`. Return `default` if the file is missing or corrupt.
    Never raises. `path` may be a str or Path.
    """
    p = Path(path)
    if not p.exists():
        return default
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return default


def dump_json_atomic(path, data) -> None:
    """Write `data` as pretty JSON to `path` atomically (tmp + os.replace).
    The tmp file is in the same directory as `path`. Trailing newline preserved.
    """
    p = Path(path)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, p)


def update_json(path, default, mutator) -> None:
    """Read JSON at `path` (with `default` fallback), pass it to mutator(),
    then atomically write the result. mutator may mutate in place and return None,
    or return a new object — both work.
    """
    data = load_json(path, default)
    result = mutator(data)
    dump_json_atomic(path, data if result is None else result)
