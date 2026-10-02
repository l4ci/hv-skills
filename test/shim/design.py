# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv design` adapters (cross-phase verbs).
import json
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)
from item import ident, issue_mode, type_of

DESIGN_HINT = "create it with hv design add"


def check_id(ctx, item):
    """The contract's ID shape: `[BFT]\\d{2,}` in file mode, `[BFT]\\d+` in issue mode."""
    if issue_mode(ctx):
        ok = re.fullmatch(r"(?:[\w.-]+:)?[BFT]\d+", item)
    else:
        ok = re.fullmatch(r"[BFT]\d{2,}", item)
    if not ok:
        raise usage(f"{ctx.name}: ID must match [BFT]\\d{{2,}} (e.g. B07, F03, T11), got '{item}'")


def design_error(rc, err):
    """Old design helper failure -> HvError (contract exits: 2 usage, 3 missing, 4 exists, 5/6 tracker)."""
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc == 1:
        if "already exists" in err:
            return HvError(4, msg, data={"blockedBy": "exists", "changed": False})
        if re.search(r"must match|usage:|cannot read --body-file|unknown argument", err):
            return HvError(2, msg)
        hint = DESIGN_HINT if "not found" in err and "hv-design-add" in err else None
        return HvError(3, msg, hint=hint)
    return {2: HvError(5, msg), 3: HvError(5, msg), 4: HvError(6, msg)}.get(rc) or HvError(70, msg)


def call_design(ctx, helper, *args, **kw):
    rc, out, err = ctx.helper(helper, *args, **kw)
    if rc != 0:
        raise design_error(rc, err)
    return out


def show_text(ctx, item):
    rc, out, _ = ctx.helper("hv-design-show", item)
    return out if rc == 0 else None


def body_text(ctx):
    """--body-file as (path for the old helper, spool to delete)."""
    given = ctx.flags.get("body-file")
    if not given:
        raise usage(f"{ctx.name}: --body-file is required")
    path, spool = stdin_to_file(given if given == "-" else os.path.join(ctx.cwd, given))
    if read_text(path) is None:
        raise usage(f"{ctx.name}: cannot read --body-file: {given}")
    return path, spool


def mutated(ctx, item, extra=None):
    iid, itype = ident(ctx, item)
    data = {"id": iid, "type": itype}
    data.update(extra or {})
    return data


@verb("design", "add", values=("title",), pos=(1, 1), repo=False)
def design_add(ctx):
    item = ctx.pos[0]
    check_id(ctx, item)
    if not ctx.flags.get("title"):
        raise usage(f"{ctx.name}: --title is required")
    call_design(ctx, "hv-design-add", item, ctx.flags["title"])
    return mutated(ctx, item, {"changed": True}), item


@verb("design", "list", repo=False)
def design_list(ctx):
    rc, out, err = ctx.helper("hv-design-list")
    if rc == 2:
        raise HvError(4, first_error_line(err), data={"blockedBy": "backend", "changed": False})
    if rc != 0:
        raise design_error(rc, err)
    return {"designs": json_body(out)}, out


@verb("design", "show", pos=(1, 1), repo=False)
def design_show(ctx):
    item = ctx.pos[0]
    check_id(ctx, item)
    body = call_design(ctx, "hv-design-show", item)
    return mutated(ctx, item, {"body": body}), body


@verb("design", "put", values=("body-file",), pos=(1, 1), repo=False)
def design_put(ctx):
    item = ctx.pos[0]
    check_id(ctx, item)
    path, spool = body_text(ctx)
    try:
        before = show_text(ctx, item)
        call_design(ctx, "hv-design-put", item, "--body-file", path)
        after = show_text(ctx, item)
    finally:
        if spool:
            os.unlink(spool)
    return mutated(ctx, item, {"changed": before != after}), f"design {item} stored"


@verb("design", "rm", pos=(1, 1), repo=False)
def design_rm(ctx):
    item = ctx.pos[0]
    check_id(ctx, item)
    iid_type = None
    if issue_mode(ctx):
        iid_type = ident(ctx, item)
    call_design(ctx, "hv-design-rm", item)
    iid, itype = iid_type or (item, type_of(ctx, item))
    return {"id": iid, "type": itype, "changed": True}, f"design {item} removed"


@verb("design", "amend", values=("section", "mode", "body-file"), pos=(1, 1), repo=False)
def design_amend(ctx):
    item, f = ctx.pos[0], ctx.flags
    check_id(ctx, item)
    if not f.get("section"):
        raise usage(f"{ctx.name}: --section is required")
    if f.get("mode") not in ("append", "replace"):
        raise usage(f"{ctx.name}: --mode must be append or replace")
    path, spool = body_text(ctx)
    try:
        text = read_text(path)
        if issue_mode(ctx):
            raise HvError(4, "design amend is file-only; the backlog backend is issues",
                          data={"blockedBy": "backend", "changed": False})
        before = show_text(ctx, item)
        call_design(ctx, "hv-design-amend", item, "--section", f["section"], f"--{f['mode']}", text)
        after = show_text(ctx, item)
    finally:
        if spool:
            os.unlink(spool)
    return (mutated(ctx, item, {"section": f["section"], "mode": f["mode"], "changed": before != after}),
            f"design {item} amended")
