package backlog

import (
	"errors"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/pytest"
)

// project is one generated .hv/ tree.
type project struct {
	Root      string   `json:"root"`
	Backlog   string   `json:"backlog"`
	Archive   string   `json:"archive"`
	Detail    string   `json:"detail"` // content for .hv/bugs/B07.md and friends, "" = none
	IDs       []string `json:"ids"`
	NoBacklog bool     `json:"noBacklog"`
}

func (p project) write(t *testing.T) {
	hv := filepath.Join(p.Root, ".hv")
	if err := os.MkdirAll(filepath.Join(hv, "bugs"), 0o755); err != nil {
		t.Fatal(err)
	}
	put := func(name, content string) {
		if err := os.WriteFile(filepath.Join(hv, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if !p.NoBacklog {
		put("BACKLOG.md", p.Backlog)
	}
	if p.Archive != "" {
		put("ARCHIVE.md", p.Archive)
	}
	if p.Detail != "" {
		put("bugs/B07.md", p.Detail)
		put("bugs/b07x.md", p.Detail)
	}
}

func genProjects(t *testing.T, n int) []project {
	rng := rand.New(rand.NewSource(11))
	lines := genLines(48, 400)
	ids := []string{"B07", "F12", "T3", "F100", "B7", "B٧", "X1", "B01", "B02", "Z9", "B07 ", "", "b07", "B0"}
	var out []project
	for i := 0; i < n; i++ {
		mk := func(count int) string {
			var b strings.Builder
			b.WriteString("# Backlog\n\n")
			for j := 0; j < count; j++ {
				if rng.Intn(6) == 0 {
					b.WriteString(pick(rng, []string{"## Bugs", "## Features", "## Tasks", "## Completed", ""}))
				} else {
					b.WriteString(lines[rng.Intn(len(lines))])
				}
				b.WriteString("\n")
			}
			s := b.String()
			if i%4 == 0 {
				s = strings.ReplaceAll(s, "\n", "\r\n")
			}
			return s
		}
		p := project{Root: filepath.Join(t.TempDir(), "proj"), Backlog: mk(rng.Intn(25)), IDs: ids}
		if i%3 != 0 {
			p.Archive = mk(rng.Intn(25))
		}
		if i%5 == 0 {
			p.Detail = "# detail\r\nbody\r\n\rlast"
		}
		p.NoBacklog = i%11 == 0
		out = append(out, p)
	}
	return out
}

const pyFile = `import json, os, sys
from hvlib_backend import FileBackend
from hvlib_section import load_backlog_corpus
from hvlib_bullet import find_origin_bullet, parse_open_bullet
res = []
for p in json.load(open(sys.argv[1])):
    os.chdir(p["root"])
    fb = FileBackend()
    corpus = load_backlog_corpus(".")
    r = {"corpus": corpus, "items": [], "detail": [], "markdown": fb.backlog_markdown()}
    for iid in p["ids"]:
        f = fb.fields(iid)
        if f is None:
            r["items"].append(None)
            continue
        line, title = find_origin_bullet(corpus, iid)
        b = parse_open_bullet("- " + line)
        f["tag"] = b["tag"] if b else ""
        f["title"] = b["title"] if b else (title or "")
        f["closed"] = f["reason"] != ""
        f["line"] = line
        r["items"].append(f)
    for iid in p["ids"]:
        r["detail"].append(fb.detail_text(iid))
    res.append(r)
print(json.dumps(res))`

func TestFileMatchesPython(t *testing.T) {
	projects := genProjects(t, 60)
	for _, p := range projects {
		p.write(t)
	}
	var want []map[string]any
	pytest.JSON(t, pyFile, projects, &want)

	var got, inputs []any
	items := 0
	for i, p := range projects {
		f := &File{Root: p.Root}
		r := map[string]any{"corpus": f.Corpus(), "items": []any{}, "detail": []any{}}
		if md, err := f.Markdown(-1); err == nil {
			r["markdown"] = md
		} else if !errors.Is(err, ErrNotFound) {
			t.Fatalf("Markdown: %v", err)
		} else {
			r["markdown"] = nil
		}
		for _, id := range p.IDs {
			it, err := f.Get(id)
			if err != nil {
				if !errors.Is(err, ErrNotFound) {
					t.Fatalf("Get(%q): %v", id, err)
				}
				r["items"] = append(r["items"].([]any), nil)
				continue
			}
			items++
			m := map[string]any{}
			for k, v := range fieldsMap(it.Fields) {
				m[k] = v
			}
			m["reason"], m["note"], m["title"], m["tag"] = it.Reason, it.Note, it.Title, it.Tag
			m["closed"], m["line"] = it.Closed, it.Line
			r["items"] = append(r["items"].([]any), m)
			if it.ID != id || it.Number != 0 || it.URL != "" {
				t.Errorf("Get(%q): ID/Number/URL = %q/%d/%q", id, it.ID, it.Number, it.URL)
			}
		}
		for _, id := range p.IDs {
			text, ok, err := f.Detail(id)
			if err != nil {
				t.Fatal(err)
			}
			if ok {
				r["detail"] = append(r["detail"].([]any), text)
			} else {
				r["detail"] = append(r["detail"].([]any), nil)
			}
		}
		_ = i
		got = append(got, r)
		inputs = append(inputs, map[string]any{"project": i, "backlog": p.Backlog, "archive": p.Archive, "noBacklog": p.NoBacklog})
	}
	w := make([]any, len(want))
	for i := range want {
		w[i] = want[i]
	}
	n := pytest.Compare(t, "FileBackend", inputs, got, w)
	t.Logf("compared %d projects (%d items found) against FileBackend.fields/detail_text/backlog_markdown and load_backlog_corpus", n, items)
	if items < 100 {
		t.Fatalf("generator found only %d items; the test is too weak", items)
	}
}

func TestFileItemShape(t *testing.T) {
	root := t.TempDir()
	p := project{Root: root, Backlog: "## Bugs\n\n- **[B07] [P1] Title. Part two.** body Milestone: M01\n- **[B08] [P2] Open.** x\n\n## Completed\n\n- ~~**[B09] [P3] Gone.** y~~ Done 2026-01-01 [`abc`] (blocked: need X)\n"}
	p.write(t)
	f := &File{Root: root}
	it, err := f.Get("B07")
	if err != nil {
		t.Fatal(err)
	}
	if it.Type != "B" || it.Tag != "P1" || it.Title != "Title. Part two" || it.Closed || it.Fields.Milestone != "M01" {
		t.Fatalf("B07 = %+v", it)
	}
	it, err = f.Get("B09")
	if err != nil || !it.Closed || it.Reason != "blocked" || it.Note != "need X" || it.Tag != "P3" {
		t.Fatalf("B09 = %+v, %v", it, err)
	}
	if _, err := f.Get("B7"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("B7 must not match B07, got %v", err)
	}
	if _, err := (&File{Root: t.TempDir()}).Markdown(0); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing BACKLOG.md: %v", err)
	}
}

type counterScenario struct {
	Backlog  string   `json:"backlog"`
	Archive  string   `json:"archive"`
	Counters *string  `json:"counters"` // nil = no file
	Kinds    []string `json:"kinds"`
}

const pyNextID = `import json, os, sys, tempfile
from pathlib import Path
from hvlib_backend import FileBackend
res = []
for i, s in enumerate(json.load(open(sys.argv[1]))):
    root = Path(tempfile.mkdtemp())
    (root / ".hv").mkdir()
    (root / ".hv" / "BACKLOG.md").write_text(s["backlog"])
    if s["archive"]:
        (root / ".hv" / "ARCHIVE.md").write_text(s["archive"])
    if s["counters"] is not None:
        (root / ".hv" / "counters.json").write_text(s["counters"])
    os.chdir(root)
    fb = FileBackend()
    ids = []
    for k in s["kinds"]:
        try:
            ids.append(fb.next_id(k))
        except Exception:
            ids.append({"err": True})
    cj = root / ".hv" / "counters.json"
    res.append({"ids": ids, "counters": cj.read_text() if cj.exists() else None})
print(json.dumps(res))`

func TestNextIDMatchesPython(t *testing.T) {
	str := func(s string) *string { return &s }
	backlog := "## Bugs\n- **[B07] [P1] a.** x\n- **[B31] b.**\n## Features\n- **[F02] f.**\n"
	scen := []counterScenario{
		{backlog, "", nil, []string{"bugs", "features", "tasks", "milestones", "bugs"}},
		{backlog, "- ~~**[B50] z.**~~ Done 2026-01-01 [`a`]\n", str(`{"bugs": 3}`), []string{"bugs", "bugs", "features"}},
		{backlog, "", str(`{"tasks": 9, "bugs": 40, "features": 1}`), []string{"bugs", "tasks", "milestones", "features"}},
		{backlog, "", str(`{"since_refactor": {"bugs": 2}, "bugs": 5}`), []string{"bugs", "milestones"}},
		{backlog, "", str(`{"bugs": 99}`), []string{"bugs", "bugs"}},
		{backlog, "", str("{\n  \"bugs\": 1,\n  \"x\": [1, 2]\n}\n"), []string{"features", "bugs"}},
		{backlog, "", str(`not json`), []string{"bugs"}},
		{backlog, "", str(`[1, 2]`), []string{"bugs"}},
		{backlog, "", str(`{"bugs": "7"}`), []string{"bugs"}},
		{backlog, "", str(`{"bugs": null}`), []string{"bugs"}},
		{backlog, "", str(`{"bugs": 2.5}`), []string{"bugs"}},
		{backlog, "", str(`{"bugs": 100.5, "x": 1}`), []string{"bugs", "features"}},
		{backlog, "", str(`{"bugs": 1e2}`), []string{"bugs"}},
		{backlog, "", nil, []string{"epics", "bugs"}},
		{"", "", nil, []string{"tasks", "tasks"}},
		{"[B٧٨] x [M12] [M3]", "", nil, []string{"bugs", "milestones"}},
		{"- **[B0001] a.**", "", nil, []string{"bugs"}},
		{"- **[B100] a.**", "", str(`{"bugs": 1}`), []string{"bugs"}},
	}
	var want []map[string]any
	pytest.JSON(t, pyNextID, scen, &want)

	var inputs, got, w []any
	ids := 0
	for i, s := range scen {
		root := t.TempDir()
		hv := filepath.Join(root, ".hv")
		os.MkdirAll(hv, 0o755)
		os.WriteFile(filepath.Join(hv, "BACKLOG.md"), []byte(s.Backlog), 0o644)
		if s.Archive != "" {
			os.WriteFile(filepath.Join(hv, "ARCHIVE.md"), []byte(s.Archive), 0o644)
		}
		if s.Counters != nil {
			os.WriteFile(filepath.Join(hv, "counters.json"), []byte(*s.Counters), 0o644)
		}
		f := &File{Root: root}
		var res []any
		for _, k := range s.Kinds {
			id, err := f.NextID(k)
			if err != nil {
				res = append(res, map[string]any{"err": true})
			} else {
				res = append(res, id)
				ids++
			}
		}
		r := map[string]any{"ids": res, "counters": nil}
		if raw, err := os.ReadFile(filepath.Join(hv, "counters.json")); err == nil {
			r["counters"] = string(raw)
		}
		got = append(got, r)
		w = append(w, want[i])
		inputs = append(inputs, s)
	}
	n := pytest.Compare(t, "next_id", inputs, got, w)
	t.Logf("compared %d counter scenarios (%d IDs minted), counters.json byte for byte", n, ids)
}
