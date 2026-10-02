// Package tracker is the gh/glab layer: one normalized issue and pull-request
// API over both forges, ported from bin/hvlib_tracker.py, and the single place
// the forge CLI runs (CLI.Run, ported from bin/hv-tracker-call), with list
// limits, pagination and bounded rate-limit handling.
//
// Adapters make one CLI round trip per call and cache nothing, except the
// GitLab username that AssignSelf resolves once per adapter.
package tracker

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/config"
)

// Kind classifies a tracker failure for the CLI exit table.
type Kind int

const (
	// KindFailed: the forge CLI ran and failed, or its output did not parse.
	KindFailed Kind = iota
	// KindUnavailable: no provider resolves, the CLI is missing, or it is not
	// authenticated (exit 5 in the 5.0 table, old helper exit 3).
	KindUnavailable
	// KindRateLimited: the forge rate-limited the call (exit 6, old exit 4).
	KindRateLimited
)

// Error is a tracker failure. Code is what the Python TrackerError carried:
// 3 unavailable, 4 rate-limited, the CLI's own exit code when it failed, and 1
// for output that did not parse.
type Error struct {
	Kind    Kind
	Code    int
	Message string
}

func (e *Error) Error() string { return e.Message }

func unavailable(format string, a ...any) *Error {
	return &Error{Kind: KindUnavailable, Code: 3, Message: fmt.Sprintf(format, a...)}
}

func rateLimited(format string, a ...any) *Error {
	return &Error{Kind: KindRateLimited, Code: 4, Message: fmt.Sprintf(format, a...)}
}

func failed(format string, a ...any) *Error {
	return &Error{Kind: KindFailed, Code: 1, Message: fmt.Sprintf(format, a...)}
}

// IsKind reports whether err is a tracker *Error of kind k.
func IsKind(err error, k Kind) bool {
	var e *Error
	return errors.As(err, &e) && e.Kind == k
}

// Issue is the normalized issue. Empty Milestone, StateReason and ClosedAt
// stand for Python's None. Comments is filled only by Get(n, true).
type Issue struct {
	Number      int
	Title       string
	Body        string
	Labels      []string
	Milestone   string
	State       string // open | closed
	StateReason string // completed | not_planned | ""
	ClosedAt    string
	URL         string
	Assignees   []string
	Comments    []Comment
}

// Comment is an issue comment (a GitLab note). ID is the forge's id as text:
// a decimal number, or a GraphQL node id for comments read through gh
// `issue view`.
type Comment struct {
	ID     string
	Body   string
	Author string
}

// Milestone is a native milestone. Number is what the forge's milestone API
// takes: the number on GitHub, the id on GitLab.
type Milestone struct {
	Number      int
	Title       string
	Description string
	State       string // open | closed
}

// PR is an open pull request (GitLab: merge request).
type PR struct {
	Number int
	Title  string
	Branch string
	URL    string
	Body   string
}

// ListFilter selects issues. An empty State means "open".
type ListFilter struct {
	State     string // open | closed | all
	Labels    []string
	Milestone string
}

// IssueEdit is a partial issue update; nil and empty fields are left alone.
type IssueEdit struct {
	Title           *string
	Body            *string
	AddLabels       []string
	RemoveLabels    []string
	Milestone       string
	RemoveMilestone bool
}

// MilestoneEdit renames, re-describes or opens/closes a native milestone.
type MilestoneEdit struct {
	Title       *string
	Description *string
	State       *string // open | closed
}

// Adapter is the normalized API both forges implement.
type Adapter interface {
	Provider() string

	Create(title, body string, labels []string, milestone string) (int, error)
	Get(number int, withComments bool) (Issue, error)
	List(f ListFilter) ([]Issue, error)
	Edit(number int, e IssueEdit) error
	EnsureLabels(names []string, autoCreate bool) error
	AddLabels(number int, labels []string, autoCreate bool) error
	RemoveLabels(number int, labels []string) error
	// Close with reason "completed" (or "") or "not_planned"; comment is optional.
	Close(number int, reason, comment string) error
	Reopen(number int) error
	AssignSelf(number int) error

	Comments(number int) ([]Comment, error)
	AddComment(number int, body string) (string, error)
	EditComment(number int, commentID, body string) error
	DeleteComment(number int, commentID string) error

	// FindMilestone returns the title of the milestone whose leading token is
	// hvID, preferring open ones; ok is false when none matches.
	FindMilestone(hvID string) (title string, ok bool, err error)
	// Milestones lists by state "open", "closed" or "all" (or "").
	Milestones(state string) ([]Milestone, error)
	CreateMilestone(title, description string) (int, error)
	EditMilestone(number int, e MilestoneEdit) error
	IssuesInMilestone(title, state string) ([]Issue, error)

	// ClosedNumbers returns the issue numbers a PR body closes through a
	// closing keyword, in order of first appearance.
	ClosedNumbers(body string) []int
	OpenPRs() ([]PR, error)
	PRsClosing(number int) ([]PR, error)
	PRCheckout(pr int) error
	// PRMerge merges with a merge commit, deletes the source branch and
	// returns the merge commit sha.
	PRMerge(pr int) (string, error)
	PRComment(pr int, body string) error
	// PRState is "open", "merged" or "closed".
	PRState(pr int) (string, error)
}

