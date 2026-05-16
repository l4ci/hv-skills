echo "umbrella mode (T1-T4)"

# Build a synthetic umbrella with 3 independent git repos (NO submodules)
UMB="$TMP/umbrella"
mkdir -p "$UMB"/{web,api,shared} "$UMB/.hv"
for r in web api shared; do
  (cd "$UMB/$r" && git init -q -b main && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init)
done

# T4: bootstrap seeds repos.json
SEEDED=$(mktemp -d)
(cd "$SEEDED" && bash "$BIN/hv-bootstrap" >/dev/null)
[ -f "$SEEDED/.hv/repos.json" ] || fail "hv-bootstrap did not seed .hv/repos.json"
python3 -c "import json; d=json.load(open('$SEEDED/.hv/repos.json')); assert d == {'repos':[]}, d" || fail "repos.json schema wrong"
pass "T4: hv-bootstrap seeds .hv/repos.json with {\"repos\":[]}"
rm -rf "$SEEDED"

# T3: hv-umbrella-init scans children and writes registry
echo "web,api" | (cd "$UMB" && "$BIN/hv-umbrella-init" >/dev/null)
python3 -c "import json; d=json.load(open('$UMB/.hv/repos.json')); names=sorted(r['name'] for r in d['repos']); assert names==['api','web'], names" || fail "registry schema wrong"
pass "T3: hv-umbrella-init writes sorted registry"

# T3: idempotent re-run
SHA_BEFORE=$(sha256sum "$UMB/.hv/repos.json" | cut -d' ' -f1)
echo "web,api" | (cd "$UMB" && "$BIN/hv-umbrella-init" >/dev/null)
SHA_AFTER=$(sha256sum "$UMB/.hv/repos.json" | cut -d' ' -f1)
[ "$SHA_BEFORE" = "$SHA_AFTER" ] || fail "hv-umbrella-init not idempotent"
pass "T3: hv-umbrella-init idempotent on repeat run"

# T3: empty children dir exits 1
EMPTY="$TMP/empty-umbrella" && mkdir -p "$EMPTY/.hv"
if (cd "$EMPTY" && "$BIN/hv-umbrella-init" <<<"" >/dev/null 2>&1); then
  fail "hv-umbrella-init should exit 1 on empty children"
fi
pass "T3: hv-umbrella-init exits 1 on empty children dir"

