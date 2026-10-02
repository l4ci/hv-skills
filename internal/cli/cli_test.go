package cli

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// testTree exercises every convention without depending on real verbs.
func testTree() *Command {
	data := func(k, v string) *jsonx.Object { o := jsonx.NewObject(); o.Set(k, v); return o }
	plain := func(run RunFunc) func(*flag.FlagSet) RunFunc {
		return func(*flag.FlagSet) RunFunc { return run }
	}
	return &Command{Name: "hv", Summary: "test root", Subs: []*Command{
		{Name: "grp", Summary: "a group", Subs: []*Command{
			{Name: "echo", Summary: "echo args", Repo: true, Verb: func(fs *flag.FlagSet) RunFunc {
				title := fs.String("title", "", "a `text` value")
				force := fs.Bool("force", false, "a boolean")
				return func(c *Ctx, args []string) (Result, error) {
					o := data("repo", c.Repo)
					o.Set("title", *title)
					o.Set("force", *force)
					items := []any{}
					for _, a := range args {
						items = append(items, a)
					}
					o.Set("args", items)
					return Result{Data: o, Text: fmt.Sprintf("title=%s force=%v args=%s", *title, *force, strings.Join(args, ","))}, nil
				}
			}},
			{Name: "warn", Summary: "warns", Verb: plain(func(c *Ctx, _ []string) (Result, error) {
				c.Warn("careful")
				return Result{Text: "done"}, nil
			})},
		}},
		{Name: "cwd", Summary: "prints cwd", Verb: plain(func(c *Ctx, _ []string) (Result, error) {
			wd, _ := os.Getwd()
			return Result{Data: data("cwd", wd), Text: wd}, nil
		})},
		{Name: "root", Summary: "finds .hv", Verb: plain(func(c *Ctx, _ []string) (Result, error) {
			r, err := c.Root()
			return Result{Text: r}, err
		})},
		{Name: "repo", Summary: "resolves --repo", Repo: true, Verb: plain(func(c *Ctx, _ []string) (Result, error) {
			p, err := c.RepoPath()
			return Result{Text: p}, err
		})},
		{Name: "fail", Summary: "fails", Verb: plain(func(c *Ctx, args []string) (Result, error) {
			switch args[0] {
			case "lock":
				return Result{}, fmt.Errorf("saving: %w", fsio.ErrLockTimeout)
			case "plain":
				return Result{}, errors.New("boom")
			case "panic":
				panic("kaboom")
			case "refused":
				return Result{}, Refused("already exists").WithHint("pick another name")
			case "answer":
				o := jsonx.NewObject()
				o.Set("clean", false)
				return Result{Data: o, Text: "dirty"}, Failed("working tree is dirty")
			case "recorded":
				o := jsonx.NewObject()
				o.Set("changed", true)
				return Result{Data: o}, Refused("item has no proof")
			case "leak":
				return Result{Data: jsonx.NewObject(), Text: "x"}, Resolution("gone")
			}
			return Result{}, NotImplemented(c.Path)
		})},
		{Name: "shadow", Summary: "breaks the no-shadow rule", Verb: func(fs *flag.FlagSet) RunFunc {
			fs.Bool("json", false, "clashes with the global")
			return nil
		}},
	}}
}

type out struct {
	code           int
	stdout, stderr string
}

func call(args ...string) out {
	var so, se bytes.Buffer
	code := run(testTree(), args, strings.NewReader(""), &so, &se)
	return out{code, so.String(), se.String()}
}