// Settings are the issues.* config values the tracker reads.
type Settings struct {
	Provider        string // auto | github | gitlab
	RetryWait       time.Duration
	NotPlannedLabel string
}

// SettingsFromConfig reads issues.provider, issues.retryWaitSeconds and
// issues.labels.notPlanned, with the hvlib_config defaults for absent or
// null keys.
func SettingsFromConfig(cfg any) Settings {
	s := Settings{Provider: "auto", RetryWait: 60 * time.Second, NotPlannedLabel: "not-planned"}
	if v, ok := config.Lookup(cfg, "issues.provider"); ok && v != nil {
		s.Provider = fmt.Sprint(v)
	}
	if v, ok := config.Lookup(cfg, "issues.retryWaitSeconds"); ok && v != nil {
		if f, err := strconv.ParseFloat(fmt.Sprint(v), 64); err == nil {
			s.RetryWait = time.Duration(f * float64(time.Second))
		}
	}
	if v, ok := config.Lookup(cfg, "issues.labels.notPlanned"); ok && v != nil {
		s.NotPlannedLabel = fmt.Sprint(v)
	}
	return s
}

// New returns the adapter for provider ("" or "auto" falls back to
// s.Provider, then to origin-URL detection in dir). Every CLI call runs in
// dir ("" is the process cwd); in umbrella mode that is the sub-repo.
func New(s Settings, provider, dir string, opts ...Option) (Adapter, error) {
	c := &CLI{Dir: dir, RetryWait: s.RetryWait}
	for _, o := range opts {
		o(c)
	}
	p, err := c.resolve(provider, s.Provider)
	if err != nil {
		return nil, err
	}
	c.Provider = p
	if p == "github" {
		return &GitHub{base{cli: c, closing: closingGH}}, nil
	}
	return &GitLab{base: base{cli: c, closing: closingGL}, NotPlannedLabel: s.NotPlannedLabel}, nil
}

// Option adjusts the CLI an adapter runs through (tests swap the executor).
type Option func(*CLI)

// WithExec routes every process the adapter starts through x, and resolves
// the CLI binary with lookPath.
func WithExec(x Exec, lookPath func(string) (string, error)) Option {
	return func(c *CLI) { c.Exec, c.LookPath = x, lookPath }
}

// WithSleep replaces the rate-limit wait.
func WithSleep(sleep func(time.Duration)) Option {
	return func(c *CLI) { c.Sleep = sleep }
}

// base holds what both adapters share.
type base struct {
	cli     *CLI
	closing func(string) []int
}

func (b *base) Provider() string { return b.cli.Provider }

func (b *base) ClosedNumbers(body string) []int { return b.closing(body) }

// run makes one call; stdin carries body only when an argument is exactly "-".
func (b *base) run(args []string, body string) (string, error) {
	var stdin io.Reader
	for _, a := range args {
		if a == "-" {
			stdin = strings.NewReader(body)
			break
		}
	}
	res, err := b.cli.Run(args, stdin)
	if err != nil {
		return "", err
	}
	if res.ExitCode != 0 {
		return "", &Error{Kind: KindFailed, Code: res.ExitCode, Message: strings.TrimSpace(string(res.Stderr))}
	}
	return string(res.Stdout), nil
}

func (b *base) json(args []string, v any) error {
	out, err := b.run(args, "")
	if err != nil {
		return err
	}
	if err := json.Unmarshal([]byte(out), v); err != nil {
		return failed("unparseable tracker output: %q", clip(out))
	}
	return nil
}

