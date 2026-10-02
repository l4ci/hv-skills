# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv version` and `hv update` adapters.
import os

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


def plugin_version(ctx):
    """`version` from plugin.json at the resolved plugin root ("" when none)."""
    root = call(ctx, "hv-resolve-plugin-root", "--root-only").strip()
    if not root:
        return ""
    return read_json_file(os.path.join(root, ".claude-plugin", "plugin.json"), {}).get("version", "") or ""


@verb("version", bools=("drift",), repo=False, root=False)
def version(ctx):
    if not ctx.flags.get("drift"):
        v = plugin_version(ctx)
        return {"version": v}, v
    require_root(ctx)
    d = json_body(call(ctx, "hv-version-check", "--json"))
    data = {"version": d["installed"], "stamped": d["stamped"], "installed": d["installed"],
            "status": d["status"], "drift": d["status"] == "drift"}
    return data, d["status"]


@verb("update", repo=False, root=False)
def update(ctx):
    env = {}
    if os.environ.get("HV_TEST_LATEST_VERSION"):
        env["HV_LATEST_VERSION"] = os.environ["HV_TEST_LATEST_VERSION"]
    out = call(ctx, "hv-update-check", env=env)
    return json_body(out), out
