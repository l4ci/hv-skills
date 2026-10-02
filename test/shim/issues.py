# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv issues` adapters.
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


def scope(ctx):
    """The global --repo, in the old helpers' spelling."""
    return ["--repo", ctx.repo] if ctx.repo else []


def issues_error(rc, err):
    """Old issues helpers: rc 1 is a missing or failing CLI, 3 and 4 are hv-tracker-call's."""
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc == 1 and "not found in current repository" in err:
        return HvError(3, msg)
    return HvError({1: 5, 3: 5, 4: 6}.get(rc, 70), msg)


def issue_number(ctx, text):
    if not re.fullmatch(r"\d+", text):
        raise usage(f"{ctx.name}: issue must be a number, got {text!r}")
    return int(text)


@verb("issues", "list", values=("label", "limit"), bools=("mine",))
def issues_list(ctx):
    f = ctx.flags
    args = scope(ctx)
    if f.get("mine"):
        args.append("--mine")
    if "label" in f:
        if not f["label"]:
            raise usage(f"{ctx.name}: --label needs a name")
        args += ["--label", f["label"]]
    if "limit" in f:
        if not re.fullmatch(r"[1-9]\d*", f["limit"]):
            raise usage(f"{ctx.name}: --limit must be a positive number")
        args += ["--limit", f["limit"]]
    rc, out, err = ctx.helper("hv-issues-list", *args)
    if rc != 0:
        raise issues_error(rc, err)
    return {"issues": json_body(out)}, out


@verb("issues", "label", values=("add", "remove"), pos=(1, 1))
def issues_label(ctx):
    f = ctx.flags
    if ("add" in f) == ("remove" in f):
        raise usage(f"{ctx.name}: pass exactly one of --add and --remove")
    action, label = ("add", f["add"]) if "add" in f else ("remove", f["remove"])
    if not label:
        raise usage(f"{ctx.name}: --{action} needs a label name")
    number = issue_number(ctx, ctx.pos[0])
    rc, _, err = ctx.helper("hv-issues-label", "apply" if action == "add" else "remove",
                            "--issue", str(number), "--label", label, *scope(ctx))
    if rc != 0:
        raise issues_error(rc, err)
    return {"issue": number, "label": label, "action": action, "changed": True}, f"{action} {label} on #{number}"


@verb("issues", "imported", values=("for-repo",), bools=("open-only",), repo=False)
def issues_imported(ctx):
    f = ctx.flags
    args = ["--repo", f["for-repo"]] if "for-repo" in f else []
    if f.get("open-only"):
        args.append("--open-only")
    out = call(ctx, "hv-issues-imported", *args)
    entries = [{**{k: v for k, v in e.items() if k != "item_id"}, "itemId": e["item_id"]}
               for e in json_body(out)]
    return {"entries": entries}, out


@verb("issues", "close", values=("commit", "item"), pos=(1, 1))
def issues_close(ctx):
    f = ctx.flags
    if not f.get("commit"):
        raise usage(f"{ctx.name}: --commit is required")
    number = issue_number(ctx, ctx.pos[0])
    args = ["--issue", str(number), "--commit", f["commit"], *scope(ctx)]
    if f.get("item"):
        args += ["--item", f["item"]]
    rc, out, err = ctx.helper("hv-issues-close", *args)
    if rc != 0:
        raise issues_error(rc, err)
    return {"issue": number, "commit": f["commit"], "changed": True}, out or f"closed #{number}"


@verb("issues", "provider")
def issues_provider(ctx):
    out = call(ctx, "hv-issues-provider", *scope(ctx))
    return {"provider": out.strip()}, out
