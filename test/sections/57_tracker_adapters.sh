echo "tracker adapters"

TMP_TA="$(mktemp -d)"
trap 'rm -rf "$TMP_TA"' EXIT

for prov in github gitlab; do
  P="$TMP_TA/$prov"; mkdir -p "$P/.hv"
  echo "{\"issues\":{\"provider\":\"$prov\",\"retryWaitSeconds\":0}}" > "$P/.hv/config.json"
  (
    cd "$P"
    export BIN PATH="$TESTDIR/fakes:$PATH" FAKE_TRACKER_DB="$P/db.json" FAKE_TRACKER_LOG="$P/log"
    TCALL() { "$BIN/hv-tracker-call" -- "$@" </dev/null; }
    if [ "$prov" = github ]; then
      TCALL api repos/fake/repo/milestones -f title=M07 >/dev/null
      for l in bug p1 extra; do TCALL label create "$l" >/dev/null; done
    else
      TCALL api projects/:id/milestones -f title=M07 >/dev/null
    fi
    PROV="$prov" PYTHONPATH="$BIN" python3 - <<'PY' || fail "$prov adapter flow"
import json, os, subprocess
from hvlib import adapter_for, TrackerError, load_config
prov = os.environ["PROV"]
a = adapter_for(load_config())
assert a.provider == prov, a.provider
assert adapter_for({}, prov).provider == prov
n = a.create("First", "line1\nline2 with `ticks`", labels=("bug", "p1"), milestone="M07")
assert n == 1, n
g = a.get(n)
keys = {"number","title","body","labels","milestone","state","closed_at","url","assignees"}
assert set(g) == keys, set(g) ^ keys
assert g["title"] == "First" and g["body"] == "line1\nline2 with `ticks`", g
assert sorted(g["labels"]) == ["bug", "p1"] and g["milestone"] == "M07", g
assert g["state"] == "open" and g["closed_at"] is None and g["assignees"] == [], g
assert g["url"].endswith("/1"), g["url"]
b = a.create("Second", "b2", labels=("bug",))
assert b == 2
assert sorted(i["number"] for i in a.list()) == [1, 2]
assert [i["number"] for i in a.list(labels=("p1",))] == [1]
assert [i["number"] for i in a.list(milestone="M07")] == [1]
assert a.list(state="closed") == []
# close issue 2 through the tracker CLI
cli = ["issue", "close", "2"]
subprocess.run([os.path.join(os.environ["BIN"], "hv-tracker-call"), "--provider", prov, "--", *cli],
               stdin=subprocess.DEVNULL, check=True, capture_output=True)
assert [i["number"] for i in a.list(state="open")] == [1]
cl = a.list(state="closed")
assert [i["number"] for i in cl] == [2] and cl[0]["state"] == "closed" and cl[0]["closed_at"], cl
assert sorted(i["number"] for i in a.list(state="all")) == [1, 2]
assert set(cl[0]) == keys
# edit
a.edit(1, title="First!", body="new body\nmore", add_labels=("extra",), remove_labels=("p1",))
g = a.get(1)
assert g["title"] == "First!" and g["body"] == "new body\nmore", g
assert sorted(g["labels"]) == ["bug", "extra"], g
a.edit(1, remove_milestone=True)
assert a.get(1)["milestone"] is None
a.edit(1, milestone="M07")
assert a.get(1)["milestone"] == "M07"
# comments
cmd = ["issue", "comment", "1", "--body", "hello"] if prov == "github" else ["issue", "note", "1", "--message", "hello"]
subprocess.run([os.path.join(os.environ["BIN"], "hv-tracker-call"), "--provider", prov, "--", *cmd],
               stdin=subprocess.DEVNULL, check=True, capture_output=True)
g = a.get(1, comments=True)
assert set(g) == keys | {"comments"}, set(g)
assert len(g["comments"]) == 1 and g["comments"][0]["body"] == "hello", g["comments"]
assert set(g["comments"][0]) == {"id", "body", "author"}
assert "comments" not in a.get(1)
# error path
os.environ["FAKE_TRACKER_FAIL"] = "view"
try:
    a.get(1)
except TrackerError as e:
    assert e.code == 1, e.code
else:
    raise AssertionError("expected TrackerError")
del os.environ["FAKE_TRACKER_FAIL"]
print(json.dumps(sorted(a.get(1).keys())))
PY
  )
  pass "$prov adapter: create/get/list/edit/comments/error"
done

# provider resolution failure
(
  cd "$TMP_TA"; mkdir -p none/.hv; cd none; echo '{}' > .hv/config.json
  git init -q . 2>/dev/null
  PYTHONPATH="$BIN" python3 - <<'PY' || fail "adapter_for unknown provider"
from hvlib import adapter_for, TrackerError
try:
    adapter_for({})
except TrackerError as e:
    assert e.code == 3 and "issues.provider" in e.message
else:
    raise AssertionError
PY
)
pass "adapter_for raises TrackerError(3) when provider unknown"

trap 'rm -rf "$TMP"' EXIT
