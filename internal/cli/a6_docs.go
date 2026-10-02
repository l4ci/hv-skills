package cli

import (
	"flag"
	"os"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/artifact"
	"github.com/l4ci/hv-skills/v5/internal/design"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/plan"
)

// Glue for the design and plan groups (A6). File mode only: issue mode
// needs internal/tracker and the item model, so those calls exit 71.

func docsCommands() []*Command {
	return []*Command{
		{Name: "design", Summary: "per-item design documents", Subs: []*Command{
			{Name: "add", Summary: "create a design stub", Verb: designAdd},
			{Name: "list", Summary: "list designs", Verb: noFlags(runDesignList)},
			{Name: "show", Summary: "print a design", Verb: noFlags(runDesignShow)},
			{Name: "put", Summary: "replace a design's text", Verb: designPut},
			{Name: "rm", Summary: "delete a design", Verb: noFlags(runDesignRm)},
			{Name: "amend", Summary: "amend one section of a design", Verb: designAmend},
		}},
		{Name: "plan", Summary: "milestone and item plans", Subs: []*Command{
			{Name: "add", Summary: "create a plan stub", Verb: planAdd},
			{Name: "list", Summary: "list plans", Verb: planList},
			{Name: "show", Summary: "print a plan", Verb: noFlags(runPlanShow)},
			{Name: "put", Summary: "replace a plan's text", Verb: planPut},
			{Name: "rm", Summary: "delete a plan", Verb: noFlags(runPlanRm)},
			{Name: "validate-docs", Summary: "check doc-by-path deliverables", Verb: noFlags(runPlanValidateDocs)},
			{Name: "rename-check", Summary: "files that mention a name", Verb: noFlags(runPlanRenameCheck)},
			{Name: "uncertain", Summary: "uncertainty pre-flight for an item", Verb: noFlags(func(*Ctx, []string) (Result, error) {
				return Result{}, NotImplemented("hv plan uncertain").WithHint("needs the backlog item model (A4)")
			})},
		}},
	}
}

// fileRoot returns the project root for a file-mode verb. Under issue mode
// it returns the not-ported error, or, for a file-only verb, exit 4.
func fileRoot(c *Ctx, fileOnly bool) (string, error) {
	root, err := c.Root()
	if err != nil {
		return "", err
	}
	if artifact.IssueMode(root) {
		if fileOnly {
			return "", Refused("%s works on the file backend only (backlog.backend is \"issues\")", c.Path)
		}
		return "", fromArtifact(artifact.ErrIssueMode(c.Path))
	}
	return root, nil
}

func bodyFlag(fs *flag.FlagSet) *string {
	return fs.String("body-file", "", "file holding the new text (`-` for stdin)")
}

func readBody(c *Ctx, file string) (string, error) {
	if file == "" {
		return "", Usage("--body-file is required")
	}
	s, err := artifact.ReadBody(c.Stdin, file)
	return s, fromArtifact(err)
}

func idData(id string, changed any) *jsonx.Object {
	d := jsonx.NewObject()
	d.Set("id", id)
	d.Set("type", design.Type(idOr(id)))
	if changed != nil {
		d.Set("changed", changed)
	}
	return d
}

func idOr(id string) string {
	if id == "" {
		return "?"
	}
	return id
}

// ---- design

func designAdd(fs *flag.FlagSet) RunFunc {
	title := fs.String("title", "", "design title")
	return func(c *Ctx, args []string) (Result, error) {
		id, err := oneArg(args, "item ID")
		if err != nil {
			return Result{}, err
		}
		if *title == "" {
			return Result{}, Usage("--title is required")
		}
		if !design.ValidID(id) {
			return Result{}, fromArtifact(design.Add("", id, *title)) // reports the bad ID
		}
		root, err := fileRoot(c, false)
		if err != nil {
			return Result{}, err
		}
		if err := design.Add(root, id, *title); err != nil {
			return Result{Data: refusal(err)}, fromArtifact(err)
		}
		return Result{Data: idData(id, true), Text: id}, nil
	}
}

// refusal is the exit-4 failure data: {"blockedBy": "exists", "changed": false}.
func refusal(err error) any {
	if ae, ok := err.(*artifact.Error); ok && ae.Exit == artifact.ExitRefused {
		d := jsonx.NewObject()
		d.Set("blockedBy", "exists")
		d.Set("changed", false)
		return d
	}
	return nil
}

