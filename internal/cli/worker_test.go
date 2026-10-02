package cli

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/host"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

// hostTripwire puts failing herdr, tmux, gh and glab first on PATH for one
// test and clears the host env. This round runs inside herdr and tmux, so a
// test that reached a real one could kill live agents. The test fails if any
// tripwire was hit.
func hostTripwire(t *testing.T) {
	t.Helper()
	dir := t.TempDir()
	hit := filepath.Join(dir, "hit")
	for _, bin := range []string{"herdr", "tmux", "gh", "glab"} {
		script := fmt.Sprintf("#!/bin/sh\necho \"%s $*\" >> '%s'\nexit 99\n", bin, hit)
		if err := os.WriteFile(filepath.Join(dir, bin), []byte(script), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	// the gate's local merge commits as the caller; CI runners have no identity
	for k, v := range map[string]string{"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"} {
		t.Setenv(k, v)
	}
	for _, k := range []string{"TMUX", "TMUX_PANE", "HERDR_ENV", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID", "HERDR_SOCKET_PATH", "HV_ACCOUNT_USAGE_DIR"} {
		t.Setenv(k, "")
		os.Unsetenv(k)
	}
	t.Cleanup(func() {
		if b, err := os.ReadFile(hit); err == nil {
			t.Errorf("test reached a real host or forge binary:\n%s", b)
		}
	})
}

func workerProject(t *testing.T, cfg string) string {
	t.Helper()
	hostTripwire(t)
	dir := gitRepo(t)
	run := func(args ...string) {
		c := exec.Command("git", args...)
		c.Dir = dir
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v %s", args, err, out)
		}
	}
	run("branch", "-m", "main")
	os.WriteFile(filepath.Join(dir, ".gitignore"), []byte(".worktrees/\n"), 0o644)
	os.WriteFile(filepath.Join(dir, ".hv", "config.json"), []byte(cfg), 0o644)
	run("add", ".gitignore")
	run("-c", "user.email=a@b", "-c", "user.name=n", "commit", "-q", "-m", "ignore")
	return dir
}

func TestWorkerPoolVerbs(t *testing.T) {
	dir := workerProject(t, `{}`)

	code, _, errOut := hvIn(t, dir, "worker", "pool", "init", "--json")
	if code != 2 || !strings.Contains(errOut, "--slots must be a positive integer") {
		t.Fatalf("init without --slots: %d %s", code, errOut)
	}
	for _, bad := range []string{"0", "-1", "x", "1.5"} {
		if code, _, _ := hvIn(t, dir, "worker", "pool", "init", "--slots", bad); code != 2 {
			t.Errorf("--slots %s: exit %d, want 2", bad, code)
		}
	}
	code, out, _ := hvIn(t, dir, "worker", "pool", "init", "--slots", "2", "--base", "main", "--json")
	d := data(t, out)
	if code != 0 || d["session"] != "hv" || d["base"] != "main" || d["changed"] != true || len(d["slots"].([]any)) != 2 {
		t.Fatalf("init: %d %v", code, d)
	}
	slot := d["slots"].([]any)[0].(map[string]any)
	if _, has := slot["task"]; has {
		t.Errorf("null registry fields must be absent: %v", slot)
	}
	_, out, _ = hvIn(t, dir, "worker", "pool", "init", "--slots", "2", "--base", "main", "--json")
	if data(t, out)["changed"] != false {
		t.Error("idempotent re-init must report changed=false")
	}
	if code, _, errOut := hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "nope"); code != 3 {
		t.Errorf("unknown base: %d %s", code, errOut)
	}

	code, out, _ = hvIn(t, dir, "worker", "pool", "list")
	if code != 0 || len(strings.Split(strings.TrimSpace(out), "\n")) != 2 || !strings.HasPrefix(out, "w1\tidle\thv-worker/w1\t") {
		t.Errorf("list text: %d %q", code, out)
	}

	if code, _, _ := hvIn(t, dir, "worker", "pool", "reap"); code != 2 {
		t.Errorf("reap with nothing: %d", code)
	}
	if code, _, _ := hvIn(t, dir, "worker", "pool", "reap", "w1", "--all"); code != 2 {
		t.Errorf("reap with both: %d", code)
	}
	code, out, _ = hvIn(t, dir, "worker", "pool", "reap", "w1", "ghost", "--json")
	d = data(t, out)
	if code != 0 || d["changed"] != true || len(d["reaped"].([]any)) != 1 {
		t.Errorf("reap: %d %v", code, d)
	}
	code, out, _ = hvIn(t, dir, "worker", "pool", "reap", "ghost", "--json")
	if d = data(t, out); code != 0 || d["changed"] != false {
		t.Errorf("reap of an unknown slot is a no-op: %d %v", code, d)
	}
}

