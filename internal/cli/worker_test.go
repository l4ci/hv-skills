package cli

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
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
