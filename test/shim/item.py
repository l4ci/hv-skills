# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv id` and `hv item` adapters.
import json
import os
import re
import subprocess

import core
from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

RESOLUTION = re.compile(r"not found|unknown|no such|mismatch|not an open item|does not exist|no open bullet|cannot read"
                        r"|needs a target sub-repo|belongs to .*, not |sub-repo|registered:")


def backend_error(rc, err):
    """core.backend_error, plus: an rc 1 that is neither usage nor a missing item is a tracker failure (5)."""
    e = core.backend_error(rc, err)
    if rc == 1 and e.exit == 3 and not RESOLUTION.search(err) and err.strip():
        return HvError(5, e.message)
    return e


def call(ctx, helper, *args, **kw):
    rc, out, err = ctx.helper(helper, *args, **kw)
    if rc != 0:
        raise backend_error(rc, err)
    return out


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
        rc, _, err = ctx.helper("hv-append", SECTION[kind], entry)
        if rc != 0:
            raise refusal(rc, err)
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
        if key in f and not f[key].strip():
            raise usage(f"{ctx.name}: --{key} needs a value")
        if f.get(key):
            args += ["--field", f"{label}={f[key]}"]
    try:
        rc, out, err = ctx.helper("hv-item-create", *args)
    finally:
        if spool:
            os.unlink(spool)
    if rc != 0:
        e = backend_error(rc, err)
        raise HvError(e.exit, e.message, data=e.data)  # unreadable --body-file stays 3 (resolution)
    new_id = out.strip()
    # Issue mode prints `B12`; rule 11 drops the letter (`type` keeps it). The detail file keeps it.
    shown = strip_letter(new_id) if issue_mode(ctx) else new_id
    data = {"id": shown, "type": TYPE_OF_KIND[kind], "kind": kind, "changed": True}
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
    was_closed, issues = False, issue_mode(ctx)
    if issues:
        rc0, shown, _ = ctx.helper("hv-item-show", item)
        was_closed = rc0 == 0 and bool(re.search(r"^status:\s*closed", shown, re.M))
    rc, _, err = ctx.helper("hv-complete", *args)
    if rc == 3 and "no proof recorded" in err:
        raise HvError(4, first_error_line(err), hint="record proof with `hv proof add`, or pass --no-proof",
                      data={"blockedBy": "proof missing", "changed": False})
    if rc != 0:
        raise backend_error(rc, err)
    # File backend: an already-completed item is a silent no-op that leaves BACKLOG.md untouched.
    changed = (not was_closed) if issues else True if before is None else read_text(backlog) != before
    iid, itype = ident(ctx, item)
    return ({"id": iid, "type": itype, "reason": reason, "commit": commit,
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
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "field": name, "value": value}, value


@verb("item", "field", "list", pos=(1, 1))
def item_field_list(ctx):
    item = ctx.pos[0]
    fields = json_body(call(ctx, "hv-todo-field", "--dump", item))
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "fields": fields}, json.dumps(fields)


@verb("item", "field", "set", values=("name", "value"), pos=(1, 1))
def item_field_set(ctx):
    item = ctx.pos[0]
    name = field_name(ctx, SET_FIELDS, "unknown or read-only")
    if "value" not in ctx.flags:
        raise usage(f"{ctx.name}: --value is required (--value '' clears the field)")
    value = ctx.flags["value"]
    if name == "detail" and issue_mode(ctx):
        # The issues backend has no detail files; refuse before any tracker call.
        raise HvError(4, "--name detail is file-only (the issues backend has no detail files)",
                      data={"blockedBy": "backend", "changed": False})
    backlog = os.path.join(find_root(ctx.cwd), ".hv", "BACKLOG.md")
    before = read_text(backlog)
    rc, _, err = ctx.helper("hv-todo-set-field", item, name, value)
    if rc == 1 and "no open bullet" in err:
        known = ctx.helper("hv-todo-field", item, "title")[0] == 0
        raise HvError(4 if known else 3, first_error_line(err),
                      data={"blockedBy": "closed item", "changed": False} if known else None)
    if rc == 1 and "is not an open item" in err:
        known = ctx.helper("hv-item-show", item)[0] == 0
        raise HvError(4 if known else 3, first_error_line(err),
                      data={"blockedBy": "closed item", "changed": False} if known else None)
    if rc == 1 and "does not exist" in err:
        raise HvError(3, first_error_line(err))
    if rc == 1 and "detail" in err:
        raise usage(first_error_line(err))
    if rc != 0:
        raise backend_error(rc, err)
    # File backend: an unchanged value leaves BACKLOG.md byte-identical.
    changed = True if before is None else read_text(backlog) != before
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "field": name, "value": value,
            "changed": changed}, value


