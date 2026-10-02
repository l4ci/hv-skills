package cli

import (
	"flag"
	"fmt"

	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/version"
)

// Tree is the hv command tree. Groups and verbs are added here as they are
// ported (A4-A8); their flags and --json shapes come from the verb contract (#46).
func Tree() *Command {
	root := &Command{
		Name:    "hv",
		Summary: "hv-skills command line",
		Subs: []*Command{
			{Name: "version", Summary: "print the hv version", Verb: noFlags(runVersion)},
			knowledgeCommands(),
			glossaryCommands(),
			blockCommand(),
			instructionsCommands(),
			decisionsCommands(),
			mapCommands(),
			qaCommands(),
			migrateCommands(),
		},
	}
	root.Subs = append(root.Subs, a6Commands()...)
	root.Subs = append(root.Subs, a4Commands()...)
	root.Subs = append(root.Subs, workerCommands())
	return root
}

// noFlags is the Verb for a verb with no flags of its own.
func noFlags(run RunFunc) func(*flag.FlagSet) RunFunc {
	return func(*flag.FlagSet) RunFunc { return run }
}

func runVersion(c *Ctx, args []string) (Result, error) {
	if len(args) > 0 {
		return Result{}, Usage("version takes no arguments")
	}
	info := version.Get()
	data := jsonx.NewObject()
	data.Set("version", info.Version)
	data.Set("commit", info.Commit)
	data.Set("date", info.Date)
	data.Set("goVersion", info.GoVersion)
	text := "hv " + info.Version
	switch {
	case info.Commit != "" && info.Date != "":
		text += fmt.Sprintf(" (%s, %s)", info.Commit, info.Date)
	case info.Commit != "":
		text += fmt.Sprintf(" (%s)", info.Commit)
	}
	return Result{Data: data, Text: text}, nil
}
