package round

import (
	"context"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/backlog"
	"github.com/l4ci/hv-skills/v5/internal/milestone"
	"github.com/l4ci/hv-skills/v5/internal/roundcfg"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

// Candidate is an item a round could assign, with its readiness.
type Candidate struct {
	ID, Title, Milestone string
	Readiness
}

// CandidateOpts selects the set.
type CandidateOpts struct {
	Scope string   // slate, milestone or next
	Slate []string // the approved items, for slate
	// Shared are the round.sharedPaths globs the overlap check ignores.
	Shared []string
}

// Candidates lists the open items the scope allows that no slot holds, in
// backlog order, each with its readiness. Scope slate is the slate and
// nothing else. Milestone is the items of the active milestones. Next is the
// same, and when none is left to assign, the items of the first planned
// milestone whose dependencies are all shipped.
func (e Env) Candidates(ctx context.Context, root string, be backlog.Backend, o CandidateOpts) ([]Candidate, error) {
	items, err := be.List(false)
	if err != nil {
		return nil, err
	}
	held := map[string]bool{}
	for _, s := range worker.LoadRegistry(root).Slots() {
		if id := heldID(worker.Str(s, "task"), worker.Str(s, "branch"), worker.Str(s, "name")); id != "" {
			held[id] = true
		}
	}
	pick := func(in func(backlog.Item) bool) []backlog.Item {
		var out []backlog.Item
		for _, it := range items {
			if !it.Closed && !held[it.ID] && in(it) {
				out = append(out, it)
			}
		}
		return out
	}
	inMilestones := func(ids []string) func(backlog.Item) bool {
		want := map[string]bool{}
		for _, id := range ids {
			want[id] = true
		}
		return func(it backlog.Item) bool {
			for _, m := range backlog.ParseMilestones(it.Fields.Get("milestone")) {
				if want[m] {
					return true
				}
			}
			return false
		}
	}

	var chosen []backlog.Item
	switch o.Scope {
	case roundcfg.ScopeSlate:
		in := map[string]bool{}
		for _, id := range o.Slate {
			in[strings.ToUpper(strings.TrimPrefix(id, "#"))] = true
		}
		chosen = pick(func(it backlog.Item) bool { return in[strings.ToUpper(it.ID)] })
	case roundcfg.ScopeMilestone, roundcfg.ScopeNext:
		active, err := milestone.Active(root)
		if err != nil {
			return nil, err
		}
		chosen = pick(inMilestones(active))
		if len(chosen) == 0 && o.Scope == roundcfg.ScopeNext {
			all, err := milestone.List(root)
			if err != nil {
				return nil, err
			}
			for _, m := range all {
				if m.Status == "planned" && m.Ready {
					chosen = pick(inMilestones([]string{m.ID}))
					break
				}
			}
		}
	default:
		return nil, &worker.Error{Exit: worker.ExitUsage, Message: "scope must be slate, milestone or next"}
	}

	tracked := e.trackedFiles(ctx, root)
	inFlight := e.InFlightItems(ctx, root, be, tracked, o.Shared)
	var out []Candidate
	for _, it := range chosen {
		r, err := Assess(be, it.ID, tracked, o.Shared, inFlight, false)
		if err != nil {
			return nil, err
		}
		ms := backlog.ParseMilestones(it.Fields.Get("milestone"))
		c := Candidate{ID: it.ID, Title: it.Title, Readiness: r}
		if len(ms) > 0 {
			c.Milestone = strings.Join(ms, ",")
		}
		out = append(out, c)
	}
	return out, nil
}

func (e Env) trackedFiles(ctx context.Context, root string) []string {
	out, _, code, err := e.Git(ctx, root, "ls-files")
	if err != nil || code != 0 {
		return nil
	}
	var files []string
	for _, l := range strings.Split(out, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			files = append(files, l)
		}
	}
	return files
}
