#!/usr/bin/env python3
"""Stateful fake `gh` (2.45) and `glab` (1.120) for offline tests.

Usage (via the front-ends): fake_tracker.py <gh|glab> ARGV...
Env: FAKE_TRACKER_DB   JSON store path (required; created on first write)
     FAKE_TRACKER_LOG  if set, each call's argv (space-joined) is appended
     FAKE_TRACKER_FAIL if set, any call whose argv contains it fails (exit 1)
Only the subset hv uses is implemented; anything else exits 2.
"""
import json
import os
import re
import sys
from datetime import datetime, timezone

USER = "fake-user"


class Fail(Exception):
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


# ---------------------------------------------------------------- store
def db_path():
    p = os.environ.get("FAKE_TRACKER_DB")
    if not p:
        raise Fail("FAKE_TRACKER_DB is required")
    return p


def load():
    try:
        with open(db_path()) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"next_issue": 1, "next_milestone": 1, "next_comment": 1,
                "issues": [], "labels": [], "milestones": []}


def save(db):
    tmp = db_path() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(db, f, indent=1)
    os.replace(tmp, db_path())


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def find_issue(db, n):
    for i in db["issues"]:
        if i["number"] == int(n):
            return i
    raise Fail("issue #%s not found" % n)


def find_milestone(db, title):
    for m in db["milestones"]:
        if m["title"] == title:
            return m
    return None


def new_issue(db, title, body, labels, milestone):
    issue = {"number": db["next_issue"], "title": title, "body": body or "",
             "labels": list(labels), "milestone": milestone, "state": "open",
             "state_reason": None, "closed_at": None, "assignees": [],
             "comments": []}
    db["next_issue"] += 1
    db["issues"].append(issue)
    return issue


def add_comment(db, issue, body):
    c = {"id": db["next_comment"], "body": body, "author": USER}
    db["next_comment"] += 1
    issue["comments"].append(c)
    return c


def new_milestone(db, title, description, state):
    if find_milestone(db, title):
        raise Fail("milestone %r already exists" % title)
    m = {"number": db["next_milestone"], "title": title,
         "description": description or "", "state": state}
    db["next_milestone"] += 1
    db["milestones"].append(m)
    return m


def close_issue(issue, reason=None):
    issue["state"] = "closed"
    issue["state_reason"] = reason
    issue["closed_at"] = now()


# ---------------------------------------------------------------- args
def parse(argv, value_flags, bool_flags=()):
    """value_flags: {flag: dest}; repeated flags collect into lists.
    Returns (opts{dest: [values]}, bools{set of dest-ish flags}, positionals)."""
    opts, bools, pos = {}, set(), []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("-") and a != "-":
            flag, eq, val = a.partition("=") if a.startswith("--") else (a, "", "")
            if flag in value_flags:
                if not eq:
                    i += 1
                    if i >= len(argv):
                        raise Fail("flag needs an argument: %s" % flag)
                    val = argv[i]
                opts.setdefault(value_flags[flag], []).append(val)
            elif flag in bool_flags:
                bools.add(flag)
            else:
                raise Fail("unknown flag: %s" % a, 2)
        else:
            pos.append(a)
        i += 1
    return opts, bools, pos


def one(opts, key, default=None):
    return opts[key][-1] if key in opts else default


def text_arg(opts, text_key, file_key):
    """--body / --body-file ('-' reads stdin)."""
    if file_key in opts:
        f = opts[file_key][-1]
        return sys.stdin.read() if f == "-" else open(f).read()
    return one(opts, text_key)


def emit(obj):
    print(json.dumps(obj))


def pick(full, fields):
    return {f: full[f] for f in fields if f in full}


def split_labels(vals):
    out = []
    for v in vals:
        out += [x for x in v.split(",") if x]
    return out


