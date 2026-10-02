package section

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const doc = "# Title\n\n## One\n\n- a\n- b\n\n## Two  \n\n- c\n\n## Three\n"

func TestFindAndBody(t *testing.T) {
	s, e, ok := Find(doc, "Two")
	if !ok || strings.TrimSpace(doc[s:e]) != "- c" {
		t.Fatalf("Two = %q ok=%v", doc[s:e], ok)
	}
	if Body(doc, "Three") != "" && strings.TrimSpace(Body(doc, "Three")) != "" {
		t.Errorf("Three body = %q", Body(doc, "Three"))
	}
	if _, _, ok := Find(doc, "Missing"); ok {
		t.Error("found a missing section")
	}
	// Names are matched literally, not as patterns.
	if _, _, ok := Find("## a.c\nx\n", "abc"); ok {
		t.Error("name treated as a pattern")
	}
}

func TestTopics(t *testing.T) {
	got := Topics(doc)
	names := []string{}
	for _, tp := range got {
		names = append(names, tp.Name)
	}
	if strings.Join(names, "|") != "One|Two|Three" {
		t.Fatalf("names = %v", names)
	}
	if got[0].Body != "\n\n- a\n- b\n\n" {
		t.Errorf("body = %q", got[0].Body)
	}
}

func TestMatching(t *testing.T) {
	out := Matching(doc, map[string]bool{"two": true, "one": true})
	want := "## One\n\n\n- a\n- b\n\n## Two\n\n\n- c\n"
	if out != want {
		t.Errorf("got %q want %q", out, want)
	}
	if Matching(doc, map[string]bool{"none": true}) != "" {
		t.Error("expected empty output")
	}
}

func TestReplaceAppendsMissingSection(t *testing.T) {
	got := Replace("## A\nx\n", "B", "\n- y\n")
	if got != "## A\nx\n\n## B\n\n- y\n" {
		t.Errorf("got %q", got)
	}
}

func TestInstructionsFile(t *testing.T) {
	dir := t.TempDir()
	if got := InstructionsFile(dir); filepath.Base(got) != "CLAUDE.md" {
		t.Errorf("no files: %s", got)
	}
	os.WriteFile(filepath.Join(dir, "AGENTS.md"), nil, 0o666)
	if got := InstructionsFile(dir); filepath.Base(got) != "AGENTS.md" {
		t.Errorf("with AGENTS.md: %s", got)
	}
}

func TestUpsertBlockIsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "CLAUDE.md")
	block := "<!-- hv-x-start -->\nbody\n<!-- hv-x-end -->"
	steps := []struct{ block, want string }{
		{block, Created},
		{block, Unchanged},
		{"<!-- hv-x-start -->\nnew\n<!-- hv-x-end -->", Updated},
		{"<!-- hv-x-start -->\nnew\n<!-- hv-x-end -->", Unchanged},
	}
	for i, s := range steps {
		got, err := UpsertBlock(path, "x", s.block, "")
		if err != nil || got != s.want {
			t.Fatalf("step %d: %q %v, want %q", i, got, err, s.want)
		}
	}
	raw, _ := os.ReadFile(path)
	if string(raw) != "<!-- hv-x-start -->\nnew\n<!-- hv-x-end -->\n" {
		t.Errorf("file = %q", raw)
	}
}

func TestUpsertBlockAppendsAndMigratesLegacy(t *testing.T) {
	path := filepath.Join(t.TempDir(), "AGENTS.md")
	os.WriteFile(path, []byte("# Project\n\ntext\n"), 0o666)
	got, err := UpsertBlock(path, "knowledge", "<!-- hv-knowledge-start -->\nA\n<!-- hv-knowledge-end -->", "knowledge")
	if err != nil || got != Appended {
		t.Fatalf("append: %q %v", got, err)
	}
	// A legacy-marker block is replaced in place by the canonical form.
	os.WriteFile(path, []byte("top\n<!-- hv:knowledge:start -->\nold\n<!-- hv:knowledge:end -->\nbottom\n"), 0o666)
	got, err = UpsertBlock(path, "knowledge", "<!-- hv-knowledge-start -->\nA\n<!-- hv-knowledge-end -->", "knowledge")
	if err != nil || got != Updated {
		t.Fatalf("legacy: %q %v", got, err)
	}
	raw, _ := os.ReadFile(path)
	if string(raw) != "top\n<!-- hv-knowledge-start -->\nA\n<!-- hv-knowledge-end -->\nbottom\n" {
		t.Errorf("file = %q", raw)
	}
}

func TestLinesMatchesPythonSplitlines(t *testing.T) {
	in := "a\nb\r\nc\rd\v e\f\u0085f g h\n"
	got := strings.Join(Lines(in), "|")
	if got != "a|b|c|d| e||f|g|h" {
		t.Errorf("got %q", got)
	}
	if len(Lines("")) != 0 || len(Lines("\n")) != 1 || len(Lines("x")) != 1 {
		t.Error("edge cases")
	}
}
