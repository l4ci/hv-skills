# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv qa` adapters.
from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("qa", "query", repo=False, pos=(1, None))
def qa_query(ctx):
    out = call(ctx, "hv-qa-query", *ctx.pos)
    return {"text": out}, out


@verb("qa", "index", repo=False)
def qa_index(ctx):
    out = call(ctx, "hv-qa-index")
    status = out.strip()
    return {"key": "qa", "status": status, "changed": status != "unchanged"}, out
