"""File-IO primitives for hv-* helpers. Pure stdlib, no hvlib dependencies.

Re-exported by hvlib for backward compat: existing `from hvlib import load_json`
imports continue to work.
"""
import json
import os
from pathlib import Path


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


def read_or_empty(path) -> str:
    """Read a file's text, or return '' if it doesn't exist.
    `path` may be a str or os.PathLike. Never raises on missing file.
    """
    try:
        return Path(path).read_text()
    except FileNotFoundError:
        return ""


def write_text_atomic(path, text: str) -> None:
    """Write `text` to `path` atomically (tmp + os.replace). Trailing
    newline is the caller's responsibility. `path` may be a str or Path.
    """
    p = Path(path)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, p)


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