func runDesignList(c *Ctx, args []string) (Result, error) {
	if err := noArgs(args); err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, true)
	if err != nil {
		return Result{}, err
	}
	list, err := design.List(root)
	if err != nil {
		return Result{}, err
	}
	rows, text := []any{}, ""
	for _, e := range list {
		o := jsonx.NewObject()
		o.Set("id", e.ID)
		o.Set("title", e.Title)
		o.Set("status", e.Status)
		o.Set("created", e.Created)
		rows = append(rows, o)
		text += e.ID + "\t" + e.Status + "\t" + e.Title + "\n"
	}
	d := jsonx.NewObject()
	d.Set("designs", rows)
	return Result{Data: d, Text: text}, nil
}

func runDesignShow(c *Ctx, args []string) (Result, error) {
	id, err := oneArg(args, "item ID")
	if err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, false)
	if err != nil {
		return Result{}, err
	}
	body, err := design.Show(root, id)
	if err != nil {
		return Result{}, fromArtifact(err)
	}
	d := idData(id, nil)
	d.Set("body", body)
	return Result{Data: d, Text: body}, nil
}

func designPut(fs *flag.FlagSet) RunFunc {
	file := bodyFlag(fs)
	return func(c *Ctx, args []string) (Result, error) {
		id, err := oneArg(args, "item ID")
		if err != nil {
			return Result{}, err
		}
		if !design.ValidID(id) {
			_, err := design.Put("", id, "")
			return Result{}, fromArtifact(err)
		}
		text, err := readBody(c, *file)
		if err != nil {
			return Result{}, err
		}
		root, err := fileRoot(c, false)
		if err != nil {
			return Result{}, err
		}
		changed, err := design.Put(root, id, text)
		if err != nil {
			return Result{}, fromArtifact(err)
		}
		return Result{Data: idData(id, changed), Text: id}, nil
	}
}

func runDesignRm(c *Ctx, args []string) (Result, error) {
	id, err := oneArg(args, "item ID")
	if err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, false)
	if err != nil {
		return Result{}, err
	}
	if err := design.Rm(root, id); err != nil {
		return Result{}, fromArtifact(err)
	}
	return Result{Data: idData(id, true), Text: id}, nil
}

func designAmend(fs *flag.FlagSet) RunFunc {
	fs.String("section", "", "heading to amend")
	fs.String("mode", "", "append or replace")
	bodyFlag(fs)
	return func(*Ctx, []string) (Result, error) {
		return Result{}, NotImplemented("hv design amend").WithHint("needs the section package")
	}
}

// ---- plan

func planAdd(fs *flag.FlagSet) RunFunc {
	title := fs.String("title", "", "plan title")
	designID := fs.String("design", "", "design item ID to link")
	repos := fs.String("repos", "", "comma list of sub-repos")
	milestone := fs.String("milestone", "", "milestone for a minted slice key")
	slice := fs.Bool("slice", false, "mint the next S<NN> key for --milestone")
	return func(c *Ctx, args []string) (Result, error) {
		if len(args) > 1 {
			return Result{}, Usage("expected one plan key, got %d arguments", len(args))
		}
		o := plan.AddOpts{Milestone: *milestone, Slice: *slice, Title: *title, Design: *designID, Repos: *repos}
		if len(args) == 1 {
			o.Key = args[0]
		}
		root, err := c.Root()
		if err != nil {
			return Result{}, err
		}
		if artifact.IssueMode(root) {
			// Argument errors stay exit 2 under issue mode; only the write is unported.
			if _, _, err := plan.Add(os.DevNull, o); err != nil {
				if ae, ok := err.(*artifact.Error); ok && ae.Exit == artifact.ExitUsage {
					return Result{}, fromArtifact(err)
				}
			}
			return Result{}, fromArtifact(artifact.ErrIssueMode(c.Path))
		}
		key, kind, err := plan.Add(root, o)
		if err != nil {
			return Result{Data: refusal(err)}, fromArtifact(err)
		}
		d := jsonx.NewObject()
		d.Set("key", key)
		d.Set("unitKind", kind)
		d.Set("changed", true)
		return Result{Data: d, Text: key}, nil
	}
}

