package cli

import (
	"bytes"
	"errors"
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
	return &Command{Name: "hv", Summary: "test root", Subs: []*Command{
		{Name: "grp", Summary: "a group", Subs: []*Command{
			{Name: "echo", Summary: "echo args", Repo: true, Run: func(c *Ctx, args []string) (Result, error) {
				o := data("repo", c.Repo)
				items := []any{}
				for _, a := range args {
					items = append(items, a)
				}
				o.Set("args", items)
				return Result{Data: o, Text: strings.Join(args, " ")}, nil
			}},
			{Name: "warn", Summary: "warns", Run: func(c *Ctx, _ []string) (Result, error) {
				c.Warn("careful")
				return Result{Text: "done"}, nil
			}},
		}},
		{Name: "cwd", Summary: "prints cwd", Run: func(c *Ctx, _ []string) (Result, error) {
			wd, _ := os.Getwd()
			return Result{Data: data("cwd", wd), Text: wd}, nil
		}},
		{Name: "root", Summary: "finds .hv", Run: func(c *Ctx, _ []string) (Result, error) {
			r, err := c.Root()
			return Result{Text: r}, err
		}},
		{Name: "fail", Summary: "fails", Run: func(c *Ctx, args []string) (Result, error) {
			switch args[0] {
			case "lock":
				return Result{}, fmt.Errorf("saving: %w", fsio.ErrLockTimeout)
			case "plain":
				return Result{}, errors.New("boom")
			case "panic":
				panic("kaboom")
			case "refused":
				return Result{}, Refused("already exists").WithHint("pick another name")
			}
			return Result{}, NotImplemented(c.Path)
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
	cases := []struct {
		args      []string
		code      int
		stdout    string
		stderrHas string
	}{
		{[]string{"grp", "echo", "a", "b"}, 0, "a b\n", ""},
		{[]string{"--json", "grp", "echo", "a"}, 0, `{"ok": true, "data": {"repo": "", "args": ["a"]}}` + "\n", ""},
		{[]string{"grp", "echo", "a", "--json"}, 0, `{"ok": true, "data": {"repo": "", "args": ["a"]}}` + "\n", ""},
		{[]string{"grp", "echo", "--repo", "web", "x"}, 0, "x\n", ""},
		{[]string{"grp", "echo", "--repo=web", "--json"}, 0, `{"ok": true, "data": {"repo": "web", "args": []}}` + "\n", ""},
		{[]string{"grp", "echo", "--", "--json"}, 0, "-- --json\n", ""},
		{[]string{"grp", "warn", "--json"}, 0, `{"ok": true, "data": {}, "warnings": ["careful"]}` + "\n", "hv grp warn: warning: careful\n"},
		{[]string{"nope"}, 2, "", "hv: unknown command \"nope\"\nhint: run: hv --help\n"},
		{[]string{}, 2, "", "hv: missing command"},
		{[]string{"grp"}, 2, "", "hv grp: missing verb; one of: echo, warn\n"},
		{[]string{"grp", "nope", "--json"}, 2, `{"ok": false, "error": {"code": "usage", "exit": 2, "message": "unknown command \"nope\"", "hint": "run: hv grp --help"}}` + "\n", "hv grp: unknown command"},
		{[]string{"cwd", "--repo", "x"}, 2, "", "hv cwd: --repo is not supported here\n"},
		{[]string{"--repo"}, 2, "", "hv: --repo needs a value\n"},
		{[]string{"--json=1", "cwd"}, 2, "", "hv: --json takes no value\n"},
		{[]string{"fail", "refused", "--json"}, 4, `{"ok": false, "error": {"code": "refused", "exit": 4, "message": "already exists", "hint": "pick another name"}}` + "\n", "hv fail: already exists\nhint: pick another name\n"},
		{[]string{"fail", "lock"}, 6, "", "hv fail: saving: lock timeout\n"},
		{[]string{"fail", "plain"}, 70, "", "hv fail: boom\nhint: this is a bug in hv"},
		{[]string{"fail", "panic"}, 70, "", "hv fail: panic: kaboom"},
		{[]string{"fail", "todo", "--json"}, 71, `{"ok": false, "error": {"code": "not_implemented", "exit": 71, "message": "hv fail is not ported yet"}}` + "\n", ""},
		{[]string{"-C", "/does/not/exist", "cwd"}, 3, "", "hv: cannot use -C /does/not/exist"},
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
	if got := call("grp", "echo", "-h"); got.code != 0 || !strings.HasPrefix(got.stdout, "hv grp echo: echo args") {
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
	for _, code := range []int{ExitFailed, ExitUsage, ExitNotFound, ExitRefused, ExitUnavailable, ExitRetry, ExitInternal, ExitNotImplemented} {
		if CodeName(code) == "" {
			t.Errorf("exit %d has no error.code name", code)
		}
	}
}
