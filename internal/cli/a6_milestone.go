package cli

import (
	"flag"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	ms "github.com/l4ci/hv-skills/v5/internal/milestone"
)

// Glue for the milestone group (A6). File mode only; issue mode exits 71
// until the tracker is wired in.

func milestoneCommands() []*Command {
	return []*Command{
		{Name: "milestone", Summary: "vision milestones", Subs: []*Command{
			{Name: "add", Summary: "mint a milestone", Verb: milestoneAdd},
			{Name: "list", Summary: "list milestones", Verb: noFlags(runMilestoneList)},
			{Name: "show", Summary: "print a milestone", Verb: noFlags(runMilestoneShow)},
			{Name: "put", Summary: "replace a milestone's text", Verb: milestonePut},
			{Name: "status", Summary: "change a milestone's status", Verb: milestoneStatus},
			{Name: "active", Summary: "IDs of active milestones", Verb: noFlags(runMilestoneActive)},
			{Name: "index", Summary: "regenerate the overview and vision block", Verb: noFlags(runMilestoneIndex)},
		}},
	}
}

func milestoneAdd(fs *flag.FlagSet) RunFunc {
	title := fs.String("title", "", "milestone title")
	summary := fs.String("summary", "", "one-paragraph summary")
	depends := fs.String("depends", "", "comma list of milestone IDs this depends on")
	return func(c *Ctx, args []string) (Result, error) {
		if err := noArgs(args); err != nil {
			return Result{}, err
		}
		if *title == "" || *summary == "" {
			return Result{}, Usage("--title and --summary are required")
		}
		root, err := fileRoot(c, false)
		if err != nil {
			return Result{}, err
		}
		id, err := ms.Add(root, *title, *summary, *depends)
		if err != nil {
			return Result{}, fromArtifact(err)
		}
		d := jsonx.NewObject()
		d.Set("id", id)
		d.Set("changed", true)
		return Result{Data: d, Text: id}, nil
	}
}

func runMilestoneList(c *Ctx, args []string) (Result, error) {
	if err := noArgs(args); err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, false)
	if err != nil {
		return Result{}, err
	}
	list, err := ms.List(root)
	if err != nil {
		return Result{}, err
	}
	rows, text := []any{}, ""
	for _, m := range list {
		o := jsonx.NewObject()
		o.Set("id", m.ID)
		o.Set("title", m.Title)
		o.Set("status", m.Status)
		deps := make([]any, len(m.Depends))
		for i, d := range m.Depends {
			deps[i] = d
		}
		o.Set("depends", deps)
		o.Set("ready", m.Ready)
		rows = append(rows, o)
		text += m.ID + "\t" + m.Status + "\t" + m.Title + "\n"
	}
	d := jsonx.NewObject()
	d.Set("milestones", rows)
	return Result{Data: d, Text: text}, nil
}

func runMilestoneShow(c *Ctx, args []string) (Result, error) {
	id, err := oneArg(args, "milestone ID")
	if err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, false)
	if err != nil {
		return Result{}, err
	}
	body, err := ms.Show(root, id)
	if err != nil {
		return Result{}, fromArtifact(err)
	}
	d := jsonx.NewObject()
	d.Set("id", id)
	d.Set("body", body)
	return Result{Data: d, Text: body}, nil
}

func milestonePut(fs *flag.FlagSet) RunFunc {
	file := bodyFlag(fs)
	return func(c *Ctx, args []string) (Result, error) {
		id, err := oneArg(args, "milestone ID")
		if err != nil {
			return Result{}, err
		}
		if !ms.ValidID(id) {
			return Result{}, Usage("milestone ID must match M\\d{2,} (e.g. M01, M03), got %q", id)
		}
		text, err := readBody(c, *file)
		if err != nil {
			return Result{}, err
		}
		root, err := fileRoot(c, false)
		if err != nil {
			return Result{}, err
		}
		changed, err := ms.Put(root, id, text)
		if err != nil {
			return Result{Data: blocked(err, "id mismatch"), Text: ""}, fromArtifact(err)
		}
		d := jsonx.NewObject()
		d.Set("id", id)
		d.Set("changed", changed)
		return Result{Data: d, Text: id}, nil
	}
}

// blocked is the exit-4 failure data for a refusal that is not "exists".
func blocked(err error, by string) any {
	if ae := asArtifact(err); ae != nil && ae.Exit == 4 {
		d := jsonx.NewObject()
		d.Set("blockedBy", by)
		d.Set("changed", false)
		return d
	}
	return nil
}

func milestoneStatus(fs *flag.FlagSet) RunFunc {
	to := fs.String("to", "", "planned, active, shipped or archived")
	return func(c *Ctx, args []string) (Result, error) {
		id, err := oneArg(args, "milestone ID")
		if err != nil {
			return Result{}, err
		}
		if !ms.ValidStatus(*to) {
			return Result{}, Usage("--to must be one of: %s", strings.Join(ms.Statuses, ", "))
		}
		root, err := fileRoot(c, false)
		if err != nil {
			return Result{}, err
		}
		changed, err := ms.SetStatus(root, id, *to)
		if err != nil {
			return Result{}, fromArtifact(err)
		}
		d := jsonx.NewObject()
		d.Set("id", id)
		d.Set("status", *to)
		d.Set("changed", changed)
		return Result{Data: d, Text: id + " " + *to}, nil
	}
}

func runMilestoneActive(c *Ctx, args []string) (Result, error) {
	if err := noArgs(args); err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, false)
	if err != nil {
		return Result{}, err
	}
	ids, err := ms.Active(root)
	if err != nil {
		return Result{}, err
	}
	rows := make([]any, len(ids))
	for i, id := range ids {
		rows[i] = id
	}
	d := jsonx.NewObject()
	d.Set("ids", rows)
	return Result{Data: d, Text: strings.Join(ids, "\n")}, nil
}

func runMilestoneIndex(c *Ctx, args []string) (Result, error) {
	if err := noArgs(args); err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, false)
	if err != nil {
		return Result{}, err
	}
	changed, err := ms.Index(root)
	if err != nil {
		return Result{}, fromArtifact(err)
	}
	d := jsonx.NewObject()
	d.Set("changed", changed)
	return Result{Data: d}, nil
}
