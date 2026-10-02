package cli

import (
	"bytes"
	"encoding/json"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"
)

// releaseOld runs the old bin/<helper> in dir and returns its rc, stdout and stderr.
func releaseOld(t *testing.T, dir, helper string, stdin string, args ...string) (int, string, string) {
	t.Helper()
	_, file, _, _ := runtime.Caller(0)
	bin := filepath.Join(filepath.Dir(file), "..", "..", "bin", helper)
	if _, err := os.Stat(bin); err != nil {
		t.Skipf("old helper %s is gone", helper)
	}
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 not available")
	}
	cmd := exec.Command("bash", append([]string{bin}, args...)...)
	cmd.Dir = dir
	cmd.Stdin = strings.NewReader(stdin)
	var so, se bytes.Buffer
	cmd.Stdout, cmd.Stderr = &so, &se
	_ = cmd.Run()
	return cmd.ProcessState.ExitCode(), so.String(), se.String()
}

// releaseTree reads every file under dir (skipping .git) into a map.
func releaseTree(t *testing.T, dir string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if d.Name() == ".git" {
				return filepath.SkipDir
			}
			return nil
		}
		b, err := os.ReadFile(p)
		rel, _ := filepath.Rel(dir, p)
		out[rel] = string(b)
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

// releaseDirs makes two project dirs holding the same files.
func releaseDirs(t *testing.T, files map[string]string) (oldDir, newDir string) {
	t.Helper()
	oldDir, newDir = t.TempDir(), t.TempDir()
	for _, d := range []string{oldDir, newDir} {
		write(t, filepath.Join(d, ".hv", "config.json"), `{}`)
		for p, c := range files {
			write(t, filepath.Join(d, p), c)
		}
	}
	return
}

func releaseData(t *testing.T, o trOut) map[string]any {
	t.Helper()
	d, _ := envelope(t, o.stdout)["data"].(map[string]any)
	return d
}

func releaseMsg(t *testing.T, o trOut) string {
	t.Helper()
	e, _ := envelope(t, o.stdout)["error"].(map[string]any)
	s, _ := e["message"].(string)
	return s
}

var releaseBumpFixtures = map[string]struct{ file, kind, text string }{
	"plugin-json": {".claude-plugin/plugin.json", "plugin-json",
		"{\n  \"name\": \"h\u00e9llo \u2603 \\u00fc\",\n  \"version\": \"1.2.3\",\n  \"nested\": {\"b\": [1, 2, {\"x\": null}], \"a\": 1.5, \"e\": 1e3},\n  \"keywords\": [],\n  \"o\": {}\n}\n"},
	"package-json": {"package.json", "package-json", `{"version":"0.9.9","scripts":{"b":"x","a":"y"}}`},
	"pyproject": {"pyproject.toml", "pyproject",
		"[build-system]\nrequires = [\"x\"]\n\n[project]\nname = \"x\"\nversion = \"1.2.3\"  # c\n\n[tool.foo]\nversion = \"9.9.9\"\n"},
	"poetry": {"pyproject.toml", "pyproject",
		"[tool.poetry]\nname = \"x\"\nversion   =   \"2.0.9\"\n\n[tool.other]\nversion = \"7.0.0\"\n"},
	"pyproject-crlf": {"pyproject.toml", "pyproject", "[project]\r\nversion = \"1.0.0\"\r\nname = \"x\"\r\n"},
	"cargo":          {"Cargo.toml", "cargo", "[package]\nname = \"x\"\nversion = \"3.4.5\"\n\n[dependencies]\nversion = \"1.0.0\"\n"},
	"plain":          {"VERSION", "plain", "  1.2.3  \n\n"},
	"version.txt":    {"version.txt", "plain", "\n\n4.5.6"},
}

func TestReleaseBumpParity(t *testing.T) {
	bumps := [][2]string{{"--level", "patch"}, {"--level", "minor"}, {"--level", "major"}, {"--to", "10.0.0"}}
	for name, fx := range releaseBumpFixtures {
		for _, b := range bumps {
			oldDir, newDir := releaseDirs(t, map[string]string{fx.file: fx.text})
			arg := b[1]
			rc, out, _ := releaseOld(t, oldDir, "hv-release-bump-version", "", fx.file, fx.kind, arg)
			o := trRun(t, newDir, "", "release", "bump", "--file", fx.file, "--kind", fx.kind, b[0], b[1], "--json")
			if rc != 0 || o.code != 0 {
				t.Fatalf("%s %v: old rc %d, new exit %d\n%s%s", name, b, rc, o.code, o.stdout, o.stderr)
			}
			d := releaseData(t, o)
			if d["to"] != strings.TrimSpace(out) || d["changed"] != true || d["kind"] != fx.kind || d["file"] != fx.file {
				t.Errorf("%s %v: data %v, old printed %q", name, b, d, out)
			}
			if !reflect.DeepEqual(releaseTree(t, oldDir), releaseTree(t, newDir)) {
				t.Errorf("%s %v: files differ\nold %q\nnew %q", name, b, releaseTree(t, oldDir)[fx.file], releaseTree(t, newDir)[fx.file])
			}
		}
	}
}

