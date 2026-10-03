package main

// Black-box parity for the A4 item verbs in issue mode (#48). Each scenario
// builds a git project whose origin resolves to github or gitlab, seeds the
// stateful fake forge (test/fakes/fake_tracker.py) with the same issues for
// both sides, runs the old implementation on side A and the Go binary on
// side B, and compares exit code, envelope (shim-backed verbs), and the final
// fake-forge database.
//
// Side A is test/hv-shim for the verbs it adapts (item create, complete, field
// get|list|set, state, reopen) and the old helper directly for the rest (show,
// claim, release, note, ready, comment); for those the Go envelope is checked
// against what the old stdout implies.
//
// Safety: the shared TestMain refuses to run unless gh resolves to test/fakes
// (TestIssueFakesFirst checks glab too); every run has its own
// FAKE_TRACKER_DB under t.TempDir.
//
// Documented divergences (each scenario that exercises one carries a `div`
// text or a `changed` expectation, so none passes silently):
//  1. shim envelopes echo the raw ref as id ("F12" on create) and a null or
//     missing type for bare numbers; the contract (rule 11) and Go use the
//     number plus the type letter. normShim rewrites the shim side from the
//     fake DB, never from Go.
//  2. item field set on a closed issue: Go 4 (contract), old rc 1 -> 3.
//  3. data.changed: shim says true for every issue-mode write; Go reports
//     whether the tracker changed. Scenarios assert Go's value (isc.changed)
//     and drop the key from the envelope comparison.
//  4. a milestone that is not M<digits>: Go 2, old rc 1 -> 3.
//  5. an empty note body: Go 2 (contract), old writes an empty note.
//  6. the loser of a claim: Go sends failure data {blockedBy: "claimed",
//     changed: true} (#106 contract: its claim and release were posted);
//     old prints only the message.
//  7. comment add / note on a milestone tracker issue or with a wrong type
//     letter: old never looks the issue up (works), Go resolves it first (3).
//  8. file backend, claim/release on an unknown item: old exits 0 silently,
//     the contract says 3.
//  9. note show of an absent note: Go has data.exists false; old prints nothing.
//  10. item create --body-file in issue mode: the shim reports data.detail
//     (".hv/tasks/T12.md", a file issue mode never writes); Go omits it.
//     Scenario create/id-placeholder-body drops it from the shim side.
//  11. item field set --name detail in issue mode: contract and Go say 4
//     (backend), the old helper path exits 2 (usage).
//  12. item note add on the file backend: the old helper crashes with a
//     TypeError traceback (FileBackend.note_put aliases note_get, which takes
//     one argument fewer), so rc 1 -> 3; Go and the contract say 4.

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"testing"
)

type isc struct {
	name     string
	remote   string // "" github, "gitlab", "none" (no origin)
	file     bool   // file backend project, no tracker
	cfg      string // config.json override
	argv     []string
	in       string
	old      []string
	oldMap   func(rc int, stderr string) int
	env      []string
	want     int
	div      string // the reference cannot agree on the exit
	refWant  int
	skipDB   bool // reference DB is not comparable; Go's must equal the seed
	changed  *bool
	textSame bool     // Go's text mode must equal the old stdout (read-only verbs)
	shimDrop []string // data keys the shim sends and the contract's Go does not (see div 10)
	check    func(t *testing.T, e envl, ref run, db map[string]any)
}

func yes() *bool { b := true; return &b }
func no() *bool  { b := false; return &b }

const issueCfg = `{"backlog": {"backend": "issues"}, "issues": {"retryWaitSeconds": 0}}`

func cm(id int, body string) map[string]any {
	return map[string]any{"id": id, "body": body, "author": "fake-user"}
}

func iss(n int, title, body string, labels []string, state string, comments ...map[string]any) map[string]any {
	cs := []any{}
	for _, c := range comments {
		cs = append(cs, c)
	}
	lb := []any{}
	for _, l := range labels {
		lb = append(lb, l)
	}
	i := map[string]any{"number": n, "title": title, "body": body, "labels": lb, "milestone": nil,
		"state": state, "state_reason": nil, "closed_at": nil, "assignees": []any{}, "comments": cs}
	if state == "closed" {
		i["state_reason"], i["closed_at"] = "completed", "2026-01-01T00:00:00Z"
	}
	return i
}

