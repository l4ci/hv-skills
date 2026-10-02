# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv decisions` adapters for the A5 verbs the A4 sections use.
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("decisions", "query", repo=False, pos=(1, None))
def decisions_query(ctx):
    out = call(ctx, "hv-decisions-query", *ctx.pos)
    return {"text": out}, out


@verb("decisions", "auto-log", values=("topic", "title", "why", "plan-key", "date"), repo=False)
def decisions_auto_log(ctx):
    f = ctx.flags
    for name in ("topic", "title", "why"):
        if not f.get(name):
            raise usage(f"{ctx.name}: --{name} is required")
    root = find_root(ctx.cwd)
    path = os.path.join(root, ".hv", "DECISIONS.md")
    before = read_text(path)
    args = [f["topic"], f["title"], f["why"]]
    if "plan-key" in f or "date" in f:
        args.append(f.get("plan-key", ""))
    if "date" in f:
        args.append(f["date"])
    call(ctx, "hv-auto-decision-log", *args)
    return ({"topic": f["topic"], "title": f["title"], "changed": read_text(path) != before},
            f"logged: {f['title']}")


STATUS_TAGS = {"Forbids/Permits unresolved": "unresolved", "Partially articulated": "partial",
               "Articulated": "articulated"}
SINCE_LINE = re.compile(r"^- \*\*(.+?) · (.+)\*\* — (\d{4}-\d{2}-\d{2}) · \[(.+)\]$")


@verb("decisions", "auto-since", repo=False)
def decisions_auto_since(ctx):
    out = call(ctx, "hv-auto-decisions-since")
    decisions = []
    for line in out.splitlines():
        m = SINCE_LINE.match(line.strip())
        if m:
            decisions.append({"topic": m.group(1), "title": m.group(2), "date": m.group(3),
                              "status": STATUS_TAGS.get(m.group(4), "articulated")})
    data = {"decisions": decisions}
    root = find_root(ctx.cwd)
    since = read_json_file(os.path.join(root, ".hv", "status.json"), {}).get("loopStartedAt")
    if since:
        data["since"] = since
    return data, out
