package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

func initRun(t *testing.T, dir string, args ...string) (int, *jsonx.Object, string) {
	t.Helper()
	wd, _ := os.Getwd() // -C changes the process directory; put it back
	t.Cleanup(func() { os.Chdir(wd) })
	code, out, errOut := stubRun(append([]string{"-C", dir}, append(args, "--json")...)...)
	v, err := jsonx.Decode([]byte(out))
	if err != nil {
		t.Fatalf("%v: %v\n%s", args, err, out)
	}
	return code, v.(*jsonx.Object), errOut
}

func initData(env *jsonx.Object) *jsonx.Object {
	d, _ := env.Get("data")
	o, _ := d.(*jsonx.Object)
	return o
}

func TestInitVerbSeedsAndRunsBlocks(t *testing.T) {
	dir := t.TempDir()
	code, env, _ := initRun(t, dir, "init")
	d := initData(env)
	if code != 0 || d == nil {
		t.Fatalf("exit %d %v", code, env)
	}
	if ch, _ := d.Get("changed"); ch != true {
		t.Error("first run not changed")
	}
	blocks, _ := d.Get("blocks")
	list, _ := blocks.([]any)
	var keys []string
	for _, b := range list {
		k, _ := b.(*jsonx.Object).Get("key")
		keys = append(keys, k.(string))
	}
	if strings.Join(keys, ",") != "skills,knowledge,milestones,decisions,map,qa" {
		t.Errorf("blocks %v", keys)
	}
	if _, ok := d.Get("instructions"); !ok {
		t.Error("no instructions")
	}
	for _, f := range []string{"AGENTS.md", "CLAUDE.md", ".hv/BACKLOG.md"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Error(err)
		}
	}
	// a second run changes nothing
	_, env, _ = initRun(t, dir, "init")
	if ch, _ := initData(env).Get("changed"); ch != false {
		t.Errorf("second run changed: %v", env)
	}
}

func TestInitNoBlocksSeedsOnly(t *testing.T) {
	dir := t.TempDir()
	code, env, _ := initRun(t, dir, "init", "--no-blocks")
	d := initData(env)
	if code != 0 {
		t.Fatal(env)
	}
	if _, ok := d.Get("blocks"); ok {
		t.Error("blocks present")
	}
	if _, ok := d.Get("instructions"); ok {
		t.Error("instructions present")
	}
	if _, err := os.Stat(filepath.Join(dir, "AGENTS.md")); err == nil {
		t.Error("AGENTS.md written")
	}
}

func TestInitWarnsAboutAStaleMirror(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(filepath.Join(dir, ".hv", "bin"), 0o755)
	os.WriteFile(filepath.Join(dir, ".hv", "bin", "hv-x"), nil, 0o755)
	_, env, errOut := initRun(t, dir, "init", "--no-blocks")
	w, _ := initData(env).Get("warnings")
	if l, _ := w.([]any); len(l) != 1 || !strings.Contains(l[0].(string), ".hv/bin") || !strings.Contains(errOut, "warning") {
		t.Errorf("warnings %v / %q", w, errOut)
	}
	if _, err := os.Stat(filepath.Join(dir, ".hv", "bin")); err == nil {
		t.Error(".hv/bin survived")
	}
}

func TestInitCorruptCountersExits70(t *testing.T) {
	dir := t.TempDir()
	os.MkdirAll(filepath.Join(dir, ".hv"), 0o755)
	os.WriteFile(filepath.Join(dir, ".hv", "counters.json"), []byte("{oops"), 0o644)
	if code, _, _ := initRun(t, dir, "init", "--no-blocks"); code != 70 {
		t.Errorf("exit %d", code)
	}
}

func TestInitCheckVerb(t *testing.T) {
	dir := t.TempDir()
	code, env, _ := initRun(t, dir, "init", "check")
	d := initData(env)
	if code != 1 {
		t.Errorf("uninitialized exit %d", code)
	}
	if d == nil {
		t.Fatalf("no data on failure: %v", env)
	}
	if v, _ := d.Get("initialized"); v != false {
		t.Errorf("%v", d)
	}
	initRun(t, dir, "init", "--no-blocks")
	code, env, _ = initRun(t, dir, "init", "check")
	if v, _ := initData(env).Get("initialized"); code != 0 || v != true {
		t.Errorf("exit %d %v", code, env)
	}
}

func TestInitCheckDoesNotWalkUp(t *testing.T) {
	root := t.TempDir()
	initRun(t, root, "init", "--no-blocks")
	sub := filepath.Join(root, "sub")
	os.MkdirAll(sub, 0o755)
	if code, _, _ := initRun(t, sub, "init", "check"); code != 1 {
		t.Errorf("walked up: exit %d", code)
	}
}

func TestInitCheckWarnsOnVersionDrift(t *testing.T) {
	dir := t.TempDir()
	initRun(t, dir, "init", "--no-blocks")
	old := installedVersionFn
	installedVersionFn = func() string { return "5.0.0" }
	t.Cleanup(func() { installedVersionFn = old })
	os.WriteFile(filepath.Join(dir, ".hv", "config.json"), []byte(`{"hvSkills":{"version":"4.9.0"}}`), 0o644)
	code, env, errOut := initRun(t, dir, "init", "check")
	w, _ := env.Get("warnings")
	if l, _ := w.([]any); code != 0 || len(l) != 1 || !strings.Contains(l[0].(string), "project at 4.9.0, binary at 5.0.0") || !strings.Contains(errOut, "drift") {
		t.Errorf("exit %d warnings %v stderr %q", code, w, errOut)
	}
}
