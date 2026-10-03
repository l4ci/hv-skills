package doctor

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixture(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// fake answers by "<tool> <args>" prefix; a tool missing from have is not on PATH.
type fake struct {
	have  map[string]bool
	reply map[string]Result // key: tool + " " + joined args
	envs  []string          // CLAUDE_CONFIG_DIR values seen by herdr integration status
}

func (f *fake) look(name string) (string, bool) { return "/fake/" + name, f.have[name] }

func (f *fake) exec(_ context.Context, bin string, args []string, env []string, _ string) (Result, error) {
	tool := filepath.Base(bin)
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, "CLAUDE_CONFIG_DIR="); ok {
			f.envs = append(f.envs, v)
		}
	}
	if r, ok := f.reply[tool+" "+strings.Join(args, " ")]; ok {
		return r, nil
	}
	return Result{ExitCode: 1}, nil
}

func statusOf(r Report, name string) Check {
	for _, c := range r.Checks {
		if c.Name == name {
			return c
		}
	}
	return Check{}
}

func TestParseIntegration(t *testing.T) {
	cur, miss := fixture(t, "integration_status_current.txt"), fixture(t, "integration_status_missing.txt")
	for _, tc := range []struct{ name, out, agent, want string }{
		{"current", cur, "claude", "current"},
		{"not installed", miss, "claude", "not installed"},
		{"other agent untouched", miss, "codex", "current"},
		{"absent agent", cur, "nope", "no status"},
		{"empty output", "", "claude", "no status"},
		{"case and spacing", "  Claude :  Current (v11) (/x)\n", "claude", "current"},
		{"outdated", "claude: outdated (v9, latest v10) (/x)\n", "claude", "outdated"},
		{"no version suffix", "claude: not installed\n", "claude", "not installed"},
	} {
		if got := ParseIntegration(tc.out, tc.agent); got != tc.want {
			t.Errorf("%s: got %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestRunTable(t *testing.T) {
	home := t.TempDir()
	good := filepath.Join(home, "good")
	os.MkdirAll(good, 0o755)
	os.WriteFile(filepath.Join(good, ".credentials.json"), []byte("{}"), 0o600)
	nocred := filepath.Join(home, "nocred")
	os.MkdirAll(nocred, 0o755)
	cur, miss := fixture(t, "integration_status_current.txt"), fixture(t, "integration_status_missing.txt")

	all := map[string]bool{"git": true, "herdr": true, "tmux": true, "gh": true, "glab": true}
	base := map[string]Result{
		"git check-ignore -q .worktrees/x": {},
		"git remote get-url origin":        {Stdout: "git@github.com:a/b.git\n"},
		"gh auth status":                   {},
		"glab auth status":                 {},
		"herdr --version":                  {Stdout: "herdr 0.9.3\n"},
		"herdr integration status":         {Stdout: cur},
	}
	with := func(over map[string]Result) map[string]Result {
		m := map[string]Result{}
		for k, v := range base {
			m[k] = v
		}
		for k, v := range over {
			m[k] = v
		}
		return m
	}
	without := func(names ...string) map[string]bool {
		m := map[string]bool{}
		for k := range all {
			m[k] = true
		}
		for _, n := range names {
			delete(m, n)
		}
		return m
	}
	herdrIn := Input{Dispatch: "herdr", Accounts: []Account{{"a", good}}}

	for _, tc := range []struct {
		name   string
		in     Input
		have   map[string]bool
		reply  map[string]Result
		check  string
		status string
		detail string // substring
		hint   string // substring
	}{
		{"git ok", Input{}, all, with(nil), "git", Pass, "gitignored", ""},
		{"git missing", Input{}, without("git"), with(nil), "git", Fail, "not found", "install git"},
		{"worktrees not ignored", Input{}, all, with(map[string]Result{"git check-ignore -q .worktrees/x": {ExitCode: 1}}), "git", Fail, "not gitignored", "hv init"},
		{"not a repo", Input{}, all, with(map[string]Result{"git check-ignore -q .worktrees/x": {ExitCode: 128}}), "git", Fail, "not inside", "git init"},

		{"host subagent skips", Input{}, all, with(nil), "host", Skip, "subagent", ""},
		{"host herdr ok", herdrIn, all, with(nil), "host", Pass, "herdr 0.9.3", ""},
		{"host herdr 0.8", herdrIn, all, with(map[string]Result{"herdr --version": {Stdout: "herdr 0.8.2"}}), "host", Fail, "herdr 0.8.2, need 0.9.x", "0.9.x"},
		{"host herdr 0.10", herdrIn, all, with(map[string]Result{"herdr --version": {Stdout: "herdr 0.10.0"}}), "host", Fail, "need 0.9.x", ""},
		{"host herdr garbage", herdrIn, all, with(map[string]Result{"herdr --version": {Stdout: "??"}}), "host", Fail, "unreadable", ""},
		{"host herdr missing", herdrIn, without("herdr"), with(nil), "host", Fail, "not found", ""},
		{"host tmux ok", Input{Dispatch: "tmux"}, all, with(nil), "host", Pass, "tmux", ""},
		{"host tmux missing", Input{Dispatch: "tmux"}, without("tmux"), with(nil), "host", Fail, "tmux not found", "install tmux"},

		{"tracker github ok", Input{}, all, with(nil), "tracker", Pass, "gh authenticated", ""},
		{"tracker gh unauthenticated", Input{}, all, with(map[string]Result{"gh auth status": {ExitCode: 1}}), "tracker", Fail, "not authenticated", "gh auth login"},
		{"tracker gh missing", Input{}, without("gh"), with(nil), "tracker", Fail, "gh not found", ""},
		{"tracker gitlab", Input{}, all, with(map[string]Result{"git remote get-url origin": {Stdout: "https://gitlab.com/a/b"}}), "tracker", Pass, "glab", ""},
		{"tracker no remote", Input{}, all, with(map[string]Result{"git remote get-url origin": {ExitCode: 2}}), "tracker", Skip, "no origin", ""},
		{"tracker config fallback", Input{IssuesProvider: "gitlab"}, all, with(map[string]Result{"git remote get-url origin": {ExitCode: 2}}), "tracker", Pass, "glab", ""},

		{"accounts none", Input{}, all, with(nil), "accounts", Skip, "no accounts", ""},
		{"accounts ok", Input{Accounts: []Account{{"a", good}}}, all, with(nil), "accounts", Pass, "1 accounts", ""},
		{"accounts tilde", Input{Home: home, Accounts: []Account{{"a", "~/good"}}}, all, with(nil), "accounts", Pass, "", ""},
		{"accounts no dir", Input{Accounts: []Account{{"a", filepath.Join(home, "gone")}}}, all, with(nil), "accounts", Fail, "does not exist", "claude /login"},
		{"accounts no creds", Input{Accounts: []Account{{"a", nocred}}}, all, with(nil), "accounts", Fail, "no credentials file", "CLAUDE_CONFIG_DIR="},
		{"accounts no configDir", Input{Accounts: []Account{{"a", ""}}}, all, with(nil), "accounts", Fail, "no configDir", "work.accounts"},

		{"hook ok", herdrIn, all, with(nil), "hook", Pass, "a: current", ""},
		{"hook not installed", herdrIn, all, with(map[string]Result{"herdr integration status": {Stdout: miss}}), "hook", Fail, "a: not installed", "herdr integration install claude"},
		{"hook status errors", herdrIn, all, with(map[string]Result{"herdr integration status": {ExitCode: 1}}), "hook", Fail, "status failed", "herdr integration install claude"},
		{"hook skips off herdr", Input{Dispatch: "tmux", Accounts: []Account{{"a", good}}}, all, with(nil), "hook", Skip, "not herdr", ""},
		{"hook skips without accounts", Input{Dispatch: "herdr"}, all, with(nil), "hook", Skip, "no accounts", ""},
		{"hook skips without herdr", herdrIn, without("herdr"), with(nil), "hook", Skip, "see host", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := &fake{have: tc.have, reply: tc.reply}
			in := tc.in
			in.Exec, in.Look = f.exec, f.look
			c := statusOf(Run(context.Background(), in), tc.check)
			if c.Status != tc.status {
				t.Fatalf("status %q, want %q (%+v)", c.Status, tc.status, c)
			}
			if !strings.Contains(c.Detail, tc.detail) {
				t.Errorf("detail %q lacks %q", c.Detail, tc.detail)
			}
			if tc.status == Fail && c.Hint == "" {
				t.Error("a fail carries a hint")
			}
			if !strings.Contains(c.Hint, tc.hint) {
				t.Errorf("hint %q lacks %q", c.Hint, tc.hint)
			}
		})
	}
}

func TestHookRunsPerAccountWithItsConfigDir(t *testing.T) {
	d := t.TempDir()
	f := &fake{have: map[string]bool{"herdr": true}, reply: map[string]Result{
		"herdr integration status": {Stdout: fixture(t, "integration_status_current.txt")},
	}}
	in := Input{Dispatch: "herdr", Home: d, Accounts: []Account{{"a", "~/one"}, {"b", "/two"}}, Exec: f.exec, Look: f.look}
	c := statusOf(Run(context.Background(), in), "hook")
	if c.Status != Pass {
		t.Fatalf("%+v", c)
	}
	want := []string{filepath.Join(d, "one"), "/two"}
	if strings.Join(f.envs, "|") != strings.Join(want, "|") {
		t.Errorf("config dirs %v, want %v", f.envs, want)
	}
}

func TestOrderAndOK(t *testing.T) {
	f := &fake{have: map[string]bool{}, reply: map[string]Result{}}
	r := Run(context.Background(), Input{Exec: f.exec, Look: f.look})
	var names []string
	for _, c := range r.Checks {
		names = append(names, c.Name)
	}
	if got := strings.Join(names, ","); got != "git,host,tracker,accounts,hook,hv" {
		t.Errorf("order %s", got)
	}
	if r.OK() {
		t.Error("git is missing, so the report is not OK")
	}
	if !(Report{Checks: []Check{{Status: Pass}, {Status: Skip}}}).OK() {
		t.Error("pass and skip are OK")
	}
}

func TestHvVersionCheck(t *testing.T) {
	plug := t.TempDir()
	os.MkdirAll(filepath.Join(plug, ".claude-plugin"), 0o755)
	os.WriteFile(filepath.Join(plug, ".claude-plugin", "plugin.json"), []byte(`{"version":"5.0.0"}`), 0o644)
	sub := filepath.Join(plug, "a", "b")
	os.MkdirAll(sub, 0o755)
	empty := t.TempDir()
	f := &fake{have: map[string]bool{}}
	for _, tc := range []struct {
		name, ver string
		roots     []string
		status    string
	}{
		{"match", "5.0.0", []string{sub}, Pass},
		{"v prefix", "v5.0.0", []string{sub}, Pass},
		{"drift", "4.5.0", []string{sub}, Fail},
		{"dev build", "", []string{sub}, Skip},
		{"outside a checkout", "5.0.0", []string{empty}, Skip},
		{"second root", "5.0.0", []string{empty, plug}, Pass},
	} {
		c := statusOf(Run(context.Background(), Input{Version: tc.ver, PluginRoots: tc.roots, Exec: f.exec, Look: f.look}), "hv")
		if c.Status != tc.status {
			t.Errorf("%s: %+v, want %s", tc.name, c, tc.status)
		}
	}
}
