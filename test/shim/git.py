# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv git` adapters.
import re
import subprocess

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("git", "guard", "clean", values=("context",))
def guard_clean(ctx):
    f = ctx.flags
    rc, _, err = ctx.helper("hv-guard-clean", f.get("context", "this command"))
    if rc == 0:
        return {"clean": True, "greenfield": False, "dirtyRepos": []}, "clean"
    if rc == 2:
        raise HvError(3, first_error_line(err))
    dirty = [l.strip() for l in err.splitlines() if l.startswith("  ") and "git add" not in l]
    raise HvError(1, first_error_line(err), data={
        "clean": False, "greenfield": "fresh repo (no commits yet)" in err,
        "dirtyRepos": dirty if "sub-repo" in err else []})


def git_dir(ctx):
    """The directory a scoped git verb runs in: --repo's checkout, else the cwd."""
    if ctx.repo is None:
        return ctx.cwd
    return call(ctx, "hv-resolve-repo-path", ctx.repo, cwd=find_root(ctx.cwd)).strip()


def umbrella_error(err):
    return "umbrella" in err


@verb("git", "base")
def git_base(ctx):
    rc, out, err = ctx.helper("hv-base-branch", cwd=git_dir(ctx))
    if rc != 0:
        raise HvError(2 if umbrella_error(err) else 3, first_error_line(err))
    base = out.strip()
    return {"base": base}, base


@verb("git", "guard", "feature-branch", pos=(0, 1))
def guard_feature_branch(ctx):
    cwd = git_dir(ctx)
    branch = ctx.pos[0] if ctx.pos else None
    rc, _, err = ctx.helper("hv-guard-feature-branch", *ctx.pos, cwd=cwd)
    if rc == 1 and umbrella_error(err):
        raise HvError(2, first_error_line(err))
    if branch is None:
        head = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd,
                              capture_output=True, text=True).stdout.strip()
        branch = head if head not in ("", "HEAD") else None
    data = {"feature": rc == 0}
    if branch:
        data["branch"] = branch
    _, base, _ = ctx.helper("hv-base-branch", cwd=cwd)
    if base.strip():
        data["base"] = base.strip()
    if rc == 0:
        return data, "feature branch"
    data["reason"] = "detached" if "detached HEAD" in err else "base"
    raise HvError(1, first_error_line(err), data=data)


@verb("git", "branch", values=("repos",), pos=(1, 1), repo=False)
def git_branch(ctx):
    name, repos = ctx.pos[0], ctx.flags.get("repos", "")
    if not repos.strip() or re.search(r"\s", repos) or "" in repos.split(","):
        raise usage(f"{ctx.name}: --repos needs a comma-separated list of repo names")
    root = find_root(ctx.cwd)
    rc, out, err = ctx.helper("hv-multi-branch-create", "--branch", name, "--repos", repos, cwd=root)
    msg = first_error_line(err)
    if rc == 0:
        names = repos.split(",")
        return {"branch": name, "repos": names, "changed": True}, name
    if "already exists in:" in err:
        raise HvError(4, msg, data={"blockedBy": "exists", "changed": False})
    if "failed to create" in err:
        raise HvError(5, msg)
    if "unregistered" in err or rc == 1 and "usage:" not in err:
        raise HvError(3, msg)
    raise usage(msg)


@verb("git", "worktree-path", pos=(1, 1))
def git_worktree_path(ctx):
    if ctx.repo is None:
        raise usage(f"{ctx.name}: --repo is required")
    rc, out, err = ctx.helper("hv-worktree-path", "--repo", ctx.repo, ctx.pos[0])
    if rc != 0:
        raise HvError(2 if "usage:" in err else 3, first_error_line(err))
    path = out.strip()
    return {"path": path}, path
