# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv map` adapters.
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


def block_status(out):
    status = out.strip()
    return {"status": status, "changed": status != "unchanged"}


def soft_cap(root):
    cap = 20
    for name in ("config.json", "config.local.json"):
        cfg = read_json_file(os.path.join(root, ".hv", name), {})
        value = (cfg.get("map") or {}).get("softcap_subsystems")
        if isinstance(value, int):
            cap = value
    return cap


@verb("map", "query", repo=False, pos=(1, None))
def map_query(ctx):
    out = call(ctx, "hv-map-query", *ctx.pos)
    return {"text": out}, out


@verb("map", "index", repo=False)
def map_index(ctx):
    out = call(ctx, "hv-map-index")
    return {"key": "map", **block_status(out)}, out


@verb("map", "stats", bools=("cap",), repo=False)
def map_stats(ctx):
    out = call(ctx, "hv-map-stats")
    raw = json_body(out)["subsystems"]
    subsystems = [{"name": s["name"], "bytes": s["bytes"], "touched": s["touched"],
                   "entryPoints": s["entry_points"], "brokenRefs": s["broken_refs"]}
                  for s in raw]
    data, text = {"subsystems": subsystems, "count": len(subsystems)}, out
    if ctx.flags.get("cap"):
        rc, _, err = ctx.helper("hv-map-cap-check")
        if rc != 0:
            raise backend_error(rc, err)
        nudge = [l.strip() for l in err.splitlines() if re.match(r"\s*note: project map has", l)]
        data["cap"] = soft_cap(find_root(ctx.cwd))
        data["overCap"] = bool(nudge)
        ctx.warnings.extend(re.sub(r"^note:\s*", "", n) for n in nudge)
        text = "\n".join(nudge) + ("\n" if nudge else "")
    return data, text
