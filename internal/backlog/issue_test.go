package backlog

import (
	"errors"
	"fmt"
	"math/rand"
	"strconv"
	"strings"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/pytest"
)

// fakeTracker is an in-memory Tracker.
type fakeTracker struct{ issues []Issue }

func (f *fakeTracker) List(state string) ([]Issue, error) {
	var out []Issue
	for _, is := range f.issues {
		if is.State == state {
			out = append(out, is)
		}
	}
	return out, nil
}

func (f *fakeTracker) Get(n int) (Issue, bool, error) {
	for _, is := range f.issues {
		if is.Number == n {
			return is, true, nil
		}
	}
	return Issue{}, false, nil
}

// issueJSON is the wire form shared with the Python stub.
type issueJSON struct {
	Number      int      `json:"number"`
	Title       string   `json:"title"`
	Body        string   `json:"body"`
	Labels      []string `json:"labels"`
	Milestone   string   `json:"milestone"`
	State       string   `json:"state"`
	StateReason string   `json:"state_reason"`
	ClosedAt    string   `json:"closed_at"`
	URL         string   `json:"url"`
}

func (i issueJSON) issue() Issue {
	return Issue{Number: i.Number, Title: i.Title, Body: i.Body, Labels: i.Labels, Milestone: i.Milestone,
		State: i.State, StateReason: i.StateReason, ClosedAt: i.ClosedAt, URL: i.URL}
}

type issueScenario struct {
	Cfg    string      `json:"cfg"`
	Repo   string      `json:"repo"`
	Issues []issueJSON `json:"issues"`
	Refs   []string    `json:"refs"`
}

func genIssues(rng *rand.Rand, n int, customLabels bool) []issueJSON {
	typ := []string{"type:bug", "type:feature", "type:task"}
	prio := []string{"p0", "p1", "p2", "p10", "px", "p"}
	size := []string{"size:Major", "size:Minor", "size:", "size:Cosmetic"}
	other := []string{"enhancement", "milestone-tracker", "in-progress", "needs-review", ""}
	if customLabels {
		typ = []string{"kind/bug", "kind/feature", "kind/task"}
		prio = []string{"prio-1", "prio-2", "prio-x"}
		size = []string{"effort:S", "effort:L"}
		other = []string{"epic", "tracker"}
	}
	titles := []string{"Fix the thing", "Fix the thing.", "Wow!", "What?", "**bold** title", "", "   ", "a\tb\n c", "Café — dash", "Trailing star*", strings.Repeat("long ", 30)}
	fieldVals := []string{"F12, B03", "[F02]", "b12", "T5 and F7.", "B1,F2;T3", "xB12 B12x [B12] B12", "web", "capture", "2026-05-09", "a1b2c3d", "M01", "B٧", "line\nbreak", "  ", "B12é", "_B12", "B12_"}
	fieldKeys := []string{"Related", "Repos", "Subsystem", "Captured", "Since", "Milestone", "Detail", "Other"}
	paras := []string{"First paragraph.", "  spaced   out  ", "", "\n", "Second para\nwith break", strings.Repeat("word ", 60), "café " + strings.Repeat("é", 210), " "}
	milestones := []string{"", "", "", "M07 — Title", "M12", "Plain title", "M", "M7-x", "  M3  "}
	var out []issueJSON
	for i := 0; i < n; i++ {
		is := issueJSON{Number: 1 + i*3 + rng.Intn(3), Title: pick(rng, titles), URL: "https://example.test/issues/" + strconv.Itoa(i)}
		for j := rng.Intn(4); j >= 0; j-- {
			switch rng.Intn(4) {
			case 0:
				is.Labels = append(is.Labels, pick(rng, typ))
			case 1:
				is.Labels = append(is.Labels, pick(rng, prio))
			case 2:
				is.Labels = append(is.Labels, pick(rng, size))
			default:
				is.Labels = append(is.Labels, pick(rng, other))
			}
		}
		var body strings.Builder
		for j := rng.Intn(4); j > 0; j-- {
			body.WriteString(pick(rng, paras))
			body.WriteString(pick(rng, []string{"\n\n", "\n \n", "\n", "\r\n\r\n"}))
		}
		if rng.Intn(2) == 0 {
			body.WriteString(pick(rng, []string{"", "\n\n", "\n"}) + "<!-- hv:fields\n")
			for _, k := range rng.Perm(len(fieldKeys))[:rng.Intn(5)] {
				body.WriteString(fieldKeys[k] + pick(rng, []string{": ", ":", ":  ", ":\t"}) + pick(rng, fieldVals) + pick(rng, []string{"", " "}) + "\n")
			}
			body.WriteString(pick(rng, []string{"-->", "\n-->", "-->  ", "-->\n\n", "--> trailing"}))
		}
		is.Body = body.String()
		is.Milestone = pick(rng, milestones)
		if rng.Intn(2) == 0 {
			is.State = "closed"
			is.StateReason = pick(rng, []string{"completed", "not_planned", ""})
			is.ClosedAt = pick(rng, []string{"2026-03-04T10:00:00Z", "2026-03-04T10:00:00Z", "2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z", "", "2026"})
		} else {
			is.State = "open"
		}
		out = append(out, is)
	}
	return out
}

