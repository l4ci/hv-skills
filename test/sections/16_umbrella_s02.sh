echo "umbrella mode S02 (--repo flags + worktree cleanup)"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && hvj init umbrella --repos web,api >/dev/null) || fail "init umbrella failed"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && hvj status add hv/x --items B01 >/dev/null) || fail "status add (no --repo) failed"
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
assert d['active'][0]['repo'] is None, d
assert d['active'][0]['branch'] == 'hv/x'
"
pass "T1: status add (no --repo) writes repo: null"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && hvj status add hv/x --items B01 --repo web >/dev/null) || fail "status add --repo web failed"
(cd "$UMB" && hvj status add hv/x --items B02 --repo api >/dev/null) || fail "status add --repo api failed"
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['branch'], e['repo']) for e in d['active'])
assert pairs == [('hv/x', 'api'), ('hv/x', 'web')], pairs
"
pass "T1: status add (--repo web) and (--repo api) coexist on same branch"

OUT=$(cd "$UMB" && hvj status add hv/x --items B01 --if-absent --repo web) || fail "status add --if-absent failed: $OUT"
[ "$(echo "$OUT" | jget data.changed)" = "false" ] || fail "if-absent on an existing (branch, repo) should report changed false: $OUT"
COUNT=$(python3 -c "import json; print(len(json.load(open('$UMB/.hv/status.json'))['active']))")
[ "$COUNT" = "2" ] || fail "if-absent should be no-op for existing (branch, repo); got count $COUNT"
pass "T1: status add --if-absent --repo respects (branch, repo) uniqueness"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && hvj status add hv/y --items B01 --repo web --if-absent >/dev/null) || fail "status add --repo web --if-absent failed"
(cd "$UMB" && hvj status add hv/y --items B02 --if-absent --repo api >/dev/null) || fail "status add --if-absent --repo api failed"
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['branch'], e['repo']) for e in d['active'])
assert pairs == [('hv/y', 'api'), ('hv/y', 'web')], pairs
"
pass "T1: status add accepts --repo and --if-absent in either order"

# A --repo that is not registered is a resolution error (exit 3), not a silent tag.
rc=0; (cd "$UMB" && "$HV_BIN" status add hv/recon-x --items B03 --repo nonexistent >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "status add --repo nonexistent should exit 3, got $rc"
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
assert not any(e['branch'] == 'hv/recon-x' for e in d['active']), d
"
pass "T1: status add --repo rejects an unregistered sub-repo (exit 3), writing nothing"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && hvj status add hv/z --items B01 >/dev/null) || fail "status add hv/z failed"
(cd "$UMB" && hvj status add hv/z --items B02 --repo web >/dev/null) || fail "status add hv/z --repo web failed"
(cd "$UMB" && hvj status rm hv/z >/dev/null) || fail "status rm (no --repo) failed"
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = [(e['branch'], e['repo']) for e in d['active']]
assert pairs == [('hv/z', 'web')], pairs
"
pass "T1: status rm (no --repo) preserves umbrella entries"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && hvj status add hv/z --items B01 --repo web >/dev/null) || fail "status add hv/z --repo web failed"
(cd "$UMB" && hvj status add hv/z --items B02 --repo api >/dev/null) || fail "status add hv/z --repo api failed"
(cd "$UMB" && hvj status rm hv/z --repo web >/dev/null) || fail "status rm --repo web failed"
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = [(e['branch'], e['repo']) for e in d['active']]
assert pairs == [('hv/z', 'api')], pairs
"
pass "T1: status rm --repo web only removes web entry"

(cd "$UMB/web" && git checkout -q -b hv/feat-merge && echo "x" > x.txt && git add x.txt && git -c user.email=t@t -c user.name=t commit -q -m "feat: x")
WEB_HEAD_BEFORE=$(cd "$UMB/web" && git -c init.defaultBranch=main rev-parse main)
(cd "$UMB" && printf 'merge: feat-merge\n\n- added x\n' | hvj ship merge hv/feat-merge --repo web --body-file - >/dev/null) \
  || fail "ship merge --repo web failed"
WEB_HEAD_AFTER=$(cd "$UMB/web" && git rev-parse main)
[ "$WEB_HEAD_BEFORE" != "$WEB_HEAD_AFTER" ] || fail "ship merge --repo web did not advance web/main"
if (cd "$UMB/web" && git rev-parse --verify hv/feat-merge >/dev/null 2>&1); then
  fail "ship merge --repo web did not delete the feature branch"
