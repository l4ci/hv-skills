# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv knowledge` adapters for the A5 verbs the A4 sections use.
import glob
import json
import os
import re
import sys

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


# ---------------------------------------------------------------- writers

def scope_args(ctx):
    return ["--repo", ctx.repo] if ctx.repo else []


def need(ctx, *names):
    for n in names:
        if not ctx.flags.get(n):
            raise usage(f"{ctx.name}: --{n} is required")


def body_text(ctx):
    """The --body-file contents: `-` is stdin, else a path relative to the cwd."""
    path = ctx.flags["body-file"]
    if path == "-":
        return sys.stdin.read()
    text = read_text(path if os.path.isabs(path) else os.path.join(ctx.cwd, path))
    if text is None:
        raise HvError(3, f"--body-file {path}: cannot read")
    return text


def knowledge_snapshot(root):
    """Every KNOWLEDGE.md the amend verb may touch, for before/after comparison."""
    paths = [os.path.join(root, ".hv", "KNOWLEDGE.md")]
    paths += sorted(glob.glob(os.path.join(root, ".hv", "knowledge", "*", "KNOWLEDGE.md")))
    return {p: read_text(p) for p in paths}


def write_failure(rc, err, msg):
    """Writer failure: rc 2 is a scope-resolution failure, rc 1 a precondition."""
    return HvError(3 if rc in (1, 2) else 70, msg)


@verb("knowledge", "add", values=("topic", "title", "body-file", "date"))
def knowledge_add(ctx):
    f = ctx.flags
    need(ctx, "topic", "title", "body-file")
    body = body_text(ctx)
    args = [*scope_args(ctx), "--topic", f["topic"], "--title", f["title"]]
    if "date" in f:
        args += ["--date", f["date"]]
    rc, _, err = ctx.helper("hv-knowledge-merge", *args, stdin=body)
    if rc != 0:
        raise write_failure(rc, err, first_error_line(err) or f"old helper failed (rc {rc})")
    changed = "wrote:" in err
    return ({"topic": f["topic"], "title": f["title"], "changed": changed},
            f"{'wrote' if changed else 'noop'}: {f['topic']}")


@verb("knowledge", "amend", values=("topic", "fragment", "mode", "body-file"))
def knowledge_amend(ctx):
    f = ctx.flags
    need(ctx, "topic", "fragment", "mode", "body-file")
    if f["mode"] != "append":
        raise usage(f"{ctx.name}: --mode must be append")
    text = body_text(ctx).rstrip("\n")
    if not text:
        raise usage(f"{ctx.name}: --body-file is empty")
    root = find_root(ctx.cwd)
    before = knowledge_snapshot(root)
    rc, _, err = ctx.helper("hv-knowledge-amend", *scope_args(ctx), "--topic", f["topic"],
                            "--fragment", f["fragment"], "--append", text)
    if rc != 0:
        msg = first_error_line(err) or f"old helper failed (rc {rc})"
        if "matches in multiple files" in err:
            raise HvError(2, msg, hint="pass --repo to pick one")
        raise write_failure(rc, err, msg)
    changed = knowledge_snapshot(root) != before
    return {"topic": f["topic"], "changed": changed}, f"amended: {f['topic']}"


@verb("knowledge", "rename-topic", values=("from", "to", "title"))
def knowledge_rename_topic(ctx):
    f = ctx.flags
    need(ctx, "from", "to")
    args = [*scope_args(ctx), "--from", f["from"], "--to", f["to"]]
    if "title" in f:
        args += ["--title", f["title"]]
    rc, _, err = ctx.helper("hv-knowledge-rename-topic", *args)
    if rc != 0:
        msg = first_error_line(err) or f"old helper failed (rc {rc})"
        if "already exists" in err:
            raise HvError(4, msg, data={"blockedBy": "exists", "changed": False})
        raise write_failure(rc, err, msg)
    data = {"from": f["from"], "to": f["to"], "mode": "bullet" if "title" in f else "topic",
            "changed": f["from"] != f["to"]}
    if "title" in f:
        data["title"] = f["title"]
    return data, f"renamed: {f['from']} -> {f['to']}"


# ---------------------------------------------------------------- tier

def tier_get(ctx, topic, title):
    out = call(ctx, "hv-knowledge-tier", *scope_args(ctx), "--get", "--topic", topic,
               "--title", title)
    return json_body(out)


def tier_filter(ctx):
    t = ctx.flags.get("tier")
    if t is not None and t not in TIERS:
        raise usage(f"{ctx.name}: --tier must be provisional|confirmed|deprecated")
    return t


