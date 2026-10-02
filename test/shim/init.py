# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv init` adapters. They act on the working directory with no walk-up.
import os

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

CORE_FILES = ("DECISIONS.md", "BACKLOG.md", "KNOWLEDGE.md", "MILESTONES.md",
              "counters.json", "config.json", "status.json")


def snapshot(cwd):
    """`find .hv .gitignore`, as a set of paths relative to cwd."""
    found = set()
    for top in (".hv", ".gitignore"):
        full = os.path.join(cwd, top)
        if os.path.exists(full):
            found.add(top)
        for d, dirs, files in os.walk(full):
            for n in dirs + files:
                found.add(os.path.relpath(os.path.join(d, n), cwd))
    return found


def stderr_lines(err, prefix):
    """Lines of stderr starting with `prefix:`, without it."""
    return [l.strip()[len(prefix) + 1:].strip() for l in err.splitlines()
            if l.strip().startswith(prefix + ":")]


@verb("init", repo=False, root=False)
def init(ctx):
    before = snapshot(ctx.cwd)
    rc, _, err = ctx.helper("hv-bootstrap")
    if rc != 0:
        raise HvError(70, first_error_line(err) or "seeding .hv/ failed")
    created = sorted(snapshot(ctx.cwd) - before)
    return {"root": ctx.cwd, "created": created, "changed": bool(created)}, ctx.cwd


@verb("init", "check", repo=False, root=False)
def init_check(ctx):
    rc, _, err = ctx.helper("hv-preflight")
    if rc == 2:
        if not os.path.isdir(os.path.join(ctx.cwd, ".hv")):
            missing = [".hv"]
        else:
            missing = [f".hv/{f}" for f in CORE_FILES
                       if not os.path.isfile(os.path.join(ctx.cwd, ".hv", f))]
        raise HvError(1, "not initialized", data={"initialized": False, "missing": missing})
    # rc 3 is the old helper-mirror check, which 5.0 drops.
    for line in err.splitlines():
        line = line.strip()
        if line and not line.startswith("stale:"):
            ctx.warnings.append(line[len("warn:"):].strip() if line.startswith("warn:") else line)
    return {"initialized": True, "missing": []}, "initialized"


@verb("init", "umbrella", values=("repos",), bools=("all",), repo=False, root=False)
def init_umbrella(ctx):
    f = ctx.flags
    if ("repos" in f) == bool(f.get("all")):
        raise usage(f"{ctx.name}: pass exactly one of --repos or --all")
    children = [n for n in os.listdir(ctx.cwd)
                if not n.startswith(".") and os.path.isdir(os.path.join(ctx.cwd, n))
                and os.path.exists(os.path.join(ctx.cwd, n, ".git"))]
    if not children:
        raise HvError(3, "no immediate git children found")
    registry = os.path.join(ctx.cwd, ".hv", "repos.json")
    before, reg_before = snapshot(ctx.cwd), read_text(registry)
    rc, _, err = ctx.helper("hv-bootstrap")
    if rc != 0:
        raise HvError(70, first_error_line(err) or "seeding .hv/ failed")
    value = "all" if f.get("all") else (f["repos"] or "none")
    rc, out, err = ctx.helper("hv-umbrella-init", stdin=value + "\n")
    if rc != 0:
        raise HvError(70, first_error_line(err))
    ctx.warnings.extend(stderr_lines(err, "warning"))
    summary = json_body(out)
    created = sorted(snapshot(ctx.cwd) - before)
    changed = bool(created) or read_text(registry) != reg_before
    return ({"root": ctx.cwd, "created": created, "registered": summary["registered"],
             "umbrellaIsGitRepo": summary["umbrellaIsGitRepo"], "changed": changed},
            ", ".join(summary["registered"]))