func TestWorkerResetVerb(t *testing.T) {
	dir := workerProject(t, `{}`)
	hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "main")
	wt := filepath.Join(dir, ".worktrees", "w1")

	code, out, _ := hvIn(t, dir, "worker", "reset", "w1", "--check-only", "--json")
	if d := data(t, out); code != 0 || d["clean"] != true || d["changed"] != false {
		t.Fatalf("check-only on a clean slot: %d %v", code, d)
	}

	os.WriteFile(filepath.Join(wt, "dirty.txt"), []byte("x"), 0o644)
	code, out, errOut := hvIn(t, dir, "worker", "reset", "w1", "--check-only", "--json")
	d := data(t, out)
	if code != 1 || d["clean"] != false || len(d["dirty"].([]any)) != 1 || !strings.Contains(errOut, "REFUSED w1") {
		t.Fatalf("check-only on a dirty slot: %d %v %s", code, d, errOut)
	}
	code, out, _ = hvIn(t, dir, "worker", "reset", "w1", "--task", "T1", "--json")
	if d = data(t, out); code != 4 || d["clean"] != false || d["changed"] != false {
		t.Fatalf("reset of a dirty slot: %d %v", code, d)
	}

	os.Remove(filepath.Join(wt, "dirty.txt"))
	code, out, _ = hvIn(t, dir, "worker", "reset", "w1", "--task", "T1", "--json")
	d = data(t, out)
	if code != 0 || d["branch"] != "hv-worker/w1-t1" || d["base"] != "main" || d["changed"] != true || d["sha"] == "" {
		t.Fatalf("reset: %d %v", code, d)
	}

	if code, _, _ := hvIn(t, dir, "worker", "reset", "ghost"); code != 3 {
		t.Errorf("unknown slot: %d", code)
	}
	if code, _, _ := hvIn(t, dir, "worker", "reset"); code != 2 {
		t.Errorf("no slot: %d", code)
	}
}