@verb("knowledge", "hit", values=("topic", "title"))
def knowledge_hit(ctx):
    f = ctx.flags
    need(ctx, "topic", "title")
    base = {"topic": f["topic"], "title": f["title"]}
    if f["topic"] == "Glossary":
        return {**base, "hits": 0, "tier": "provisional", "promoted": False,
                "promotionBlocked": False, "changed": False}, "glossary: not tracked"
    rc, _, err = ctx.helper("hv-knowledge-hit", *scope_args(ctx), "--topic", f["topic"],
                            "--title", f["title"])
    if rc != 0:
        raise write_failure(rc, err, first_error_line(err) or f"old helper failed (rc {rc})")
    state = tier_get(ctx, f["topic"], f["title"])
    return ({**base, "hits": state.get("hits", 0), "tier": state.get("tier", "provisional"),
             "promoted": "auto-promoted:" in err, "promotionBlocked": "skip-auto-promote:" in err,
             "changed": True}, f"hit: {f['topic']} :: {f['title']}")


@verb("knowledge", "tier", "get", values=("topic", "title"))
def knowledge_tier_get(ctx):
    f = ctx.flags
    need(ctx, "topic", "title")
    data = {"topic": f["topic"], "title": f["title"], "found": False}
    if f["topic"] != "Glossary":
        state = tier_get(ctx, f["topic"], f["title"])
        if state:
            data.update(found=True, tier=state["tier"], hits=state["hits"],
                        lastSeen=state["lastSeen"])
    return data, json.dumps(data)


@verb("knowledge", "tier", "set", values=("topic", "title", "tier"))
def knowledge_tier_set(ctx):
    f = ctx.flags
    need(ctx, "topic", "title", "tier")
    if tier_filter(ctx) is None:
        raise usage(f"{ctx.name}: --tier is required")
    data = {"topic": f["topic"], "title": f["title"], "tier": f["tier"]}
    if f["topic"] == "Glossary":
        return {**data, "changed": False}, "glossary: not tracked"
    prev = tier_get(ctx, f["topic"], f["title"])
    call(ctx, "hv-knowledge-tier", *scope_args(ctx), "--set", "--topic", f["topic"],
         "--title", f["title"], "--tier", f["tier"])
    if prev:
        data["previousTier"] = prev["tier"]
    data["changed"] = prev.get("tier") != f["tier"]
    return data, f"tier: {f['topic']} :: {f['title']} = {f['tier']}"


@verb("knowledge", "tier", "list", values=("tier",))
def knowledge_tier_list(ctx):
    t = tier_filter(ctx)
    out = call(ctx, "hv-knowledge-tier", *scope_args(ctx), "--list", *(["--tier", t] if t else []))
    return {"entries": json_body(out)}, out


# ---------------------------------------------------------------- contradictions

def contradictions(ctx):
    return json_body(call(ctx, "hv-knowledge-contradiction", "--list"))


@verb("knowledge", "contradiction", "add", values=("topic", "title", "text"), repo=False)
def knowledge_contradiction_add(ctx):
    f = ctx.flags
    need(ctx, "topic", "title", "text")
    call(ctx, "hv-knowledge-contradiction", "--add", "--topic", f["topic"], "--title",
         f["title"], "--text", f["text"])
    return ({"topic": f["topic"], "title": f["title"], "pending": len(contradictions(ctx)),
             "changed": True}, f"queued: {f['topic']} :: {f['title']}")


@verb("knowledge", "contradiction", "list", repo=False)
def knowledge_contradiction_list(ctx):
    out = call(ctx, "hv-knowledge-contradiction", "--list")
    return {"items": json_body(out)}, out


@verb("knowledge", "contradiction", "clear", repo=False)
def knowledge_contradiction_clear(ctx):
    cleared = len(contradictions(ctx))
    call(ctx, "hv-knowledge-contradiction", "--clear")
    return {"cleared": cleared, "changed": cleared > 0}, f"cleared: {cleared}"


@verb("knowledge", "contradiction", "has", values=("topic", "title"), repo=False)
def knowledge_contradiction_has(ctx):
    f = ctx.flags
    need(ctx, "topic", "title")
    rc, _, err = ctx.helper("hv-knowledge-contradiction", "--has", "--topic", f["topic"],
                            "--title", f["title"])
    if rc == 0:
        return {"has": True}, "has"
    if rc == 1 and not err.strip():
        raise HvError(1, "pair is not in the contradiction queue", data={"has": False})
    raise HvError(70, first_error_line(err) or f"old helper failed (rc {rc})")
