# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv worker dispatch|poll|session` adapters.
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

# Old exit 3 messages that name a missing thing (the contract keeps these at 3);
# every other old exit 3 is a host or git failure (5).
MISSING = re.compile(r"no worker pool|not in the pool|worktree missing|no session to relay"
                     r"|does not exist|not found")


def workers_file(root):
    return os.path.join(root, ".hv", "workers.json")


def registry(root):
    return read_json_file(workers_file(root), {})


def body_file(ctx, path, required=True):
    """The --body-file as a path the old helper can read, plus a spool file to delete."""
    if path == "-":
        return stdin_to_file(path)
    full = path if os.path.isabs(path) else os.path.join(ctx.cwd, path)
    if not os.path.isfile(full):
        raise HvError(3, f"body file not found: {path}")
    return full, None


# ---------------------------------------------------------------- dispatch

def dispatch_error(rc, err):
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc == 2:
        if "reopens the previous conversation" in err:
            return HvError(4, msg, data={"blockedBy": "resume flag", "changed": False})
        return HvError(2, msg)
    if rc == 3:
        if "REFUSED" in err:
            return HvError(4, "slot holds work; reset refused",
                           data={"blockedBy": "reset guard", "changed": False})
        if MISSING.search(err):
            return HvError(3, msg)
        return HvError(5, msg)
    if rc == 4:
        return HvError(6, msg, hint="the brief was never submitted; safe to resend")
    if rc == 5:
        return HvError(5, msg, hint="a dialog refused input; inspect the pane before resending")
    return HvError(70, msg)


@verb("worker", "dispatch", values=("body-file", "task", "round", "boot-timeout"),
      bools=("relay",), pos=(1, 1), repo=False)
def worker_dispatch(ctx):
    f, slot = ctx.flags, ctx.pos[0]
    if not f.get("body-file"):
        raise usage(f"{ctx.name}: --body-file is required")
    if "round" in f and not f["round"].isdigit():
        raise usage(f"{ctx.name}: --round must be a number")
    path, spool = body_file(ctx, f["body-file"])
    try:
        args = ["--slot", slot, "--brief-file", path]
        for flag in ("task", "round", "boot-timeout"):
            if flag in f:
                args += [f"--{flag}", f[flag]]
        if f.get("relay"):
            args.append("--relay")
        rc, out, err = ctx.helper("hv-worker-dispatch", *args)
    finally:
        if spool:
            os.unlink(spool)
    if rc != 0:
        raise dispatch_error(rc, err)
    m = re.search(r"dispatched: \S+ \((.*)\)", out)
    data = {"slot": slot, "handle": m.group(1) if m else ""}
    if f.get("task"):
        data["task"] = f["task"]
    if "round" in f:
        data["round"] = int(f["round"])
    data["relay"] = bool(f.get("relay"))
    data["changed"] = True
    return data, out.strip()


# ---------------------------------------------------------------- poll

@verb("worker", "poll", values=("settle", "lines"), pos=(0, 1), repo=False)
def worker_poll(ctx):
    f = ctx.flags
    slot = ctx.pos[0] if ctx.pos else None
    root = find_root(ctx.cwd)
    fixture = os.environ.get("HV_TEST_POLL_FIXTURE")
    args = []
    if fixture:
        args += ["--fixture", fixture]
        if os.environ.get("HV_TEST_POLL_STATUS"):
            args += ["--status", os.environ["HV_TEST_POLL_STATUS"]]
    if slot:
        args += ["--slot", slot]
    for flag in ("settle", "lines"):
        if flag in f:
            args += [f"--{flag}", f[flag]]
    before = read_text(workers_file(root))
    rc, out, err = ctx.helper("hv-worker-poll", *args)
    if rc != 0:
        msg = first_error_line(err) or f"old helper failed (rc {rc})"
        raise HvError({2: 2, 3: 5}.get(rc, 70), msg)
    if slot and not fixture and not any(s.get("name") == slot
                                        for s in registry(root).get("slots", [])):
        raise HvError(3, f"slot '{slot}' is not in the pool")
    rows = [{"name": r["name"], "state": r["state"].lower(), "evidence": r["evidence"]}
            for r in json_body(out)]
    changed = read_text(workers_file(root)) != before
    text = "\n".join(f"{r['name']}\t{r['state']}\t{r['evidence']}" for r in rows)
    return {"slots": rows, "changed": changed}, text


# ---------------------------------------------------------------- session

@verb("worker", "session", "check", values=("session",), repo=False)
def session_check(ctx):
    args = ["--session", ctx.flags["session"]] if "session" in ctx.flags else []
    rc, out, err = ctx.helper("hv-worker-session", "check", *args)
    if rc == 0:
        where = re.sub(r"^inside\s*", "", out.strip())
        data = {"inside": True}
        if where:
            data["where"] = where
        return data, out.strip()
    if rc == 1:
        raise HvError(1, "outside a managed host session", data={"inside": False})
    raise HvError({2: 2, 3: 5}.get(rc, 70), first_error_line(err) or f"old helper failed (rc {rc})")


@verb("worker", "session", "ensure", values=("session", "body-file", "boot-timeout"), repo=False)
def session_ensure(ctx):
    f = ctx.flags
    args = []
    if "session" in f:
        args += ["--session", f["session"]]
    if "boot-timeout" in f:
        args += ["--boot-timeout", f["boot-timeout"]]
    spool = None
    try:
        if f.get("body-file"):
            path, spool = body_file(ctx, f["body-file"])
            args += ["--instruction-file", path]
        rc, out, err = ctx.helper("hv-worker-session", "ensure", *args)
    finally:
        if spool:
            os.unlink(spool)
    if rc != 0:
        msg = first_error_line(err) or f"old helper failed (rc {rc})"
        if rc == 2:
            raise HvError(2, msg)
        if rc == 3:
            if "inside a herdr pane" in err:
                raise HvError(4, msg, data={"blockedBy": "outside herdr", "changed": False})
            raise HvError(5, msg)
        raise HvError(70, msg)
    m = re.search(r"^handed off to tmux session '([^']*)'", out, re.M)
    if m:
        return {"inside": False, "handedOff": True, "session": m.group(1), "changed": True}, out.strip()
    where = re.sub(r"^inside\s*", "", out.strip())
    where = re.sub(r"\s*\S\s*no handoff needed$", "", where)
    data = {"inside": True}
    if where:
        data["where"] = where
    data.update({"handedOff": False, "changed": False})
    return data, out.strip()
