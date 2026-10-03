// Package doctor is the logic behind `hv doctor`: one read-only preflight
// check per thing a parallel round depends on (git, the dispatch host, the
// forge CLI, the worker accounts, herdr's agent integration, the hv binary).
//
// Nothing here reaches os/exec or the real PATH directly: the caller injects
// Exec and Look, so tests need no real herdr, gh or tmux. A missing tool is a
// failed check, never an error.
package doctor

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Check statuses.
const (
	Pass = "pass"
	Fail = "fail"
	Skip = "skip"
)

// Check is one line of the report.
type Check struct {
	Name   string
	Status string
	Detail string
	Hint   string // set on every Fail
}

// Report is every check, in order.
type Report struct{ Checks []Check }

// OK is true when no check failed.
func (r Report) OK() bool {
	for _, c := range r.Checks {
		if c.Status == Fail {
			return false
		}
	}
	return true
}

// Account is one entry of work.accounts.
type Account struct{ Name, ConfigDir string }

// Result is what a finished command left behind.
type Result struct {
	Stdout, Stderr string
	ExitCode       int
}

// Exec runs bin (a path Look returned) in dir with extraEnv added to the
// process environment. A command that ran and exited non-zero is a Result
// with ExitCode set and a nil error; err means it could not run at all.
type Exec func(ctx context.Context, bin string, args []string, extraEnv []string, dir string) (Result, error)

// Input is everything Run needs from the outside.
type Input struct {
	Dir  string // working directory: where git runs
	Home string // expands a leading "~/" in a configDir

	// From the project config when .hv/ exists; zero values otherwise.
	Dispatch       string // work.dispatch
	IssuesProvider string // issues.provider
	Accounts       []Account

	Version string // the running binary's version, "" when unknown

	// PluginRoots are directories to search upward for
	// .claude-plugin/plugin.json, in order.
	PluginRoots []string

	Exec Exec
	// Look resolves a tool name to a path, or false when it is not found.
	Look func(name string) (string, bool)
}

// Run executes every check in the contract's order.
func Run(ctx context.Context, in Input) Report {
	d := &runner{in: in, ctx: ctx}
	return Report{Checks: []Check{
		d.git(), d.host(), d.tracker(), d.accounts(), d.hook(), d.hv(),
	}}
}

type runner struct {
	in  Input
	ctx context.Context
}

func pass(name, detail string) Check { return Check{Name: name, Status: Pass, Detail: detail} }
func skip(name, detail string) Check { return Check{Name: name, Status: Skip, Detail: detail} }
func fail(name, detail, hint string) Check {
	return Check{Name: name, Status: Fail, Detail: detail, Hint: hint}
}

// run runs a looked-up tool; ok is false when it could not run at all.
func (d *runner) run(bin string, args []string, env []string) (Result, bool) {
	r, err := d.in.Exec(d.ctx, bin, args, env, d.in.Dir)
	return r, err == nil
}

func (d *runner) git() Check {
	bin, ok := d.in.Look("git")
	if !ok {
		return fail("git", "git not found on PATH", "install git")
	}
	r, ran := d.run(bin, []string{"check-ignore", "-q", ".worktrees/x"}, nil)
	switch {
	case !ran:
		return fail("git", "git could not run", "install git")
	case r.ExitCode == 0:
		return pass("git", ".worktrees/ is gitignored")
	case r.ExitCode == 1:
		return fail("git", ".worktrees/ is not gitignored", "add .worktrees/ to .gitignore (hv init does this)")
	default:
		return fail("git", "not inside a git repository", "run: git init")
	}
}

var versionRe = regexp.MustCompile(`(\d+)\.(\d+)\.(\d+)`)

func (d *runner) host() Check {
	switch d.in.Dispatch {
	case "herdr":
		bin, ok := d.in.Look("herdr")
		if !ok {
			return fail("host", "herdr not found on PATH", "install herdr 0.9.x (https://herdr.dev)")
		}
		r, ran := d.run(bin, []string{"--version"}, nil)
		out := strings.TrimSpace(r.Stdout + " " + r.Stderr)
		m := versionRe.FindStringSubmatch(out)
		if !ran || r.ExitCode != 0 || m == nil {
			return fail("host", "herdr version unreadable", "reinstall herdr 0.9.x (https://herdr.dev)")
		}
		v := m[0]
		if m[1] != "0" || m[2] != "9" {
			return fail("host", fmt.Sprintf("herdr %s, need 0.9.x", v), "install herdr 0.9.x (https://herdr.dev)")
		}
		return pass("host", "herdr "+v)
	case "tmux":
		if _, ok := d.in.Look("tmux"); !ok {
			return fail("host", "tmux not found on PATH", "install tmux")
		}
		return pass("host", "tmux on PATH")
	default:
		name := d.in.Dispatch
		if name == "" {
			name = "subagent"
		}
		return skip("host", "work.dispatch is "+name+", no terminal host needed")
	}
}

var forgeHost = regexp.MustCompile(`(?i)github|gitlab`)

// provider is "github", "gitlab" or "": the origin host decides, and
// issues.provider is only the fallback (as in `hv issues provider`).
func (d *runner) provider() string {
	if bin, ok := d.in.Look("git"); ok {
		if r, ran := d.run(bin, []string{"remote", "get-url", "origin"}, nil); ran && r.ExitCode == 0 {
			if m := forgeHost.FindString(r.Stdout); m != "" {
				return strings.ToLower(m)
			}
		}
	}
	if p := d.in.IssuesProvider; p == "github" || p == "gitlab" {
		return p
	}
	return ""
}

