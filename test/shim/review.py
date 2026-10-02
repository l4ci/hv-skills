# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv review` adapters.
import re
import subprocess

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


# ---------------------------------------------------------------- shared with ship.py

def repo_dir(ctx):
    """Directory of the repo the verb acts on: the --repo sub-repo, else the cwd."""
    if ctx.repo:
        return call(ctx, "hv-resolve-repo-path", ctx.repo, cwd=find_root(ctx.cwd)).strip()
    return ctx.cwd


def git_out(cwd, *args):
    proc = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def current_branch(ctx, cwd):
    branch = git_out(cwd, "rev-parse", "--abbrev-ref", "HEAD")
    if not branch or branch == "HEAD":
        raise HvError(3, "no branch given and HEAD is not on a branch")
    return branch


def git_error(err):
    """Old rc 1 from a branch-reading helper -> contract exit, split by message."""
    msg = first_error_line(err) or "old helper failed"
    if "umbrella" in err:
        return HvError(2, msg)
    if "not found" in err:
        return HvError(3, msg)
    if re.search(r"against itself|no commits (between|beyond)", err):
        return HvError(1, msg)
    return HvError(5, msg)


def run_branch_helper(ctx, helper, args, repo_flag=True):
    """Run a helper with the global --repo as its old first argument."""
    full = (["--repo", ctx.repo] if ctx.repo and repo_flag else []) + args
    rc, out, err = ctx.helper(helper, *full)
    if rc == 0:
        return out
    if rc == 1 or rc == 2:
        raise git_error(err)
    raise HvError(5, first_error_line(err) or f"{helper} failed (rc {rc})")


# ---------------------------------------------------------------- adapters: review

@verb("review", "scope", pos=(0, 1))
def review_scope(ctx):
    out = run_branch_helper(ctx, "hv-review-scope", ctx.pos[:1])
    data = json_body(out)
    for intent in data.get("intents", []):
        intent["type"] = item_type(intent["id"])
    return data, out


@verb("review", "brief", pos=(0, 1))
def review_brief(ctx):
    branch = ctx.pos[0] if ctx.pos else current_branch(ctx, repo_dir(ctx))
    brief = run_branch_helper(ctx, "hv-second-opinion-brief", [branch])
    scope = json_body(run_branch_helper(ctx, "hv-review-scope", [branch]))
    return {"branch": branch, "base": scope["base"], "commitCount": scope["commitCount"],
            "brief": brief}, brief


@verb("review", "scaffolding", values=("base",), pos=(0, 1))
def review_scaffolding(ctx):
    cwd = repo_dir(ctx)
    base = ctx.flags.get("base")
    if not base:
        rc, out, _ = ctx.helper("hv-base-branch", cwd=cwd)
        base = out.strip() if rc == 0 and out.strip() else "main"
    branch = ctx.pos[0] if ctx.pos else current_branch(ctx, cwd)
    for ref in (base, branch):
        if not git_out(cwd, "rev-parse", "--verify", "--quiet", ref + "^{commit}"):
            if ctx.helper("hv-umbrella-on", cwd=cwd)[1].strip() == "yes" and not ctx.repo:
                raise usage(f"{ctx.name}: umbrella root needs --repo <name>")
            raise HvError(3, f"{ref}: no such branch")
    out = run_branch_helper(ctx, "hv-review-scaffolding", [base, branch])
    findings = []
    for line in out.splitlines():
        parts = line.split(":", 2)
        if len(parts) == 3 and parts[1].isdigit():
            findings.append({"file": parts[0], "line": int(parts[1]), "text": parts[2]})
    return {"findings": findings}, out


@verb("review", "queue")
def review_queue(ctx):
    rc, out, err = ctx.helper("hv-review-queue")
    if rc == 0 and "file backend has no review queue" in err:
        raise HvError(4, "review queue needs backlog.backend issues",
                      data={"blockedBy": "backend", "changed": False})
    if rc != 0:
        if rc == 1 and "usage:" in err:
            raise HvError(2, first_error_line(err))
        raise HvError({3: 5, 4: 6}.get(rc, 5), first_error_line(err) or f"old helper failed (rc {rc})")
    items = []
    for row in json_body(out):
        m = re.match(r"^(?:(.*):)?([BFT])(\d+)$", row["id"])
        if not m:
            raise HvError(70, f"unexpected queue id {row['id']!r}")
        repo = row.get("repo") or m.group(1)
        if ctx.repo and repo != ctx.repo:
            continue
        item = {"id": (f"{repo}:" if repo else "") + m.group(3), "type": m.group(2),
                "number": row["number"], "title": row["title"]}
        if repo:
            item["repo"] = repo
        item["prs"] = row["prs"]
        items.append(item)
    return {"items": items}, "\n".join(f"{i['type']}{i['number']} {i['title']}" for i in items)
