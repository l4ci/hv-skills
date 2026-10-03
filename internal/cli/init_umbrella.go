package cli

import (
	"errors"
	"flag"
	"os"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/initproj"
)

// seedBase is the base seeding `hv init` does; `init umbrella` runs it first
// (the old init skill always ran hv-bootstrap before hv-umbrella-init). The
// `hv init` verb sets it, so both share one seed.
var seedBase func(root string) error

// initCommand is the `init` node with its real sub-verbs. It stays a stub
// until the `hv init` verb itself lands; addStubs fills in the rest.
func initCommand() *Command {
	return &Command{Name: "init", Summary: "not ported yet (exit 71)", Stub: true, Verb: stubVerb, Subs: []*Command{
		{Name: "umbrella", Summary: "register the git repos below this directory as an umbrella", Verb: initUmbrella},
	}}
}

func initUmbrella(fs *flag.FlagSet) RunFunc {
	repos := fs.String("repos", "", "comma-separated sub-repo names to register (empty: none)")
	all := fs.Bool("all", false, "register every immediate git child")
	list := fs.Bool("list", false, "only list the candidates; write nothing")
	return func(c *Ctx, args []string) (Result, error) {
		if err := knNoArgs(args); err != nil {
			return Result{}, err
		}
		reposGiven := false
		fs.Visit(func(f *flag.Flag) { reposGiven = reposGiven || f.Name == "repos" })
		root, err := os.Getwd()
		if err != nil {
			return Result{}, err
		}
		if *list {
			if reposGiven || *all {
				return Result{}, Usage("--list takes neither --repos nor --all")
			}
			l, err := initproj.List(root)
			if err != nil {
				return Result{}, Resolution("%v", unwrapPathErr(err))
			}
			return Result{Data: knObj("root", root, "candidates", strSlice(l.Candidates), "isGitRepo", l.IsGitRepo),
				Text: "candidates: " + listOrNone(l.Candidates)}, nil
		}
		if reposGiven == *all {
			return Result{}, Usage("give exactly one of --repos <csv> or --all")
		}
		var names []string
		if reposGiven && *repos != "" {
			names = strings.Split(*repos, ",")
		}
		var seed func() error
		if seedBase != nil {
			seed = func() error { return seedBase(root) }
		}
		res, err := initproj.Umbrella(root, initproj.UmbrellaOptions{All: *all, Names: names}, seed)
		if err != nil {
			if errors.Is(err, initproj.ErrNoCandidates) {
				return Result{}, Resolution("%v", err)
			}
			return Result{}, &Error{Exit: ExitInternal, Message: err.Error()}
		}
		for _, w := range res.Warnings {
			c.Warn("%s", w)
		}
		return Result{
			Data: knObj("root", root, "created", strSlice(res.Created), "registered", strSlice(res.Registered),
				"umbrellaIsGitRepo", res.IsGitRepo, "changed", res.Changed),
			Text: "registered: " + listOrNone(res.Registered),
		}, nil
	}
}

func listOrNone(l []string) string {
	if len(l) == 0 {
		return "none"
	}
	return strings.Join(l, ", ")
}
