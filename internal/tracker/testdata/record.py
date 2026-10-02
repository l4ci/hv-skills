#!/usr/bin/env python3
"""Record the M07 tracker adapters (bin/hvlib_tracker.py through bin/hv-tracker-call)
against the offline fake gh/glab (test/fakes/fake_tracker.py).

Every forge CLI call is captured (argv, stdin, stdout, stderr, exit code) together with
what the Python adapter returned, so the Go port replays the same calls with no network
and no Python, and must make the same calls and return the same values.

Usage: python3 internal/tracker/testdata/record.py [out-dir]   (default: this directory)
Writes <out-dir>/github.json and <out-dir>/gitlab.json. Re-run after changing a scenario.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BIN = os.path.join(REPO, "bin")
FAKE = os.path.join(REPO, "test", "fakes", "fake_tracker.py")
sys.path.insert(0, BIN)

from hvlib_tracker import TrackerError, adapter_for  # noqa: E402

# A wrapper that sits where gh/glab would and logs every call it forwards to the fake.
RECORDER = r'''#!/usr/bin/env python3
import json, os, subprocess, sys
tool = os.path.basename(sys.argv[0])
data = sys.stdin.buffer.read()
r = subprocess.run([sys.executable, os.environ["REC_FAKE"], tool, *sys.argv[1:]], input=data, capture_output=True)
with open(os.environ["REC_LOG"], "a") as f:
    f.write(json.dumps({"name": tool, "argv": sys.argv[1:], "stdin": data.decode(),
                        "stdout": r.stdout.decode(), "stderr": r.stderr.decode(), "code": r.returncode}) + "\n")
sys.stdout.buffer.write(r.stdout)
sys.stderr.buffer.write(r.stderr)
sys.exit(r.returncode)
'''

CLOSING_BODIES = [
    "Closes #1",
    "fixes: #2, resolves  #3 and closed #1",
    "prefixcloses #4 xfixes #5",
    "CLOSED #6 Fixed\t#7 resolve #8",
    "resolves#9 close # 10 close #11abc",
    "implements #12, implemented: #13",
    "éfixes #14 fixes #15 closes　#16",
    "",
]


def py(v):
    """JSON-safe copy of an adapter result."""
    return json.loads(json.dumps(v))


def scenario(prov):
    """Steps as (op, kwargs[, env]). op "call" runs hv-tracker-call directly; "closed_numbers"
    makes no call."""
    ms = "M07 Tracker"
    s = [
        ("create_milestone", {"title": ms, "description": "tracker port"}),
        ("create_milestone", {"title": "M08", "description": ""}),
        ("milestones", {}),
        ("edit_milestone", {"number": 2, "state": "closed"}),
        ("edit_milestone", {"number": 1, "title": ms, "description": "renamed"}),
        ("milestones", {"state": "open"}),
        ("milestones", {"state": "closed"}),
        ("find_milestone", {"hv_id": "M07"}),
        ("find_milestone", {"hv_id": "M0"}),
        ("find_milestone", {"hv_id": "M08"}),
        ("ensure_labels", {"names": ["bug", "p1", "bug", ""]}),
        ("ensure_labels", {"names": ["bug"]}),
        ("ensure_labels", {"names": ["nope"], "auto_create": False}),
        ("create", {"title": "First", "body": "line1\nline2 with `ticks` and $vars", "labels": ["bug", "p1"],
                    "milestone": ms}),
        ("create", {"title": "Second", "body": "b2"}),
        ("get", {"number": 1}),
        ("list", {}),
        ("list", {"labels": ["p1"]}),
        ("list", {"milestone": ms}),
        ("list", {"state": "closed"}),
        ("edit", {"number": 1, "title": "First!", "body": "new body\nmore", "remove_labels": ["p1"]}),
        ("add_labels", {"number": 1, "labels": ["extra", "extra", ""]}),
        ("get", {"number": 1}),
        ("remove_labels", {"number": 1, "labels": ["extra"]}),
        ("remove_labels", {"number": 1, "labels": []}),
        ("edit", {"number": 1, "remove_milestone": True}),
        ("get", {"number": 1}),
        ("edit", {"number": 1, "milestone": ms}),
        ("issues_in_milestone", {"title": ms}),
        ("add_comment", {"number": 1, "body": "hello"}),
        ("add_comment", {"number": 1, "body": "second\nline"}),
        ("comments", {"number": 1}),
        ("edit_comment", {"number": 1, "comment_id": 1, "body": "edited"}),
        ("delete_comment", {"number": 1, "comment_id": 2}),
        ("comments", {"number": 1}),
        ("get", {"number": 1, "comments": True}),
        ("assign_self", {"number": 1}),
        ("assign_self", {"number": 2}),
        ("get", {"number": 1}),
        ("close", {"number": 2, "reason": "not_planned", "comment": "duplicate"}),
        ("get", {"number": 2}),
        ("reopen", {"number": 2}),
        ("get", {"number": 2}),
        ("close", {"number": 2}),
        ("list", {"state": "closed"}),
        ("list", {"state": "all"}),
    ]
    if prov == "github":
        pr = ["pr", "create", "--title", "Fix it", "--body", "Closes #1, fixes: #2", "--head", "feat-1"]
        pr2 = ["pr", "create", "--title", "Other", "--body", "nothing here", "--head", "feat-2"]
        comment = ["issue", "comment", "1", "--body-file", "-"]
    else:
        pr = ["mr", "create", "--title", "Fix it", "--description", "Implements #1, fixes: #2",
              "--source-branch", "feat-1"]
        pr2 = ["mr", "create", "--title", "Other", "--description", "nothing here", "--source-branch", "feat-2"]
        comment = ["issue", "note", "1", "--message", "via call"]
    s += [
        ("call", {"args": pr}),
        ("call", {"args": pr2}),
        ("call", {"args": comment, "stdin": "via call\nwith stdin"}),
        ("call", {"args": ["issue", "list", "--json", "number", "--state", "all"]
                  if prov == "github" else ["issue", "list", "--output", "json", "--all"]}),
        ("call", {"args": ["issue", "view", "99"]}),
        ("open_prs", {}),
    ]
    first = 3 if prov == "github" else 1  # gh PRs share the issue counter
    s += [
        ("prs_closing", {"number": 1}),
        ("prs_closing", {"number": 2}),
        ("prs_closing", {"number": 9}),
        ("pr_comment", {"pr": first, "body": "lgtm\nmulti-line"}),
        ("pr_state", {"pr": first}),
        ("pr_checkout", {"pr": first + 1}),
        ("pr_merge", {"pr": first}),
        ("pr_state", {"pr": first}),
        ("get", {"number": 1}),
        ("pr_merge", {"pr": first}),
        ("get", {"number": 1}, {"FAKE_TRACKER_FAIL": "view"}),
        ("get", {"number": 1}, {"FAKE_TRACKER_FAIL": "view", "FAKE_TRACKER_FAIL_MSG": "secondary rate limit"}),
        ("list", {}, {"FAKE_TRACKER_FAIL": "list", "FAKE_TRACKER_FAIL_MSG": "API rate limit exceeded"}),
        ("get", {"number": 1}, {"FAKE_TRACKER_FAIL": "view", "FAKE_TRACKER_FAIL_MSG": f"run {'gh' if prov == 'github' else 'glab'} auth login"}),
        ("close", {"number": 1, "comment": "bye"}, {"FAKE_TRACKER_FAIL": "close"}),
    ]
    s += [("closed_numbers", {"body": b}) for b in CLOSING_BODIES]
    return s


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def record(prov, out_dir):
    with tempfile.TemporaryDirectory() as tmp:
        proj, fakes, log = os.path.join(tmp, "proj"), os.path.join(tmp, "bin"), os.path.join(tmp, "calls.log")
        os.makedirs(os.path.join(proj, ".hv"))
        os.makedirs(fakes)
        with open(os.path.join(proj, ".hv", "config.json"), "w") as f:
            json.dump({"issues": {"provider": prov, "retryWaitSeconds": 0}}, f)
        git(proj, "init", "-q", "-b", "main")
        git(proj, "-c", "user.email=r@x", "-c", "user.name=r", "commit", "-q", "--allow-empty", "-m", "init")
        for tool in ("gh", "glab"):
            p = os.path.join(fakes, tool)
            with open(p, "w") as f:
                f.write(RECORDER)
            os.chmod(p, 0o755)
        base_env = dict(os.environ, PATH=fakes + os.pathsep + os.environ["PATH"], REC_FAKE=FAKE, REC_LOG=log,
                        FAKE_TRACKER_DB=os.path.join(tmp, "db.json"))
        for k in ("FAKE_TRACKER_DB_DIR", "FAKE_TRACKER_FAIL", "FAKE_TRACKER_FAIL_MSG", "FAKE_TRACKER_LOG"):
            base_env.pop(k, None)
        os.chdir(proj)
        for tool in ("gh", "glab"):  # never reach a real forge
            found = shutil.which(tool, path=base_env["PATH"])
            if found != os.path.join(fakes, tool):
                sys.exit(f"record.py: {tool} resolves to {found}, not the recorder")
        adapter = adapter_for(None, prov)
        steps = []
        for st in scenario(prov):
            op, kw = st[0], st[1]
            os.environ.clear()
            os.environ.update(base_env, **(st[2] if len(st) > 2 else {}))
            open(log, "w").close()
            step = {"op": op, "args": kw}
            if len(st) > 2:
                step["env"] = st[2]
            if op == "call":
                stdin = kw.get("stdin")
                r = subprocess.run([os.path.join(BIN, "hv-tracker-call"), "--", *kw["args"]],
                                   input=(stdin or "").encode(), capture_output=True)
                step["result"] = {"stdout": r.stdout.decode(), "stderr": r.stderr.decode(), "code": r.returncode}
            else:
                try:
                    step["result"] = py(getattr(adapter, op)(**kw))
                except TrackerError as e:
                    step["error"] = {"code": e.code, "message": e.message}
            with open(log) as f:
                step["calls"] = [json.loads(line) for line in f]
            steps.append(step)
        os.environ.clear()
        os.environ.update(base_env)
        os.chdir(REPO)
    with open(os.path.join(out_dir, prov + ".json"), "w") as f:
        json.dump({"provider": prov, "steps": steps}, f, indent=1, ensure_ascii=False)
        f.write("\n")


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else HERE
    for prov in ("github", "gitlab"):
        record(prov, out_dir)


if __name__ == "__main__":
    main()
