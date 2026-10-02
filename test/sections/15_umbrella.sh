echo "umbrella mode (T1-T4)"

# Build a synthetic umbrella with 3 independent git repos (NO submodules)
UMB="$TMP/umbrella"
mkdir -p "$UMB"/{web,api,shared} "$UMB/.hv"
for r in web api shared; do
  (cd "$UMB/$r" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init)
done

# T4: init seeds repos.json
SEEDED=$(mktemp -d)
(cd "$SEEDED" && hvj init >/dev/null) || fail "init failed in a fresh directory"
[ -f "$SEEDED/.hv/repos.json" ] || fail "init did not seed .hv/repos.json"
python3 -c "import json; d=json.load(open('$SEEDED/.hv/repos.json')); assert d == {'repos':[]}, d" || fail "repos.json schema wrong"
pass "T4: init seeds .hv/repos.json with {\"repos\":[]}"
rm -rf "$SEEDED"

# T3: init umbrella scans children and writes the registry
OUT=$(cd "$UMB" && hvj init umbrella --repos web,api) || fail "init umbrella failed: $OUT"
python3 -c "import json; d=json.load(open('$UMB/.hv/repos.json')); names=sorted(r['name'] for r in d['repos']); assert names==['api','web'], names" || fail "registry schema wrong"
[ "$(echo "$OUT" | jget data.registered)" = '["api","web"]' ] || fail "init umbrella data.registered wrong: $OUT"
[ "$(echo "$OUT" | jget data.umbrellaIsGitRepo)" = "false" ] || fail "init umbrella: umbrella is not a git repo: $OUT"
[ "$(echo "$OUT" | jget data.changed)" = "true" ] || fail "first init umbrella should report changed: $OUT"
pass "T3: init umbrella writes sorted registry"

# T3: idempotent re-run
SHA_BEFORE=$(sha256sum "$UMB/.hv/repos.json" | cut -d' ' -f1)
OUT=$(cd "$UMB" && hvj init umbrella --repos web,api) || fail "init umbrella re-run failed: $OUT"
SHA_AFTER=$(sha256sum "$UMB/.hv/repos.json" | cut -d' ' -f1)
[ "$SHA_BEFORE" = "$SHA_AFTER" ] || fail "init umbrella not idempotent"
[ "$(echo "$OUT" | jget data.changed)" = "false" ] || fail "init umbrella re-run should report changed false: $OUT"
pass "T3: init umbrella idempotent on repeat run"

