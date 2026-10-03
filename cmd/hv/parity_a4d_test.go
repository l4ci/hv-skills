package main

// Black-box parity for `hv issues list|label|imported|close|provider` and
// `hv migrate issues` (#48). Each scenario builds a git project whose origin
// resolves to github or gitlab, seeds the stateful fake forge
// (test/fakes/fake_tracker.py) identically for both sides, runs the shim
// (test/shim, which adapts the old helpers) on side A and the Go binary on
// side B, and compares the exit code, the --json envelope, the final .hv/ tree
// and the final fake-forge database. A scenario may run several commands in
// a row on the same project (resume after a failure).
//
// Safety: the shared TestMain refuses to run unless gh resolves to test/fakes,
// TestDFakesFirst checks glab too, and every run has its own FAKE_TRACKER_DB
// under t.TempDir.
//
// Documented divergences (a scenario with `div` names one):
//  1. data.changed: the shim says true for every label and close that exits 0
//     (old cannot tell a no-op); Go reports the real value. Scenarios assert
//     Go's value (drun.changed) and drop the key from the comparison.
//  2. A forge CLI that exits with a code other than 1, 3 or 4: the old helpers
//     pass the CLI's rc through and the shim maps unknown rcs to 70; Go says 5
//     (the CLI failed). The fake gh exits 2 for the flags it does not
//     implement (--assignee on `issue list`), so github `issues list --mine`
//     fails there; internal/issues covers it.
//  3. issues.autoCreateLabel false: old reads it with jq's `// true`, so false
//     still reads as true and the label is created anyway; the contract (and
//     Go) says false means no creation.
//  4. .hv/issue-map.json that is a JSON array: old dies with usage (shim 2),
//     Go treats a corrupt state file as exit 70. (Any other non-tracker
//     failure mid-run, which crashes the old helper with a traceback, is the
//     same split: shim 2, Go 70, or 2 for a validation error.)
//  5. (retired) The fake gh now answers `issue view --json state -q .state`,
//     so the github idempotency check of close sees CLOSED like gitlab does.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

type drun struct {
	argv    []string
	env     []string
	want    int
	div     string // the reference cannot agree on the exit
	refWant int
	changed *bool      // Go's data.changed; dropped from the comparison (divergence 1)
	skipDB  bool       // the forge DBs differ by design; Go's must equal the seed (divergence 3)
	msgHas  string     // the Go error message contains this
	norm    func(envl) // applied to both envelopes
	check   func(t *testing.T, g envl, db map[string]any)
}

type dsc struct {
	name   string
	remote string // "" github, "gitlab", "none"
	fx     fx
	db     func() map[string]any
	runs   []drun
}

const dCfg = `{"issues": {"retryWaitSeconds": 0, "bulkPaceMs": 0}}`

func dseed() map[string]any {
	i3 := iss(3, "Gamma closed", "gamma", []string{"bug"}, "closed")
	i4 := iss(4, "Delta mine", "delta", []string{"bug", "existing"}, "open")
	i4["assignees"] = []any{"fake-user"}
	return map[string]any{
		"next_issue": 7, "next_milestone": 2, "next_comment": 3, "next_mr": 1,
		"labels": []any{"bug", "feature", "existing"}, "prs": []any{},
		"milestones": []any{map[string]any{"number": 1, "title": "M09 — Shipped", "description": "", "state": "closed"}},
		"issues": []any{
			iss(1, "Alpha", "alpha body", []string{"bug"}, "open"),
			iss(2, "Beta", "beta body", []string{"feature", "existing"}, "open"),
			i3, i4,
			iss(5, "Epsilon", "eps", []string{}, "open", cm(1, "a note")),
			iss(6, "Zeta", "zeta", []string{"existing"}, "open"),
		},
	}
}

func dempty() map[string]any { return nil }

// dseed78 is dseed with the issues #7 and #8 a pre-populated map points at.
func dseed78() map[string]any {
	db := dseed()
	db["issues"] = append(db["issues"].([]any), iss(7, "First bug", "x", []string{"type:bug"}, "open"), iss(8, "Feature", "y", []string{"type:feature"}, "open"))
	db["next_issue"] = 9
	return db
}

// oracleStep is what the old side did for one run of a scenario.
type oracleStep struct {
	Code           int
	Stdout, Stderr string
	Tree           map[string]string // the .hv/ tree after the run
	DB             map[string]any    // the forge database after the run
}

