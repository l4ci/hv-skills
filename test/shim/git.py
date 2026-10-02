# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv git` adapters.
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