fi
[ ! -d "$UMB/.git" ] || fail "ship merge --repo web should NOT create umbrella .git/"
pass "T2: ship merge --repo web lands the merge in web/.git/, not umbrella"

# T4: merging a branch that has a Layout B worktree removes the worktree first.
(cd "$UMB/web" && git checkout -q main && git branch hv/wt-x 2>/dev/null || true)
mkdir -p "$UMB/.claude/worktrees/web"
(cd "$UMB/web" && git worktree add "$UMB/.claude/worktrees/web/hv-wt-x" hv/wt-x >/dev/null 2>&1)
[ -d "$UMB/.claude/worktrees/web/hv-wt-x" ] || fail "Layout B worktree setup failed"
(cd "$UMB/.claude/worktrees/web/hv-wt-x" && echo y > y.txt && git add y.txt && git -c user.email=t@t -c user.name=t commit -q -m "feat: y")
(cd "$UMB" && printf 'merge: wt-x\n\n- added y\n' | hvj ship merge hv/wt-x --repo web --body-file - >/dev/null) \
  || fail "ship merge --repo web of a worktree branch failed"
[ ! -d "$UMB/.claude/worktrees/web/hv-wt-x" ] || fail "Layout B worktree was not cleaned up by ship merge"
pass "T4: ship merge --repo web removes the Layout B worktree"
(cd "$UMB/web" && git branch -D hv/wt-x >/dev/null 2>&1) || true

# white-box-begin: go-unit A8 #52
(cd "$UMB/web" && git checkout -q main && git branch hv/wt-z 2>/dev/null || true)
mkdir -p "$UMB/.claude/worktrees/web"
(cd "$UMB/web" && git worktree add "$UMB/.claude/worktrees/web/hv-wt-z" hv/wt-z >/dev/null 2>&1)
[ -d "$UMB/.claude/worktrees/web/hv-wt-z" ] || fail "Layout B worktree setup failed"
(cd "$UMB/web" && "$BIN/hv-worktree-clear" --repo web hv/wt-z)
[ ! -d "$UMB/.claude/worktrees/web/hv-wt-z" ] || fail "Layout B worktree was not cleaned up"
pass "T4: hv-worktree-clear --repo web removes Layout B worktree"
# white-box-end
(cd "$UMB/web" && git branch -D hv/wt-z >/dev/null 2>&1) || true

cp "$TMP/.hv/status.json" "$TMP/.hv/status.json.bak"
echo '{"active":[]}' > "$TMP/.hv/status.json"
(cd "$TMP" && hvj status add hv/legacy --items L01 >/dev/null) || fail "status add without flags failed"
python3 -c "
import json; d=json.load(open('$TMP/.hv/status.json'))
e = d['active'][0]
assert e['branch'] == 'hv/legacy' and e['repo'] is None, e
"
(cd "$TMP" && hvj status rm hv/legacy >/dev/null) || fail "status rm without flags failed"
python3 -c "
import json; d=json.load(open('$TMP/.hv/status.json'))
assert d['active'] == [], d
"
mv "$TMP/.hv/status.json.bak" "$TMP/.hv/status.json"
pass "single-repo backward compat: status add and status rm without flags"

# white-box-begin: go-unit A4 #48
echo "parse_todo_fields Repos field"
RESULT=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import parse_todo_fields
r = parse_todo_fields('- **[F01] [Major] T.** D. Detail: x. Milestone: M02 Repos: web')
import json
print(json.dumps(r, sort_keys=True))
")
EXPECTED='{"captured": "", "detail": "x.", "milestone": "M02", "related": "", "repos": "web", "since": "", "subsystem": ""}'
[ "$RESULT" = "$EXPECTED" ] || fail "parse_todo_fields Repos: expected $EXPECTED, got $RESULT"
pass "parse_todo_fields captures Repos field without bleeding into Milestone"
# white-box-end

# white-box-begin: go-unit A4 #48
RESULT2=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import parse_todo_fields
r = parse_todo_fields('- **[B07] [P1] T.** D. Milestone: M01')
print(r['milestone'])
")
[ "$RESULT2" = "M01" ] || fail "parse_todo_fields Milestone without Repos: expected M01, got '$RESULT2'"
pass "parse_todo_fields Milestone capture without Repos field unchanged"
# white-box-end

