# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv block` adapters (A5).

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

STATUSES = ("created", "updated", "appended", "unchanged")


def block_result(key, out):
    status = out.strip().splitlines()[-1] if out.strip() else ""
    if status not in STATUSES:
        raise HvError(70, f"old helper printed an unknown status: {out!r}")
    return {"key": key, "status": status, "changed": status != "unchanged"}, status


@verb("block", values=("body-file",), pos=(1, 1))
def block(ctx):
    key, f = ctx.pos[0], ctx.flags
    if key == "skills":
        raise usage(f"{ctx.name}: pass `hv block skills` with no other arguments")
    if "body-file" in f:
        if ctx.repo:
            raise usage(f"{ctx.name}: --repo is not allowed with --body-file")
        if f["body-file"] == "-":
            body = sys.stdin.read()
        else:
            body = read_text(f["body-file"])
            if body is None:
                raise HvError(3, f"body file '{f['body-file']}' not found")
        rc, out, err = ctx.helper("hv-managed-block", key, "--body-stdin", stdin=body)
    else:
        if key not in ("knowledge", "decisions"):
            raise usage(f"{ctx.name}: unknown key '{key}' (known: knowledge, decisions)")
        if key == "decisions" and ctx.repo:
            raise usage(f"{ctx.name}: decisions is umbrella-only; --repo not allowed")
        rc, out, err = ctx.helper("hv-managed-block", key, *(["--repo", ctx.repo] if ctx.repo else []))
    if rc != 0:
        raise HvError(3 if rc == 1 else 70, first_error_line(err) or f"old helper failed (rc {rc})")
    return block_result(key, out)


@verb("block", "skills", repo=False)
def block_skills(ctx):
    rc, out, err = ctx.helper("hv-skills-index")
    if rc != 0:
        raise HvError(70, first_error_line(err) or f"old helper failed (rc {rc})")
    return block_result("skills", out)
