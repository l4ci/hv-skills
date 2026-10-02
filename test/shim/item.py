# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv id` and `hv item` adapters.
import json
import os
import re
import subprocess

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


# ---------------------------------------------------------------- adapters: ids and items

@verb("id", "next", values=("kind",))
def id_next(ctx):
    kind = ctx.flags.get("kind")
    if kind not in KINDS + ("milestones",):
        raise usage(f"{ctx.name}: --kind must be bugs|features|tasks|milestones")
    new_id = call(ctx, "hv-next-id", kind).strip()
    return {"kind": kind, "id": new_id, "changed": True}, new_id


CREATE_FIELDS = {"related": "Related", "milestone": "Milestone", "repos": "Repos",
                 "subsystem": "Subsystem", "captured": "Captured"}


@verb("item", "create",
      values=("kind", "title", "tag", "desc", "body-file", "raw-file", *CREATE_FIELDS))
def item_create(ctx):
    f = ctx.flags
    kind = f.get("kind")
    if kind not in KINDS:
        raise usage(f"{ctx.name}: --kind must be bugs|features|tasks")
    if "raw-file" in f:
        if set(f) - {"kind", "raw-file"}:
            raise usage(f"{ctx.name}: --raw-file takes only --kind")
        path, spool = stdin_to_file(f["raw-file"])
        try:
            # old: hv-append "<section>" "$(cat <file>)" (command substitution strips trailing newlines)
            entry = (read_text(path) or "").rstrip("\n")
        finally:
            if spool:
                os.unlink(spool)
        m = re.search(r"\*\*\[([A-Z]\d+)\]", entry)
        if not m:
            raise usage(f"{ctx.name}: --raw-file bullet needs a **[ID]")
        call(ctx, "hv-append", SECTION[kind], entry)
        return {"id": m.group(1), "type": TYPE_OF_KIND[kind], "kind": kind, "changed": True}, m.group(1)
    if not f.get("title"):
        raise usage(f"{ctx.name}: --title is required")
    tag = f.get("tag", "")
    valid = {"bugs": ("P0", "P1", "P2", "P3"), "features": ("Major", "Minor", "Cosmetic"), "tasks": ()}[kind]
    if tag and tag not in valid:
        raise usage(f"{ctx.name}: --tag for {kind} must be one of {', '.join(valid) or '(none)'}")
    args = [kind, "--title", f["title"]]
    for name, val in (("--tag", tag), ("--desc", f.get("desc", ""))):
        if val:
            args += [name, val]
    path, spool = None, None
    if f.get("body-file"):
        path, spool = stdin_to_file(f["body-file"])
        args += ["--body-file", path]
    for key, label in CREATE_FIELDS.items():
        if f.get(key):
            args += ["--field", f"{label}={f[key]}"]
    try:
        rc, out, err = ctx.helper("hv-item-create", *args)
    finally:
        if spool:
            os.unlink(spool)
    if rc != 0:
        e = backend_error(rc, err)
        raise HvError(2 if e.exit == 3 and "cannot read" in e.message else e.exit, e.message)
    new_id = out.strip()
    data = {"id": new_id, "type": TYPE_OF_KIND[kind], "kind": kind, "changed": True}
    if f.get("body-file"):
        data["detail"] = f".hv/{kind}/{new_id}.md"
    return data, new_id


@verb("item", "complete", values=("commit", "reason", "note"), bools=("no-proof",), pos=(1, 1))
def item_complete(ctx):
    f, item = ctx.flags, ctx.pos[0]
    reason = f.get("reason", "done")
    if reason not in ("done", "handed-off", "blocked", "dropped"):
        raise usage(f"{ctx.name}: --reason must be done|handed-off|blocked|dropped")
    commit = f.get("commit")
    if not commit:
        proc = subprocess.run(["git", "log", "-1", "--format=%h"], cwd=ctx.cwd,
                              capture_output=True, text=True)
        commit = proc.stdout.strip()
        if not commit:
            raise HvError(5, "git has no HEAD to default --commit", hint="pass --commit <hash>")
    args = [item, commit, "--reason", reason]
    if f.get("note"):
        args += ["--note", f["note"]]
    if f.get("no-proof"):
        args.append("--no-proof")
    root = find_root(ctx.cwd)
    backlog = os.path.join(root, ".hv", "BACKLOG.md")
    before = read_text(backlog)
    rc, _, err = ctx.helper("hv-complete", *args)
    if rc == 3 and "no proof recorded" in err:
        raise HvError(4, first_error_line(err), hint="record proof with `hv proof add`, or pass --no-proof",
                      data={"blockedBy": "proof missing", "changed": False})
    if rc != 0:
        raise backend_error(rc, err)
    # File backend: an already-completed item is a silent no-op that leaves BACKLOG.md untouched.
    changed = True if before is None else read_text(backlog) != before
    return ({"id": item, "type": item_type(item), "reason": reason, "commit": commit,
             "changed": changed},
            f"completed {item} ({reason}) at {commit}")


GET_FIELDS = ("title", "detail", "related", "milestone", "repos", "subsystem", "since", "reason", "note")
SET_FIELDS = ("milestone", "related", "repos", "subsystem", "detail")


def field_name(ctx, allowed, what):
    name = ctx.flags.get("name")
    if not name:
        raise usage(f"{ctx.name}: --name is required")
    if name not in allowed:
        raise usage(f"{ctx.name}: {what} field {name}; pick one of {', '.join(allowed)}")
    return name


@verb("item", "field", "get", values=("name",), pos=(1, 1))
def item_field_get(ctx):
    item = ctx.pos[0]
    name = field_name(ctx, GET_FIELDS, "unknown")
    value = call(ctx, "hv-todo-field", item, name)[:-1]
    return {"id": item, "type": item_type(item), "field": name, "value": value}, value


@verb("item", "field", "list", pos=(1, 1))
def item_field_list(ctx):
    item = ctx.pos[0]
    fields = json_body(call(ctx, "hv-todo-field", "--dump", item))
    return {"id": item, "type": item_type(item), "fields": fields}, json.dumps(fields)


@verb("item", "field", "set", values=("name", "value"), pos=(1, 1))
def item_field_set(ctx):
    item = ctx.pos[0]
    name = field_name(ctx, SET_FIELDS, "unknown or read-only")
    if "value" not in ctx.flags:
        raise usage(f"{ctx.name}: --value is required (--value '' clears the field)")
    value = ctx.flags["value"]
    backlog = os.path.join(find_root(ctx.cwd), ".hv", "BACKLOG.md")
    before = read_text(backlog)
    rc, _, err = ctx.helper("hv-todo-set-field", item, name, value)
    if rc == 1 and "no open bullet" in err:
        known = ctx.helper("hv-todo-field", item, "title")[0] == 0
        raise HvError(4 if known else 3, first_error_line(err),
                      data={"blockedBy": "closed item", "changed": False} if known else None)
    if rc == 1 and "detail" in err:
        raise usage(first_error_line(err))
    if rc != 0:
        raise backend_error(rc, err)
    # File backend: an unchanged value leaves BACKLOG.md byte-identical.
    changed = True if before is None else read_text(backlog) != before
    return {"id": item, "type": item_type(item), "field": name, "value": value,
            "changed": changed}, value
