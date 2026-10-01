"""Tracker adapters: one normalized issue API over gh and glab.

Every call goes through bin/hv-tracker-call (rate limits, pagination, provider checks).
hv-tracker-call runs the CLI in the process cwd, so call these with cwd = the project dir.
No caching: each method is one CLI round trip.

Normalized issue: {"number", "title", "body", "labels", "milestone" (title|None),
"state" ("open"|"closed"), "state_reason" ("completed"|"not_planned"|None), "closed_at",
"url", "assignees"}; get(comments=True) adds
"comments": [{"id", "body", "author"}].
"""
import json
import os
import re
import subprocess

from hvlib_config import config_value, tracker_label

_BIN = os.path.dirname(os.path.abspath(__file__))


class TrackerError(Exception):
    """code = hv-tracker-call / CLI exit code; message = stripped stderr text."""

    def __init__(self, code, message=""):
        super().__init__(f"[{code}] {message}")
        self.code = code
        self.message = message


def _int_or_raw(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return v


class _Adapter:
    provider = ""

    def _run(self, args, body=None):
        """Run hv-tracker-call; stdin is fed only when an argument is `-`."""
        cmd = [os.path.join(_BIN, "hv-tracker-call"), "--provider", self.provider, "--", *args]
        wants = "-" in args
        r = subprocess.run(
            cmd,
            input=(body or "").encode() if wants else None,
            stdin=None if wants else subprocess.DEVNULL,
            capture_output=True,
        )
        if r.returncode != 0:
            raise TrackerError(r.returncode, r.stderr.decode(errors="replace").strip())
        return r.stdout.decode(errors="replace")

    def _json(self, args):
        out = self._run(args)
        try:
            return json.loads(out)
        except ValueError:
            raise TrackerError(1, f"unparseable tracker output: {out[:200]!r}")

    @staticmethod
    def _number_from_url(out):
        m = re.search(r"/(\d+)\s*$", out.strip().splitlines()[-1] if out.strip() else "")
        if not m:
            raise TrackerError(1, f"cannot parse issue number from: {out.strip()[:200]!r}")
        return int(m.group(1))


class GitHubAdapter(_Adapter):
    provider = "github"
    _FIELDS = "number,title,body,labels,milestone,state,stateReason,closedAt,url,assignees"

    def create(self, title, body, labels=(), milestone=None):
        args = ["issue", "create", "--title", title, "--body-file", "-"]
        for l in labels:
            args += ["--label", l]
        if milestone:
            args += ["--milestone", milestone]
        return self._number_from_url(self._run(args, body))

    @staticmethod
    def _norm(d):
        ms = d.get("milestone")
        return {
            "number": d["number"],
            "title": d.get("title") or "",
            "body": d.get("body") or "",
            "labels": [l["name"] for l in d.get("labels") or []],
            "milestone": ms["title"] if ms else None,
            "state": "closed" if str(d.get("state", "")).upper() == "CLOSED" else "open",
            "state_reason": {"COMPLETED": "completed", "NOT_PLANNED": "not_planned"}.get(
                str(d.get("stateReason") or "").upper()),
            "closed_at": d.get("closedAt") or None,
            "url": d.get("url") or "",
            "assignees": [a["login"] for a in d.get("assignees") or []],
        }

    def get(self, number, comments=False):
        fields = self._FIELDS + (",comments" if comments else "")
        d = self._json(["issue", "view", str(number), "--json", fields])
        out = self._norm(d)
        if comments:
            out["comments"] = [
                {"id": _int_or_raw(c.get("id")), "body": c.get("body") or "",
                 "author": (c.get("author") or {}).get("login", "")}
                for c in d.get("comments") or []
            ]
        return out

    def list(self, state="open", labels=(), milestone=None):
        args = ["issue", "list", "--state", state, "--json", self._FIELDS]
        for l in labels:
            args += ["--label", l]
        if milestone:
            args += ["--milestone", milestone]
        return [self._norm(d) for d in self._json(args)]

    def edit(self, number, title=None, body=None, add_labels=(), remove_labels=(),
             milestone=None, remove_milestone=False):
        args = ["issue", "edit", str(number)]
        if title is not None:
            args += ["--title", title]
        if body is not None:
            args += ["--body-file", "-"]
        for l in add_labels:
            args += ["--add-label", l]
        for l in remove_labels:
            args += ["--remove-label", l]
        if milestone:
            args += ["--milestone", milestone]
        if remove_milestone:
            args += ["--remove-milestone"]
        self._run(args, body)


class GitLabAdapter(_Adapter):
    provider = "gitlab"
    not_planned_label = "not-planned"  # glab has no close reason; a label stands in

    def create(self, title, body, labels=(), milestone=None):
        args = ["issue", "create", "--title", title, "--description", body]
        if labels:
            args += ["--label", ",".join(labels)]
        if milestone:
            args += ["--milestone", milestone]
        args += ["-y"]
        return self._number_from_url(self._run(args))

    def _norm(self, d):
        ms = d.get("milestone")
        closed = d.get("state") == "closed"
        labels = list(d.get("labels") or [])
        return {
            "number": d["iid"],
            "title": d.get("title") or "",
            "body": d.get("description") or "",
            "labels": labels,
            "milestone": ms["title"] if ms else None,
            "state": "closed" if closed else "open",
            "state_reason": (("not_planned" if self.not_planned_label in labels else "completed")
                             if closed else None),
            "closed_at": d.get("closed_at") or None,
            "url": d.get("web_url") or "",
            "assignees": [a["username"] for a in d.get("assignees") or []],
        }

    def get(self, number, comments=False):
        args = ["issue", "view", str(number), "--output", "json"]
        if comments:
            args.append("--comments")
        d = self._json(args)
        out = self._norm(d)
        if comments:
            out["comments"] = [
                {"id": _int_or_raw(n.get("id")), "body": n.get("body") or "",
                 "author": (n.get("author") or {}).get("username", "")}
                for n in d.get("notes") or []
            ]
        return out

    def list(self, state="open", labels=(), milestone=None):
        args = ["issue", "list", "--output", "json"]
        if state == "all":
            args.append("--all")
        elif state == "closed":
            args.append("--closed")
        for l in labels:
            args += ["--label", l]
        if milestone:
            args += ["--milestone", milestone]
        return [self._norm(d) for d in self._json(args)]

    def edit(self, number, title=None, body=None, add_labels=(), remove_labels=(),
             milestone=None, remove_milestone=False):
        args = ["issue", "update", str(number)]
        if title is not None:
            args += ["--title", title]
        if body is not None:
            args += ["--description", body]
        if add_labels:
            args += ["--label", ",".join(add_labels)]
        if remove_labels:
            args += ["--unlabel", ",".join(remove_labels)]
        if milestone:
            args += ["--milestone", milestone]
        elif remove_milestone:
            # glab has no remove flag; an empty title clears the milestone.
            args += ["--milestone", ""]
        self._run(args)


def adapter_for(cfg, provider=None):
    """Adapter for provider, else issues.provider, else origin-URL detection (run in cwd)."""
    if provider in (None, "", "auto"):
        provider = config_value(cfg, "issues.provider")
    if provider not in ("github", "gitlab"):
        r = subprocess.run([os.path.join(_BIN, "hv-issues-provider")], capture_output=True, text=True)
        provider = r.stdout.strip()
    if provider == "github":
        return GitHubAdapter()
    if provider == "gitlab":
        a = GitLabAdapter()
        a.not_planned_label = tracker_label(cfg or {}, "notPlanned")
        return a
    raise TrackerError(3, "cannot determine provider (set issues.provider)")
