echo "umbrella mode S02 (--repo flags + reconcile + worktree-clear)"

echo '{"active":[]}' > "$UMB/.hv/status.json"
echo "web,api" | (cd "$UMB" && "$BIN/hv-umbrella-init" >/dev/null)

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" hv/x B01)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
assert d['active'][0]['repo'] is None, d
assert d['active'][0]['branch'] == 'hv/x'
"
pass "T1: hv-status-add (no --repo) writes repo: null"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" --repo web hv/x B01)
(cd "$UMB" && "$BIN/hv-status-add" --repo api hv/x B02)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['branch'], e['repo']) for e in d['active'])
assert pairs == [('hv/x', 'api'), ('hv/x', 'web')], pairs
"
pass "T1: hv-status-add (--repo web) and (--repo api) coexist on same branch"

(cd "$UMB" && "$BIN/hv-status-add" --if-absent --repo web hv/x B01)
COUNT=$(python3 -c "import json; print(len(json.load(open('$UMB/.hv/status.json'))['active']))")
[ "$COUNT" = "2" ] || fail "if-absent should be no-op for existing (branch, repo); got count $COUNT"
pass "T1: hv-status-add --if-absent --repo respects (branch, repo) uniqueness"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" --repo web --if-absent hv/y B01)
(cd "$UMB" && "$BIN/hv-status-add" --if-absent --repo api hv/y B02)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['branch'], e['repo']) for e in d['active'])
assert pairs == [('hv/y', 'api'), ('hv/y', 'web')], pairs
"
pass "T1: hv-status-add accepts --repo and --if-absent in either order"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" hv/z B01)
(cd "$UMB" && "$BIN/hv-status-add" --repo web hv/z B02)
(cd "$UMB" && "$BIN/hv-status-remove" hv/z)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = [(e['branch'], e['repo']) for e in d['active']]
assert pairs == [('hv/z', 'web')], pairs
"
pass "T1: hv-status-remove (no --repo) preserves umbrella entries"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add" --repo web hv/z B01)
(cd "$UMB" && "$BIN/hv-status-add" --repo api hv/z B02)
(cd "$UMB" && "$BIN/hv-status-remove" --repo web hv/z)
python3 -c "
import json; d=json.load(open('$UMB/.hv/status.json'))
pairs = [(e['branch'], e['repo']) for e in d['active']]
assert pairs == [('hv/z', 'api')], pairs
"
pass "T1: hv-status-remove --repo web only removes web entry"

(cd "$UMB/web" && git checkout -q -b hv/feat-merge && echo "x" > x.txt && git add x.txt && git -c user.email=t@t -c user.name=t commit -q -m "feat: x")
WEB_HEAD_BEFORE=$(cd "$UMB/web" && git -c init.defaultBranch=main rev-parse main)
(cd "$UMB" && printf 'merge: feat-merge\n\n- added x\n' | "$BIN/hv-merge" --repo web hv/feat-merge >/dev/null)
WEB_HEAD_AFTER=$(cd "$UMB/web" && git rev-parse main)
[ "$WEB_HEAD_BEFORE" != "$WEB_HEAD_AFTER" ] || fail "hv-merge --repo web did not advance web/main"
if (cd "$UMB/web" && git rev-parse --verify hv/feat-merge >/dev/null 2>&1); then
  fail "hv-merge --repo web did not delete the feature branch"
fi
[ ! -d "$UMB/.git" ] || fail "hv-merge --repo web should NOT create umbrella .git/"
pass "T2: hv-merge --repo web lands the merge in web/.git/, not umbrella"

echo '{"active":[]}' > "$UMB/.hv/status.json"
(cd "$UMB/web" && git checkout -q main && git branch hv/recon-live 2>/dev/null || true)
(cd "$UMB" && "$BIN/hv-status-add" --repo web hv/recon-live B01)
(cd "$UMB" && "$BIN/hv-status-add" --repo api hv/recon-dead B02)
OUT=$(cd "$UMB" && "$BIN/hv-reconcile")
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
na = d['needsAction']
cl = d['cleaned']
assert any(e['branch'] == 'hv/recon-live' and e.get('repo') == 'web' for e in na), na
assert any(e['branch'] == 'hv/recon-dead' and e.get('repo') == 'api' for e in cl), cl
"
pass "T3: hv-reconcile output entries carry repo field"

