package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
)

const reviewBacklog = `# Backlog

## Bugs

- **[B01] [P1] Fix the parser.** Detail: x
- **[B03] [P2] no period here**

## Features

- **[F02] [Major] Add the thing.** Related: [B01]

## Completed

- ~~**[T05] [P3] Old task.** Done 2025-01-02 [` + "`abc1234`" + `]~~
`

// reviewFeature builds a repo on main with a backlog and a feature branch
// "feat/x" carrying commits that cite items, and files that trip the
// scaffolding scan across two files and several hunks.
func reviewFeature(t *testing.T, repo string) {
	t.Helper()
	var body strings.Builder
	for i := 1; i <= 30; i++ {
		body.WriteString("line " + string(rune('a'+i%26)) + "\n")
	}
	write(t, filepath.Join(repo, "a.txt"), body.String())
	write(t, filepath.Join(repo, "b.txt"), "one\ntwo\n")
	write(t, filepath.Join(repo, "crlf.txt"), "x\r\ny\r\n")
	gitT(t, repo, "add", "a.txt", "b.txt", "crlf.txt")
	gitT(t, repo, "commit", "-q", "-m", "base files")
	gitT(t, repo, "checkout", "-q", "-b", "feat/x")

	lines := strings.Split(strings.TrimSuffix(body.String(), "\n"), "\n")
	lines[1] = "Task 12 is in flight"
	lines[20] = "a Placeholder here"
	lines = append(lines, "caféTask 3 stays unmatched", "tasks 5 no", "not yet wired up", "NOT YET WIRED")
	write(t, filepath.Join(repo, "a.txt"), strings.Join(lines, "\n")+"\n")
	write(t, filepath.Join(repo, "b.txt"), "one\nadded later\ntwo\n")
	write(t, filepath.Join(repo, "crlf.txt"), "x\r\ny\r\nz placeholder\r\n")
	write(t, filepath.Join(repo, "café.txt"), "task 1\n")
	gitT(t, repo, "add", "a.txt", "b.txt", "crlf.txt", "café.txt")
	gitT(t, repo, "commit", "-q", "-m", "Do work [B01] and [F02]", "-m", "Also [T05], [B03] and [B99].")
	write(t, filepath.Join(repo, "c.txt"), "extra\n")
	gitT(t, repo, "add", "c.txt")
	gitT(t, repo, "commit", "-q", "-m", "More [B01]")
	gitT(t, repo, "branch", "empty", "main")
	gitT(t, repo, "checkout", "-q", "feat/x")
}

// reviewProject is a plain repo (with .hv/BACKLOG.md) and an umbrella whose
// svc sub-repo has the same branches.
func reviewProject(t *testing.T) (plain, umb string) {
	t.Helper()
	plain = newRepo(t, t.TempDir(), "proj", "main")
	write(t, filepath.Join(plain, ".hv", "BACKLOG.md"), reviewBacklog)
	reviewFeature(t, plain)
	umb = umbrella(t)
	write(t, filepath.Join(umb, ".hv", "BACKLOG.md"), reviewBacklog)
	reviewFeature(t, filepath.Join(umb, "svc"))
	return plain, umb
}

func reviewRoot() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(file), "..", "..")
}

// reviewShim runs the old helpers through the test shim.
func reviewShim(t *testing.T, dir string, args ...string) (int, map[string]any) {
	t.Helper()
	root := reviewRoot()
	cmd := exec.Command("python3", append([]string{filepath.Join(root, "test", "hv-shim"), "--json"}, args...)...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "HV_SHIM_HELPERS="+filepath.Join(root, "bin"))
	var out bytes.Buffer
	cmd.Stdout = &out
	_ = cmd.Run()
	var env map[string]any
	if err := json.Unmarshal(out.Bytes(), &env); err != nil {
		t.Fatalf("shim %v: %v\n%s", args, err, out.String())
	}
	return cmd.ProcessState.ExitCode(), env
}

// reviewBoth runs a verb through the shim and the Go binary; exit codes must
// agree and, on success, the data too.
func reviewBoth(t *testing.T, name, dir string, args ...string) map[string]any {
	t.Helper()
	oc, oenv := reviewShim(t, dir, args...)
	o := trRun(t, dir, "", append(append([]string{}, args...), "--json")...)
	if o.code != oc {
		t.Fatalf("%s: go exit %d, old exit %d\n%s%s", name, o.code, oc, o.stdout, o.stderr)
	}
	env := envelope(t, o.stdout)
	if oc != 0 {
		if env["data"] != nil {
			t.Errorf("%s: failure carries data %v", name, env["data"])
		}
		return nil
	}
	if !reflect.DeepEqual(env["data"], oenv["data"]) {
		t.Errorf("%s: data differs\ngo:  %v\nold: %v", name, env["data"], oenv["data"])
	}
	return env["data"].(map[string]any)
}

