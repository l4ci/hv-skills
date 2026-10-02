package cli

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"strconv"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

// The A7 verbs (worker pool, reset, account, ...) live in internal/worker;
// this file is their glue. Tests swap the package variables below for fakes.
var (
	workerEnv      = func() worker.Env { return worker.Env{} }
	workerAccounts = func() *worker.Accounts { return &worker.Accounts{} }
)

func workerCommands() *Command {
	return &Command{Name: "worker", Summary: "/hv-work worker slots, hosts and accounts", Subs: []*Command{
		{Name: "pool", Summary: "slot registry, worktrees and branches", Subs: []*Command{
			{Name: "init", Summary: "create the slots' worktrees and register them", Verb: poolInit},
			{Name: "list", Summary: "list the registered slots", Verb: noFlags(runPoolList)},
			{Name: "reap", Summary: "remove slots, their worktrees and branches", Verb: poolReap},
		}},
		{Name: "reset", Summary: "refuse a slot that holds work, else cut a fresh task branch", Verb: workerReset},
		{Name: "account", Summary: "per-account usage headroom and slot assignment", Subs: []*Command{
			{Name: "list", Summary: "list accounts with their usage verdict", Verb: noFlags(runAccountList)},
			{Name: "pick", Summary: "name the account with the most headroom", Verb: accountPick},
			{Name: "assign", Summary: "put an account's config dir on a slot", Verb: accountAssign},
		}},
	}}
}

// fromWorker maps a worker.Error onto the exit table.
func fromWorker(err error) error {
	var we *worker.Error
	if errors.As(err, &we) {
		return &Error{Exit: we.Exit, Message: we.Message, Hint: we.Hint}
	}
	return err
}

func slotList(slots []*jsonx.Object) []any {
	out := make([]any, 0, len(slots))
	for _, s := range slots {
		out = append(out, s)
	}
	return out
}

func slotLine(s *jsonx.Object) string {
	return strings.Join([]string{worker.Str(s, "name"), worker.Str(s, "state"), worker.Str(s, "branch"), worker.Str(s, "worktree")}, "\t")
}

func poolInit(fs *flag.FlagSet) RunFunc {
	slots := fs.String("slots", "", "number of slots to create")
	base := fs.String("base", "", "base branch (default: the current branch)")
	session := fs.String("session", "", "host session name (default: hv)")
	return func(c *Ctx, args []string) (Result, error) {
		if err := noArgs(args); err != nil {
			return Result{}, err
		}
		n, err := strconv.Atoi(*slots)
		if *slots == "" || err != nil || n < 1 || strings.TrimLeft(*slots, "0123456789") != "" {
			return Result{}, Usage("--slots must be a positive integer")
		}
		root, err := c.Root()
		if err != nil {
			return Result{}, err
		}
		res, err := workerEnv().PoolInit(context.Background(), root,
			worker.InitOpts{Slots: n, Base: *base, Session: *session}, workerAccounts())
		if err != nil {
			return Result{}, fromWorker(err)
		}
		for _, w := range res.Warnings {
			c.Warn("%s", w)
		}
		d := jsonx.NewObject()
		d.Set("session", res.Session)
		d.Set("base", res.Base)
		d.Set("slots", slotList(res.Slots))
		d.Set("changed", res.Changed)
		var lines []string
		for _, s := range res.Slots {
			lines = append(lines, slotLine(s))
		}
		return Result{Data: d, Text: strings.Join(lines, "\n")}, nil
	}
}

func runPoolList(c *Ctx, args []string) (Result, error) {
	if err := noArgs(args); err != nil {
		return Result{}, err
	}
	root, err := c.Root()
	if err != nil {
		return Result{}, err
	}
	session, round, slots := worker.PoolList(root)
	d := jsonx.NewObject()
	if session != nil {
		d.Set("session", session)
	}
	if round != nil {
		d.Set("round", round)
	}
	d.Set("slots", slotList(slots))
	var lines []string
	for _, s := range slots {
		lines = append(lines, slotLine(s))
	}
	return Result{Data: d, Text: strings.Join(lines, "\n")}, nil
}

func poolReap(fs *flag.FlagSet) RunFunc {
	all := fs.Bool("all", false, "reap every slot")
	return func(c *Ctx, args []string) (Result, error) {
		if (len(args) == 0) == !*all {
			return Result{}, Usage("reap needs slot names or --all, not both")
		}
		root, err := c.Root()
		if err != nil {
			return Result{}, err
		}
		reaped, err := workerEnv().Reap(root, args, *all)
		if err != nil {
			return Result{}, fromWorker(err)
		}
		d := jsonx.NewObject()
		list := make([]any, 0, len(reaped))
		for _, r := range reaped {
			list = append(list, r)
		}
		d.Set("reaped", list)
		d.Set("changed", len(reaped) > 0)
		return Result{Data: d, Text: strings.Join(reaped, "\n")}, nil
	}
}