# T1: walk-up from various positions
[ "$(cd "$UMB" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from umbrella root"
[ "$(cd "$UMB/web" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from sub-repo"
mkdir -p "$UMB/web/src/components/deep"
[ "$(cd "$UMB/web/src/components/deep" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from deep nested"
pass "T1: hv-resolve-umbrella walks up correctly (3 cwd cases)"

# T1: not found
if (cd /tmp && "$BIN/hv-resolve-umbrella" >/dev/null 2>&1); then
  fail "hv-resolve-umbrella should exit 1 in /tmp"
fi
pass "T1: hv-resolve-umbrella exits 1 when no .hv/ above cwd"

# T1: symlink — pwd -P matters
ln -sfn "$UMB/web" "$TMP/symlink-web"
[ "$(cd "$TMP/symlink-web/src/components/deep" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up via symlink"
rm -f "$TMP/symlink-web"
pass "T1: hv-resolve-umbrella handles symlinked sub-repo paths"

# T1: masking — stray .hv/ inside a registered sub-repo
mkdir -p "$UMB/web/.hv"
if (cd "$UMB/web/src" 2>/dev/null && "$BIN/hv-resolve-umbrella" 2>&1 1>/dev/null) | grep -q "masking"; then
  pass "T1: hv-resolve-umbrella detects masking with stderr message"
else
  # stderr may not flow through subshell — check exit code instead
  EC=0
  (cd "$UMB/web" && "$BIN/hv-resolve-umbrella" >/dev/null 2>/dev/null) || EC=$?
  [ "$EC" = "2" ] || fail "masking should exit 2, got $EC"
  pass "T1: hv-resolve-umbrella detects masking (exit 2)"
fi
rmdir "$UMB/web/.hv"

# T2: hv-resolve-repo from sub-repo
[ "$(cd "$UMB/web" && "$BIN/hv-resolve-repo")" = "web" ] || fail "resolve-repo from web root"
[ "$(cd "$UMB/api" && "$BIN/hv-resolve-repo")" = "api" ] || fail "resolve-repo from api root"
pass "T2: hv-resolve-repo identifies registered sub-repo"

# T2: deep dir
[ "$(cd "$UMB/web/src/components/deep" && "$BIN/hv-resolve-repo")" = "web" ] || fail "resolve-repo from deep dir"
pass "T2: hv-resolve-repo works from sub-repo deep dir"

# T2: unregistered sub-repo (shared was not registered)
if (cd "$UMB/shared" && "$BIN/hv-resolve-repo" >/dev/null 2>&1); then
  fail "resolve-repo should exit 1 for shared (not registered)"
fi
pass "T2: hv-resolve-repo exits 1 for unregistered sub-repo"

# T2: cwd outside any sub-repo
if (cd "$UMB" && "$BIN/hv-resolve-repo" >/dev/null 2>&1); then
  fail "resolve-repo should exit 1 from umbrella root"
fi
pass "T2: hv-resolve-repo exits 1 outside any sub-repo's git"

# T1+T2: composition from Layout B worktree
(cd "$UMB/web" && git worktree add "$UMB/.claude/worktrees/web/feat-x" -b hv/feat-x >/dev/null 2>&1)
WT="$UMB/.claude/worktrees/web/feat-x"
[ "$(cd "$WT" && "$BIN/hv-resolve-umbrella")" = "$UMB" ] || fail "walk-up from Layout B worktree"
[ "$(cd "$WT" && "$BIN/hv-resolve-repo")" = "web" ] || fail "resolve-repo from Layout B worktree"
pass "T1+T2: composition from Layout B worktree path"
(cd "$UMB/web" && git worktree remove "$WT" >/dev/null 2>&1; git branch -D hv/feat-x >/dev/null 2>&1) || true

# M03-T1: hv-resolve-repos parses CSV and resolves names
(cd "$UMB" && "$BIN/hv-resolve-repos" "web, api" > "$TMP/resolved.json")
python3 -c "
import json
d = json.load(open('$TMP/resolved.json'))
assert isinstance(d, list) and len(d) == 2, d
names = sorted(r['name'] for r in d)
assert names == ['api', 'web'], names
for r in d:
    assert r['path'].startswith('/'), r
" || fail "hv-resolve-repos output schema wrong"
pass "M03-T1: hv-resolve-repos returns JSON array of {name, path}"

# M03-T1: single-name CSV returns 1-element array
(cd "$UMB" && "$BIN/hv-resolve-repos" "web" > "$TMP/resolved-single.json")
python3 -c "
import json
d = json.load(open('$TMP/resolved-single.json'))
assert len(d) == 1 and d[0]['name'] == 'web', d
" || fail "hv-resolve-repos single-name output wrong"
pass "M03-T1: hv-resolve-repos accepts single name"

# M03-T1: unregistered name exits 1 with clear stderr
if (cd "$UMB" && "$BIN/hv-resolve-repos" "web, nonexistent" 2>"$TMP/err" >/dev/null); then
  fail "hv-resolve-repos should exit 1 on unregistered name"
fi
grep -q "nonexistent" "$TMP/err" || fail "hv-resolve-repos error must name the missing sub-repo"
pass "M03-T1: hv-resolve-repos exits 1 and names missing sub-repo"

# M03-T1: empty CSV returns empty array, exit 0
(cd "$UMB" && "$BIN/hv-resolve-repos" "" > "$TMP/resolved-empty.json")
python3 -c "import json; d=json.load(open('$TMP/resolved-empty.json')); assert d == [], d" \
  || fail "hv-resolve-repos empty CSV must return []"
pass "M03-T1: hv-resolve-repos handles empty CSV"

# M03-T2: hv-multi-branch-create succeeds when branch is absent in all repos
(cd "$UMB" && "$BIN/hv-multi-branch-create" --branch hv/m3-test --repos "web, api")
git -C "$UMB/web" show-ref --verify --quiet refs/heads/hv/m3-test \
  || fail "hv-multi-branch-create did not create branch in web"
git -C "$UMB/api" show-ref --verify --quiet refs/heads/hv/m3-test \
  || fail "hv-multi-branch-create did not create branch in api"
pass "M03-T2: hv-multi-branch-create creates branch in every named repo"

# Cleanup the branches before the collision test below
git -C "$UMB/web" branch -D hv/m3-test >/dev/null
git -C "$UMB/api" branch -D hv/m3-test >/dev/null

# M03-T2: pre-existing branch in ANY named repo aborts before creating any
git -C "$UMB/web" branch hv/m3-collide >/dev/null
if (cd "$UMB" && "$BIN/hv-multi-branch-create" --branch hv/m3-collide --repos "web, api" 2>"$TMP/err" >/dev/null); then
  fail "hv-multi-branch-create should exit 1 when branch exists in any repo"
fi
grep -q "web" "$TMP/err" || fail "hv-multi-branch-create error must name the colliding repo"
if git -C "$UMB/api" show-ref --verify --quiet refs/heads/hv/m3-collide; then
  fail "hv-multi-branch-create created branch in api despite collision in web"
fi
pass "M03-T2: hv-multi-branch-create aborts atomically on collision"

# Cleanup
git -C "$UMB/web" branch -D hv/m3-collide >/dev/null

# M03-T2: unregistered repo name exits non-zero (delegated to hv-resolve-repos)
if (cd "$UMB" && "$BIN/hv-multi-branch-create" --branch hv/m3-bad --repos "web, nonexistent" 2>/dev/null); then
  fail "hv-multi-branch-create should fail on unregistered repo"
fi
pass "M03-T2: hv-multi-branch-create rejects unregistered repos"

# M03-T3: hv-status-add-multi creates one status entry per (branch, repo)
rm -f "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add-multi" --branch hv/m3-foo --items M03-S01 --repos "web, api")
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
" || fail "hv-status-add-multi did not create one entry per (branch, repo)"
pass "M03-T3: hv-status-add-multi creates one status entry per repo"

# M03-T3: --worktrees pairs paths with repos by index
rm -f "$UMB/.hv/status.json"
(cd "$UMB" && "$BIN/hv-status-add-multi" --branch hv/m3-bar --items M03-S01 \
  --repos "web, api" --worktrees "/tmp/wt-web, /tmp/wt-api")
python3 -c "
import json
d = json.load(open('$UMB/.hv/status.json'))
pairs = sorted((e['repo'], e['worktree']) for e in d['active'] if e['branch'] == 'hv/m3-bar')
assert pairs == [('api', '/tmp/wt-api'), ('web', '/tmp/wt-web')], pairs
" || fail "hv-status-add-multi worktree pairing wrong"
pass "M03-T3: hv-status-add-multi pairs --worktrees with --repos by index"

# M03-T3: mismatched --worktrees length is a usage error
rm -f "$UMB/.hv/status.json"
if (cd "$UMB" && "$BIN/hv-status-add-multi" --branch hv/m3-baz --items M03-S01 \
     --repos "web, api" --worktrees "/tmp/only-one" 2>/dev/null); then
  fail "hv-status-add-multi should reject mismatched --worktrees length"
fi
pass "M03-T3: hv-status-add-multi rejects mismatched --worktrees length"

# M03-T3: unregistered repo name exits non-zero
rm -f "$UMB/.hv/status.json"
if (cd "$UMB" && "$BIN/hv-status-add-multi" --branch hv/m3-bad --items M03-S01 --repos "web, nonexistent" 2>/dev/null); then
  fail "hv-status-add-multi should reject unregistered repos"
fi
pass "M03-T3: hv-status-add-multi rejects unregistered repos"

# M03-T5: hv-capture/SKILL.md Step 4.6 declares multi-select for Repos
grep -q "multiSelect:.*true" "$REPO/hv-capture/SKILL.md" \
  || fail "hv-capture Step 4.6 must declare multiSelect: true for the Repos question"
grep -q "comma-separated list of registered sub-repos" "$REPO/hv-capture/SKILL.md" \
  || fail "hv-capture field-order line must say 'comma-separated list of registered sub-repos'"
if grep -q "single name in V1" "$REPO/hv-capture/SKILL.md"; then
  fail "hv-capture must no longer carry the 'single name in V1' qualifier"
fi
pass "M03-T5: hv-capture/SKILL.md Step 4.6 supports multi-repo Repos tagging"

# M03-T6: hv-plan-add accepts comma-separated --repo and validates each name
PLANS_TMP=$(mktemp -d)
mkdir -p "$PLANS_TMP/.hv"
cp -r "$UMB/.hv/repos.json" "$PLANS_TMP/.hv/repos.json"

# Single name still works (backwards compat)
(cd "$PLANS_TMP" && "$BIN/hv-plan-add" --repo web M99 B01 "single repo plan" >/dev/null)
grep -q "^repo: web$" "$PLANS_TMP/.hv/plans/M99-B01.md" \
  || fail "hv-plan-add single --repo did not write 'repo: web' frontmatter"
pass "M03-T6: hv-plan-add accepts a single --repo name"

# Multi-repo list writes joined frontmatter
(cd "$PLANS_TMP" && "$BIN/hv-plan-add" --repo "web, api" M99 B02 "multi repo plan" >/dev/null)
grep -q "^repo: web, api$" "$PLANS_TMP/.hv/plans/M99-B02.md" \
  || fail "hv-plan-add multi --repo did not write 'repo: web, api' frontmatter"
pass "M03-T6: hv-plan-add accepts comma-separated --repo and writes joined value"

# Unregistered name in CSV is rejected; no plan file written
if (cd "$PLANS_TMP" && "$BIN/hv-plan-add" --repo "web, nonexistent" M99 B03 "bad plan" 2>"$TMP/err" >/dev/null); then
  fail "hv-plan-add should reject unregistered name in --repo CSV"
fi
[ -f "$PLANS_TMP/.hv/plans/M99-B03.md" ] && fail "hv-plan-add wrote plan file despite invalid --repo"
grep -q "nonexistent" "$TMP/err" || fail "hv-plan-add error must name the unregistered sub-repo"
pass "M03-T6: hv-plan-add rejects unregistered name in --repo CSV"

rm -rf "$PLANS_TMP"

# M03-T6: hv-plan/SKILL.md prose mentions multi-repo flow
grep -q 'multi-repo items pass the full comma-list' "$REPO/hv-plan/SKILL.md" \
  || fail "hv-plan/SKILL.md must explain multi-repo --repo flow"
pass "M03-T6: hv-plan/SKILL.md documents multi-repo --repo"

# M03-T6: hv-work/SKILL.md Preview Mode peek shape supports multiple sub-repo lines
grep -q "one line per repo for multi-repo items" "$REPO/hv-work/SKILL.md" \
  || fail "hv-work/SKILL.md Preview Mode peek must show one Repo line per sub-repo for multi-repo items"
pass "M03-T6: hv-work/SKILL.md Preview Mode peek renders one line per repo"

# M03-T4: hv-work/SKILL.md documents multi-repo dispatch via the helpers
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

# Cleanup status.json so it doesn't pollute later assertions
rm -f "$UMB/.hv/status.json"

# Single-repo backwards compat — existing fixtures must still pass.
# This block runs in the parent $TMP (the original single-repo test fixture);
# verify hv-resolve-umbrella still works there with no umbrella in scope.
[ "$(cd "$TMP" && "$BIN/hv-resolve-umbrella")" = "$TMP" ] || fail "single-repo cwd still resolves to its own .hv/"
pass "single-repo backward compat: hv-resolve-umbrella still works"