# white-box-begin: go-unit A3 #47
echo "hvlib.load_repos"
mkdir lr-test && cd lr-test
mkdir -p .hv web api
cat > .hv/repos.json <<'EOF'
{"repos": [{"name": "web", "path": "./web"}, {"name": "api", "path": "./api"}]}
EOF
RESULT=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import load_repos
r = load_repos()
print(sorted(r.keys()))
")
[ "$RESULT" = "['api', 'web']" ] || fail "load_repos keys: expected ['api', 'web'], got $RESULT"
pass "load_repos returns name → path mapping"
# white-box-end

# white-box-begin: go-unit A3 #47
# Empty registry case
echo '{"repos": []}' > .hv/repos.json
EMPTY=$(PYTHONPATH="$BIN" python3 -c "from hvlib import load_repos; print(load_repos())")
[ "$EMPTY" = "{}" ] || fail "load_repos empty registry: expected {}, got '$EMPTY'"
pass "load_repos returns {} for empty registry"
# white-box-end

cd ..

echo "git base walks up to umbrella config"
mkdir bb-walk && cd bb-walk
# Create a fake umbrella with config.json, no git
mkdir -p .hv subrepo
cat > .hv/config.json <<'EOF'
{"git": {"baseBranch": "develop"}}
EOF
# Create a sub-repo with its own git tree, no .hv/
cd subrepo
git init -q
git config user.email t@t && git config user.name t
git checkout -q -b develop 2>/dev/null || git branch -m develop
echo "x" > f && git add f && git commit -q -m "seed"
# From inside the sub-repo (no .hv/), `git base` should find umbrella's develop
OUT=$(hvj git base) || fail "git base from sub-repo failed: $OUT"
[ "$(echo "$OUT" | jget data.base)" = "develop" ] || fail "git base from sub-repo: expected develop, got $OUT"
pass "git base walks up to umbrella .hv/config.json from sub-repo"
cd ../..

echo "summary shows repo for umbrella active entries"
mkdir sum-test && cd sum-test
mkdir -p .hv
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF
cat > .hv/MILESTONES.md <<'EOF'
# Milestones

## Active milestones

## Milestones
EOF
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z", "repo": "web"}]}
EOF
echo '{"bugs":0,"features":0,"tasks":0,"milestones":0}' > .hv/counters.json
OUT=$(hvj summary) || fail "summary failed: $OUT"
[ "$(echo "$OUT" | jget 'data.active[0].repo')" = "web" ] || fail "summary missing repo web on the active entry: $OUT"
pass "summary carries the repo for an umbrella active entry"

# And: legacy entry without repo carries no repo field
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z"}]}
EOF
OUT=$(hvj summary) || fail "summary failed: $OUT"
echo "$OUT" | jget 'data.active[0].repo' >/dev/null && fail "summary unexpectedly carries a repo for a non-umbrella entry: $OUT"
[ "$(echo "$OUT" | jget 'data.active[0].branch')" = "hv/foo" ] || fail "summary should still list the legacy active entry: $OUT"
pass "summary carries no repo for legacy active entries"
cd ..

echo "backlog list In Progress repo"
mkdir bl-test && cd bl-test
mkdir -p .hv
cat > .hv/BACKLOG.md <<'EOF'
# TODO

## Bugs

- **[B01] [P1] Title.** Body.

## Features

## Tasks

## Completed
EOF
cat > .hv/MILESTONES.md <<'EOF'
# Milestones

## Active milestones

## Milestones
EOF
echo '{"bugs":1,"features":0,"tasks":0,"milestones":0}' > .hv/counters.json

# With umbrella entry: the in-progress row names the repo
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z", "repo": "web"}]}
EOF
OUT=$(hvj backlog list) || fail "backlog list failed: $OUT"
[ "$(echo "$OUT" | jget 'data.inProgress[0].repo')" = "web" ] || fail "backlog list in-progress row missing repo: $OUT"
pass "backlog list names the repo on an in-progress row when the entry has one"

# Legacy entry: the row has no repo
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z"}]}
EOF
OUT=$(hvj backlog list) || fail "backlog list failed: $OUT"
echo "$OUT" | jget 'data.inProgress[0].repo' >/dev/null && fail "backlog list unexpectedly shows a repo: $OUT"
[ "$(echo "$OUT" | jget 'data.inProgress[0].id')" = "B01" ] || fail "backlog list should still list the in-progress row: $OUT"
pass "backlog list omits repo when no active entry has one"
cd ..

echo "init check gates on repos.json under umbrella mode"
mkdir pf-test && cd pf-test
hvj init >/dev/null || fail "init failed in pf-test"

