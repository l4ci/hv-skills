# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv debug counter` adapters (cross-phase verbs).
import json
import os
import subprocess

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

HELPER = "hv-debug-counter"


def session_file(ctx):
    """(session, state file) as the old helper derives them: current branch, `/` -> `-`."""
    root = find_root(ctx.cwd)
    proc = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root, capture_output=True, text=True)
    branch = proc.stdout.strip() if proc.returncode == 0 else ""
    if not branch:
        raise HvError(5, "hv debug counter must be run from within a git repository")
    session = branch.replace("/", "-")
    return session, os.path.join(root, ".hv", "debug", f"{session}.json")


def state(path):
    return read_json_file(path, None)


def run(ctx, *args):
    """Run the old helper; map its failures onto the contract's exits."""
    rc, out, err = ctx.helper(HELPER, *args)
    if rc == 0:
        return out
    msg = first_error_line(err) or f"{HELPER} failed (rc {rc})"
    if "no debug session file" in err:
        raise HvError(3, msg, hint="hv debug counter init <bugId>")
    if "git repository" in err or "current git branch" in err:
        raise HvError(5, msg)
    if "no attempts recorded" in err or "not 'pending'" in err:
        raise HvError(4, msg, data={"blockedBy": "no pending attempt", "changed": False})
    if "usage:" in err or "unknown subcommand" in err:
        raise usage(msg)
    raise HvError(70, msg)


def need_state(path):
    d = state(path)
    if d is None:
        raise HvError(3, f"no debug session file at {path}", hint="hv debug counter init <bugId>")
    return d


@verb("debug", "counter", "init", pos=(1, 1), repo=False)
def counter_init(ctx):
    session, path = session_file(ctx)
    existed = os.path.exists(path)
    run(ctx, "init", ctx.pos[0])
    return {"session": session, "bugId": ctx.pos[0], "changed": not existed}, session


@verb("debug", "counter", "record-attempt", values=("hypothesis", "commit"), repo=False)
def counter_record(ctx):
    f = ctx.flags
    for k in ("hypothesis", "commit"):
        if not f.get(k):
            raise usage(f"{ctx.name}: --{k} is required")
    session_file(ctx)
    n = run(ctx, "record-attempt", "--hypothesis", f["hypothesis"], "--commit", f["commit"]).strip()
    return {"attempt": int(n), "changed": True}, n


@verb("debug", "counter", "fail", repo=False)
def counter_fail(ctx):
    session_file(ctx)
    n = run(ctx, "fail").strip()
    return {"failedFixes": int(n), "changed": True}, n


@verb("debug", "counter", "pass", repo=False)
def counter_pass(ctx):
    _, path = session_file(ctx)
    run(ctx, "pass")
    attempts = (state(path) or {}).get("attempts") or [{}]
    return {"attempt": attempts[-1].get("n", len(attempts)), "changed": True}, "passed"


def camel(a):
    out = {"n": a.get("n"), "startedAt": a.get("started_at", ""), "hypothesis": a.get("hypothesis", ""),
           "commit": a.get("commit", ""), "outcome": a.get("outcome", "")}
    if "ended_at" in a:
        out["endedAt"] = a["ended_at"]
    return out


@verb("debug", "counter", "show", repo=False)
def counter_show(ctx):
    _, path = session_file(ctx)
    d = need_state(path)
    return ({"session": d.get("session", ""), "bugId": d.get("bug_id", ""), "startedAt": d.get("started_at", ""),
             "failedFixes": d.get("failed_fixes", 0), "hypothesisCycles": d.get("hypothesis_cycles", 0),
             "attempts": [camel(a) for a in d.get("attempts", [])]}, read_text(path))


@verb("debug", "counter", "summary", repo=False)
def counter_summary(ctx):
    _, path = session_file(ctx)
    d = need_state(path)
    data = {"bugId": d.get("bug_id", ""), "failedFixes": d.get("failed_fixes", 0), "markdown": ""}
    if not d.get("attempts"):
        raise HvError(1, "no attempts recorded", data=data)
    data["markdown"] = run(ctx, "summary").rstrip("\n")
    return data, data["markdown"]


@verb("debug", "counter", "clear", repo=False)
def counter_clear(ctx):
    _, path = session_file(ctx)
    existed = os.path.exists(path)
    run(ctx, "clear")
    return {"changed": existed}, "cleared"


@verb("debug", "counter", "inc-cycle", repo=False)
def counter_inc(ctx):
    session_file(ctx)
    n = run(ctx, "inc-cycle").strip()
    return {"hypothesisCycles": int(n), "changed": True}, n