func TestReleaseBumpDetectsFile(t *testing.T) {
	oldDir, newDir := releaseDirs(t, map[string]string{"package.json": `{"version":"1.0.0"}`, "VERSION": "5.0.0\n"})
	releaseOld(t, oldDir, "hv-release-bump-version", "", "package.json", "package-json", "patch")
	o := trRun(t, newDir, "", "release", "bump", "--level", "patch", "--json")
	d := releaseData(t, o)
	if o.code != 0 || d["file"] != "package.json" || d["kind"] != "package-json" || d["from"] != "1.0.0" || d["to"] != "1.0.1" {
		t.Fatalf("%d %v", o.code, d)
	}
	if !reflect.DeepEqual(releaseTree(t, oldDir), releaseTree(t, newDir)) {
		t.Error("files differ")
	}
	// An explicit --kind overrides the detected one; a bare name picks the kind.
	o = trRun(t, newDir, "", "release", "bump", "--file", "VERSION", "--to", "5.0.1", "--json")
	if o.code != 0 || releaseData(t, o)["kind"] != "plain" || releaseTree(t, newDir)["VERSION"] != "5.0.1\n" {
		t.Fatalf("%d %s", o.code, o.stdout)
	}
}

func TestReleaseBumpExits(t *testing.T) {
	files := map[string]string{
		"package.json":   `{"version":"2.0.0"}`,
		"bad.json":       `{"version":`,
		"nover.json":     `{"name":"x"}`,
		"pyproject.toml": "[project]\nname = \"x\"\n",
		"semver.json":    `{"version":"v1"}`,
	}
	oldDir, newDir := releaseDirs(t, files)
	cases := []struct {
		name      string
		args      []string
		code      int
		oldArgs   []string
		oldRC     int
		blockedBy string
	}{
		{"equal", []string{"--to", "2.0.0"}, 4, []string{"package.json", "package-json", "2.0.0"}, 1, "not greater"},
		{"lower", []string{"--to", "1.9.9"}, 4, []string{"package.json", "package-json", "1.9.9"}, 1, "not greater"},
		{"neither", nil, 2, nil, 0, ""},
		{"both", []string{"--level", "patch", "--to", "3.0.0"}, 2, nil, 0, ""},
		{"bad level", []string{"--level", "huge"}, 2, nil, 0, ""},
		{"bad to", []string{"--to", "3.0"}, 2, []string{"package.json", "package-json", "3.0"}, 1, ""},
		{"bad kind", []string{"--level", "patch", "--kind", "yaml"}, 2, []string{"package.json", "yaml", "patch"}, 1, ""},
		{"unknown file name", []string{"--level", "patch", "--file", "x.cfg"}, 2, nil, 0, ""},
		{"missing file", []string{"--level", "patch", "--file", "gone.json"}, 3, []string{"gone.json", "package-json", "patch"}, 1, ""},
		{"corrupt json", []string{"--level", "patch", "--file", "bad.json"}, 3, []string{"bad.json", "package-json", "patch"}, 1, ""},
		{"no version field", []string{"--level", "patch", "--file", "nover.json"}, 3, []string{"nover.json", "package-json", "patch"}, 1, ""},
		{"no version in toml", []string{"--level", "patch", "--file", "pyproject.toml"}, 3, []string{"pyproject.toml", "pyproject", "patch"}, 1, ""},
		{"not semver", []string{"--level", "patch", "--file", "semver.json"}, 3, []string{"semver.json", "package-json", "patch"}, 1, ""},
	}
	for _, c := range cases {
		o := trRun(t, newDir, "", append(append([]string{"release", "bump"}, c.args...), "--json")...)
		if o.code != c.code {
			t.Errorf("%s: exit %d, want %d\n%s%s", c.name, o.code, c.code, o.stdout, o.stderr)
			continue
		}
		if c.blockedBy != "" {
			d := releaseData(t, o)
			if d["blockedBy"] != c.blockedBy || d["changed"] != false {
				t.Errorf("%s: failure data %v", c.name, d)
			}
		}
		if c.oldArgs != nil {
			if rc, _, _ := releaseOld(t, oldDir, "hv-release-bump-version", "", c.oldArgs...); rc != c.oldRC {
				t.Errorf("%s: old rc %d, want %d", c.name, rc, c.oldRC)
			}
		}
	}
	if !reflect.DeepEqual(releaseTree(t, oldDir), releaseTree(t, newDir)) || releaseTree(t, newDir)["package.json"] != files["package.json"] {
		t.Error("a refused or failed bump touched a file")
	}
}

