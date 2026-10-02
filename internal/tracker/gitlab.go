package tracker

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// GitLab is the glab adapter. glab has no close reason, so a not-planned
// close adds NotPlannedLabel and reads it back as the state reason.
type GitLab struct {
	base
	NotPlannedLabel string
	me              string
}

type glIssue struct {
	IID         int                         `json:"iid"`
	Title       string                      `json:"title"`
	Description string                      `json:"description"`
	Labels      []string                    `json:"labels"`
	Milestone   *struct{ Title string }     `json:"milestone"`
	State       string                      `json:"state"`
	ClosedAt    string                      `json:"closed_at"`
	WebURL      string                      `json:"web_url"`
	Assignees   []struct{ Username string } `json:"assignees"`
	Notes       []glNote                    `json:"notes"`
}

type glNote struct {
	ID     json.RawMessage            `json:"id"`
	Body   string                     `json:"body"`
	System bool                       `json:"system"`
	Author *struct{ Username string } `json:"author"`
}

func (n glNote) comment() Comment {
	c := Comment{ID: idText(n.ID), Body: n.Body}
	if n.Author != nil {
		c.Author = n.Author.Username
	}
	return c
}

func (g *GitLab) norm(d glIssue) Issue {
	is := Issue{Number: d.IID, Title: d.Title, Body: d.Description, State: "open", ClosedAt: d.ClosedAt, URL: d.WebURL,
		Labels: append([]string{}, d.Labels...), Assignees: []string{}}
	if d.Milestone != nil {
		is.Milestone = d.Milestone.Title
	}
	if d.State == "closed" {
		is.State, is.StateReason = "closed", "completed"
		for _, l := range d.Labels {
			if l == g.NotPlannedLabel {
				is.StateReason = "not_planned"
			}
		}
	}
	for _, a := range d.Assignees {
		is.Assignees = append(is.Assignees, a.Username)
	}
	return is
}

func (g *GitLab) Create(title, body string, labels []string, milestone string) (int, error) {
	args := []string{"issue", "create", "--title", title, "--description", body}
	if len(labels) > 0 {
		args = append(args, "--label", strings.Join(labels, ","))
	}
	if milestone != "" {
		args = append(args, "--milestone", milestone)
	}
	out, err := g.run(append(args, "-y"), "")
	if err != nil {
		return 0, err
	}
	return numberFromURL(out)
}

// EnsureLabels is a no-op: GitLab creates labels on first use.
func (g *GitLab) EnsureLabels(names []string, autoCreate bool) error { return nil }

func (g *GitLab) AddLabels(number int, labels []string, autoCreate bool) error {
	return g.addLabels(g, number, labels, autoCreate)
}

func (g *GitLab) RemoveLabels(number int, labels []string) error {
	return g.removeLabels(g, number, labels)
}

func (g *GitLab) FindMilestone(hvID string) (string, bool, error) {
	ms, err := g.milestones("projects/:id/milestones?per_page=100")
	if err != nil {
		return "", false, err
	}
	t, ok := matchMilestone(ms, hvID)
	return t, ok, nil
}

// Milestones numbers each milestone by its API id (what PUT
// .../milestones/<id> takes).
func (g *GitLab) Milestones(state string) ([]Milestone, error) {
	want := map[string]string{"open": "&state=active", "closed": "&state=closed"}[state]
	return g.milestones("projects/:id/milestones?per_page=100" + want)
}

func (g *GitLab) milestones(path string) ([]Milestone, error) {
	var raw []rawMilestone
	if err := g.pages(path, &raw); err != nil {
		return nil, err
	}
	out := []Milestone{}
	for _, r := range raw {
		out = append(out, r.norm(r.ID))
	}
	return out, nil
}