(cd "$UMB" && "$BIN/hv-status-add" --repo nonexistent hv/recon-x B03)
OUT=$(cd "$UMB" && "$BIN/hv-reconcile")
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
cl = d['cleaned']
assert any(e.get('reason') == 'repo_unregistered' and e.get('repo') == 'nonexistent' for e in cl), cl
"
pass "T3: hv-reconcile flags entries pointing at unregistered repos"

(cd "$UMB/web" && git checkout -q main && git branch hv/wt-x 2>/dev/null || true)
mkdir -p "$UMB/.claude/worktrees/web"
(cd "$UMB/web" && git worktree add "$UMB/.claude/worktrees/web/hv-wt-x" hv/wt-x >/dev/null 2>&1)
[ -d "$UMB/.claude/worktrees/web/hv-wt-x" ] || fail "Layout B worktree setup failed"
(cd "$UMB/web" && "$BIN/hv-worktree-clear" --repo web hv/wt-x)
[ ! -d "$UMB/.claude/worktrees/web/hv-wt-x" ] || fail "Layout B worktree was not cleaned up"
pass "T4: hv-worktree-clear --repo web removes Layout B worktree"
(cd "$UMB/web" && git branch -D hv/wt-x >/dev/null 2>&1) || true

OUT=$(cd "$TMP" && "$BIN/hv-reconcile")
echo "$OUT" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert 'cleaned' in d and 'needsAction' in d
for e in d['needsAction']:
    assert e.get('repo') in (None, ''), e
"
pass "single-repo backward compat: hv-reconcile schema unchanged"

cp "$TMP/.hv/status.json" "$TMP/.hv/status.json.bak"
echo '{"active":[]}' > "$TMP/.hv/status.json"
(cd "$TMP" && "$BIN/hv-status-add" hv/legacy L01)
python3 -c "
import json; d=json.load(open('$TMP/.hv/status.json'))
e = d['active'][0]
assert e['branch'] == 'hv/legacy' and e['repo'] is None, e
"
(cd "$TMP" && "$BIN/hv-status-remove" hv/legacy)
python3 -c "
import json; d=json.load(open('$TMP/.hv/status.json'))
assert d['active'] == [], d
"
mv "$TMP/.hv/status.json.bak" "$TMP/.hv/status.json"
pass "single-repo backward compat: hv-status-add and hv-status-remove without flags"

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

