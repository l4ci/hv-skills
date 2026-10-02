package cli

import (
	"flag"
	"strconv"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/artifact"
	"github.com/l4ci/hv-skills/v5/internal/config"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/plan"
	"github.com/l4ci/hv-skills/v5/internal/proof"
)

// Glue for the proof group and plan uncertain, which read items through
// internal/backlog. File mode only for now; issue mode exits 71.

func proofCommands() []*Command {
	return []*Command{
		{Name: "proof", Summary: "verification proof rows on items", Subs: []*Command{
			{Name: "add", Summary: "append a proof row", Verb: proofAdd},
			{Name: "show", Summary: "list an item's proof rows", Verb: proofShow},
		}},
	}
}

// backlogRoot is the project root for a verb that reads the backlog. An
// invalid backlog.backend is an internal error (exit 70, as the old helpers
// exited 1 on it); issue mode is not ported yet (71).
func backlogRoot(c *Ctx) (string, error) {
	root, err := c.Root()
	if err != nil {
		return "", err
	}
	name, err := config.Backend(config.Load(root + "/.hv/config.json"))
	if err != nil {
		return "", &Error{Exit: ExitInternal, Message: err.Error()}
	}
	if name == "issues" {
		return "", fromArtifact(artifact.ErrIssueMode(c.Path))
	}
	return root, nil
}

func proofData(id string, changed any) *jsonx.Object {
	d := jsonx.NewObject()
	d.Set("id", id)
	d.Set("type", id[:1])
	if changed != nil {
		d.Set("changed", changed)
	}
	return d
}

func proofAdd(fs *flag.FlagSet) RunFunc {
	check := fs.String("check", "", "what was checked")
	result := fs.String("result", "", "PASS or FAIL")
	evidence := fs.String("evidence", "", "path or text proving it")
	sha := fs.String("sha", "", "commit the check ran against (default: HEAD)")
	return func(c *Ctx, args []string) (Result, error) {
		id, err := oneArg(args, "item ID")
		if err != nil {
			return Result{}, err
		}
		if strings.TrimSpace(*check) == "" || strings.TrimSpace(*evidence) == "" {
			return Result{}, Usage("--check and --evidence are required")
		}
		if *result != "PASS" && *result != "FAIL" {
			return Result{}, Usage("--result must be exactly PASS or FAIL")
		}
		root, err := backlogRoot(c)
		if err != nil {
			return Result{}, err
		}
		row, changed, err := proof.Add(root, id, proof.AddOpts{Check: *check, Result: *result, Evidence: *evidence, Sha: *sha})
		if err != nil {
			return Result{}, fromArtifact(err)
		}
		d := proofData(id, nil)
		d.Set("check", row.Check)
		d.Set("result", row.Result)
		d.Set("sha", row.Sha)
		d.Set("evidence", row.Evidence)
		d.Set("changed", changed)
		return Result{Data: d, Text: id}, nil
	}
}

func proofShow(fs *flag.FlagSet) RunFunc {
	count := fs.Bool("count", false, "text mode: print only the number of rows")
	return func(c *Ctx, args []string) (Result, error) {
		id, err := oneArg(args, "item ID")
		if err != nil {
			return Result{}, err
		}
		root, err := backlogRoot(c)
		if err != nil {
			return Result{}, err
		}
		rows, lines, err := proof.Show(root, id)
		if err != nil {
			return Result{}, fromArtifact(err)
		}
		out := make([]any, len(rows))
		for i, r := range rows {
			o := jsonx.NewObject()
			o.Set("date", r.Date)
			o.Set("check", r.Check)
			o.Set("result", r.Result)
			o.Set("sha", r.Sha)
			o.Set("evidence", r.Evidence)
			out[i] = o
		}
		d := proofData(id, nil)
		d.Set("count", len(rows))
		d.Set("rows", out)
		text := strings.Join(lines, "\n")
		if *count {
			text = strconv.Itoa(len(rows))
		} else if len(lines) == 0 {
			text = ""
		}
		return Result{Data: d, Text: text}, nil
	}
}

func runPlanUncertain(c *Ctx, args []string) (Result, error) {
	id, err := oneArg(args, "item ID")
	if err != nil {
		return Result{}, err
	}
	root, err := backlogRoot(c)
	if err != nil {
		return Result{}, err
	}
	typ, reasons, err := plan.Uncertain(root, id)
	if err != nil {
		return Result{}, fromArtifact(err)
	}
	rs := make([]any, len(reasons))
	for i, r := range reasons {
		rs[i] = r
	}
	d := jsonx.NewObject()
	d.Set("id", id)
	d.Set("type", typ)
	d.Set("uncertain", len(reasons) > 0)
	d.Set("reasons", rs)
	if len(reasons) == 0 {
		return Result{Data: d}, Failed("%s is certain", id)
	}
	return Result{Data: d, Text: strings.Join(reasons, "\n")}, nil
}