# T3: a directory with no git children exits 3
EMPTY="$TMP/empty-umbrella" && mkdir -p "$EMPTY/.hv"
rc=0; (cd "$EMPTY" && "$HV_BIN" init umbrella --repos "" >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "init umbrella should exit 3 on empty children, got $rc"
pass "T3: init umbrella exits 3 on empty children dir"

# T3: exactly one of --repos or --all
rc=0; (cd "$UMB" && "$HV_BIN" init umbrella >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "init umbrella with neither --repos nor --all should exit 2, got $rc"
rc=0; (cd "$UMB" && "$HV_BIN" init umbrella --repos web --all >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "init umbrella with both --repos and --all should exit 2, got $rc"
pass "T3: init umbrella needs exactly one of --repos / --all"

# T3: --all registers every git child; an unknown --repos name is ignored with a warning
ALL_TMP=$(mktemp -d)
mkdir -p "$ALL_TMP"/{one,two}
for r in one two; do
  (cd "$ALL_TMP/$r" && git init -q -b main)
done
OUT=$(cd "$ALL_TMP" && hvj init umbrella --all) || fail "init umbrella --all failed: $OUT"
[ "$(echo "$OUT" | jget data.registered)" = '["one","two"]' ] || fail "init umbrella --all should register every child: $OUT"
rm -rf "$ALL_TMP/.hv"
OUT=$(cd "$ALL_TMP" && hvj init umbrella --repos one,nope 2>/dev/null) || fail "init umbrella with an unknown name failed: $OUT"
[ "$(echo "$OUT" | jget data.registered)" = '["one"]' ] || fail "unknown name should be ignored: $OUT"
echo "$OUT" | jget 'warnings[0]' >/dev/null || fail "unknown name should add a warning: $OUT"
rm -rf "$ALL_TMP"
pass "T3: init umbrella --all registers every child; unknown names warn"

# T1: the working directory is inside an umbrella from the root, a sub-repo and a deep dir
OUT=$(cd "$UMB" && hvj repo umbrella) || fail "repo umbrella from the umbrella root: $OUT"
[ "$(echo "$OUT" | jget data.umbrella)" = "true" ] || fail "repo umbrella from the umbrella root: $OUT"
OUT=$(cd "$UMB/web" && hvj repo umbrella) || fail "repo umbrella from a sub-repo: $OUT"
[ "$(echo "$OUT" | jget data.umbrella)" = "true" ] || fail "repo umbrella from a sub-repo: $OUT"
mkdir -p "$UMB/web/src/components/deep"
OUT=$(cd "$UMB/web/src/components/deep" && hvj repo umbrella) || fail "repo umbrella from a deep dir: $OUT"
[ "$(echo "$OUT" | jget data.umbrella)" = "true" ] || fail "repo umbrella from a deep dir: $OUT"
pass "T1: repo umbrella holds from root, sub-repo and deep cwd (3 cwd cases)"

# white-box-begin: go-unit A3 #47
[ "$(cd "$UMB" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from umbrella root"
[ "$(cd "$UMB/web" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from sub-repo"
[ "$(cd "$UMB/web/src/components/deep" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from deep nested"
pass "T1: hv-resolve-umbrella walks up correctly (3 cwd cases)"
# white-box-end

# T1: no .hv/ above cwd means no umbrella (exit 1, never 3)
NOHV=$(mktemp -d)
rc=0; OUT=$(cd "$NOHV" && hvj repo umbrella 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "repo umbrella should exit 1 with no .hv/ above cwd, got $rc"
[ "$(echo "$OUT" | jget data.umbrella)" = "false" ] || fail "repo umbrella should say false with no .hv/: $OUT"
rm -rf "$NOHV"
pass "T1: repo umbrella exits 1 when no .hv/ above cwd"

# white-box-begin: go-unit A3 #47
if (cd /tmp && "$BIN/hv-resolve-umbrella" >/dev/null 2>&1); then
  fail "hv-resolve-umbrella should exit 1 in /tmp"
fi
pass "T1: hv-resolve-umbrella exits 1 when no .hv/ above cwd"
# white-box-end

# T1: symlink — the path is resolved physically
ln -sfn "$UMB/web" "$TMP/symlink-web"
OUT=$(cd "$TMP/symlink-web/src/components/deep" && hvj repo umbrella) || fail "repo umbrella via symlink: $OUT"
[ "$(echo "$OUT" | jget data.umbrella)" = "true" ] || fail "repo umbrella via symlink: $OUT"
rm -f "$TMP/symlink-web"
pass "T1: repo umbrella handles symlinked sub-repo paths"

# white-box-begin: go-unit A3 #47
ln -sfn "$UMB/web" "$TMP/symlink-web"
[ "$(cd "$TMP/symlink-web/src/components/deep" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up via symlink"
rm -f "$TMP/symlink-web"
pass "T1: hv-resolve-umbrella handles symlinked sub-repo paths"
# white-box-end

# T1: masking — a stray .hv/ inside a registered sub-repo hides the umbrella from repo which
mkdir -p "$UMB/web/.hv"
rc=0; (cd "$UMB/web/src" && "$HV_BIN" repo which >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "repo which should exit 3 when a stray .hv/ masks the umbrella, got $rc"
rmdir "$UMB/web/.hv"
pass "T1: repo which exits 3 on a stray .hv/ inside a registered sub-repo"

# white-box-begin: go-unit A3 #47
mkdir -p "$UMB/web/.hv"
if grep -q "masking" <<<"$( (cd "$UMB/web/src" 2>/dev/null && "$BIN/hv-resolve-umbrella" 2>&1 1>/dev/null))"; then
  pass "T1: hv-resolve-umbrella detects masking with stderr message"
else
  # stderr may not flow through subshell — check exit code instead
  EC=0
  (cd "$UMB/web" && "$BIN/hv-resolve-umbrella" >/dev/null 2>/dev/null) || EC=$?
  [ "$EC" = "2" ] || fail "masking should exit 2, got $EC"
  pass "T1: hv-resolve-umbrella detects masking (exit 2)"
fi
# white-box-end
rmdir "$UMB/web/.hv"

# T2: repo which from a sub-repo
OUT=$(cd "$UMB/web" && hvj repo which) || fail "repo which from web root: $OUT"
[ "$(echo "$OUT" | jget data.name)" = "web" ] || fail "repo which from web root: $OUT"
[ "$(echo "$OUT" | jget data.path)" = "$UMB/web" ] || fail "repo which path from web root: $OUT"
OUT=$(cd "$UMB/api" && hvj repo which) || fail "repo which from api root: $OUT"
[ "$(echo "$OUT" | jget data.name)" = "api" ] || fail "repo which from api root: $OUT"
pass "T2: repo which identifies registered sub-repo"

# T2: deep dir
OUT=$(cd "$UMB/web/src/components/deep" && hvj repo which) || fail "repo which from deep dir: $OUT"
[ "$(echo "$OUT" | jget data.name)" = "web" ] || fail "repo which from deep dir: $OUT"
pass "T2: repo which works from sub-repo deep dir"

# T2: unregistered sub-repo (shared was not registered)
rc=0; (cd "$UMB/shared" && "$HV_BIN" repo which >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "repo which should exit 3 for shared (not registered), got $rc"
pass "T2: repo which exits 3 for unregistered sub-repo"

# T2: cwd outside any sub-repo
rc=0; (cd "$UMB" && "$HV_BIN" repo which >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "repo which should exit 3 from umbrella root, got $rc"
pass "T2: repo which exits 3 outside any sub-repo's git"

# T1+T2: composition from Layout B worktree
(cd "$UMB/web" && git worktree add "$UMB/.claude/worktrees/web/feat-x" -b hv/feat-x >/dev/null 2>&1)
WT="$UMB/.claude/worktrees/web/feat-x"
OUT=$(cd "$WT" && hvj repo umbrella) || fail "repo umbrella from Layout B worktree: $OUT"
[ "$(echo "$OUT" | jget data.umbrella)" = "true" ] || fail "repo umbrella from Layout B worktree: $OUT"
OUT=$(cd "$WT" && hvj repo which) || fail "repo which from Layout B worktree: $OUT"
[ "$(echo "$OUT" | jget data.name)" = "web" ] || fail "repo which from Layout B worktree: $OUT"
[ "$(echo "$OUT" | jget data.path)" = "$UMB/web" ] || fail "repo which should map the worktree to its main repo: $OUT"
pass "T1+T2: composition from Layout B worktree path"
# white-box-begin: go-unit A3 #47
[ "$(cd "$WT" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from Layout B worktree"
(cd "$UMB/web" && git worktree remove "$WT" >/dev/null 2>&1; git branch -D hv/feat-x >/dev/null 2>&1) || true
# white-box-end

# M03-T1: repo resolve resolves names
OUT=$(cd "$UMB" && hvj repo resolve web api) || fail "repo resolve failed: $OUT"
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)['data']['repos']
assert isinstance(d, list) and len(d) == 2, d
assert [r['name'] for r in d] == ['web', 'api'], d
for r in d:
    assert r['path'].startswith('/'), r
" || fail "repo resolve output schema wrong: $OUT"
pass "M03-T1: repo resolve returns {name, path} per name, in argument order"

# M03-T1: single name returns 1 element
OUT=$(cd "$UMB" && hvj repo resolve web) || fail "repo resolve web failed: $OUT"
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)['data']['repos']
assert len(d) == 1 and d[0]['name'] == 'web', d
" || fail "repo resolve single-name output wrong: $OUT"
pass "M03-T1: repo resolve accepts single name"

# M03-T1: unregistered name exits 3 and names the missing sub-repo
rc=0; OUT=$(cd "$UMB" && hvj repo resolve web nonexistent 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "repo resolve should exit 3 on unregistered name, got $rc"
[ "$(echo "$OUT" | jget error.exit)" = "3" ] || fail "repo resolve error envelope wrong: $OUT"
grep -q "nonexistent" <<<"$(jget error.message <<<"$OUT")" || fail "repo resolve error must name the missing sub-repo: $OUT"
pass "M03-T1: repo resolve exits 3 and names missing sub-repo"

# M03-T1: no names returns an empty list, exit 0
OUT=$(cd "$UMB" && hvj repo resolve) || fail "repo resolve with no names failed: $OUT"
[ "$(echo "$OUT" | jget data.repos)" = "[]" ] || fail "repo resolve with no names must return []: $OUT"
pass "M03-T1: repo resolve handles no names"

# M03-T2: git branch succeeds when the branch is absent in all repos
(cd "$UMB" && hvj git branch hv/m3-test --repos web,api >/dev/null) || fail "git branch failed"
git -C "$UMB/web" show-ref --verify --quiet refs/heads/hv/m3-test \
  || fail "git branch did not create branch in web"
git -C "$UMB/api" show-ref --verify --quiet refs/heads/hv/m3-test \
  || fail "git branch did not create branch in api"
pass "M03-T2: git branch creates branch in every named repo"

# Cleanup the branches before the collision test below
git -C "$UMB/web" branch -D hv/m3-test >/dev/null
git -C "$UMB/api" branch -D hv/m3-test >/dev/null

# M03-T2: pre-existing branch in ANY named repo aborts before creating any (exit 4)
git -C "$UMB/web" branch hv/m3-collide >/dev/null
rc=0; OUT=$(cd "$UMB" && hvj git branch hv/m3-collide --repos web,api 2>/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "git branch should exit 4 when branch exists in any repo, got $rc"
grep -q "web" <<<"$(jget error.message <<<"$OUT")" || fail "git branch error must name the colliding repo: $OUT"
[ "$(echo "$OUT" | jget data.changed)" = "false" ] || fail "git branch refusal should report changed false: $OUT"
if git -C "$UMB/api" show-ref --verify --quiet refs/heads/hv/m3-collide; then
  fail "git branch created branch in api despite collision in web"
fi
pass "M03-T2: git branch aborts atomically on collision"

# Cleanup
git -C "$UMB/web" branch -D hv/m3-collide >/dev/null

# M03-T2: unregistered repo name exits 3
rc=0; (cd "$UMB" && "$HV_BIN" git branch hv/m3-bad --repos web,nonexistent >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "git branch should exit 3 on unregistered repo, got $rc"
pass "M03-T2: git branch rejects unregistered repos"

# M03-T3: status add --repos creates one status entry per (branch, repo)
rm -f "$UMB/.hv/status.json"
(cd "$UMB" && hvj status add hv/m3-foo --items M03-S01 --repos web,api >/dev/null) || fail "status add --repos failed"
python3 -c "
import json
d = json.load(open('$UMB/.hv/status.json'))
active = d.get('active', [])
keys = sorted((e['branch'], e['repo']) for e in active if e['branch'] == 'hv/m3-foo')
assert keys == [('hv/m3-foo', 'api'), ('hv/m3-foo', 'web')], keys
for e in active:
    if e['branch'] == 'hv/m3-foo':
        assert e['items'] == ['M03-S01'], e
        assert e.get('worktree') is None, e
" || fail "status add --repos did not create one entry per (branch, repo)"
pass "M03-T3: status add --repos creates one status entry per repo"

# M03-T3: --worktrees pairs paths with repos by index
rm -f "$UMB/.hv/status.json"
(cd "$UMB" && hvj status add hv/m3-bar --items M03-S01 \
  --repos web,api --worktrees /tmp/wt-web,/tmp/wt-api >/dev/null) || fail "status add --worktrees failed"
python3 -c "
import json
d = json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['repo'], e['worktree']) for e in d['active'] if e['branch'] == 'hv/m3-bar')
assert pairs == [('api', '/tmp/wt-api'), ('web', '/tmp/wt-web')], pairs
" || fail "status add worktree pairing wrong"
pass "M03-T3: status add pairs --worktrees with --repos by index"

# M03-T3: mismatched --worktrees length is a usage error
rm -f "$UMB/.hv/status.json"
rc=0; (cd "$UMB" && "$HV_BIN" status add hv/m3-baz --items M03-S01 \
     --repos web,api --worktrees /tmp/only-one >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "status add should exit 2 on mismatched --worktrees length, got $rc"
pass "M03-T3: status add rejects mismatched --worktrees length"

# M03-T3: unregistered repo name exits 3
rm -f "$UMB/.hv/status.json"
rc=0; (cd "$UMB" && "$HV_BIN" status add hv/m3-bad --items M03-S01 --repos web,nonexistent >/dev/null 2>&1) || rc=$?
[ "$rc" = 3 ] || fail "status add should exit 3 on unregistered repos, got $rc"
pass "M03-T3: status add rejects unregistered repos"

# M03-T5: hv-capture/SKILL.md Step 4.6 declares multi-select for Repos
# white-box-begin: A9 #53 doclint
grep -q "multiSelect:.*true" "$REPO/hv-capture/SKILL.md" \
  || fail "hv-capture Step 4.6 must declare multiSelect: true for the Repos question"
grep -q "comma-separated list of registered sub-repos" "$REPO/hv-capture/SKILL.md" \
  || fail "hv-capture field-order line must say 'comma-separated list of registered sub-repos'"
if grep -q "single name in V1" "$REPO/hv-capture/SKILL.md"; then
  fail "hv-capture must no longer carry the 'single name in V1' qualifier"
fi
pass "M03-T5: hv-capture/SKILL.md Step 4.6 supports multi-repo Repos tagging"
# white-box-end

# M03-T6: plan add accepts comma-separated --repos and validates each name
PLANS_TMP=$(mktemp -d)
mkdir -p "$PLANS_TMP/.hv"
cp -r "$UMB/.hv/repos.json" "$PLANS_TMP/.hv/repos.json"

# Single name still works (backwards compat)
(cd "$PLANS_TMP" && hvj plan add M99-B01 --title "single repo plan" --repos web >/dev/null) || fail "plan add --repos web failed"
grep -q "^repo: web$" "$PLANS_TMP/.hv/plans/M99-B01.md" \
  || fail "plan add single --repos did not write 'repo: web' frontmatter"
pass "M03-T6: plan add accepts a single --repos name"

# Multi-repo list writes joined frontmatter
(cd "$PLANS_TMP" && hvj plan add M99-B02 --title "multi repo plan" --repos web,api >/dev/null) || fail "plan add --repos web,api failed"
grep -q "^repo: web, api$" "$PLANS_TMP/.hv/plans/M99-B02.md" \
  || fail "plan add multi --repos did not write 'repo: web, api' frontmatter"
pass "M03-T6: plan add accepts comma-separated --repos and writes joined value"

# Unregistered name in CSV is rejected (exit 3); no plan file written
rc=0; OUT=$(cd "$PLANS_TMP" && hvj plan add M99-B03 --title "bad plan" --repos web,nonexistent 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "plan add should exit 3 on unregistered name in --repos, got $rc"
[ -f "$PLANS_TMP/.hv/plans/M99-B03.md" ] && fail "plan add wrote plan file despite invalid --repos"
grep -q "nonexistent" <<<"$(jget error.message <<<"$OUT")" || fail "plan add error must name the unregistered sub-repo: $OUT"
pass "M03-T6: plan add rejects unregistered name in --repos CSV"

rm -rf "$PLANS_TMP"

# M03-T6: hv-plan/SKILL.md prose mentions multi-repo flow
# white-box-begin: A9 #53 doclint
grep -q 'multi-repo items pass the full comma-list' "$REPO/hv-plan/SKILL.md" \
  || fail "hv-plan/SKILL.md must explain multi-repo --repo flow"
pass "M03-T6: hv-plan/SKILL.md documents multi-repo --repo"
# white-box-end

# M03-T6: hv-work/SKILL.md Preview Mode peek shape supports multiple sub-repo lines
# white-box-begin: A9 #53 doclint
grep -q "one line per repo for multi-repo items" "$REPO/hv-work/SKILL.md" \
  || fail "hv-work/SKILL.md Preview Mode peek must show one Repo line per sub-repo for multi-repo items"
pass "M03-T6: hv-work/SKILL.md Preview Mode peek renders one line per repo"
# white-box-end

# M03-T4: hv-work/SKILL.md documents multi-repo dispatch via the helpers
# white-box-begin: A9 #53 keep
grep -q "hv-multi-branch-create" "$REPO/hv-work/SKILL.md" \
  || fail "hv-work/SKILL.md must reference bin/hv-multi-branch-create for multi-repo branch creation"
grep -q "hv-status-add-multi" "$REPO/hv-work/SKILL.md" \
  || fail "hv-work/SKILL.md must reference bin/hv-status-add-multi for multi-repo status entries"
grep -q "hv-resolve-repos" "$REPO/hv-work/SKILL.md" \
  || fail "hv-work/SKILL.md must reference bin/hv-resolve-repos for multi-repo validation"
if grep -q "M03 (deferred)" "$REPO/hv-work/SKILL.md"; then
  fail "hv-work/SKILL.md must no longer say 'M03 (deferred)'"
fi
if grep -q "wait for M03 multi-repo support" "$REPO/hv-work/SKILL.md"; then
  fail "hv-work/SKILL.md must no longer say 'wait for M03 multi-repo support'"
fi
pass "M03-T4: hv-work/SKILL.md documents multi-repo dispatch flow"
# white-box-end

# Cleanup status.json so it doesn't pollute later assertions
rm -f "$UMB/.hv/status.json"

# Single-repo backwards compat — existing fixtures must still pass.
# This block runs in the parent $TMP (the original single-repo test fixture);
# it has no registered sub-repos, so it is not an umbrella and the project
# still resolves from its own .hv/.
rc=0; OUT=$(cd "$TMP" && hvj repo umbrella 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "single-repo cwd must not be an umbrella, got exit $rc: $OUT"
(cd "$TMP" && hvj config show work.dispatch >/dev/null) || fail "single-repo cwd still resolves to its own .hv/"
pass "single-repo backward compat: the project resolves with no umbrella in scope"

# white-box-begin: go-unit A3 #47
[ "$(cd "$TMP" && "$BIN/hv-resolve-umbrella")" = "$TMP" ] || fail "single-repo cwd still resolves to its own .hv/"
pass "single-repo backward compat: hv-resolve-umbrella still works"
# white-box-end