const defaultCfg = `{}`
const customCfg = `{"issues": {"labels": {"types": {"bug": "kind/bug", "feature": "kind/feature", "task": "kind/task"}, "priorityPrefix": "prio-", "sizePrefix": "effort:", "milestoneTracker": "tracker"}}}`

const pyIssues = `import json, sys
from hvlib_backend import IssueBackend, parse_fields_block, render_fields_block
from hvlib_tracker import TrackerError

class Stub:
    def __init__(self, issues):
        self.issues = {i["number"]: self.norm(i) for i in issues}
    @staticmethod
    def norm(i):
        i = dict(i)
        for k in ("milestone", "state_reason", "closed_at"):
            i[k] = i[k] or None
        i["assignees"] = []
        return i
    def list(self, state="open"):
        return [i for i in self.issues.values() if i["state"] == state]
    def get(self, n):
        if n not in self.issues:
            raise TrackerError(1, "issue not found")
        return self.issues[n]

out = []
for s in json.load(open(sys.argv[1])):
    cfg = json.loads(s["cfg"])
    b = IssueBackend(cfg, repo=s["repo"] or None)
    b._adapter = Stub(s["issues"])
    r = {"markdown": {}, "items": [], "detail": []}
    for lim in (None, 0, 1, 3, 20):
        r["markdown"][str(lim)] = b.backlog_markdown(closed_limit=lim)
    for ref in s["refs"]:
        f = b.fields(ref)
        if f is None:
            r["items"].append(None)
        else:
            issue = b._lookup(ref)
            letter = b._letter(issue)
            f["tag"] = b._tag(issue, letter)
            f["type"] = letter
            f["id"] = f"{letter}{issue['number']}"
            f["closed"] = issue["state"] == "closed"
            f["line"] = ("" + b._done_line(issue)) if f["closed"] else "- " + b._bullet_inner(issue)
            r["items"].append(f)
        r["detail"].append(b.detail_text(ref))
    out.append(r)
print(json.dumps(out))`

func TestIssuesMatchPython(t *testing.T) {
	rng := rand.New(rand.NewSource(21))
	var scen []issueScenario
	for i := 0; i < 40; i++ {
		s := issueScenario{Cfg: defaultCfg, Issues: genIssues(rng, 4+rng.Intn(12), false)}
		if i%3 == 1 {
			s.Cfg, s.Issues = customCfg, genIssues(rng, 4+rng.Intn(12), true)
		}
		if i%4 == 2 {
			s.Repo = "web"
		}
		for _, is := range s.Issues {
			n := strconv.Itoa(is.Number)
			s.Refs = append(s.Refs, n, "#"+n, "F"+n, "b"+n, "T"+n)
		}
		s.Refs = append(s.Refs, "999", "x", "", "#", "F", "web:1", "1.5", " 3 ", "B-1")
		scen = append(scen, s)
	}

	var want []map[string]any
	pytest.GoldenJSON(t, pyIssues, scen, &want)

	var inputs, got, w []any
	items := 0
	for i, s := range scen {
		cfg, err := jsonx.Decode([]byte(s.Cfg))
		if err != nil {
			t.Fatal(err)
		}
		tr := &fakeTracker{}
		for _, is := range s.Issues {
			tr.issues = append(tr.issues, is.issue())
		}
		b := &Issues{Cfg: cfg, Tracker: tr, Repo: s.Repo}
		r := map[string]any{"markdown": map[string]any{}, "items": []any{}, "detail": []any{}}
		for _, lim := range []struct {
			key string
			n   int
		}{{"None", -1}, {"0", 0}, {"1", 1}, {"3", 3}, {"20", 20}} {
			md, err := b.Markdown(lim.n)
			if err != nil {
				t.Fatal(err)
			}
			r["markdown"].(map[string]any)[lim.key] = md
		}
		for _, ref := range s.Refs {
			it, err := b.Get(ref)
			if err != nil {
				if !errors.Is(err, ErrNotFound) {
					t.Fatalf("Get(%q): %v", ref, err)
				}
				r["items"] = append(r["items"].([]any), nil)
			} else {
				items++
				m := map[string]any{}
				for k, v := range fieldsMap(it.Fields) {
					m[k] = v
				}
				m["reason"], m["note"], m["title"], m["tag"], m["type"] = it.Reason, it.Note, it.Title, it.Tag, it.Type
				m["closed"], m["line"] = it.Closed, it.Line
				m["id"] = it.Type + strconv.Itoa(it.Number)
				r["items"] = append(r["items"].([]any), m)
				wantID := strconv.Itoa(it.Number)
				if s.Repo != "" {
					wantID = s.Repo + ":" + wantID
				}
				if it.ID != wantID || it.URL == "" {
					t.Errorf("Get(%q): ID %q (want %q), URL %q", ref, it.ID, wantID, it.URL)
				}
			}
			text, ok, err := b.Detail(ref)
			if err != nil {
				t.Fatal(err)
			}
			if ok {
				r["detail"] = append(r["detail"].([]any), text)
			} else {
				r["detail"] = append(r["detail"].([]any), nil)
			}
		}
		got = append(got, r)
		w = append(w, want[i])
		inputs = append(inputs, map[string]any{"scenario": i, "cfg": s.Cfg, "repo": s.Repo, "issues": s.Issues})
	}
	n := pytest.Compare(t, "IssueBackend", inputs, got, w)
	t.Logf("compared %d scenarios (%d items) against IssueBackend.backlog_markdown/fields/_bullet_inner/_done_line/detail_text", n, items)
	if items < 300 {
		t.Fatalf("only %d items resolved; test too weak", items)
	}
}

