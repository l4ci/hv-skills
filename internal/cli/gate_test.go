package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/gate"
)

// gateConfig is base (a JSON object) with autonomy.level and the ship keys
// laid over it.
func gateConfig(t *testing.T, base, level string, ship map[string]any) string {
	t.Helper()
	cfg := map[string]any{}
	if base != "" {
		if err := json.Unmarshal([]byte(base), &cfg); err != nil {
			t.Fatal(err)
		}
	}
	cfg["autonomy"] = map[string]any{"level": level}
	if ship != nil {
		cfg["ship"] = ship
	}
	b, _ := json.Marshal(cfg)
	return string(b)
}

func gateAudit(t *testing.T, root string) []map[string]any {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, gate.AuditFile))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	var out []map[string]any
	for _, l := range strings.Split(strings.TrimRight(string(b), "\n"), "\n") {
		var m map[string]any
		if err := json.Unmarshal([]byte(l), &m); err != nil {
			t.Fatal(err)
		}
		out = append(out, m)
	}
	return out
}

var gateYes = []string{"--confirm", "--confirm-note", "Yes, go ahead"}

// gateCase is one gated verb: setup builds a fresh project at an autonomy
// level and returns its root, the args, the stdin and a check that nothing
// public happened yet.
type gateCase struct {
	gate  string
	verb  string
	setup func(t *testing.T, level string) (root string, args []string, stdin string, untouched func() bool)
}

// gateRemote makes origin a bare repo at the relative path
// github.com/fake/repo.git inside work: git treats it as a local path, and
// `hv release host` reads it as github.
func gateRemote(t *testing.T, work string) {
	t.Helper()
	gitT(t, work, "init", "-q", "--bare", "github.com/fake/repo.git")
	write(t, filepath.Join(work, ".git", "info", "exclude"), "github.com/\n")
	gitT(t, work, "remote", "add", "origin", "github.com/fake/repo.git")
}

func gateCases() []gateCase {
	tagged := func(t *testing.T, level string) string {
		work := newRepo(t, t.TempDir(), "proj", "main")
		write(t, filepath.Join(work, ".hv", "config.json"), gateConfig(t, "", level, nil))
		gateRemote(t, work)
		gitT(t, work, "tag", "-a", "v1.2.3", "-m", "v1.2.3")
		return work
	}
	onRemote := func(t *testing.T, work string) bool {
		return gitT(t, work, "ls-remote", "--tags", "origin", "refs/tags/v1.2.3") != ""
	}
	return []gateCase{
		{gate.TagPush, "release push", func(t *testing.T, level string) (string, []string, string, func() bool) {
			work := tagged(t, level)
			return work, []string{"release", "push", "1.2.3"}, "", func() bool { return !onRemote(t, work) }
		}},
		{gate.ReleasePublish, "release publish", func(t *testing.T, level string) (string, []string, string, func() bool) {
			work := tagged(t, level)
			gitT(t, work, "push", "-q", "origin", "main", "v1.2.3")
			f := &forge{answer: func(string, []string) (string, string, int) {
				return "https://github.com/fake/repo/releases/tag/v1.2.3\n", "", 0
			}}
			useForge(t, f)
			return work, []string{"release", "publish", "1.2.3", "--title", "v1.2.3 — x", "--body-file", "-"}, "notes",
				func() bool { return len(f.calls) == 0 }
		}},
		{gate.PublicFiling, "tracker suggest-upstream", func(t *testing.T, level string) (string, []string, string, func() bool) {
			root := trProject(t, gateConfig(t, "", level, nil))
			f := &forge{answer: func(string, []string) (string, string, int) {
				return "https://github.com/l4ci/hv-skills/issues/5\n", "", 0
			}}
			useForge(t, f)
			return root, []string{"tracker", "suggest-upstream", "--title", "T", "--body-file", "-"}, "body",
				func() bool { return len(f.calls) == 0 }
		}},
		{gate.MergeApproval, "ship merge", func(t *testing.T, level string) (string, []string, string, func() bool) {
			work := newRepo(t, t.TempDir(), "proj", "main")
			write(t, filepath.Join(work, ".hv", "config.json"), gateConfig(t, `{"backlog":{"backend":"file"}}`, level, map[string]any{"mergeApproval": "all"}))
			shipBranchOf(t, work, "hv/x", [3]string{"x.txt", "feat: x", ""})
			return work, []string{"ship", "merge", "hv/x", "--body-file", "-"}, "merge: x",
				func() bool { return gitT(t, work, "branch", "--list", "hv/x") != "" }
		}},
		{gate.MergeApproval, "ship pr-merge", func(t *testing.T, level string) (string, []string, string, func() bool) {
			f := a8Fixture()
			root := a8Project(t, f)
			write(t, filepath.Join(root, ".hv", "config.json"), gateConfig(t, issuesConfig, level, map[string]any{"mergeApproval": "all"}))
			return root, []string{"ship", "pr-merge", "10"}, "", func() bool { return len(f.merged) == 0 }
		}},
		{gate.MergeApproval, "worker gate", func(t *testing.T, level string) (string, []string, string, func() bool) {
			dir := workerProject(t, gateConfig(t, `{"refactor":{"verifyCommands":["test -f feature.txt"]}}`, level, map[string]any{"mergeApproval": "all"}))
			hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "main")
			wt := filepath.Join(dir, ".worktrees", "w1")
			write(t, filepath.Join(wt, "feature.txt"), "f")
			gitT(t, wt, "add", "feature.txt")
			gitT(t, wt, "commit", "-q", "-m", "feature")
			return dir, []string{"worker", "gate", "w1", "--base", "main"}, "", func() bool {
				_, err := os.Stat(filepath.Join(dir, "feature.txt"))
				return os.IsNotExist(err)
			}
		}},
	}
}

