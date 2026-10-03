package cli

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/config"
	"github.com/l4ci/hv-skills/v5/internal/git"
	"github.com/l4ci/hv-skills/v5/internal/host"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/round"
	"github.com/l4ci/hv-skills/v5/internal/tracker"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

// The C2 verbs `hv round status` and `hv round reconcile`; the assembly and
// the drift rules are internal/round. Tests swap roundEnv for fakes.
var roundEnv = defaultRoundEnv

// defaultRoundEnv wires the real git, host and forge. The host is herdr when
// work.dispatch says so or the process runs inside herdr (rounds are started
// by hand with `herdr worktree create`, whatever the config says), else tmux.
// A host or forge that cannot be built or reached is left nil: the verbs
// report it as unavailable instead of failing.
func defaultRoundEnv(ctx context.Context, root string) round.Env {
	cfg := config.Load(filepath.Join(root, ".hv", "config.json"))
	e := round.Env{Git: worker.ExecGit, Base: "main"}
	if b, ok, err := (git.Repo{Dir: root}).Base(ctx, ""); err == nil && ok {
		e.Base = b
	}
	dispatch, _ := config.Lookup(cfg, "work.dispatch")
	hostKind := "tmux"
	if dispatch == "herdr" || os.Getenv("HERDR_ENV") == "1" {
		hostKind = "herdr"
	}
	h := host.New(hostKind, host.Deps{})
	if err := h.Require(); err != nil {
		e.HostErr = err.Error()
	} else if s, ok := h.(host.Snapshotter); ok {
		e.Snapshot, e.HostName = s.Snapshot, h.Name()
	}
	f, err := tracker.New(ctx, tracker.SettingsFromConfig(cfg), "", root, trackerOptions...)
	if err != nil {
		e.ForgeErr = err.Error()
	} else {
		e.Forge = f
	}
	return e
}

func roundStatus(*flag.FlagSet) RunFunc {
	return func(c *Ctx, args []string) (Result, error) {
		if err := noArgs(args); err != nil {
			return Result{}, err
		}
		root, err := c.Root()
		if err != nil {
			return Result{}, err
		}
		ctx := c.Context()
		rep, err := roundEnv(ctx, root).Status(ctx, root)
		if err != nil {
			return Result{}, fromWorker(err)
		}
		for _, w := range rep.Warnings {
			c.Warn("%s", w)
		}
		d := jsonx.NewObject()
		d.Set("slots", rowList(rep.Rows))
		d.Set("drift", len(rep.Findings))
		d.Set("unavailable", strs(rep.Unavailable))
		if rep.Host != "" {
			d.Set("host", rep.Host)
		}
		esc, escLines := escalationRows(rep.Escalations)
		d.Set("escalations", esc)
		var lines []string
		for _, r := range rep.Rows {
			lines = append(lines, strings.Join([]string{
				r.Name, dash(r.Issue), dash(r.Branch), dash(r.PR), dash(r.HostState), dash(strings.Join(r.Drift, ","))}, "\t"))
		}
		for _, l := range escLines {
			lines = append(lines, "escalation\t"+l)
		}
		return Result{Data: d, Text: strings.Join(lines, "\n")}, nil
	}
}

func roundReconcile(fs *flag.FlagSet) RunFunc {
	apply := fs.Bool("apply", false, "make the safe repairs (default: report only)")
	return func(c *Ctx, args []string) (Result, error) {
		if err := noArgs(args); err != nil {
			return Result{}, err
		}
		root, err := c.Root()
		if err != nil {
			return Result{}, err
		}
		ctx := c.Context()
		out, err := roundEnv(ctx, root).Reconcile(ctx, root, *apply)
		if err != nil {
			return Result{}, fromWorker(err)
		}
		for _, w := range out.Report.Warnings {
			c.Warn("%s", w)
		}
		d := jsonx.NewObject()
		d.Set("drift", findingList(out.Drift))
		d.Set("repaired", findingList(out.Repaired))
		d.Set("clean", out.Clean())
		d.Set("unavailable", strs(out.Report.Unavailable))
		d.Set("changed", len(out.Repaired) > 0)
		esc, escLines := escalationRows(out.Report.Escalations)
		d.Set("escalations", esc)
		var lines []string
		for _, f := range out.Drift {
			lines = append(lines, fmt.Sprintf("drift\t%s\t%s\t%s", f.Kind, dash(firstOf(f.Slot, "#"+f.Issue)), f.Detail))
		}
		for _, f := range out.Repaired {
			lines = append(lines, fmt.Sprintf("repaired\t%s\t%s\t%s", f.Kind, dash(firstOf(f.Slot, "#"+f.Issue)), f.Repair))
		}
		for _, l := range escLines {
			lines = append(lines, "escalation\t"+l)
		}
		return Result{Data: d, Text: strings.Join(lines, "\n")}, nil
	}
}

func rowList(rows []round.Row) []any {
	out := make([]any, 0, len(rows))
	for _, r := range rows {
		o := jsonx.NewObject()
		o.Set("name", r.Name)
		setIf(o, "agent", r.Agent)
		setIf(o, "issue", r.Issue)
		o.Set("branch", r.Branch)
		setIf(o, "pr", r.PR)
		setIf(o, "prState", r.PRState)
		setIf(o, "hostState", r.HostState)
		setIf(o, "tab", r.Tab)
		o.Set("registered", r.Registered)
		o.Set("drift", strs(r.Drift))
		o.Set("escalations", strs(r.Escalations))
		setIf(o, "kind", r.Kind)
		setIf(o, "tier", r.Tier)
		setIf(o, "model", r.Model)
		setIf(o, "tierReason", r.TierReason)
		out = append(out, o)
	}
	return out
}

func findingList(fs []round.Finding) []any {
	out := make([]any, 0, len(fs))
	for _, f := range fs {
		o := jsonx.NewObject()
		o.Set("kind", f.Kind)
		setIf(o, "slot", f.Slot)
		setIf(o, "issue", f.Issue)
		o.Set("detail", f.Detail)
		setIf(o, "repair", f.Repair)
		out = append(out, o)
	}
	return out
}

func setIf(o *jsonx.Object, k, v string) {
	if v != "" {
		o.Set(k, v)
	}
}

func strs(l []string) []any {
	out := make([]any, 0, len(l))
	for _, s := range l {
		out = append(out, s)
	}
	return out
}

func dash(s string) string {
	if s == "" || s == "#" {
		return "-"
	}
	return s
}

func firstOf(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