func (g *GitLab) CreateMilestone(title, description string) (int, error) {
	var d struct{ ID json.RawMessage }
	if err := g.json([]string{"api", "-X", "POST", "projects/:id/milestones",
		"-f", "title=" + title, "-f", "description=" + description}, &d); err != nil {
		return 0, err
	}
	n, ok := intOf(d.ID)
	if !ok {
		return 0, failed("cannot parse milestone id from: %q", clip(string(d.ID)))
	}
	return n, nil
}

func (g *GitLab) EditMilestone(number int, e MilestoneEdit) error {
	args := []string{"api", "-X", "PUT", fmt.Sprintf("projects/:id/milestones/%d", number)}
	if e.Title != nil {
		args = append(args, "-f", "title="+*e.Title)
	}
	if e.Description != nil {
		args = append(args, "-f", "description="+*e.Description)
	}
	if e.State != nil {
		ev := "activate"
		if *e.State == "closed" {
			ev = "close"
		}
		args = append(args, "-f", "state_event="+ev)
	}
	_, err := g.run(args, "")
	return err
}

func (g *GitLab) IssuesInMilestone(title, state string) ([]Issue, error) {
	if state == "" {
		state = "all"
	}
	return g.List(ListFilter{State: state, Milestone: title})
}

func (g *GitLab) Get(number int, withComments bool) (Issue, error) {
	args := []string{"issue", "view", strconv.Itoa(number), "--output", "json"}
	if withComments {
		args = append(args, "--comments")
	}
	var d glIssue
	if err := g.json(args, &d); err != nil {
		return Issue{}, err
	}
	is := g.norm(d)
	if withComments {
		is.Comments = []Comment{}
		for _, n := range d.Notes {
			is.Comments = append(is.Comments, n.comment())
		}
	}
	return is, nil
}

func (g *GitLab) List(f ListFilter) ([]Issue, error) {
	args := []string{"issue", "list", "--output", "json"}
	switch f.State {
	case "all":
		args = append(args, "--all")
	case "closed":
		args = append(args, "--closed")
	}
	for _, l := range f.Labels {
		args = append(args, "--label", l)
	}
	if f.Milestone != "" {
		args = append(args, "--milestone", f.Milestone)
	}
	var raw []glIssue
	if err := g.json(args, &raw); err != nil {
		return nil, err
	}
	out := []Issue{}
	for _, d := range raw {
		out = append(out, g.norm(d))
	}
	return out, nil
}

func (g *GitLab) Edit(number int, e IssueEdit) error {
	args := []string{"issue", "update", strconv.Itoa(number)}
	if e.Title != nil {
		args = append(args, "--title", *e.Title)
	}
	if e.Body != nil {
		args = append(args, "--description", *e.Body)
	}
	if len(e.AddLabels) > 0 {
		args = append(args, "--label", strings.Join(e.AddLabels, ","))
	}
	if len(e.RemoveLabels) > 0 {
		args = append(args, "--unlabel", strings.Join(e.RemoveLabels, ","))
	}
	if e.Milestone != "" {
		args = append(args, "--milestone", e.Milestone)
	} else if e.RemoveMilestone {
		// glab has no remove flag; an empty title clears the milestone.
		args = append(args, "--milestone", "")
	}
	_, err := g.run(args, "")
	return err
}

// Comments returns the comments oldest first, system notes excluded.
func (g *GitLab) Comments(number int) ([]Comment, error) {
	var raw []glNote
	if err := g.pages(fmt.Sprintf("projects/:id/issues/%d/notes?sort=asc&order_by=created_at", number), &raw); err != nil {
		return nil, err
	}
	out := []Comment{}
	for _, n := range raw {
		if !n.System {
			out = append(out, n.comment())
		}
	}
	return out, nil
}

func (g *GitLab) AddComment(number int, body string) (string, error) {
	return g.createdID([]string{"api", "-X", "POST", fmt.Sprintf("projects/:id/issues/%d/notes", number), "-f", "body=" + body})
}