// seedDB is the fixture forge: #1 feature with criteria and a native
// milestone, #2 bug, #3 milestone tracker, #4 closed task, #5 bug with a proof
// note, a design note and a question, #6 feature claimed by "other", #7 task
// claimed by "me", #8 blocked bug, #9 dropped bug, #10 bare task, #11 task with
// a three-part plan note.
func seedDB() map[string]any {
	i1 := iss(1, "Add export", "Export it.\n\n## Acceptance\n- [ ] works\n\n<!-- hv:fields\nRelated: B2\n-->",
		[]string{"type:feature", "size:Major"}, "open")
	i1["milestone"] = []any{"M07 — Title", 1}
	i6 := iss(6, "Parallel work", "x", []string{"type:feature", "in-progress"}, "open",
		cm(4, "<!-- hv:claim other -->\nClaimed by other"))
	i6["assignees"] = []any{"fake-user"}
	i9 := iss(9, "Dropped bug", "x", []string{"type:bug", "not-planned"}, "closed")
	i9["state_reason"] = "not_planned"
	return map[string]any{
		"next_issue": 12, "next_milestone": 2, "next_comment": 20, "next_mr": 1,
		"labels": []any{}, "prs": []any{},
		"milestones": []any{map[string]any{"number": 1, "title": "M07 — Title", "description": "", "state": "open"}},
		"issues": []any{
			i1,
			iss(2, "Crash on start", "boom", []string{"type:bug", "p1"}, "open"),
			iss(3, "M07 tracking", "", []string{"milestone-tracker"}, "open"),
			iss(4, "Old task", "x", []string{"type:task"}, "closed"),
			iss(5, "Noted bug", "x", []string{"type:bug"}, "open",
				cm(1, "<!-- hv:proof -->\n## Proof\n- build · PASS · ok"),
				cm(2, "<!-- hv:design -->\nthe design"),
				cm(3, "<!-- hv:comment question -->\nWhy?\nmore")),
			i6,
			iss(7, "Mine", "x", []string{"type:task", "needs-review"}, "open",
				cm(5, "<!-- hv:claim me -->\nClaimed by me")),
			iss(8, "Blocked bug", "x", []string{"type:bug", "blocked"}, "open"),
			i9,
			iss(10, "Bare task", "", []string{"type:task"}, "open"),
			iss(11, "Planned", "x", []string{"type:task"}, "open",
				cm(6, "<!-- hv:plan 1/3 -->\nline1\n"), cm(7, "<!-- hv:plan 2/3 -->\nline2\n"), cm(8, "<!-- hv:plan 3/3 -->\nline3")),
		},
	}
}

