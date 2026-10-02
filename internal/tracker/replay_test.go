package tracker

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"
)

// The fixtures in testdata/ are the M07 Python adapters recorded against the
// offline fake gh/glab by testdata/record.py: every CLI call each step made
// and what the adapter returned. Replaying them proves the Go adapters make
// the same calls, in the same order, and return the same values.

type recCall struct {
	Name   string   `json:"name"`
	Argv   []string `json:"argv"`
	Stdin  string   `json:"stdin"`
	Stdout string   `json:"stdout"`
	Stderr string   `json:"stderr"`
	Code   int      `json:"code"`
}

type recStep struct {
	Op     string                     `json:"op"`
	Args   map[string]json.RawMessage `json:"args"`
	Calls  []recCall                  `json:"calls"`
	Result json.RawMessage            `json:"result"`
	Error  *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

type recording struct {
	Provider string    `json:"provider"`
	Steps    []recStep `json:"steps"`
}

func TestReplayRecordedFixtures(t *testing.T) {
	for _, p := range []string{"github", "gitlab"} {
		t.Run(p, func(t *testing.T) { replay(t, filepath.Join("testdata", p+".json")) })
	}
}

// TestFixturesAreCurrent re-records against the Python adapters, while they
// still exist in bin/, and replays the fresh recording.
func TestFixturesAreCurrent(t *testing.T) {
	if testing.Short() {
		t.Skip("re-recording runs the Python adapters")
	}
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 not on PATH")
	}
	if _, err := os.Stat(filepath.Join("..", "..", "bin", "hvlib_tracker.py")); err != nil {
		t.Skip("bin/hvlib_tracker.py is gone")
	}
	dir := t.TempDir()
	if out, err := exec.Command("python3", filepath.Join("testdata", "record.py"), dir).CombinedOutput(); err != nil {
		t.Fatalf("record.py: %v\n%s", err, out)
	}
	for _, p := range []string{"github", "gitlab"} {
		t.Run(p, func(t *testing.T) { replay(t, filepath.Join(dir, p+".json")) })
	}
}

func replay(t *testing.T, path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var rec recording
	if err := json.Unmarshal(data, &rec); err != nil {
		t.Fatal(err)
	}
	var calls []recCall
	var step string
	x := func(dir, name string, args []string, stdin []byte) ([]byte, []byte, int, error) {
		if len(calls) == 0 {
			t.Fatalf("%s: unexpected call %s %q", step, name, args)
		}
		c := calls[0]
		calls = calls[1:]
		if name != c.Name || !reflect.DeepEqual(args, c.Argv) {
			t.Fatalf("%s: call\n got %s %q\nwant %s %q", step, name, args, c.Name, c.Argv)
		}
		if string(stdin) != c.Stdin {
			t.Fatalf("%s: stdin %q, want %q", step, stdin, c.Stdin)
		}
		return []byte(c.Stdout), []byte(c.Stderr), c.Code, nil
	}
	found := func(string) (string, error) { return "/fake", nil }
	a, err := New(Settings{Provider: rec.Provider, NotPlannedLabel: "not-planned"}, "", "",
		WithExec(x, found), WithSleep(func(time.Duration) {}))
	if err != nil {
		t.Fatal(err)
	}
	for i, s := range rec.Steps {
		step = fmt.Sprintf("step %d %s %s", i, s.Op, s.Args)
		calls = s.Calls
		got, err := dispatch(a, s.Op, s.Args)
		if len(calls) != 0 {
			t.Fatalf("%s: %d recorded calls not made, next %q", step, len(calls), calls[0].Argv)
		}
		if s.Error != nil {
			var e *Error
			if !errors.As(err, &e) {
				t.Fatalf("%s: want error %d %q, got %v (result %v)", step, s.Error.Code, s.Error.Message, err, got)
			}
			want := strings.TrimPrefix(s.Error.Message, "error: hv-tracker-call: ")
			if e.Code != s.Error.Code || e.Message != want {
				t.Fatalf("%s: error [%d] %q, want [%d] %q", step, e.Code, e.Message, s.Error.Code, want)
			}
			continue
		}
		if err != nil {
			t.Fatalf("%s: %v", step, err)
		}
		gotJSON, _ := json.Marshal(got)
		var g, w any
		_ = json.Unmarshal(gotJSON, &g)
		_ = json.Unmarshal(s.Result, &w)
		if !reflect.DeepEqual(g, w) {
			t.Fatalf("%s: result\n got %s\nwant %s", step, gotJSON, s.Result)
		}
	}
}

