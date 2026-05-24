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


def load_sidecar(path, schema_version: int = 1, default=None):
    """Load a JSON sidecar with mandatory schema-version checking.

    Returns the parsed dict on success. If the file is missing, returns
    `default` (defaulting to `{"version": schema_version}` shape —
    callers pass whatever bare-bones default they need).

    Raises ValueError with the standard message
    "<basename>.json schema version mismatch — expected <N>, got <M>"
    when the loaded `version` field doesn't match `schema_version`. Files
    without a `version` field are treated as schema_version (legacy data
    auto-tagged on first write).
    """
    p = Path(path)
    if not p.exists():
        return default if default is not None else {"version": schema_version}
    data = json.loads(p.read_text())
    got = data.get("version")
    if got is not None and got != schema_version:
        name = p.name
        raise ValueError(
            f"{name} schema version mismatch — expected {schema_version}, got {got}"
        )
    if got is None:
        data["version"] = schema_version
    return data


def update_json(path, default, mutator) -> None:
    """Read JSON at `path` (with `default` fallback), pass it to mutator(),
    then atomically write the result. mutator may mutate in place and return None,
    or return a new object — both work.
    """
    data = load_json(path, default)
    result = mutator(data)
    dump_json_atomic(path, data if result is None else result)


def _deep_merge(base, override):
    """Recursively merge override into base. Nested dicts merge by key;
    scalars, lists, and type mismatches use the override value.
    Returns a new dict — does not mutate inputs.
    """
    if not isinstance(base, dict) or not isinstance(override, dict):
        return override
    out = dict(base)
    for k, v in override.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config(config_path=".hv/config.json", default=None):
    """Read project config with optional per-developer local overrides.

    Reads `config_path` (default `.hv/config.json`) and deep-merges
    `<dirname>/config.local.json` on top when present. The local file is
    gitignored — it carries per-developer or per-machine overrides
    (typically `autonomy.level`, model preferences) without touching the
    shared committed config.

    Both files are JSON objects. Nested keys merge recursively; scalars
    and arrays in the local file replace the base entirely.

    `default` (when both files are missing or corrupt) defaults to `{}`.
    Never raises.
    """
    if default is None:
        default = {}
    p = Path(config_path)
    base = load_json(p, default)
    local = load_json(p.parent / "config.local.json", None)
    if local is None:
        return base
    return _deep_merge(base, local)
