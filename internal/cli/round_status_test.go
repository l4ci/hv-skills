package cli

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/host"
	"github.com/l4ci/hv-skills/v5/internal/round"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

// roundFixture is a project with one parked and one working worktree, and a
// roundEnv with a fake host and no forge, so nothing reaches herdr or gh.
func roundFixture(t *testing.T, agents []host.Agent) string {
	t.Helper()
	root := gitRepo(t)
	for name, br := range map[string]string{"ben": "park/ben", "dana": "dana/58-x"} {
		c := exec.Command("git", "worktree", "add", "-q", "-b", br, filepath.Join(root, ".worktrees", name), "HEAD")
		c.Dir = root
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("%v %s", err, out)
		}
	}
	saved := roundEnv
	t.Cleanup(func() { roundEnv = saved })
	roundEnv = func(context.Context, string) round.Env {
		e := round.Env{Git: worker.ExecGit, Base: "feat/x", ForgeErr: "fake: no forge"}
		if agents != nil {
			e.Snapshot = func(context.Context) ([]host.Agent, error) { return agents, nil }
			e.HostName = "herdr"
		}
		return e
	}
	return root
}

func TestRoundStatusAndReconcile(t *testing.T) {
	root := roundFixture(t, []host.Agent{})
	// Re-point the fake at the real worktree path now that root is known.
	roundEnv = func(context.Context, string) round.Env {
		return round.Env{Git: worker.ExecGit, Base: "feat/x", HostName: "herdr", ForgeErr: "fake: no forge",
			Snapshot: func(context.Context) ([]host.Agent, error) {
				return []host.Agent{{Tab: "w1:t1", Name: "dana", Cwd: filepath.Join(root, ".worktrees", "dana"), Status: "working"}}, nil
			}}
	}
	code, out, _ := hvIn(t, root, "--json", "round", "status")
	if code != 0 {
		t.Fatalf("status exit %d: %s", code, out)
	}
	d := data(t, out)
	rows := d["slots"].([]any)
	if len(rows) != 2 || d["host"] != "herdr" || !reflect.DeepEqual(d["unavailable"], []any{"forge"}) {
		t.Fatalf("data = %v", d)
	}
	dana := rows[1].(map[string]any)
	if dana["name"] != "dana" || dana["issue"] != "58" || dana["hostState"] != "working" || dana["registered"] != false {
		t.Errorf("dana = %v", dana)
	}

	code, out, _ = hvIn(t, root, "--json", "round", "reconcile")
	d = data(t, out)
	if code != 0 || d["changed"] != false || d["clean"] != false || len(d["drift"].([]any)) != 2 {
		t.Fatalf("reconcile = %d %v", code, d)
	}
	if _, err := os.Stat(worker.RegistryPath(root)); err == nil {
		t.Fatal("reconcile without --apply wrote the registry")
	}

	code, out, _ = hvIn(t, root, "--json", "round", "reconcile", "--apply")
	d = data(t, out)
	if code != 0 || d["changed"] != true || len(d["repaired"].([]any)) != 2 || len(d["drift"].([]any)) != 0 {
		t.Fatalf("reconcile --apply = %d %v", code, d)
	}
	if s := worker.LoadRegistry(root).Slot("dana"); s == nil || worker.Str(s, "task") != "58" {
		t.Errorf("registry = %v", s)
	}
}

func TestRoundVerbsRejectRepoAndArgs(t *testing.T) {
	root := roundFixture(t, nil)
	for _, args := range [][]string{{"round", "status", "x"}, {"round", "reconcile", "x"}, {"--repo", "a", "round", "status"}} {
		if code, _, _ := hvIn(t, root, args...); code != 2 {
			t.Errorf("%v exit %d, want 2", args, code)
		}
	}
}
