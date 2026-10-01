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


_CLOSE_VERBS = r"close[sd]?|fix(?:es|ed)?|resolve[sd]?"
_CLOSING_RE = re.compile(rf"(?<![\w])(?:{_CLOSE_VERBS})\b:?\s+#(\d+)(?!\d)", re.I)
_CLOSING_RE_GL = re.compile(
    rf"(?<![\w])(?:{_CLOSE_VERBS}|implement(?:s|ed)?)\b:?\s+#(\d+)(?!\d)", re.I)


class _Adapter:
    provider = ""
    _closing_re = _CLOSING_RE
    cwd = None  # run the CLI here (umbrella: the sub-repo); None = the process cwd

    def closed_numbers(self, body):
        """Issue numbers a PR/MR body closes through a closing keyword
        (`Closes #3`, `fixes: #4`, ...), in order of appearance."""
        return list(dict.fromkeys(int(m) for m in self._closing_re.findall(body or "")))

    def prs_closing(self, number):
        """Open PRs/MRs whose body closes issue `number`:
        [{"number", "title", "branch", "url", "body"}]."""
        return [p for p in self.open_prs() if int(number) in self.closed_numbers(p["body"])]

    def _run(self, args, body=None):
        """Run hv-tracker-call; stdin is fed only when an argument is `-`."""
        cmd = [os.path.join(_BIN, "hv-tracker-call"), "--provider", self.provider, "--", *args]
        wants = "-" in args
        r = subprocess.run(
            cmd,
            input=(body or "").encode() if wants else None,
            stdin=None if wants else subprocess.DEVNULL,
            capture_output=True,
            cwd=self.cwd,
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

    def _pages(self, path):
        """Dicts from an `api` list call; tolerates paginated output that
        concatenates one JSON array per page."""
        out = self._run(["api", path]).strip()
        dec, pos, items = json.JSONDecoder(), 0, []
        try:
            while pos < len(out):
                page, end = dec.raw_decode(out, pos)
                items += page
                pos = end
                while pos < len(out) and out[pos].isspace():
                    pos += 1
        except (ValueError, TypeError):
            raise TrackerError(1, f"unparseable tracker output: {out[:200]!r}")
        return items

    _milestones = _pages

    def issues_in_milestone(self, title, state="all"):
        """Normalized issues assigned to the native milestone `title`."""
        return self.list(state=state, milestone=title)

    @staticmethod
    def _norm_milestone(d, number_key):
        return {
            "number": d[number_key],
            "title": d.get("title") or "",
            "description": d.get("description") or "",
            "state": "closed" if str(d.get("state", "")).lower() == "closed" else "open",
        }

    def _created_id(self, args):
        """Id of the object a POST `api` call created."""
        d = self._json(args)
        try:
            return int(d["id"])
        except (KeyError, TypeError, ValueError):
            raise TrackerError(1, f"cannot parse comment id from: {str(d)[:200]!r}")

    def add_labels(self, number, labels, auto_create=True):
        labels = [l for l in dict.fromkeys(labels) if l]
        if labels:
            self.ensure_labels(labels, auto_create=auto_create)
            self.edit(number, add_labels=labels)

    def remove_labels(self, number, labels):
        labels = [l for l in dict.fromkeys(labels) if l]
        if labels:
            self.edit(number, remove_labels=labels)

    @staticmethod
    def _match_milestone(items, hv_id):
        """Title of the milestone whose leading token is `hv_id`, preferring open ones."""
        pat = re.compile(re.escape(hv_id) + r"(?!\w)")
        hits = [m for m in items if pat.match((m.get("title") or "").strip())]
        hits.sort(key=lambda m: str(m.get("state", "")).lower() in ("closed",))
        return hits[0]["title"] if hits else None

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

    def ensure_labels(self, names, auto_create=True):
        """Make sure every label exists (gh refuses unknown ones). Missing ones are
        created when `auto_create`, else TrackerError(1)."""
        names = [n for n in dict.fromkeys(names) if n]
        if not names:
            return
        have = {l["name"] for l in self._json(["label", "list", "--json", "name", "--limit", "1000"])}
        for n in names:
            if n in have:
                continue
            if not auto_create:
                raise TrackerError(1, f"label '{n}' does not exist (issues.autoCreateLabel is off)")
            self._run(["label", "create", n, "--force"])

    def find_milestone(self, hv_id):
        """Native milestone title whose leading token is `hv_id` (open or closed), else None."""
        return self._match_milestone(
            self._milestones("repos/{owner}/{repo}/milestones?state=all&per_page=100"), hv_id)

    def milestones(self, state="all"):
        """Native milestones: [{"number", "title", "description", "state" ("open"|"closed")}]."""
        return [self._norm_milestone(d, "number") for d in self._milestones(
            f"repos/{{owner}}/{{repo}}/milestones?state={state}&per_page=100")]

    def create_milestone(self, title, description=""):
        """Create a native milestone and return its number."""
        d = self._json(["api", "-X", "POST", "repos/{owner}/{repo}/milestones",
                        "-f", f"title={title}", "-f", f"description={description}"])
        try:
            return int(d["number"])
        except (KeyError, TypeError, ValueError):
            raise TrackerError(1, f"cannot parse milestone number from: {str(d)[:200]!r}")

    def edit_milestone(self, number, title=None, description=None, state=None):
        """Rename, re-describe or open/close ("open"|"closed") a native milestone."""
        args = ["api", "-X", "PATCH", f"repos/{{owner}}/{{repo}}/milestones/{number}"]
        for k, v in (("title", title), ("description", description), ("state", state)):
            if v is not None:
                args += ["-f", f"{k}={v}"]
        self._run(args)

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

    def comments(self, number):
        """Comments oldest first: [{"id", "body", "author"}]."""
        return [{"id": _int_or_raw(c.get("id")), "body": c.get("body") or "",
                 "author": (c.get("user") or {}).get("login", "")}
                for c in self._pages(f"repos/{{owner}}/{{repo}}/issues/{number}/comments")]

    def add_comment(self, number, body):
        """Post a comment and return its id."""
        return self._created_id(
            ["api", "-X", "POST", f"repos/{{owner}}/{{repo}}/issues/{number}/comments", "-f", f"body={body}"])

    def edit_comment(self, number, comment_id, body):
        self._run(["api", "-X", "PATCH", f"repos/{{owner}}/{{repo}}/issues/comments/{comment_id}",
                   "-f", f"body={body}"])

    def delete_comment(self, number, comment_id):
        self._run(["api", "-X", "DELETE", f"repos/{{owner}}/{{repo}}/issues/comments/{comment_id}"])

    def close(self, number, reason="completed", comment=None):
        """Close with a state reason ("completed" | "not_planned") and optional comment."""
        args = ["issue", "close", str(number), "--reason",
                "not planned" if reason == "not_planned" else "completed"]
        if comment:
            args += ["--comment", comment]
        self._run(args)

    def reopen(self, number):
        self._run(["issue", "reopen", str(number)])

    def assign_self(self, number):
        self._run(["issue", "edit", str(number), "--add-assignee", "@me"])

    # -- pull requests -------------------------------------------------------

    def open_prs(self):
        """Every open PR: [{"number", "title", "branch", "url", "body"}]."""
        return [{"number": d["number"], "title": d.get("title") or "", "branch": d.get("headRefName") or "",
                 "url": d.get("url") or "", "body": d.get("body") or ""}
                for d in self._json(["pr", "list", "--state", "open", "--json",
                                     "number,title,body,headRefName,url"])]

    def pr_checkout(self, pr):
        self._run(["pr", "checkout", str(pr)])

    def pr_merge(self, pr):
        """Merge with a merge commit, delete the branch; returns the merge commit sha."""
        self._run(["pr", "merge", str(pr), "--merge", "--delete-branch"])
        oid = (self._json(["pr", "view", str(pr), "--json", "mergeCommit"]).get("mergeCommit") or {}).get("oid")
        if not oid:
            raise TrackerError(1, f"cannot read the merge commit of PR {pr}")
        return oid

    def pr_comment(self, pr, body):
        self._run(["pr", "comment", str(pr), "--body-file", "-"], body)

    def pr_state(self, pr):
        """"open" | "merged" | "closed"."""
        return str(self._json(["pr", "view", str(pr), "--json", "state"]).get("state", "")).lower()


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

    def ensure_labels(self, names, auto_create=True):
        """No-op: GitLab creates labels on first use."""

    def find_milestone(self, hv_id):
        """Native milestone title whose leading token is `hv_id` (open or closed), else None."""
        return self._match_milestone(self._milestones("projects/:id/milestones?per_page=100"), hv_id)

    def milestones(self, state="all"):
        """Native milestones: [{"number", "title", "description", "state" ("open"|"closed")}].
        `number` is the milestone's API id (what PUT .../milestones/<id> takes)."""
        want = {"open": "&state=active", "closed": "&state=closed"}.get(state, "")
        return [self._norm_milestone(d, "id") for d in self._milestones(
            f"projects/:id/milestones?per_page=100{want}")]

    def create_milestone(self, title, description=""):
        """Create a native milestone and return its id."""
        d = self._json(["api", "-X", "POST", "projects/:id/milestones",
                        "-f", f"title={title}", "-f", f"description={description}"])
        try:
            return int(d["id"])
        except (KeyError, TypeError, ValueError):
            raise TrackerError(1, f"cannot parse milestone id from: {str(d)[:200]!r}")

    def edit_milestone(self, number, title=None, description=None, state=None):
        """Rename, re-describe or open/close ("open"|"closed") a native milestone."""
        args = ["api", "-X", "PUT", f"projects/:id/milestones/{number}"]
        for k, v in (("title", title), ("description", description)):
            if v is not None:
                args += ["-f", f"{k}={v}"]
        if state is not None:
            args += ["-f", "state_event=" + ("close" if state == "closed" else "activate")]
        self._run(args)

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

    def comments(self, number):
        """Comments oldest first, system notes excluded: [{"id", "body", "author"}]."""
        return [{"id": _int_or_raw(n.get("id")), "body": n.get("body") or "",
                 "author": (n.get("author") or {}).get("username", "")}
                for n in self._pages(f"projects/:id/issues/{number}/notes?sort=asc&order_by=created_at")
                if not n.get("system")]

    def add_comment(self, number, body):
        """Post a comment and return its id."""
        return self._created_id(
            ["api", "-X", "POST", f"projects/:id/issues/{number}/notes", "-f", f"body={body}"])

    def edit_comment(self, number, comment_id, body):
        self._run(["api", "-X", "PUT", f"projects/:id/issues/{number}/notes/{comment_id}",
                   "-f", f"body={body}"])

    def delete_comment(self, number, comment_id):
        self._run(["api", "-X", "DELETE", f"projects/:id/issues/{number}/notes/{comment_id}"])

    def close(self, number, reason="completed", comment=None):
        """Close; glab has no state reason, so "not_planned" adds the not-planned label."""
        if comment:
            self._run(["issue", "note", str(number), "-m", comment])
        if reason == "not_planned":
            self.add_labels(number, [self.not_planned_label])
        self._run(["issue", "close", str(number)])

    def reopen(self, number):
        self._run(["issue", "reopen", str(number)])
        self.remove_labels(number, [self.not_planned_label])

    def assign_self(self, number):
        """glab 1.120 documents --assignee as usernames (no @me), so resolve ours once;
        the `+` prefix adds without replacing the other assignees."""
        if getattr(self, "_me", None) is None:
            self._me = self._json(["api", "user"]).get("username") or ""
            if not self._me:
                raise TrackerError(1, "cannot resolve the authenticated GitLab username")
        self._run(["issue", "update", str(number), "--assignee", "+" + self._me])

    # -- merge requests ------------------------------------------------------

    _closing_re = _CLOSING_RE_GL

    def open_prs(self):
        """Every open MR: [{"number", "title", "branch", "url", "body"}]."""
        return [{"number": d["iid"], "title": d.get("title") or "", "branch": d.get("source_branch") or "",
                 "url": d.get("web_url") or "", "body": d.get("description") or ""}
                for d in self._json(["mr", "list", "--output", "json"])]

    def pr_checkout(self, pr):
        self._run(["mr", "checkout", str(pr)])

    def pr_merge(self, pr):
        """Merge (merge commit), remove the source branch; returns the merge commit sha."""
        self._run(["mr", "merge", str(pr), "--yes", "--remove-source-branch"])
        sha = self._json(["mr", "view", str(pr), "--output", "json"]).get("merge_commit_sha")
        if not sha:
            raise TrackerError(1, f"cannot read the merge commit of MR {pr}")
        return sha

    def pr_comment(self, pr, body):
        self._run(["mr", "note", str(pr), "--message", body])

    def pr_state(self, pr):
        """"open" | "merged" | "closed"."""
        st = str(self._json(["mr", "view", str(pr), "--output", "json"]).get("state", "")).lower()
        return "open" if st == "opened" else st


def adapter_for(cfg, provider=None, cwd=None):
    """Adapter for provider, else issues.provider, else origin-URL detection (run in cwd).
    `cwd` (umbrella: a sub-repo path) is where detection and every CLI call run."""
    if provider in (None, "", "auto"):
        provider = config_value(cfg, "issues.provider")
    if provider not in ("github", "gitlab"):
        r = subprocess.run([os.path.join(_BIN, "hv-issues-provider")], capture_output=True, text=True, cwd=cwd)
        provider = r.stdout.strip()
    if provider == "github":
        a = GitHubAdapter()
    elif provider == "gitlab":
        a = GitLabAdapter()
        a.not_planned_label = tracker_label(cfg or {}, "notPlanned")
    else:
        raise TrackerError(3, "cannot determine provider (set issues.provider)")
    if cwd is not None:
        a.cwd = cwd
    return a
