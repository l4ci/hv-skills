# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv worker pool` and `hv worker reset` adapters.
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

SLOT_FIELDS = ("name", "branch", "worktree", "base", "handle", "state", "task", "pr",
               "relays", "configDir", "account")


def registry_path(root):
    return os.path.join(root, ".hv", "workers.json")


def read_registry(root):
    return read_json_file(registry_path(root), {})


def slot_data(slot):
    """A registry slot as contract `slot` data: null fields are absent, relays always present."""
    out = {k: slot[k] for k in SLOT_FIELDS if slot.get(k) is not None}
    out.setdefault("relays", [])
    return out


def warnings_from(ctx, err):
    for line in err.splitlines():
        m = re.match(r"\s*(?:warning|note):\s*(.*\S)", line)
        if m:
            ctx.warnings.append(m.group(1))


# ---------------------------------------------------------------- adapters: pool

@verb("worker", "pool", "init", values=("slots", "base", "session"), repo=False)
def pool_init(ctx):
    f = ctx.flags
    if not f.get("slots"):
        raise usage(f"{ctx.name}: --slots is required")
    if not re.fullmatch(r"[0-9]+", f["slots"]) or int(f["slots"]) < 1:
        raise usage(f"{ctx.name}: --slots must be a positive integer")
    root = find_root(ctx.cwd)
    args = ["init", "--slots", f["slots"]]
    for flag in ("base", "session"):
        if f.get(flag):
            args += [f"--{flag}", f[flag]]
    before = read_text(registry_path(root))
    rc, _, err = ctx.helper("hv-worker-pool", *args, cwd=root)
    if rc != 0:
        msg = first_error_line(err) or f"hv-worker-pool failed (rc {rc})"
        if rc == 2:
            raise usage(msg)
        # A base that cannot be resolved, or a registry path that is not ours, is a
        # resolution failure; every other rc 3 is git failing.
        if re.search(r"base branch|cannot resolve|another repository", err):
            raise HvError(3, msg)
        raise HvError(5, msg)
    warnings_from(ctx, err)
    reg = read_registry(root)
    slots = [slot_data(s) for s in reg.get("slots", [])]
    base = f.get("base") or (slots[0]["base"] if slots else "")
    return ({"session": reg.get("session") or f.get("session") or "hv", "base": base,
             "slots": slots, "changed": read_text(registry_path(root)) != before},
            "\n".join(s["name"] for s in slots))


@verb("worker", "pool", "list", repo=False)
def pool_list(ctx):
    root = find_root(ctx.cwd)
    rc, out, err = ctx.helper("hv-worker-pool", "list", "--json", cwd=root)
    if rc != 0:
        raise HvError(5, first_error_line(err) or f"hv-worker-pool failed (rc {rc})")
    reg = json_body(out) if out.strip() else {}
    data = {"slots": [slot_data(s) for s in reg.get("slots", [])]}
    if reg.get("session"):
        data["session"] = reg["session"]
    if reg.get("round") is not None:
        data["round"] = reg["round"]
    text = "\n".join(f"{s['name']} {s.get('state', '')} {s.get('branch', '')} {s.get('worktree', '')}"
                     for s in data["slots"])
    return data, text


@verb("worker", "pool", "reap", bools=("all",), pos=(0, None), repo=False)
def pool_reap(ctx):
    slots, every = ctx.pos, bool(ctx.flags.get("all"))
    if bool(slots) == every:
        raise usage(f"{ctx.name}: give one or more slots, or --all (not both)")
    root = find_root(ctx.cwd)
    held = [s.get("name") for s in read_registry(root).get("slots", [])]
    reaped = held if every else [s for s in dict.fromkeys(slots) if s in held]
    calls = [["--all"]] if every else [["--slot", s] for s in slots]
    for args in calls:
        rc, _, err = ctx.helper("hv-worker-pool", "reap", *args, cwd=root)
        if rc != 0:
            raise HvError(5, first_error_line(err) or f"hv-worker-pool failed (rc {rc})")
    return {"reaped": reaped, "changed": bool(reaped)}, "\n".join(reaped)


# ---------------------------------------------------------------- adapters: reset

def refusal_blocks(err):
    """The `dirty` and `unmerged` lists from the REFUSED stderr block."""
    out, section = {}, None
    for line in err.splitlines():
        if line.startswith("REFUSED"):
            section = "dirty" if "uncommitted changes" in line else "unmerged"
            out[section] = []
        elif section and line.startswith("  "):
            out[section].append(line[2:])
        else:
            section = None
    return out


@verb("worker", "reset", values=("task",), bools=("check-only",), pos=(1, 1), repo=False)
def worker_reset(ctx):
    slot, check = ctx.pos[0], bool(ctx.flags.get("check-only"))
    root = find_root(ctx.cwd)
    args = ["--slot", slot] + (["--task", ctx.flags["task"]] if ctx.flags.get("task") else []) \
        + (["--check-only"] if check else [])
    rc, out, err = ctx.helper("hv-worker-reset", *args, cwd=root)
    if rc == 0:
        if re.search(r"^retry: ", out, re.M):
            return ({"slot": slot, "clean": False, "retained": True, "changed": False}, out)
        data = {"slot": slot, "clean": True, "retained": False, "changed": not check}
        m = re.search(r"^reset: \S+ on (\S+) at (\S+)", out, re.M)
        if m:
            base = next((s.get("base") for s in read_registry(root).get("slots", [])
                         if s.get("name") == slot), None)
            data.update({"branch": m.group(1), "sha": m.group(2)})
            if base:
                data["base"] = base
        return data, out
    msg = first_error_line(err) or f"hv-worker-reset failed (rc {rc})"
    if rc == 2:
        raise usage(msg)
    if "REFUSED" in err:
        blocks = refusal_blocks(err)
        data = {"slot": slot, "clean": False, "retained": False, **blocks, "changed": False}
        if check:
            raise HvError(1, f"slot {slot} holds work", data=data)
        raise HvError(4, f"slot {slot} holds work", data={**data, "blockedBy": "slot holds work"})
    if "could not cut" in err:
        raise HvError(5, msg)
    raise HvError(3, msg)
