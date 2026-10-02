# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv refactor` adapters.
from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


def age_counts(ctx):
    body = json_body(call(ctx, "hv-refactor-age"))
    return {"features": int(body.get("features", 0)), "bugs": int(body.get("bugs", 0))}


@verb("refactor", "age")
def refactor_age(ctx):
    data = age_counts(ctx)
    return data, f"{data['features']} features, {data['bugs']} bugs since the last refactor"


@verb("refactor", "reset")
def refactor_reset(ctx):
    before = age_counts(ctx)
    call(ctx, "hv-refactor-reset")
    return {"changed": any(before.values())}, "reset"


@verb("refactor", "targets", repo=False)
def refactor_targets(ctx):
    out = call(ctx, "hv-refactor-targets")
    return json_body(out), out