func TestReleaseVersionParity(t *testing.T) {
	for name, fx := range releaseBumpFixtures {
		dir, _ := releaseDirs(t, map[string]string{fx.file: fx.text})
		if name == "version.txt" || name == "pyproject-crlf" {
			continue
		}
		rc, out, _ := releaseOld(t, dir, "hv-release-detect-version", "")
		var want map[string]any
		if err := json.Unmarshal([]byte(out), &want); err != nil || rc != 0 {
			t.Fatalf("%s: old rc %d %q", name, rc, out)
		}
		o := trRun(t, dir, "", "release", "version", "--json")
		if o.code != 0 || !reflect.DeepEqual(releaseData(t, o), want) {
			t.Errorf("%s: %d %v, old %v", name, o.code, releaseData(t, o), want)
		}
		_, next, _ := releaseOld(t, dir, "hv-release-bump-version", "", "--dry-run", fx.file, fx.kind, "minor")
		o = trRun(t, dir, "", "release", "version", "--level", "minor", "--json")
		if o.code != 0 || releaseData(t, o)["next"] != strings.TrimSpace(next) {
			t.Errorf("%s: next %v, old %q", name, releaseData(t, o), next)
		}
		if got := releaseTree(t, dir)[fx.file]; got != fx.text {
			t.Errorf("%s: version --level wrote the file", name)
		}
	}
}

func TestReleaseVersionPriorityAndOverride(t *testing.T) {
	files := map[string]string{
		"VERSION": "9.9.9\n", "Cargo.toml": "[package]\nversion = \"3.0.0\"\n", "package.json": `{"version":"2.5.0"}`,
		".claude-plugin/plugin.json": `{"version":"1.0.0"}`, "other/version.txt": "8.0.0\n",
	}
	dir, _ := releaseDirs(t, files)
	oldRC, oldOut, _ := releaseOld(t, dir, "hv-release-detect-version", "")
	o := trRun(t, dir, "", "release", "version", "--json")
	d := releaseData(t, o)
	if oldRC != 0 || d["file"] != ".claude-plugin/plugin.json" || !strings.Contains(oldOut, ".claude-plugin/plugin.json") {
		t.Fatalf("priority: %v old %q", d, oldOut)
	}
	for _, over := range []string{"package.json", "other/version.txt", "missing.json"} {
		write(t, filepath.Join(dir, ".hv", "config.json"), `{"release":{"versionFile":"`+over+`"}}`)
		rc, out, _ := releaseOld(t, dir, "hv-release-detect-version", "")
		o := trRun(t, dir, "", "release", "version", "--json")
		if rc == 0 {
			var want map[string]any
			_ = json.Unmarshal([]byte(out), &want)
			if o.code != 0 || !reflect.DeepEqual(releaseData(t, o), want) {
				t.Errorf("override %s: %d %v, old %v", over, o.code, releaseData(t, o), want)
			}
		} else if o.code != 3 || !strings.Contains(releaseMsg(t, o), "does not exist") {
			t.Errorf("override %s: old rc %d, new %d %s", over, rc, o.code, o.stdout)
		}
	}
	// config.local.json wins over config.json.
	write(t, filepath.Join(dir, ".hv", "config.local.json"), `{"release":{"versionFile":"package.json"}}`)
	if o := trRun(t, dir, "", "release", "version", "--json"); releaseData(t, o)["file"] != "package.json" {
		t.Errorf("local override ignored: %s", o.stdout)
	}
}

func TestReleaseVersionExits(t *testing.T) {
	empty, _ := releaseDirs(t, nil)
	if rc, _, _ := releaseOld(t, empty, "hv-release-detect-version", ""); rc != 1 {
		t.Fatalf("old rc %d", rc)
	}
	if o := trRun(t, empty, "", "release", "version", "--json"); o.code != 3 || !strings.Contains(releaseMsg(t, o), "no version file detected") {
		t.Errorf("none: %d %s", o.code, o.stdout)
	}
	broken, _ := releaseDirs(t, map[string]string{"package.json": `{"nope":1}`})
	if o := trRun(t, broken, "", "release", "version", "--json"); o.code != 3 || !strings.Contains(releaseMsg(t, o), "no version field found") {
		t.Errorf("no field: %d %s", o.code, o.stdout)
	}
	dir, _ := releaseDirs(t, map[string]string{"VERSION": "1.0.0\n"})
	o := trRun(t, dir, "", "release", "version", "--to", "1.0.0", "--json")
	d := releaseData(t, o)
	if o.code != 1 || d["version"] != "1.0.0" || d["next"] != nil {
		t.Errorf("not greater: %d %s", o.code, o.stdout)
	}
	if rc, _, _ := releaseOld(t, dir, "hv-release-bump-version", "", "--dry-run", "VERSION", "plain", "1.0.0"); rc != 1 {
		t.Errorf("old dry-run rc %d", rc)
	}
	for _, args := range [][]string{{"--level", "huge"}, {"--to", "1.x"}, {"--level", "patch", "--to", "2.0.0"}, {"extra"}} {
		if o := trRun(t, dir, "", append([]string{"release", "version"}, append(args, "--json")...)...); o.code != 2 {
			t.Errorf("%v: exit %d", args, o.code)
		}
	}
}