func TestReviewScopeParity(t *testing.T) {
	plain, umb := reviewProject(t)
	data := reviewBoth(t, "plain", plain, "review", "scope", "feat/x")
	if data["commitCount"] != 2.0 {
		t.Errorf("commitCount %v", data["commitCount"])
	}
	intents := data["intents"].([]any)
	if len(intents) != 4 {
		t.Fatalf("intents %v", intents)
	}
	if b03 := intents[3].(map[string]any); b03["id"] != "B03" || b03["title"] != nil {
		t.Errorf("a bullet without a title must give null: %v", b03)
	}
	reviewBoth(t, "current branch", plain, "review", "scope")
	reviewBoth(t, "umbrella --repo", umb, "review", "scope", "--repo", "svc", "feat/x")
	reviewBoth(t, "umbrella no repo", umb, "review", "scope", "feat/x")
	reviewBoth(t, "missing", plain, "review", "scope", "nope")
	reviewBoth(t, "empty branch", plain, "review", "scope", "empty")
	for _, args := range [][]string{{"review", "scope", "main"}, {"review", "scope", "main", "--repo", "svc"}} {
		dir := plain
		if len(args) > 3 {
			dir = umb
		}
		o := trRun(t, dir, "", append(args, "--json")...)
		if o.code != 1 || !strings.Contains(o.stdout+o.stderr, "cannot review base branch 'main' against itself") {
			t.Errorf("%v: %d %s%s", args, o.code, o.stdout, o.stderr)
		}
		if e := envelope(t, o.stdout); e["data"] != nil {
			t.Errorf("base branch carries data: %v", e)
		}
	}
	if o := trRun(t, umb, "", "review", "scope", "feat/x"); o.code != 2 {
		t.Errorf("umbrella without --repo: exit %d", o.code)
	}
	if o := trRun(t, plain, "", "review", "scope", "nope"); o.code != 3 {
		t.Errorf("missing branch: exit %d", o.code)
	}
	if o := trRun(t, plain, "", "review", "scope", "feat/x"); o.code != 0 || !strings.Contains(o.stdout, "feat/x vs main") {
		t.Errorf("text mode: %d %q", o.code, o.stdout)
	}
}

func TestReviewBriefParity(t *testing.T) {
	plain, umb := reviewProject(t)
	root := reviewRoot()
	oldBrief := func(dir string, args ...string) (string, int) {
		cmd := exec.Command("bash", append([]string{filepath.Join(root, "bin", "hv-second-opinion-brief")}, args...)...)
		cmd.Dir = dir
		var out, er bytes.Buffer
		cmd.Stdout, cmd.Stderr = &out, &er
		_ = cmd.Run()
		if er.Len() > 0 {
			t.Logf("old brief stderr: %s", er.String())
		}
		return out.String(), cmd.ProcessState.ExitCode()
	}
	// The old helper's --repo form calls hv-review-scope from inside the
	// sub-repo, where repos.json is gone, so it fails; its in-repo run is the
	// same scenario.
	for _, c := range []struct {
		dir, oldDir string
		args        []string
	}{
		{plain, plain, []string{"review", "brief", "feat/x"}},
		{umb, filepath.Join(umb, "svc"), []string{"review", "brief", "--repo", "svc", "feat/x"}},
	} {
		oldArgs := []string{"feat/x"}
		want, rc := oldBrief(c.oldDir, oldArgs...)
		if rc != 0 {
			t.Fatalf("old brief rc %d", rc)
		}
		o := trRun(t, c.dir, "", c.args...)
		if o.code != 0 || o.stdout != want {
			t.Errorf("%v: text differs (exit %d)\n--- go\n%q\n--- old\n%q", c.args, o.code, o.stdout, want)
		}
		o = trRun(t, c.dir, "", append(append([]string{}, c.args...), "--json")...)
		data := envelope(t, o.stdout)["data"].(map[string]any)
		if data["brief"] != want || data["commitCount"] != 2.0 || data["base"] != "main" || data["branch"] != "feat/x" {
			t.Errorf("%v: data %v", c.args, data)
		}
		if len(data) != 4 {
			t.Errorf("keys %v", data)
		}
	}
	reviewBoth(t, "shim parity", plain, "review", "brief", "feat/x")
	reviewBoth(t, "shim current", plain, "review", "brief")
	reviewBoth(t, "missing", plain, "review", "brief", "nope")
	if o := trRun(t, umb, "", "review", "brief", "feat/x"); o.code != 2 {
		t.Errorf("umbrella without --repo: exit %d", o.code)
	}

	o := trRun(t, plain, "", "review", "brief", "main")
	if o.code != 1 || !strings.Contains(o.stderr, "cannot second-opinion base branch 'main' against itself") {
		t.Errorf("base: %d %s", o.code, o.stderr)
	}
	o = trRun(t, plain, "", "review", "brief", "empty")
	if o.code != 1 || !strings.Contains(o.stderr, "branch 'empty' has no commits beyond 'main'") {
		t.Errorf("empty: %d %s", o.code, o.stderr)
	}
	if _, rc := oldBrief(plain, "empty"); rc != 2 {
		t.Errorf("old helper rc %d, want 2 (the shim maps it to 1)", rc)
	}
	// A bullet without a title printed Python's None.
	if o := trRun(t, plain, "", "review", "brief", "feat/x"); !strings.Contains(o.stdout, "- [B03] None — ") {
		t.Errorf("missing None title line")
	}
}

