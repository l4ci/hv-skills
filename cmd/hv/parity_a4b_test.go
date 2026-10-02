package main

// Scenarios for the A4 backlog views, summary, status and refactor verbs (#48),
// on the differential harness of parity_a4_test.go. Shim-backed verbs (backlog
// list, summary, backlog archive, status add, status rm) are compared with
// test/hv-shim: exit code, envelope and the whole .hv/ tree. The rest run the
// old helper directly, as the contract's `old:` line says, and check the Go
// envelope against what the old output implies.

import (
	"encoding/json"
	"fmt"
	"reflect"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// ---- shared pieces -----------------------------------------------------------

// dropIn removes key from every object of the list at path ("data.inProgress").
func dropIn(path, key string) func(envl) envl {
	return func(e envl) envl {
		if l, ok := at(e, path).([]any); ok {
			for _, it := range l {
				if m, ok := it.(map[string]any); ok {
					delete(m, key)
				}
			}
		}
		return e
	}
}

// trunc10 cuts the startedAt of the In Progress rows to the date: the shim
// reads them back from the Markdown table when it cannot match an entry's
// items (a CSV string), which only has the date.
func trunc10(e envl) envl {
	if l, ok := at(e, "data.inProgress").([]any); ok {
		for _, it := range l {
			if m, ok := it.(map[string]any); ok {
				if s, ok := m["startedAt"].(string); ok && len(s) > 10 {
					m["startedAt"] = s[:10]
				}
			}
		}
	}
	return e
}

func chain(fns ...func(envl) envl) func(envl) envl {
	return func(e envl) envl {
		for _, f := range fns {
			e = f(e)
		}
		return e
	}
}

func strs(v any) []string {
	out := []string{}
	l, _ := v.([]any)
	for _, x := range l {
		out = append(out, fmt.Sprint(x))
	}
	return out
}

func lines(s string) []string {
	out := []string{}
	for _, l := range strings.Split(s, "\n") {
		if l != "" {
			out = append(out, l)
		}
	}
	return out
}

// checkLines compares the string list at path with the lines the old helper printed.
func checkLines(path string) func(t *testing.T, e envl, ref run) {
	return func(t *testing.T, e envl, ref run) {
		t.Helper()
		got, want := strs(at(e, path)), lines(ref.stdout)
		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s = %q, old printed %q", path, got, want)
		}
	}
}

func both(fs ...func(t *testing.T, e envl, ref run)) func(t *testing.T, e envl, ref run) {
	return func(t *testing.T, e envl, ref run) {
		t.Helper()
		for _, f := range fs {
			f(t, e, ref)
		}
	}
}

func eqCheck(path string, want any) func(t *testing.T, e envl, ref run) {
	return func(t *testing.T, e envl, _ run) { t.Helper(); eq(t, e, path, want) }
}

func blocked(t *testing.T, e envl, _ run) {
	t.Helper()
	eq(t, e, "data.blockedBy", "backend")
	eq(t, e, "data.changed", false)
}

// umbFx is a file-backend umbrella: the standard backlog at the root and two
// registered sub-repos, each a git repo.
var umbFx = fx{subs: map[string][]string{
	"web": {"chore: web init", "fix: [B01] web side"},
	"api": {"chore: api init"},
}}

func withFx(f fx, mod func(*fx)) fx { mod(&f); return f }

const stFile = `{
  "active": [
    {
      "branch": "feat/x",
      "repo": null,
      "items": ["B02"],
      "worktree": null,
      "startedAt": "2026-09-01T10:00:00Z"
    }
  ]
}
`

const stTwo = `{
  "active": [
    {"branch": "feat/x", "repo": null, "items": ["B01", "F01"], "worktree": "../wt-x", "startedAt": "2026-09-01T10:00:00Z"},
    {"branch": "feat/y", "repo": null, "items": ["T01"], "worktree": null, "startedAt": "2026-09-02T11:30:00Z"}
  ],
  "loopStartedAt": "2026-09-03T08:00:00Z"
}
`

const stUmb = `{
  "active": [
    {"branch": "feat/x", "repo": "web", "items": ["B01"], "worktree": "web-wt", "startedAt": "2026-09-01T10:00:00Z"},
    {"branch": "feat/x", "repo": "api", "items": ["B01"], "worktree": null, "startedAt": "2026-09-01T10:00:00Z"},
    {"branch": "feat/z", "repo": null, "items": ["T02"], "worktree": null, "startedAt": "2026-09-04T10:00:00Z"}
  ]
}
`

// ---- the scenarios ---------------------------------------------------------------