func TestReleaseRepoScope(t *testing.T) {
	root := umbrella(t)
	write(t, filepath.Join(root, "svc", "VERSION"), "1.4.0\n")
	write(t, filepath.Join(root, "VERSION"), "9.0.0\n")
	gitT(t, filepath.Join(root, "svc"), "remote", "add", "origin", "git@github.com:l4ci/svc.git")
	o := trRun(t, root, "", "release", "version", "--repo", "svc", "--json")
	if d := releaseData(t, o); o.code != 0 || d["version"] != "1.4.0" {
		t.Fatalf("version: %d %s", o.code, o.stdout)
	}
	if o := trRun(t, root, "", "release", "host", "--repo", "svc", "--json"); releaseData(t, o)["host"] != "github" {
		t.Errorf("host: %s", o.stdout)
	}
	if o := trRun(t, root, "", "release", "bump", "--repo", "svc", "--level", "minor", "--json"); o.code != 0 || releaseTree(t, root)["svc/VERSION"] != "1.5.0\n" || releaseTree(t, root)["VERSION"] != "9.0.0\n" {
		t.Errorf("bump: %s", o.stdout)
	}
	write(t, filepath.Join(root, "notes.md"), "- hi\n")
	if o := trRun(t, root, "", "release", "changelog", "1.5.0", "--body-file", "notes.md", "--repo", "svc", "--json"); o.code != 3 {
		t.Errorf("a relative notes file resolves in the sub-repo: %d %s", o.code, o.stdout)
	}
	write(t, filepath.Join(root, "svc", "notes.md"), "- hi\n")
	if o := trRun(t, root, "", "release", "changelog", "1.5.0", "--body-file", "notes.md", "--repo", "svc", "--json"); o.code != 0 {
		t.Errorf("changelog: %d %s", o.code, o.stdout)
	}
	if _, ok := releaseTree(t, root)["svc/CHANGELOG.md"]; !ok {
		t.Error("changelog not written in the sub-repo")
	}
	if o := trRun(t, root, "", "release", "pending", "--repo", "svc", "--json"); releaseData(t, o)["reason"] != "no-tag" {
		t.Errorf("pending: %s", o.stdout)
	}
	if o := trRun(t, root, "", "release", "version", "--repo", "nope", "--json"); o.code != 3 {
		t.Errorf("unknown repo: %d", o.code)
	}
}

func TestReleaseHostParity(t *testing.T) {
	urls := []string{
		"", "git@github.com:l4ci/x.git", "https://github.com/l4ci/x", "HTTPS://GitHub.COM/l4ci/x", "ssh://git@github.com/l4ci/x",
		"git@gitlab.com:a/b.git", "https://gitlab.com/a/b", "https://github.acme.io/a/b", "git@ghe.github.acme.io:a/b", "https://gitlab.acme.io/a/b",
		"ssh://git@GitLab.internal:2222/a/b", "https://example.com/a/b", "/srv/git/repo.git", "https://user@github.com/a/b", "github.com",
	}
	for _, url := range urls {
		dir := t.TempDir()
		gitT(t, dir, "init", "-q", "-b", "main")
		if url != "" {
			gitT(t, dir, "remote", "add", "origin", url)
		}
		_, out, _ := releaseOld(t, dir, "hv-release-detect-host", "")
		o := trRun(t, dir, "", "release", "host", "--json")
		if o.code != 0 || releaseData(t, o)["host"] != strings.TrimSpace(out) {
			t.Errorf("%q: %v, old %q", url, o.stdout, out)
		}
	}
	// Not a git repo: no host.
	plain := t.TempDir()
	if o := trRun(t, plain, "", "release", "host", "--json"); releaseData(t, o)["host"] != "none" {
		t.Errorf("plain dir: %s", o.stdout)
	}
	if o := trRun(t, plain, "", "release", "host", "x", "--json"); o.code != 2 {
		t.Errorf("positional: %d", o.code)
	}
}

// releaseCommit adds a commit with subject and body.
func releaseCommit(t *testing.T, dir, subject, body string) {
	t.Helper()
	msg := subject
	if body != "" {
		msg += "\n\n" + body
	}
	gitT(t, dir, "commit", "-q", "--allow-empty", "-m", msg)
}

