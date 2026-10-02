package worker

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

var tripwireHit string

// TestMain puts tripwire herdr, tmux, gh and glab first on PATH and clears the
// host env. This round runs inside herdr and tmux, where a stray `herdr tab
// close` or `tmux kill-window` kills live agents: any test that reaches a real
// host binary fails the whole run.
func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "worker-tripwire")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	tripwireHit = filepath.Join(dir, "hit")
	for _, bin := range []string{"herdr", "tmux", "gh", "glab"} {
		script := fmt.Sprintf("#!/bin/sh\necho \"$0 $*\" >> '%s'\necho 'tripwire: real %s reached from a test' >&2\nexit 99\n", tripwireHit, bin)
		if err := os.WriteFile(filepath.Join(dir, bin), []byte(script), 0o755); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	os.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, k := range []string{"TMUX", "TMUX_PANE", "HERDR_ENV", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID", "HERDR_SOCKET_PATH", "HV_ACCOUNT_USAGE_DIR"} {
		os.Unsetenv(k)
	}
	code := m.Run()
	if b, err := os.ReadFile(tripwireHit); err == nil {
		fmt.Fprintf(os.Stderr, "FAIL: tests exec'd a real host or forge binary from PATH:\n%s", b)
		code = 1
	}
	os.RemoveAll(dir)
	os.Exit(code)
}

// ── fixtures shared by the parity tests ─────────────────────────────────────

func binDir(t *testing.T) string {
	t.Helper()
	d, err := filepath.Abs("../../bin")
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func sh(t *testing.T, dir string, name string, args ...string) string {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@t", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@t")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %v in %s: %v\n%s", name, args, dir, err, out)
	}
	return strings.TrimSpace(string(out))
}

// newProject makes a git project with one commit on main, a gitignored
// .worktrees/ and the given .hv/config.json. The path is symlink-resolved.
func newProject(t *testing.T, config string) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	sh(t, dir, "git", "init", "-q", "-b", "main", ".")
	os.MkdirAll(filepath.Join(dir, ".hv"), 0o755)
	os.WriteFile(filepath.Join(dir, ".gitignore"), []byte(".worktrees/\n"), 0o644)
	os.WriteFile(filepath.Join(dir, "seed.txt"), []byte("seed\n"), 0o644)
	os.WriteFile(filepath.Join(dir, ".hv", "config.json"), []byte(config), 0o644)
	sh(t, dir, "git", "add", ".gitignore", "seed.txt")
	sh(t, dir, "git", "commit", "-q", "-m", "seed")
	return dir
}

type oldResult struct {
	Stdout, Stderr string
	Code           int
}

// runOld runs a bin/ helper in dir with a clean host environment.
func runOld(t *testing.T, dir string, env []string, helper string, args ...string) oldResult {
	t.Helper()
	cmd := exec.Command(filepath.Join(binDir(t), helper), args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), env...)
	var out, errb bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errb
	err := cmd.Run()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if err != nil {
		t.Fatalf("%s: %v", helper, err)
	}
	return oldResult{out.String(), errb.String(), code}
}

// registry returns workers.json with the project path replaced by ROOT, so two
// projects in different temp dirs compare byte for byte.
func registry(t *testing.T, dir string) string {
	t.Helper()
	b, err := os.ReadFile(RegistryPath(dir))
	if err != nil {
		t.Fatal(err)
	}
	return strings.ReplaceAll(string(b), dir, "ROOT")
}

func mustEqual(t *testing.T, what, old, got string) {
	t.Helper()
	if old != got {
		t.Errorf("%s differs from the old helper\n--- old\n%s\n--- go\n%s", what, old, got)
	}
}

var bg = context.Background()

func TestTripwireCatchesRealHostBinary(t *testing.T) {
	out, err := exec.Command("herdr", "tab", "close", "x").CombinedOutput()
	if err == nil || !strings.Contains(string(out), "tripwire") {
		t.Fatalf("herdr on PATH is not the tripwire: %s", out)
	}
	os.Remove(tripwireHit) // hit on purpose
}