func TestExitCodesAndEnvelope(t *testing.T) {
	echo := func(repo, title string, force bool, args string) string {
		a := "[]"
		if args != "" {
			a = "[" + args + "]"
		}
		return fmt.Sprintf(`{"ok": true, "data": {"repo": "%s", "title": "%s", "force": %v, "args": %s}}`+"\n", repo, title, force, a)
	}
	cases := []struct {
		args      []string
		code      int
		stdout    string
		stderrHas string
	}{
		{[]string{"grp", "echo", "a", "b"}, 0, "title= force=false args=a,b\n", ""},
		{[]string{"--json", "grp", "echo", "a"}, 0, echo("", "", false, `"a"`), ""},
		{[]string{"grp", "--json", "echo", "a"}, 0, echo("", "", false, `"a"`), ""},
		{[]string{"grp", "echo", "a", "--json"}, 0, echo("", "", false, `"a"`), ""},
		// Flags and args interleave; a value flag always takes the next token.
		{[]string{"grp", "echo", "a", "--title", "T", "b", "--force"}, 0, "title=T force=true args=a,b\n", ""},
		{[]string{"grp", "echo", "--title", "--json"}, 0, "title=--json force=false args=\n", ""},
		{[]string{"grp", "echo", "--title", "-h", "--json"}, 0, echo("", "-h", false, ""), ""},
		{[]string{"grp", "echo", "-title=x", "--force=false", "--title", "y"}, 0, "title=y force=false args=\n", ""},
		{[]string{"grp", "echo", "-", "--", "--json", "-h"}, 0, "title= force=false args=-,--json,-h\n", ""},
		{[]string{"grp", "echo", "--repo", "web", "x"}, 0, "title= force=false args=x\n", ""},
		{[]string{"--repo=web", "grp", "echo", "--json"}, 0, echo("web", "", false, ""), ""},
		{[]string{"grp", "warn", "--json"}, 0, `{"ok": true, "data": {}, "warnings": ["careful"]}` + "\n", "hv grp warn: warning: careful\n"},
		// Usage errors.
		{[]string{"nope"}, 2, "", "hv: unknown command \"nope\"\nhint: run: hv --help\n"},
		{[]string{}, 2, "", "hv: missing command"},
		{[]string{"grp"}, 2, "", "hv grp: missing verb; one of: echo, warn\n"},
		{[]string{"grp", "nope", "--json"}, 2, `{"ok": false, "error": {"code": "usage", "exit": 2, "message": "unknown command \"nope\"", "hint": "run: hv grp --help"}}` + "\n", "hv grp: unknown command"},
		{[]string{"--title", "x", "grp", "echo"}, 2, "", "hv: unknown flag \"--title\"\n"},
		{[]string{"grp", "echo", "--bogus"}, 2, "", "hv grp echo: unknown flag \"--bogus\"\n"},
		{[]string{"grp", "echo", "--title"}, 2, "", "hv grp echo: flag --title needs a value\n"},
		{[]string{"grp", "echo", "--force=maybe"}, 2, "", "hv grp echo: invalid value \"maybe\" for --force\n"},
		{[]string{"grp", "echo", "---x"}, 2, "", "bad flag syntax"},
		{[]string{"--", "grp", "echo"}, 2, "", "hv: unexpected -- before the verb\n"},
		{[]string{"cwd", "--repo", "x"}, 2, "", "hv cwd: unknown flag \"--repo\"\n"},
		{[]string{"--repo", "x", "cwd"}, 2, "", "hv cwd: unknown flag \"--repo\"\n"},
		{[]string{"--repo"}, 2, "", "hv: flag --repo needs a value\n"},
		// A parse error still answers in JSON when --json is a token.
		{[]string{"grp", "echo", "--bogus", "--json"}, 2, `{"ok": false, "error": {"code": "usage", "exit": 2, "message": "unknown flag \"--bogus\""}}` + "\n", ""},
		// Verb outcomes.
		{[]string{"fail", "refused", "--json"}, 4, `{"ok": false, "error": {"code": "refused", "exit": 4, "message": "already exists", "hint": "pick another name"}}` + "\n", "hv fail: already exists\nhint: pick another name\n"},
		// Failure data rides beside error on exit 1 and 4 only.
		{[]string{"fail", "answer", "--json"}, 1, `{"ok": false, "error": {"code": "failed", "exit": 1, "message": "working tree is dirty"}, "data": {"clean": false}}` + "\n", "hv fail: working tree is dirty\n"},
		{[]string{"fail", "answer"}, 1, "dirty\n", "hv fail: working tree is dirty\n"},
		{[]string{"fail", "recorded", "--json"}, 4, `{"ok": false, "error": {"code": "refused", "exit": 4, "message": "item has no proof"}, "data": {"changed": true}}` + "\n", ""},
		{[]string{"fail", "leak", "--json"}, 3, `{"ok": false, "error": {"code": "resolution", "exit": 3, "message": "gone"}}` + "\n", ""},
		{[]string{"fail", "leak"}, 3, "", "hv fail: gone\n"},
		{[]string{"fail", "lock"}, 6, "", "hv fail: saving: lock timeout\n"},
		{[]string{"fail", "plain"}, 70, "", "hv fail: boom\nhint: this is a bug in hv"},
		{[]string{"fail", "panic"}, 70, "", "hv fail: panic: kaboom"},
		{[]string{"fail", "todo", "--json"}, 71, `{"ok": false, "error": {"code": "not_implemented", "exit": 71, "message": "hv fail is not ported yet"}}` + "\n", ""},
		{[]string{"-C", "/does/not/exist", "cwd"}, 3, "", "hv cwd: cannot use -C /does/not/exist"},
		{[]string{"shadow"}, 70, "", "flag redefined: json"},
	}
	for _, tc := range cases {
		got := call(tc.args...)
		if got.code != tc.code || got.stdout != tc.stdout || !strings.Contains(got.stderr, tc.stderrHas) {
			t.Errorf("hv %v\n got  code=%d stdout=%q stderr=%q\n want code=%d stdout=%q stderr~%q",
				tc.args, got.code, got.stdout, got.stderr, tc.code, tc.stdout, tc.stderrHas)
		}
		if tc.code == 0 && tc.stderrHas == "" && got.stderr != "" {
			t.Errorf("hv %v: unexpected stderr %q", tc.args, got.stderr)
		}
	}
}