# ---------------------------------------------------------------- gh
def gh_issue(i, base_url="https://github.com/fake/repo"):
    return {
        "number": i["number"], "title": i["title"], "body": i["body"],
        "labels": [{"name": n} for n in i["labels"]],
        "milestone": ({"title": i["milestone"][0], "number": i["milestone"][1]}
                      if i["milestone"] else None),
        "state": i["state"].upper(),
        "stateReason": (i["state_reason"] or "").upper().replace(" ", "_") or None,
        "url": "%s/issues/%d" % (base_url, i["number"]),
        "closedAt": i["closed_at"],
        "assignees": [{"login": a} for a in i["assignees"]],
        "comments": [{"id": c["id"], "body": c["body"],
                      "author": {"login": c["author"]}} for c in i["comments"]],
    }


def gh_milestone_ref(db, title):
    m = find_milestone(db, title)
    if not m:
        raise Fail("could not add to milestone '%s': '%s' not found" % (title, title))
    return [m["title"], m["number"]]


def gh_check_labels(db, labels):
    for n in labels:
        if n not in db["labels"]:
            raise Fail("could not add label: '%s' not found" % n)


GH_ISSUE_FLAGS = {
    "--title": "title", "-t": "title", "--body": "body", "-b": "body",
    "--body-file": "body_file", "-F": "body_file", "--label": "label", "-l": "label",
    "--milestone": "milestone", "-m": "milestone", "--state": "state", "-s": "state",
    "--limit": "limit", "-L": "limit", "--json": "json", "--add-label": "add_label",
    "--remove-label": "remove_label", "--add-assignee": "add_assignee",
    "--remove-assignee": "remove_assignee", "--reason": "reason", "-r": "reason",
    "--comment": "comment", "-c": "comment",
}


def gh_issue_cmd(db, args):
    verb, rest = args[0], args[1:]
    o, b, pos = parse(rest, GH_ISSUE_FLAGS, ("--remove-milestone",))
    fields = split_labels(o.get("json", []))
    if verb == "create":
        labels = split_labels(o.get("label", []))
        gh_check_labels(db, labels)
        ms = gh_milestone_ref(db, one(o, "milestone")) if "milestone" in o else None
        body = text_arg(o, "body", "body_file")
        i = new_issue(db, one(o, "title", ""), body, labels, ms)
        save(db)
        print(gh_issue(i)["url"])
    elif verb == "list":
        state = one(o, "state", "open")
        want = split_labels(o.get("label", []))
        rows = [i for i in db["issues"]
                if (state == "all" or i["state"] == state)
                and all(w in i["labels"] for w in want)
                and ("milestone" not in o or (i["milestone"] and i["milestone"][0] == one(o, "milestone")))]
        rows.sort(key=lambda i: -i["number"])
        rows = rows[:int(one(o, "limit", 30))]
        emit([pick(gh_issue(i), fields) for i in rows])
    elif verb == "view":
        i = find_issue(db, pos[0])
        emit(pick(gh_issue(i), fields)) if fields else print("title:\t%s" % i["title"])
    elif verb == "edit":
        i = find_issue(db, pos[0])
        if "title" in o:
            i["title"] = one(o, "title")
        body = text_arg(o, "body", "body_file")
        if body is not None:
            i["body"] = body
        add = split_labels(o.get("add_label", []))
        gh_check_labels(db, add)
        i["labels"] += [x for x in add if x not in i["labels"]]
        i["labels"] = [x for x in i["labels"] if x not in split_labels(o.get("remove_label", []))]
        if "milestone" in o:
            i["milestone"] = gh_milestone_ref(db, one(o, "milestone"))
        if "--remove-milestone" in b:
            i["milestone"] = None
        i["assignees"] += [x for x in split_labels(o.get("add_assignee", [])) if x not in i["assignees"]]
        i["assignees"] = [x for x in i["assignees"] if x not in split_labels(o.get("remove_assignee", []))]
        save(db)
        print("https://github.com/fake/repo/issues/%d" % i["number"])
    elif verb == "close":
        i = find_issue(db, pos[0])
        if "comment" in o:
            add_comment(db, i, one(o, "comment"))
        close_issue(i, one(o, "reason", "completed"))
        save(db)
    elif verb == "reopen":
        i = find_issue(db, pos[0])
        i.update(state="open", state_reason=None, closed_at=None)
        save(db)
    elif verb == "comment":
        i = find_issue(db, pos[0])
        add_comment(db, i, text_arg(o, "body", "body_file") or "")
        save(db)
        print("https://github.com/fake/repo/issues/%d#issuecomment-1" % i["number"])
    else:
        raise Fail("unsupported", 2)


