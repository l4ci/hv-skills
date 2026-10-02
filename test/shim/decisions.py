# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv decisions` adapters for the A5 verbs the A4 sections use.
from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("decisions", "query", repo=False, pos=(1, None))
def decisions_query(ctx):
    out = call(ctx, "hv-decisions-query", *ctx.pos)
    return {"text": out}, out
