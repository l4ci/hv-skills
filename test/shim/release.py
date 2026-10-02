# Part of the temporary hv test shim (#46); removed in A9 (#53). See test/hv-shim.
# `hv release` adapters.
import os
import re

from core import *  # noqa: F401,F403  (shared shim helpers and @verb)

SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
LEVELS = ("patch", "minor", "major")
KINDS_KNOWN = ("plugin-json", "package-json", "pyproject", "cargo", "plain")


# ---------------------------------------------------------------- version and bump

def detect_version(ctx):
    """The old detect-version JSON: file, version, kind (exit 3 when nothing is found)."""
    rc, out, err = ctx.helper("hv-release-detect-version")
    if rc != 0:
        raise HvError(3, first_error_line(err) or "no version file detected")
    return json_body(out)


def bump_error(err, refused):
    """Old bump-version rc 1, split by message."""
    msg = first_error_line(err)
    if "strictly greater" in err:
        if refused:
            return HvError(4, msg, data={"blockedBy": "not greater", "changed": False})
        return HvError(1, msg)
    if re.search(r"bump must be|unknown kind", err):
        return HvError(2, msg)
    return HvError(3, msg)


def version_kind(path):
    """Manifest kind from the file name, as hvlib.infer_version_kind (None when unknown)."""
    name = os.path.basename(path)
    if name == "plugin.json":
        return "plugin-json"
    if name.endswith(".json"):
        return "package-json"
    if name == "pyproject.toml":
        return "pyproject"
    if name == "Cargo.toml":
        return "cargo"
    if name == "VERSION":
        return "plain"
    return None


def bump_arg(ctx):
    """The old third positional from --level or --to; None when neither is given."""
    level, to = ctx.flags.get("level"), ctx.flags.get("to")
    if level is not None and to is not None:
        raise usage(f"{ctx.name}: --level and --to are mutually exclusive")
    if level is not None:
        if level not in LEVELS:
            raise usage(f"{ctx.name}: --level must be patch|minor|major")
        return level
    if to is not None:
        if not SEMVER.match(to):
            raise usage(f"{ctx.name}: --to must be a bare X.Y.Z")
        return to
    return None


@verb("release", "version", values=("level", "to"))
def release_version(ctx):
    enter_repo(ctx)
    bump = bump_arg(ctx)
    cur = detect_version(ctx)
    data = {"file": cur["file"], "version": cur["version"], "kind": cur["kind"]}
    if bump is None:
        return data, cur["version"]
    rc, out, err = ctx.helper("hv-release-bump-version", "--dry-run", cur["file"], cur["kind"], bump)
    if rc != 0:
        e = bump_error(err, refused=False)
        if e.exit == 1:
            e.data = data
        raise e
    data["next"] = out.strip()
    return data, data["next"]


@verb("release", "bump", values=("level", "to", "file", "kind"))
def release_bump(ctx):
    enter_repo(ctx)
    f = ctx.flags
    bump = bump_arg(ctx)
    if bump is None:
        raise usage(f"{ctx.name}: one of --level or --to is required")
    if "file" in f:
        path = f["file"]
        kind = f.get("kind") or version_kind(path)
        if kind is None:
            raise usage(f"{ctx.name}: unknown version file name {os.path.basename(path)}; pass --kind")
    else:
        cur = detect_version(ctx)
        path, kind = cur["file"], f.get("kind") or cur["kind"]
    if kind not in KINDS_KNOWN:
        raise usage(f"{ctx.name}: --kind must be one of {', '.join(KINDS_KNOWN)}")
    if not os.path.exists(os.path.join(ctx.cwd, path)):
        raise HvError(3, f"file not found: {path}")
    old = read_version(ctx, path, kind)
    rc, out, err = ctx.helper("hv-release-bump-version", path, kind, bump)
    if rc != 0:
        raise bump_error(err, refused=True)
    new = out.strip()
    return {"file": path, "kind": kind, "from": old, "to": new, "changed": True}, new


def read_version(ctx, path, kind):
    """Current version of a version file, read before the bump writes it."""
    import sys
    from pathlib import Path
    if helpers_dir() not in sys.path:
        sys.path.insert(0, helpers_dir())
    from hvlib import get_version_or_die
    try:
        return get_version_or_die(Path(ctx.cwd) / path, kind)
    except SystemExit:
        raise HvError(3, f"{path}: cannot read a version")


# ---------------------------------------------------------------- host

@verb("release", "host")
def release_host(ctx):
    enter_repo(ctx)
    host = call(ctx, "hv-release-detect-host").strip()
    return {"host": host}, host


# ---------------------------------------------------------------- notes

def to_h3(markdown):
    """`## X` headings become `### X`; deeper ones stay."""
    return re.sub(r"^## ", "### ", markdown, flags=re.M)