def issue_mode(ctx):
    """True under `backlog.backend` issues (old: `python3 -m hvlib_backend is-issues`)."""
    env = dict(os.environ, PYTHONPATH=helpers_dir() + os.pathsep + os.environ.get("PYTHONPATH", ""))
    return subprocess.run(["python3", "-m", "hvlib_backend", "is-issues"], cwd=find_root(ctx.cwd) or ctx.cwd, env=env,
                          capture_output=True).returncode == 0


def type_of(ctx, item):
    """`type` letter of an item: from its ID, else (issue mode, bare number) from hv-item-show."""
    t = item_type(item)
    if t:
        return t
    rc, out, _ = ctx.helper("hv-item-show", item)
    m = re.search(r"^type:\s*(bug|feature|task)", out, re.M) if rc == 0 else None
    return {"bug": "B", "feature": "F", "task": "T"}[m.group(1)] if m else None


def strip_letter(canon):
    """Rule 11: the backend's `B12` / `repo:B12` becomes `12` / `repo:12`."""
    return re.sub(r"(^|[:#])[BFT](?=\d+$)", lambda m: ":" if m.group(1) == "#" else m.group(1), canon)


CANON = """
import sys
from hvlib_backend import get_backend
b = get_backend()
ref = sys.argv[1]
if hasattr(b, "_pick"):
    sub, plain = b._pick(ref)
    cid = sub.canonical_id(plain)
    print(f"{sub.repo}:{cid}" if cid else "")
else:
    print(b.canonical_id(ref) or "")
"""


def ident(ctx, item):
    """(`id` spelling, `type`) for an item's data object: file mode echoes the argument,
    issue mode gives the backend's canonical id without the type letter (`repo:12` in an
    umbrella, `12` otherwise; `T1`, `#1` and `1` all give `12`)."""
    itype = type_of(ctx, item)
    if not issue_mode(ctx):
        return item, itype
    env = dict(os.environ, PYTHONPATH=helpers_dir() + os.pathsep + os.environ.get("PYTHONPATH", ""))
    proc = subprocess.run(["python3", "-c", CANON, item], cwd=find_root(ctx.cwd) or ctx.cwd, env=env,
                          capture_output=True, text=True)
    canon = proc.stdout.strip() if proc.returncode == 0 else ""
    if canon:
        return strip_letter(canon), itype or item_type(canon)
    m = re.match(r"^(?:([^:#]+)[:#])?#?[BFT]?(\d+)$", item)
    if not m:
        return item, itype
    return (f"{m.group(1)}:{m.group(2)}" if m.group(1) else m.group(2)), itype


STATES = ("in-progress", "needs-review", "changes-requested", "none")


@verb("item", "state", values=("to",), pos=(1, 1))
def item_state(ctx):
    item, to = ctx.pos[0], ctx.flags.get("to")
    if to not in STATES:
        raise usage(f"{ctx.name}: --to must be one of {', '.join(STATES)}")
    if not issue_mode(ctx) and ctx.helper("hv-todo-field", item, "title")[0] != 0:
        # The old helper is a silent no-op on the file backend; the contract says 3.
        raise HvError(3, f"item {item} not found")
    rc, _, err = ctx.helper("hv-item-state", item, to)
    if rc != 0:
        raise backend_error(rc, err)
    # File backend: silent no-op, so nothing changed. Issue mode cannot tell if the label matched.
    iid, itype = ident(ctx, item)
    return ({"id": iid, "type": itype, "state": None if to == "none" else to,
             "changed": issue_mode(ctx)}, f"{item} state: {to}")


@verb("item", "reopen", pos=(1, 1))
def item_reopen(ctx):
    item = ctx.pos[0]
    rc, _, err = ctx.helper("hv-uncomplete", item)
    if rc != 0:
        raise backend_error(rc, err)
    iid, itype = ident(ctx, item)
    return ({"id": iid, "type": itype, "changed": "already active" not in err},
            f"reopened {item}")


