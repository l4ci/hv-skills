# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv plan` adapters (cross-phase verbs).
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)


@verb("plan", "add", values=("title", "design", "repos", "milestone"), bools=("slice",),
      pos=(0, 1), repo=False)
def plan_add(ctx):
    f = ctx.flags
    slice_mode = bool(f.get("slice"))
    if ctx.pos and (slice_mode or "milestone" in f):
        raise usage(f"{ctx.name}: a key cannot be combined with --slice or --milestone")
    if slice_mode and not f.get("milestone"):
        raise usage(f"{ctx.name}: --slice needs --milestone")
    if not ctx.pos and not slice_mode:
        raise usage(f"{ctx.name}: give a <milestone>-<unit> key, or --milestone <M01> --slice")
    if not f.get("title"):
        raise usage(f"{ctx.name}: --title is required")
    if slice_mode:
        milestone, unit = f["milestone"], "slice"
    else:
        milestone, sep, unit = ctx.pos[0].partition("-")
        if not sep or not unit:
            raise usage(f"{ctx.name}: key must look like M01-B07, got '{ctx.pos[0]}'")
    args = []
    if f.get("repos"):
        args += ["--repo", ", ".join(n.strip() for n in f["repos"].split(",") if n.strip())]
    if f.get("design"):
        from item import issue_mode  # issue numbers can be one digit
        if not re.fullmatch(r"[BFT]\d+" if issue_mode(ctx) else r"[BFT]\d{2,}", f["design"]):
            raise usage(f"{ctx.name}: --design must be an item ID like B07, got '{f['design']}'")
        args += ["--design", f".hv/designs/{f['design']}.md"]
    rc, out, err = ctx.helper("hv-plan-add", *args, milestone, unit, f["title"])
    if rc != 0:
        msg = first_error_line(err)
        if "already exists" in err:
            raise HvError(4, msg, data={"blockedBy": "exists", "changed": False})
        if re.search(r"design file not found|not in \.hv/repos\.json|not found", err):
            raise HvError(3, msg)
        if rc == 1 and not re.search(r"usage:|must look like|must be|empty after parsing", err):
            raise HvError(3, msg)   # issue mode: milestone has no tracker
        if rc == 1:
            raise usage(msg)
        raise backend_error(rc, err)
    key = out.strip()
    kind = "slice" if unit == "slice" or re.fullmatch(r"S\d+", unit) else "item"
    return {"key": key, "unitKind": kind, "changed": True}, key


@verb("plan", "uncertain", pos=(1, 1), repo=False)
def plan_uncertain(ctx):
    from item import ident  # item.py owns the rule-11 id spelling
    item = ctx.pos[0]
    rc, out, err = ctx.helper("hv-uncertain", item)
    msg = first_error_line(err) or f"hv-uncertain failed (rc {rc})"
    if rc == 2:
        raise HvError(5 if "unavailable" in err else 3, msg)
    if rc in (3, 4):
        raise HvError({3: 5, 4: 6}[rc], msg)
    if rc == 1 and re.search(r"^error:", err, re.M):
        # Old rc 1 means "certain", but a tracker failure also exits 1, with an error line.
        raise HvError(5, msg)
    if rc not in (0, 1):
        raise HvError(70, msg)
    iid, itype = ident(ctx, item)
    reasons = [l.strip() for l in out.splitlines() if l.strip()]
    data = {"id": iid, "type": itype, "uncertain": rc == 0, "reasons": reasons if rc == 0 else []}
    if rc == 1:
        raise HvError(1, f"{item} is certain", data=data)
    return data, out


# ---------------------------------------------------------------- list, show, put, rm

PLAN_KEY = re.compile(r"M\d{2,}-(S\d+|[BFT]\d+)")


def plan_key(ctx):
    key = ctx.pos[0]
    if not PLAN_KEY.fullmatch(key):
        raise usage(f"{ctx.name}: key must look like M01-B07 or M01-S02, got '{key}'")
    return key