func planList(fs *flag.FlagSet) RunFunc {
	milestone := fs.String("milestone", "", "only this milestone's plans")
	return func(c *Ctx, args []string) (Result, error) {
		if err := noArgs(args); err != nil {
			return Result{}, err
		}
		if *milestone != "" && !plan.ValidMilestone(*milestone) {
			return Result{}, Usage("--milestone must look like M01, got %q", *milestone)
		}
		root, err := fileRoot(c, false)
		if err != nil {
			return Result{}, err
		}
		list, err := plan.List(root, *milestone)
		if err != nil {
			return Result{}, err
		}
		rows, text := []any{}, ""
		for _, e := range list {
			o := jsonx.NewObject()
			o.Set("key", e.Key)
			o.Set("milestone", e.Milestone)
			o.Set("unit", e.Unit)
			o.Set("unitKind", e.UnitKind)
			o.Set("title", e.Title)
			o.Set("status", e.Status)
			o.Set("created", e.Created)
			repos := make([]any, len(e.Repos))
			for i, r := range e.Repos {
				repos[i] = r
			}
			o.Set("repos", repos)
			rows = append(rows, o)
			text += e.Key + "\t" + e.Status + "\t" + e.Title + "\n"
		}
		d := jsonx.NewObject()
		d.Set("plans", rows)
		return Result{Data: d, Text: text}, nil
	}
}

func keyData(key string, changed any) *jsonx.Object {
	d := jsonx.NewObject()
	d.Set("key", key)
	if changed != nil {
		d.Set("changed", changed)
	}
	return d
}

func runPlanShow(c *Ctx, args []string) (Result, error) {
	key, err := oneArg(args, "plan key")
	if err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, false)
	if err != nil {
		return Result{}, err
	}
	body, err := plan.Show(root, key)
	if err != nil {
		return Result{}, fromArtifact(err)
	}
	d := keyData(key, nil)
	d.Set("body", body)
	return Result{Data: d, Text: body}, nil
}

func planPut(fs *flag.FlagSet) RunFunc {
	file := bodyFlag(fs)
	return func(c *Ctx, args []string) (Result, error) {
		key, err := oneArg(args, "plan key")
		if err != nil {
			return Result{}, err
		}
		if !plan.ValidKey(key) {
			_, err := plan.Put("", key, "")
			return Result{}, fromArtifact(err)
		}
		text, err := readBody(c, *file)
		if err != nil {
			return Result{}, err
		}
		root, err := fileRoot(c, false)
		if err != nil {
			return Result{}, err
		}
		changed, err := plan.Put(root, key, text)
		if err != nil {
			return Result{}, fromArtifact(err)
		}
		return Result{Data: keyData(key, changed), Text: key}, nil
	}
}

func runPlanRm(c *Ctx, args []string) (Result, error) {
	key, err := oneArg(args, "plan key")
	if err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, false)
	if err != nil {
		return Result{}, err
	}
	if err := plan.Rm(root, key); err != nil {
		return Result{}, fromArtifact(err)
	}
	return Result{Data: keyData(key, true), Text: key}, nil
}

func runPlanValidateDocs(c *Ctx, args []string) (Result, error) {
	key, err := oneArg(args, "plan key")
	if err != nil {
		return Result{}, err
	}
	root, err := fileRoot(c, true)
	if err != nil {
		return Result{}, err
	}
	ms, text, err := plan.ValidateDocs(root, key)
	if err != nil {
		return Result{}, fromArtifact(err)
	}
	rows := []any{}
	for _, m := range ms {
		o := jsonx.NewObject()
		o.Set("path", m.Path)
		if m.TargetRepo != "" {
			o.Set("targetRepo", m.TargetRepo)
		}
		o.Set("issue", m.Issue)
		if m.Suggestion != "" {
			o.Set("suggestion", m.Suggestion)
		}
		rows = append(rows, o)
	}
	d := keyData(key, nil)
	d.Set("valid", len(ms) == 0)
	d.Set("mismatches", rows)
	return Result{Data: d, Text: text}, nil
}

func runPlanRenameCheck(c *Ctx, args []string) (Result, error) {
	if len(args) == 0 {
		return Result{}, Usage("missing <old> name")
	}
	cwd, err := os.Getwd()
	if err != nil {
		return Result{}, err
	}
	files := plan.RenameCheck(cwd, args[0], args[1:])
	rows := make([]any, len(files))
	for i, f := range files {
		rows[i] = f
	}
	d := jsonx.NewObject()
	d.Set("files", rows)
	return Result{Data: d, Text: strings.Join(files, "\n")}, nil
}