# ---------------------------------------------------------------- adapters: show, claims, notes, comments

def refusal(rc, err, hint=None):
    """backend_error, plus the contract's default exit-4 data for `backend` refusals."""
    e = backend_error(rc, err)
    if e.exit == 4:
        e.hint = e.hint or hint
        e.data = {"blockedBy": "backend", "changed": False}
    return e


def run(ctx, helper, *args, hint=None, **kw):
    """Run an old helper; stdout on rc 0, else raise via refusal()."""
    rc, out, err = ctx.helper(helper, *args, **kw)
    if rc != 0:
        raise refusal(rc, err, hint)
    return out


def known_in_file_mode(ctx, item):
    """Old claim/release/state are silent no-ops on the file backend; the contract wants 3 for an unknown item."""
    if not issue_mode(ctx) and ctx.helper("hv-todo-field", item, "title")[0] != 0:
        raise HvError(3, f"item {item} not found")


def csv_list(value):
    return [] if value == "none" else [v.strip() for v in value.split(",") if v.strip()]


COMMENT_ROW = re.compile(r"^- (.*?) · (\w+) · (.*)$")


def parse_comment_rows(lines):
    """Rows `- <who> · <kind> · <text>`; indented lines continue the previous text."""
    rows = []
    for line in lines:
        m = COMMENT_ROW.match(line)
        if m and not line.startswith(" "):
            rows.append({"who": m.group(1), "kind": m.group(2), "text": m.group(3)})
        elif rows:
            rows[-1]["text"] += "\n" + (line[2:] if line.startswith("  ") else line)
    for r in rows:
        r["text"] = r["text"].rstrip("\n")
    return rows


@verb("item", "show", pos=(1, 1))
def item_show(ctx):
    out = run(ctx, "hv-item-show", ctx.pos[0])
    lines = out.split("\n")
    head = re.match(r"^\[(.+?)\] (.*)$", lines[0])
    fixed = {}
    for line in lines[1:9]:
        key, _, val = line.partition(": ")
        fixed[key] = val
    none = lambda v: None if v in ("", "none") else v
    return ({"id": strip_letter(head.group(1)), "type": fixed["type"][0].upper(), "title": head.group(2),
             "status": fixed["status"], "state": none(fixed["state"]), "claimedBy": none(fixed["claimed by"]),
             "assignees": csv_list(fixed["assignee"]), "milestone": none(fixed["milestone"]),
             "notes": csv_list(fixed["notes"]), "comments": parse_comment_rows(lines[9:])}, out)


def claim_id(ctx):
    as_ = ctx.flags.get("as")
    if as_ is None:
        raise usage(f"{ctx.name}: --as is required")
    if not as_ or re.search(r"\s", as_) or "-->" in as_:
        raise usage(f"{ctx.name}: --as must be non-empty with no whitespace and no -->")
    return as_


@verb("item", "claim", values=("as",), pos=(1, 1))
def item_claim(ctx):
    item, as_ = ctx.pos[0], claim_id(ctx)
    known_in_file_mode(ctx, item)
    rc, out, err = ctx.helper("hv-item-claim", item, "--as", as_)
    if rc == 5:
        raise HvError(4, first_error_line(err), data={"blockedBy": "claimed", "changed": True})
    if rc != 0:
        raise refusal(rc, err)
    iid, itype = ident(ctx, item)
    m = re.match(r"claimed (\S+) as ", out)
    return ({"id": iid, "type": itype, "claimId": as_, "changed": bool(m)}, out)


@verb("item", "release", values=("as",), pos=(1, 1))
def item_release(ctx):
    item, as_ = ctx.pos[0], claim_id(ctx)
    known_in_file_mode(ctx, item)
    run(ctx, "hv-item-release", item, "--as", as_)
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "claimId": as_, "changed": issue_mode(ctx)}, f"released {item}"


@verb("item", "ready", pos=(1, 1))
def item_ready(ctx):
    item = ctx.pos[0]
    rc, out, err = ctx.helper("hv-item-ready", item)
    if rc == 1 and out.strip() and "error:" not in err:
        iid, itype = ident(ctx, item)
        reasons = [l for l in out.split("\n") if l]
        raise HvError(1, "item not ready: " + "; ".join(reasons),
                      data={"id": iid, "type": itype, "ready": False, "reasons": reasons})
    if rc != 0:
        raise refusal(rc, err)
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "ready": True, "reasons": []}, f"{item} is ready"


