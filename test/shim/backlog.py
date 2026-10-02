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


@verb("backlog", "list", values=("grep",))
def backlog_list(ctx):
    f = ctx.flags
    out = call(ctx, "hv-backlog", *(["--grep", f["grep"]] if "grep" in f else []))
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
        row = {"id": r["ID"], "title": r["Title"], "branch": r["Branch"],
               "startedAt": starts.get((r["Branch"], r["ID"])) or r["Started"]}
        if r.get("Repo"):
            row["repo"] = r["Repo"]
        data["inProgress"].append(row)
    for key, label, tagkey, tagname in (("bugs", "Bugs", "Prio", "priority"),
                                        ("features", "Features", "Size", "size"),
                                        ("tasks", "Tasks", None, None)):
        for r in md_rows(blocks.get(label, [])):
            row = {"id": r["ID"]}
            if tagkey:
                row[tagname] = r[tagkey]
            row.update(title=r["Title"], related=ids_in(r["Related"]))
            if r.get("Milestone"):
                row["milestone"] = r["Milestone"]
            data[key].append(row)
    for line in blocks.get("Clusters", []):
        data["clusters"].append(re.findall(r"(?:^- |, | ↔ )\[([A-Z]\d+)\]", line))
    return data, out


def to_int(s, default=0):
    return int(s) if s else default


@verb("summary")
def summary(ctx):
    out = call(ctx, "hv-summary")
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
                data["recent"].append({"id": iid, "date": date, **({"reason": why} if why else {})})
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
    moved = to_int(call(ctx, "hv-archive-old", days).strip())
    return {"days": int(days), "moved": moved, "changed": moved > 0}, f"archived {moved}"
