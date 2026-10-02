# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv backlog` and `hv summary` adapters.
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


# ---------------------------------------------------------------- adapters: backlog, summary, git

def md_rows(lines):
    """Rows of one markdown table as dicts keyed by the header cells."""
    rows = [[c.strip() for c in l.strip().strip("|").split("|")] for l in lines if l.startswith("|")]
    return [dict(zip(rows[0], r)) for r in rows[2:]] if len(rows) > 2 else []


def ids_in(cell):
    return re.findall(r"[A-Z]\d+", cell)


def bcall(ctx, helper, *args, **kw):
    """call(), with the contract's default failure data on a backend refusal (exit 4)."""
    rc, out, err = ctx.helper(helper, *args, **kw)
    if rc == 0:
        return out
    if rc == 1 and re.match(r"\s*error: hv-", err) and not re.search(
            r"not found|usage:|unknown argument|expects|invalid|not a valid", err):
        raise HvError(5, first_error_line(err))      # a tracker failure, not a lookup miss
    e = backend_error(rc, err)
    if e.exit == 4:
        e.data = {"blockedBy": "backend", "changed": False}
    raise e


def shown_id(ctx, iid):
    """Rule 11: the issues backend's `B12` / `repo:B12` is `12` / `repo:12` in data."""
    if not issue_backend(ctx):
        return iid
    return re.sub(r"(^|:)[BFT](?=\d+$)", r"\1", iid)


@verb("backlog", "list", values=("grep",))
def backlog_list(ctx):
    f = ctx.flags
    out = bcall(ctx, "hv-backlog", *(["--grep", f["grep"]] if "grep" in f else []))
    blocks, cur = {}, None
    for line in out.splitlines():
        if line.startswith("### "):
            cur = blocks.setdefault(line[4:].strip(), [])
        elif cur is not None and line.strip():
            cur.append(line)
    starts = {}
    for e in status_entries(find_root(ctx.cwd)):
        for i in e.get("items") or []:
            starts[(e.get("branch"), i)] = e.get("startedAt")
    data = {"inProgress": [], "bugs": [], "features": [], "tasks": [], "clusters": []}
    for r in md_rows(blocks.get("In Progress", [])):
        row = {"id": shown_id(ctx, r["ID"]), "type": item_type(r["ID"]), "title": r["Title"], "branch": r["Branch"],
               "startedAt": starts.get((r["Branch"], r["ID"])) or r["Started"]}
        if r.get("Repo"):
            row["repo"] = r["Repo"]
        data["inProgress"].append(row)
    for key, label, tagkey, tagname in (("bugs", "Bugs", "Prio", "priority"),
                                        ("features", "Features", "Size", "size"),
                                        ("tasks", "Tasks", None, None)):
        for r in md_rows(blocks.get(label, [])):
            row = {"id": shown_id(ctx, r["ID"])}
            if tagkey:
                row[tagname] = r[tagkey]
            row.update(title=r["Title"], related=ids_in(r["Related"]))
            if r.get("Milestone"):
                row["milestone"] = r["Milestone"]
            data[key].append(row)
    for line in blocks.get("Clusters", []):
        data["clusters"].append(re.findall(r"(?:^- |, | ↔ )\[([A-Z]\d+)\]", line))
    return data, out


def issue_backend(ctx):
    """True when the merged config selects the issues backend (IDs lose their type letter)."""
    cfg = {}
    for name in ("config.json", "config.local.json"):
        cfg.update(read_json_file(os.path.join(find_root(ctx.cwd), ".hv", name), {}))
    return (cfg.get("backlog") or {}).get("backend") == "issues"


def to_int(s, default=0):
    return int(s) if s else default