// TestGatedVerbsAtEveryAutonomyLevel is the B1 acceptance matrix: each gated
// verb exits 4 without --confirm at every autonomy level, changes nothing and
// audits nothing; with --confirm it acts and audits the quoted answer.
func TestGatedVerbsAtEveryAutonomyLevel(t *testing.T) {
	for _, level := range []string{"off", "auto", "loop"} {
		for _, c := range gateCases() {
			t.Run(level+"/"+c.verb, func(t *testing.T) {
				root, args, stdin, untouched := c.setup(t, level)
				o := trRun(t, root, stdin, append([]string{"--json"}, args...)...)
				d, _ := envelope(t, o.stdout)["data"].(map[string]any)
				if o.code != 4 || d["blockedBy"] != "manual gate" || d["gate"] != c.gate || d["changed"] != false {
					t.Fatalf("no confirm: %+v", o)
				}
				if !strings.Contains(o.stderr, "--confirm --confirm-note") {
					t.Errorf("hint missing: %s", o.stderr)
				}
				if !untouched() || gateAudit(t, root) != nil {
					t.Fatalf("a refusal acted or audited")
				}
				o = trRun(t, root, stdin, append(append([]string{"--json"}, args...), gateYes...)...)
				if o.code != 0 {
					t.Fatalf("confirmed: %+v", o)
				}
				if untouched() {
					t.Fatalf("confirmed but nothing happened")
				}
				a := gateAudit(t, root)
				if len(a) != 1 || a[0]["gate"] != c.gate || a[0]["verb"] != c.verb || a[0]["note"] != "Yes, go ahead" || a[0]["autonomy"] != level {
					t.Fatalf("audit %v", a)
				}
			})
		}
	}
}

func TestGatedVerbsRejectHalfAConfirmation(t *testing.T) {
	for _, c := range gateCases() {
		root, args, stdin, untouched := c.setup(t, "off")
		for _, half := range [][]string{{"--confirm"}, {"--confirm-note", "yes"}, {"--confirm", "--confirm-note", " "}} {
			if o := trRun(t, root, stdin, append(args, half...)...); o.code != 2 || !untouched() {
				t.Errorf("%s %v: %+v", c.verb, half, o)
			}
		}
	}
}