func TestReleaseNotesParity(t *testing.T) {
	dir := newRepo(t, t.TempDir(), "r", "main")
	write(t, filepath.Join(dir, ".hv", "config.json"), `{}`)
	gitT(t, dir, "tag", "v0.1.0")
	for _, c := range [][2]string{
		{"feat: add login", ""},
		{"feature(api): add endpoint", ""},
		{"fix(core): crash (rare) on start", ""},
		{"fix: plain fix", "BREAKING CHANGE: behaviour moved"},
		{"perf: faster", ""},
		{"refactor(x): tidy", ""},
		{"chore: bump", ""},
		{"style(fmt): spaces", ""},
		{"docs: readme", ""},
		{"test: add cases", ""},
		{"test(unit): more", "BREAKING CHANGE: ignored, test is skipped"},
		{"random subject", ""},
		{"feat(a)b): odd scope", ""},
		{"feat(): empty scope", ""},
		{"feat!: bang", "breaking change: lowercase counts"},
		{"Fix: capital is Other", ""},
		{"feat: tabbed\tsubject", "body"},
	} {
		releaseCommit(t, dir, c[0], c[1])
	}
	h3 := regexp.MustCompile(`(?m)^## `)
	for _, since := range []string{"", "v0.1.0", "HEAD~3"} {
		rng := "HEAD"
		args := []string{"release", "notes", "--from", "commits", "--json"}
		if since != "" {
			rng = since + "..HEAD"
			args = append(args, "--since", since)
		}
		rc, out, _ := releaseOld(t, dir, "hv-release-changelog-from-commits", "", rng)
		o := trRun(t, dir, "", args...)
		d := releaseData(t, o)
		want := h3.ReplaceAllString(out, "### ")
		if rc != 0 || o.code != 0 || d["markdown"] != want || d["from"] != "commits" || d["empty"] != false {
			t.Errorf("since %q: rc %d exit %d\n%q\nwant %q", since, rc, o.code, d["markdown"], want)
		}
	}
	// text mode prints the markdown verbatim
	o := trRun(t, dir, "", "release", "notes", "--from", "commits", "--since", "HEAD~1")
	if o.code != 0 || !strings.HasPrefix(o.stdout, "### ") || !strings.HasSuffix(o.stdout, "1 commits.\n") {
		t.Errorf("text: %q", o.stdout)
	}
}

func TestReleaseNotesEmptyAndErrors(t *testing.T) {
	dir := newRepo(t, t.TempDir(), "r", "main")
	write(t, filepath.Join(dir, ".hv", "config.json"), `{}`)
	// no commits in range
	rc, out, _ := releaseOld(t, dir, "hv-release-changelog-from-commits", "", "HEAD..HEAD")
	o := trRun(t, dir, "", "release", "notes", "--from", "commits", "--since", "HEAD", "--json")
	d := releaseData(t, o)
	if rc != 0 || out != "" || o.code != 0 || d["empty"] != true || d["markdown"] != "" {
		t.Errorf("empty range: %d %q / %d %v", rc, out, o.code, d)
	}
	// only skipped commits: the old helper prints nothing either
	releaseCommit(t, dir, "test: only tests", "")
	rc, out, _ = releaseOld(t, dir, "hv-release-changelog-from-commits", "", "HEAD~1..HEAD")
	o = trRun(t, dir, "", "release", "notes", "--from", "commits", "--since", "HEAD~1", "--json")
	if rc != 0 || out != "" || releaseData(t, o)["empty"] != true {
		t.Errorf("skipped only: %q %s", out, o.stdout)
	}
	// unresolvable ref
	rc, _, _ = releaseOld(t, dir, "hv-release-changelog-from-commits", "", "nope..HEAD")
	o = trRun(t, dir, "", "release", "notes", "--from", "commits", "--since", "nope", "--json")
	if rc != 1 || o.code != 3 {
		t.Errorf("bad since: old %d new %d", rc, o.code)
	}
	// a repo with no commit at all: HEAD does not resolve
	fresh := t.TempDir()
	gitT(t, fresh, "init", "-q", "-b", "main")
	if o := trRun(t, fresh, "", "release", "notes", "--from", "commits", "--json"); o.code != 3 {
		t.Errorf("unborn HEAD: %d", o.code)
	}
	// not a git repo at all: git fails for another reason
	if o := trRun(t, t.TempDir(), "", "release", "notes", "--from", "commits", "--json"); o.code != 5 {
		t.Errorf("not a repo: %d", o.code)
	}
}

