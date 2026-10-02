package cli

import (
	"github.com/l4ci/hv-skills/v5/internal/artifact"
	"github.com/l4ci/hv-skills/v5/internal/backlog"
	"github.com/l4ci/hv-skills/v5/internal/design"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/plan"
	"github.com/l4ci/hv-skills/v5/internal/proof"
)

// The issue-mode halves of the design, plan and proof verbs. They resolve
// the item through the A4 workflow (so "F7", "#7" and "7" all answer "7"
// and an unknown item is exit 3) and keep their text in item notes.

// modeRoot is the project root and whether backlog.backend is "issues".
func modeRoot(c *Ctx) (root string, issue bool, err error) {
	root, err = c.Root()
	if err != nil {
		return "", false, err
	}
	return root, artifact.IssueMode(root), nil
}

// failAny maps a domain error (artifact or backlog) onto the exit table,
// keeping the exit-4 refusal data a duplicate create carries.
func failAny(err error) (Result, error) {
	if ae := asArtifact(err); ae != nil {
		return Result{Data: refusal(err)}, fromArtifact(err)
	}
	return a4Fail(err)
}

func typedData(id, typ string, changed any) *jsonx.Object {
	d := jsonx.NewObject()
	d.Set("id", id)
	d.Set("type", typ)
	if changed != nil {
		d.Set("changed", changed)
	}
	return d
}

// ---- design

func designAddIssue(c *Ctx, id, title string) (Result, error) {
	if !design.ValidIssueID(id) {
		return failAny(design.AddNote(nil, "", id, title))
	}
	_, wf, cid, typ, err := a4Flow(c, id)
	if err != nil {
		return a4Fail(err)
	}
	if err := design.AddNote(wf, id, id, title); err != nil {
		return failAny(err)
	}
	return Result{Data: typedData(cid, typ, true), Text: cid}, nil
}

func designShowIssue(c *Ctx, id string) (Result, error) {
	if !design.ValidIssueID(id) {
		return failAny(errOf(design.ShowNote(nil, "", id)))
	}
	_, wf, cid, typ, err := a4Flow(c, id)
	if err != nil {
		return a4Fail(err)
	}
	body, err := design.ShowNote(wf, id, id)
	if err != nil {
		return failAny(err)
	}
	d := typedData(cid, typ, nil)
	d.Set("body", body)
	return Result{Data: d, Text: body}, nil
}

func designPutIssue(c *Ctx, id, file string) (Result, error) {
	if !design.ValidIssueID(id) {
		return failAny(errOf(design.PutNote(nil, "", id, "")))
	}
	text, err := readBody(c, file)
	if err != nil {
		return Result{}, err
	}
	_, wf, cid, typ, err := a4Flow(c, id)
	if err != nil {
		return a4Fail(err)
	}
	changed, err := design.PutNote(wf, id, id, text)
	if err != nil {
		return failAny(err)
	}
	return Result{Data: typedData(cid, typ, changed), Text: cid}, nil
}

func designRmIssue(c *Ctx, id string) (Result, error) {
	if !design.ValidIssueID(id) {
		return failAny(design.RmNote(nil, "", id))
	}
	_, wf, cid, typ, err := a4Flow(c, id)
	if err != nil {
		return a4Fail(err)
	}
	if err := design.RmNote(wf, id, id); err != nil {
		return failAny(err)
	}
	return Result{Data: typedData(cid, typ, true), Text: cid}, nil
}

// errOf drops a function's value and keeps its error, for the validation-only calls above.
func errOf[T any](_ T, err error) error { return err }

// ---- plan (item plans; slice plans come with the milestone verbs)

var errSliceIssue = func(c *Ctx) error {
	return fromArtifact(artifact.ErrIssueMode(c.Path + " (slice plans)").WithHint("slice plans need the milestone tracking issue"))
}