func TestMergeApprovalPaths(t *testing.T) {
	work := newRepo(t, t.TempDir(), "proj", "main")
	write(t, filepath.Join(work, ".hv", "config.json"), gateConfig(t, `{"backlog":{"backend":"file"}}`, "loop",
		map[string]any{"mergeApproval": "paths", "mergeApprovalPaths": []any{"hv-release", "*.md"}}))
	shipBranchOf(t, work, "hv/code", [3]string{"main.go", "feat: code", ""})
	shipBranchOf(t, work, "hv/skill", [3]string{"hv-release/SKILL.md", "docs: skill", ""})

	// unlisted paths merge without approval, and nothing is audited
	if o := trRun(t, work, "merge: code", "ship", "merge", "hv/code", "--body-file", "-"); o.code != 0 || gateAudit(t, work) != nil {
		t.Fatalf("unlisted: %+v", o)
	}
	o := trRun(t, work, "merge: skill", "--json", "ship", "merge", "hv/skill", "--body-file", "-")
	d, _ := envelope(t, o.stdout)["data"].(map[string]any)
	if o.code != 4 || !reflect.DeepEqual(d["paths"], []any{"hv-release/SKILL.md"}) {
		t.Fatalf("listed: %+v", o)
	}
	if o := trRun(t, work, "merge: skill", append([]string{"ship", "merge", "hv/skill", "--body-file", "-"}, gateYes...)...); o.code != 0 {
		t.Fatalf("listed, confirmed: %+v", o)
	}

	// pr-merge reads the PR's files from the forge
	f := a8Fixture()
	f.files = map[int][]string{10: {"src/a.go"}, 11: {"README.md"}}
	root := a8Project(t, f)
	write(t, filepath.Join(root, ".hv", "config.json"), gateConfig(t, issuesConfig, "loop",
		map[string]any{"mergeApproval": "paths", "mergeApprovalPaths": []any{"*.md"}}))
	if code, _, msg := a8Run(t, root, "ship", "pr-merge", "10"); code != 0 {
		t.Fatalf("pr 10: %d %s", code, msg)
	}
	code, data, _ := a8Run(t, root, "ship", "pr-merge", "11")
	if code != 4 || data["pr"] != float64(11) || !reflect.DeepEqual(data["paths"], []any{"README.md"}) || !reflect.DeepEqual(f.merged, []int{10}) {
		t.Fatalf("pr 11: %d %v merged %v", code, data, f.merged)
	}
	// the gate runs before the proof check, so a refusal records nothing
	if is := f.Fake.Issues[1]; strings.Contains(strings.Join(is.Labels, ","), "changes-requested") {
		t.Fatalf("issue 2 labelled on a gate refusal: %v", is.Labels)
	}
}

func TestMergeApprovalBadMode(t *testing.T) {
	work := newRepo(t, t.TempDir(), "proj", "main")
	write(t, filepath.Join(work, ".hv", "config.json"), `{"ship":{"mergeApproval":"sometimes"}}`)
	shipBranchOf(t, work, "hv/x", [3]string{"x.txt", "feat: x", ""})
	if o := trRun(t, work, "merge: x", "ship", "merge", "hv/x", "--body-file", "-"); o.code != 2 || !strings.Contains(o.stderr, "ship.mergeApproval") {
		t.Fatalf("%+v", o)
	}
}

func TestWorkerGateApprovalRequiredVerdict(t *testing.T) {
	c := gateCases()[5]
	root, args, _, _ := c.setup(t, "auto")
	code, out, _ := hvIn(t, root, append([]string{"--json"}, args...)...)
	d := data(t, out)
	if code != 4 || d["verdict"] != "approval-required" || d["slot"] != "w1" || d["blockedBy"] != "manual gate" || d["changed"] != false {
		t.Fatalf("%d %v", code, d)
	}
	// --check-only never reaches the gate
	if code, _, _ := hvIn(t, root, append(args, "--check-only")...); code != 0 {
		t.Fatalf("check-only: %d", code)
	}
}

