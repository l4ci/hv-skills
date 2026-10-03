package cli

import (
	"bytes"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func umbrellaFixture(t *testing.T, kids ...string) string {
	t.Helper()
	root, _ := filepath.EvalSymlinks(t.TempDir())
	for _, k := range kids {
		if err := os.MkdirAll(filepath.Join(root, k, ".git"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestInitUmbrellaList(t *testing.T) {
	root := umbrellaFixture(t, "web", "api")
	code, env, stderr := hvRun(t, "--json", "-C", root, "init", "umbrella", "--list")
	data := umbData(env)
	if code != 0 || data["root"] != root || data["isGitRepo"] != false || !reflect.DeepEqual(data["candidates"], []any{"api", "web"}) {
		t.Fatalf("code=%d env=%v stderr=%s", code, env, stderr)
	}
	if _, err := os.Stat(filepath.Join(root, ".hv")); err == nil {
		t.Fatal("--list wrote .hv")
	}
	// no candidates is an answer, not an error
	code, env, _ = hvRun(t, "--json", "-C", t.TempDir(), "init", "umbrella", "--list")
	if code != 0 || len(umbData(env)["candidates"].([]any)) != 0 {
		t.Fatalf("code=%d env=%v", code, env)
	}
	for _, argv := range [][]string{{"--list", "--all"}, {"--list", "--repos", "web"}} {
		if code, _, _ := hvRun(t, append([]string{"-C", root, "init", "umbrella"}, argv...)...); code != ExitUsage {
			t.Fatalf("%v: code=%d", argv, code)
		}
	}
}

func TestInitUmbrellaRegisters(t *testing.T) {
	root := umbrellaFixture(t, "web", "api")
	os.MkdirAll(filepath.Join(root, ".git"), 0o755)
	var seededAt string
	seedBase = func(r string) error { seededAt = r; return os.MkdirAll(filepath.Join(r, ".hv", "bugs"), 0o755) }
	t.Cleanup(func() { seedBase = nil })

	code, env, stderr := hvRun(t, "--json", "-C", root, "init", "umbrella", "--repos", "web,nope")
	data := umbData(env)
	if code != 0 || seededAt != root || data["root"] != root || data["umbrellaIsGitRepo"] != true || data["changed"] != true ||
		!reflect.DeepEqual(data["registered"], []any{"web"}) {
		t.Fatalf("code=%d env=%v stderr=%s", code, env, stderr)
	}
	if warns, _ := env["warnings"].([]any); len(warns) != 1 || !strings.Contains(warns[0].(string), "unknown name 'nope'") {
		t.Fatalf("warnings=%v", env["warnings"])
	}
	created := data["created"].([]any)
	for _, want := range []string{".hv/bugs", ".hv/repos.json", ".hv/knowledge/web", ".gitignore"} {
		if !containsAny(created, want) {
			t.Errorf("created lacks %s: %v", want, created)
		}
	}
	// second run: nothing to do
	code, env, _ = hvRun(t, "--json", "-C", root, "init", "umbrella", "--repos", "web")
	if data = umbData(env); code != 0 || data["changed"] != false || len(data["created"].([]any)) != 0 {
		t.Fatalf("rerun: code=%d env=%v", code, env)
	}
	// --repos "" registers none but keeps the prior web
	code, env, _ = hvRun(t, "--json", "-C", root, "init", "umbrella", "--repos", "")
	if code != 0 || !reflect.DeepEqual(umbData(env)["registered"], []any{"web"}) {
		t.Fatalf("empty repos: code=%d env=%v", code, env)
	}
}

func containsAny(l []any, s string) bool {
	for _, v := range l {
		if v == s {
			return true
		}
	}
	return false
}

func TestInitUmbrellaExits(t *testing.T) {
	root := umbrellaFixture(t, "web")
	for _, argv := range [][]string{{}, {"--all", "--repos", "web"}, {"--all", "extra"}} {
		if code, _, _ := hvRun(t, append([]string{"-C", root, "init", "umbrella"}, argv...)...); code != ExitUsage {
			t.Fatalf("%v: code=%d", argv, code)
		}
	}
	empty := t.TempDir()
	if code, _, _ := hvRun(t, "-C", empty, "init", "umbrella", "--all"); code != ExitResolution {
		t.Fatalf("no children: code=%d", code)
	}
	if _, err := os.Stat(filepath.Join(empty, ".hv")); err == nil {
		t.Fatal("exit 3 left .hv behind")
	}
}

func TestVersionDrift(t *testing.T) {
	root := a4Project(t, `{"hvSkills": {"version": "4.9.0"}}`)
	old := installedVersionFn
	t.Cleanup(func() { installedVersionFn = old })

	cases := []struct {
		installed, status string
		drift             bool
	}{{"4.9.0", "match", false}, {"5.0.0", "drift", true}, {"", "unknown", false}}
	for _, tc := range cases {
		installedVersionFn = func() string { return tc.installed }
		code, env, stderr := hvRun(t, "--json", "-C", root, "version", "--drift")
		d := umbData(env)
		if code != 0 || d["status"] != tc.status || d["drift"] != tc.drift || d["stamped"] != "4.9.0" ||
			d["installed"] != tc.installed || d["version"] != tc.installed {
			t.Fatalf("%+v: code=%d env=%v stderr=%s", tc, code, env, stderr)
		}
	}

	// text mode: a nudge on drift only
	installedVersionFn = func() string { return "5.0.0" }
	wd, _ := os.Getwd()
	t.Cleanup(func() { os.Chdir(wd) })
	var out, errb bytes.Buffer
	if code := Main([]string{"-C", root, "version", "--drift"}, nil, &out, &errb); code != 0 || !strings.HasPrefix(out.String(), "hv-skills drift: project at 4.9.0, binary at 5.0.0") {
		t.Fatalf("code=%d out=%q", code, out.String())
	}
	out.Reset()
	installedVersionFn = func() string { return "4.9.0" }
	if code := Main([]string{"-C", root, "version", "--drift"}, nil, &out, &errb); code != 0 || out.Len() != 0 {
		t.Fatalf("match must be silent: code=%d out=%q", code, out.String())
	}
	installedVersionFn = func() string { return "5.0.0" }

	// no stamp is unknown; config.local.json overrides the stamp
	bare := a4Project(t, "")
	installedVersionFn = func() string { return "5.0.0" }
	if _, env, _ := hvRun(t, "--json", "-C", bare, "version", "--drift"); umbData(env)["status"] != "unknown" {
		t.Fatalf("env=%v", env)
	}
	os.WriteFile(filepath.Join(root, ".hv", "config.local.json"), []byte(`{"hvSkills": {"version": "5.0.0"}}`), 0o644)
	if _, env, _ := hvRun(t, "--json", "-C", root, "version", "--drift"); umbData(env)["status"] != "match" {
		t.Fatalf("local override ignored: env=%v", env)
	}

	// no .hv/ anywhere: exit 3
	if code, _, _ := hvRun(t, "-C", t.TempDir(), "version", "--drift"); code != ExitResolution {
		t.Fatalf("no .hv: code=%d", code)
	}
	if code, _, _ := hvRun(t, "version", "extra", "--drift"); code != ExitUsage {
		t.Fatalf("extra arg: code=%d", code)
	}
}

// umbData is env["data"] as a plain map; hvRun decodes objects as *jsonx.Object.
func umbData(env map[string]any) map[string]any {
	m := map[string]any{}
	if o, ok := env["data"].(*jsonx.Object); ok {
		for _, k := range o.Keys() {
			m[k], _ = o.Get(k)
		}
	}
	return m
}
