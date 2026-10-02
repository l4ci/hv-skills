# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv proof` adapters (cross-phase verbs).
import subprocess

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)
from item import type_of


def proof_count(ctx, item):
    rc, out, _ = ctx.helper("hv-proof-show", item, "--count")
    return out.strip() if rc == 0 else None


@verb("proof", "add", values=("check", "result", "evidence", "sha"), pos=(1, 1), repo=False)
def proof_add(ctx):
    f, item = ctx.flags, ctx.pos[0]
    for k in ("check", "result", "evidence"):
        if not f.get(k):
            raise usage(f"{ctx.name}: --{k} is required")
    if f["result"] not in ("PASS", "FAIL"):
        raise usage(f"{ctx.name}: --result must be PASS or FAIL")
    one = lambda s: " ".join(s.split())
    sha = one(f.get("sha", ""))
    if not sha:
        proc = subprocess.run(["git", "log", "-1", "--format=%h"], cwd=ctx.cwd,
                              capture_output=True, text=True)
        sha = proc.stdout.strip() or "-"
    before = proof_count(ctx, item)
    rc, _, err = ctx.helper("hv-proof-add", item, "--check", f["check"], "--result", f["result"],
                            "--evidence", f["evidence"], "--sha", sha)
    if rc != 0:
        raise backend_error(rc, err)
    changed = proof_count(ctx, item) != before
    return ({"id": item, "type": type_of(ctx, item), "check": one(f["check"]), "result": f["result"],
             "sha": sha, "evidence": one(f["evidence"]), "changed": changed},
            f"proof recorded for {item}")