func writeDB(t *testing.T, db map[string]any) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "tracker.json")
	raw, _ := json.Marshal(db)
	if err := os.WriteFile(p, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// readDB loads a fake DB with the volatile closed_at stamps normalized.
func readDB(t *testing.T, p string) map[string]any {
	t.Helper()
	raw, err := os.ReadFile(p)
	if err != nil {
		return nil
	}
	var db map[string]any
	if err := json.Unmarshal(raw, &db); err != nil {
		t.Fatalf("%s: %v", p, err)
	}
	for _, i := range db["issues"].([]any) {
		m := i.(map[string]any)
		if s, _ := m["closed_at"].(string); s != "" {
			m["closed_at"] = "<ts>"
		}
	}
	return db
}

func norm(v map[string]any) map[string]any {
	raw, _ := json.Marshal(v)
	var out map[string]any
	json.Unmarshal(raw, &out)
	for _, i := range out["issues"].([]any) {
		m := i.(map[string]any)
		if s, _ := m["closed_at"].(string); s != "" {
			m["closed_at"] = "<ts>"
		}
	}
	return out
}

func envRun(t *testing.T, dir, stdin string, extra []string, name string, args ...string) run {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(append([]string{}, baseEnv...), extra...)
	cmd.Stdin = strings.NewReader(stdin)
	var so, se strings.Builder
	cmd.Stdout, cmd.Stderr = &so, &se
	code := 0
	if err := cmd.Run(); err != nil {
		ee, ok := err.(*exec.ExitError)
		if !ok {
			t.Fatalf("%s: %v", name, err)
		}
		code = ee.ExitCode()
	}
	return run{code: code, stdout: so.String(), stderr: se.String(), dir: dir}
}

// mapIssueOld maps an old helper's rc to the contract: usage text 2, not found
// 3, backend 4, tracker unavailable 5, rate limit 6, claimed-by-another 4.
func mapIssueOld(rc int, stderr string) int {
	switch rc {
	case 0:
		return 0
	case 1:
		if usageish.MatchString(stderr) {
			return 2
		}
		return 3
	case 2, 5:
		return 4
	case 3:
		return 5
	case 4:
		return 6
	}
	return 70
}

func readyMapIssue(rc int, stderr string) int {
	if rc == 1 && !strings.Contains(stderr, "error:") {
		return 1
	}
	return mapIssueOld(rc, stderr)
}

var digits = regexp.MustCompile(`\d+`)

// typeOfIssue is the type letter of issue n in db from its labels.
func typeOfIssue(db map[string]any, n string) any {
	if db == nil {
		return nil
	}
	for _, i := range db["issues"].([]any) {
		m := i.(map[string]any)
		if fmt.Sprint(m["number"]) != n {
			continue
		}
		for _, l := range m["labels"].([]any) {
			switch l {
			case "type:bug", "kind/bug":
				return "B"
			case "type:feature", "kind/feature":
				return "F"
			}
		}
		return "T"
	}
	return nil
}

// normShim rewrites the shim's id and type to the contract's (divergence 1),
// taking the type from the reference forge's final DB, never from Go.
func normShim(e envl, refDB map[string]any) envl {
	d, ok := e["data"].(map[string]any)
	if !ok {
		return e
	}
	id, ok := d["id"].(string)
	if !ok {
		return e
	}
	if n := digits.FindString(id); n != "" && !strings.HasPrefix(id, "B0") && !strings.HasPrefix(id, "F0") && !strings.HasPrefix(id, "T0") {
		d["id"] = n
		d["type"] = typeOfIssue(refDB, n)
	}
	return e
}

func dropChanged(e envl) {
	if d, ok := e["data"].(map[string]any); ok {
		delete(d, "changed")
	}
}

// iscOracle is what the old side did for a scenario.
type iscOracle struct {
	Code           int // the old exit code, after mapping to the contract's
	Stdout, Stderr string
	Tree           map[string]string // file scenarios: the .hv/ tree after the run
	DB             map[string]any    // the forge database after the run
}

// oracle runs the scenario's old side in a copy of base, or replays it from
// the cache when none of its inputs changed (parity_cache_test.go).
func (s isc) oracle(t *testing.T, base string, in info, remote string, argv []string) (ref run, refCode int, tree map[string]string, db map[string]any) {
	t.Helper()
	var old []string
	if len(s.old) > 0 {
		old = subst(s.old, in)
	}
	key := oracleKey(t, map[string]any{"kind": "isc", "project": projectDigest(base), "remote": remote, "seed": seedDB(),
		"argv": argv, "old": old, "in": s.in, "env": s.env, "file": s.file})
	var c iscOracle
	if oracleLoad(key, &c) {
		return run{stdout: c.Stdout, stderr: c.Stderr}, c.Code, c.Tree, c.DB
	}
	refDir := copyTree(t, base)
	refDB := writeDB(t, seedDB())
	env := append([]string{"FAKE_TRACKER_DB=" + refDB}, s.env...)
	if len(old) > 0 {
		ref = envRun(t, refDir, s.in, env, filepath.Join(stagedBin, old[0]), old[1:]...)
		m := s.oldMap
		if m == nil {
			m = mapIssueOld
		}
		refCode = m(ref.code, ref.stderr)
	} else {
		ref = envRun(t, refDir, s.in, env, "python3", append([]string{shimPath}, argv...)...)
		refCode = ref.code
	}
	ref.dir = refDir
	if s.file {
		tree = snapshot(t, refDir)
	}
	db = readDB(t, refDB)
	oracleStore(t, key, iscOracle{refCode, ref.stdout, ref.stderr, tree, db})
	return ref, refCode, tree, db
}

// fixture builds the scenario's project with its origin remote.
func (s isc) fixture(t *testing.T) (base string, in info, remote string) {
	t.Helper()
	f := fx{config: issueCfg}
	if s.file {
		f = fx{}
	} else {
		f.noBacklog = true
	}
	if s.cfg != "" {
		f.config = s.cfg
	}
	base, in = f.build(t)
	remote = map[string]string{"": "https://github.com/example/repo.git", "gitlab": "https://gitlab.com/example/repo.git"}[s.remote]
	if remote != "" {
		git(t, base, "remote", "add", "origin", remote)
	}
	return base, in, remote
}

func (s isc) exec(t *testing.T) {
	t.Parallel()
	if frozenOn != nil {
		frozenCheck(t, s.goSide)
		return
	}
	base, in, remote := s.fixture(t)
	argv := subst(s.argv, in)
	ref, refCode, refTree, rDB := s.oracle(t, base, in, remote, argv)
	goDir := copyTree(t, base)
	goDB := writeDB(t, seedDB())
	goRun := envRun(t, goDir, s.in, append([]string{"FAKE_TRACKER_DB=" + goDB}, s.env...), hvBin, argv...)
	if goRun.code != s.want {
		t.Errorf("go exit = %d, want %d\nargv: %v\nstdout: %s\nstderr: %s", goRun.code, s.want, argv, goRun.stdout, goRun.stderr)
	}
	goEnv := parseEnv(t, "go", goRun)
	goEnv["__info"] = in
	if s.div != "" {
		if refCode != s.refWant {
			t.Errorf("reference exit = %d, want %d (divergence: %s)\nstdout: %s\nstderr: %s", refCode, s.refWant, s.div, ref.stdout, ref.stderr)
		}
	} else if refCode != goRun.code {
		t.Errorf("exit differs: reference %d, go %d\nargv: %v\nref stdout: %s\nref stderr: %s\ngo stdout: %s\ngo stderr: %s",
			refCode, goRun.code, argv, ref.stdout, ref.stderr, goRun.stdout, goRun.stderr)
	}
	if s.file {
		if d := diffTrees(refTree, snapshot(t, goDir)); d != "" {
			t.Errorf(".hv/ trees differ:\n%s", d)
		}
	}
	gDB := readDB(t, goDB)
	if !s.file && (gDB == nil || rDB == nil) {
		t.Fatalf("a forge DB went missing (go %v, reference %v)", gDB != nil, rDB != nil)
	}
	switch {
	case s.skipDB:
		if want := norm(seedDB()); !reflect.DeepEqual(gDB, want) && !(s.file && gDB == nil) {
			t.Errorf("go changed the forge although it refused (%s)", s.div)
		}
	case !reflect.DeepEqual(gDB, rDB):
		gj, _ := json.MarshalIndent(gDB, "", " ")
		rj, _ := json.MarshalIndent(rDB, "", " ")
		t.Errorf("forge DBs differ\nargv: %v\nref stderr: %s\n--- reference\n%s\n--- go\n%s", argv, ref.stderr, rj, gj)
	}
	if len(s.old) == 0 && s.div == "" {
		r, g := normShim(parseEnv(t, "shim", ref), rDB), goEnv
		if s.changed != nil {
			dropChanged(r)
			dropChanged(g)
			if got := at(goEnv, "data.changed"); s.want == 0 && got == nil {
				// dropped above; re-read from the raw go output
				ge := parseEnv(t, "go", goRun)
				if at(ge, "data.changed") != *s.changed {
					t.Errorf("go data.changed = %v, want %v", at(ge, "data.changed"), *s.changed)
				}
			}
		}
		for _, k := range s.shimDrop {
			if d, ok := r["data"].(map[string]any); ok {
				delete(d, k)
			}
		}
		r, g = stripText(r), stripText(g)
		if !reflect.DeepEqual(map[string]any(r), map[string]any(g)) {
			rj, _ := json.Marshal(r)
			gj, _ := json.Marshal(g)
			t.Errorf("envelopes differ\nargv: %v\nshim: %s\ngo:   %s", argv, rj, gj)
		}
	}
	if s.textSame && s.want == 0 && refCode == 0 {
		var txt []string
		for _, a := range argv {
			if a != "--json" {
				txt = append(txt, a)
			}
		}
		gt := envRun(t, goDir, s.in, append([]string{"FAKE_TRACKER_DB=" + goDB}, s.env...), hvBin, txt...)
		if strings.TrimRight(gt.stdout, "\n") != strings.TrimRight(ref.stdout, "\n") {
			t.Errorf("text mode differs from old stdout\nold: %q\ngo:  %q", ref.stdout, gt.stdout)
		}
	}
	if s.check != nil {
		s.check(t, goEnv, ref, rDB)
	}
	record(t, s.goSide)
}

func TestIssueFakesFirst(t *testing.T) {
	for _, tool := range []string{"gh", "glab"} {
		p, err := exec.LookPath(tool)
		if err != nil || !strings.HasPrefix(p, filepath.Join(repoDir, "test", "fakes")+string(os.PathSeparator)) {
			t.Fatalf("%s resolves to %q (%v), not test/fakes", tool, p, err)
		}
	}
}

func TestParityA4Issue(t *testing.T) {
	var all []isc
	add := func(s ...isc) { all = append(all, s...) }
	both := func(s isc) { // github and gitlab
		g := s
		g.name = s.name + "/gitlab"
		g.remote = "gitlab"
		s.name += "/github"
		add(s, g)
	}
	rate := []string{"FAKE_TRACKER_FAIL=issue view", "FAKE_TRACKER_FAIL_MSG=secondary rate limit"}
	filesBody := map[string]string{}
	_ = filesBody

	// negatives every ref-taking verb shares: unknown, wrong letter, tracker issue,
	// rate limit, forge unavailable.
	type verb struct {
		name string
		argv func(id string) []string // new argv including --json
		old  func(id string) []string
		in   string
		oldM func(int, string) int
		ok   string // a valid ID for the rate-limit and unavailable runs
	}
	verbs := []verb{
		{"complete", func(id string) []string { return j("item", "complete", id, "--commit", "abc1234", "--no-proof") }, nil, "", nil, "2"},
		{"reopen", func(id string) []string { return j("item", "reopen", id) }, nil, "", nil, "4"},
		{"statev", func(id string) []string { return j("item", "state", id, "--to", "in-progress") }, nil, "", nil, "2"},
		{"fieldget", func(id string) []string { return j("item", "field", "get", id, "--name", "title") }, nil, "", nil, "1"},
		{"fieldset", func(id string) []string { return j("item", "field", "set", id, "--name", "related", "--value", "B1") }, nil, "", nil, "2"},
		{"show", func(id string) []string { return j("item", "show", id) }, func(id string) []string { return []string{"hv-item-show", id} }, "", nil, "5"},
		{"claim", func(id string) []string { return j("item", "claim", id, "--as", "me") }, func(id string) []string { return []string{"hv-item-claim", id, "--as", "me"} }, "", nil, "2"},
		{"release", func(id string) []string { return j("item", "release", id, "--as", "me") }, func(id string) []string { return []string{"hv-item-release", id, "--as", "me"} }, "", nil, "7"},
		{"ready", func(id string) []string { return j("item", "ready", id) }, func(id string) []string { return []string{"hv-item-ready", id} }, "", readyMapIssue, "1"},
		{"commentlist", func(id string) []string { return j("item", "comment", "list", id) }, func(id string) []string { return []string{"hv-item-comment", id, "--list"} }, "", nil, "5"},
	}
	for _, v := range verbs {
		mk := func(name, id string, want int, env []string, remote string) isc {
			s := isc{name: v.name + "/" + name, argv: v.argv(id), env: env, remote: remote, want: want, oldMap: v.oldM}
			if v.old != nil {
				s.old = v.old(id)
			}
			return s
		}
		add(mk("unknown", "99", 3, nil, ""), mk("wrong-letter", "F2", 3, nil, ""), mk("tracker-issue", "3", 3, nil, ""),
			mk("rate-limit", v.ok, 6, rate, ""), mk("forge-unavailable", v.ok, 5, nil, "none"))
	}
	// the same refusals when the ref names a bug as a feature letter and the
	// other spellings of a valid ref resolve.
	for _, ref := range []string{"2", "#2", "B2", "b2"} {
		add(isc{name: "show/ref-" + ref, argv: j("item", "show", ref), old: []string{"hv-item-show", ref}, want: 0, textSame: false,
			check: func(t *testing.T, e envl, ref run, db map[string]any) {
				eq(t, e, "data.id", "2")
				eq(t, e, "data.type", "B")
			}})
	}

	// ---- create (shim)
	cr := func(name string, want int, args ...string) isc {
		return isc{name: "create/" + name, argv: j(append([]string{"item", "create"}, args...)...), want: want, changed: yes()}
	}
	body := fx{}
	_ = body
	add(
		cr("feature-full", 0, "--kind", "features", "--title", "New thing", "--tag", "Major", "--desc", "d", "--milestone", "M07", "--related", "B2", "--subsystem", "web", "--captured", "2026-10-01"),
		cr("bug-tag", 0, "--kind", "bugs", "--title", "Broken", "--tag", "P2"),
		cr("task-plain", 0, "--kind", "tasks", "--title", "Chore"),
		cr("milestone-missing", 3, "--kind", "bugs", "--title", "x", "--milestone", "M99"),
		cr("bad-tag", 2, "--kind", "bugs", "--title", "x", "--tag", "Major"),
		cr("no-title", 2, "--kind", "bugs"),
		isc{name: "create/milestone-bad-format", argv: j("item", "create", "--kind", "bugs", "--title", "x", "--milestone", "next"), want: 2,
			div: "4: Go usage 2 (contract: one milestone ID), the shim maps the old ValueError to 5", refWant: 5},
		isc{name: "create/rate-limit", argv: j("item", "create", "--kind", "bugs", "--title", "x"), want: 6,
			env: []string{"FAKE_TRACKER_FAIL=issue create", "FAKE_TRACKER_FAIL_MSG=secondary rate limit"}},
		isc{name: "create/forge-unavailable", remote: "none", argv: j("item", "create", "--kind", "bugs", "--title", "x"), want: 5},
		isc{name: "create/id-placeholder-body", argv: j("item", "create", "--kind", "tasks", "--title", "Doc", "--body-file", "body.md"), want: 0, changed: yes(), shimDrop: []string{"detail"},
			check: func(t *testing.T, e envl, _ run, db map[string]any) {
				for _, i := range db["issues"].([]any) {
					if m := i.(map[string]any); m["number"] == float64(12) && !strings.Contains(fmt.Sprint(m["body"]), "# T12") {
						t.Errorf("{ID} not replaced: %v", m["body"])
					}
				}
				eq(t, e, "data.id", "12")
				eq(t, e, "data.type", "T")
			}},
		isc{name: "create/custom-labels", cfg: `{"backlog":{"backend":"issues"},"issues":{"retryWaitSeconds":0,"labels":{"types":{"bug":"kind/bug","feature":"kind/feature","task":"kind/task"},"priorityPrefix":"prio-","sizePrefix":"effort:"}}}`,
			argv: j("item", "create", "--kind", "bugs", "--title", "Custom", "--tag", "P1"), want: 0, changed: yes()},
	)
	both(cr("gitlab-feature", 0, "--kind", "features", "--title", "New thing", "--tag", "Minor", "--milestone", "M07"))

	// ---- field set / get / list (shim)
	fs := func(name, id, field, value string, want int, ch *bool) isc {
		return isc{name: "fieldset/" + name, argv: j("item", "field", "set", id, "--name", field, "--value", value), want: want, changed: ch}
	}
	add(
		fs("milestone", "2", "milestone", "M07", 0, yes()),
		fs("milestone-same", "1", "milestone", "M07", 0, no()),
		fs("milestone-clear", "1", "milestone", "", 0, yes()),
		fs("milestone-clear-none", "2", "milestone", "", 0, no()),
		fs("related", "2", "related", "B1", 0, yes()),
		fs("related-same", "1", "related", "B2", 0, no()),
		fs("related-clear", "1", "related", "", 0, yes()),
		fs("repos", "2", "repos", "web, api", 0, yes()),
		fs("milestone-missing", "2", "milestone", "M99", 3, nil),
		isc{name: "fieldset/detail-refused", argv: j("item", "field", "set", "2", "--name", "detail", "--value", "x"), want: 4},
		fs("bad-field", "2", "title", "x", 2, nil),
		isc{name: "fieldset/closed", argv: j("item", "field", "set", "4", "--name", "related", "--value", "B1"), want: 4},
		isc{name: "fieldset/milestone-bad-format", argv: j("item", "field", "set", "2", "--name", "milestone", "--value", "later"), want: 2,
			div: "4: Go usage 2 (contract: one milestone ID), the shim maps the old ValueError to 5", refWant: 5},
		isc{name: "fieldget/title", argv: j("item", "field", "get", "1", "--name", "title"), want: 0},
		isc{name: "fieldget/milestone", argv: j("item", "field", "get", "1", "--name", "milestone"), want: 0},
		isc{name: "fieldget/related-bracketed", argv: j("item", "field", "get", "1", "--name", "related"), want: 0},
		isc{name: "fieldget/closed-reason", argv: j("item", "field", "get", "9", "--name", "reason"), want: 0},
		isc{name: "fieldlist/open", argv: j("item", "field", "list", "1"), want: 0},
		isc{name: "fieldlist/closed", argv: j("item", "field", "list", "4"), want: 0},
	)
	both(fs("gitlab-milestone", "2", "milestone", "M07", 0, yes()))

	// ---- complete (shim)
	co := func(name, id string, want int, ch *bool, args ...string) isc {
		return isc{name: "complete/" + name, argv: j(append([]string{"item", "complete", id, "--commit", "abc1234"}, args...)...), want: want, changed: ch}
	}
	add(
		co("done-with-proof", "5", 0, yes()),
		co("done-proof-missing", "2", 4, nil),
		co("done-no-proof", "2", 0, yes(), "--no-proof"),
		co("done-note", "2", 0, yes(), "--no-proof", "--note", "a\nb"),
		co("done-clears-state-labels", "7", 0, yes(), "--no-proof"),
		co("dropped", "2", 0, yes(), "--reason", "dropped", "--note", "n"),
		co("handed-off", "6", 0, yes(), "--reason", "handed-off"),
		co("blocked", "2", 0, yes(), "--reason", "blocked", "--note", "waiting"),
		co("blocked-already", "8", 0, no(), "--reason", "blocked"),
		co("already-closed", "4", 0, no()),
		co("bad-reason", "2", 2, nil, "--reason", "nope"),
	)
	both(co("gitlab-done-proof", "5", 0, yes()))
	both(co("gitlab-dropped", "6", 0, yes(), "--reason", "dropped"))

	// ---- reopen / state (shim)
	for _, c := range []struct {
		n, id string
		ch    *bool
	}{{"closed", "4", yes()}, {"dropped", "9", yes()}, {"unblock", "8", yes()}, {"open-noop", "2", no()}} {
		add(isc{name: "reopen/" + c.n, argv: j("item", "reopen", c.id), want: 0, changed: c.ch})
	}
	both(isc{name: "reopen/gitlab", argv: j("item", "reopen", "9"), want: 0, changed: yes()})
	st := func(name, id, to string, want int, ch *bool) isc {
		return isc{name: "state/" + name, argv: j("item", "state", id, "--to", to), want: want, changed: ch}
	}
	add(
		st("in-progress", "2", "in-progress", 0, yes()),
		st("swap", "6", "needs-review", 0, yes()),
		st("changes", "7", "changes-requested", 0, yes()),
		st("none", "7", "none", 0, yes()),
		st("noop", "7", "needs-review", 0, no()),
		st("none-noop", "2", "none", 0, no()),
		st("bad-to", "2", "bogus", 2, nil),
	)
	both(st("gitlab-in-progress", "2", "in-progress", 0, yes()))

	// ---- claim / release (old helpers)
	cl := func(name, id, as string, want int, check func(*testing.T, envl, run, map[string]any)) isc {
		return isc{name: "claim/" + name, argv: j("item", "claim", id, "--as", as), old: []string{"hv-item-claim", id, "--as", as}, want: want, check: check}
	}
	won := func(t *testing.T, e envl, _ run, _ map[string]any) {
		eq(t, e, "data.changed", true)
		eq(t, e, "data.claimId", "me")
		eq(t, e, "data.type", "B")
	}
	add(
		cl("win", "2", "me", 0, won),
		cl("already-holder", "7", "me", 0, func(t *testing.T, e envl, _ run, _ map[string]any) { eq(t, e, "data.type", "T") }),
		cl("held-by-other", "6", "me", 4, func(t *testing.T, e envl, ref run, _ map[string]any) {
			// divergence 6: failure data the old helper has no way to send
			eq(t, e, "data.blockedBy", "claimed")
			eq(t, e, "data.changed", true)
			if !strings.Contains(ref.stderr, "claimed by other") {
				t.Errorf("old message does not name the holder: %s", ref.stderr)
			}
		}),
		cl("closed", "4", "me", 3, nil),
		cl("bad-as", "2", "a b", 2, nil),
		cl("empty-as", "2", "", 2, nil),
		cl("arrow-as", "2", "a-->b", 2, nil),
	)
	both(cl("gitlab-win", "2", "me", 0, won))
	rl := func(name, id, as string, want int, ch bool) isc {
		return isc{name: "release/" + name, argv: j("item", "release", id, "--as", as), old: []string{"hv-item-release", id, "--as", as}, want: want,
			check: func(t *testing.T, e envl, _ run, _ map[string]any) {
				if want == 0 {
					eq(t, e, "data.changed", ch)
				}
			}}
	}
	add(rl("match-last-claim", "6", "other", 0, true), rl("match-keeps-state", "7", "me", 0, true), rl("no-match", "6", "zzz", 0, false),
		rl("closed-item", "4", "me", 0, false), rl("bad-as", "6", "a b", 2, false))
	both(rl("gitlab-match", "6", "other", 0, true))

	// ---- show (old helper)
	showCheck := func(want map[string]any) func(*testing.T, envl, run, map[string]any) {
		return func(t *testing.T, e envl, ref run, _ map[string]any) {
			for k, v := range want {
				eq(t, e, "data."+k, v)
			}
			// the old text rows agree with data
			if !strings.Contains(ref.stdout, "comments: "+fmt.Sprint(len(at(e, "data.comments").([]any)))) {
				t.Errorf("comment count differs: %s", ref.stdout)
			}
		}
	}
	add(
		isc{name: "show/noted", argv: j("item", "show", "5"), old: []string{"hv-item-show", "5"}, want: 0, textSame: true,
			check: showCheck(map[string]any{"id": "5", "type": "B", "status": "open", "claimedBy": nil, "state": nil})},
		isc{name: "show/claimed", argv: j("item", "show", "6"), old: []string{"hv-item-show", "6"}, want: 0, textSame: true,
			check: showCheck(map[string]any{"id": "6", "type": "F", "claimedBy": "other", "state": "in-progress"})},
		isc{name: "show/milestone", argv: j("item", "show", "1"), old: []string{"hv-item-show", "1"}, want: 0, textSame: true,
			check: showCheck(map[string]any{"milestone": "M07"})},
		isc{name: "show/closed", argv: j("item", "show", "9"), old: []string{"hv-item-show", "9"}, want: 0, textSame: true,
			check: showCheck(map[string]any{"status": "closed"})},
		isc{name: "show/file-backend", file: true, remote: "none", argv: j("item", "show", "B01"), old: []string{"hv-item-show", "B01"}, want: 1,
			div: "read-only verb under the wrong backend: contract (#106) exit 1, old rc 2 maps to 4", refWant: 4},
	)
	both(isc{name: "show/noted", argv: j("item", "show", "5"), old: []string{"hv-item-show", "5"}, want: 0, textSame: true})

	// ---- ready (old helper)
	rdy := func(name, id string, want int, ready bool) isc {
		return isc{name: "ready/" + name, argv: j("item", "ready", id), old: []string{"hv-item-ready", id}, oldMap: readyMapIssue, want: want,
			check: func(t *testing.T, e envl, ref run, _ map[string]any) {
				if want == 3 {
					return
				}
				eq(t, e, "data.ready", ready)
				var got, old []string
				for _, r := range at(e, "data.reasons").([]any) {
					got = append(got, r.(string))
				}
				for _, l := range strings.Split(strings.TrimSpace(ref.stdout), "\n") {
					if l != "" {
						old = append(old, l)
					}
				}
				if !reflect.DeepEqual(got, old) {
					t.Errorf("reasons %q, old %q", got, old)
				}
			}}
	}
	add(rdy("criteria", "1", 0, true), rdy("design-note", "5", 0, true), rdy("not-ready", "10", 1, false), rdy("not-ready-bug", "2", 1, false))
	both(rdy("criteria", "1", 0, true))

	// ---- comment add / list (old helper)
	ca := func(name, id, kind, body string, want int) isc {
		return isc{name: "comment-add/" + name, argv: j("item", "comment", "add", id, "--kind", kind, "--body-file", "-"),
			old: []string{"hv-item-comment", id, "--kind", kind, "--body-file", "-"}, in: body, want: want,
			check: func(t *testing.T, e envl, ref run, _ map[string]any) {
				if want == 0 {
					eq(t, e, "data.commentId", strings.TrimSpace(ref.stdout))
					eq(t, e, "data.changed", true)
				}
			}}
	}
	add(
		ca("question", "2", "question", "Why?\nbecause\n", 0),
		ca("unicode", "5", "decision", "Café — ok ✓", 0),
		ca("empty", "2", "question", "  \n", 2),
		ca("bad-kind", "2", "bogus", "x", 2),
		ca("unknown", "99", "question", "x", 3),
		isc{name: "comment-add/milestone-tracker", argv: j("item", "comment", "add", "3", "--kind", "question", "--body-file", "-"),
			old: []string{"hv-item-comment", "3", "--kind", "question", "--body-file", "-"}, in: "x", want: 3,
			div: "7: old posts on a milestone tracker issue, Go resolves first", refWant: 0, skipDB: true},
	)
	both(ca("question", "2", "question", "Why?", 0))
	cll := func(name, id string, args []string, want int, oldArgs ...string) isc {
		return isc{name: "comment-list/" + name, argv: j(append([]string{"item", "comment", "list", id}, args...)...),
			old: append([]string{"hv-item-comment", id, "--list"}, oldArgs...), want: want, textSame: true}
	}
	add(cll("all", "5", nil, 0), cll("kind", "5", []string{"--kind", "question"}, 0, "--kind", "question"),
		cll("kind-empty", "5", []string{"--kind", "answer"}, 0, "--kind", "answer"), cll("none", "2", nil, 0),
		cll("bad-kind", "5", []string{"--kind", "bogus"}, 2, "--kind", "bogus"))

	// ---- note add / show / rm (old helper)
	nadd := func(name, id, kind, text string, want int, ch bool, env ...string) isc {
		return isc{name: "note-add/" + name, argv: j("item", "note", "add", id, "--kind", kind, "--body-file", "-"),
			old: []string{"hv-item-note", id, "--kind", kind, "--body-file", "-"}, in: text, env: env, want: want,
			check: func(t *testing.T, e envl, _ run, _ map[string]any) {
				if want == 0 {
					eq(t, e, "data.changed", ch)
				}
			}}
	}
	long := strings.Repeat("a line of the plan that is fairly long\n", 12)
	add(
		nadd("new-proof", "2", "proof", "## Proof\n- x · PASS · y\n", 0, true),
		nadd("edit-design", "5", "design", "new design\n", 0, true),
		nadd("identical", "5", "design", "the design\n", 0, false),
		nadd("unicode", "2", "plan", "Café — ✓\n", 0, true),
		nadd("split", "2", "plan", long, 0, true, "HV_NOTE_LIMIT=80"),
		nadd("shrink-parts", "11", "plan", "short", 0, true, "HV_NOTE_LIMIT=80"),
		nadd("grow-parts", "5", "design", long, 0, true, "HV_NOTE_LIMIT=80"),
		nadd("long-line", "2", "design", strings.Repeat("x", 300), 0, true, "HV_NOTE_LIMIT=80"),
		nadd("bad-kind", "2", "bogus", "x", 2, false),
		nadd("unknown", "99", "proof", "x", 3, false),
		isc{name: "note-add/empty-body", argv: j("item", "note", "add", "2", "--kind", "proof", "--body-file", "-"),
			old: []string{"hv-item-note", "2", "--kind", "proof", "--body-file", "-"}, in: "  \n", want: 2,
			div: "5: Go usage 2, old writes an empty note", refWant: 0, skipDB: true},
		isc{name: "note-add/file-backend", file: true, remote: "none", argv: j("item", "note", "add", "B01", "--kind", "proof", "--body-file", "-"),
			old: []string{"hv-item-note", "B01", "--kind", "proof", "--body-file", "-"}, in: "x", want: 4,
			div: "12: old crashes with a TypeError traceback on the file backend", refWant: 3},
	)
	both(nadd("new-proof", "2", "proof", "## Proof\n- x · PASS · y\n", 0, true))
	nshow := func(name, id, kind string, want int, exists bool, env ...string) isc {
		return isc{name: "note-show/" + name, argv: j("item", "note", "show", id, "--kind", kind),
			old: []string{"hv-item-note", id, "--kind", kind, "--show"}, want: want, env: env, textSame: true,
			check: func(t *testing.T, e envl, ref run, _ map[string]any) {
				if want != 0 {
					return
				}
				eq(t, e, "data.exists", exists)
				eq(t, e, "data.body", strings.TrimRight(ref.stdout, "\n"))
			}}
	}
	add(nshow("proof", "5", "proof", 0, true), nshow("design", "5", "design", 0, true), nshow("multipart-plan", "11", "plan", 0, true),
		nshow("absent", "2", "plan", 0, false), nshow("bad-kind", "2", "bogus", 2, false), nshow("file-backend", "B01", "design", 1, false),
		isc{name: "note-show/wrong-letter", argv: j("item", "note", "show", "F2", "--kind", "proof"),
			old: []string{"hv-item-note", "F2", "--kind", "proof", "--show"}, want: 3, div: "7: old ignores the type letter", refWant: 0})
	// file-backend scenarios need file:true; patch the two above. note show is
	// read-only, so the contract (#106) wants exit 1 where old rc 2 maps to 4.
	for i := range all {
		if strings.HasPrefix(all[i].name, "note-show/file-backend") {
			all[i].file, all[i].remote = true, "none"
			all[i].div, all[i].refWant = "read-only verb under the wrong backend: contract (#106) exit 1, old rc 2 maps to 4", 4
		}
	}
	both(nshow("proof", "5", "proof", 0, true))
	nrm := func(name, id, kind string, want int, ch bool) isc {
		return isc{name: "note-rm/" + name, argv: j("item", "note", "rm", id, "--kind", kind), old: []string{"hv-item-note", id, "--kind", kind, "--rm"}, want: want,
			check: func(t *testing.T, e envl, _ run, _ map[string]any) {
				if want == 0 {
					eq(t, e, "data.changed", ch)
				}
			}}
	}
	add(nrm("design", "5", "design", 0, true), nrm("multipart", "11", "plan", 0, true), nrm("absent", "2", "plan", 0, false),
		nrm("bad-kind", "2", "bogus", 2, false), nrm("unknown", "99", "plan", 3, false))
	both(nrm("design", "5", "design", 0, true))

	// ---- file backend: claim / release / state are no-ops
	fileOK := func(name string, argv, old []string, want int, key string, val any) isc {
		return isc{name: "file/" + name, file: true, remote: "none", argv: argv, old: old, want: want,
			check: func(t *testing.T, e envl, _ run, _ map[string]any) {
				if want == 0 {
					eq(t, e, key, val)
				}
			}}
	}
	add(
		fileOK("claim", j("item", "claim", "B01", "--as", "me"), []string{"hv-item-claim", "B01", "--as", "me"}, 0, "data.changed", false),
		fileOK("release", j("item", "release", "B01", "--as", "me"), []string{"hv-item-release", "B01", "--as", "me"}, 0, "data.changed", false),
		isc{name: "file/state", file: true, remote: "none", argv: j("item", "state", "B01", "--to", "in-progress"), want: 0},
		isc{name: "file/state-unknown", file: true, remote: "none", argv: j("item", "state", "B99", "--to", "none"), want: 3},
		isc{name: "file/claim-unknown", file: true, remote: "none", argv: j("item", "claim", "B99", "--as", "me"), old: []string{"hv-item-claim", "B99", "--as", "me"},
			want: 3, div: "8: old file backend claims silently", refWant: 0},
	)

	seen := map[string]bool{}
	for _, s := range all {
		if seen[s.name] {
			t.Fatalf("duplicate scenario %s", s.name)
		}
		seen[s.name] = true
	}
	t.Logf("%d scenarios", len(all))
	if len(all) < 150 {
		t.Fatalf("only %d scenarios", len(all))
	}
	for _, s := range all {
		s := s
		t.Run(s.name, s.exec)
	}
}