func (d *runner) tracker() Check {
	p := d.provider()
	if p == "" {
		return skip("tracker", "no origin remote naming github or gitlab")
	}
	cli, login := "gh", "gh auth login"
	if p == "gitlab" {
		cli, login = "glab", "glab auth login"
	}
	bin, ok := d.in.Look(cli)
	if !ok {
		return fail("tracker", cli+" not found on PATH", "install "+cli)
	}
	r, ran := d.run(bin, []string{"auth", "status"}, nil)
	if !ran || r.ExitCode != 0 {
		return fail("tracker", cli+" is not authenticated", login)
	}
	return pass("tracker", cli+" authenticated ("+p+")")
}

func (d *runner) expand(dir string) string {
	if strings.HasPrefix(dir, "~/") && d.in.Home != "" {
		return filepath.Join(d.in.Home, dir[2:])
	}
	return dir
}

func (d *runner) accounts() Check {
	if len(d.in.Accounts) == 0 {
		return skip("accounts", "no accounts in work.accounts")
	}
	var bad []string
	var hint string
	for _, a := range d.in.Accounts {
		dir := d.expand(a.ConfigDir)
		var why string
		if dir == "" {
			why = "no configDir"
			if hint == "" {
				hint = "set configDir for account " + a.Name + " in work.accounts"
			}
		} else if fi, err := os.Stat(dir); err != nil || !fi.IsDir() {
			why = "configDir " + dir + " does not exist"
		} else if fi, err := os.Stat(filepath.Join(dir, ".credentials.json")); err != nil || !fi.Mode().IsRegular() {
			why = "no credentials file in " + dir
		}
		if why != "" {
			bad = append(bad, a.Name+": "+why)
			if hint == "" {
				hint = "CLAUDE_CONFIG_DIR=" + a.ConfigDir + " claude /login"
			}
		}
	}
	if len(bad) > 0 {
		return fail("accounts", strings.Join(bad, "; "), hint)
	}
	return pass("accounts", fmt.Sprintf("%d accounts with credentials", len(d.in.Accounts)))
}

const hookHint = "herdr integration install claude"

func (d *runner) hook() Check {
	if d.in.Dispatch != "herdr" {
		return skip("hook", "host is not herdr")
	}
	if len(d.in.Accounts) == 0 {
		return skip("hook", "no accounts in work.accounts")
	}
	bin, ok := d.in.Look("herdr")
	if !ok {
		return skip("hook", "herdr not on PATH (see host)")
	}
	var parts []string
	failed := false
	for _, a := range d.in.Accounts {
		r, ran := d.run(bin, []string{"integration", "status"}, []string{"CLAUDE_CONFIG_DIR=" + d.expand(a.ConfigDir)})
		if !ran || r.ExitCode != 0 {
			failed = true
			parts = append(parts, a.Name+": herdr integration status failed")
			continue
		}
		state := ParseIntegration(r.Stdout, "claude")
		if state != "current" {
			failed = true
		}
		parts = append(parts, a.Name+": "+state)
	}
	if failed {
		return fail("hook", strings.Join(parts, "; "), hookHint)
	}
	return pass("hook", strings.Join(parts, "; "))
}

// ParseIntegration reads the line for agent from `herdr integration status`
// (`claude: current (v10) (/path)`, `codex: not installed (/path)`) and
// returns "current", "not installed", the raw remainder for any other state
// (an outdated install), or "no status" when there is no such line. The
// format is herdr's own, so this stays tolerant: case, spacing and trailing
// version or path detail are ignored.
func ParseIntegration(out, agent string) string {
	for _, line := range strings.Split(out, "\n") {
		name, rest, ok := strings.Cut(strings.TrimSpace(line), ":")
		if !ok || !strings.EqualFold(strings.TrimSpace(name), agent) {
			continue
		}
		rest = strings.ToLower(strings.TrimSpace(rest))
		switch {
		case strings.HasPrefix(rest, "not installed"), strings.HasPrefix(rest, "missing"):
			return "not installed"
		case strings.HasPrefix(rest, "current"), strings.HasPrefix(rest, "up to date"), strings.HasPrefix(rest, "installed"):
			return "current"
		case rest == "":
			return "no status"
		}
		if i := strings.Index(rest, " ("); i > 0 {
			rest = rest[:i]
		}
		return rest
	}
	return "no status"
}

func (d *runner) hv() Check {
	ver := strings.TrimPrefix(strings.TrimSpace(d.in.Version), "v")
	for _, root := range d.in.PluginRoots {
		plugin, ok := findPlugin(root)
		if !ok {
			continue
		}
		if ver == "" || ver == "(devel)" || ver == "dev" {
			return skip("hv", "running a development build")
		}
		if plugin != ver {
			return fail("hv", fmt.Sprintf("hv %s, plugin.json says %s", ver, plugin), "run: hv update")
		}
		return pass("hv", "hv "+ver+" matches plugin.json")
	}
	return skip("hv", "not inside a plugin or source checkout")
}

// findPlugin walks up from dir to the nearest .claude-plugin/plugin.json and
// returns its version.
func findPlugin(dir string) (string, bool) {
	for dir != "" {
		b, err := os.ReadFile(filepath.Join(dir, ".claude-plugin", "plugin.json"))
		if err == nil {
			var p struct {
				Version string `json:"version"`
			}
			if json.Unmarshal(b, &p) == nil && p.Version != "" {
				return strings.TrimPrefix(p.Version, "v"), true
			}
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", false
}