func TestReviewScaffoldingParity(t *testing.T) {
	plain, umb := reviewProject(t)
	data := reviewBoth(t, "plain", plain, "review", "scaffolding", "feat/x")
	findings := data["findings"].([]any)
	if len(findings) < 6 {
		t.Fatalf("expected matches in several hunks and files: %v", findings)
	}
	files := map[string]bool{}
	for _, f := range findings {
		files[f.(map[string]any)["file"].(string)] = true
	}
	if !files["a.txt"] || !files["b.txt"] || !files["crlf.txt"] {
		t.Errorf("files %v", files)
	}
	reviewBoth(t, "explicit base", plain, "review", "scaffolding", "feat/x", "--base", "main")
	reviewBoth(t, "current branch", plain, "review", "scaffolding")
	reviewBoth(t, "umbrella --repo", umb, "review", "scaffolding", "--repo", "svc", "feat/x")
	reviewBoth(t, "umbrella no repo", umb, "review", "scaffolding", "feat/x")
	reviewBoth(t, "missing branch", plain, "review", "scaffolding", "nope")
	reviewBoth(t, "missing base", plain, "review", "scaffolding", "feat/x", "--base", "nope")
	reviewBoth(t, "no findings", plain, "review", "scaffolding", "empty")
	if d := reviewBoth(t, "empty", plain, "review", "scaffolding", "empty"); len(d["findings"].([]any)) != 0 {
		t.Errorf("empty branch: %v", d)
	}

	// Text mode is the old helper's stdout.
	cmd := exec.Command("bash", filepath.Join(reviewRoot(), "bin", "hv-review-scaffolding"), "main", "feat/x")
	cmd.Dir = plain
	want, _ := cmd.Output()
	o := trRun(t, plain, "", "review", "scaffolding", "feat/x")
	if o.code != 0 || o.stdout != string(want) {
		t.Errorf("text differs\n--- go\n%q\n--- old\n%q", o.stdout, want)
	}
	if o := trRun(t, umb, "", "review", "scaffolding", "feat/x"); o.code != 2 {
		t.Errorf("umbrella no repo: exit %d", o.code)
	}
	if o := trRun(t, plain, "", "review", "scaffolding", "nope"); o.code != 3 {
		t.Errorf("missing branch: exit %d", o.code)
	}
}

// TestReviewScaffoldingUnicode pins the one place the port differs from
// Python's regex by construction: Go's \b is ASCII-only, so the port spells
// the boundary out; the old helper's answer must still come out.
func TestReviewScaffoldingUnicode(t *testing.T) {
	plain, _ := reviewProject(t)
	var texts []string
	for _, f := range envelope(t, trRun(t, plain, "", "review", "scaffolding", "feat/x", "--json").stdout)["data"].(map[string]any)["findings"].([]any) {
		texts = append(texts, f.(map[string]any)["text"].(string))
	}
	for _, s := range texts {
		if strings.Contains(s, "éTask") || strings.Contains(s, "tasks 5") {
			t.Errorf("must not match %q", s)
		}
	}
}

func TestReviewQueueNotImplemented(t *testing.T) {
	plain, _ := reviewProject(t)
	if o := trRun(t, plain, "", "review", "queue"); o.code != 71 {
		t.Errorf("exit %d, want 71\n%s%s", o.code, o.stdout, o.stderr)
	}
}
