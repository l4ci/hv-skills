# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv instructions` adapters (A5).
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("instructions", "init", repo=False)
def instructions_init(ctx):
    rc, out, err = ctx.helper("hv-instructions-init")
    if rc != 0:
        raise HvError(70, first_error_line(err) or f"old helper failed (rc {rc})")
    actions = []
    for line in out.splitlines():
        line = line.strip()
        if m := re.match(r"created: (\S+)$", line):
            actions.append({"action": "created", "file": m.group(1)})
        elif m := re.match(r"moved: (.+?) → (\S+)$", line):
            actions.append({"action": "moved", "file": m.group(2),
                            "keys": [k.strip() for k in m.group(1).split(",")]})
        elif m := re.match(r"linked: (\S+) → @", line):
            actions.append({"action": "linked", "file": m.group(1)})
        elif m := re.match(r"note: (\S+) is a symlink", line):
            actions.append({"action": "skippedSymlink", "file": m.group(1)})
    return {"actions": actions, "changed": any(a["action"] != "skippedSymlink" for a in actions)}, out