COMMENT_KINDS = ("question", "answer", "decision", "feedback")
NOTE_KINDS = ("proof", "design", "plan")


def need_kind(ctx, allowed, required=True):
    kind = ctx.flags.get("kind")
    if kind is None and not required:
        return None
    if kind not in allowed:
        raise usage(f"{ctx.name}: --kind must be one of {', '.join(allowed)}")
    return kind


def body_arg(ctx):
    """--body-file as a path the old helper can read, plus its text. Returns (path, text, spool)."""
    given = ctx.flags.get("body-file")
    if not given:
        raise usage(f"{ctx.name}: --body-file is required")
    path, spool = stdin_to_file(given if given == "-" else os.path.join(ctx.cwd, given))
    text = read_text(path)
    if text is None:
        raise HvError(3, f"cannot read --body-file: {given}")
    if not text.strip():
        if spool:
            os.unlink(spool)
        raise usage(f"{ctx.name}: empty body")
    return path, text, spool


@verb("item", "comment", "add", values=("kind", "body-file"), pos=(1, 1))
def item_comment_add(ctx):
    item = ctx.pos[0]
    kind = need_kind(ctx, COMMENT_KINDS)
    path, _, spool = body_arg(ctx)
    try:
        out = run(ctx, "hv-item-comment", item, "--kind", kind, "--body-file", path)
    finally:
        if spool:
            os.unlink(spool)
    iid, itype = ident(ctx, item)
    data = {"id": iid, "type": itype, "kind": kind, "changed": True}
    if out.strip():
        data["commentId"] = out.strip()
    return data, out.strip() or f"commented on {item}"


@verb("item", "comment", "list", values=("kind",), pos=(1, 1))
def item_comment_list(ctx):
    item = ctx.pos[0]
    kind = need_kind(ctx, COMMENT_KINDS, required=False)
    out = run(ctx, "hv-item-comment", item, "--list", *(["--kind", kind] if kind else []))
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "comments": parse_comment_rows(out.split("\n"))}, out


NOTE_HINT = "use hv design or hv plan"


@verb("item", "note", "add", values=("kind", "body-file"), pos=(1, 1))
def item_note_add(ctx):
    item = ctx.pos[0]
    kind = need_kind(ctx, NOTE_KINDS)
    path, _, spool = body_arg(ctx)
    try:
        run(ctx, "hv-item-note", item, "--kind", kind, "--body-file", path, hint=NOTE_HINT)
    finally:
        if spool:
            os.unlink(spool)
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "kind": kind, "changed": True}, f"noted {kind} on {item}"


@verb("item", "note", "show", values=("kind",), pos=(1, 1))
def item_note_show(ctx):
    item = ctx.pos[0]
    kind = need_kind(ctx, NOTE_KINDS)
    body = run(ctx, "hv-item-note", item, "--kind", kind, "--show", hint=NOTE_HINT).rstrip("\n")
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "kind": kind, "exists": body != "", "body": body}, body


@verb("item", "note", "rm", values=("kind",), pos=(1, 1))
def item_note_rm(ctx):
    item = ctx.pos[0]
    kind = need_kind(ctx, NOTE_KINDS)
    run(ctx, "hv-item-note", item, "--kind", kind, "--rm", hint=NOTE_HINT)
    iid, itype = ident(ctx, item)
    return {"id": iid, "type": itype, "kind": kind, "changed": True}, f"removed {kind} note on {item}"


# ---------------------------------------------------------------- adapters: rm, shipped

def active_branches(root, ids):
    """{id: branch} for the given IDs held by an entry of .hv/status.json."""
    hit = {}
    for entry in status_entries(root):
        items = entry.get("items") or []
        if isinstance(items, str):
            items = items.split(",")
        for i in items:
            if i.strip() in ids:
                hit.setdefault(i.strip(), entry.get("branch", ""))
    return hit


