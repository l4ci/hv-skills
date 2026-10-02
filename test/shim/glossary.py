# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv glossary` adapters (A5).
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


def knowledge_snapshot(root):
    """Every KNOWLEDGE.md under .hv/, so `changed` covers the umbrella and any sub-repo scope."""
    snap = {}
    for d, _, files in os.walk(os.path.join(root, ".hv")):
        if "KNOWLEDGE.md" in files:
            p = os.path.join(d, "KNOWLEDGE.md")
            snap[p] = read_text(p)
    return snap


def scope_args(ctx):
    return ["--repo", ctx.repo] if ctx.repo else []


def writer_failure(rc, err):
    """Old rc plus stderr -> HvError: 2 stays usage, a missing target is 3, a collision is 4."""
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc == 3:
        return HvError(4, msg, data={"blockedBy": "alias-collision", "changed": False})
    if rc == 2 and re.search(r"missing|not found|unknown sub-repo|not registered|umbrella", err):
        return HvError(3, msg)
    return HvError(2 if rc in (1, 2) else 70, msg)


@verb("glossary", "read", pos=(1, None))
def glossary_read(ctx):
    rc, out, err = ctx.helper("hv-glossary-read", *scope_args(ctx), "--", *ctx.pos)
    if rc != 0:
        raise HvError(3 if rc == 2 else 70, first_error_line(err) or f"old helper failed (rc {rc})")
    return {"text": out}, out


@verb("glossary", "write", values=("def", "alias", "not"), bools=("touch",), pos=(1, 1))
def glossary_write(ctx):
    f = ctx.flags
    if "def" not in f or not f["def"]:
        raise usage(f"{ctx.name}: --def is required")
    root = find_root(ctx.cwd)
    before = knowledge_snapshot(root)
    args = [ctx.pos[0], "--def", f["def"]]
    for flag in ("alias", "not"):
        if flag in f:
            args += [f"--{flag}", f[flag]]
    if f.get("touch"):
        args.append("--touch")
    rc, _, err = ctx.helper("hv-glossary-write", *args, *scope_args(ctx))
    if rc != 0:
        raise writer_failure(rc, err)
    term = (re.findall(r"^wrote: Glossary/(.*)$", err, re.M) or [ctx.pos[0]])[-1]
    return {"term": term, "changed": knowledge_snapshot(root) != before}, f"wrote: Glossary/{term}"


@verb("glossary", "import", values=("body-file",), bools=("touch",))
def glossary_import(ctx):
    f = ctx.flags
    if "body-file" not in f:
        raise usage(f"{ctx.name}: --body-file is required")
    path, tmp = stdin_to_file(f["body-file"])
    try:
        if not os.path.isfile(path):
            raise HvError(3, f"manifest file '{f['body-file']}' not found")
        root = find_root(ctx.cwd)
        before = knowledge_snapshot(root)
        args = [os.path.abspath(path)] + (["--touch"] if f.get("touch") else [])
        rc, _, err = ctx.helper("hv-glossary-import", *args, *scope_args(ctx))
    finally:
        if tmp:
            os.unlink(tmp)
    if rc != 0:
        # The old helper's exit 2 covers both a bad manifest line (usage) and a missing
        # target; 3 was every refusal.
        if rc == 2 and re.search(r"manifest line", err):
            raise usage(first_error_line(err))
        raise writer_failure(rc, err)
    terms = re.findall(r"^wrote: Glossary/(.*)$", err, re.M)
    m = re.search(r"batch ok: (\d+) term", err)
    imported = int(m.group(1)) if m else 0
    return {"imported": imported, "terms": terms,
            "changed": knowledge_snapshot(root) != before}, f"imported {imported} term(s)"