func TestReleaseNotesArgs(t *testing.T) {
	dir := newRepo(t, t.TempDir(), "r", "main")
	write(t, filepath.Join(dir, ".hv", "config.json"), `{}`)
	for _, args := range [][]string{
		{"release", "notes"},
		{"release", "notes", "--from", "x"},
		{"release", "notes", "--from", "commits", "M01"},
		{"release", "notes", "--from", "issues"},
		{"release", "notes", "--from", "issues", "M01", "M02"},
	} {
		if o := trRun(t, dir, "", append(args, "--json")...); o.code != 2 {
			t.Errorf("%v: exit %d", args, o.code)
		}
	}
	if o := trRun(t, dir, "", "release", "notes", "--from", "issues", "M01", "--json"); o.code != 71 {
		t.Errorf("issues not ported: exit %d", o.code)
	}
	// umbrella root without --repo
	root := umbrella(t)
	if o := trRun(t, root, "", "release", "notes", "--from", "issues", "M01", "--json"); o.code != 2 {
		t.Errorf("umbrella: exit %d", o.code)
	}
	if o := trRun(t, root, "", "release", "notes", "--from", "issues", "M01", "--repo", "svc", "--json"); o.code != 71 {
		t.Errorf("umbrella with --repo: exit %d", o.code)
	}
}

func TestReleaseChangelogParity(t *testing.T) {
	notes := "### New\n\n- thing (`abc1234`)\n\n\n"
	cases := []struct {
		name string
		file *string // nil: no changelog
	}{
		{"no file", nil},
		{"h1 and blank", releaseStr("# Changelog\n\n## v1.0.0 — 2020-01-01\n\nold\n")},
		{"h1 then text", releaseStr("# Changelog\nsome intro\nmore\n")},
		{"h1 text then blank", releaseStr("# Changelog\nintro\n\nmore\n")},
		{"h1 only", releaseStr("# Changelog\n")},
		{"h1 only no newline", releaseStr("# Changelog")},
		{"no h1", releaseStr("## v1.0.0 — 2020-01-01\n\nold\n")},
		{"leading blanks", releaseStr("\n\n# Changelog\n\nbody\n")},
		{"h2 first", releaseStr("## Changelog\n\nbody\n")},
		{"h1 with spaces blank", releaseStr("# Changelog\n  \t\nbody\n")},
		{"empty file", releaseStr("")},
		{"crlf", releaseStr("# Changelog\r\n\r\nbody\r\n")},
		{"later h1", releaseStr("intro\n# Changelog\n\nbody\n")},
		{"hash only", releaseStr("#\n\nTitle\n")},
	}
	for _, c := range cases {
		files := map[string]string{"notes.md": notes}
		if c.file != nil {
			files["CHANGELOG.md"] = *c.file
		}
		oldDir, newDir := releaseDirs(t, files)
		rc, out, _ := releaseOld(t, oldDir, "hv-release-update-changelog", "", "1.1.0", "notes.md")
		o := trRun(t, newDir, "", "release", "changelog", "1.1.0", "--body-file", "notes.md", "--json")
		if c.name == "h1 only no newline" {
			// the old helper crashes here; the port appends the section instead
			if rc == 0 || o.code != 0 || !strings.HasPrefix(releaseTree(t, newDir)["CHANGELOG.md"], "# Changelog\n\n## v1.1.0 — ") {
				t.Errorf("%s: old %d, new %d %q", c.name, rc, o.code, releaseTree(t, newDir)["CHANGELOG.md"])
			}
			continue
		}
		if rc != 0 || o.code != 0 {
			t.Errorf("%s: old %d new %d %s", c.name, rc, o.code, o.stdout)
			continue
		}
		d := releaseData(t, o)
		if d["path"] != strings.TrimSpace(out) || d["version"] != "1.1.0" || d["changed"] != true {
			t.Errorf("%s: data %v old %q", c.name, d, out)
		}
		if a, b := releaseTree(t, oldDir)["CHANGELOG.md"], releaseTree(t, newDir)["CHANGELOG.md"]; a != b {
			t.Errorf("%s: files differ\nold %q\nnew %q", c.name, a, b)
		}
	}
}

func releaseStr(s string) *string { return &s }

func TestReleaseChangelogOptions(t *testing.T) {
	oldDir, newDir := releaseDirs(t, map[string]string{"notes.md": "- x\n", "docs/CHANGES.md": "# Changes\n\nold\n"})
	rc, out, _ := releaseOld(t, oldDir, "hv-release-update-changelog", "", "2.0.0", "notes.md", "--path", "docs/CHANGES.md")
	o := trRun(t, newDir, "", "release", "changelog", "2.0.0", "--body-file", "notes.md", "--path", "docs/CHANGES.md", "--json")
	if rc != 0 || o.code != 0 || releaseData(t, o)["path"] != strings.TrimSpace(out) {
		t.Fatalf("path: %d %d %s", rc, o.code, o.stdout)
	}
	if !reflect.DeepEqual(releaseTree(t, oldDir), releaseTree(t, newDir)) {
		t.Error("files differ with --path")
	}
	// stdin
	stdinDir := t.TempDir()
	write(t, filepath.Join(stdinDir, ".hv", "config.json"), `{}`)
	o = trRun(t, stdinDir, "- from stdin\r\n\n", "release", "changelog", "1.0.0", "--body-file", "-", "--json")
	got := releaseTree(t, stdinDir)["CHANGELOG.md"]
	if o.code != 0 || !strings.HasPrefix(got, "# Changelog\n\n## v1.0.0 — ") || !strings.HasSuffix(got, "\n\n- from stdin\n\n") {
		t.Errorf("stdin: %d %q", o.code, got)
	}
}