// dispatch calls the Go method for a recorded Python call and returns its
// result in the Python adapter's shape.
func dispatch(a Adapter, op string, args map[string]json.RawMessage) (any, error) {
	in := func(k string) int {
		var n int
		_ = json.Unmarshal(args[k], &n)
		return n
	}
	s := func(k string) string {
		var v string
		_ = json.Unmarshal(args[k], &v)
		return v
	}
	ptr := func(k string) *string {
		if _, ok := args[k]; !ok {
			return nil
		}
		v := s(k)
		return &v
	}
	list := func(k string) []string {
		var v []string
		_ = json.Unmarshal(args[k], &v)
		return v
	}
	flag := func(k string, def bool) bool {
		v := def
		if raw, ok := args[k]; ok {
			_ = json.Unmarshal(raw, &v)
		}
		return v
	}
	raw := func(k string) string { return strings.Trim(string(args[k]), `"`) }

	switch op {
	case "call":
		c := a.(interface{ cliOf() *CLI }).cliOf()
		r, err := c.Run(list("args"), strings.NewReader(s("stdin")))
		if err != nil {
			e := err.(*Error)
			return map[string]any{"stdout": "", "stderr": "error: hv-tracker-call: " + e.Message + "\n", "code": e.Code}, nil
		}
		return map[string]any{"stdout": string(r.Stdout), "stderr": string(r.Stderr), "code": r.ExitCode}, nil
	case "closed_numbers":
		return nonNil(a.ClosedNumbers(s("body"))), nil
	case "create":
		return a.Create(s("title"), s("body"), list("labels"), s("milestone"))
	case "get":
		is, err := a.Get(in("number"), flag("comments", false))
		return pyIssue(is), err
	case "list":
		return pyIssues(a.List(ListFilter{State: s("state"), Labels: list("labels"), Milestone: s("milestone")}))
	case "issues_in_milestone":
		return pyIssues(a.IssuesInMilestone(s("title"), s("state")))
	case "edit":
		return nil, a.Edit(in("number"), IssueEdit{Title: ptr("title"), Body: ptr("body"), AddLabels: list("add_labels"),
			RemoveLabels: list("remove_labels"), Milestone: s("milestone"), RemoveMilestone: flag("remove_milestone", false)})
	case "ensure_labels":
		return nil, a.EnsureLabels(list("names"), flag("auto_create", true))
	case "add_labels":
		return nil, a.AddLabels(in("number"), list("labels"), flag("auto_create", true))
	case "remove_labels":
		return nil, a.RemoveLabels(in("number"), list("labels"))
	case "close":
		return nil, a.Close(in("number"), s("reason"), s("comment"))
	case "reopen":
		return nil, a.Reopen(in("number"))
	case "assign_self":
		return nil, a.AssignSelf(in("number"))
	case "comments":
		cs, err := a.Comments(in("number"))
		return pyComments(cs), err
	case "add_comment":
		id, err := a.AddComment(in("number"), s("body"))
		return pyID(id), err
	case "edit_comment":
		return nil, a.EditComment(in("number"), raw("comment_id"), s("body"))
	case "delete_comment":
		return nil, a.DeleteComment(in("number"), raw("comment_id"))
	case "find_milestone":
		t, ok, err := a.FindMilestone(s("hv_id"))
		if !ok {
			return nil, err
		}
		return t, err
	case "milestones":
		ms, err := a.Milestones(s("state"))
		out := []any{}
		for _, m := range ms {
			out = append(out, map[string]any{"number": m.Number, "title": m.Title, "description": m.Description, "state": m.State})
		}
		return out, err
	case "create_milestone":
		return a.CreateMilestone(s("title"), s("description"))
	case "edit_milestone":
		return nil, a.EditMilestone(in("number"), MilestoneEdit{Title: ptr("title"), Description: ptr("description"), State: ptr("state")})
	case "open_prs":
		return pyPRs(a.OpenPRs())
	case "prs_closing":
		return pyPRs(a.PRsClosing(in("number")))
	case "pr_checkout":
		return nil, a.PRCheckout(in("pr"))
	case "pr_merge":
		return a.PRMerge(in("pr"))
	case "pr_comment":
		return nil, a.PRComment(in("pr"), s("body"))
	case "pr_state":
		return a.PRState(in("pr"))
	}
	return nil, fmt.Errorf("no dispatch for op %q", op)
}

func (b *base) cliOf() *CLI { return b.cli }

func nonNil(ns []int) []int {
	if ns == nil {
		return []int{}
	}
	return ns
}

func none(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func pyID(id string) any {
	if n, err := strconv.Atoi(id); err == nil {
		return n
	}
	return id
}

func pyIssue(is Issue) map[string]any {
	m := map[string]any{"number": is.Number, "title": is.Title, "body": is.Body, "labels": is.Labels,
		"milestone": none(is.Milestone), "state": is.State, "state_reason": none(is.StateReason),
		"closed_at": none(is.ClosedAt), "url": is.URL, "assignees": is.Assignees}
	if is.Comments != nil {
		m["comments"] = pyComments(is.Comments)
	}
	return m
}

func pyIssues(list []Issue, err error) (any, error) {
	out := []any{}
	for _, is := range list {
		out = append(out, pyIssue(is))
	}
	return out, err
}

func pyComments(cs []Comment) []any {
	out := []any{}
	for _, c := range cs {
		out = append(out, map[string]any{"id": pyID(c.ID), "body": c.Body, "author": c.Author})
	}
	return out
}

func pyPRs(prs []PR, err error) (any, error) {
	out := []any{}
	for _, p := range prs {
		out = append(out, map[string]any{"number": p.Number, "title": p.Title, "branch": p.Branch, "url": p.URL, "body": p.Body})
	}
	return out, err
}