func TestWorkerAccountVerbs(t *testing.T) {
	cfg := `{"work":{"accounts":[{"name":"alpha","configDir":"/a"},{"name":"beta","configDir":"/b"}]}}`
	dir := workerProject(t, cfg)
	usage := t.TempDir()
	os.WriteFile(filepath.Join(usage, "alpha.json"), []byte(`{"five_hour":{"utilization":90,"resets_at":null},"seven_day":{"utilization":10,"resets_at":null}}`), 0o644)
	os.WriteFile(filepath.Join(usage, "beta.json"), []byte(`{"five_hour":{"utilization":20,"resets_at":null},"seven_day":{"utilization":10,"resets_at":null}}`), 0o644)
	t.Setenv("HV_ACCOUNT_USAGE_DIR", usage)

	code, out, _ := hvIn(t, dir, "worker", "account", "list", "--json")
	d := data(t, out)
	rows := d["accounts"].([]any)
	if code != 0 || len(rows) != 2 || rows[0].(map[string]any)["headroom"] != 10.0 || rows[1].(map[string]any)["verdict"] != "free" {
		t.Fatalf("list: %d %v", code, d)
	}
	if _, has := rows[0].(map[string]any)["resetsAt"]; has {
		t.Error("null fields must be absent")
	}
	code, out, _ = hvIn(t, dir, "worker", "account", "list")
	if code != 0 || !strings.Contains(out, "alpha        free      5h=90%   7d=10%") {
		t.Errorf("list text: %q", out)
	}

	code, out, _ = hvIn(t, dir, "worker", "account", "pick", "--json")
	if d = data(t, out); code != 0 || d["found"] != true || d["account"] != "beta" {
		t.Errorf("pick: %d %v", code, d)
	}
	code, out, _ = hvIn(t, dir, "worker", "account", "pick", "--exclude", "beta,alpha", "--json")
	if d = data(t, out); code != 1 || d["found"] != false {
		t.Errorf("pick with nothing left: %d %v", code, d)
	}

	hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "main")
	code, out, _ = hvIn(t, dir, "worker", "account", "assign", "w1", "--account", "alpha", "--json")
	if d = data(t, out); code != 0 || d["account"] != "alpha" || d["changed"] != true {
		t.Errorf("assign: %d %v", code, d)
	}
	code, out, _ = hvIn(t, dir, "worker", "account", "assign", "w1", "--account", "alpha", "--json")
	if d = data(t, out); code != 0 || d["changed"] != false {
		t.Errorf("assign again: %d %v", code, d)
	}
	if code, _, _ := hvIn(t, dir, "worker", "account", "assign", "w1", "--account", "ghost"); code != 3 {
		t.Errorf("unknown account: %d", code)
	}
}

// ── host verbs, with the host swapped for a fake ────────────────────────────

type cliHost struct {
	inSession bool
	sendErr   error
	calls     []string
}

func (h *cliHost) Name() string    { return "tmux" }
func (h *cliHost) Require() error  { return nil }
func (h *cliHost) InSession() bool { return h.inSession }
func (h *cliHost) Where() string   { return "main" }
func (h *cliHost) Spawn(_ context.Context, o host.SpawnOpts) (string, error) {
	h.calls = append(h.calls, "spawn")
	return "hv:" + o.Slot, nil
}
func (h *cliHost) Send(_ context.Context, slot, handle, file string) error {
	b, _ := os.ReadFile(file)
	h.calls = append(h.calls, "send:"+string(b))
	return h.sendErr
}
func (h *cliHost) Capture(context.Context, string, string, int) string { return "static\n" }
func (h *cliHost) Status(context.Context, string, string) string       { return "" }
func (h *cliHost) Kill(context.Context, string, string) error {
	h.calls = append(h.calls, "kill")
	return nil
}
func (h *cliHost) Notify(context.Context, string, string) {}

func useHost(t *testing.T, h host.Host) {
	t.Helper()
	old := workerEnv
	workerEnv = func() worker.Env {
		return worker.Env{NewHost: func(string) host.Host { return h }, Sleep: func(time.Duration) {}}
	}
	t.Cleanup(func() { workerEnv = old })
}

func TestWorkerDispatchVerb(t *testing.T) {
	dir := workerProject(t, `{}`)
	hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "main")
	h := &cliHost{inSession: true}
	useHost(t, h)
	brief := filepath.Join(t.TempDir(), "b.md")
	os.WriteFile(brief, []byte("hello\n"), 0o644)

	if code, _, _ := hvIn(t, dir, "worker", "dispatch", "w1"); code != 2 {
		t.Errorf("no --body-file: %d", code)
	}
	if code, _, _ := hvIn(t, dir, "worker", "dispatch", "w1", "--body-file", brief, "--round", "x"); code != 2 {
		t.Errorf("bad --round: %d", code)
	}
	code, out, _ := hvIn(t, dir, "worker", "dispatch", "w1", "--body-file", brief, "--task", "T1", "--round", "2", "--json")
	d := data(t, out)
	if code != 0 || d["slot"] != "w1" || d["handle"] != "hv:w1" || d["task"] != "T1" || d["round"] != 2.0 || d["relay"] != false || d["changed"] != true {
		t.Fatalf("dispatch: %d %v", code, d)
	}
	if got := strings.Join(h.calls, ","); got != "kill,spawn,send:--- ORCHESTRATOR (round 2) ---\nhello\n" {
		t.Errorf("calls = %q", got)
	}
	code, out, _ = hvIn(t, dir, "worker", "dispatch", "w1", "--body-file", brief, "--relay", "--json")
	if d = data(t, out); code != 0 || d["relay"] != true {
		t.Errorf("relay: %d %v", code, d)
	}

	// the contract's split: never submitted is retry (6), a dialog is unavailable (5)
	h.sendErr = host.ErrNotSubmitted
	if code, _, _ := hvIn(t, dir, "worker", "dispatch", "w1", "--body-file", brief, "--relay"); code != 6 {
		t.Errorf("never submitted: %d, want 6", code)
	}
	h.sendErr = host.ErrDialogOpen
	if code, _, _ := hvIn(t, dir, "worker", "dispatch", "w1", "--body-file", brief, "--relay"); code != 5 {
		t.Errorf("dialog open: %d, want 5", code)
	}
	if code, _, _ := hvIn(t, dir, "worker", "dispatch", "ghost", "--body-file", brief); code != 3 {
		t.Errorf("unknown slot: %d", code)
	}
}