def gh_label_cmd(db, args):
    o, b, pos = parse(args[1:], {"--color": "c", "-c": "c", "--description": "d", "-d": "d", "--json": "json",
                                 "--limit": "limit", "-L": "limit"},
                      ("--force", "-f"))
    if args[0] == "create":
        name = pos[0]
        if name in db["labels"]:
            if not ({"--force", "-f"} & b):
                raise Fail('label with name "%s" already exists; use `--force` to update its color and description' % name)
        else:
            db["labels"].append(name)
            save(db)
    elif args[0] == "list":
        emit([{"name": n} for n in db["labels"]])
    else:
        raise Fail("unsupported", 2)


def parse_api(args, extra_flags):
    flags = {"-X": "method", "--method": "method", "-f": "field", "--raw-field": "field",
             "-F": "field", "--field": "field"}
    flags.update(extra_flags)
    o, b, pos = parse(args, flags, ("--paginate",))
    fields = {}
    for kv in o.get("field", []):
        k, _, v = kv.partition("=")
        fields[k] = v
    path = pos[0].split("?")[0].lstrip("/")
    return path, one(o, "method"), fields, o


def ms_by_number(db, n):
    for m in db["milestones"]:
        if m["number"] == int(n):
            return m
    raise Fail("404 Not Found")


def gh_api(db, args):
    path, method, fields, _ = parse_api(args, {})
    method = (method or ("POST" if fields else "GET")).upper()
    m = re.match(r"^repos/[^/]+/[^/]+/(.+)$", path)
    if not m:
        raise Fail("unsupported", 2)
    rest = m.group(1)
    gm = lambda x: {"number": x["number"], "title": x["title"],
                    "description": x["description"], "state": x["state"]}
    if rest == "milestones" and method == "GET":
        emit([gm(x) for x in db["milestones"]])
    elif rest == "milestones" and method == "POST":
        x = new_milestone(db, fields.get("title", ""), fields.get("description"), fields.get("state", "open"))
        save(db)
        emit(gm(x))
    elif re.match(r"^milestones/\d+$", rest) and method == "PATCH":
        x = ms_by_number(db, rest.split("/")[1])
        for k in ("title", "description", "state"):
            if k in fields:
                x[k] = fields[k]
        save(db)
        emit(gm(x))
    elif re.match(r"^issues/\d+/comments$", rest) and method == "GET":
        i = find_issue(db, rest.split("/")[1])
        emit([{"id": c["id"], "body": c["body"], "user": {"login": c["author"]}} for c in i["comments"]])
    elif re.match(r"^issues/comments/\d+$", rest) and method == "PATCH":
        cid = int(rest.split("/")[2])
        for i in db["issues"]:
            for c in i["comments"]:
                if c["id"] == cid:
                    c["body"] = fields.get("body", c["body"])
                    save(db)
                    emit({"id": c["id"], "body": c["body"], "user": {"login": c["author"]}})
                    return
        raise Fail("404 Not Found")
    else:
        raise Fail("unsupported", 2)


def run_gh(db, args):
    if args[:2] == ["auth", "status"]:
        return
    if args and args[0] == "issue" and len(args) > 1:
        return gh_issue_cmd(db, args[1:])
    if args and args[0] == "label" and len(args) > 1:
        return gh_label_cmd(db, args[1:])
    if args and args[0] == "api":
        return gh_api(db, args[1:])
    raise Fail("unsupported", 2)


