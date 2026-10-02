# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv spike` adapters (cross-phase verbs).
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("spike", "add", values=("question",), pos=(1, 1))
def spike_add(ctx):
    name, question = ctx.pos[0], ctx.flags.get("question")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
        raise usage(f"{ctx.name}: name must be lowercase alphanumeric + dashes, got '{name}'")
    if not question:
        raise usage(f"{ctx.name}: --question is required")
    # old: hv-spike-add [--repo <repo>] <name> "<question>"
    args = (["--repo", ctx.repo] if ctx.repo else []) + [name, question]
    rc, _, err = ctx.helper("hv-spike-add", *args)
    if rc != 0:
        msg = first_error_line(err)
        if "requires --repo" in err:
            raise usage(msg)
        if "already exists" in err:
            raise HvError(4, msg, data={"blockedBy": "exists", "changed": False})
        raise HvError(5, msg or f"git failed (rc {rc})")
    return {"name": name, "branch": f"spike/{name}", "changed": True}, f"spike/{name}"
