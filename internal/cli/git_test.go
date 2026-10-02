package cli

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
)

// gitT runs git in dir and fails the test on error.
func gitT(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.email=t@x", "-c", "user.name=t", "-c", "init.defaultBranch=main"}, args...)...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v in %s: %v\n%s", args, dir, err, out)
	}
	return strings.TrimSpace(string(out))
}

// newRepo makes a repo in dir/name with one commit on branch.
func newRepo(t *testing.T, dir, name, branch string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.MkdirAll(p, 0o755); err != nil {
		t.Fatal(err)
	}
	gitT(t, p, "init", "-q", "-b", branch)
	gitT(t, p, "commit", "-q", "--allow-empty", "-m", "init")
	return p
}

func write(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

// umbrella builds root/.hv with repos.json registering svc and web (both
// repos on main) and a ghost entry whose directory does not exist.
func umbrella(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	newRepo(t, root, "svc", "main")
	newRepo(t, root, "web", "main")
	write(t, filepath.Join(root, ".hv", "config.json"), `{}`)
	write(t, filepath.Join(root, ".hv", "repos.json"),
		`{"repos":[{"name":"svc","path":"svc"},{"name":"web","path":"web"},{"name":"ghost","path":"ghost"}]}`)
	return root
}

type gitCase struct {
	name string
	dir  string
	args []string
	code int
	data map[string]any // compared key by key against the envelope
	// old helper run on the same scenario while bin/ has it: rc and stdout.
	oldArgs []string
	oldRC   int
	oldOut  string
}

func runGitCases(t *testing.T, helper string, cases []gitCase) {
	t.Helper()
	_, file, _, _ := runtime.Caller(0)
	bin := filepath.Join(filepath.Dir(file), "..", "..", "bin", helper)
	_, err := os.Stat(bin)
	haveOld := err == nil
	for _, c := range cases {
		o := trRun(t, c.dir, "", append(append([]string{}, c.args...), "--json")...)
		if o.code != c.code {
			t.Errorf("%s: exit %d, want %d\n%s%s", c.name, o.code, c.code, o.stdout, o.stderr)
			continue
		}
		env := envelope(t, o.stdout)
		data, _ := env["data"].(map[string]any)
		for k, want := range c.data {
			if got := data[k]; !reflect.DeepEqual(got, want) {
				t.Errorf("%s: data.%s = %#v, want %#v", c.name, k, got, want)
			}
		}
		if c.data != nil && len(data) != len(c.data) {
			t.Errorf("%s: data %v has keys beyond %v", c.name, data, c.data)
		}
		if !haveOld || c.oldArgs == nil {
			continue
		}
		cmd := exec.Command("bash", append([]string{bin}, c.oldArgs...)...)
		cmd.Dir = c.dir
		out, _ := cmd.Output()
		rc := cmd.ProcessState.ExitCode()
		if rc != c.oldRC || strings.TrimSpace(string(out)) != c.oldOut {
			t.Errorf("%s: old %s gave rc %d %q; the case says rc %d %q", c.name, helper, rc, out, c.oldRC, c.oldOut)
		}
	}
}

func TestGitBase(t *testing.T) {
	d := t.TempDir()
	main := newRepo(t, d, "main", "main")
	master := newRepo(t, d, "master", "master")
	dev := newRepo(t, d, "dev", "dev")
	write(t, filepath.Join(dev, ".hv", "config.json"), `{"git":{"baseBranch":"dev"}}`)
	stale := newRepo(t, d, "stale", "main")
	write(t, filepath.Join(stale, ".hv", "config.json"), `{"git":{"baseBranch":"gone"}}`)
	fresh := filepath.Join(d, "fresh")
	os.Mkdir(fresh, 0o755)
	gitT(t, fresh, "init", "-q")
	remote := newRepo(t, d, "remote", "develop")
	gitT(t, remote, "update-ref", "refs/remotes/origin/develop", "HEAD")
	gitT(t, remote, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/develop")
	gitT(t, remote, "branch", "-m", "develop", "work")

	u := umbrella(t)
	gitT(t, filepath.Join(u, "svc"), "branch", "-m", "main", "trunk")
	// A stray .hv/ in a registered sub-repo masks its config.
	masked := filepath.Join(u, "web")
	gitT(t, masked, "branch", "dev")
	write(t, filepath.Join(masked, ".hv", "config.json"), `{"git":{"baseBranch":"dev"}}`)

	b := func(s string) map[string]any { return map[string]any{"base": s} }
	runGitCases(t, "hv-base-branch", []gitCase{
		{name: "main", dir: main, args: []string{"git", "base"}, data: b("main"), oldArgs: []string{}, oldOut: "main"},
		{name: "master", dir: master, args: []string{"git", "base"}, data: b("master"), oldArgs: []string{}, oldOut: "master"},
		{name: "configured", dir: dev, args: []string{"git", "base"}, data: b("dev"), oldArgs: []string{}, oldOut: "dev"},
		{name: "configured missing", dir: stale, args: []string{"git", "base"}, data: b("main"), oldArgs: []string{}, oldOut: "main"},
		{name: "origin/HEAD", dir: remote, args: []string{"git", "base"}, data: b("develop"), oldArgs: []string{}, oldOut: "develop"},
		{name: "none", dir: fresh, args: []string{"git", "base"}, code: 3, oldArgs: []string{}, oldRC: 1},
		{name: "umbrella root", dir: u, args: []string{"git", "base"}, code: 2, oldArgs: []string{}, oldRC: 1},
		{name: "--repo", dir: u, args: []string{"git", "base", "--repo", "svc"}, data: b("trunk"), oldArgs: nil},
		{name: "masked", dir: masked, args: []string{"git", "base"}, data: b("main"), oldArgs: []string{}, oldOut: "main"},
	})
}

func TestGitGuardClean(t *testing.T) {
	d := t.TempDir()
	clean := newRepo(t, d, "clean", "main")
	dirty := newRepo(t, d, "dirty", "main")
	write(t, filepath.Join(dirty, "f"), "x")
	fresh := filepath.Join(d, "fresh")
	os.Mkdir(fresh, 0o755)
	gitT(t, fresh, "init", "-q")
	write(t, filepath.Join(fresh, "f"), "x")
	plain := filepath.Join(d, "plain")
	os.Mkdir(plain, 0o755)

	u := umbrella(t)
	write(t, filepath.Join(u, "web", "f"), "x")

	res := func(clean, green bool, dirty ...string) map[string]any {
		ds := []any{}
		for _, x := range dirty {
			ds = append(ds, x)
		}
		return map[string]any{"clean": clean, "greenfield": green, "dirtyRepos": ds}
	}
	runGitCases(t, "hv-guard-clean", []gitCase{
		{name: "clean", dir: clean, args: []string{"git", "guard", "clean"}, data: res(true, false), oldArgs: []string{}},
		{name: "dirty", dir: dirty, args: []string{"git", "guard", "clean"}, code: 1, data: res(false, false), oldArgs: []string{}, oldRC: 1},
		{name: "fresh", dir: fresh, args: []string{"git", "guard", "clean"}, code: 1, data: res(false, true), oldArgs: []string{}, oldRC: 1},
		{name: "not a repo", dir: plain, args: []string{"git", "guard", "clean"}, code: 3, oldArgs: []string{}, oldRC: 2},
		{name: "umbrella", dir: u, args: []string{"git", "guard", "clean", "--context", "/hv-work"}, code: 1,
			data: res(false, false, "web", "ghost (not a git repo at ghost)"), oldArgs: []string{"/hv-work"}, oldRC: 1},
		{name: "umbrella --repo clean", dir: u, args: []string{"git", "guard", "clean", "--repo", "svc"}, data: res(true, false)},
		{name: "umbrella --repo dirty", dir: u, args: []string{"git", "guard", "clean", "--repo", "web"}, code: 1, data: res(false, false)},
	})
	o := trRun(t, dirty, "", "git", "guard", "clean", "--context", "/hv-ship")
	if !strings.Contains(o.stderr, "before running /hv-ship") {
		t.Errorf("--context not in the message: %q", o.stderr)
	}
}

func TestGitGuardFeatureBranch(t *testing.T) {
	d := t.TempDir()
	feat := newRepo(t, d, "feat", "main")
	gitT(t, feat, "switch", "-q", "-c", "ben/1-x")
	onMain := newRepo(t, d, "onmain", "main")
	detached := newRepo(t, d, "detached", "main")
	gitT(t, detached, "checkout", "-q", "--detach")
	fresh := filepath.Join(d, "fresh")
	os.Mkdir(fresh, 0o755)
	gitT(t, fresh, "init", "-q", "-b", "trunk")
	u := umbrella(t)

	runGitCases(t, "hv-guard-feature-branch", []gitCase{
		{name: "feature", dir: feat, args: []string{"git", "guard", "feature-branch"},
			data: map[string]any{"feature": true, "branch": "ben/1-x", "base": "main"}, oldArgs: []string{}},
		{name: "on base", dir: onMain, args: []string{"git", "guard", "feature-branch"}, code: 1,
			data: map[string]any{"feature": false, "branch": "main", "base": "main", "reason": "base"}, oldArgs: []string{}, oldRC: 1},
		{name: "named base", dir: feat, args: []string{"git", "guard", "feature-branch", "main"}, code: 1,
			data: map[string]any{"feature": false, "branch": "main", "base": "main", "reason": "base"}, oldArgs: []string{"main"}, oldRC: 1},
		{name: "detached", dir: detached, args: []string{"git", "guard", "feature-branch"}, code: 1,
			data: map[string]any{"feature": false, "reason": "detached"}, oldArgs: []string{}, oldRC: 1},
		{name: "explicit HEAD", dir: feat, args: []string{"git", "guard", "feature-branch", "HEAD"}, code: 1,
			data: map[string]any{"feature": false, "reason": "detached"}, oldArgs: []string{"HEAD"}, oldRC: 1},
		{name: "no base, conventional name", dir: fresh, args: []string{"git", "guard", "feature-branch", "trunk"}, code: 1,
			data: map[string]any{"feature": false, "branch": "trunk", "reason": "base"}, oldArgs: []string{"trunk"}, oldRC: 1},
		{name: "no base, other name", dir: fresh, args: []string{"git", "guard", "feature-branch", "x"},
			data: map[string]any{"feature": true, "branch": "x"}, oldArgs: []string{"x"}},
		{name: "umbrella root", dir: u, args: []string{"git", "guard", "feature-branch"}, code: 2, oldArgs: []string{}, oldRC: 1},
		{name: "--repo", dir: u, args: []string{"git", "guard", "feature-branch", "--repo", "svc"}, code: 1,
			data: map[string]any{"feature": false, "branch": "main", "base": "main", "reason": "base"}},
	})
}

func TestGitBranch(t *testing.T) {
	u := umbrella(t)
	svc, web := filepath.Join(u, "svc"), filepath.Join(u, "web")
	gitT(t, web, "branch", "taken")
	list := func(xs ...string) []any {
		out := []any{}
		for _, x := range xs {
			out = append(out, x)
		}
		return out
	}
	runGitCases(t, "hv-multi-branch-create", []gitCase{
		{name: "collision", dir: u, args: []string{"git", "branch", "taken", "--repos", "svc,web"}, code: 4,
			data: map[string]any{"branch": "taken", "repos": list("svc", "web"), "changed": false}},
		{name: "unknown", dir: u, args: []string{"git", "branch", "x", "--repos", "svc,nope"}, code: 3,
			oldArgs: []string{"--branch", "x", "--repos", "svc,nope"}, oldRC: 1},
		{name: "spaces", dir: u, args: []string{"git", "branch", "x", "--repos", "svc, web"}, code: 2},
		{name: "empty entry", dir: u, args: []string{"git", "branch", "x", "--repos", "svc,"}, code: 2},
		{name: "no repos", dir: u, args: []string{"git", "branch", "x"}, code: 2},
		{name: "no name", dir: u, args: []string{"git", "branch", "--repos", "svc"}, code: 2},
		{name: "git refuses", dir: u, args: []string{"git", "branch", "bad..name", "--repos", "svc"}, code: 5},
		{name: "create", dir: u, args: []string{"git", "branch", "feat/x", "--repos", "svc,web"},
			data: map[string]any{"branch": "feat/x", "repos": list("svc", "web"), "changed": true}},
	})
	if gitT(t, svc, "branch", "--list", "taken") != "" {
		t.Error("a collision must create nothing anywhere")
	}
	for _, r := range []string{svc, web} {
		if gitT(t, r, "branch", "--list", "feat/x") == "" || gitT(t, r, "rev-parse", "--abbrev-ref", "HEAD") != "main" {
			t.Errorf("%s: branch missing or HEAD moved", r)
		}
	}
}

func TestGitWorktreePath(t *testing.T) {
	u := umbrella(t)
	real, _ := filepath.EvalSymlinks(u)
	want := real + "/.claude/worktrees/svc/feat/x"
	runGitCases(t, "hv-worktree-path", []gitCase{
		{name: "path", dir: u, args: []string{"git", "worktree-path", "--repo", "svc", "feat/x"},
			data: map[string]any{"path": want}, oldArgs: []string{"--repo", "svc", "feat/x"}, oldOut: want},
		{name: "from a sub-repo", dir: filepath.Join(u, "svc"), args: []string{"git", "worktree-path", "--repo", "svc", "feat/x"},
			data: map[string]any{"path": want}, oldArgs: []string{"--repo", "svc", "feat/x"}, oldOut: want},
		{name: "no --repo", dir: u, args: []string{"git", "worktree-path", "feat/x"}, code: 2, oldArgs: []string{"feat/x"}, oldRC: 1},
		{name: "unknown repo", dir: u, args: []string{"git", "worktree-path", "--repo", "nope", "feat/x"}, code: 3},
		{name: "no branch", dir: u, args: []string{"git", "worktree-path", "--repo", "svc"}, code: 2},
	})
}
