package cli

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/config"
	"github.com/l4ci/hv-skills/v5/internal/doctor"
	"github.com/l4ci/hv-skills/v5/internal/hook"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/version"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

// doctorCommand is `hv doctor` (C6): a read-only preflight. It runs without
// .hv/ and reads the project config only when one is found.
func doctorCommand() *Command {
	return &Command{Name: "doctor", Summary: "preflight: git, host, forge, accounts, herdr hook, orchestrator hooks, hv, codex", Verb: noFlags(runDoctor)}
}

// doctorCallTimeout bounds each tool call, so a hung herdr cannot hang the verb.
const doctorCallTimeout = 20 * time.Second

func runDoctor(c *Ctx, args []string) (Result, error) {
	if err := noArgs(args); err != nil {
		return Result{}, err
	}
	rep := doctor.Run(c.Context(), doctorInput())
	checks := make([]any, 0, len(rep.Checks))
	var lines []string
	for _, ch := range rep.Checks {
		o := jsonx.NewObject()
		o.Set("name", ch.Name)
		o.Set("status", ch.Status)
		o.Set("detail", ch.Detail)
		line := ch.Status + "\t" + ch.Name + "\t" + ch.Detail
		if ch.Hint != "" {
			o.Set("hint", ch.Hint)
			line += "\n\thint: " + ch.Hint
		}
		checks = append(checks, o)
		lines = append(lines, line)
	}
	data := knObj("ok", rep.OK(), "checks", checks)
	res := Result{Data: data, Text: strings.Join(lines, "\n")}
	if !rep.OK() {
		return res, Failed("doctor: a check failed")
	}
	return res, nil
}

// doctorInput gathers the real environment: HV_TEST_DOCTOR_PATH replaces PATH
// for tool lookup (a test hook, not part of the CLI).
func doctorInput() doctor.Input {
	in := doctor.Input{Version: version.Get().Version, Exec: doctorExec, Look: doctorLook(os.Getenv("HV_TEST_DOCTOR_PATH"))}
	in.Dir, _ = os.Getwd()
	in.Home, _ = os.UserHomeDir()
	in.PluginRoots = []string{in.Dir}
	if exe, err := os.Executable(); err == nil {
		if real, err := filepath.EvalSymlinks(exe); err == nil {
			exe = real
		}
		in.PluginRoots = append(in.PluginRoots, filepath.Dir(exe))
	}
	root := ""
	for d := in.Dir; d != ""; {
		if fi, err := os.Stat(filepath.Join(d, ".hv")); err == nil && fi.IsDir() {
			root = d
			break
		}
		if p := filepath.Dir(d); p != d {
			d = p
		} else {
			break
		}
	}
	if root == "" {
		return in
	}
	cfg := config.Load(filepath.Join(root, ".hv", "config.json"))
	str := func(key string) string {
		v, _ := config.Lookup(cfg, key)
		s, _ := v.(string)
		return s
	}
	in.Dispatch, in.IssuesProvider = str("work.dispatch"), str("issues.provider")
	in.CodexHomes = codexHomes(root)
	if raw, _ := config.Lookup(cfg, "work.accounts"); raw != nil {
		list, _ := raw.([]any)
		for _, e := range list {
			if o, ok := e.(*jsonx.Object); ok {
				a := doctor.Account{}
				if v, ok := o.Get("name"); ok {
					a.Name, _ = v.(string)
				}
				if v, ok := o.Get("configDir"); ok {
					a.ConfigDir, _ = v.(string)
				}
				if a.Name != "" {
					in.Accounts = append(in.Accounts, a)
				}
			}
		}
	}
	in.ProjectRoot = root
	if on, err := hook.BoolKey(cfg, "orchestrator.switchOnUsage"); err == nil {
		in.SwitchOnUsage = on
	}
	for _, a := range in.Accounts {
		if a.ConfigDir != "" {
			in.ConfigDirs = append(in.ConfigDirs, a.ConfigDir)
		}
	}
	if len(in.ConfigDirs) == 0 {
		if d := os.Getenv("CLAUDE_CONFIG_DIR"); d != "" {
			in.ConfigDirs = []string{d}
		} else if in.Home != "" {
			in.ConfigDirs = []string{filepath.Join(in.Home, ".claude")}
		}
	}
	return in
}

// doctorLook finds a tool on pathOverride when set, else on PATH.
func doctorLook(pathOverride string) func(string) (string, bool) {
	return func(name string) (string, bool) {
		if pathOverride == "" {
			p, err := exec.LookPath(name)
			return p, err == nil
		}
		for _, dir := range filepath.SplitList(pathOverride) {
			p := filepath.Join(dir, name)
			if fi, err := os.Stat(p); err == nil && fi.Mode().IsRegular() && fi.Mode().Perm()&0o111 != 0 {
				return p, true
			}
		}
		return "", false
	}
}

func doctorExec(ctx context.Context, bin string, args, extraEnv []string, dir string) (doctor.Result, error) {
	ctx, cancel := context.WithTimeout(ctx, doctorCallTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), extraEnv...)
	var out, errb strings.Builder
	cmd.Stdout, cmd.Stderr = &out, &errb
	err := cmd.Run()
	r := doctor.Result{Stdout: out.String(), Stderr: errb.String()}
	if ee, ok := err.(*exec.ExitError); ok {
		r.ExitCode = ee.ExitCode()
		return r, nil
	}
	return r, err
}

// codexHomes lists the slot homes that exist under <git-common-dir>/hv/codex/,
// sorted by slot name. Any failure reads as none: the check then has no home
// to look at, and git trouble is the git check's to report.
func codexHomes(root string) []doctor.CodexHome {
	cd, err := worker.CommonDir(context.Background(), worker.ExecGit, root)
	if err != nil {
		return nil
	}
	entries, err := os.ReadDir(worker.CodexHomesDir(cd))
	if err != nil {
		return nil
	}
	var homes []doctor.CodexHome
	for _, e := range entries {
		if e.IsDir() {
			homes = append(homes, doctor.CodexHome{Slot: e.Name(), Dir: filepath.Join(worker.CodexHomesDir(cd), e.Name())})
		}
	}
	return homes
}
