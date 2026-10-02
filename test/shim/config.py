# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv config` adapters.
import json
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

SHOW_LINE = re.compile(r"^(\S+) = (.*)  \(source: (local|project|default)\)$")


def show_rows(ctx, *args):
    """Parse hv-config-show's `key = value  (source: x)` lines."""
    out = call(ctx, "hv-config-show", *args)
    rows = []
    for line in out.splitlines():
        m = SHOW_LINE.match(line)
        if m:
            rows.append({"key": m.group(1), "value": json.loads(m.group(2)), "source": m.group(3)})
    return rows


def lookup(cfg, key):
    """(found, value) for a dotted key in a config dict."""
    cur = cfg
    for seg in key.split("."):
        if not isinstance(cur, dict) or seg not in cur:
            return False, None
        cur = cur[seg]
    return True, cur


@verb("config", "show", pos=(0, 1))
def config_show(ctx):
    rc, out, err = ctx.helper("hv-config-show", *ctx.pos)
    if rc != 0:
        if "unknown key" in err:
            raise HvError(3, first_error_line(err))
        raise HvError(2 if "usage:" in err else 70, first_error_line(err))
    rows = []
    for line in out.splitlines():
        m = SHOW_LINE.match(line)
        if m:
            rows.append({"key": m.group(1), "value": json.loads(m.group(2)), "source": m.group(3)})
    return {"entries": rows}, out


@verb("config", "set", pos=(2, 2))
def config_set(ctx):
    key, raw = ctx.pos
    if not key or any(seg == "" for seg in key.split(".")):
        raise usage(f"{ctx.name}: malformed key path {key!r}")
    if key not in [r["key"] for r in show_rows(ctx)]:
        raise usage(f"{ctx.name}: unknown key {key!r} (not in the config schema)")
    root = find_root(ctx.cwd)
    path = os.path.join(root, ".hv", "config.json")
    before = read_json_file(path, {})
    had, previous = lookup(before, key)
    # The old helper's `${2:?}` rejects an empty value; a JSON literal stores the same string.
    rc, _, err = ctx.helper("hv-config-set", key, raw if raw != "" else '""')
    if rc != 0:
        if "malformed key path" in err or "usage:" in err:
            raise usage(first_error_line(err))
        raise HvError(70, first_error_line(err))
    after = read_json_file(path, {})
    _, value = lookup(after, key)
    data = {"key": key, "value": value, "changed": after != before}
    if had:
        data["previous"] = previous
    return data, f"{key} = {json.dumps(value)}"


@verb("config", "check")
def config_check(ctx):
    out = call(ctx, "hv-config-schema-check").strip()
    if out == "UP_TO_DATE":
        return {"status": "upToDate", "upToDate": True, "missing": []}, "up to date"
    if out == "FRESH":
        status, missing = "fresh", []
    elif out == "CORRUPT":
        status, missing = "corrupt", []
    elif out.startswith("STALE:"):
        status, missing = "stale", [k for k in out[len("STALE:"):].split(",") if k]
    else:
        raise HvError(70, f"unexpected schema-check output: {out!r}")
    raise HvError(1, f"config is {status}", data={"status": status, "upToDate": False,
                                                  "missing": missing})