# warn_count <envelope>: number of entries in `warnings` (0 when the key is absent).
warn_count() {
  python3 -c 'import json, sys; print(len(json.load(sys.stdin).get("warnings", [])))'
}

# Single-repo: no repos.json needed
rm -f .hv/repos.json
echo '{"umbrella": {"enabled": false}}' > .hv/config.json
OUT=$(hvj init check) || fail "init check failed single-repo: $OUT"
[ "$(echo "$OUT" | jget data.initialized)" = "true" ] || fail "init check single-repo: $OUT"
[ "$(echo "$OUT" | warn_count)" = "0" ] || fail "init check single-repo should not warn: $OUT"
pass "init check passes single-repo without repos.json"

# Umbrella enabled, repos.json missing: ADVISORY (a warning, exit 0).
# Per DECISIONS.md > Architecture > "Persistence-trio scoping under umbrella
# mode": data is truth; the config flag is informational. Earlier versions
# of preflight blocked here; the rule was relaxed to advisory in v3.x.
echo '{"umbrella": {"enabled": true}}' > .hv/config.json
OUT=$(hvj init check 2>/dev/null) || fail "init check should exit 0 (advisory) when umbrella.enabled and repos.json missing: $OUT"
[ "$(echo "$OUT" | warn_count)" -ge 1 ] || fail "init check expected a warning about the umbrella mismatch: $OUT"
grep -q "umbrella" <<<"$(jget 'warnings[0]' <<<"$OUT")" || fail "init check warning should mention umbrella: $OUT"
pass "init check warns advisory when umbrella.enabled and repos.json missing"

# Umbrella enabled, repos.json with at least one entry: pass (silent)
echo '{"repos": [{"name": "web", "path": "./web"}]}' > .hv/repos.json
OUT=$(hvj init check) || fail "init check failed with valid repos.json: $OUT"
[ "$(echo "$OUT" | warn_count)" = "0" ] || fail "init check with a valid registry should not warn: $OUT"
pass "init check passes with umbrella.enabled and valid repos.json"

# Umbrella enabled, repos.json empty: ADVISORY (a warning, exit 0).
echo '{"repos": []}' > .hv/repos.json
OUT=$(hvj init check 2>/dev/null) || fail "init check should exit 0 (advisory) when umbrella.enabled and repos.json empty: $OUT"
[ "$(echo "$OUT" | warn_count)" -ge 1 ] || fail "init check expected a warning about the empty repos.json: $OUT"
pass "init check warns advisory when umbrella.enabled and repos.json empty"

# Umbrella DISABLED but repos.json valid: pass (data is truth; flag is informational).
# Exercises the B15 fix — /hv-next must reconcile when repos.json is present
# even if a stale config has umbrella.enabled: false.
echo '{"umbrella": {"enabled": false}}' > .hv/config.json
echo '{"repos": [{"name": "web", "path": "./web"}]}' > .hv/repos.json
OUT=$(hvj init check) || fail "init check failed when repos.json valid but flag false: $OUT"
[ "$(echo "$OUT" | warn_count)" = "0" ] || fail "init check should not warn when repos.json is valid and the flag is false: $OUT"
pass "init check passes with umbrella.enabled:false but valid repos.json (data is truth)"

# Direct test of repo umbrella: repos.json wins over the config flag.
OUT=$(hvj repo umbrella) || fail "repo umbrella expected yes from repos.json regardless of config flag, got $OUT"
[ "$(echo "$OUT" | jget data.umbrella)" = "true" ] || fail "repo umbrella expected true: $OUT"
pass "repo umbrella is true from repos.json regardless of config flag"
cd ..

# white-box-begin: go-unit A3 #47
echo "hv-resolve-umbrella detects deep stray .hv/"
mkdir ru-deep && cd ru-deep
# umbrella + sub-repo registered + DEEP stray .hv/ inside sub-repo's source tree
mkdir -p .hv web/src/.hv
cat > .hv/repos.json <<'EOF'
{"repos": [{"name": "web", "path": "./web"}]}
EOF
cd web/src
RC=0; "$BIN/hv-resolve-umbrella" 2>/dev/null || RC=$?
[ "$RC" = "2" ] || fail "hv-resolve-umbrella deep stray expected exit 2, got $RC"
pass "hv-resolve-umbrella exits 2 on deep stray .hv/ inside registered sub-repo"
# white-box-end
cd ../../..
