# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv spike` adapters (cross-phase verbs).
import os
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


SPIKE_NAME = re.compile(r"[a-z0-9][a-z0-9-]*")


def spike_name(ctx):
    name = ctx.pos[0]
    if not SPIKE_NAME.fullmatch(name):
        raise usage(f"{ctx.name}: name must be lowercase alphanumeric + dashes, got '{name}'")
    return name


@verb("spike", "finish", pos=(1, 1), repo=False)
def spike_finish(ctx):
    name = spike_name(ctx)
    root = find_root(ctx.cwd)
    text = read_text(os.path.join(root, ".hv", "spikes", f"{name}.md"))
    if text is None:
        raise HvError(3, f".hv/spikes/{name}.md not found")
    if re.search(r"^status:\s*done\s*$", text, re.M):
        return {"name": name, "status": "done", "changed": False}, f"{name}: done"
    rc, _, err = ctx.helper("hv-spike-finish", name)
    if rc != 0:
        raise HvError(70, first_error_line(err) or f"hv-spike-finish failed (rc {rc})")
    return {"name": name, "status": "done", "changed": True}, f"{name}: done"


@verb("spike", "list", repo=False)
def spike_list(ctx):
    out = call(ctx, "hv-spike-list")
    spikes = []
    for s in json_body(out):
        if not s.get("repo"):
            s.pop("repo", None)
        spikes.append(s)
    return {"spikes": spikes}, out


@verb("spike", "show", pos=(1, 1), repo=False)
def spike_show(ctx):
    name = spike_name(ctx)
    rc, out, err = ctx.helper("hv-spike-show", name)
    if rc != 0:
        raise HvError(3, first_error_line(err))
    return {"name": name, "body": out}, out
