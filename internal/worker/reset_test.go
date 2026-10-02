package worker

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// pair builds two identical projects with one initialised slot: a for the old
// helper, b for the Go port.
func pair(t *testing.T) (a, b string) {
	t.Helper()
	a, b = newProject(t, `{}`), newProject(t, `{}`)
	runOld(t, a, nil, "hv-worker-pool", "init", "--slots", "1", "--base", "main")
	if _, err := goInit(t, b, InitOpts{Slots: 1, Base: "main"}); err != nil {
		t.Fatal(err)
	}
	return a, b
}

func wt(d string) string { return filepath.Join(d, ".worktrees", "w1") }

func both(t *testing.T, a, b string, f func(t *testing.T, d string)) {
	t.Helper()
	f(t, a)
	f(t, b)
}

func commitIn(t *testing.T, dir, file string) {
	t.Helper()
	os.WriteFile(filepath.Join(dir, file), []byte(file+"\n"), 0o644)
	sh(t, dir, "git", "add", file)
	sh(t, dir, "git", "commit", "-q", "-m", "add "+file)
}

// oldReset runs the old guard; goReset the port. Exit codes are compared
// through the contract's mapping: old 3 for held work is 4 (1 with --check-only).
func oldReset(t *testing.T, d string, args ...string) oldResult {
	return runOld(t, d, nil, "hv-worker-reset", append([]string{"--slot", "w1"}, args...)...)
}

func TestResetCleanSlotCutsTaskBranch(t *testing.T) {
	a, b := pair(t)
	r := oldReset(t, a, "--task", "T-7/Fix Me")
	if r.Code != 0 {
		t.Fatalf("old: %+v", r)
	}
	res, err := Env{}.Reset(b, "w1", "T-7/Fix Me", false)
	if err != nil {
		t.Fatal(err)
	}
	mustEqual(t, "workers.json", registry(t, a), registry(t, b))
	if res.Branch != "hv-worker/w1-t-7-fix-me" || !res.Changed || !res.Clean || res.Retained {
		t.Errorf("%+v", res)
	}
	if want := "reset: w1 on hv-worker/w1-t-7-fix-me at " + res.SHA + "\n"; r.Stdout != strings.Replace(want, res.SHA, strings.TrimSpace(r.Stdout[strings.LastIndex(r.Stdout, " ")+1:]), 1) {
		t.Errorf("old stdout %q", r.Stdout)
	}
	if want := sh(t, b, "git", "rev-parse", "--short", "main"); res.SHA != want {
		t.Errorf("sha = %s, want %s", res.SHA, want)
	}
	if got := sh(t, wt(b), "git", "symbolic-ref", "--short", "HEAD"); got != "hv-worker/w1-t-7-fix-me" {
		t.Errorf("worktree on %s", got)
	}
	if out := sh(t, b, "git", "branch", "--list", "hv-worker/w1"); out != "" {
		t.Errorf("old per-task branch not dropped: %s", out)
	}
}

func TestResetCheckOnlyChangesNothing(t *testing.T) {
	_, b := pair(t)
	before := registry(t, b)
	res, err := Env{}.Reset(b, "w1", "T1", true)
	if err != nil || !res.Clean || res.Changed || res.Branch != "" || res.SHA != "" {
		t.Fatalf("%+v %v", res, err)
	}
	mustEqual(t, "registry", before, registry(t, b))
	if got := sh(t, wt(b), "git", "symbolic-ref", "--short", "HEAD"); got != "hv-worker/w1" {
		t.Errorf("--check-only moved the worktree to %s", got)
	}
}

func TestResetRefusesDirtyWorktree(t *testing.T) {
	a, b := pair(t)
	both(t, a, b, func(t *testing.T, d string) {
		os.WriteFile(filepath.Join(wt(d), "untracked.txt"), []byte("x"), 0o644)
	})
	r := oldReset(t, a, "--task", "T2")
	if r.Code != 3 || !strings.Contains(r.Stderr, "REFUSED w1 — uncommitted changes") {
		t.Fatalf("old: %+v", r)
	}
	before := registry(t, b)
	res, err := Env{}.Reset(b, "w1", "T2", false)
	we, ok := err.(*Error)
	if !ok || we.Exit != ExitRefused || !strings.Contains(we.Message, "REFUSED w1 — uncommitted changes") {
		t.Fatalf("err = %v", err)
	}
	if res.Clean || res.Changed || len(res.Dirty) != 1 || res.Dirty[0] != "?? untracked.txt" || len(res.Unmerged) != 0 {
		t.Errorf("%+v", res)
	}
	if rd, _ := we.Data.(ResetResult); rd.Dirty == nil {
		t.Errorf("failure data missing: %#v", we.Data)
	}
	mustEqual(t, "registry", before, registry(t, b))
	// the same refusal is exit 1 under --check-only
	_, err = Env{}.Reset(b, "w1", "T2", true)
	if we, ok := err.(*Error); !ok || we.Exit != ExitFailed {
		t.Errorf("--check-only err = %v", err)
	}
}

