# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv plan` adapters (cross-phase verbs).
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("plan", "add", values=("title", "design", "repos", "milestone"), bools=("slice",),
      pos=(0, 1), repo=False)
def plan_add(ctx):
    f = ctx.flags
    slice_mode = bool(f.get("slice"))
    if ctx.pos and (slice_mode or "milestone" in f):
        raise usage(f"{ctx.name}: a key cannot be combined with --slice or --milestone")
    if slice_mode and not f.get("milestone"):
        raise usage(f"{ctx.name}: --slice needs --milestone")
    if not ctx.pos and not slice_mode:
        raise usage(f"{ctx.name}: give a <milestone>-<unit> key, or --milestone <M01> --slice")
    if not f.get("title"):
        raise usage(f"{ctx.name}: --title is required")
    if slice_mode:
        milestone, unit = f["milestone"], "slice"
    else:
        milestone, sep, unit = ctx.pos[0].partition("-")
        if not sep or not unit:
            raise usage(f"{ctx.name}: key must look like M01-B07, got '{ctx.pos[0]}'")
    args = []
    if f.get("repos"):
        args += ["--repo", ", ".join(n.strip() for n in f["repos"].split(",") if n.strip())]
    if f.get("design"):
        if not re.fullmatch(r"[BFT]\d{2,}", f["design"]):
            raise usage(f"{ctx.name}: --design must be an item ID like B07, got '{f['design']}'")
        args += ["--design", f".hv/designs/{f['design']}.md"]
    rc, out, err = ctx.helper("hv-plan-add", *args, milestone, unit, f["title"])
    if rc != 0:
        msg = first_error_line(err)
        if "already exists" in err:
            raise HvError(4, msg, data={"blockedBy": "exists", "changed": False})
        if re.search(r"design file not found|not in \.hv/repos\.json|not found", err):
            raise HvError(3, msg)
        if rc == 1 and not re.search(r"usage:|must look like|must be|empty after parsing", err):
            raise HvError(3, msg)   # issue mode: milestone has no tracker
        if rc == 1:
            raise usage(msg)
        raise backend_error(rc, err)
    key = out.strip()
    kind = "slice" if unit == "slice" or re.fullmatch(r"S\d+", unit) else "item"
    return {"key": key, "unitKind": kind, "changed": True}, key