def plan_error(ctx, rc, err, hint=None):
    """Old plan helper failure -> contract exit. rc 1 is a missing plan, 2 a backend mismatch."""
    msg = first_error_line(err) or f"old helper failed (rc {rc})"
    if rc == 1:
        return HvError(3, msg, hint=hint)
    return backend_error(rc, err)


@verb("plan", "list", values=("milestone",), repo=False)
def plan_list(ctx):
    ms = ctx.flags.get("milestone")
    if ms is not None and not re.fullmatch(r"M\d{2,}", ms):
        raise usage(f"{ctx.name}: --milestone must look like M01, got '{ms}'")
    rc, out, err = ctx.helper("hv-plan-list", *([ms] if ms else []))
    if rc != 0:
        raise plan_error(ctx, rc, err)
    plans = json_body(out)
    for p in plans:
        repo = p.pop("repo", "")
        p["repos"] = [r.strip() for r in repo.split(",") if r.strip()]
    if "item plans live on their issues" in err:
        ctx.warnings.append("item plans live on their issues; listing slice plans only")
    return {"plans": plans}, out


@verb("plan", "show", pos=(1, 1), repo=False)
def plan_show(ctx):
    key = plan_key(ctx)
    rc, out, err = ctx.helper("hv-plan-show", key)
    if rc != 0:
        raise plan_error(ctx, rc, err)
    return {"key": key, "body": out}, out


@verb("plan", "put", values=("body-file",), pos=(1, 1), repo=False)
def plan_put(ctx):
    key = plan_key(ctx)
    given = ctx.flags.get("body-file")
    if not given:
        raise usage(f"{ctx.name}: --body-file is required")
    path, spool = stdin_to_file(given if given == "-" else os.path.join(ctx.cwd, given))
    try:
        if read_text(path) is None:
            raise usage(f"{ctx.name}: cannot read --body-file: {given}")
        before = ctx.helper("hv-plan-show", key)[1]
        rc, _, err = ctx.helper("hv-plan-put", key, "--body-file", path)
        if rc != 0:
            raise plan_error(ctx, rc, err, hint="hv plan add")
        after = ctx.helper("hv-plan-show", key)[1]
    finally:
        if spool:
            os.unlink(spool)
    return {"key": key, "changed": before != after}, f"updated {key}"


@verb("plan", "rm", pos=(1, 1), repo=False)
def plan_rm(ctx):
    key = plan_key(ctx)
    rc, _, err = ctx.helper("hv-plan-rm", key)
    if rc != 0:
        raise plan_error(ctx, rc, err)
    return {"key": key, "changed": True}, f"removed {key}"


# ---------------------------------------------------------------- validate-docs, rename-check

@verb("plan", "validate-docs", pos=(1, 1), repo=False)
def plan_validate_docs(ctx):
    key = plan_key(ctx)
    rc, out, err = ctx.helper("hv-plan-validate-docs", key)
    if rc == 1:
        raise HvError(3, first_error_line(err) or f"plan not found: {key}")
    if rc == 2:
        raise HvError(70, first_error_line(err) or "plan has no parseable frontmatter")
    if rc != 0:
        raise backend_error(rc, err)
    mismatches, cur = [], None
    for line in out.splitlines()[1:]:
        s = line.strip()
        if line.startswith("  - "):
            cur = {"path": line[4:].strip()}
            mismatches.append(cur)
        elif cur is None or not s:
            continue
        elif s.startswith("target repo: "):
            cur["targetRepo"] = s[len("target repo: "):]
        elif s.startswith("suggested alternative: "):
            cur["suggestion"] = s[len("suggested alternative: "):]
        else:
            cur["issue"] = s
    return {"key": key, "valid": not mismatches, "mismatches": mismatches}, out


@verb("plan", "rename-check", pos=(1, None), repo=False, root=False)
def plan_rename_check(ctx):
    # Runs in the -C/cwd directory, not the project root; pathspecs follow a literal `--`.
    rc, out, err = ctx.helper("hv-plan-rename-check", *ctx.pos)
    if rc != 0:
        raise backend_error(rc, err)
    files = [l for l in out.splitlines() if l]
    return {"files": files}, out