func TestJSONOutputIsOneDocument(t *testing.T) {
	for _, args := range [][]string{{"grp", "echo", "x", "--json"}, {"nope", "--json"}, {"--json", "--help"}} {
		got := call(args...)
		if strings.Count(got.stdout, "\n") != 1 || !strings.HasSuffix(got.stdout, "\n") {
			t.Errorf("hv %v: stdout is not one line: %q", args, got.stdout)
		}
		if _, err := jsonx.Decode([]byte(got.stdout)); err != nil {
			t.Errorf("hv %v: stdout is not JSON: %v", args, err)
		}
	}
}

func TestHelp(t *testing.T) {
	got := call("grp", "--help")
	if got.code != 0 || !strings.Contains(got.stdout, "echo") || !strings.Contains(got.stdout, "warn") {
		t.Fatalf("group help: %+v", got)
	}
	if got := call("grp", "echo", "-h"); got.code != 0 || !strings.HasPrefix(got.stdout, "hv grp echo: echo args") || !strings.Contains(got.stdout, "--title") {
		t.Fatalf("verb help: %+v", got)
	}
}

func TestCwdAndRoot(t *testing.T) {
	wd, _ := os.Getwd()
	t.Cleanup(func() { os.Chdir(wd) })
	dir := t.TempDir()
	deep := filepath.Join(dir, "a", "b")
	os.MkdirAll(deep, 0o755)
	os.Mkdir(filepath.Join(dir, ".hv"), 0o755)
	real, _ := filepath.EvalSymlinks(dir)

	if got := call("-C", deep, "root"); got.code != 0 || strings.TrimSpace(got.stdout) != real {
		t.Fatalf("root from %s: %+v, want %s", deep, got, real)
	}
	bare := t.TempDir()
	got := call("--cwd="+bare, "root")
	if got.code != 3 || !strings.Contains(got.stderr, "hint: run: hv init") {
		t.Fatalf("no .hv: %+v", got)
	}
}

func TestVersionVerb(t *testing.T) {
	var so, se bytes.Buffer
	if code := Main([]string{"--version"}, nil, &so, &se); code != 0 || !strings.HasPrefix(so.String(), "hv ") {
		t.Fatalf("--version: code=%d out=%q err=%q", code, so.String(), se.String())
	}
	so.Reset()
	if code := Main([]string{"version", "--json"}, nil, &so, &se); code != 0 || !strings.HasPrefix(so.String(), `{"ok": true, "data": {"version": `) {
		t.Fatalf("version --json: %q", so.String())
	}
	if code := Main([]string{"version", "extra"}, nil, &so, &se); code != 2 {
		t.Fatalf("version extra: code=%d", code)
	}
}

func TestEveryExitCodeHasAName(t *testing.T) {
	for _, code := range []int{ExitFailed, ExitUsage, ExitResolution, ExitRefused, ExitUnavailable, ExitRetry, ExitInternal, ExitNotImplemented} {
		if CodeName(code) == "" {
			t.Errorf("exit %d has no error.code name", code)
		}
	}
}

func TestRepoResolution(t *testing.T) {
	wd, _ := os.Getwd()
	t.Cleanup(func() { os.Chdir(wd) })
	dir := t.TempDir()
	real, _ := filepath.EvalSymlinks(dir)
	must := func(err error) {
		if err != nil {
			t.Fatal(err)
		}
	}
	must(os.MkdirAll(filepath.Join(dir, ".hv"), 0o755))
	must(os.MkdirAll(filepath.Join(dir, "web"), 0o755))

	// Not umbrella mode: no repos.json.
	if got := call("-C", dir, "repo", "--repo", "web"); got.code != 3 || !strings.Contains(got.stderr, "not in umbrella mode") {
		t.Fatalf("no registry: %+v", got)
	}
	must(os.WriteFile(filepath.Join(dir, ".hv", "repos.json"),
		[]byte(`{"repos": [{"name": "web", "path": "web"}, {"name": "", "path": "x"}]}`), 0o644))
	if got := call("-C", dir, "repo", "--repo", "web"); got.code != 0 || strings.TrimSpace(got.stdout) != filepath.Join(real, "web") {
		t.Fatalf("registered: %+v", got)
	}
	if got := call("-C", dir, "repo", "--repo", "api", "--json"); got.code != 3 || !strings.Contains(got.stdout, `"code": "resolution"`) {
		t.Fatalf("unregistered: %+v", got)
	}
	if got := call("-C", dir, "repo"); got.code != 0 || got.stdout != "" {
		t.Fatalf("no --repo: %+v", got)
	}
}

// No real verb may define a flag named like a global (rule 2).
func TestTreeVerbsDoNotShadowGlobals(t *testing.T) {
	var walk func(cmd *Command)
	walk = func(cmd *Command) {
		for _, s := range cmd.Subs {
			walk(s)
		}
		if cmd.Verb == nil {
			return
		}
		defer func() {
			if r := recover(); r != nil {
				t.Errorf("%s: %v", cmd.Name, r)
			}
		}()
		fs := newFlagSet(cmd.Name)
		cmd.Verb(fs)
		var g globals
		g.register(fs, false, cmd.Repo)
	}
	walk(Tree())
}