@verb("summary")
def summary(ctx):
    out = bcall(ctx, "hv-summary")
    if out.startswith("No .hv/ yet"):
        raise HvError(3, "no .hv/ found in this directory or any parent", hint="run: hv init")
    data = {"backlog": {"bugs": 0, "features": 0, "tasks": 0}, "active": [], "recent": [], "milestones": []}
    for line in out.splitlines():
        label, _, rest = line.partition(": ")
        if label == "Backlog":
            for n, word in re.findall(r"(\d+) (bug|feature|task)", rest):
                data["backlog"][word + "s"] = int(n)
        elif label == "Active":
            m = re.match(r"(.*?) on (\S+?)(?: in (\S+))?(?: \(repo: ([^)]+)\))? \(since ([^)]*)\)$", rest)
            if m:
                e = {"items": m.group(1).split(", "), "branch": m.group(2)}
                if m.group(3):
                    e["worktree"] = m.group(3)
                if m.group(4):
                    e["repo"] = m.group(4)
                e["since"] = m.group(5)
                data["active"].append(e)
        elif label == "Recent":
            for iid, date, why in re.findall(r"\[([^\]]+)\] on (\d{4}-\d\d-\d\d)(?: \(([^)]+)\))?", rest):
                letter = item_type(iid)
                data["recent"].append({"id": iid[1:] if issue_backend(ctx) and letter else iid,
                                       "type": letter, "date": date,
                                       **({"reason": why} if why else {})})
        elif label == "Active milestones":
            for part in re.split(r", (?=[A-Z]\d+(?: |$))", rest):
                mid, _, title = part.partition(" ")
                data["milestones"].append({"id": mid, "title": title})
        elif label in ("Knowledge", "Decisions"):
            m = re.match(r"(\d+) topics? \((.*?)(?:, \.\.\.)?\)$", rest)
            if m:
                data[label.lower()] = {"count": int(m.group(1)), "topics": m.group(2).split(", ")}
        elif label == "Archive":
            data["archive"] = to_int(re.match(r"\d+", rest).group())
    return data, out


@verb("backlog", "archive", values=("days",))
def backlog_archive(ctx):
    f = ctx.flags
    days = f.get("days", "5")
    if not days.isdigit():
        raise usage(f"{ctx.name}: --days must be a number")
    moved = to_int(bcall(ctx, "hv-archive-old", days).strip())
    return {"days": int(days), "moved": moved, "changed": moved > 0}, f"archived {moved}"


# ---------------------------------------------------------------- adapters: backlog lookups and writers

@verb("backlog", "ids", values=("milestone",))
def backlog_ids(ctx):
    mid = ctx.flags.get("milestone")
    if not mid:
        raise usage(f"{ctx.name}: --milestone is required")
    ids = [shown_id(ctx, i) for i in bcall(ctx, "hv-todo-by-milestone", mid).split()]
    return {"milestone": mid, "ids": ids}, "\n".join(ids)


@verb("backlog", "milestones", pos=(1, None))
def backlog_milestones(ctx):
    ms = bcall(ctx, "hv-find-milestone-for-items", *ctx.pos).split()
    return {"milestones": ms}, "\n".join(ms)


@verb("backlog", "drift")
def backlog_drift(ctx):
    out = bcall(ctx, "hv-todo-drift")
    body = json_body(out)
    drift = [{"id": d["id"], "type": item_type(d["id"]), "commits": d["commits"]}
             for d in body.get("drift", [])]
    if ctx.repo is not None:
        for d in drift:
            d["commits"] = [c for c in d["commits"] if c.get("repo") == ctx.repo]
        drift = [d for d in drift if d["commits"]]
    sym = [{"id": s["id"], "type": item_type(s["id"]), "symbols": s["symbols"], "files": s["files"]}
           for s in body.get("symbol_drift", [])]
    return {"drift": drift, "symbolDrift": sym}, out


@verb("backlog", "backfill")
def backlog_backfill(ctx):
    rc, out, err = ctx.helper("hv-backfill-since")
    if rc == 1 and "HEAD commit" in err:
        raise HvError(5, first_error_line(err))
    if rc != 0:
        e = backend_error(rc, err)
        if e.exit == 4:
            e.data = {"blockedBy": "backend", "changed": False}
        raise e
    stamped = to_int(out.strip())
    return {"stamped": stamped, "changed": stamped > 0}, f"stamped {stamped}"


@verb("backlog", "stale", values=("kind", "days"))
def backlog_stale(ctx):
    f = ctx.flags
    kind = f.get("kind")
    if kind not in ("map", "knowledge", "todo"):
        raise usage(f"{ctx.name}: --kind must be map|knowledge|todo")
    days = f.get("days", "90")
    if not days.isdigit():
        raise usage(f"{ctx.name}: --days must be a number")
    args = [kind, "--days", days]
    if os.environ.get("HV_TEST_TODAY"):
        args += ["--today", os.environ["HV_TEST_TODAY"]]
    out = call(ctx, "hv-staleness", *args)
    entries = []
    for line in out.splitlines():
        name, _, date = line.strip().rpartition(" ")
        if name:
            entries.append({"name": name, "date": None if date == "unknown" else date})
    return {"kind": kind, "days": int(days), "entries": entries}, out