// oracle runs the scenario's old side (the shim) in a copy of base, or replays
// it from the cache when none of its inputs changed (parity_cache_test.go).
func (s dsc) oracle(t *testing.T, base string, in info, remote string, seed map[string]any) []oracleStep {
	t.Helper()
	type runIn struct {
		Argv, Env []string
	}
	var runs []runIn
	for _, r := range s.runs {
		runs = append(runs, runIn{subst(r.argv, in), r.env})
	}
	key := oracleKey(t, map[string]any{"kind": "dsc", "project": projectDigest(base), "remote": remote, "seed": seed, "runs": runs})
	var steps []oracleStep
	if oracleLoad(key, &steps) && len(steps) == len(s.runs) {
		return steps
	}
	steps = nil
	refDir := copyTree(t, base)
	refDB := filepath.Join(t.TempDir(), "ref.json")
	if seed != nil {
		raw, _ := json.Marshal(seed)
		if err := os.WriteFile(refDB, raw, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for _, r := range runs {
		run := envRun(t, refDir, "", append([]string{"FAKE_TRACKER_DB=" + refDB}, r.Env...), "python3", append([]string{shimPath}, r.Argv...)...)
		steps = append(steps, oracleStep{run.code, run.stdout, run.stderr, snapshot(t, refDir), readDB(t, refDB)})
	}
	oracleStore(t, key, steps)
	return steps
}

func (s dsc) exec(t *testing.T) {
	t.Parallel()
	f := s.fx
	if f.config == "" {
		f.config = dCfg
	}
	base, in := f.build(t)
	remote := map[string]string{"": "https://github.com/example/repo.git", "gitlab": "https://gitlab.com/example/repo.git"}[s.remote]
	if remote != "" {
		git(t, base, "remote", "add", "origin", remote)
	}
	var seed map[string]any
	if s.db != nil {
		seed = s.db()
	}
	ref := s.oracle(t, base, in, remote, seed)
	goDir := copyTree(t, base)
	goDB := filepath.Join(t.TempDir(), "go.json")
	if seed != nil {
		raw, _ := json.Marshal(seed)
		if err := os.WriteFile(goDB, raw, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for n, r := range s.runs {
		argv := subst(r.argv, in)
		tag := fmt.Sprintf("run %d %v", n+1, argv)
		goRun := envRun(t, goDir, "", append([]string{"FAKE_TRACKER_DB=" + goDB}, r.env...), hvBin, argv...)
		refRun := run{code: ref[n].Code, stdout: ref[n].Stdout, stderr: ref[n].Stderr}
		if goRun.code != r.want {
			t.Errorf("%s: go exit = %d, want %d\nstdout: %s\nstderr: %s", tag, goRun.code, r.want, goRun.stdout, goRun.stderr)
		}
		refWant := r.want
		if r.div != "" {
			refWant = r.refWant
		}
		if refRun.code != refWant {
			t.Errorf("%s: reference exit = %d, want %d (%s)\nstdout: %s\nstderr: %s", tag, refRun.code, refWant, r.div, refRun.stdout, refRun.stderr)
		}
		goEnv := parseEnv(t, "go", goRun)
		refEnv := parseEnv(t, "shim", refRun)
		if r.msgHas != "" {
			if msg, _ := at(goEnv, "error.message").(string); !strings.Contains(msg, r.msgHas) {
				t.Errorf("%s: error message %q does not contain %q", tag, msg, r.msgHas)
			}
		}
		if d := diffTrees(ref[n].Tree, snapshot(t, goDir)); d != "" {
			t.Errorf("%s: .hv/ trees differ:\n%s", tag, d)
		}
		gDB, rDB := readDB(t, goDB), ref[n].DB
		if r.skipDB {
			if want := norm(s.db()); !reflect.DeepEqual(gDB, want) {
				t.Errorf("%s: go changed the forge although it refused (%s)", tag, r.div)
			}
		} else if !reflect.DeepEqual(gDB, rDB) {
			gj, _ := json.MarshalIndent(gDB, "", " ")
			rj, _ := json.MarshalIndent(rDB, "", " ")
			t.Errorf("%s: forge DBs differ\nref stderr: %s\n--- reference\n%s\n--- go\n%s", tag, refRun.stderr, rj, gj)
		}
		if r.div == "" || refRun.code == goRun.code {
			g, rf := stripText(goEnv), stripText(refEnv)
			if r.changed != nil {
				if got := at(goEnv, "data.changed"); goRun.code == 0 && got != *r.changed {
					t.Errorf("%s: go data.changed = %v, want %v", tag, got, *r.changed)
				}
				dropChanged(g)
				dropChanged(rf)
			}
			if r.norm != nil {
				r.norm(g)
				r.norm(rf)
			}
			if r.div == "" && !reflect.DeepEqual(map[string]any(rf), map[string]any(g)) {
				rj, _ := json.Marshal(rf)
				gj, _ := json.Marshal(g)
				t.Errorf("%s: envelopes differ\nshim: %s\ngo:   %s", tag, rj, gj)
			}
		}
		if r.check != nil {
			r.check(t, goEnv, gDB)
		}
	}
}

func TestDFakesFirst(t *testing.T) { TestIssueFakesFirst(t) }

// sortEntries orders data.entries so the old helper's directory order does not matter.
func sortEntries(e envl) {
	d, ok := e["data"].(map[string]any)
	if !ok {
		return
	}
	rows, ok := d["entries"].([]any)
	if !ok {
		return
	}
	sort.SliceStable(rows, func(i, j int) bool {
		a, _ := json.Marshal(rows[i])
		b, _ := json.Marshal(rows[j])
		return string(a) < string(b)
	})
}

func dr(want int, argv ...string) drun {
	return drun{argv: append([]string{"--json"}, argv...), want: want}
}

func (r drun) env1(kv ...string) drun { r.env = append(r.env, kv...); return r }
func (r drun) ch(b bool) drun         { r.changed = &b; return r }
func (r drun) with(div string, refWant int) drun {
	r.div, r.refWant = div, refWant
	return r
}
func (r drun) msg(s string) drun { r.msgHas = s; return r }

// one is a single-run scenario on the standard project and the standard forge.
func one(name string, r drun) dsc { return dsc{name: name, db: dseed, runs: []drun{r}} }

func (s dsc) on(remote string) dsc { s.remote = remote; return s }

// both adds the github and the gitlab form of a scenario.
func dboth(all *[]dsc, s dsc) {
	g := s
	g.name = s.name + "/github"
	l := s
	l.name = s.name + "/gitlab"
	l.remote = "gitlab"
	*all = append(*all, g, l)
}

func umbrella(f fx) fx {
	f.subs = map[string][]string{"web": {"feat: web start"}, "api": {"feat: api start"}}
	prev := f.after
	f.after = func(t *testing.T, dir string, in *info) {
		git(t, filepath.Join(dir, "web"), "remote", "add", "origin", "https://github.com/example/web.git")
		git(t, filepath.Join(dir, "api"), "remote", "add", "origin", "https://gitlab.com/example/api.git")
		in.x["web"] = git(t, filepath.Join(dir, "web"), "rev-parse", "--short", "HEAD")
		in.x["api"] = git(t, filepath.Join(dir, "api"), "rev-parse", "--short", "HEAD")
		if prev != nil {
			prev(t, dir, in)
		}
	}
	return f
}

func TestParityA4D(t *testing.T) {
	var all []dsc
	add := func(s ...dsc) { all = append(all, s...) }
	rate := []string{"FAKE_TRACKER_FAIL_MSG=secondary rate limit"}

	// ---- issues provider ----
	for _, c := range []struct{ name, remote string }{{"github", ""}, {"gitlab", "gitlab"}, {"none", "none"}} {
		add(one("provider/"+c.name, dr(0, "issues", "provider")).on(c.remote))
	}
	for name, url := range map[string]string{
		"ghe-host":    "https://github.corp.example/o/r.git",
		"ssh-short":   "git@gitlab.example.org:o/r.git",
		"ssh-url":     "ssh://git@github.com/o/r.git",
		"other":       "https://bitbucket.org/o/r.git",
		"upper-host":  "https://GitHub.com/o/r.git",
		"gitlab-self": "https://gitlab.internal/o/r.git",
	} {
		url := url
		f := fx{after: func(t *testing.T, dir string, in *info) { git(t, dir, "remote", "add", "origin", url) }}
		add(dsc{name: "provider/url-" + name, remote: "none", fx: f, db: dseed, runs: []drun{dr(0, "issues", "provider")}})
	}
	add(dsc{name: "provider/umbrella-web", remote: "none", fx: umbrella(fx{}), runs: []drun{dr(0, "issues", "provider", "--repo", "web")}},
		dsc{name: "provider/umbrella-api", remote: "none", fx: umbrella(fx{}), runs: []drun{dr(0, "issues", "provider", "--repo", "api")}},
		dsc{name: "provider/umbrella-root", remote: "none", fx: umbrella(fx{}), runs: []drun{dr(0, "issues", "provider")}},
		dsc{name: "provider/repo-unknown", remote: "none", fx: umbrella(fx{}), runs: []drun{dr(3, "issues", "provider", "--repo", "nope")}},
		dsc{name: "provider/repo-no-umbrella", runs: []drun{dr(3, "issues", "provider", "--repo", "web")}},
		dsc{name: "provider/no-hv", remote: "none", fx: fx{noHV: true}, runs: []drun{dr(3, "issues", "provider")}},
		dsc{name: "provider/extra-arg", runs: []drun{dr(2, "issues", "provider", "x")}},
	)

	// ---- issues list ----
	listBoth(&all, "list/default", dseed, "issues", "list")
	listBoth(&all, "list/limit-2", dseed, "issues", "list", "--limit", "2")
	listBoth(&all, "list/limit-1", dseed, "issues", "list", "--limit=1")
	listBoth(&all, "list/label", dseed, "issues", "list", "--label", "existing")
	listBoth(&all, "list/label-none", dseed, "issues", "list", "--label", "nosuch")
	listBoth(&all, "list/label-limit", dseed, "issues", "list", "--label", "existing", "--limit", "1")
	listBoth(&all, "list/empty-forge", dempty, "issues", "list")
	listBoth(&all, "list/mine", dseed, "issues", "list", "--mine")
	add(one("list/unknown-provider", dr(3, "issues", "list").with("no resolvable provider is exit 3 here, an empty list or 5 in the shim (#48)", 0).msg("issues.provider")).on("none"))
	dboth(&all, one("list/limit-0", dr(2, "issues", "list", "--limit", "0")))
	dboth(&all, one("list/limit-abc", dr(2, "issues", "list", "--limit", "abc")))
	dboth(&all, one("list/limit-neg", dr(2, "issues", "list", "--limit", "-3")))
	dboth(&all, one("list/label-empty", dr(2, "issues", "list", "--label", "")))
	dboth(&all, one("list/unknown-flag", dr(2, "issues", "list", "--bogus")))
	dboth(&all, one("list/positional", dr(2, "issues", "list", "7")))
	dboth(&all, one("list/forge-fails", dr(5, "issues", "list").env1("FAKE_TRACKER_FAIL=issue list")))
	dboth(&all, one("list/auth-fails", dr(5, "issues", "list").env1("FAKE_TRACKER_FAIL=auth status")))
	dboth(&all, one("list/rate-limited", dr(6, "issues", "list").env1(append([]string{"FAKE_TRACKER_FAIL=issue list"}, rate...)...)))
	add(dsc{name: "list/umbrella-web", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{dr(0, "issues", "list", "--repo", "web")}},
		dsc{name: "list/umbrella-api", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{dr(0, "issues", "list", "--repo", "api", "--limit", "3")}},
		dsc{name: "list/umbrella-root-unknown", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{dr(3, "issues", "list").with("no resolvable provider is exit 3 here, an empty list or 5 in the shim (#48)", 0)}},
		dsc{name: "list/repo-unknown", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{dr(3, "issues", "list", "--repo", "nope")}},
		dsc{name: "list/no-hv", remote: "none", fx: fx{noHV: true}, runs: []drun{dr(3, "issues", "list")}},
	)

	// ---- issues label ----
	dboth(&all, one("label/add-existing", dr(0, "issues", "label", "1", "--add", "bug").ch(false)))
	dboth(&all, one("label/add-new-label", dr(0, "issues", "label", "1", "--add", "brand-new").ch(true)))
	dboth(&all, one("label/add-registered", dr(0, "issues", "label", "1", "--add", "feature").ch(true)))
	dboth(&all, one("label/remove-present", dr(0, "issues", "label", "2", "--remove", "existing").ch(true)))
	dboth(&all, one("label/remove-absent", dr(0, "issues", "label", "1", "--remove", "existing").ch(false)))
	dboth(&all, one("label/add-closed-issue", dr(0, "issues", "label", "3", "--add", "feature").ch(true)))
	dboth(&all, one("label/add-equals-form", dr(0, "issues", "label", "6", "--add=bug").ch(true)))
	dboth(&all, one("label/unicode-label", dr(0, "issues", "label", "5", "--add", "prioé").ch(true)))
	dboth(&all, one("label/spaced-label", dr(0, "issues", "label", "5", "--add", "needs review").ch(true)))
	dboth(&all, one("label/missing-issue", dr(3, "issues", "label", "99", "--add", "bug").with("a missing issue is exit 3 here, 5 in the shim (#48)", 5)))
	dboth(&all, one("label/missing-issue-remove", dr(3, "issues", "label", "99", "--remove", "bug").with("a missing issue is exit 3 here, 5 in the shim (#48)", 5)))
	dboth(&all, one("label/both-flags", dr(2, "issues", "label", "1", "--add", "a", "--remove", "b")))
	dboth(&all, one("label/neither-flag", dr(2, "issues", "label", "1")))
	dboth(&all, one("label/empty-label", dr(2, "issues", "label", "1", "--add", "")))
	dboth(&all, one("label/no-number", dr(2, "issues", "label", "--add", "bug")))
	dboth(&all, one("label/bad-number", dr(2, "issues", "label", "abc", "--add", "bug")))
	dboth(&all, one("label/two-numbers", dr(2, "issues", "label", "1", "2", "--add", "bug")))
	dboth(&all, one("label/forge-fails", dr(5, "issues", "label", "1", "--add", "bug").env1("FAKE_TRACKER_FAIL=issue")))
	add(one("label/rate-limited/github", dr(5, "issues", "label", "1", "--add", "bug").env1(append([]string{"FAKE_TRACKER_FAIL=issue edit"}, rate...)...)),
		one("label/rate-limited-remove/github", dr(6, "issues", "label", "1", "--remove", "bug").env1(append([]string{"FAKE_TRACKER_FAIL=issue edit"}, rate...)...)),
		one("label/rate-limited/gitlab", dr(6, "issues", "label", "1", "--add", "bug").env1(append([]string{"FAKE_TRACKER_FAIL=issue update"}, rate...)...)).on("gitlab"),
		one("label/rate-limited-remove/gitlab", dr(6, "issues", "label", "1", "--remove", "bug").env1(append([]string{"FAKE_TRACKER_FAIL=issue update"}, rate...)...)).on("gitlab"))
	add(one("label/unknown-provider", dr(3, "issues", "label", "1", "--add", "bug").with("no resolvable provider is exit 3 here, an empty list or 5 in the shim (#48)", 5).msg("issues.provider")).on("none"))
	add(dsc{name: "label/autocreate-off/github", db: dseed, fx: fx{config: `{"issues": {"retryWaitSeconds": 0, "autoCreateLabel": false}}`},
		runs: []drun{func() drun {
			r := dr(3, "issues", "label", "1", "--add", "brand-new").with("old reads autoCreateLabel with jq's `// true`, so false still creates (divergence 3)", 0)
			r.skipDB = true
			return r
		}()}},
		dsc{name: "label/autocreate-off/gitlab", remote: "gitlab", db: dseed, fx: fx{config: `{"issues": {"retryWaitSeconds": 0, "autoCreateLabel": false}}`},
			runs: []drun{dr(0, "issues", "label", "1", "--add", "brand-new").ch(true)}})
	dboth(&all, dsc{name: "label/autocreate-off-existing", db: dseed, fx: fx{config: `{"issues": {"retryWaitSeconds": 0, "autoCreateLabel": false}}`},
		runs: []drun{dr(0, "issues", "label", "1", "--add", "existing").ch(true)}})
	dboth(&all, dsc{name: "label/autocreate-explicit-on", db: dseed, fx: fx{config: `{"issues": {"retryWaitSeconds": 0, "autoCreateLabel": true}}`},
		runs: []drun{dr(0, "issues", "label", "2", "--add", "newer").ch(true)}})
	add(dsc{name: "label/umbrella-web", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{dr(0, "issues", "label", "1", "--add", "bug", "--repo", "web").ch(false)}},
		dsc{name: "label/umbrella-api", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{dr(0, "issues", "label", "1", "--add", "fresh", "--repo", "api").ch(true)}},
		dsc{name: "label/repo-unknown", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{dr(3, "issues", "label", "1", "--add", "x", "--repo", "nope")}},
		dsc{name: "label/add-then-remove", db: dseed, runs: []drun{
			dr(0, "issues", "label", "1", "--add", "tmp").ch(true), dr(0, "issues", "label", "1", "--remove", "tmp").ch(true), dr(0, "issues", "label", "1", "--remove", "tmp").ch(false)}},
		dsc{name: "label/add-twice-gitlab", remote: "gitlab", db: dseed, runs: []drun{
			dr(0, "issues", "label", "1", "--add", "tmp").ch(true), dr(0, "issues", "label", "1", "--add", "tmp").ch(false)}},
		dsc{name: "label/add-twice-github", db: dseed, runs: []drun{
			dr(0, "issues", "label", "1", "--add", "tmp").ch(true), dr(0, "issues", "label", "1", "--add", "tmp").ch(false)}},
	)

	// ---- issues close ----
	dboth(&all, one("close/plain", dr(0, "issues", "close", "1", "--commit", "{head}").ch(true)))
	dboth(&all, one("close/with-item", dr(0, "issues", "close", "2", "--commit", "{head}", "--item", "F07").ch(true)))
	dboth(&all, one("close/short-sha", dr(0, "issues", "close", "6", "--commit", "{h1}", "--item", "B03").ch(true)))
	dboth(&all, one("close/ref-name", dr(0, "issues", "close", "1", "--commit", "HEAD").ch(true)))
	dboth(&all, one("close/empty-item", dr(0, "issues", "close", "1", "--commit", "{head}", "--item", "").ch(true)))
	dboth(&all, one("close/item-with-space", dr(0, "issues", "close", "1", "--commit", "{head}", "--item", "F 7").ch(true)))
	dboth(&all, one("close/commit-unknown", dr(3, "issues", "close", "1", "--commit", "deadbeef")))
	dboth(&all, one("close/missing-commit", dr(2, "issues", "close", "1")))
	dboth(&all, one("close/no-number", dr(2, "issues", "close", "--commit", "{head}")))
	dboth(&all, one("close/bad-number", dr(2, "issues", "close", "x1", "--commit", "{head}")))
	dboth(&all, one("close/missing-issue", dr(3, "issues", "close", "99", "--commit", "{head}").with("a missing issue is exit 3 here, 5 in the shim (#48)", 5)))
	dboth(&all, one("close/forge-fails", dr(5, "issues", "close", "1", "--commit", "{head}").env1("FAKE_TRACKER_FAIL=issue close")))
	dboth(&all, one("close/rate-limited", dr(6, "issues", "close", "1", "--commit", "{head}").env1(append([]string{"FAKE_TRACKER_FAIL=issue close"}, rate...)...)))
	dboth(&all, one("close/auth-fails", dr(5, "issues", "close", "1", "--commit", "{head}").env1("FAKE_TRACKER_FAIL=auth status")))
	add(one("close/unknown-provider", dr(3, "issues", "close", "1", "--commit", "{head}").with("no resolvable provider is exit 3 here, an empty list or 5 in the shim (#48)", 5).msg("issues.provider")).on("none"))
	add(one("close/already-closed/gitlab", dr(0, "issues", "close", "3", "--commit", "{head}").ch(false)).on("gitlab"))
	add(one("close/already-closed/github", dr(0, "issues", "close", "3", "--commit", "{head}").ch(false)))
	add(dsc{name: "close/umbrella-web", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{
		{argv: []string{"--json", "issues", "close", "1", "--commit", "{x:web}", "--repo", "web"}, want: 0, changed: yes()}}})
	add(dsc{name: "close/umbrella-api", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{
		{argv: []string{"--json", "issues", "close", "2", "--commit", "{x:api}", "--repo", "api", "--item", "T1"}, want: 0, changed: yes()}}})
	add(dsc{name: "close/repo-unknown", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{dr(3, "issues", "close", "1", "--commit", "HEAD", "--repo", "nope")}})
	add(dsc{name: "close/twice/gitlab", remote: "gitlab", db: dseed, runs: []drun{
		dr(0, "issues", "close", "1", "--commit", "{head}").ch(true), dr(0, "issues", "close", "1", "--commit", "{head}").ch(false)}})

	// ---- issues imported ----
	importedFx := fx{
		backlog: importedBacklog,
		archive: "sectioned",
		files: map[string]string{
			".hv/bugs/B01.md":     "# B01\n\nUpstream GH: #12 and GH: #13.\n",
			".hv/features/F01.md": "# F01\n\nGL: #8 Repos: web\n",
			".hv/tasks/T09.md":    "# T09 detail\n\nGH: #70\n",
		},
		after: func(t *testing.T, dir string, in *info) {
			write(t, dir, ".hv/ARCHIVE.md", "# Archive\n\n## Completed\n- ~~**[B05] [P2] Archived bug.** old GH: #50 Repos: web~~ Done 2026-05-15 [`e4abdbe`]\n- ~~**[F05] [Minor] Old.** old GL: #51~~ Done 2026-05-15 [`e4abdbe`]\n")
		},
	}
	imp := func(name string, argv ...string) {
		r := dr(0, append([]string{"issues", "imported"}, argv...)...)
		r.norm = sortEntries
		add(dsc{name: "imported/" + name, remote: "none", fx: importedFx, db: dseed, runs: []drun{r}})
	}
	imp("all")
	imp("for-repo-web", "--for-repo", "web")
	imp("for-repo-api", "--for-repo", "api")
	imp("for-repo-none", "--for-repo", "nosuch")
	imp("open-only")
	imp("open-only-web", "--open-only", "--for-repo", "web")
	imp("open-only-api", "--for-repo", "api", "--open-only")
	add(dsc{name: "imported/open-only-umbrella", remote: "none", fx: umbrella(importedFx), db: importedDB, runs: []drun{
		{argv: []string{"--json", "issues", "imported", "--open-only"}, want: 0, norm: sortEntries}}})
	add(dsc{name: "imported/open-only-umbrella-web", remote: "none", fx: umbrella(importedFx), db: importedDB, runs: []drun{
		{argv: []string{"--json", "issues", "imported", "--open-only", "--for-repo", "web"}, want: 0, norm: sortEntries}}})
	add(dsc{name: "imported/open-only-forge-fails", remote: "none", fx: importedFx, db: importedDB, runs: []drun{
		{argv: []string{"--json", "issues", "imported", "--open-only"}, want: 0, norm: sortEntries, env: []string{"FAKE_TRACKER_FAIL=issue view"}}}})
	add(dsc{name: "imported/empty-backlog", remote: "none", fx: fx{backlog: "# TODO\n\n## Bugs\n\n## Completed\n"}, runs: []drun{dr(0, "issues", "imported")}})
	add(dsc{name: "imported/no-archive-no-details", remote: "none", fx: fx{backlog: importedBacklog, files: map[string]string{".hv/bugs/B01.md": "", ".hv/features/F01.md": "", ".hv/plans/M01-B02.md": "", ".hv/plans/M02-F01.md": ""}}, runs: []drun{
		{argv: []string{"--json", "issues", "imported"}, want: 0, norm: sortEntries}}})
	add(dsc{name: "imported/no-hv", remote: "none", fx: fx{noHV: true}, runs: []drun{dr(3, "issues", "imported")}})
	add(dsc{name: "imported/repo-flag-rejected", remote: "none", fx: umbrella(importedFx), runs: []drun{dr(2, "issues", "imported", "--repo", "web")}})
	add(dsc{name: "imported/positional", remote: "none", fx: importedFx, runs: []drun{dr(2, "issues", "imported", "web")}})
	add(dsc{name: "imported/text-vs-open", remote: "none", fx: fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] One.** GH:#5 GL:  #6 Repos: web , api Related: [F01]\n- **[B02] [P1] Two.** GL: #6\n\n## Completed\n- ~~**[B03] [P1] Done.** GH: #1~~ Done 2026-01-01 [`a`]\n"}, runs: []drun{
		{argv: []string{"--json", "issues", "imported"}, want: 0, norm: sortEntries}}})
	add(dsc{name: "imported/archive-and-open-same-key", remote: "none", fx: fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] One.** GH: #5\n\n## Completed\n",
		after: func(t *testing.T, dir string, in *info) {
			write(t, dir, ".hv/ARCHIVE.md", "## Old\n- ~~**[B01] [P1] One.** GH: #5~~ Done 2026-01-01 [`a`]\n")
		}}, runs: []drun{{argv: []string{"--json", "issues", "imported"}, want: 0, norm: sortEntries}}})

	// ---- migrate issues ----
	addMigrate(&all)

	for _, s := range all {
		s := s
		t.Run(s.name, s.exec)
	}
	t.Logf("%d scenarios", len(all))
}