func TestReleaseChangelogExits(t *testing.T) {
	oldDir, newDir := releaseDirs(t, map[string]string{"notes.md": "- x\n", "CHANGELOG.md": "# Changelog\n\n## v1.0.0 — 2020-01-01\n\nold\n\n## v1.0.01 — x\n"})
	want := releaseTree(t, newDir)
	rc, _, _ := releaseOld(t, oldDir, "hv-release-update-changelog", "", "1.0.0", "notes.md")
	o := trRun(t, newDir, "", "release", "changelog", "1.0.0", "--body-file", "notes.md", "--json")
	if rc != 1 || o.code != 4 {
		t.Fatalf("exists: old %d new %d", rc, o.code)
	}
	if d := releaseData(t, o); d["blockedBy"] != "exists" || d["changed"] != false {
		t.Errorf("failure data %v", d)
	}
	// \b: v1.0.0 must not match a longer number
	if o := trRun(t, newDir, "", "release", "changelog", "1.0.1", "--body-file", "notes.md", "--json"); o.code != 0 {
		t.Errorf("1.0.1 vs 1.0.01: %d", o.code)
	}
	_ = want
	cases := []struct {
		args []string
		code int
	}{
		{[]string{"1.0", "--body-file", "notes.md"}, 2},
		{[]string{"v1.0.0", "--body-file", "notes.md"}, 2},
		{[]string{"3.0.0"}, 2},
		{[]string{"--body-file", "notes.md"}, 2},
		{[]string{"3.0.0", "--body-file", "gone.md"}, 3},
	}
	for _, c := range cases {
		before := releaseTree(t, newDir)
		o := trRun(t, newDir, "", append(append([]string{"release", "changelog"}, c.args...), "--json")...)
		if o.code != c.code {
			t.Errorf("%v: exit %d, want %d", c.args, o.code, c.code)
		}
		if !reflect.DeepEqual(before, releaseTree(t, newDir)) {
			t.Errorf("%v: wrote a file", c.args)
		}
	}
	if rc, _, _ := releaseOld(t, oldDir, "hv-release-update-changelog", "", "3.0.0", "gone.md"); rc != 1 {
		t.Errorf("old missing notes rc %d", rc)
	}
}

// releaseTagRepo makes a repo whose tag v1.0.0 sits daysAgo days back, with n commits after it.
func releaseTagRepo(t *testing.T, daysAgo, n int) string {
	t.Helper()
	dir := newRepo(t, t.TempDir(), "r", "main")
	write(t, filepath.Join(dir, ".hv", "config.json"), `{}`)
	when := "@" + releaseItoa(releaseNow()-int64(daysAgo)*86400) + " +0000"
	t.Setenv("GIT_COMMITTER_DATE", when)
	t.Setenv("GIT_AUTHOR_DATE", when)
	releaseCommit(t, dir, "feat: tagged", "")
	gitT(t, dir, "tag", "v1.0.0")
	t.Setenv("GIT_COMMITTER_DATE", "")
	t.Setenv("GIT_AUTHOR_DATE", "")
	os.Unsetenv("GIT_COMMITTER_DATE")
	os.Unsetenv("GIT_AUTHOR_DATE")
	for i := 0; i < n; i++ {
		releaseCommit(t, dir, "fix: more", "")
	}
	return dir
}

func TestReleasePendingParity(t *testing.T) {
	type tc struct {
		name, cfg string
		days, n   int
	}
	cases := []tc{
		{"quiet", `{}`, 1, 2},
		{"commits threshold", `{}`, 1, 10},
		{"days threshold", `{}`, 20, 1},
		{"tag but no commits", `{}`, 30, 0},
		{"custom commits", `{"release":{"nudgeAfterCommits":2,"nudgeAfterDays":100}}`, 1, 2},
		{"custom days", `{"release":{"nudgeAfterCommits":100,"nudgeAfterDays":3}}`, 5, 1},
		{"bool thresholds", `{"release":{"nudgeAfterCommits":true,"nudgeAfterDays":false}}`, 0, 1},
		{"bool days", `{"release":{"nudgeAfterCommits":50,"nudgeAfterDays":true}}`, 2, 1},
		{"float ignored", `{"release":{"nudgeAfterCommits":2.0,"nudgeAfterDays":"3"}}`, 1, 5},
		{"negative", `{"release":{"nudgeAfterCommits":-1}}`, 1, 1},
		{"release not an object", `{"release":5}`, 1, 11},
	}
	for _, c := range cases {
		dir := releaseTagRepo(t, c.days, c.n)
		write(t, filepath.Join(dir, ".hv", "config.json"), c.cfg)
		rc, out, _ := releaseOld(t, dir, "hv-release-pending", "")
		var want map[string]any
		if rc != 0 || json.Unmarshal([]byte(out), &want) != nil {
			if c.name == "release not an object" {
				continue // the old helper crashes on a non-object release
			}
			t.Fatalf("%s: old rc %d %q", c.name, rc, out)
		}
		o := trRun(t, dir, "", "release", "pending", "--json")
		if o.code != 0 || !reflect.DeepEqual(releaseData(t, o), want) {
			t.Errorf("%s: %d\n%v\nold %v", c.name, o.code, releaseData(t, o), want)
		}
		if tx := trRun(t, dir, "", "release", "pending"); tx.stdout != out {
			t.Errorf("%s: text %q, old %q", c.name, tx.stdout, out)
		}
	}
}