def parse_rm_plan(out):
    """`[ID] removal plan:` blocks of the old preview -> contract items."""
    items, cur = [], None
    for line in out.split("\n"):
        m = re.match(r"^\[(\S+)\] removal plan:$", line)
        if m:
            cur = {"id": m.group(1), "type": item_type(m.group(1)), "todoEntry": False, "crossRefs": 0,
                   "planFiles": [], "archive": False}
            items.append(cur)
        elif cur is None:
            continue
        elif (m := re.match(r"^  TODO entry: (\S+) ## ", line)):
            cur["todoEntry"] = m.group(1).endswith("BACKLOG.md")
            cur["archive"] = m.group(1).endswith("ARCHIVE.md")
        elif (m := re.match(r"^  Cross-references to strip: (\d+)", line)):
            cur["crossRefs"] = int(m.group(1))
        elif (m := re.match(r"^  Detail file: (\S+) \(delete\)", line)):
            cur["detailFile"] = m.group(1)
        elif (m := re.match(r"^    (\S+) \(delete\)$", line)):
            cur["planFiles"].append(m.group(1))
        elif (m := re.match(r"^  Active stream: \[\S+\] will be stripped from branch (.+) in status", line)):
            cur["activeBranch"] = m.group(1)
    return items


@verb("item", "rm", bools=("scrub-archive", "apply"), pos=(1, None))
def item_rm(ctx):
    ids = [i for arg in ctx.pos for i in arg.split(",") if i]
    apply_ = bool(ctx.flags.get("apply"))
    flags = ["--scrub-archive"] if ctx.flags.get("scrub-archive") else []
    root = find_root(ctx.cwd)
    hint = "use hv item complete <ID> --reason dropped"
    rc, out, err = ctx.helper("hv-rm", *flags, ",".join(ids))
    if rc == 2 and "is active on branch" in err:
        # Old refuses a preview of an active ID; the contract previews it and refuses only --apply.
        active = active_branches(root, set(ids))
        if apply_:
            who, branch = next(iter(active.items()))
            raise HvError(4, f"{who} is active on branch {branch}",
                          hint="release it first with hv status rm " + branch,
                          data={"blockedBy": "active", "id": who, "activeBranch": branch,
                                "changed": False})
        rest = [i for i in ids if i not in active]
        planned = {}
        if rest:
            planned = {it["id"]: it for it in parse_rm_plan(run(ctx, "hv-rm", *flags, ",".join(rest), hint=hint))}
        items = [planned.get(i) or {"id": i, "type": item_type(i), "todoEntry": True, "crossRefs": 0,
                                    "planFiles": [], "archive": False, "activeBranch": active[i]}
                 for i in ids]
        ctx.warnings.append("preview only; pass --apply")
        return {"applied": False, "items": items, "changed": False}, out
    if rc != 0:
        raise refusal(rc, err, hint)
    items = parse_rm_plan(out)
    if apply_:
        out = run(ctx, "hv-rm", "--force", *flags, ",".join(ids), hint=hint)
    else:
        ctx.warnings.append("preview only; pass --apply")
    return {"applied": apply_, "items": items, "changed": apply_}, out


HIT = re.compile(r"^  \[(STRONG|MEDIUM)\] (\S+) (.*?)  \(tokens: (.*)\)$")
PATH_HIT = re.compile(r"^  \[PATH\]\s+(.*?) → (.*)$")


@verb("item", "shipped", pos=(1, None))
def item_shipped(ctx):
    enter_repo(ctx)
    titles = [t for t in ctx.pos if t.strip()]
    if not titles:
        raise usage(f"{ctx.name}: give at least one non-blank title")
    rc, out, err = ctx.helper("hv-capture-audit", *titles)
    if rc not in (0, 2):
        raise usage(first_error_line(err)) if rc == 1 else backend_error(rc, err)
    hits, cur = {}, None
    for line in out.split("\n"):
        m = re.match(r"^=== (.*) ===$", line)
        if m:
            cur = hits.setdefault(m.group(1), [])
        elif cur is None:
            continue
        elif (m := HIT.match(line)):
            cur.append({"level": m.group(1).lower(), "hash": m.group(2), "subject": m.group(3),
                        "tokens": [t.strip() for t in m.group(4).split(",")]})
        elif (m := PATH_HIT.match(line)):
            cur.append({"level": "path", "token": m.group(1), "path": m.group(2)})
    data = {"found": rc == 2, "titles": [{"title": t, "hits": hits.get(t, [])} for t in titles]}
    if rc == 0:
        raise HvError(1, "no ship evidence found", data=data)
    return data, out
