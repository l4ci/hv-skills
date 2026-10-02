# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv knowledge` adapters for the A5 verbs the A4 sections use.
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

TIERS = ("provisional", "confirmed", "deprecated")


@verb("knowledge", "query", values=("tier",), bools=("include-deprecated",), pos=(1, None))
def knowledge_query(ctx):
    f = ctx.flags
    if "tier" in f and f["tier"] not in TIERS:
        raise usage(f"{ctx.name}: --tier must be provisional|confirmed|deprecated")
    args = []
    if ctx.repo:
        args += ["--repo", ctx.repo]
    if f.get("include-deprecated"):
        args.append("--include-deprecated")
    if "tier" in f:
        args += ["--tier", f["tier"]]
    rc, out, err = ctx.helper("hv-knowledge-query", *args, "--", *ctx.pos)
    if rc != 0:
        msg = first_error_line(err) or f"old helper failed (rc {rc})"
        raise HvError(3 if rc == 2 else 70, msg)
    missing = []
    for line in err.splitlines():
        m = re.search(r"no topic heading matches '([^']*)'", line)
        if m:
            missing.append(m.group(1))
            ctx.warnings.append(re.sub(r"^warning:\s*(hv-[\w-]+:\s*)?", "", line.strip()))
    return {"text": out, "missing": missing}, out


@verb("knowledge", "stats", repo=False)
def knowledge_stats(ctx):
    out = call(ctx, "hv-knowledge-stats")
    return json_body(out), out