func TestResetRefusesUnmergedCommits(t *testing.T) {
	a, b := pair(t)
	both(t, a, b, func(t *testing.T, d string) { commitIn(t, wt(d), "work.txt") })
	r := oldReset(t, a, "--task", "T3")
	if r.Code != 3 || !strings.Contains(r.Stderr, "REFUSED w1 — 1 commit(s) not on main") {
		t.Fatalf("old: %+v", r)
	}
	res, err := Env{}.Reset(b, "w1", "T3", false)
	we, ok := err.(*Error)
	if !ok || we.Exit != ExitRefused || !strings.Contains(we.Message, "REFUSED w1 — 1 commit(s) not on main") {
		t.Fatalf("err = %v", err)
	}
	if len(res.Unmerged) != 1 || !strings.HasSuffix(res.Unmerged[0], " add work.txt") || len(res.Dirty) != 0 {
		t.Errorf("%+v", res)
	}
}

// git cherry compares by patch: a cherry-picked merge counts as merged.
func TestResetTreatsACherryPickedCommitAsMerged(t *testing.T) {
	a, b := pair(t)
	both(t, a, b, func(t *testing.T, d string) {
		commitIn(t, wt(d), "work.txt")
		sha := sh(t, wt(d), "git", "rev-parse", "HEAD")
		sh(t, d, "git", "cherry-pick", sha)
	})
	if r := oldReset(t, a, "--check-only"); r.Code != 0 {
		t.Fatalf("old: %+v", r)
	}
	res, err := Env{}.Reset(b, "w1", "", true)
	if err != nil || !res.Clean {
		t.Errorf("%+v %v", res, err)
	}
}

func TestResetRetryKeepsTheTasksOwnWork(t *testing.T) {
	a, b := pair(t)
	both(t, a, b, func(t *testing.T, d string) {})
	if r := oldReset(t, a, "--task", "T4"); r.Code != 0 {
		t.Fatalf("old setup: %+v", r)
	}
	if _, err := (Env{}).Reset(b, "w1", "T4", false); err != nil {
		t.Fatal(err)
	}
	both(t, a, b, func(t *testing.T, d string) {
		os.WriteFile(filepath.Join(wt(d), "wip.txt"), []byte("wip"), 0o644)
		// dispatch records the task on the slot; the guard compares against it
		raw, _ := os.ReadFile(RegistryPath(d))
		os.WriteFile(RegistryPath(d), []byte(strings.Replace(string(raw), `"task": null`, `"task": "T4"`, 1)), 0o644)
	})
	r := oldReset(t, a, "--task", "T4")
	if r.Code != 0 || !strings.HasPrefix(r.Stdout, "retry: w1 keeps its work on hv-worker/w1-t4") {
		t.Fatalf("old: %+v", r)
	}
	before := registry(t, b)
	res, err := Env{}.Reset(b, "w1", "T4", false)
	if err != nil || !res.Retained || res.Changed || res.Clean || res.Branch != "hv-worker/w1-t4" {
		t.Fatalf("%+v %v", res, err)
	}
	mustEqual(t, "registry", before, registry(t, b))
	mustEqual(t, "registry vs old", registry(t, a), registry(t, b))
	if _, err := os.Stat(filepath.Join(wt(b), "wip.txt")); err != nil {
		t.Error("the WIP was dropped")
	}
	// a DIFFERENT task on the same dirty slot is still refused
	if _, err := (Env{}).Reset(b, "w1", "T5", false); err == nil {
		t.Error("a new task must not inherit the last task's WIP")
	}
}

func TestResetResolutionFailures(t *testing.T) {
	dir := newProject(t, `{}`)
	exit := func(err error) int {
		if we, ok := err.(*Error); ok {
			return we.Exit
		}
		return -1
	}
	_, err := Env{}.Reset(dir, "w1", "", false)
	if exit(err) != ExitResolution || !strings.Contains(err.Error(), "no worker pool") {
		t.Errorf("no registry: %v", err)
	}
	goInit(t, dir, InitOpts{Slots: 1, Base: "main"})
	if _, err = (Env{}).Reset(dir, "w9", "", false); exit(err) != ExitResolution || !strings.Contains(err.Error(), "slot 'w9' is not in the pool") {
		t.Errorf("unknown slot: %v", err)
	}
	sh(t, dir, "git", "branch", "-m", "main", "trunk")
	if _, err = (Env{}).Reset(dir, "w1", "", false); exit(err) != ExitResolution || !strings.Contains(err.Error(), "base 'main' does not exist") {
		t.Errorf("missing base: %v", err)
	}
	os.RemoveAll(wt(dir))
	if _, err = (Env{}).Reset(dir, "w1", "", false); exit(err) != ExitResolution || !strings.Contains(err.Error(), "worktree missing") {
		t.Errorf("missing worktree: %v", err)
	}
}

func TestBranchFor(t *testing.T) {
	for _, c := range []struct{ task, want string }{
		{"", "hv-worker/w1"},
		{"T-7", "hv-worker/w1-t-7"},
		{"F42 Add/Thing", "hv-worker/w1-f42-add-thing"},
		{"a.b_c-d", "hv-worker/w1-a.b_c-d"},
		{"ä", "hv-worker/w1---"}, // tr works bytewise: two bytes, two dashes
	} {
		if got := BranchFor("w1", c.task); got != c.want {
			t.Errorf("BranchFor(%q) = %q, want %q", c.task, got, c.want)
		}
	}
}

func TestBranchForMatchesTr(t *testing.T) {
	for _, task := range []string{"B07", "Fix: login (v2)", "x\ty", "ÄÖ-1"} {
		old := sh(t, t.TempDir(), "bash", "-c", `printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._\n-' '-'`, "_", task)
		if got := BranchFor("w1", task); got != "hv-worker/w1-"+old {
			t.Errorf("BranchFor(%q) = %q, tr gives %q", task, got, old)
		}
	}
}