# ---------------------------------------------------------------- glab
def gl_issue(i):
    return {
        "iid": i["number"], "title": i["title"], "description": i["body"],
        "labels": list(i["labels"]),
        "milestone": ({"title": i["milestone"][0], "iid": i["milestone"][1]}
                      if i["milestone"] else None),
        "state": "opened" if i["state"] == "open" else "closed",
        "web_url": "https://gitlab.com/fake/repo/-/issues/%d" % i["number"],
        "closed_at": i["closed_at"],
        "assignees": [{"username": a} for a in i["assignees"]],
    }


def gl_milestone_ref(db, title):
    m = find_milestone(db, title)
    if not m:
        raise Fail("milestone '%s' not found" % title)
    return [m["title"], m["number"]]


GL_ISSUE_FLAGS = {
    "--title": "title", "-t": "title", "--description": "desc", "-d": "desc",
    "--label": "label", "-l": "label", "--unlabel": "unlabel", "--milestone": "milestone",
    "-m": "milestone", "--per-page": "per_page", "-P": "per_page", "--output": "output",
    "-O": "output", "--assignee": "assignee", "-a": "assignee", "--message": "message",
}


def gl_issue_cmd(db, args):
    verb, rest = args[0], args[1:]
    flags = dict(GL_ISSUE_FLAGS)
    if verb == "note":
        flags["-m"] = "message"
    o, b, pos = parse(rest, flags, ("--yes", "-y", "--all", "-A", "--closed", "-c", "--comments", "--unassign"))
    if verb == "create":
        labels = split_labels(o.get("label", []))
        for n in labels:
            if n not in db["labels"]:
                db["labels"].append(n)
        ms = gl_milestone_ref(db, one(o, "milestone")) if "milestone" in o else None
        i = new_issue(db, one(o, "title", ""), one(o, "desc"), labels, ms)
        save(db)
        print(gl_issue(i)["web_url"])
    elif verb == "list":
        want = split_labels(o.get("label", []))
        rows = []
        for i in db["issues"]:
            if "--all" in b or "-A" in b:
                pass
            elif "--closed" in b or "-c" in b:
                if i["state"] != "closed":
                    continue
            elif i["state"] != "open":
                continue
            if not all(w in i["labels"] for w in want):
                continue
            if "milestone" in o and not (i["milestone"] and i["milestone"][0] == one(o, "milestone")):
                continue
            rows.append(i)
        rows.sort(key=lambda i: -i["number"])
        rows = rows[:int(one(o, "per_page", 30))]
        emit([gl_issue(i) for i in rows])
    elif verb == "view":
        i = find_issue(db, pos[0])
        out = gl_issue(i)
        if "--comments" in b:
            out["notes"] = [{"id": c["id"], "body": c["body"], "author": {"username": c["author"]}}
                            for c in i["comments"]]
        emit(out)
    elif verb == "update":
        i = find_issue(db, pos[0])
        if "title" in o:
            i["title"] = one(o, "title")
        if "desc" in o:
            i["body"] = one(o, "desc")
        for n in split_labels(o.get("label", [])):
            if n not in db["labels"]:
                db["labels"].append(n)
            if n not in i["labels"]:
                i["labels"].append(n)
        i["labels"] = [x for x in i["labels"] if x not in split_labels(o.get("unlabel", []))]
        if "milestone" in o:
            title = one(o, "milestone")
            i["milestone"] = gl_milestone_ref(db, title) if title else None  # `--milestone ""` clears
        if "--unassign" in b:
            i["assignees"] = []
        i["assignees"] += [x for x in split_labels(o.get("assignee", [])) if x not in i["assignees"]]
        save(db)
        print(gl_issue(i)["web_url"])
    elif verb == "close":
        close_issue(find_issue(db, pos[0]))
        save(db)
    elif verb == "reopen":
        find_issue(db, pos[0]).update(state="open", state_reason=None, closed_at=None)
        save(db)
    elif verb == "note":
        add_comment(db, find_issue(db, pos[0]), one(o, "message", ""))
        save(db)
    else:
        raise Fail("unsupported", 2)


