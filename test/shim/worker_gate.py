# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv worker gate` and `hv worker account` adapters.
import json
import os
import re
import subprocess

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


def registry(ctx):
    return read_json_file(os.path.join(ctx.cwd, ".hv", "workers.json"), {})


# ---------------------------------------------------------------- adapters: worker gate

# (verdict, token) in the order the old gate can print them.
GATE_TOKENS = (
    ("provenance-fail", r"PROVENANCE-FAIL"),
    ("not-merged", r"NOT-MERGED"),
    ("not-on-base", r"NOT-ON-BASE"),
    ("merged-remotely", r"MERGED-REMOTELY"),
    ("check-broke", r"CHECK-BROKE"),
    ("stale", r"^STALE "),
    ("verify-failed", r"verify FAILED"),
    ("pr-mismatch", r"error: PR \S+ (?:is \S+, not open|targets|is headed by|head is)"),
    ("merge-failed", r"error: (?:\S+ merge failed|merge of .* conflicted)"),
)
# The merge landed on the way to these no's.
GATE_MERGED = {"verify-failed", "merged-remotely"}
# Old exit 3 that is a missing ref, not a verdict.
GATE_MISSING = r"error: (?:no worker pool|slot '.*' is not in the pool|base branch '.*' does not exist|worker branch '.*' does not exist|gate must run with)"


@verb("worker", "gate", values=("base",), bools=("check-only", "no-verify"), pos=(1, 1), repo=False)
def worker_gate(ctx):
    f, slot = ctx.flags, ctx.pos[0]
    if not f.get("base"):
        raise usage(f"{ctx.name}: --base is required")
    args = ["--slot", slot, "--base", f["base"]]
    if f.get("check-only"):
        args.append("--check-only")
    if f.get("no-verify"):
        args.append("--no-verify")
    rc, out, err = ctx.helper("hv-worker-gate", *args)
    both = out + err
    if rc == 2:
        raise HvError(2, first_error_line(err) or "usage")
    entry = next((s for s in registry(ctx).get("slots", []) if s.get("name") == slot), {})
    data = {"slot": slot, "verdict": "", "base": f["base"], "verified": [],
            "verifySkipped": bool(re.search(r"^NO-VERIFY ", out, re.M)), "changed": False}
    if entry.get("branch"):
        data["branch"] = entry["branch"]
    if entry.get("pr"):
        data["pr"] = entry["pr"]
    data["verified"] = re.findall(r"^\s*verify ok: (.*)$", out, re.M)
    m = re.search(r"^(?:MERGED|GATE-PASS) \S+ .*?\(?([0-9a-f]{7,40})\)?$", out, re.M)
    if m:
        data["sha"] = m.group(1)
    if rc == 0:
        data["verdict"] = "pass" if re.search(r"^(?:MERGED|GATE-PASS|NO-VERIFY) ", out, re.M) else "fresh"
        data["changed"] = data["verdict"] == "pass"
        m = re.search(r"^FRESH \S+ (\S+)", out, re.M)
        if m:
            # The old FRESH line names no SHA: report the tip that was checked
            # (the pushed branch when a PR is recorded).
            ref = ("origin/" if data.get("pr") else "") + m.group(1)
            sha = subprocess.run(["git", "-C", ctx.cwd, "rev-parse", "--short=7", ref],
                                 capture_output=True, text=True).stdout.strip()
            if sha:
                data["sha"] = sha
        return data, out
    if rc == 3 and re.search(GATE_MISSING, err):
        raise HvError(3, first_error_line(err))
    verdict = next((v for v, pat in GATE_TOKENS if re.search(pat, both, re.M)), None)
    if verdict is None:
        raise backend_error(rc, err)
    data["verdict"] = verdict
    data["changed"] = verdict in GATE_MERGED
    line = next((l for l in both.splitlines() if re.search(dict(GATE_TOKENS)[verdict], l)), "")
    tail = [l for l in err.splitlines() if l.strip() and l != line][-20:]
    raise HvError(1, line.strip() or verdict, hint="\n".join(tail) or None, data=data)


# ---------------------------------------------------------------- adapters: worker account

def account_fail(rc, err):
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc == 2:
        return HvError(2, msg)
    if rc == 3:
        return HvError(3, msg)
    return HvError(70, msg)


@verb("worker", "account", "list", repo=False)
def worker_account_list(ctx):
    rc, out, err = ctx.helper("hv-worker-account", "list", "--json")
    if rc != 0:
        raise account_fail(rc, err)
    rows = [{k: v for k, v in r.items() if v is not None} for r in json.loads(out)]
    return {"accounts": rows}, "\n".join(f"{r['name']} {r['verdict']}" for r in rows)


@verb("worker", "account", "pick", values=("exclude",), repo=False)
def worker_account_pick(ctx):
    args = ["pick"] + (["--exclude", ctx.flags["exclude"]] if ctx.flags.get("exclude") else [])
    rc, out, err = ctx.helper("hv-worker-account", *args)
    if rc == 3:
        raise HvError(1, first_error_line(err) or "no usable account", data={"found": False})
    if rc != 0:
        raise account_fail(rc, err)
    name = out.strip()
    return {"found": True, "account": name}, name


@verb("worker", "account", "assign", values=("account",), pos=(1, 1), repo=False)
def worker_account_assign(ctx):
    slot, account = ctx.pos[0], ctx.flags.get("account")
    before = next((s.get("account") for s in registry(ctx).get("slots", [])
                   if s.get("name") == slot), None)
    args = ["assign", "--slot", slot] + (["--account", account] if account else [])
    rc, out, err = ctx.helper("hv-worker-account", *args)
    if rc == 3 and not account and "cooling down" in err:
        raise HvError(4, first_error_line(err),
                      data={"blockedBy": "no usable account", "changed": False})
    if rc != 0:
        raise account_fail(rc, err)
    m = re.search(r"assigned: (\S+) -> (\S+)", out)
    got = m.group(2) if m else account
    return {"slot": slot, "account": got, "changed": before != got}, out.strip()