func (g *GitLab) EditComment(number int, commentID, body string) error {
	_, err := g.run([]string{"api", "-X", "PUT", fmt.Sprintf("projects/:id/issues/%d/notes/%s", number, commentID), "-f", "body=" + body}, "")
	return err
}

func (g *GitLab) DeleteComment(number int, commentID string) error {
	_, err := g.run([]string{"api", "-X", "DELETE", fmt.Sprintf("projects/:id/issues/%d/notes/%s", number, commentID)}, "")
	return err
}

func (g *GitLab) Close(number int, reason, comment string) error {
	n := strconv.Itoa(number)
	if comment != "" {
		if _, err := g.run([]string{"issue", "note", n, "-m", comment}, ""); err != nil {
			return err
		}
	}
	if reason == "not_planned" {
		if err := g.AddLabels(number, []string{g.NotPlannedLabel}, true); err != nil {
			return err
		}
	}
	_, err := g.run([]string{"issue", "close", n}, "")
	return err
}

func (g *GitLab) Reopen(number int) error {
	if _, err := g.run([]string{"issue", "reopen", strconv.Itoa(number)}, ""); err != nil {
		return err
	}
	return g.RemoveLabels(number, []string{g.NotPlannedLabel})
}

// AssignSelf adds the authenticated user without replacing other assignees.
// glab documents --assignee as usernames (no @me), so the username is
// resolved once per adapter.
func (g *GitLab) AssignSelf(number int) error {
	if g.me == "" {
		var u struct {
			Username string `json:"username"`
		}
		if err := g.json([]string{"api", "user"}, &u); err != nil {
			return err
		}
		if u.Username == "" {
			return failed("cannot resolve the authenticated GitLab username")
		}
		g.me = u.Username
	}
	_, err := g.run([]string{"issue", "update", strconv.Itoa(number), "--assignee", "+" + g.me}, "")
	return err
}

func (g *GitLab) OpenPRs() ([]PR, error) {
	var raw []struct {
		IID          int    `json:"iid"`
		Title        string `json:"title"`
		Description  string `json:"description"`
		SourceBranch string `json:"source_branch"`
		WebURL       string `json:"web_url"`
	}
	if err := g.json([]string{"mr", "list", "--output", "json"}, &raw); err != nil {
		return nil, err
	}
	out := []PR{}
	for _, d := range raw {
		out = append(out, PR{Number: d.IID, Title: d.Title, Branch: d.SourceBranch, URL: d.WebURL, Body: d.Description})
	}
	return out, nil
}

func (g *GitLab) PRsClosing(number int) ([]PR, error) { return g.prsClosing(g, number) }

func (g *GitLab) PRCheckout(pr int) error {
	_, err := g.run([]string{"mr", "checkout", strconv.Itoa(pr)}, "")
	return err
}

func (g *GitLab) PRMerge(pr int) (string, error) {
	if _, err := g.run([]string{"mr", "merge", strconv.Itoa(pr), "--yes", "--remove-source-branch"}, ""); err != nil {
		return "", err
	}
	var d struct {
		MergeCommitSHA string `json:"merge_commit_sha"`
	}
	if err := g.json([]string{"mr", "view", strconv.Itoa(pr), "--output", "json"}, &d); err != nil {
		return "", err
	}
	if d.MergeCommitSHA == "" {
		return "", failed("cannot read the merge commit of MR %d", pr)
	}
	return d.MergeCommitSHA, nil
}

func (g *GitLab) PRComment(pr int, body string) error {
	_, err := g.run([]string{"mr", "note", strconv.Itoa(pr), "--message", body}, "")
	return err
}

func (g *GitLab) PRState(pr int) (string, error) {
	var d struct {
		State string `json:"state"`
	}
	if err := g.json([]string{"mr", "view", strconv.Itoa(pr), "--output", "json"}, &d); err != nil {
		return "", err
	}
	st := strings.ToLower(d.State)
	if st == "opened" {
		st = "open"
	}
	return st, nil
}
