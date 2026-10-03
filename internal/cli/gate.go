package cli

import (
	"errors"
	"flag"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/gate"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// gateCommands is the `hv gate` group (B1, #54).
func gateCommands() *Command {
	return &Command{Name: "gate", Summary: "the manual-gate registry", Subs: []*Command{
		{Name: "list", Summary: "list every manual gate and the verbs that enforce it", Verb: noFlags(gateList)},
	}}
}

func gateList(c *Ctx, args []string) (Result, error) {
	if len(args) > 0 {
		return Result{}, Usage("unexpected argument %q", args[0])
	}
	rows := []any{}
	var lines []string
	for _, g := range gate.Registry {
		o := jsonx.NewObject()
		o.Set("name", g.Name)
		o.Set("enforced", g.Enforced())
		o.Set("verbs", strList(g.Verbs))
		o.Set("skills", strList(g.Skills))
		o.Set("creates", g.Creates)
		rows = append(rows, o)
		by := "skill only"
		if g.Enforced() {
			by = "hv " + strings.Join(g.Verbs, ", hv ")
		}
		lines = append(lines, g.Name+": "+by+" ("+g.Creates+")")
	}
	return Result{Data: gitObj("gates", rows), Text: strings.Join(lines, "\n")}, nil
}

// confirmFlags defines --confirm and --confirm-note on a gated verb's flag
// set. The returned func validates the pair after parsing (exit 2 when one
// comes without the other).
func confirmFlags(fs *flag.FlagSet) func() (gate.Confirm, error) {
	given := fs.Bool("confirm", false, "the human approved this step (manual gate)")
	note := fs.String("confirm-note", "", "the human's answer, quoted as given (required with --confirm)")
	return func() (gate.Confirm, error) {
		c := gate.Confirm{Given: *given, Note: *note}
		if err := c.Validate(); err != nil {
			return c, Usage("%v", err)
		}
		return c, nil
	}
}

// clearGate runs the gate check for a gated verb. On a refusal it returns the
// manual-gate failure data and exit 4; with --confirm it audits the approval
// under the project root, so the caller may act. extra adds fields to the
// failure data (worker gate's own shape).
func clearGate(c *Ctx, name, target string, conf gate.Confirm, paths []string, extra *jsonx.Object) (Result, error) {
	root := ""
	if conf.Given {
		var err error
		if root, err = c.Root(); err != nil {
			return Result{}, err
		}
	}
	verb := strings.TrimPrefix(c.Path, "hv ")
	err := gate.Clear(root, name, verb, target, conf, paths)
	var r *gate.Refused
	switch {
	case errors.As(err, &r):
		d := extra
		if d == nil {
			d = jsonx.NewObject()
		}
		d.Set("blockedBy", "manual gate")
		d.Set("gate", r.Gate)
		if name == gate.MergeApproval {
			d.Set("paths", strList(r.Paths))
		}
		d.Set("changed", false)
		return Result{Data: d}, Refused("%s", r.Error()).WithHint(r.Hint())
	case err != nil:
		return Result{}, err
	}
	return Result{}, nil
}

// mergePolicy loads ship.mergeApproval for a merge verb; a bad value is exit 2.
// Without a .hv/ root there is no config, so the default `none` applies.
func mergePolicy(c *Ctx) (gate.MergePolicy, error) {
	root, err := c.Root()
	if err != nil {
		return gate.MergePolicy{Mode: gate.MergeNone}, nil
	}
	p, err := gate.LoadMergePolicy(root)
	if errors.Is(err, gate.ErrBadMergeMode) {
		return p, Usage("%v", err)
	}
	return p, err
}

// clearMerge applies the merge-approval gate: files lists the merge's changed
// paths and runs only when the policy reads them. A merge the policy does not
// cover passes without an audit line.
func clearMerge(c *Ctx, p gate.MergePolicy, target string, conf gate.Confirm, files func() ([]string, error), extra *jsonx.Object) (Result, error) {
	var changed []string
	if p.NeedsFiles() {
		var err error
		if changed, err = files(); err != nil {
			return Result{}, err
		}
	}
	covered, hit := p.Covers(changed)
	if !covered {
		return Result{}, nil
	}
	return clearGate(c, gate.MergeApproval, target, conf, hit, extra)
}
