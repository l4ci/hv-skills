# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv tracker` adapters.
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


def repo_dir(ctx):
    """The directory a scoped verb runs in: --repo's checkout, else the cwd."""
    if ctx.repo is None:
        return ctx.cwd
    out = call(ctx, "hv-resolve-repo-path", ctx.repo, cwd=find_root(ctx.cwd))
    return out.strip()


def resolved_provider(ctx, cwd, flag):
    """`--provider` if set, else issues.provider, else the old remote detection."""
    if flag and flag != "auto":
        return flag
    cfg = {}
    for name in ("config.json", "config.local.json"):
        cfg = {**cfg, **read_json_file(os.path.join(find_root(ctx.cwd), ".hv", name), {})}
    prov = (cfg.get("issues") or {}).get("provider")
    if prov in ("github", "gitlab"):
        return prov
    _, out, _ = ctx.helper("hv-issues-provider", cwd=cwd)
    return out.strip() or "unknown"


@verb("tracker", "call", values=("provider",), pos=(0, None))
def tracker_call(ctx):
    prov = ctx.flags.get("provider", "auto")
    if prov not in ("auto", "github", "gitlab"):
        raise usage(f"{ctx.name}: --provider must be auto, github or gitlab")
    if not ctx.pos:
        raise usage(f"{ctx.name}: no CLI arguments; pass them after --")
    cwd = repo_dir(ctx)
    # stdin is inherited: the old helper reads it only when an argument is `-`, `@-` or `=-`.
    rc, out, err = ctx.helper("hv-tracker-call", "--provider", prov, "--", *ctx.pos, cwd=cwd)
    ours = err.lstrip().startswith(("error: hv-tracker-call:", "usage: hv-tracker-call"))
    if rc != 0 and ours:
        if err.lstrip().startswith("usage:"):
            raise usage(first_error_line(err))
        raise HvError({3: 5, 4: 6}.get(rc, 70), first_error_line(err))
    data = {"provider": resolved_provider(ctx, cwd, prov), "exitCode": rc,
            "stdout": out, "stderr": err}
    if rc != 0:
        raise HvError(1, f"{ctx.pos[0]} exited {rc}", data=data)
    return data, out


@verb("tracker", "suggest-upstream", values=("title", "body-file", "upstream-repo"))
def tracker_suggest_upstream(ctx):
    f = ctx.flags
    if not f.get("title") or not f.get("body-file"):
        raise usage(f"{ctx.name}: --title and --body-file are required")
    path, tmp = stdin_to_file(f["body-file"])
    try:
        body = read_text(path)
        if body is None:
            raise HvError(3, f"cannot read {f['body-file']}")
    finally:
        if tmp:
            os.unlink(tmp)
    args = ["--title", f["title"]]
    if f.get("upstream-repo"):
        args += ["--upstream-repo", f["upstream-repo"]]
    repo = f.get("upstream-repo") or os.environ.get("HV_UPSTREAM_REPO") or "l4ci/hv-skills"
    rc, out, err = ctx.helper("hv-issue-suggest", *args, stdin=body)
    if rc == 0:
        d = json_body(out)
        return {"url": d["url"], "number": d["number"], "upstreamRepo": repo,
                "changed": True}, d["url"]
    if "gh not available" in out:
        m = re.search(r"https://\S+/issues/new", out)
        raise HvError(5, "gh is missing or not authenticated",
                      hint=m.group(0) if m else f"https://github.com/{repo}/issues/new")
    raise HvError(2 if rc == 2 else 70, first_error_line(err) or f"old helper failed (rc {rc})")