func resetData(r worker.ResetResult) *jsonx.Object {
	d := jsonx.NewObject()
	d.Set("slot", r.Slot)
	d.Set("clean", r.Clean)
	d.Set("retained", r.Retained)
	if r.Branch != "" {
		d.Set("branch", r.Branch)
	}
	if r.Base != "" {
		d.Set("base", r.Base)
	}
	if r.SHA != "" {
		d.Set("sha", r.SHA)
	}
	if len(r.Dirty) > 0 {
		d.Set("dirty", strList(r.Dirty))
	}
	if len(r.Unmerged) > 0 {
		d.Set("unmerged", strList(r.Unmerged))
	}
	d.Set("changed", r.Changed)
	return d
}

func strList(in []string) []any {
	out := make([]any, 0, len(in))
	for _, s := range in {
		out = append(out, s)
	}
	return out
}

func workerReset(fs *flag.FlagSet) RunFunc {
	task := fs.String("task", "", "task id; names the per-task branch")
	check := fs.Bool("check-only", false, "stop after the guard: exit 0 only when the slot holds no work")
	return func(c *Ctx, args []string) (Result, error) {
		slot, err := oneArg(args, "slot")
		if err != nil {
			return Result{}, err
		}
		root, err := c.Root()
		if err != nil {
			return Result{}, err
		}
		r, err := workerEnv().Reset(root, slot, *task, *check)
		res := Result{Data: resetData(r)}
		if err != nil {
			var we *worker.Error
			if errors.As(err, &we) && we.Data != nil {
				return res, fromWorker(err)
			}
			return Result{}, fromWorker(err)
		}
		switch {
		case r.Retained:
			res.Text = fmt.Sprintf("retry: %s keeps its work on %s (same task %s)", slot, r.Branch, *task)
		case r.Changed:
			res.Text = fmt.Sprintf("reset: %s on %s at %s", slot, r.Branch, r.SHA)
		default:
			res.Text = fmt.Sprintf("%s holds no work", slot)
		}
		return res, nil
	}
}

func accountObject(m worker.Meter) *jsonx.Object {
	o := jsonx.NewObject()
	o.Set("name", m.Name)
	o.Set("configDir", m.ConfigDir)
	o.Set("verdict", m.Verdict)
	o.Set("reason", m.Reason)
	for _, f := range []struct {
		key string
		v   *float64
	}{{"fiveHour", m.FiveHour}, {"sevenDay", m.SevenDay}} {
		if f.v != nil {
			o.Set(f.key, *f.v)
		}
	}
	if m.ResetsAt != nil {
		o.Set("resetsAt", worker.ISOFormat(*m.ResetsAt))
	}
	if m.Headroom != nil {
		o.Set("headroom", *m.Headroom)
	}
	return o
}

func runAccountList(c *Ctx, args []string) (Result, error) {
	if err := noArgs(args); err != nil {
		return Result{}, err
	}
	root, err := c.Root()
	if err != nil {
		return Result{}, err
	}
	rows := workerAccounts().Meters(context.Background(), root)
	list := make([]any, 0, len(rows))
	var lines []string
	for _, m := range rows {
		o := accountObject(m)
		list = append(list, o)
		pct := func(v *float64) string {
			if v == nil {
				return "-"
			}
			return fmt.Sprintf("%.0f%%", *v)
		}
		note := m.Reason
		if note == "" && m.ResetsAt != nil {
			note = worker.ISOFormat(*m.ResetsAt)
		}
		lines = append(lines, fmt.Sprintf("%-12s %-9s 5h=%-5s 7d=%-5s %s", m.Name, m.Verdict, pct(m.FiveHour), pct(m.SevenDay), note))
	}
	if len(rows) == 0 {
		lines = []string{"no accounts configured (slots inherit the ambient CLAUDE_CONFIG_DIR)"}
	}
	d := jsonx.NewObject()
	d.Set("accounts", list)
	return Result{Data: d, Text: strings.Join(lines, "\n")}, nil
}

func accountPick(fs *flag.FlagSet) RunFunc {
	exclude := fs.String("exclude", "", "comma-separated account names to skip")
	return func(c *Ctx, args []string) (Result, error) {
		if err := noArgs(args); err != nil {
			return Result{}, err
		}
		root, err := c.Root()
		if err != nil {
			return Result{}, err
		}
		var skip []string
		for _, n := range strings.Split(*exclude, ",") {
			if strings.TrimSpace(n) != "" {
				skip = append(skip, n)
			}
		}
		name, found := workerAccounts().Pick(context.Background(), root, skip)
		d := jsonx.NewObject()
		d.Set("found", found)
		if !found {
			return Result{Data: d}, Failed("every configured account is cooling down, or none is configured")
		}
		d.Set("account", name)
		return Result{Data: d, Text: name}, nil
	}
}

func accountAssign(fs *flag.FlagSet) RunFunc {
	account := fs.String("account", "", "account name (default: the best pick)")
	return func(c *Ctx, args []string) (Result, error) {
		slot, err := oneArg(args, "slot")
		if err != nil {
			return Result{}, err
		}
		root, err := c.Root()
		if err != nil {
			return Result{}, err
		}
		name, changed, err := workerAccounts().Assign(context.Background(), root, slot, *account)
		if err != nil {
			return Result{}, fromWorker(err)
		}
		d := jsonx.NewObject()
		d.Set("slot", slot)
		d.Set("account", name)
		d.Set("changed", changed)
		return Result{Data: d, Text: fmt.Sprintf("assigned: %s -> %s", slot, name)}, nil
	}
}