func planAddIssue(c *Ctx, root string, o plan.AddOpts) (Result, error) {
	if err := plan.CheckAdd(o, true); err != nil {
		return Result{}, fromArtifact(err)
	}
	if o.Key == "" {
		return Result{}, errSliceIssue(c) // minting a slice is the milestone half
	}
	item, isItem, err := plan.ItemOf(o.Key)
	if err != nil {
		return Result{}, fromArtifact(err)
	}
	if !isItem {
		return Result{}, errSliceIssue(c)
	}
	_, wf, _, _, err := a4Flow(c, item)
	if err != nil {
		return a4Fail(err)
	}
	key, err := plan.AddItemNote(root, wf, o)
	if err != nil {
		return failAny(err)
	}
	d := keyData(key, true)
	d.Set("unitKind", "item")
	d.Set("changed", true)
	return Result{Data: orderKey(d), Text: key}, nil
}

// orderKey puts unitKind before changed, as the contract spells the data.
func orderKey(d *jsonx.Object) *jsonx.Object {
	out := jsonx.NewObject()
	for _, k := range []string{"key", "unitKind", "changed"} {
		if v, ok := d.Get(k); ok {
			out.Set(k, v)
		}
	}
	return out
}

// planItem resolves a plan key to its item in issue mode; a slice key is the
// milestone half.
func planItem(c *Ctx, key string) (wf backlog.Workflow, item string, err error) {
	item, isItem, err := plan.ItemOf(key)
	if err != nil {
		return nil, "", fromArtifact(err)
	}
	if !isItem {
		return nil, "", errSliceIssue(c)
	}
	_, wf, _, _, err = a4Flow(c, item)
	return wf, item, err
}

func planShowIssue(c *Ctx, key string) (Result, error) {
	wf, item, err := planItem(c, key)
	if err != nil {
		return a4Fail(err)
	}
	body, err := plan.ShowItemNote(wf, item)
	if err != nil {
		return failAny(err)
	}
	d := keyData(key, nil)
	d.Set("body", body)
	return Result{Data: d, Text: body}, nil
}

func planPutIssue(c *Ctx, key, file string) (Result, error) {
	if !plan.ValidKey(key) {
		return Result{}, fromArtifact(errOf(plan.Put("", key, "")))
	}
	text, err := readBody(c, file)
	if err != nil {
		return Result{}, err
	}
	wf, item, err := planItem(c, key)
	if err != nil {
		return a4Fail(err)
	}
	changed, err := plan.PutItemNote(wf, item, key, text)
	if err != nil {
		return failAny(err)
	}
	return Result{Data: keyData(key, changed), Text: key}, nil
}

func planRmIssue(c *Ctx, key string) (Result, error) {
	wf, item, err := planItem(c, key)
	if err != nil {
		return a4Fail(err)
	}
	if err := plan.RmItemNote(wf, item); err != nil {
		return failAny(err)
	}
	return Result{Data: keyData(key, true), Text: key}, nil
}

// ---- proof

func proofAddIssue(c *Ctx, root, id string, o proof.AddOpts) (Result, error) {
	_, wf, cid, typ, err := a4Flow(c, id)
	if err != nil {
		return a4Fail(err)
	}
	row, changed, err := proof.AddNote(wf, id, root, o)
	if err != nil {
		return failAny(err)
	}
	d := typedData(cid, typ, nil)
	d.Set("check", row.Check)
	d.Set("result", row.Result)
	d.Set("sha", row.Sha)
	d.Set("evidence", row.Evidence)
	d.Set("changed", changed)
	return Result{Data: d, Text: cid}, nil
}

func proofShowIssue(c *Ctx, id string, countOnly bool) (Result, error) {
	_, wf, cid, typ, err := a4Flow(c, id)
	if err != nil {
		return a4Fail(err)
	}
	rows, lines, err := proof.ShowNote(wf, id)
	if err != nil {
		return failAny(err)
	}
	return proofResult(cid, typ, rows, lines, countOnly), nil
}

// ---- plan uncertain

func uncertainIssue(c *Ctx, id string) (Result, error) {
	be, _, _, _, err := a4Flow(c, id)
	if err != nil {
		return a4Fail(err)
	}
	it, err := be.Get(id)
	if err != nil {
		return a4Fail(err)
	}
	typ, reasons, err := plan.UncertainIssue(be, it)
	if err != nil {
		return failAny(err)
	}
	return uncertainResult(it.ID, typ, reasons)
}