func TestParityA4B(t *testing.T) {
	var all []scn
	add := func(s ...scn) { all = append(all, s...) }
	listNorm := dropIn("data.inProgress", "type") // the shim rows have no `type`; the contract has one

	// ---- backlog list (shim)
	const bl = "# TODO\n\n## Bugs\n"
	add(
		scn{name: "list/std", argv: j("backlog", "list"), want: 0, text: true, norm: listNorm,
			check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.bugs.0.id", "B01")
				eq(t, e, "data.bugs.0.priority", "P1")
				eq(t, e, "data.features.0.size", "Minor")
				eq(t, e, "data.clusters.0.0", "B01")
			}},
		scn{name: "list/no-backlog", fx: fx{noBacklog: true}, argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/empty-sections", fx: fx{backlog: "# TODO\n\n## Bugs\n\n## Features\n\n## Tasks\n\n## Completed\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/no-sections", fx: fx{backlog: "# TODO\n"}, argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-title", argv: j("backlog", "list", "--grep", "first"), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-upper", argv: j("backlog", "list", "--grep", "SECOND"), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-related", argv: j("backlog", "list", "--grep", "[F01]"), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-field-text", argv: j("backlog", "list", "--grep", "capture"), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-none", argv: j("backlog", "list", "--grep", "zzzz"), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-empty", argv: j("backlog", "list", "--grep", ""), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-equals-form", argv: j("backlog", "list", "--grep=task"), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-keeps-cluster", argv: j("backlog", "list", "--grep", "Second bug"), want: 0, text: true, norm: listNorm},
		scn{name: "list/grep-spaces-and-dot", argv: j("backlog", "list", "--grep", "parser. dotted"), want: 0, text: true, norm: listNorm},
		scn{name: "list/active-one", fx: fx{status: stFile}, argv: j("backlog", "list"), want: 0, text: true, norm: listNorm,
			check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.inProgress.0.id", "B02")
				eq(t, e, "data.inProgress.0.type", "B")
				eq(t, e, "data.inProgress.0.title", "[P2] Second bug")
				eq(t, e, "data.inProgress.0.startedAt", "2026-09-01T10:00:00Z")
			}},
		scn{name: "list/active-two-branches", fx: fx{status: stTwo}, argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/active-not-filtered-by-grep", fx: fx{status: stFile}, argv: j("backlog", "list", "--grep", "task"), want: 0, text: true, norm: listNorm},
		scn{name: "list/active-no-match-message", fx: fx{status: stFile}, argv: j("backlog", "list", "--grep", "zzz"), want: 0, text: true, norm: listNorm},
		scn{name: "list/active-csv-items", fx: fx{status: `{"active": [{"branch": "b", "repo": null, "items": "B01, F01", "worktree": null, "startedAt": "2026-09-01T10:00:00Z"}]}`},
			argv: j("backlog", "list"), want: 0, text: true, norm: chain(listNorm, trunc10)},
		scn{name: "list/active-no-items", fx: fx{status: `{"active": [{"branch": "b", "repo": null, "items": [], "worktree": null, "startedAt": "2026-09-01T10:00:00Z"}]}`},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/active-unknown-id", fx: fx{status: `{"active": [{"branch": "b", "repo": null, "items": ["B99", "T01"], "worktree": null, "startedAt": "2026-09-01T10:00:00Z"}]}`},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/active-no-started", fx: fx{status: `{"active": [{"branch": "b", "repo": null, "items": ["T01"]}]}`},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/active-corrupt-status", fx: fx{status: "{not json"}, argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/active-repo-column", fx: withFx(umbFx, func(f *fx) { f.status = stUmb }), argv: j("backlog", "list"), want: 0, text: true, norm: listNorm,
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.inProgress.0.repo", "web") }},
		scn{name: "list/sort-bug-prio", fx: fx{backlog: bl + "- **[B01] [P2] two.** a\n- **[B02] [P0] zero.** b\n- **[B03] none.** c\n- **[B04] [P1] one.** d\n- **[B05] [P9] odd.** e\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/sort-feature-size", fx: fx{backlog: "# TODO\n\n## Features\n- **[F01] [Major] big.** a\n- **[F02] [Cosmetic] tiny.** b\n- **[F03] none.** c\n- **[F04] [Minor] mid.** d\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/milestone-column", fx: fx{backlog: bl + "- **[B01] [P1] a.** x Milestone: M01\n- **[B02] [P1] b.** y\n- **[B03] [P1] c.** z Milestone: M01, M03\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/milestone-only-features", fx: fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n\n## Features\n- **[F01] [Major] f.** y Milestone: M02\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/clusters-chain-and-pair", fx: fx{backlog: bl + "- **[B01] [P1] a.** x Related: [B02]\n- **[B02] [P1] b.** y\n- **[B03] [P1] c.** z Related: [B04], [F01]\n- **[B04] [P1] d.** w\n- **[B05] [P1] lonely.** v Related: [B77]\n\n## Features\n- **[F01] [Major] f.** u\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/clusters-grep-one-member", fx: fx{backlog: bl + "- **[B01] [P1] alpha.** x Related: [B02]\n- **[B02] [P1] beta.** y\n- **[B03] [P1] gamma.** z Related: [B04]\n- **[B04] [P1] delta.** w\n"},
			argv: j("backlog", "list", "--grep", "gamma"), want: 0, text: true, norm: listNorm},
		scn{name: "list/clusters-with-active-member", fx: fx{status: stFile}, argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/related-trailing-dot", fx: fx{backlog: bl + "- **[B01] [P1] a.** x Related: [B02]. Milestone: M01\n- **[B02] [P1] b.** y\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/indented-bullet", fx: fx{backlog: bl + "- **[B01] [P1] a.** x\n  - **[B02] [P1] nested.** y\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/duplicate-ids", fx: fx{backlog: bl + "- **[B01] [P1] a.** x\n- **[B01] [P2] again.** y\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/no-period-title", fx: fx{backlog: "# TODO\n\n## Tasks\n- **[T01] No period**\n- **[T02] With. period** rest\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/unicode-title", fx: fx{backlog: bl + "- **[B01] [P1] Größe — naïve.** Zeile Related: [B02]\n- **[B02] [P1] 日本語.** y\n"},
			argv: j("backlog", "list", "--grep", "GRÖSSE"), want: 0, text: true, norm: listNorm},
		scn{name: "list/completed-only", fx: fx{backlog: "# TODO\n\n## Completed\n- ~~**[B01] [P1] Done.** x~~ Done 2026-09-30 [`abc1234`]\n"},
			argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/umbrella-no-repo", fx: umbFx, argv: j("backlog", "list"), want: 0, text: true, norm: listNorm},
		scn{name: "list/umbrella-repo-registered", fx: umbFx, argv: j("backlog", "list", "--repo", "web"), want: 0, text: true, norm: listNorm},
		scn{name: "list/umbrella-repo-unregistered", fx: umbFx, argv: j("backlog", "list", "--repo", "nope"), want: 3},
		scn{name: "list/repo-outside-umbrella", argv: j("backlog", "list", "--repo", "web"), want: 3},
		scn{name: "list/positional", argv: j("backlog", "list", "extra"), want: 2},
		scn{name: "list/unknown-flag", argv: j("backlog", "list", "--bogus"), want: 2},
		scn{name: "list/grep-needs-value", argv: j("backlog", "list", "--grep"), want: 2},
		scn{name: "list/no-hv", fx: fx{noHV: true}, argv: j("backlog", "list"), want: 3},
		scn{name: "list/issues-backend", fx: fx{config: issuesConfig}, goOnly: true, want: 5, argv: j("backlog", "list")},
	)
	_ = bl

	// ---- backlog ids (hv-todo-by-milestone)
	ids := func(name string, f fx, mid string, extra ...string) scn {
		return scn{name: "ids/" + name, fx: f, argv: j(append([]string{"backlog", "ids", "--milestone", mid}, extra...)...),
			old: []string{"hv-todo-by-milestone", mid}, want: 0,
			check: both(checkLines("data.ids"), eqCheck("data.milestone", mid))}
	}
	msFx := fx{backlog: bl + "- **[B01] [P1] a.** x Milestone: M01\n- **[B02] [P1] b.** y Milestone: M01, M03\n- **[B03] [P1] c.** z Milestone: M03\n  - **[B04] [P1] indented.** w Milestone: M01\n\n## Features\n- **[F01] [Major] f.** u Milestone: M03\n\n## Tasks\n- **[T01] t.** v Milestone: M01\n\n## Completed\n- ~~**[B09] [P1] done.** q Milestone: M01~~ Done 2026-09-30 [`abc`]\n"}
	add(
		ids("std-m01", fx{}, "M01"),
		ids("std-m02", fx{}, "M02"),
		ids("unknown", fx{}, "M99"),
		ids("multi-valued-m01", msFx, "M01"),
		ids("multi-valued-m03", msFx, "M03"),
		ids("completed-skipped", msFx, "M09"),
		ids("no-backlog", fx{noBacklog: true}, "M01"),
		ids("duplicate-ids", fx{backlog: bl + "- **[B01] [P1] a.** x Milestone: M01\n- **[B01] [P1] again.** y Milestone: M01\n"}, "M01"),
		ids("umbrella", umbFx, "M01", "--repo", "web"),
		ids("lowercase-not-matched", fx{backlog: bl + "- **[B01] [P1] a.** x Milestone: m01\n"}, "M01"),
		scn{name: "ids/empty-value", goOnly: true, argv: j("backlog", "ids", "--milestone", ""), want: 2},
		scn{name: "ids/missing-flag", goOnly: true, argv: j("backlog", "ids"), want: 2},
		scn{name: "ids/positional", goOnly: true, argv: j("backlog", "ids", "--milestone", "M01", "M01"), want: 2},
		scn{name: "ids/no-hv", goOnly: true, fx: fx{noHV: true}, argv: j("backlog", "ids", "--milestone", "M01"), want: 3},
		scn{name: "ids/repo-unregistered", goOnly: true, fx: umbFx, argv: j("backlog", "ids", "--milestone", "M01", "--repo", "x"), want: 3},
		scn{name: "ids/issues-backend", fx: fx{config: issuesConfig}, goOnly: true, want: 5, argv: j("backlog", "ids", "--milestone", "M01")},
	)

	// ---- backlog milestones (hv-find-milestone-for-items)
	mil := func(name string, f fx, items ...string) scn {
		return scn{name: "milestones/" + name, fx: f, argv: j(append([]string{"backlog", "milestones"}, items...)...),
			old: append([]string{"hv-find-milestone-for-items"}, items...), want: 0, check: checkLines("data.milestones")}
	}
	numFx := fx{backlog: bl + "- **[B01] [P1] a.** x Milestone: M10, M2\n- **[B02] [P1] b.** y Milestone: M2, M03\n- **[B03] [P1] c.** z\n\n## Completed\n- ~~**[B09] [P1] done.** q Milestone: M07~~ Done 2026-09-30 [`abc`]\n"}
	add(
		mil("one", fx{}, "B01"),
		mil("two-sorted-unique", fx{}, "B01", "B03", "B02"),
		mil("numeric-order", numFx, "B01", "B02"),
		mil("untagged", fx{}, "T01"),
		mil("unknown-silent", fx{}, "B99", "B01"),
		mil("completed-not-surfaced", numFx, "B09"),
		mil("short-form-not-matched", fx{}, "B1"),
		mil("no-backlog", fx{noBacklog: true}, "B01"),
		mil("umbrella", umbFx, "B01", "B03"),
		scn{name: "milestones/no-ids", goOnly: true, argv: j("backlog", "milestones"), want: 2},
		scn{name: "milestones/no-hv", goOnly: true, fx: fx{noHV: true}, argv: j("backlog", "milestones", "B01"), want: 3},
		scn{name: "milestones/repo-unregistered", goOnly: true, argv: j("backlog", "milestones", "B01", "--repo", "x"), want: 3},
		scn{name: "milestones/issues-backend", fx: fx{config: issuesConfig}, goOnly: true, want: 5, argv: j("backlog", "milestones", "12")},
	)

	// ---- summary (shim)
	sumNorm := chain(dropIn("data.recent", "type"), func(e envl) envl {
		// an entry without items: the shim reads "?" back as an item; the contract says none.
		if l, ok := at(e, "data.active").([]any); ok {
			for _, it := range l {
				if m, ok := it.(map[string]any); ok {
					if its, _ := m["items"].([]any); len(its) == 1 && its[0] == "?" {
						m["items"] = []any{}
					}
				}
			}
		}
		return e
	})
	know := func(n int) string {
		var b strings.Builder
		b.WriteString("# Knowledge\n\npreamble\n")
		for i := 0; i < n; i++ {
			fmt.Fprintf(&b, "\n## Topic%d\n- entry\n", i+1)
		}
		return b.String()
	}
	ms := func(id, title, status string) string {
		s := "---\n"
		if id != "" {
			s += "id: " + id + "\n"
		}
		if title != "" {
			s += "title: " + title + "\n"
		}
		if status != "" {
			s += "status: " + status + "\n"
		}
		return s + "---\n\nbody\n"
	}
	sum := func(name string, f fx) scn {
		return scn{name: "summary/" + name, fx: f, argv: j("summary"), want: 0, text: true, norm: sumNorm}
	}
	add(variants(sum("std", fx{}))...)
	add(
		sum("no-sections", fx{backlog: "# TODO\n"}),
		sum("empty-sections", fx{backlog: "# TODO\n\n## Bugs\n\n## Features\n\n## Tasks\n\n## Completed\n"}),
		sum("singular-counts", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n\n## Features\n- **[F01] [Major] f.** x\n\n## Tasks\n- **[T01] t.** x\n"}),
		sum("counts-any-bold-bracket-line", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n  - **[B02] [P1] indented.** y\n- **[X9] unknown letter.** z\n- plain\n"}),
		sum("recent-reasons", fx{backlog: "# TODO\n\n## Completed\n- ~~**[B01] [P1] a.** x~~ Done 2026-09-30 [`abc1234`] (handed-off: elsewhere)\n- ~~**[F02] [Major] b.** y~~ Done 2026-09-29 [`abc1234`] (blocked)\n- ~~**[T03] c.** z~~ Done 2026-09-28 [`abc1234`] (dropped: no)\n- ~~**[B04] d.** w~~ Done 2026-09-27 [`abc1234`]\n"}),
		sum("recent-fewer-than-three", fx{backlog: "# TODO\n\n## Completed\n- ~~**[B01] [P1] a.** x~~ Done 2026-09-30 [`abc1234`]\n"}),
		sum("recent-without-id", fx{backlog: "# TODO\n\n## Completed\n- ~~no id here~~ Done 2026-09-30 [`abc1234`]\n- ~~**[B02] [P1] b.** y~~ Done 2026-09-29 [`abc1234`]\n"}),
		sum("recent-ignores-indented-and-other-lines", fx{backlog: "# TODO\n\n## Completed\nnotes\n  - ~~**[B01] [P1] a.** x~~ Done 2026-09-30 [`abc1234`]\n- ~~**[B02] [P1] b.** y~~ Done 2026-09-29 [`abc1234`]\n"}),
		sum("active-one", fx{status: stFile}),
		sum("active-two-with-worktree", fx{status: stTwo}),
		sum("active-umbrella-repos", withFx(umbFx, func(f *fx) { f.status = stUmb })),
		sum("active-no-items", fx{status: `{"active": [{"branch": "b", "repo": null, "items": [], "worktree": null, "startedAt": "2026-09-01T10:00:00Z"}]}`}),
		sum("active-csv-items", fx{status: `{"active": [{"branch": "b", "repo": null, "items": "B01, T01", "worktree": null, "startedAt": "2026-09-01T10:00:00Z"}]}`}),
		sum("active-no-started", fx{status: `{"active": [{"branch": "b", "items": ["B01"]}]}`}),
		sum("active-corrupt-status", fx{status: "{nope"}),
		sum("knowledge-one-topic", fx{files: map[string]string{".hv/KNOWLEDGE.md": know(1)}}),
		sum("knowledge-four-topics", fx{files: map[string]string{".hv/KNOWLEDGE.md": know(4)}}),
		sum("knowledge-five-topics", fx{files: map[string]string{".hv/KNOWLEDGE.md": know(5)}}),
		sum("knowledge-no-topics", fx{files: map[string]string{".hv/KNOWLEDGE.md": "# Knowledge\n\nnothing\n"}}),
		sum("decisions-and-knowledge", fx{files: map[string]string{".hv/KNOWLEDGE.md": know(2), ".hv/DECISIONS.md": know(6)}}),
		sum("archive-one-item", fx{files: map[string]string{".hv/ARCHIVE.md": "# Archive\n- ~~**[B05] [P2] a.** old~~ Done 2026-05-15 [`e4abdbe`]\n"}}),
		sum("archive-no-done-lines", fx{files: map[string]string{".hv/ARCHIVE.md": "# Archive\n\nnothing\n"}}),
		sum("milestones-active", fx{files: map[string]string{".hv/milestones/M01.md": ms("M01", "First milestone", "active"), ".hv/milestones/M02.md": ms("M02", "Second", "planned"),
			".hv/milestones/M03.md": ms("M03", "Third one", "active")}}),
		sum("milestones-id-from-filename", fx{files: map[string]string{".hv/milestones/M07.md": ms("", "Seventh", "active")}}),
		sum("milestones-default-status-planned", fx{files: map[string]string{".hv/milestones/M04.md": ms("M04", "Fourth", "")}}),
		sum("milestones-no-title", fx{files: map[string]string{".hv/milestones/M05.md": ms("M05", "", "active")}}),
		sum("milestones-no-frontmatter-skipped", fx{files: map[string]string{".hv/milestones/M06.md": "# M06\nno frontmatter\n", ".hv/milestones/M08.md": ms("M08", "Eighth", "active")}}),
		sum("everything", withFx(umbFx, func(f *fx) {
			f.status = stTwo
			f.archive = "plain"
			f.files = map[string]string{".hv/KNOWLEDGE.md": know(5), ".hv/DECISIONS.md": know(1), ".hv/milestones/M01.md": ms("M01", "First milestone", "active")}
		})),
		scn{name: "summary/no-backlog", fx: fx{noBacklog: true}, argv: j("summary"), want: 3},
		scn{name: "summary/no-hv", fx: fx{noHV: true}, argv: j("summary"), want: 3},
		scn{name: "summary/positional", argv: j("summary", "x"), want: 2, goOnly: true},
		scn{name: "summary/repo-unregistered", fx: umbFx, argv: j("summary", "--repo", "nope"), want: 3},
		scn{name: "summary/repo-registered", fx: umbFx, argv: j("summary", "--repo", "web"), want: 0, text: true, norm: sumNorm},
		scn{name: "summary/issues-backend", fx: fx{config: issuesConfig}, goOnly: true, want: 5, argv: j("summary")},
		scn{name: "summary/topic-names-with-commas-kept-whole", goOnly: true, want: 0,
			fx:   fx{files: map[string]string{".hv/KNOWLEDGE.md": "# K\n\n## One, two\nx\n\n## Three\ny\n"}},
			argv: j("summary"), check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.knowledge.count", float64(2))
				if got := strs(at(e, "data.knowledge.topics")); !reflect.DeepEqual(got, []string{"One, two", "Three"}) {
					t.Errorf("topics = %q", got)
				}
			}},
	)

	// ---- backlog archive (shim)
	arch := "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n\n## Completed\n" +
		"- ~~**[B02] [P1] old.** x~~ Done {d30} [`abc1234`]\n" +
		"- ~~**[B03] [P1] mid.** x~~ Done {d6} [`abc1234`]\n" +
		"- ~~**[B04] [P1] edge.** x~~ Done {d5} [`abc1234`]\n" +
		"- ~~**[B05] [P1] fresh.** x~~ Done {d2} [`abc1234`] (dropped: gone)\n" +
		"- ~~**[B06] [P1] today.** x~~ Done {d0} [`abc1234`]\n"
	archFx := fx{backlog: arch}
	ar := func(name string, f fx, want int, args ...string) scn {
		return scn{name: "archive/" + name, fx: f, argv: j(append([]string{"backlog", "archive"}, args...)...), want: want}
	}
	add(variants(ar("default-days", archFx, 0))...)
	add(variants(ar("days-0", archFx, 0, "--days", "0"))...)
	add(
		ar("days-1", archFx, 0, "--days", "1"),
		ar("days-6", archFx, 0, "--days", "6"),
		ar("days-100-nothing-old-enough", archFx, 0, "--days", "100"),
		ar("days-equals-form", archFx, 0, "--days=3"),
		ar("std-fixture-old-dates", fx{}, 0),
		ar("std-fixture-days-9999", fx{}, 0, "--days", "9999"),
		ar("existing-plain-archive", withFx(archFx, func(f *fx) { f.archive = "plain" }), 0),
		ar("existing-sectioned-archive", withFx(archFx, func(f *fx) { f.archive = "sectioned" }), 0),
		ar("archive-without-trailing-newline", withFx(archFx, func(f *fx) {
			f.files = map[string]string{".hv/ARCHIVE.md": "# Archive\n\n- ~~**[B00] x.** y~~ Done 2026-01-01 [`abc`]   \n\n\n"}
		}), 0),
		ar("completed-last-no-trailing-newline", fx{backlog: strings.TrimRight(arch, "\n")}, 0),
		ar("completed-before-other-section", fx{backlog: arch + "\n## Notes\nhello\n"}, 0),
		ar("completed-before-other-section-no-blank", fx{backlog: arch + "## Notes\nhello\n"}, 0),
		ar("completed-empty", fx{backlog: "# TODO\n\n## Completed\n"}, 0),
		ar("non-done-lines-kept", fx{backlog: "# TODO\n\n## Completed\nnote line\n- ~~**[B02] [P1] old.** x~~ Done {d30} [`abc1234`]\n  - ~~**[B03] [P1] indented.** x~~ Done {d30} [`abc1234`]\n\ntail text\n"}, 0),
		ar("no-completed-section", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n"}, 0),
		ar("no-backlog", fx{noBacklog: true}, 0),
		ar("crlf-backlog", fx{backlog: strings.ReplaceAll(arch, "\n", "\r\n")}, 0),
		ar("handed-off-and-blocked-moved", fx{backlog: "# TODO\n\n## Completed\n- ~~**[B02] [P1] a.** x~~ Done {d30} [`abc`] (handed-off: to F01. Related: [F01])\n- ~~**[B03] [P1] b.** x~~ Done {d30} [`abc`] (blocked)\n"}, 0),
		ar("days-abc", archFx, 2, "--days", "abc"),
		ar("days-negative", archFx, 2, "--days", "-1"),
		ar("days-fraction", archFx, 2, "--days", "3.5"),
		ar("days-empty", archFx, 2, "--days", ""),
		ar("positional", archFx, 2, "7"),
		ar("no-hv", fx{noHV: true}, 3),
		scn{name: "archive/issues-backend", fx: fx{config: issuesConfig}, argv: j("backlog", "archive"), want: 4, shimNoData: true, check: blocked},
		scn{name: "archive/invalid-date-line", fx: fx{backlog: "# TODO\n\n## Completed\n- ~~**[B02] [P1] a.** x~~ Done 2026-13-45 [`abc`]\n"},
			argv: j("backlog", "archive"), want: 70, div: "the helper crashes on a calendar-invalid date (rc 1, shim maps it to 3), writing nothing; hv exits 70 and writes nothing", refWant: 3},
		scn{name: "archive/repo-registered", fx: withFx(umbFx, func(f *fx) { f.backlog = arch }), argv: j("backlog", "archive", "--repo", "web"), want: 0},
		scn{name: "archive/repo-unregistered", fx: umbFx, argv: j("backlog", "archive", "--repo", "x"), want: 3},
	)

	// ---- backlog stale (hv-staleness)
	today := "2026-10-02"
	stale := func(name string, f fx, kind, todayV string, days int, want int) scn {
		old := []string{"hv-staleness", kind, "--today", todayV}
		argv := []string{"backlog", "stale", "--kind", kind}
		if days >= 0 {
			old = append(old, "--days", strconv.Itoa(days))
			argv = append(argv, "--days", strconv.Itoa(days))
		}
		return scn{name: "stale/" + name, fx: f, argv: j(argv...), old: old, want: want, env: []string{"HV_TEST_TODAY=" + todayV},
			check: func(t *testing.T, e envl, ref run) {
				t.Helper()
				var got []string
				l, _ := at(e, "data.entries").([]any)
				for _, it := range l {
					m := it.(map[string]any)
					got = append(got, fmt.Sprintf("%v %v", m["name"], m["date"]))
				}
				if want := lines(ref.stdout); !reflect.DeepEqual(append([]string{}, got...), append([]string{}, want...)) && !(len(got) == 0 && len(want) == 0) {
					t.Errorf("entries = %q, old printed %q", got, want)
				}
				eq(t, e, "data.kind", kind)
			}}
	}
	todoFx := fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] old.** x Captured: 2026-01-01\n- **[B02] [P1] fresh.** y Captured: 2026-09-15\n- **[B03] [P1] undated.** z\n- **[B04] [P1] junk.** w Captured: not-a-date\n\n## Features\n- **[F01] [Major] compact.** v Captured: 20260101\n- **[F02] [Minor] padded.** u Captured:  2026-02-02 \n\n## Tasks\n- **[T01] t.** s Captured: 2026-07-04\n\n## Completed\n- ~~**[B09] [P1] done.** q Captured: 2020-01-01~~ Done 2026-09-30 [`abc`]\n"}
	knowFx := fx{files: map[string]string{".hv/KNOWLEDGE.md": "# K\n\n## Alpha\nx\n\n## Beta, gamma\ny\n\n## Delta  \nz\n"}}
	mapFile := func(sub, touched string) string {
		s := "---\nsubsystem: " + sub + "\n"
		if touched != "" {
			s += "touched: " + touched + "\n"
		}
		return s + "---\nbody\n"
	}
	mapFx := fx{files: map[string]string{
		".hv/map/auth.md": mapFile("auth", "2026-01-01"), ".hv/map/cache.md": mapFile("cache", "2026-09-30"),
		".hv/map/billing.md": mapFile("billing", ""), ".hv/map/nosub.md": "---\ntitle: x\n---\nbody\n",
		".hv/map/broken.md": "no frontmatter\n", ".hv/map/zeta.md": mapFile("aaa-first", "2025-12-31"),
		".hv/map/bad-date.md": mapFile("baddate", "yesterday"),
	}}
	add(
		stale("todo-90", todoFx, "todo", today, 90, 0),
		stale("todo-default-days", todoFx, "todo", today, -1, 0),
		stale("todo-0-days", todoFx, "todo", today, 0, 0),
		stale("todo-1000-days", todoFx, "todo", today, 1000, 0),
		stale("todo-earlier-today", todoFx, "todo", "2026-01-31", 20, 0),
		stale("todo-future-captured-not-stale", todoFx, "todo", "2025-01-01", 0, 0),
		stale("todo-no-backlog", fx{noBacklog: true}, "todo", today, 90, 0),
		stale("todo-std-fixture", fx{}, "todo", today, 90, 0),
		stale("knowledge-stale", knowFx, "knowledge", "2027-06-01", 90, 0),
		stale("knowledge-fresh", knowFx, "knowledge", today, 90, 0),
		stale("knowledge-boundary-0-days", knowFx, "knowledge", today, 0, 0),
		stale("knowledge-missing-file", fx{}, "knowledge", "2027-06-01", 90, 0),
		stale("knowledge-no-headings", fx{files: map[string]string{".hv/KNOWLEDGE.md": "# K\nnothing\n"}}, "knowledge", "2027-06-01", 90, 0),
		stale("map-touched", mapFx, "map", today, 90, 0),
		stale("map-git-date-fallback", mapFx, "map", "2027-06-01", 90, 0),
		stale("map-none-stale", mapFx, "map", "2025-01-01", 90, 0),
		stale("map-missing-dir", fx{}, "map", today, 90, 0),
		stale("map-umbrella", withFx(umbFx, func(f *fx) { f.files = mapFx.files }), "map", today, 90, 0),
		scn{name: "stale/bad-kind", argv: j("backlog", "stale", "--kind", "plans"), old: []string{"hv-staleness", "plans"}, want: 2,
			oldMap: func(rc int, _ string) int {
				if rc == 1 {
					return 2
				}
				return rc
			}},
		scn{name: "stale/missing-kind", goOnly: true, argv: j("backlog", "stale"), want: 2},
		scn{name: "stale/positional", goOnly: true, argv: j("backlog", "stale", "--kind", "todo", "x"), want: 2},
		scn{name: "stale/days-not-a-number", goOnly: true, argv: j("backlog", "stale", "--kind", "todo", "--days", "soon"), want: 2},
		scn{name: "stale/bad-today-env", goOnly: true, argv: j("backlog", "stale", "--kind", "todo"), env: []string{"HV_TEST_TODAY=tomorrow"}, want: 2},
		scn{name: "stale/no-hv", goOnly: true, fx: fx{noHV: true}, argv: j("backlog", "stale", "--kind", "todo"), want: 3},
		scn{name: "stale/repo-unregistered", goOnly: true, fx: umbFx, argv: j("backlog", "stale", "--kind", "todo", "--repo", "x"), want: 3},
		scn{name: "stale/todo-reads-file-under-issues-config", fx: withFx(todoFx, func(f *fx) { f.config = issuesConfig }), argv: j("backlog", "stale", "--kind", "todo", "--days", "90"),
			old: []string{"hv-staleness", "todo", "--today", today, "--days", "90"}, env: []string{"HV_TEST_TODAY=" + today}, want: 0, check: checkStaleLines},
		scn{name: "stale/default-today-is-real-today", goOnly: true, argv: j("backlog", "stale", "--kind", "todo", "--days", "0"), want: 0, fx: todoFx,
			check: func(t *testing.T, e envl, _ run) {
				if n := len(strs(at(e, "data.entries"))); n == 0 {
					t.Errorf("no entries with --days 0 and the real date")
				}
			}},
	)

	finish(t, all)
}

func checkStaleLines(t *testing.T, e envl, ref run) {
	t.Helper()
	var got []string
	l, _ := at(e, "data.entries").([]any)
	for _, it := range l {
		m := it.(map[string]any)
		got = append(got, fmt.Sprintf("%v %v", m["name"], m["date"]))
	}
	if want := lines(ref.stdout); len(got)+len(want) > 0 && !reflect.DeepEqual(got, want) {
		t.Errorf("entries = %q, old printed %q", got, want)
	}
}

// finish checks the scenario table and runs it.
func finish(t *testing.T, all []scn) {
	t.Helper()
	seen := map[string]bool{}
	for _, s := range all {
		if seen[s.name] {
			t.Fatalf("duplicate scenario name %q", s.name)
		}
		seen[s.name] = true
	}
	t.Logf("%d scenarios", len(all))
	for _, s := range all {
		s := s
		t.Run(s.name, s.exec)
	}
}

var (
	_ = json.Marshal
	_ = regexp.MustCompile
	_ = strconv.Itoa
)
