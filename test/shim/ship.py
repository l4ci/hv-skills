# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv ship` adapters.
import os
import re
import sys

import subprocess

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)
from review import current_branch, git_error, git_out, repo_dir


def read_body(ctx, what):
    """Text of --body-file (`-` is stdin); exit 2 when missing or empty."""
    path = ctx.flags.get("body-file")
    if not path:
        raise usage(f"{ctx.name}: --body-file is required")
    body = sys.stdin.read() if path == "-" else read_text(path)
    if body is None:
        raise usage(f"{ctx.name}: cannot read {path}")
    if not body.strip():
        raise usage(f"{ctx.name}: {what} is empty")
    return body


def need_repo_at_umbrella(ctx):
    """Exit 2 at an umbrella root without --repo (listed before the branch check)."""
    if not ctx.repo and ctx.helper("hv-umbrella-on")[1].strip() == "yes" \
            and not os.path.isdir(os.path.join(ctx.cwd, ".git")):
        raise usage(f"{ctx.name}: umbrella root needs --repo <name>")


def need_branch(ctx, cwd, branch):
    need_repo_at_umbrella(ctx)
    if not git_out(cwd, "rev-parse", "--verify", "--quiet", branch + "^{commit}"):
        raise HvError(3, f"branch '{branch}' not found")


def bare_id(item):
    """`F12` -> `12`, `repo:F12` -> `repo:12` (dual spelling: the letter is `type`)."""
    return re.sub(r"(^|:)[BFT](\d+)$", r"\1\2", item)


@verb("ship", "body", pos=(0, 1))
def ship_body(ctx):
    cwd = repo_dir(ctx)
    branch = ctx.pos[0] if ctx.pos else current_branch(ctx, cwd)
    rc, out, err = ctx.helper("hv-ship-body", branch, cwd=cwd)
    if rc != 0:
        raise git_error(err)
    return {"branch": branch, "body": out}, out


@verb("ship", "pr", values=("title", "body-file", "items"), pos=(1, 1))
def ship_pr(ctx):
    f, branch = ctx.flags, ctx.pos[0]
    if not f.get("title"):
        raise usage(f"{ctx.name}: --title is required")
    body = read_body(ctx, "the PR body")
    cwd = repo_dir(ctx)
    need_branch(ctx, cwd, branch)
    args = (["--repo", ctx.repo] if ctx.repo else []) + (["--closes", f["items"]] if f.get("items") else [])
    rc, out, err = ctx.helper("hv-pr", *args, branch, f["title"], stdin=body)
    if rc == 1:
        if re.search(r"expects PR body|needs --repo|ambiguous|requires --repo|umbrella", err):
            raise HvError(2, first_error_line(err))
        if "no such item" in err:
            raise HvError(3, first_error_line(err))
        raise HvError(5, first_error_line(err) or "hv-pr failed")
    if rc != 0:
        raise HvError({4: 6}.get(rc, 5), first_error_line(err) or f"hv-pr failed (rc {rc})")
    lines = [l for l in out.splitlines() if l.strip()]
    url = lines[-1].strip() if lines else ""
    m = re.search(r"(\d+)/?$", url)
    data = {"branch": branch, "url": url,
            "provider": "gitlab" if "gitlab" in url else "github"}
    if m:
        data["number"] = int(m.group(1))
    data["items"] = [i for i in (f.get("items") or "").split(",") if i]
    data["changed"] = True
    return data, url


@verb("ship", "merge", values=("body-file",), pos=(1, 1))
def ship_merge(ctx):
    branch = ctx.pos[0]
    body = read_body(ctx, "the merge message")
    cwd = repo_dir(ctx)
    need_branch(ctx, cwd, branch)
    rc, base, _ = ctx.helper("hv-base-branch", cwd=cwd)
    base = base.strip()
    if rc == 0 and base == branch:
        raise HvError(4, f"'{branch}' is the base branch",
                      data={"blockedBy": "base branch", "changed": False})
    args = ["--repo", ctx.repo] if ctx.repo else []
    rc, out, err = ctx.helper("hv-merge", *args, branch, stdin=body)
    if rc != 0:
        if re.search(r"requires --repo|umbrella", err):
            raise HvError(2, first_error_line(err))
        if "CONFLICT" in out or "Automatic merge failed" in out + err:
            # Contract: a conflicting merge is aborted, so the tree is left as it was.
            subprocess.run(["git", "merge", "--abort"], cwd=ctx.cwd, capture_output=True)
            raise HvError(4, "merge conflict; merge aborted",
                          data={"blockedBy": "conflict", "changed": False})
        raise HvError(5, first_error_line(err) or f"hv-merge failed (rc {rc})")
    lines = [l for l in out.splitlines() if l.strip()]
    sha = lines[-1].strip()
    return {"branch": branch, "base": base, "sha": sha, "changed": True}, sha