RESULT2=$(PYTHONPATH="$BIN" python3 -c "
from hvlib import parse_todo_fields
r = parse_todo_fields('- **[B07] [P1] T.** D. Milestone: M01')
print(r['milestone'])
")
[ "$RESULT2" = "M01" ] || fail "parse_todo_fields Milestone without Repos: expected M01, got '$RESULT2'"
pass "parse_todo_fields Milestone capture without Repos field unchanged"

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

# Empty registry case
echo '{"repos": []}' > .hv/repos.json
EMPTY=$(PYTHONPATH="$BIN" python3 -c "from hvlib import load_repos; print(load_repos())")
[ "$EMPTY" = "{}" ] || fail "load_repos empty registry: expected {}, got '$EMPTY'"
pass "load_repos returns {} for empty registry"

cd ..

echo "hv-base-branch walks up to umbrella config"
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
# From inside the sub-repo (no .hv/), hv-base-branch should find umbrella's develop
RESULT=$("$BIN/hv-base-branch")
[ "$RESULT" = "develop" ] || fail "hv-base-branch from sub-repo: expected develop, got '$RESULT'"
pass "hv-base-branch walks up to umbrella .hv/config.json from sub-repo"
cd ../..

echo "hv-summary shows repo for umbrella active entries"
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
OUT=$("$BIN/hv-summary")
echo "$OUT" | grep -q "(repo: web)" || fail "hv-summary missing (repo: web): $OUT"
pass "hv-summary shows (repo: <name>) for umbrella active entry"

# And: legacy entry without repo doesn't show parenthetical
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z"}]}
EOF
OUT=$("$BIN/hv-summary")
if echo "$OUT" | grep -q "repo:"; then fail "hv-summary unexpectedly shows 'repo:' for non-umbrella entry: $OUT"; fi
pass "hv-summary does not show repo: for legacy active entries"
cd ..

echo "hv-backlog In Progress Repo column"
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

# With umbrella entry: column should appear
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z", "repo": "web"}]}
EOF
OUT=$("$BIN/hv-backlog")
echo "$OUT" | grep -q "| Repo |" || fail "hv-backlog missing Repo column: $OUT"
pass "hv-backlog adds Repo column when active entry has repo"

# Legacy entry: column should NOT appear
cat > .hv/status.json <<'EOF'
{"active": [{"branch": "hv/foo", "items": ["B01"], "startedAt": "2026-05-01T12:00:00Z"}]}
EOF
OUT=$("$BIN/hv-backlog")
if echo "$OUT" | grep -q "| Repo |"; then fail "hv-backlog unexpectedly shows Repo column: $OUT"; fi
pass "hv-backlog omits Repo column when no active entry has repo"
cd ..

echo "hv-preflight gates on repos.json under umbrella mode"
mkdir pf-test && cd pf-test
mkdir -p .hv/bin
# Seed minimal required files
echo "" > .hv/DECISIONS.md
echo "" > .hv/BACKLOG.md
echo "" > .hv/KNOWLEDGE.md
echo "" > .hv/MILESTONES.md
echo "{}" > .hv/counters.json
echo '{"active":[]}' > .hv/status.json
# Copy hvlib*.py (hvlib.py + split-out hvlib_io.py / hvlib_version.py) + hv-preflight
# (preflight discovers helpers from its own dir's siblings; hvlib.py imports from the
# split modules at import time so all three must travel together)
cp "$BIN"/hvlib*.py .hv/bin/
for f in "$BIN"/hv-*; do cp "$f" .hv/bin/ && chmod +x ".hv/bin/$(basename $f)"; done

# Single-repo: no repos.json needed
echo '{"umbrella": {"enabled": false}}' > .hv/config.json
.hv/bin/hv-preflight && pass "hv-preflight passes single-repo without repos.json" || fail "hv-preflight failed single-repo"

# Umbrella enabled, repos.json missing: ADVISORY (warn to stderr, exit 0).
# Per DECISIONS.md > Architecture > "Persistence-trio scoping under umbrella
# mode": data is truth; the config flag is informational. Earlier versions
# of preflight blocked here; the rule was relaxed to advisory in v3.x.
echo '{"umbrella": {"enabled": true}}' > .hv/config.json
WARN=$(.hv/bin/hv-preflight 2>&1 >/dev/null) || fail "hv-preflight should exit 0 (advisory) when umbrella.enabled and repos.json missing"
echo "$WARN" | grep -q "umbrella.enabled=true" || fail "hv-preflight expected warning about umbrella mismatch, got: $WARN"
pass "hv-preflight warns advisory when umbrella.enabled and repos.json missing"

# Umbrella enabled, repos.json with at least one entry: pass (silent)
echo '{"repos": [{"name": "web", "path": "./web"}]}' > .hv/repos.json
.hv/bin/hv-preflight && pass "hv-preflight passes with umbrella.enabled and valid repos.json" || fail "hv-preflight failed with valid repos.json"

# Umbrella enabled, repos.json empty: ADVISORY (warn to stderr, exit 0).
echo '{"repos": []}' > .hv/repos.json
WARN=$(.hv/bin/hv-preflight 2>&1 >/dev/null) || fail "hv-preflight should exit 0 (advisory) when umbrella.enabled and repos.json empty"
echo "$WARN" | grep -q "umbrella.enabled=true" || fail "hv-preflight expected warning about empty repos.json, got: $WARN"
pass "hv-preflight warns advisory when umbrella.enabled and repos.json empty"

# Umbrella DISABLED but repos.json valid: pass (data is truth; flag is informational).
# Exercises the B15 fix — /hv-next must reconcile when repos.json is present
# even if a stale config has umbrella.enabled: false.
echo '{"umbrella": {"enabled": false}}' > .hv/config.json
echo '{"repos": [{"name": "web", "path": "./web"}]}' > .hv/repos.json
.hv/bin/hv-preflight && pass "hv-preflight passes with umbrella.enabled:false but valid repos.json (data is truth)" || fail "hv-preflight failed when repos.json valid but flag false"

# Direct test of hv-umbrella-on: repos.json wins over the config flag.
OUT=$(.hv/bin/hv-umbrella-on)
[ "$OUT" = "yes" ] || fail "hv-umbrella-on expected 'yes' from repos.json regardless of config flag, got '$OUT'"
pass "hv-umbrella-on returns 'yes' from repos.json regardless of config flag"
cd ..

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
cd ../../..