def gl_label_cmd(db, args):
    o, b, pos = parse(args[1:], {"--name": "name", "-n": "name", "--color": "c", "-c": "c",
                                 "--description": "d", "-d": "d", "--output": "output", "-O": "output"})
    if args[0] == "create":
        name = one(o, "name")
        if name in db["labels"]:
            raise Fail("Label already exists")
        db["labels"].append(name)
        save(db)
    elif args[0] == "list":
        emit([{"id": k + 1, "name": n} for k, n in enumerate(db["labels"])])
    else:
        raise Fail("unsupported", 2)


def gl_api(db, args):
    path, method, fields, _ = parse_api(args, {"--input": "input"})
    method = (method or ("POST" if fields else "GET")).upper()
    m = re.match(r"^projects/.+?/((?:milestones|issues).*)$", path)
    if not m:
        raise Fail("unsupported", 2)
    rest = m.group(1)

    def gm(x):
        return {"id": x["number"], "iid": x["number"], "title": x["title"],
                "description": x["description"], "state": "closed" if x["state"] == "closed" else "active"}
    if rest == "milestones" and method == "GET":
        emit([gm(x) for x in db["milestones"]])
    elif rest == "milestones" and method == "POST":
        x = new_milestone(db, fields.get("title", ""), fields.get("description"), "open")
        save(db)
        emit(gm(x))
    elif re.match(r"^milestones/\d+$", rest) and method == "PUT":
        x = ms_by_number(db, rest.split("/")[1])
        for k in ("title", "description"):
            if k in fields:
                x[k] = fields[k]
        ev = fields.get("state_event")
        if ev:
            x["state"] = "closed" if ev == "close" else "open"
        save(db)
        emit(gm(x))
    elif re.match(r"^issues/\d+/notes$", rest) and method == "GET":
        i = find_issue(db, rest.split("/")[1])
        emit([{"id": c["id"], "body": c["body"], "author": {"username": c["author"]}} for c in i["comments"]])
    elif re.match(r"^issues/\d+/notes/\d+$", rest) and method == "PUT":
        parts = rest.split("/")
        i = find_issue(db, parts[1])
        for c in i["comments"]:
            if c["id"] == int(parts[3]):
                c["body"] = fields.get("body", c["body"])
                save(db)
                emit({"id": c["id"], "body": c["body"], "author": {"username": c["author"]}})
                return
        raise Fail("404 Not found")
    else:
        raise Fail("unsupported", 2)


def run_glab(db, args):
    if args[:2] == ["auth", "status"]:
        return
    if args and args[0] == "issue" and len(args) > 1:
        return gl_issue_cmd(db, args[1:])
    if args and args[0] == "label" and len(args) > 1:
        return gl_label_cmd(db, args[1:])
    if args and args[0] == "api":
        return gl_api(db, args[1:])
    raise Fail("unsupported", 2)


# ---------------------------------------------------------------- main
def main():
    tool, args = sys.argv[1], sys.argv[2:]
    line = " ".join(args)
    if os.environ.get("FAKE_TRACKER_LOG"):
        with open(os.environ["FAKE_TRACKER_LOG"], "a") as f:
            f.write(line + "\n")
    sub = os.environ.get("FAKE_TRACKER_FAIL")
    if sub and sub in line:
        sys.stderr.write("fake %s: simulated failure for: %s\n" % (tool, line))
        return 1
    try:
        db = load()
        (run_gh if tool == "gh" else run_glab)(db, args)
    except Fail as e:
        if e.code == 2 and str(e) == "unsupported":
            sys.stderr.write("fake %s: unsupported: %s\n" % (tool, line))
        else:
            sys.stderr.write("%s\n" % e)
        return e.code
    return 0


if __name__ == "__main__":
    sys.exit(main())