const pyBlock = `import json, sys
from hvlib_backend import parse_fields_block, render_fields_block
out = []
for body in json.load(open(sys.argv[1])):
    text, fields = parse_fields_block(body)
    out.append({"text": text, "fields": fields, "order": list(fields.keys()),
                "render": render_fields_block(text, fields),
                "render2": render_fields_block(body, {"A": " x\n y ", "B": "", "C": "  ", "D": "v"})})
print(json.dumps(out))`

func TestFieldsBlockMatchesPython(t *testing.T) {
	rng := rand.New(rand.NewSource(5))
	bodies := []string{
		"", "plain", "text\n\n<!-- hv:fields\nRelated: F1\nRepos: web\n-->", "<!-- hv:fields\nA: 1\n-->",
		"text\r\n\r\n<!-- hv:fields\r\nA: 1\r\nB:   2  \r\n-->\r\n", "t\n<!-- hv:fields\nA: 1\nA: 2\nB:\nC: 3\n-->",
		"t\n<!-- hv:fields\nnot a field\n9x: y\nA: ok\n -->  \n\n", "t\n<!-- hv:fields\n-->", "t\n<!-- hv:fields\n\n-->",
		"x<!-- hv:fields\nA: 1\n-->\ny", "<!-- hv:fields\nA: 1\n--> tail", "a\n<!-- hv:fields\nA: 1\n-->\n<!-- hv:fields\nB: 2\n-->",
		"t\n\n\n<!-- hv:fields\nA: 1\n-->", "t<!-- hv:fields\nA: café \n-->", "<!-- hv:fields\nA: 1",
		"t\n<!-- hv:fields\nA: -->x\nB: 2\n-->",
	}
	for _, is := range genIssues(rng, 150, false) {
		bodies = append(bodies, is.Body)
	}
	var want []map[string]any
	pytest.GoldenJSON(t, pyBlock, bodies, &want)
	var got, w, inputs []any
	for i, body := range bodies {
		text, fields, order := ParseFieldsBlock(body)
		if order == nil {
			order = []string{}
		}
		got = append(got, map[string]any{"text": text, "fields": fields, "order": order,
			"render":  RenderFieldsBlock(text, order, fields),
			"render2": RenderFieldsBlock(body, []string{"A", "B", "C", "D"}, map[string]string{"A": " x\n y ", "D": "v"})})
		w = append(w, want[i])
		inputs = append(inputs, body)
	}
	n := pytest.Compare(t, "fields block", inputs, got, w)
	t.Logf("compared %d bodies (parse_fields_block, render_fields_block)", n)
}

func TestIssuesOpenAndErrors(t *testing.T) {
	tr := &fakeTracker{issues: []Issue{
		{Number: 1, Title: "Real", State: "open", Labels: []string{"type:bug"}},
		{Number: 2, Title: "Tracker", State: "open", Labels: []string{"milestone-tracker"}},
	}}
	b := &Issues{Cfg: mustDecode(t, `{}`), Tracker: tr}
	if _, err := b.Get("2"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("milestone tracker must not be an item: %v", err)
	}
	if _, err := b.Get("F1"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("letter mismatch must not be found: %v", err)
	}
	if !b.IsMilestoneTracker(tr.issues[1]) || b.Letter(tr.issues[0]) != "B" || b.Letter(Issue{}) != "T" {
		t.Fatal("Letter / IsMilestoneTracker")
	}
	if _, _, err := (&Issues{Cfg: mustDecode(t, `{}`)}).Detail("1"); err == nil {
		t.Fatal("nil tracker must be an error, not a panic")
	}
	if got := fmt.Sprint(b.Name()); got != "issues" {
		t.Fatal(got)
	}
}

func mustDecode(t *testing.T, s string) any {
	t.Helper()
	v, err := jsonx.Decode([]byte(s))
	if err != nil {
		t.Fatal(err)
	}
	return v
}