func TestReleasePublishHosts(t *testing.T) {
	// no recognized remote: nothing to publish, no approval needed
	work := newRepo(t, t.TempDir(), "proj", "main")
	write(t, filepath.Join(work, ".hv", "config.json"), "{}")
	o := trRun(t, work, "notes", "--json", "release", "publish", "1.0.0", "--title", "T", "--body-file", "-")
	d, _ := envelope(t, o.stdout)["data"].(map[string]any)
	if o.code != 0 || d["host"] != "none" || d["changed"] != false || !strings.Contains(o.stderr, "nothing published") {
		t.Fatalf("none: %+v", o)
	}
	// gitlab has no drafts
	gl := newRepo(t, t.TempDir(), "proj", "main")
	write(t, filepath.Join(gl, ".hv", "config.json"), "{}")
	gitT(t, gl, "remote", "add", "origin", "https://gitlab.com/fake/repo.git")
	if o := trRun(t, gl, "notes", append([]string{"release", "publish", "1.0.0", "--title", "T", "--body-file", "-", "--draft"}, gateYes...)...); o.code != 2 {
		t.Fatalf("gitlab draft: %+v", o)
	}
	// the tag must be on origin first
	gh := newRepo(t, t.TempDir(), "proj", "main")
	write(t, filepath.Join(gh, ".hv", "config.json"), "{}")
	gateRemote(t, gh)
	useForge(t, &forge{})
	if o := trRun(t, gh, "notes", append([]string{"release", "publish", "1.0.0", "--title", "T", "--body-file", "-"}, gateYes...)...); o.code != 3 {
		t.Fatalf("tag not on origin: %+v", o)
	}
	// github: gh release create with the notes file, the title and --draft
	gitT(t, gh, "tag", "v1.0.0")
	gitT(t, gh, "push", "-q", "origin", "v1.0.0")
	var notes string
	f := &forge{answer: func(_ string, args []string) (string, string, int) {
		for i, a := range args {
			if a == "--notes-file" {
				b, _ := os.ReadFile(args[i+1])
				notes = string(b)
			}
		}
		return "https://github.com/fake/repo/releases/tag/v1.0.0\n", "", 0
	}}
	useForge(t, f)
	o = trRun(t, gh, "## Fixed\n- x\n", append([]string{"--json", "release", "publish", "1.0.0", "--title", "v1.0.0 — x", "--body-file", "-", "--draft"}, gateYes...)...)
	d, _ = envelope(t, o.stdout)["data"].(map[string]any)
	if o.code != 0 || d["url"] != "https://github.com/fake/repo/releases/tag/v1.0.0" || d["draft"] != true || d["host"] != "github" {
		t.Fatalf("github: %+v", o)
	}
	if len(f.calls) != 1 || !strings.HasPrefix(f.calls[0], "gh release create v1.0.0 --title v1.0.0 — x --notes-file ") ||
		!strings.HasSuffix(f.calls[0], " --draft") || notes != "## Fixed\n- x\n" {
		t.Fatalf("calls %q notes %q", f.calls, notes)
	}
}

func TestReleasePushResolution(t *testing.T) {
	work := newRepo(t, t.TempDir(), "proj", "main")
	write(t, filepath.Join(work, ".hv", "config.json"), "{}")
	for _, c := range []struct {
		args []string
		code int
	}{
		{[]string{"1.2"}, 2},
		{[]string{"1.2.3"}, 3}, // no tag
	} {
		if o := trRun(t, work, "", append(append([]string{"release", "push"}, c.args...), gateYes...)...); o.code != c.code {
			t.Errorf("%v: %+v", c.args, o)
		}
	}
	gitT(t, work, "tag", "v1.2.3")
	if o := trRun(t, work, "", append([]string{"release", "push", "1.2.3"}, gateYes...)...); o.code != 3 || !strings.Contains(o.stderr, "origin") {
		t.Errorf("no origin: %+v", o)
	}
	gateRemote(t, work)
	if o := trRun(t, work, "", append([]string{"release", "push", "1.2.3", "--branch", "nope"}, gateYes...)...); o.code != 3 {
		t.Errorf("unknown branch: %+v", o)
	}
	o := trRun(t, work, "", append([]string{"--json", "release", "push", "1.2.3"}, gateYes...)...)
	d, _ := envelope(t, o.stdout)["data"].(map[string]any)
	if o.code != 0 || d["tag"] != "v1.2.3" || d["branch"] != "main" || d["remote"] != "origin" || d["changed"] != true {
		t.Fatalf("push: %+v", o)
	}
	if gitT(t, work, "ls-remote", "--heads", "origin", "main") == "" {
		t.Error("the branch was not pushed with the tag")
	}
}

func TestGateList(t *testing.T) {
	code, out, _ := hvIn(t, t.TempDir(), "--json", "gate", "list")
	var env struct {
		Data struct {
			Gates []struct {
				Name     string   `json:"name"`
				Enforced bool     `json:"enforced"`
				Verbs    []string `json:"verbs"`
				Skills   []string `json:"skills"`
				Creates  string   `json:"creates"`
			} `json:"gates"`
		} `json:"data"`
	}
	if err := json.Unmarshal([]byte(out), &env); err != nil || code != 0 || len(env.Data.Gates) != len(gate.Registry) {
		t.Fatalf("%d %s", code, out)
	}
	g := env.Data.Gates[3]
	if g.Name != gate.MergeApproval || !g.Enforced || !reflect.DeepEqual(g.Verbs, []string{"ship merge", "ship pr-merge", "worker gate"}) {
		t.Errorf("%+v", g)
	}
	if last := env.Data.Gates[len(env.Data.Gates)-1]; last.Enforced || last.Verbs == nil {
		t.Errorf("skill-only gate %+v (verbs must be [], not null)", last)
	}
}
