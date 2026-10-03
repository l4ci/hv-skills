package cli

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/initproj"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// The `hv init` group (A9): `init` seeds .hv/, `init check` is the preflight.
// They act on the working directory after -C, with no walk-up, because they run
// before a project root exists.

func initCommands() *Command {
	return &Command{Name: "init", Summary: "seed .hv/ in this directory", Verb: initVerb, Subs: []*Command{
		{Name: "check", Summary: "is .hv/ initialized here", Verb: noFlags(initCheck)},
		{Name: "umbrella", Summary: "register the git repos below this directory as an umbrella", Verb: initUmbrella},
	}}
}

// initDir is the directory init acts on: the working directory, symlinks resolved.
func initDir() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", Resolution("cannot read the working directory: %v", err)
	}
	return dir, nil
}

func initErr(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, initproj.ErrSeed):
		return &Error{Exit: ExitInternal, Message: strings.TrimPrefix(err.Error(), initproj.ErrSeed.Error()+": ")}
	}
	return knErr(err)
}

func initVerb(fs *flag.FlagSet) RunFunc {
	noBlocks := fs.Bool("no-blocks", false, "seed .hv/ only; skip AGENTS.md and the managed blocks")
	return func(c *Ctx, args []string) (Result, error) {
		if err := knNoArgs(args); err != nil {
			return Result{}, err
		}
		dir, err := initDir()
		if err != nil {
			return Result{}, err
		}
		res, err := initproj.Init(dir)
		if err != nil {
			return Result{}, initErr(err)
		}
		warnings := append([]string{}, res.Warnings...)
		if len(res.Removed) > 0 {
			warnings = append(warnings, "removed the stale .hv/bin mirror: "+strings.Join(res.Removed, ", ")+" (5.0 has no .hv/bin)")
		}
		changed := res.Changed()
		data := knObj("root", dir, "created", strSlice(res.Created))
		var lines []string
		for _, p := range res.Created {
			lines = append(lines, "created: "+p)
		}
		if !*noBlocks {
			b := initproj.Blocks(dir, func() (bool, error) { return initMilestoneIndex(c) })
			changed = changed || b.Changed()
			warnings = append(warnings, b.Warnings...)
			entries := []any{}
			for _, e := range b.Blocks {
				entries = append(entries, knObj("key", e.Key, "status", e.Status, "changed", e.Changed))
				lines = append(lines, fmt.Sprintf("block %s: %s", e.Key, e.Status))
			}
			data.Set("blocks", entries)
			data.Set("instructions", initInstructionsData(b))
		}
		for _, w := range warnings {
			c.Warn("%s", w)
		}
		if len(warnings) > 0 {
			data.Set("warnings", strSlice(warnings))
		}
		data.Set("changed", changed)
		if !changed {
			lines = append(lines, "noop: already initialized")
		}
		return Result{Data: data, Text: strings.Join(lines, "\n")}, nil
	}
}

// initMilestoneIndex runs `milestone index`, which handles issue mode, now
// that init has created the .hv/ it finds the project root by.
func initMilestoneIndex(c *Ctx) (bool, error) {
	res, err := runMilestoneIndex(c, nil)
	if err != nil {
		return false, err
	}
	if o, ok := res.Data.(*jsonx.Object); ok {
		if v, ok := o.Get("changed"); ok {
			b, _ := v.(bool)
			return b, nil
		}
	}
	return false, nil
}

func initInstructionsData(b initproj.BlocksResult) []any {
	acts := []any{}
	for _, a := range b.Instructions {
		o := knObj("action", a.Action, "file", a.File)
		if len(a.Keys) > 0 {
			o.Set("keys", strSlice(a.Keys))
		}
		acts = append(acts, o)
	}
	return acts
}

func initCheck(c *Ctx, args []string) (Result, error) {
	if err := knNoArgs(args); err != nil {
		return Result{}, err
	}
	dir, err := initDir()
	if err != nil {
		return Result{}, err
	}
	res := initproj.Check(dir, func() string { return versionDriftLine(dir) })
	data := knObj("initialized", res.Initialized, "missing", strSlice(res.Missing))
	if !res.Initialized {
		return Result{Data: data}, Failed("not initialized: %s missing", strings.Join(res.Missing, ", ")).WithHint("run: hv init")
	}
	for _, w := range res.Warnings {
		c.Warn("%s", w)
	}
	return Result{Data: data, Text: "initialized"}, nil
}
