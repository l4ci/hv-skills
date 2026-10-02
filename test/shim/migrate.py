# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv migrate` adapters (`migrate issues`; `migrate v4` is A5).
import hashlib
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

# (line prefix, action, keep the prefix in `text`). `set` covers old's `set milestone … status …`
# and `set plan body …` lines.
OPS = (("create milestone ", "create-milestone", False), ("create issue ", "create-issue", False),
       ("note ", "note", False), ("rewrite ", "rewrite", False), ("skip ", "skip", False),
       ("set ", "set", False))
ITEM_ID = re.compile(r"[BFT]\d+$")


def digest(*paths):
    h = hashlib.md5()
    for p in paths:
        h.update((read_text(p) or "").encode())
    return h.hexdigest()


def open_item_total(root):
    """Open bullets under Bugs, Features and Tasks, which is what the old helper migrates."""
    total, live = 0, False
    for line in (read_text(os.path.join(root, ".hv", "BACKLOG.md")) or "").splitlines():
        if line.startswith("## "):
            live = line[3:].strip() in ("Bugs", "Features", "Tasks")
        elif live and re.match(r"- \*\*\[[BFT]\d+\]", line):
            total += 1
    return total


@verb("migrate", "issues", values=("limit",), bools=("apply",), repo=False)
def migrate_issues(ctx):
    f = ctx.flags
    apply = bool(f.get("apply"))
    if "limit" in f and not f["limit"].isdigit():
        raise usage(f"{ctx.name}: --limit must be a number")
    root = find_root(ctx.cwd)
    mapfile = os.path.join(root, ".hv", "issue-map.json")
    state = lambda: digest(mapfile, os.path.join(root, ".hv", "BACKLOG.md"))
    total = open_item_total(root)
    before = state()
    args = ["--apply" if apply else "--dry-run"]
    if "limit" in f:
        args += ["--limit", f["limit"]]
    rc, out, err = ctx.helper("hv-migrate-issues", *args)
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc != 0:
        if rc == 1 and "umbrella mode" in err:
            raise HvError(4, msg, data={"blockedBy": "umbrella", "changed": False})
        if rc == 1 and "nothing to migrate" in err:
            raise HvError(3, msg)
        if rc == 4:
            m = re.search(r"rate limited: (\d+) of (\d+) items migrated", out)
            raise HvError(6, f"{m.group(1)} of {m.group(2)} migrated" if m else msg)
        if rc in (1, 3) and (rc == 3 or "stopped on a tracker error" in out):
            # Exit 5 carries no failure data, so the message ends with the saved progress.
            done = read_json_file(mapfile, {})
            n = sum(1 for k, v in done.items() if ITEM_ID.match(k) and v.get("id"))
            raise HvError(5, f"{msg}; {n} of {total} migrated")
        raise HvError(2 if rc == 1 else 70, msg)
    for line in err.splitlines():
        if line.startswith("warning:"):
            ctx.warnings.append(re.sub(r"^warning:\s*(hv-[\w-]+:\s*)?", "", line.strip()))
    ops, imap = [], None
    lines = out.splitlines()
    for i, line in enumerate(lines):
        if line == "would-be map:":
            imap = json_body("\n".join(lines[i + 1:]))
            break
        for prefix, action, keep in OPS:
            if line.startswith(prefix):
                ops.append({"action": action, "text": line if keep else line[len(prefix):]})
                break
    if imap is None:
        imap = read_json_file(mapfile, {})
    done = read_json_file(mapfile, {})
    migrated = sum(1 for k, v in done.items() if ITEM_ID.match(k) and v.get("id"))
    if not apply:
        ctx.warnings.append("preview only; pass --apply")
    data = {"applied": apply, "operations": ops, "map": imap, "migrated": migrated,
            "total": total, "changed": apply and state() != before}
    return data, out