@verb("ship", "pr-merge", values=("items",), pos=(1, 1))
def ship_pr_merge(ctx):
    pr = ctx.pos[0]
    if not pr.isdigit():
        raise usage(f"{ctx.name}: <pr> must be all digits")
    args = [pr] + (["--items", ctx.flags["items"]] if ctx.flags.get("items") else [])
    args += ["--repo", ctx.repo] if ctx.repo else []
    rc, out, err = ctx.helper("hv-pr-merge", *args)
    if rc == 5:
        unproven = re.findall(r"^unproven (\S+?):", err, re.M)
        ids = [bare_id(i) for i in unproven]
        raise HvError(4, "an item has no proof; not merged", data={
            "pr": int(pr), "merged": False, "unproven": ids, "changesRequested": ids,
            "changed": True})
    if rc == 2:
        raise HvError(4, first_error_line(err), hint="use: hv ship merge",
                      data={"blockedBy": "backend", "changed": False})
    if rc == 1:
        msg = first_error_line(err) or "hv-pr-merge failed"
        if re.search(r"usage:|ambiguous|needs --repo|requires --repo", err):
            raise HvError(2, msg)
        if re.search(r"not found|no such|unknown|is not open", err):
            raise HvError(3, msg)
        if re.search(r"\b(pr|mr) merge\b", err):
            # The forge refused the merge itself: the requested outcome didn't happen (4).
            raise HvError(4, msg, data={"pr": int(pr), "merged": False, "unproven": [],
                                        "changesRequested": [], "changed": False})
        raise HvError(5, msg)
    if rc != 0:
        raise HvError({3: 5, 4: 6}.get(rc, 5), first_error_line(err) or f"hv-pr-merge failed (rc {rc})")
    m = re.search(r"^merged \d+ as (\S+)", out, re.M)
    closed = [bare_id(i) for i in re.findall(r"^closed (\S+)", out, re.M)]
    return {"pr": int(pr), "sha": m.group(1) if m else "", "closed": closed, "changed": True}, out


@verb("ship", "undo", values=("cycle",), bools=("allow-post-merge", "apply"))
def ship_undo(ctx):
    f = ctx.flags
    args = (["--cycle", f["cycle"]] if f.get("cycle") else []) \
        + (["--force"] if f.get("apply") else []) \
        + (["--allow-post-merge"] if f.get("allow-post-merge") else [])
    cwd = repo_dir(ctx)
    rc, out, err = ctx.helper("hv-undo", *args, cwd=cwd)
    if rc != 0:
        msg = first_error_line(err) or f"hv-undo failed (rc {rc})"
        if "hv-uncomplete failed" in err:
            # Contract: exit 5 carries no failure data, so the message says what changed.
            head = git_out(cwd, "rev-parse", "--short", "HEAD")
            raise HvError(5, f"the reset already happened (HEAD is now {head}), "
                             f"but restoring an item failed: {msg}")
        if re.search(r"no merge commit found|not a valid commit", err):
            raise HvError(3, msg)
        if re.search(r"unknown flag|unexpected positional|requires a commit hash", err):
            raise usage(msg)
        why = ("not on base branch" if "must run on the base branch" in err else
               "dirty tree" if "uncommitted changes" in err else
               "not a merge" if re.search(r"not a merge|HEAD shape", err) else
               "merge subject" if re.search(r"merge: |not an hv-skills", err) else
               "post-merge commits" if "after the cycle merge" in err else
               "pr mode" if "PR-mode" in err else "refused")
        raise HvError(4, msg, data={"blockedBy": why, "changed": False})
    plan = re.search(r"^Undo plan for last cycle: (\S+)", out, re.M)
    subject = re.search(r"^Subject:\s+(.*)$", out, re.M)
    base = re.search(r"^Base:\s+(\S+)", out, re.M)
    items = re.findall(r"^(?:Items:)?\s+([A-Z]?\d+|[\w.-]+:[BFT]?\d+) will be restored", out, re.M)
    data = {"applied": bool(f.get("apply")), "cycle": plan.group(1) if plan else "",
            "subject": subject.group(1).strip() if subject else "",
            "base": base.group(1) if base else "", "items": items}
    done = re.search(r"^Undone cycle \S+\. Reset \S+ to (\S+)\. Restored: (.*)\.$", out, re.M)
    if f.get("apply") and done:
        restored = done.group(2).strip()
        data["restoredTo"] = done.group(1)
        data["restored"] = [] if restored == "none" else [i.strip() for i in restored.split(",")]
        data["changed"] = True
        return data, done.group(0)
    data["changed"] = False
    ctx.warnings.append("preview only; pass --apply")
    return data, out