// listBoth is a successful `issues list` on github and gitlab. The fake gh
// rejects --assignee, so --mine fails on github: Go 5, the shim 70 (divergence 2).
func listBoth(all *[]dsc, name string, db func() map[string]any, argv ...string) {
	gh, gl := dr(0, argv...), dr(0, argv...)
	for _, a := range argv {
		if a == "--mine" {
			gh = dr(5, argv...).with("the fake gh rejects --assignee: rc 2, shim 70 (divergence 2)", 70)
		}
	}
	*all = append(*all, dsc{name: name + "/github", db: db, runs: []drun{gh}}, dsc{name: name + "/gitlab", remote: "gitlab", db: db, runs: []drun{gl}})
}

func (s dsc) withDB(f func() map[string]any) dsc { s.db = f; return s }

const importedBacklog = `# TODO

## Bugs
- **[B01] [P1] First bug.** x GH: #12 Related: [F01] Since: {h1}
- **[B02] [P2] Second bug.** y GL: #7 Repos: web
- **[B03] [P3] Third bug.** z GH: #5 Repos: web, api Milestone: M01
- **[B04] [P2] No refs.** nothing

## Features
- **[F01] [Major] Feature.** GH: #20 GL: #8 Detail: ` + "`.hv/features/F01.md`" + `

## Tasks
- **[T01] Task.** GL: #3 GH: #4 Repos: api

## Completed
- ~~**[B08] [P2] Done bug.** GH: #99~~ Done 2026-09-30 [` + "`abc1234`" + `]
`

