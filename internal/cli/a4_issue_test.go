package cli

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/backlog"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// a4FakeTracker is an in-memory backlog.Tracker, so the issue-mode branches
// run without gh or glab. The real adapter to internal/tracker (#90) is a
// follow-up.
type a4FakeTracker struct{ issues []backlog.Issue }

func (f *a4FakeTracker) List(state string) ([]backlog.Issue, error) {
	var out []backlog.Issue
	for _, is := range f.issues {
		if is.State == state {
			out = append(out, is)
		}
	}
	return out, nil
}

func (f *a4FakeTracker) Get(n int) (backlog.Issue, bool, error) {
	for _, is := range f.issues {
		if is.Number == n {
			return is, true, nil
		}
	}
	return backlog.Issue{}, false, nil
}

// withTracker swaps newTracker for one serving tr, for the test's duration.
func withTracker(t *testing.T, tr backlog.Tracker) {
	t.Helper()
	old := newTracker
	newTracker = func(string, any) (backlog.Tracker, error) { return tr, nil }
	t.Cleanup(func() { newTracker = old })
}

const issuesConfig = `{"backlog": {"backend": "issues"}}`

func issueFixture() *a4FakeTracker {
	return &a4FakeTracker{issues: []backlog.Issue{
		{Number: 7, Title: "Add export", Body: "Export the backlog.\n\n<!-- hv:fields\nRelated: B9\n-->",
			Labels: []string{"type:feature", "size:Major"}, Milestone: "M02 — Sharing", State: "open",
			URL: "https://example.test/issues/7"},
		{Number: 9, Title: "Crash on start", Labels: []string{"type:bug", "p1"}, State: "closed",
			StateReason: "not_planned", ClosedAt: "2026-09-30T10:00:00Z", URL: "https://example.test/issues/9"},
		{Number: 3, Title: "M02 tracking", Labels: []string{"milestone-tracker"}, State: "open"},
	}}
}

func dataOf(t *testing.T, env map[string]any) *jsonx.Object {
	t.Helper()
	d, ok := env["data"].(*jsonx.Object)
	if !ok {
		t.Fatalf("no data in %v", env)
	}
	return d
}

func get(o *jsonx.Object, k string) any { v, _ := o.Get(k); return v }

// Issue mode: every accepted spelling of an issue resolves to the canonical
// id (the number) with the type letter beside it (contract rule 11).
func TestIssueFieldGetCanonicalID(t *testing.T) {
	root := a4Project(t, issuesConfig)
	withTracker(t, issueFixture())
	for _, ref := range []string{"7", "#7", "F7", "f7"} {
		code, env, stderr := hvRun(t, "--json", "-C", root, "item", "field", "get", ref, "--name", "title")
		if code != 0 {
			t.Fatalf("%s: exit %d: %s", ref, code, stderr)
		}
		d := dataOf(t, env)
		if get(d, "id") != "7" || get(d, "type") != "F" || get(d, "value") != "Add export" {
			t.Fatalf("%s: data %v", ref, d)
		}
	}
	code, env, _ := hvRun(t, "--json", "-C", root, "item", "field", "get", "7", "--name", "milestone")
	if d := dataOf(t, env); code != 0 || get(d, "value") != "M02" {
		t.Fatalf("milestone: exit %d, %v", code, d)
	}
}

func TestIssueFieldListClosedItem(t *testing.T) {
	root := a4Project(t, issuesConfig)
	withTracker(t, issueFixture())
	code, env, stderr := hvRun(t, "--json", "-C", root, "item", "field", "list", "#9")
	if code != 0 {
		t.Fatalf("exit %d: %s", code, stderr)
	}
	d := dataOf(t, env)
	f, _ := get(d, "fields").(*jsonx.Object)
	if get(d, "id") != "9" || get(d, "type") != "B" || f == nil ||
		get(f, "reason") != "dropped" || get(f, "detail") != "https://example.test/issues/9" {
		t.Fatalf("data %v", d)
	}
}

// Unknown numbers, a type-letter mismatch and milestone tracking issues are
// not items: exit 3.
func TestIssueRefsThatDoNotResolve(t *testing.T) {
	root := a4Project(t, issuesConfig)
	withTracker(t, issueFixture())
	for _, ref := range []string{"99", "B7", "#3", "x7"} {
		if code, _, _ := hvRun(t, "--json", "-C", root, "item", "field", "get", ref, "--name", "title"); code != ExitResolution {
			t.Fatalf("%s: exit %d, want %d", ref, code, ExitResolution)
		}
	}
}

// What this PR does not port in issue mode fails cleanly: file-only verbs are
// refused (4, backend); the tracker-backed writes are not implemented (71).
func TestIssueModeUnportedAndFileOnly(t *testing.T) {
	root := a4Project(t, issuesConfig)
	withTracker(t, issueFixture())
	raw := filepath.Join(t.TempDir(), "bullet.md")
	if err := os.WriteFile(raw, []byte("- **[B05] [P1] Raw.** x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		argv []string
		exit int
	}{
		{[]string{"id", "next", "--kind", "bugs"}, ExitRefused},
		{[]string{"item", "rm", "7"}, ExitRefused},
		{[]string{"item", "create", "--kind", "bugs", "--raw-file", raw}, ExitRefused},
		{[]string{"item", "complete", "7", "--commit", "abc", "--no-proof"}, ExitNotImplemented},
		{[]string{"item", "reopen", "7"}, ExitNotImplemented},
		{[]string{"item", "ready", "7"}, ExitNotImplemented},
		{[]string{"item", "comment", "list", "7"}, ExitNotImplemented},
		{[]string{"item", "field", "set", "7", "--name", "related", "--value", "B9"}, ExitNotImplemented},
		{[]string{"item", "create", "--kind", "bugs", "--title", "x"}, ExitNotImplemented},
	}
	for _, c := range cases {
		code, env, _ := hvRun(t, append([]string{"--json", "-C", root}, c.argv...)...)
		if code != c.exit {
			t.Fatalf("%v: exit %d, want %d (%v)", c.argv, code, c.exit, env)
		}
	}
}

// Without an injected tracker, issue mode stops at the stub: exit 5.
func TestIssueModeWithoutTracker(t *testing.T) {
	root := a4Project(t, issuesConfig)
	if code, _, _ := hvRun(t, "--json", "-C", root, "item", "field", "get", "7", "--name", "title"); code != ExitUnavailable {
		t.Fatalf("exit %d, want %d", code, ExitUnavailable)
	}
}