func TestWorkerDispatchBodyFromStdin(t *testing.T) {
	dir := workerProject(t, `{}`)
	hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "main")
	h := &cliHost{inSession: true}
	useHost(t, h)
	old, _ := os.Getwd()
	os.Chdir(dir)
	defer os.Chdir(old)
	var so, se bytes.Buffer
	code := Main([]string{"worker", "dispatch", "w1", "--body-file", "-", "--task", "T1"}, strings.NewReader("from stdin\n"), &so, &se)
	if code != 0 || !strings.HasSuffix(strings.Join(h.calls, ","), "from stdin\n") {
		t.Errorf("exit %d calls %q err %s", code, h.calls, se.String())
	}
}

func TestWorkerPollVerb(t *testing.T) {
	dir := workerProject(t, `{}`)
	hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "main")
	useHost(t, &cliHost{inSession: true})
	code, out, _ := hvIn(t, dir, "worker", "poll", "--settle", "0", "--json")
	d := data(t, out)
	rows := d["slots"].([]any)
	if code != 0 || len(rows) != 1 || rows[0].(map[string]any)["state"] != "idle" || d["changed"] != false {
		t.Fatalf("poll: %d %v", code, d)
	}
	if code, _, _ := hvIn(t, dir, "worker", "poll", "ghost"); code != 3 {
		t.Errorf("unknown slot: %d", code)
	}

	fx := filepath.Join(t.TempDir(), "pane.txt")
	os.WriteFile(fx, []byte("HV-BLOCKED w1: which?\n"), 0o644)
	t.Setenv("HV_TEST_POLL_FIXTURE", fx)
	t.Setenv("HV_TEST_POLL_STATUS", "working")
	code, out, _ = hvIn(t, dir, "worker", "poll", "--json")
	rows = data(t, out)["slots"].([]any)
	if code != 0 || rows[0].(map[string]any)["state"] != "blocked" || rows[0].(map[string]any)["name"] != "fixture" {
		t.Errorf("fixture mode: %d %v", code, rows)
	}
	t.Setenv("HV_TEST_POLL_FIXTURE", "/no/such")
	if code, _, _ := hvIn(t, dir, "worker", "poll"); code != 2 {
		t.Errorf("missing fixture: %d", code)
	}
}

func TestWorkerSessionVerbs(t *testing.T) {
	dir := workerProject(t, `{}`)
	h := &cliHost{}
	useHost(t, h)
	code, out, _ := hvIn(t, dir, "worker", "session", "check", "--json")
	if d := data(t, out); code != 1 || d["inside"] != false {
		t.Errorf("outside: %d %v", code, d)
	}
	h.inSession = true
	code, out, _ = hvIn(t, dir, "worker", "session", "check", "--json")
	if d := data(t, out); code != 0 || d["inside"] != true || d["where"] != "main" {
		t.Errorf("inside: %d %v", code, d)
	}
	code, out, _ = hvIn(t, dir, "worker", "session", "ensure", "--json")
	if d := data(t, out); code != 0 || d["handedOff"] != false || d["changed"] != false || d["inside"] != true {
		t.Errorf("ensure inside: %d %v", code, d)
	}
}