@verb("release", "notes", values=("from", "since"), pos=(0, 1))
def release_notes(ctx):
    f, src = ctx.flags, ctx.flags.get("from")
    if src not in ("commits", "issues"):
        raise usage(f"{ctx.name}: --from must be commits|issues")
    if src == "commits":
        if ctx.pos:
            raise usage(f"{ctx.name}: a milestone is only for --from issues")
        enter_repo(ctx)
        rng = f"{f['since']}..HEAD" if f.get("since") else "HEAD"
        rc, out, err = ctx.helper("hv-release-changelog-from-commits", rng)
        if rc != 0:
            msg = first_error_line(err) or "git log failed"
            raise HvError(3 if re.search(r"unknown revision|bad revision|ambiguous argument", err) else 5, msg)
        md = to_h3(out)
        return {"from": "commits", "markdown": md, "empty": out.strip() == ""}, md
    if not ctx.pos:
        raise usage(f"{ctx.name}: --from issues needs a milestone ID")
    args = [ctx.pos[0]]
    if f.get("since"):
        args += ["--since", f["since"]]
    if ctx.repo:
        args += ["--repo", ctx.repo]
    rc, out, err = ctx.helper("hv-release-notes-from-issues", *args)
    if rc != 0:
        raise issue_error(rc, err)
    return {"from": "issues", "markdown": out, "empty": out.strip() == ""}, out


def issue_error(rc, err):
    """Old issue-only release helper failure -> HvError."""
    if rc == 1 and "--repo" in err:
        return HvError(2, first_error_line(err))
    e = backend_error(rc, err)
    if e.exit == 4:
        e.data = {"blockedBy": "backend", "changed": False}
    return e


# ---------------------------------------------------------------- changelog

@verb("release", "changelog", values=("body-file", "path"), pos=(1, 1))
def release_changelog(ctx):
    enter_repo(ctx)
    f, version = ctx.flags, ctx.pos[0]
    if not SEMVER.match(version):
        raise usage(f"{ctx.name}: version must be a bare X.Y.Z")
    if not f.get("body-file"):
        raise usage(f"{ctx.name}: --body-file is required")
    notes, spool = stdin_to_file(f["body-file"])
    try:
        if not os.path.exists(os.path.join(ctx.cwd, notes)):
            raise HvError(3, f"notes file not found: {f['body-file']}")
        args = [version, notes]
        if f.get("path"):
            args += ["--path", f["path"]]
        rc, out, err = ctx.helper("hv-release-update-changelog", *args)
    finally:
        if spool:
            os.unlink(spool)
    if rc != 0:
        msg = first_error_line(err)
        if "already has a section" in err:
            raise HvError(4, msg, data={"blockedBy": "exists", "changed": False})
        raise HvError(2 if "must match" in err else 3, msg)
    path = out.strip() or f.get("path") or "CHANGELOG.md"
    return {"path": path, "version": version, "changed": True}, path


# ---------------------------------------------------------------- pending

@verb("release", "pending")
def release_pending(ctx):
    enter_repo(ctx)
    rc, out, err = ctx.helper("hv-release-pending")
    if rc != 0:
        raise HvError(5, first_error_line(err) or "git failed")
    return json_body(out), out


# ---------------------------------------------------------------- milestone-check and close-milestone

@verb("release", "milestone-check", pos=(1, 1))
def release_milestone_check(ctx):
    args = [ctx.pos[0]]
    if ctx.repo:
        args += ["--repo", ctx.repo]
    rc, out, err = ctx.helper("hv-release-milestone-check", *args)
    if rc not in (0, 6):
        raise issue_error(rc, err)
    blocked, still_open = [], []
    for line in out.splitlines():
        m = re.match(r"^blocked: #(\d+) (.*) \[([^\]]+)\]$", line)
        if m:
            blocked.append({"number": int(m.group(1)), "title": m.group(2), "label": m.group(3)})
            continue
        m = re.match(r"^warning: #(\d+) (.*) \(still open\)$", line)
        if m:
            still_open.append({"number": int(m.group(1)), "title": m.group(2)})
    blocked.sort(key=lambda i: i["number"])
    still_open.sort(key=lambda i: i["number"])
    data = {"clear": not blocked, "blocked": blocked, "stillOpen": still_open}
    if blocked:
        raise HvError(1, f"{ctx.pos[0]} is blocked by {len(blocked)} open issue(s)", data=data)
    return data, out


@verb("release", "close-milestone", values=("release",), pos=(1, 1))
def release_close_milestone(ctx):
    mid, rel = ctx.pos[0], ctx.flags.get("release")
    if not rel or not SEMVER.match(rel):
        raise usage(f"{ctx.name}: --release must be a bare X.Y.Z")
    args = [mid, f"v{rel}"]
    if ctx.repo:
        args += ["--repo", ctx.repo]
    rc, out, err = ctx.helper("hv-release-close-milestone", *args)
    if rc != 0:
        raise issue_error(rc, err)
    m = re.search(r"closed-out (\S+) (\S+): (\d+) issues", out)
    if not m:
        raise HvError(70, f"unexpected close-out output: {out.strip()}")
    k = int(m.group(3))
    return {"milestone": m.group(1), "release": rel, "tag": m.group(2), "issues": k,
            "changed": k > 0}, out