func TestReleasePendingNoTagAndConfigLocal(t *testing.T) {
	dir := newRepo(t, t.TempDir(), "r", "main")
	write(t, filepath.Join(dir, ".hv", "config.json"), `{"release":{"nudgeAfterCommits":3}}`)
	rc, out, _ := releaseOld(t, dir, "hv-release-pending", "")
	var want map[string]any
	_ = json.Unmarshal([]byte(out), &want)
	o := trRun(t, dir, "", "release", "pending", "--json")
	if rc != 0 || o.code != 0 || !reflect.DeepEqual(releaseData(t, o), want) || want["reason"] != "no-tag" || want["thresholdCommits"] != 10.0 {
		t.Errorf("no tag: %v vs %v", releaseData(t, o), want)
	}
	// config.local.json overrides, as load_config merges it
	d2 := releaseTagRepo(t, 1, 3)
	write(t, filepath.Join(d2, ".hv", "config.json"), `{"release":{"nudgeAfterCommits":50}}`)
	write(t, filepath.Join(d2, ".hv", "config.local.json"), `{"release":{"nudgeAfterCommits":3}}`)
	_, out, _ = releaseOld(t, d2, "hv-release-pending", "")
	_ = json.Unmarshal([]byte(out), &want)
	if o := trRun(t, d2, "", "release", "pending", "--json"); !reflect.DeepEqual(releaseData(t, o), want) || want["shouldNudge"] != true {
		t.Errorf("local: %v vs %v", releaseData(t, o), want)
	}
}

func TestReleasePendingGitFails(t *testing.T) {
	dir := releaseTagRepo(t, 1, 1)
	real, _ := exec.LookPath("git")
	fake := t.TempDir()
	write(t, filepath.Join(fake, "git"), "#!/bin/sh\n[ \"$1\" = rev-list ] && { echo 'fatal: boom' >&2; exit 128; }\nexec "+real+" \"$@\"\n")
	if err := os.Chmod(filepath.Join(fake, "git"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", fake+string(os.PathListSeparator)+os.Getenv("PATH"))
	rc, _, _ := releaseOld(t, dir, "hv-release-pending", "")
	o := trRun(t, dir, "", "release", "pending", "--json")
	if rc == 0 || o.code != 5 || !strings.Contains(releaseMsg(t, o), "boom") {
		t.Errorf("old %d new %d %s", rc, o.code, o.stdout)
	}
	if o := trRun(t, dir, "", "release", "pending", "x", "--json"); o.code != 2 {
		t.Errorf("positional: %d", o.code)
	}
}

func TestReleaseIssueVerbsNotPorted(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, ".hv", "config.json"), `{}`)
	cases := []struct {
		args []string
		code int
	}{
		{[]string{"milestone-check", "M01"}, 71},
		{[]string{"milestone-check"}, 2},
		{[]string{"close-milestone", "M01", "--release", "1.2.3"}, 71},
		{[]string{"close-milestone", "M01"}, 2},
		{[]string{"close-milestone", "M01", "--release", "v1.2.3"}, 2},
		{[]string{"close-milestone", "--release", "1.2.3"}, 2},
	}
	for _, c := range cases {
		if o := trRun(t, dir, "", append(append([]string{"release"}, c.args...), "--json")...); o.code != c.code {
			t.Errorf("%v: exit %d, want %d", c.args, o.code, c.code)
		}
	}
	root := umbrella(t)
	for _, args := range [][]string{{"milestone-check", "M01"}, {"close-milestone", "M01", "--release", "1.2.3"}} {
		if o := trRun(t, root, "", append(append([]string{"release"}, args...), "--json")...); o.code != 2 {
			t.Errorf("%v at umbrella root: exit %d", args, o.code)
		}
		if o := trRun(t, root, "", append(append([]string{"release"}, args...), "--repo", "svc", "--json")...); o.code != 71 {
			t.Errorf("%v --repo: exit %d", args, o.code)
		}
	}
}

func releaseNow() int64 { return time.Now().Unix() }

func releaseItoa(n int64) string { return strconv.FormatInt(n, 10) }