// importedDB has the issues the GL: references point at, open and closed.
func importedDB() map[string]any {
	db := dseed()
	var rows []any
	for _, n := range []int{3, 7, 8, 12, 51} {
		st := "open"
		if n == 3 {
			st = "closed"
		}
		rows = append(rows, iss(n, fmt.Sprintf("Issue %d", n), "b", []string{}, st))
	}
	db["issues"] = rows
	db["next_issue"] = 100
	return db
}

var migMilestones = map[string]string{
	".hv/milestones/M00.md": "---\nid: M00\ntitle: Old\nstatus: shipped\ndepends: []\ncreated: 2026-01-01\n---\n\n# M00 — Old\n\n## Goal\n\nDone already.\n",
	".hv/milestones/M01.md": "---\nid: M01\ntitle: Core engine\nstatus: planned\ndepends: []\ncreated: 2026-01-02\n---\n\n# M01 — Core engine\n\n## Goal\n\nBuild the core\nin two lines.\n\n## Acceptance criteria\n\n- ship [B01] and [F01]; T1 is a label\n",
	".hv/milestones/M02.md": "---\nid: M02\ntitle: Second\nstatus: active\ndepends: [M01]\ncreated: 2026-01-03\n---\n\n# M02 — Second\n\n## Goal\n\nThe second thing.\n\n## Notes\n\nSee B03 and F01.\n",
	".hv/plans/M01-S01.md":  "# slice 1\n\n- [B01] first\n- T1 bare\n",
	".hv/plans/M01-S02.md":  "   \n",
	".hv/plans/M02-S01.md":  "# slice\n\n[F01] and [B03]\n",
}

