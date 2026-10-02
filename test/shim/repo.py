# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv repo` adapters.
from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("repo", "which", repo=False, root=False)
def repo_which(ctx):
    rc, out, err = ctx.helper("hv-resolve-repo")
    if rc != 0:
        msg = first_error_line(err) or "not inside a registered sub-repo"
        hint = None
        if "masking" in err:
            hint = f"remove the stray .hv/ at {find_root(ctx.cwd)}/.hv"
        raise HvError(3, msg, hint=hint)
    name = out.strip()
    rc, umb, err = ctx.helper("hv-resolve-umbrella")
    if rc != 0:
        raise HvError(3, first_error_line(err) or "no umbrella found")
    path = call(ctx, "hv-resolve-repo-path", name, cwd=umb.strip()).strip()
    return {"name": name, "path": path}, name


@verb("repo", "resolve", pos=(0, None), repo=False)
def repo_resolve(ctx):
    rc, out, err = ctx.helper("hv-resolve-repos", ",".join(ctx.pos), cwd=find_root(ctx.cwd))
    if rc != 0:
        raise HvError(3, first_error_line(err))
    repos = json_body(out)
    return {"repos": repos}, "\n".join(f"{r['name']}\t{r['path']}" for r in repos)


@verb("repo", "umbrella", repo=False, root=False)
def repo_umbrella(ctx):
    root = find_root(ctx.cwd)
    answer = "no"
    if root is not None:
        answer = call(ctx, "hv-umbrella-on", root, cwd=root).strip()
    if answer == "yes":
        return {"umbrella": True}, "yes"
    raise HvError(1, "not an umbrella project", data={"umbrella": False})
