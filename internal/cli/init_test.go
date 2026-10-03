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

// initCode runs hv with -C and returns the exit code, restoring the cwd.
func initCode(t *testing.T, args ...string) int {
	t.Helper()
	wd, _ := os.Getwd()
	t.Cleanup(func() { os.Chdir(wd) })
	code, _, _ := stubRun(args...)
	return code
}

// codexRoot builds a fake skills root: two skills and a non-skill directory.
func codexRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	for _, n := range []string{"hv-alpha", "hv-beta"} {
		os.MkdirAll(filepath.Join(root, n), 0o755)
		os.WriteFile(filepath.Join(root, n, "SKILL.md"), []byte("# "+n+"\n"), 0o644)
	}
	os.MkdirAll(filepath.Join(root, "hv-nothing"), 0o755)
	os.MkdirAll(filepath.Join(root, "references"), 0o755)
	return root
}

func codexLinks(d *jsonx.Object) map[string]string {
	c, _ := d.Get("codex")
	l, _ := c.(*jsonx.Object).Get("links")
	out := map[string]string{}
	for _, e := range l.([]any) {
		o := e.(*jsonx.Object)
		n, _ := o.Get("name")
		s, _ := o.Get("status")
		out[n.(string)] = s.(string)
	}
	return out
}

func TestInitCodexLinksAndIsIdempotent(t *testing.T) {
	skills, dir := codexRoot(t), t.TempDir()
	code, env, _ := initRun(t, dir, "init", "--no-blocks", "--codex", "--skills-dir", skills)
	d := initData(env)
	if code != 0 {
		t.Fatal(env)
	}
	if got := codexLinks(d); len(got) != 2 || got["hv-alpha"] != "created" || got["hv-beta"] != "created" {
		t.Errorf("links %v", got)
	}
	for _, n := range []string{"hv-alpha", "hv-beta"} {
		tgt, err := os.Readlink(filepath.Join(dir, ".agents", "skills", n))
		if err != nil || tgt != filepath.Join(skills, n) {
			t.Errorf("%s -> %q %v", n, tgt, err)
		}
	}
	if _, err := os.Lstat(filepath.Join(dir, ".agents", "skills", "hv-nothing")); err == nil {
		t.Error("linked a non-skill dir")
	}
	cr, _ := d.Get("created")
	for _, p := range cr.([]any) {
		if strings.HasPrefix(p.(string), ".agents") {
			t.Errorf("created lists %v", p)
		}
	}
	gi, _ := os.ReadFile(filepath.Join(dir, ".gitignore"))
	if strings.Count(string(gi), ".agents/skills/hv-*") != 1 {
		t.Errorf("gitignore:\n%s", gi)
	}
	_, env, _ = initRun(t, dir, "init", "--no-blocks", "--codex", "--skills-dir", skills)
	d = initData(env)
	if ch, _ := d.Get("changed"); ch != false {
		t.Errorf("second run changed: %v", env)
	}
	if got := codexLinks(d); got["hv-alpha"] != "unchanged" || got["hv-beta"] != "unchanged" {
		t.Errorf("links %v", got)
	}
	gi2, _ := os.ReadFile(filepath.Join(dir, ".gitignore"))
	if string(gi2) != string(gi) {
		t.Error("gitignore rewritten")
	}
}

func TestInitCodexSkipsExistingPaths(t *testing.T) {
	skills, dir := codexRoot(t), t.TempDir()
	os.MkdirAll(filepath.Join(dir, ".agents", "skills", "hv-alpha"), 0o755)
	os.Symlink("/elsewhere", filepath.Join(dir, ".agents", "skills", "hv-beta"))
	code, env, _ := initRun(t, dir, "init", "--no-blocks", "--codex", "--skills-dir", skills)
	d := initData(env)
	if code != 0 {
		t.Fatal(env)
	}
	if got := codexLinks(d); got["hv-alpha"] != "skipped" || got["hv-beta"] != "skipped" {
		t.Errorf("links %v", got)
	}
	if tgt, _ := os.Readlink(filepath.Join(dir, ".agents", "skills", "hv-beta")); tgt != "/elsewhere" {
		t.Errorf("overwrote link: %q", tgt)
	}
	if w, _ := d.Get("warnings"); w == nil {
		t.Error("no warnings")
	}
}

func TestInitCodexInvalidRootWritesNothing(t *testing.T) {
	dir := t.TempDir()
	code := initCode(t, "-C", dir, "init", "--codex", "--skills-dir", t.TempDir())
	if code != 3 {
		t.Errorf("exit %d", code)
	}
	if ents, _ := os.ReadDir(dir); len(ents) != 0 {
		t.Errorf("wrote %v", ents)
	}
}

func TestInitCodexDerivesRootFromBinary(t *testing.T) {
	skills, dir := codexRoot(t), t.TempDir()
	os.MkdirAll(filepath.Join(skills, "bin"), 0o755)
	old := executablePath
	executablePath = func() (string, error) { return filepath.Join(skills, "bin", "hv"), nil }
	t.Cleanup(func() { executablePath = old })
	// EvalSymlinks needs the file to exist
	os.WriteFile(filepath.Join(skills, "bin", "hv"), nil, 0o755)
	code, env, _ := initRun(t, dir, "init", "--no-blocks", "--codex")
	if code != 0 || codexLinks(initData(env))["hv-alpha"] != "created" {
		t.Errorf("exit %d %v", code, env)
	}
	// a binary with no skills beside it: exit 3
	executablePath = func() (string, error) { return filepath.Join(t.TempDir(), "bin", "hv"), nil }
	if code := initCode(t, "-C", t.TempDir(), "init", "--codex"); code != 3 {
		t.Errorf("exit %d", code)
	}
}

func TestInitSkillsDirNeedsCodex(t *testing.T) {
	dir := t.TempDir()
	code := initCode(t, "-C", dir, "init", "--skills-dir", codexRoot(t))
	if code != 2 {
		t.Errorf("exit %d", code)
	}
	if ents, _ := os.ReadDir(dir); len(ents) != 0 {
		t.Errorf("wrote %v", ents)
	}
}

func TestInitDefaultHasNoCodex(t *testing.T) {
	dir := t.TempDir()
	_, env, _ := initRun(t, dir, "init", "--no-blocks")
	if _, ok := initData(env).Get("codex"); ok {
		t.Error("codex in data")
	}
	if _, err := os.Lstat(filepath.Join(dir, ".agents")); err == nil {
		t.Error(".agents created")
	}
	gi, _ := os.ReadFile(filepath.Join(dir, ".gitignore"))
	if strings.Contains(string(gi), ".agents") {
		t.Error("gitignore mentions .agents")
	}
}