// pages decodes an `api` list call whose paginated output concatenates one
// JSON array per page.
func (b *base) pages(path string, v any) error {
	out, err := b.run([]string{"api", path}, "")
	if err != nil {
		return err
	}
	var all []json.RawMessage
	dec := json.NewDecoder(strings.NewReader(strings.TrimSpace(out)))
	for dec.More() {
		var page []json.RawMessage
		if err := dec.Decode(&page); err != nil {
			return failed("unparseable tracker output: %q", clip(out))
		}
		all = append(all, page...)
	}
	joined, _ := json.Marshal(all)
	if err := json.Unmarshal(joined, v); err != nil {
		return failed("unparseable tracker output: %q", clip(out))
	}
	return nil
}

func (b *base) createdID(args []string) (string, error) {
	var d struct{ ID json.RawMessage }
	if err := b.json(args, &d); err != nil {
		return "", err
	}
	n, ok := intOf(d.ID)
	if !ok {
		return "", failed("cannot parse comment id from: %q", clip(string(d.ID)))
	}
	return strconv.Itoa(n), nil
}

func clip(s string) string {
	if len(s) > 200 {
		return s[:200]
	}
	return s
}

// intOf reads a JSON number, or a string holding a decimal integer, as int
// (Python's int(v)).
func intOf(raw json.RawMessage) (int, bool) {
	var n json.Number
	if json.Unmarshal(raw, &n) == nil {
		i, err := strconv.Atoi(string(n))
		return i, err == nil
	}
	var s string
	if json.Unmarshal(raw, &s) == nil {
		i, err := strconv.Atoi(strings.TrimSpace(s))
		return i, err == nil
	}
	return 0, false
}

// idText renders a comment id as hvlib_tracker._int_or_raw would: an integer
// when it reads as one, else the raw string.
func idText(raw json.RawMessage) string {
	if n, ok := intOf(raw); ok {
		return strconv.Itoa(n)
	}
	var s string
	if json.Unmarshal(raw, &s) == nil {
		return s
	}
	return string(raw)
}

// uniq drops empty and repeated names, keeping first-seen order.
func uniq(names []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, n := range names {
		if n != "" && !seen[n] {
			seen[n] = true
			out = append(out, n)
		}
	}
	return out
}

func (b *base) prsClosing(a Adapter, number int) ([]PR, error) {
	prs, err := a.OpenPRs()
	if err != nil {
		return nil, err
	}
	var out []PR
	for _, p := range prs {
		for _, n := range a.ClosedNumbers(p.Body) {
			if n == number {
				out = append(out, p)
				break
			}
		}
	}
	return out, nil
}

func (b *base) addLabels(a Adapter, number int, labels []string, autoCreate bool) error {
	labels = uniq(labels)
	if len(labels) == 0 {
		return nil
	}
	if err := a.EnsureLabels(labels, autoCreate); err != nil {
		return err
	}
	return a.Edit(number, IssueEdit{AddLabels: labels})
}

func (b *base) removeLabels(a Adapter, number int, labels []string) error {
	labels = uniq(labels)
	if len(labels) == 0 {
		return nil
	}
	return a.Edit(number, IssueEdit{RemoveLabels: labels})
}

// numberFromURL reads the issue number off the last line of a create call.
func numberFromURL(out string) (int, error) {
	lines := strings.Split(strings.TrimSpace(out), "\n")
	last := strings.TrimRightFunc(lines[len(lines)-1], isPySpace)
	i := len(last)
	for i > 0 && last[i-1] >= '0' && last[i-1] <= '9' {
		i--
	}
	if i == len(last) || i == 0 || last[i-1] != '/' {
		return 0, failed("cannot parse issue number from: %q", clip(strings.TrimSpace(out)))
	}
	n, err := strconv.Atoi(last[i:])
	if err != nil {
		return 0, failed("cannot parse issue number from: %q", clip(strings.TrimSpace(out)))
	}
	return n, nil
}

// matchMilestone is the title of the milestone whose leading token is hvID,
// preferring open ones.
func matchMilestone(items []Milestone, hvID string) (string, bool) {
	var closed string
	found := false
	for _, m := range items {
		t := strings.TrimSpace(m.Title)
		if !strings.HasPrefix(t, hvID) || startsWithWord(t[len(hvID):]) {
			continue
		}
		if m.State != "closed" {
			return m.Title, true
		}
		if !found {
			closed, found = m.Title, true
		}
	}
	return closed, found
}

type rawMilestone struct {
	Number      int    `json:"number"`
	ID          int    `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	State       any    `json:"state"`
}

func (r rawMilestone) norm(number int) Milestone {
	m := Milestone{Number: number, Title: r.Title, Description: r.Description, State: "open"}
	if strings.ToLower(fmt.Sprint(r.State)) == "closed" {
		m.State = "closed"
	}
	return m
}