// mfx is a migration project: the standard backlog (open B01-B04, F01, F02,
// T01, T02 with detail, proof, design and plan files) plus the extras.
func mfx(extra map[string]string) fx {
	files := map[string]string{}
	for k, v := range extra {
		files[k] = v
	}
	return fx{files: files}
}

func withMS(extra map[string]string) fx {
	files := map[string]string{}
	for k, v := range migMilestones {
		files[k] = v
	}
	for k, v := range extra {
		files[k] = v
	}
	return fx{files: files}
}

// mig is a run of hv migrate issues.
func mig(want int, args ...string) drun {
	return dr(want, append([]string{"migrate", "issues"}, args...)...)
}

func addMigrate(all *[]dsc) {
	add := func(s ...dsc) { *all = append(*all, s...) }
	rate := "FAKE_TRACKER_FAIL_MSG=secondary rate limit"
	m := func(name string, f fx, db func() map[string]any, runs ...drun) dsc {
		return dsc{name: "migrate/" + name, fx: f, db: db, runs: runs}
	}

	// preview
	for _, f := range []struct {
		name string
		fx   fx
		db   func() map[string]any
		args []string
	}{
		{"preview/items", mfx(nil), dseed, nil},
		{"preview/items-empty-forge", mfx(nil), dempty, nil},
		{"preview/with-milestones", withMS(nil), dseed, nil},
		{"preview/limit-3", withMS(nil), dseed, []string{"--limit", "3"}},
		{"preview/limit-0", withMS(nil), dseed, []string{"--limit", "0"}},
		{"preview/limit-99", mfx(nil), dseed, []string{"--limit=99"}},
	} {
		dboth(all, m(f.name, f.fx, f.db, mig(0, f.args...).ch(false)))
	}
	add(m("preview/unknown-provider-ok", withMS(nil), dseed, mig(0)).on("none"))
	// apply
	dboth(all, m("apply/items", mfx(nil), dseed, mig(0, "--apply")))
	dboth(all, m("apply/items-empty-forge", mfx(nil), dempty, mig(0, "--apply")))
	dboth(all, m("apply/with-milestones", withMS(nil), dseed, mig(0, "--apply")))
	dboth(all, m("apply/with-milestones-empty-forge", withMS(nil), dempty, mig(0, "--apply")))
	dboth(all, m("apply/twice", withMS(nil), dseed, mig(0, "--apply"), mig(0, "--apply")))
	dboth(all, m("apply/then-preview", withMS(nil), dseed, mig(0, "--apply"), mig(0)))
	dboth(all, m("apply/limit-resume", withMS(nil), dseed, mig(0, "--apply", "--limit", "2"), mig(0, "--apply", "--limit", "3"), mig(0, "--apply")))
	dboth(all, m("apply/limit-then-preview", withMS(nil), dseed, mig(0, "--apply", "--limit", "2"), mig(0)))
	dboth(all, m("apply/limit-0", withMS(nil), dseed, mig(0, "--apply", "--limit", "0")))
	dboth(all, m("apply/limit-0-items-only", mfx(nil), dseed, mig(0, "--apply", "--limit", "0"), mig(0, "--apply")))
	dboth(all, m("apply/pace-2ms", func() fx {
		f := withMS(nil)
		f.config = `{"issues": {"retryWaitSeconds": 0, "bulkPaceMs": 2}}`
		return f
	}(), dseed, mig(0, "--apply")))
	dboth(all, m("apply/pace-default-key-missing-zero", func() fx { f := mfx(nil); f.config = `{"issues": {"retryWaitSeconds": 0, "bulkPaceMs": 0}}`; return f }(), dseed, mig(0, "--apply")))
	// usage and refusals
	dboth(all, m("usage/limit-abc", mfx(nil), dseed, mig(2, "--limit", "abc")))
	dboth(all, m("usage/limit-neg", mfx(nil), dseed, mig(2, "--limit", "-1")))
	dboth(all, m("usage/limit-empty", mfx(nil), dseed, mig(2, "--limit", "")))
	dboth(all, m("usage/positional", mfx(nil), dseed, mig(2, "x")))
	dboth(all, m("usage/unknown-flag", mfx(nil), dseed, mig(2, "--dry-run")))
	dboth(all, m("refuse/no-backlog", fx{noBacklog: true}, dseed, mig(3)))
	dboth(all, m("refuse/no-backlog-apply", fx{noBacklog: true}, dseed, mig(3, "--apply")))
	add(dsc{name: "refuse/umbrella/preview", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{mig(4)}},
		dsc{name: "refuse/umbrella/apply", remote: "none", fx: umbrella(fx{}), db: dseed, runs: []drun{mig(4, "--apply")}},
		dsc{name: "refuse/no-hv", remote: "none", fx: fx{noHV: true}, runs: []drun{mig(3)}},
		dsc{name: "refuse/no-provider-apply", remote: "none", fx: mfx(nil), db: dseed, runs: []drun{mig(5, "--apply").msg("0 of 8 migrated")}},
		dsc{name: "refuse/no-provider-apply-empty-backlog", remote: "none", fx: fx{backlog: "# TODO\n\n## Bugs\n\n## Completed\n"}, db: dseed, runs: []drun{mig(0, "--apply")}},
	)
	// tracker failures and resume
	dboth(all, m("fail/tracking-issue", withMS(nil), dseed, mig(5, "--apply").env1("FAKE_TRACKER_FAIL=issue create").msg("0 of 8 migrated")))
	dboth(all, m("fail/milestone-create", withMS(nil), dseed, mig(5, "--apply").env1("FAKE_TRACKER_FAIL=milestones").msg("0 of 8 migrated")))
	dboth(all, m("fail/item-create", mfx(nil), dseed, mig(5, "--apply").env1("FAKE_TRACKER_FAIL=issue create").msg("0 of 8 migrated")))
	dboth(all, m("fail/rate-limit-item", mfx(nil), dseed, mig(6, "--apply").env1("FAKE_TRACKER_FAIL=issue create", rate).msg("0 of 8 migrated")))
	for _, p := range []struct{ remote, notes, edit string }{{"", "comments", "issue edit"}, {"gitlab", "notes", "issue update"}} {
		name := map[string]string{"": "github", "gitlab": "gitlab"}[p.remote]
		add(m("fail/notes-then-resume/"+name, mfx(nil), dseed,
			mig(5, "--apply").env1("FAKE_TRACKER_FAIL="+p.notes).msg("8 of 8 migrated"), mig(0, "--apply"), mig(0, "--apply")).on(p.remote),
			m("fail/notes-rate-limit-then-resume/"+name, mfx(nil), dseed,
				mig(6, "--apply").env1("FAKE_TRACKER_FAIL="+p.notes, rate).msg("8 of 8 migrated"), mig(0, "--apply")).on(p.remote),
			m("fail/related-edit-then-resume/"+name, mfx(nil), dseed,
				mig(5, "--apply").env1("FAKE_TRACKER_FAIL="+p.edit).msg("8 of 8 migrated"), mig(0, "--apply")).on(p.remote))
	}
	dboth(all, m("ok/auth-status-not-called", mfx(nil), dseed, mig(0, "--apply").env1("FAKE_TRACKER_FAIL=auth status")))
	dboth(all, m("fail/get-url", mfx(nil), dseed, mig(5, "--apply").env1("FAKE_TRACKER_FAIL=issue view").msg("0 of 8 migrated")))
	// map state
	preMap := `{
  "B01": {"id": "B7", "number": 7, "url": "https://example.test/7", "done": ["proof"]},
  "F01": {"id": "F8", "number": 8, "url": "https://example.test/8", "done": []}
}
`
	dboth(all, m("map/prepopulated-preview", mfx(map[string]string{".hv/issue-map.json": preMap}), dseed, mig(0)))
	dboth(all, m("map/prepopulated-apply", mfx(map[string]string{".hv/issue-map.json": preMap}), dseed78, mig(0, "--apply")))
	dboth(all, m("map/array-is-corrupt", mfx(map[string]string{".hv/issue-map.json": "[]\n"}), dseed,
		mig(70, "--apply").with("old dies with usage (divergence 4)", 2)))
	dboth(all, m("map/unparseable-restarts", mfx(map[string]string{".hv/issue-map.json": "{not json"}), dseed, mig(0, "--apply")))
	dboth(all, m("map/empty-object", mfx(map[string]string{".hv/issue-map.json": "{}\n"}), dseed, mig(0)))
	dboth(all, m("map/foreign-keys-kept", mfx(map[string]string{".hv/issue-map.json": `{"X9": {"id": "X9", "number": 1, "url": "u", "done": []}}`}), dseed, mig(0, "--apply")))
	fullMap := `{
  "B01": {"id": "B7", "number": 7, "url": "u", "done": ["proof", "related"]}, "B02": {"id": "B8", "number": 8, "url": "u", "done": ["plan", "related"]},
  "B03": {"id": "B9", "number": 9, "url": "u", "done": []}, "B04": {"id": "B10", "number": 10, "url": "u", "done": []},
  "F01": {"id": "F11", "number": 11, "url": "u", "done": ["plan", "related"]}, "F02": {"id": "F12", "number": 12, "url": "u", "done": ["design", "related"]},
  "T01": {"id": "T13", "number": 13, "url": "u", "done": []}, "T02": {"id": "T14", "number": 14, "url": "u", "done": ["related"]}
}`
	dboth(all, m("map/all-migrated-freezes", mfx(map[string]string{".hv/issue-map.json": fullMap}), dseed, mig(0, "--apply").ch(true)))
	frozen := "> Frozen: this backlog moved to the issue tracker on 2026-01-01 (see .hv/issue-map.json). Edit issues, not this file.\n\n"
	dboth(all, m("map/all-migrated-frozen-noop", fx{backlog: frozen + stdBacklog, files: map[string]string{".hv/issue-map.json": fullMap}}, dseed, mig(0, "--apply").ch(false)))
	dboth(all, m("freeze/already-frozen", fx{backlog: frozen + stdBacklog}, dseed, mig(0, "--apply")))
	dboth(all, m("freeze/leading-blank-lines", fx{backlog: "\n\n" + frozen + stdBacklog}, dseed, mig(0, "--apply")))
	dboth(all, m("freeze/empty-backlog", fx{backlog: "# TODO\n\n## Bugs\n\n## Completed\n"}, dseed, mig(0, "--apply"), mig(0, "--apply")))
	// content cases
	dboth(all, m("content/unmapped-related", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] One.** a Related: [B08], [F01] Since: {h1}\n- **[B02] [P2] Two.** b Related: [B08], [B09]\n\n## Features\n- **[F01] [Major] Feat.** c\n\n## Completed\n- ~~**[B08] [P2] Done.** x~~ Done 2026-09-30 [`abc`]\n"}, dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/bad-tag-dropped", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P9] Bad tag.** a\n- **[B02] [Major] Wrong kind tag.** b\n\n## Features\n- **[F01] [P1] Wrong too.** c\n\n## Tasks\n- **[T01] [Major] Task tag.** d\n"}, dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/milestone-not-on-tracker", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] One.** a Milestone: M07\n- **[B02] [P1] Two.** b Milestone: M09\n"}, dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/milestone-in-map-and-files", withMS(map[string]string{}), dempty, mig(0), mig(0, "--apply")))
	dboth(all, m("content/id-placeholder", fx{files: map[string]string{".hv/tasks/T01.md": "# {ID}\n\nSee [{ID}] here.\n"}}, dseed, mig(0, "--apply")))
	dboth(all, m("content/unicode-and-quotes", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] Café \"quoted\" title.** résumé ☃ text Since: {h1}\n\n## Tasks\n- **[T01] Dotted v1.2.3 name.** body\n"}, dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/duplicate-id", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] One.** a\n- **[B01] [P1] One again.** b\n"}, dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/title-only-dots", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] Fine.** a\n- **[B02] [P1] ..** b\n- **[B03] [P1] After.** c\n"}, dseed, mig(2, "--apply")))
	dboth(all, m("content/note-split", fx{files: map[string]string{".hv/designs/F02.md": strings.Repeat("a design line\n", 40), ".hv/plans/M01-B02.md": strings.Repeat("plan line [B01]\n", 30)}}, dseed,
		mig(0, "--apply").env1("HV_NOTE_LIMIT=200")))
	dboth(all, m("content/proof-only-detail", fx{files: map[string]string{".hv/bugs/B01.md": "## Proof\n- build · PASS · ok\n"}}, dseed, mig(0, "--apply")))
	dboth(all, m("content/detail-blank", fx{files: map[string]string{".hv/bugs/B01.md": "\n\n   \n"}}, dseed, mig(0, "--apply")))
	dboth(all, m("content/related-bare-and-bracketed", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] One.** a Related: B02, [F01]\n- **[B02] [P1] Two.** b Related: [B01]\n\n## Features\n- **[F01] [Major] F.** c Related: [B01], [B02], T01\n\n## Tasks\n- **[T01] T.** d\n", files: map[string]string{".hv/designs/F01.md": "see B01, [B02], B01.md and /path/B02 and xB01 and B011\n", ".hv/plans/M01-F01.md": "Relates to F01 and [T01]\n"}}, dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/custom-labels", fx{config: `{"issues": {"retryWaitSeconds": 0, "bulkPaceMs": 0, "labels": {"types": {"bug": "kind/bug", "feature": "kind/feature", "task": "kind/task"}, "priorityPrefix": "prio-", "sizePrefix": "effort:", "milestoneTracker": "ms-tracker"}}}`, files: migMilestones}, dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/config-provider-gitlab", fx{config: `{"issues": {"retryWaitSeconds": 0, "bulkPaceMs": 0, "provider": "gitlab"}}`}, dseed, mig(0, "--apply")))
	dboth(all, m("content/config-provider-github", fx{config: `{"issues": {"retryWaitSeconds": 0, "bulkPaceMs": 0, "provider": "github"}}`}, dseed, mig(0, "--apply")))
	add(m("content/config-provider-without-remote", fx{config: `{"issues": {"retryWaitSeconds": 0, "bulkPaceMs": 0, "provider": "github"}}`}, dseed, mig(0, "--apply")).on("none"))
	dboth(all, m("content/ms-id-mismatch", withMS(map[string]string{".hv/milestones/M02.md": "---\nid: M05\ntitle: Odd\nstatus: planned\ndepends: [M01, M09]\n---\n\n# M05\n\n## Goal\n\nGoal text.\n"}), dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/ms-no-frontmatter-id", withMS(map[string]string{".hv/milestones/M02.md": "---\ntitle: Noid\nstatus: active\n---\n\n# M02 — Heading title\n\n## Goal\n\nText.\n"}), dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/ms-archived-and-shipped-skipped", withMS(map[string]string{".hv/milestones/M03.md": "---\nid: M03\ntitle: Arch\nstatus: archived\n---\n\n# M03\n", ".hv/milestones/M04.md": "no frontmatter\n"}), dseed, mig(0, "--apply")))
	dboth(all, m("content/ms-only", fx{backlog: "# TODO\n\n## Bugs\n\n## Completed\n", files: migMilestones}, dempty, mig(0), mig(0, "--apply")))
	dboth(all, m("content/ms-depends-multiple", withMS(map[string]string{".hv/milestones/M02.md": "---\nid: M02\ntitle: Deps\nstatus: active\ndepends: [M01, M00]\n---\n\n# M02 — Deps\n\n## Goal\n\nDepends on two.\n"}), dempty, mig(0, "--apply")))
	dboth(all, m("content/fields-all", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] Full.** desc text Detail: `.hv/bugs/B01.md` Related: [F01]. Milestone: M09 Repos: web, api Subsystem: capture. Captured: 2026-01-02 Since: {h1}\n\n## Features\n- **[F01] [Cosmetic] Pretty.** x\n"}, dseed, mig(0), mig(0, "--apply")))
	dboth(all, m("content/crlf-backlog", fx{backlog: "# TODO\r\n\r\n## Bugs\r\n- **[B01] [P1] Crlf.** a Since: {h1}\r\n"}, dseed, mig(0, "--apply")))
	dboth(all, m("content/plan-glob-ambiguity", fx{files: map[string]string{".hv/plans/M01-B01.md": "p1\n", ".hv/plans/M02-B01.md": "p2\n", ".hv/plans/M01-B011.md": "wrong\n"}}, dseed, mig(0, "--apply")))
}
