# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv milestone` adapters (cross-phase verbs).
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

MILESTONE_STATUSES = ("planned", "active", "shipped", "archived")


def tracker_error(rc, err):
    """Old vision helpers: rc 2 and 3 are both 5, rc 4 is 6; rc 1 is a lookup or usage failure."""
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc == 1:
        return HvError(3, msg)
    return HvError({2: 5, 3: 5, 4: 6}.get(rc, 70), msg)


@verb("milestone", "add", values=("title", "summary", "depends"), repo=False)
def milestone_add(ctx):
    f = ctx.flags
    for k in ("title", "summary"):
        if not f.get(k):
            raise usage(f"{ctx.name}: --{k} is required")
    rc, out, err = ctx.helper("hv-vision-add", f["title"], f["summary"], f.get("depends", ""))
    if rc != 0:
        raise tracker_error(rc, err)
    mid = out.strip()
    return {"id": mid, "changed": True}, mid


@verb("milestone", "list", repo=False)
def milestone_list(ctx):
    out = call(ctx, "hv-vision-list")
    return {"milestones": json_body(out)}, out


def milestone_status_line(ctx, mid):
    rc, out, _ = ctx.helper("hv-vision-show", mid)
    m = re.search(r"^status:\s*(\S+)", out, re.M) if rc == 0 else None
    return m.group(1) if m else None


@verb("milestone", "status", values=("to",), pos=(1, 1), repo=False)
def milestone_status(ctx):
    mid, to = ctx.pos[0], ctx.flags.get("to")
    if not re.fullmatch(r"M\d{2,}", mid):
        raise usage(f"{ctx.name}: milestone ID must match M\\d{{2,}}, got '{mid}'")
    if to not in MILESTONE_STATUSES:
        raise usage(f"{ctx.name}: --to must be one of {', '.join(MILESTONE_STATUSES)}")
    before = milestone_status_line(ctx, mid)
    rc, _, err = ctx.helper("hv-vision-status", mid, to)
    if rc != 0:
        raise tracker_error(rc, err)
    # The old helper also runs hv-vision-index on every call; changed compares the status line.
    return {"id": mid, "status": to, "changed": before != to}, f"{mid} status: {to}"
