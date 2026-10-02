# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv status` adapters.
import os

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


# ---------------------------------------------------------------- adapters: status

@verb("status", "add", values=("items", "worktree", "repos", "worktrees"), bools=("if-absent",),
      pos=(1, 1))
def status_add(ctx):
    f, branch = ctx.flags, ctx.pos[0]
    if not f.get("items"):
        raise usage(f"{ctx.name}: --items is required")
    multi = "repos" in f
    if multi and ctx.repo is not None:
        raise usage(f"{ctx.name}: --repo and --repos are mutually exclusive")
    if ("worktree" in f) == multi and ("worktree" in f or "worktrees" in f):
        raise usage(f"{ctx.name}: use --worktree with one repo, --worktrees with --repos")
    root = find_root(ctx.cwd)
    if multi:
        names = [n.strip() for n in f["repos"].split(",") if n.strip()]
        if "worktrees" in f and len([w for w in f["worktrees"].split(",")]) != len(names):
            raise usage(f"{ctx.name}: --worktrees must list one path per --repos name")
        rc, _, err = ctx.helper("hv-resolve-repos", f["repos"], cwd=root)
        if rc != 0:
            raise HvError(3, err.strip())
        scope = names
    else:
        scope = [ctx.repo]
    matching = lambda: [e for e in status_entries(root)
                        if e.get("branch") == branch and (e.get("repo") or None) in scope]
    existing = len(matching())
    flag = ["--if-absent"] if f.get("if-absent") else []
    if multi:
        args = [*flag, "--branch", branch, "--items", f["items"], "--repos", f["repos"]]
        if "worktrees" in f:
            args += ["--worktrees", f["worktrees"]]
        call(ctx, "hv-status-add-multi", *args)
    else:
        args = [*flag, *(["--repo", ctx.repo] if ctx.repo else []), branch, f["items"]]
        if f.get("worktree"):
            args.append(f["worktree"])
        call(ctx, "hv-status-add", *args)
    entries = [{"repo": e.get("repo") or None, "items": e.get("items") or [],
                "worktree": e.get("worktree") or None, "startedAt": e.get("startedAt", "")}
               for e in matching()]
    changed = not (f.get("if-absent") and existing == len(scope))
    return {"branch": branch, "entries": entries, "changed": changed}, f"active: {branch}"


@verb("status", "rm", pos=(1, 1))
def status_rm(ctx):
    branch = ctx.pos[0]
    root = find_root(ctx.cwd)
    suffix = f"@{ctx.repo}" if ctx.repo else ""
    handoff = os.path.join(root, ".hv", "handoff", f"{branch}{suffix}.md")
    mine = lambda: [e for e in status_entries(root)
                    if e.get("branch") == branch and (e.get("repo") or None) == ctx.repo]
    before, had_handoff = len(mine()), os.path.exists(handoff)
    call(ctx, "hv-status-remove", *(["--repo", ctx.repo] if ctx.repo else []), branch)
    removed = before - len(mine())
    swept = had_handoff and not os.path.exists(handoff)
    return ({"branch": branch, "removed": removed, "handoffRemoved": swept,
             "changed": removed > 0 or swept}, f"removed {branch}")


@verb("status", "show", pos=(1, 1))
def status_show(ctx):
    branch = ctx.pos[0]
    root = find_root(ctx.cwd)
    entry = next((e for e in status_entries(root) if e.get("branch") == branch
                  and (ctx.repo is None or e.get("repo") == ctx.repo)), None)
    if entry is None:
        return {"branch": branch, "active": False, "repo": None, "items": [],
                "worktree": None}, f"{branch}: not active"
    data = {"branch": branch, "active": True, "repo": entry.get("repo") or None,
            "items": entry.get("items") or [], "worktree": entry.get("worktree") or None}
    if entry.get("startedAt"):
        data["startedAt"] = entry["startedAt"]
    return data, f"{branch}: active"


@verb("status", "handoff", bools=("canonical",), pos=(1, 1))
def status_handoff(ctx):
    branch = ctx.pos[0]
    root = find_root(ctx.cwd)
    args = [*(["--repo", ctx.repo] if ctx.repo else []),
            *(["--write"] if ctx.flags.get("canonical") else []), branch]
    out = call(ctx, "hv-resolve-handoff", *args, cwd=root).strip()
    path = out or None
    return ({"branch": branch, "path": path,
             "exists": bool(path) and os.path.exists(os.path.join(root, path))}, out)


def loop_stamp(ctx, sub):
    return call(ctx, "hv-loop-stamp", sub, cwd=find_root(ctx.cwd)).strip()


@verb("status", "loop", "start", repo=False)
def status_loop_start(ctx):
    was_set = bool(loop_stamp(ctx, "read"))
    loop_stamp(ctx, "start")
    stamp = loop_stamp(ctx, "read")
    return {"loopStartedAt": stamp, "changed": not was_set}, stamp


@verb("status", "loop", "clear", repo=False)
def status_loop_clear(ctx):
    was_set = bool(loop_stamp(ctx, "read"))
    loop_stamp(ctx, "clear")
    return {"changed": was_set}, "cleared"


@verb("status", "loop", "show", repo=False)
def status_loop_show(ctx):
    stamp = loop_stamp(ctx, "read")
    return {"loopStartedAt": stamp or None}, stamp