func TestWorkerGateVerb(t *testing.T) {
	dir := workerProject(t, `{"refactor":{"verifyCommands":["test -f feature.txt"]}}`)
	hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "main")
	wt := filepath.Join(dir, ".worktrees", "w1")
	git := func(d string, args ...string) {
		t.Helper()
		c := exec.Command("git", append([]string{"-c", "user.email=a@b", "-c", "user.name=n"}, args...)...)
		c.Dir = d
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v %s", args, err, out)
		}
	}
	if code, _, _ := hvIn(t, dir, "worker", "gate", "w1"); code != 2 {
		t.Errorf("no --base: %d", code)
	}
	if code, _, _ := hvIn(t, dir, "worker", "gate", "ghost", "--base", "main"); code != 3 {
		t.Errorf("unknown slot: %d", code)
	}
	os.WriteFile(filepath.Join(wt, "feature.txt"), []byte("f"), 0o644)
	git(wt, "add", "feature.txt")
	git(wt, "commit", "-q", "-m", "feature")

	code, out, _ := hvIn(t, dir, "worker", "gate", "w1", "--base", "main", "--check-only", "--json")
	d := data(t, out)
	if code != 0 || d["verdict"] != "fresh" || d["changed"] != false || d["branch"] != "hv-worker/w1" {
		t.Fatalf("check-only: %d %v", code, d)
	}

	// main moves: the slot is stale, a verdict on exit 1 with the answer in data
	os.WriteFile(filepath.Join(dir, "main.txt"), []byte("m"), 0o644)
	git(dir, "add", "main.txt")
	git(dir, "commit", "-q", "-m", "main moves")
	code, out, errOut := hvIn(t, dir, "worker", "gate", "w1", "--base", "main", "--json")
	if d = data(t, out); code != 1 || d["verdict"] != "stale" || d["changed"] != false || !strings.Contains(errOut, "STALE w1") {
		t.Fatalf("stale: %d %v %s", code, d, errOut)
	}
	if code, _, _ := hvIn(t, dir, "worker", "gate", "w1", "--base", "nope"); code != 3 {
		t.Errorf("unknown base: %d", code)
	}

	git(wt, "merge", "-q", "main", "-m", "sync")
	code, out, _ = hvIn(t, dir, "worker", "gate", "w1", "--base", "main", "--json")
	d = data(t, out)
	if code != 0 || d["verdict"] != "pass" || d["changed"] != true || d["verified"].([]any)[0] != "test -f feature.txt" || d["verifySkipped"] != false || d["sha"] == nil {
		t.Fatalf("pass: %d %v", code, d)
	}
	if _, err := os.Stat(filepath.Join(dir, "feature.txt")); err != nil {
		t.Error("the slot's work is not on main")
	}
	// the merge commit is on main but not on the slot's branch, so it is stale again
	if code, _, _ = hvIn(t, dir, "worker", "gate", "w1", "--base", "main"); code != 1 {
		t.Errorf("re-gating a merged slot: %d, want 1 (stale)", code)
	}
}

func TestWorkerDispatchRefusalEnvelopeCarriesData(t *testing.T) {
	dir := workerProject(t, `{"work":{"workerCommand":"claude --resume"}}`)
	hvIn(t, dir, "worker", "pool", "init", "--slots", "1", "--base", "main")
	useHost(t, &cliHost{inSession: true})
	brief := filepath.Join(t.TempDir(), "b.md")
	os.WriteFile(brief, []byte("x"), 0o644)
	code, out, _ := hvIn(t, dir, "worker", "dispatch", "w1", "--body-file", brief, "--task", "T1", "--json")
	d := data(t, out)
	if code != 4 || d["blockedBy"] != "resume-flag" || d["changed"] != false {
		t.Errorf("%d %s", code, out)
	}
}
