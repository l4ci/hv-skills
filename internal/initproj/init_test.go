package initproj

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/l4ci/rota/internal/config"
	"github.com/l4ci/rota/internal/pytest"
)

// fixture is a starting tree: path (relative to the root) to content.
type fixture map[string]string

var fixtures = map[string]fixture{
	"empty": {},
	"legacy-todo": {
		".rota/TODO.md": "# Backlog\n\n## Bugs\n- [B01] old\n",
	},
	"todo-and-backlog": {
		".rota/TODO.md":    "# Old\n",
		".rota/BACKLOG.md": "# Backlog\n\n## Bugs\n- [B09] mine\n",
	},
	"vision-heading": {
		".rota/MILESTONES.md": "# Vision\n\nbody line\n# Vision\n",
	},
	"old-counters": {
		".rota/counters.json": `{"bugs":3,"features":1,"tasks":2}` + "\n",
	},
	"old-counters-pretty": {
		".rota/counters.json": "{\n  \"bugs\": 7,\n  \"milestones\": 2\n}\n",
	},
	"knowledge-preamble": {
		".rota/KNOWLEDGE.md": "# Knowledge\n\nUse `/hv:learn` to save and `/hv:work` to read.\n\n## Topic\n\n- see `/hv:ship` here\n",
	},
	"gitignore-blanket": {
		".gitignore": "node_modules/\n.rota/\ndist/\n",
	},
	"gitignore-no-newline": {
		".gitignore": "node_modules/\n.rota/status.json",
	},
	"gitignore-complete": {
		".gitignore": strings.Join(ignoreLines, "\n") + "\n",
	},
	"gitignore-worktrees-spellings": {
		".gitignore": "/.worktrees\n",
	},
	"gitignore-worktrees-crlf": {
		".gitignore": "dist/\r\n.worktrees/\r\n",
	},
	"gitignore-only-blanket": {
		".gitignore": ".rota/\n",
	},
	"initialized": {
		".rota/BACKLOG.md":    "# Backlog\n\n## Bugs\n\n## Features\n\n## Tasks\n\n## Completed\n",
		".rota/KNOWLEDGE.md":  "# Knowledge\n\nmine\n",
		".rota/DECISIONS.md":  "# Decisions\n",
		".rota/MAP.md":        "# Project map\n\nmine\n",
		".rota/MILESTONES.md": "# Milestones\n",
		".rota/counters.json": `{"bugs":1,"features":2,"tasks":3,"milestones":4,"since_refactor":{"features":5,"bugs":6}}` + "\n",
		".rota/status.json":   `{"active":[]}` + "\n",
		".rota/repos.json":    `{"repos":[]}` + "\n",
		".rota/config.json":   `{"work":{"isolation":"worktree"}}` + "\n",
	},
}

func names() []string {
	var n []string
	for k := range fixtures {
		n = append(n, k)
	}
	sort.Strings(n)
	return n
}

func writeFixture(t *testing.T, dir string, f fixture) {
	t.Helper()
	for p, c := range f {
		full := filepath.Join(dir, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(c), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// readTree is every path under dir (directories as "/"), minus what the
// comparison ignores.
func readTree(t *testing.T, dir string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(dir, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(dir, p)
		if rel == "." {
			return nil
		}
		if d.IsDir() {
			out[rel] = "/"
			return nil
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		out[rel] = string(b)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

// TestInitMatchesBootstrapGolden checks that Init leaves the tree the old
// hv-bootstrap left on every fixture, as recorded in testdata/golden. The
// deliberate differences are the ones in the A9 rulings: no `.rota/bin` directory, the G4 MAP.md text and the G7 config.json key order, plus B2's
// `.rota/verdicts.json` line in the .gitignore block (#55), edited into the golden by hand.
func TestInitMatchesBootstrapGolden(t *testing.T) {
	var want map[string]map[string]string
	pytest.Golden(t, fixtures, &want)
	for _, name := range names() {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			writeFixture(t, dir, fixtures[name])
			if _, err := Init(dir); err != nil {
				t.Fatal(err)
			}
			got, exp := readTree(t, dir), want[name]
			delete(exp, ".rota/bin")
			for _, tree := range []map[string]string{got, exp} {
				if _, mine := fixtures[name][".rota/MAP.md"]; !mine {
					delete(tree, ".rota/MAP.md")
				}
				if _, mine := fixtures[name][".rota/config.json"]; !mine {
					delete(tree, ".rota/config.json")
				}
			}
			if !reflect.DeepEqual(got, exp) {
				for p := range exp {
					if got[p] != exp[p] {
						t.Errorf("%s differs\n got: %q\nwant: %q", p, got[p], exp[p])
					}
				}
				for p := range got {
					if _, ok := exp[p]; !ok {
						t.Errorf("extra path %s", p)
					}
				}
			}
		})
	}
}

func TestInitIsIdempotent(t *testing.T) {
	for _, name := range names() {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			writeFixture(t, dir, fixtures[name])
			if _, err := Init(dir); err != nil {
				t.Fatal(err)
			}
			first := readTree(t, dir)
			res, err := Init(dir)
			if err != nil {
				t.Fatal(err)
			}
			if res.Changed() || len(res.Warnings) > 1 {
				t.Errorf("second run: %+v", res)
			}
			if !reflect.DeepEqual(first, readTree(t, dir)) {
				t.Error("second run changed the tree")
			}
		})
	}
}

func TestInitCreatedListsTheDiff(t *testing.T) {
	dir := t.TempDir()
	res, err := Init(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{".gitignore", ".rota", ".rota/BACKLOG.md", ".rota/bugs", ".rota/map", ".rota/config.json", ".rota/status.json"} {
		if !contains(res.Created, p) {
			t.Errorf("created lacks %s: %v", p, res.Created)
		}
	}
	if contains(res.Created, ".rota/bin") {
		t.Error("init created .rota/bin")
	}
	if !sort.StringsAreSorted(res.Created) || !res.Changed() {
		t.Errorf("created %v changed %v", res.Created, res.Changed())
	}
}

func contains(l []string, s string) bool {
	for _, x := range l {
		if x == s {
			return true
		}
	}
	return false
}

// The seed's keys appear in the order config.Keys lists them (G7).
func TestSeedConfigKeepsSchemaOrder(t *testing.T) {
	schema := map[string]int{}
	for i, k := range config.Keys {
		schema[k.Name] = i
	}
	seed := []string{"issues.providers.github", "issues.providers.gitlab", "issues.label", "issues.autoCreateLabel", "issues.filterMineOnly"}
	prevSchema, prevText := -1, -1
	for _, name := range seed {
		i, ok := schema[name]
		at := strings.Index(configSeed, `"`+name[strings.LastIndex(name, ".")+1:]+`"`)
		if !ok || at < 0 {
			t.Fatalf("%s: in schema %v, in seed at %d", name, ok, at)
		}
		if i <= prevSchema || at <= prevText {
			t.Errorf("%s breaks schema order", name)
		}
		prevSchema, prevText = i, at
	}
	var v map[string]any
	if err := json.Unmarshal([]byte(configSeed), &v); err != nil {
		t.Fatal(err)
	}
}

func TestInitRefusesACorruptCounters(t *testing.T) {
	for _, body := range []string{"{not json", "[]", ""} {
		dir := t.TempDir()
		writeFixture(t, dir, fixture{".rota/counters.json": body})
		_, err := Init(dir)
		if err == nil || !strings.Contains(err.Error(), "counters.json") {
			t.Errorf("%q: %v", body, err)
		}
		if got := readTree(t, dir)[".rota/counters.json"]; got != body {
			t.Errorf("%q: counters rewritten to %q", body, got)
		}
		// nothing else was written: exit 70 leaves the tree as it was
		if tree := readTree(t, dir); len(tree) != 2 {
			t.Errorf("%q: refused init left %v", body, tree)
		}
	}
}

func TestInitWarnsOnLegacyTodoBesideBacklog(t *testing.T) {
	dir := t.TempDir()
	writeFixture(t, dir, fixtures["todo-and-backlog"])
	res, err := Init(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Warnings) != 1 || !strings.Contains(res.Warnings[0], "TODO.md") {
		t.Errorf("warnings: %v", res.Warnings)
	}
}

func TestInitRemovesTheStaleMirror(t *testing.T) {
	dir := t.TempDir()
	writeFixture(t, dir, fixture{
		".rota/bin/hv-preflight":          "#!/bin/sh\n",
		".rota/bin/hvlib.py":              "",
		".rota/bin/hvlib_io.py":           "",
		".rota/bin/__pycache__/hvlib.pyc": "x",
	})
	res, err := Init(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, ".rota", "bin")); !os.IsNotExist(err) {
		t.Errorf(".rota/bin survived: %v", err)
	}
	want := []string{".rota/bin", ".rota/bin/__pycache__", ".rota/bin/hv-preflight", ".rota/bin/hvlib.py", ".rota/bin/hvlib_io.py"}
	if !reflect.DeepEqual(res.Removed, want) || !res.Changed() {
		t.Errorf("removed %v", res.Removed)
	}
}

func TestInitKeepsCustomFilesInTheMirror(t *testing.T) {
	dir := t.TempDir()
	writeFixture(t, dir, fixture{".rota/bin/hv-x": "", ".rota/bin/mine.sh": "keep"})
	res, err := Init(dir)
	if err != nil {
		t.Fatal(err)
	}
	if readTree(t, dir)[".rota/bin/mine.sh"] != "keep" || contains(res.Removed, ".rota/bin") {
		t.Errorf("custom file lost: %v", res.Removed)
	}
	if len(res.Warnings) != 1 || !strings.Contains(res.Warnings[0], ".rota/bin/mine.sh") {
		t.Errorf("warnings: %v", res.Warnings)
	}
}

func TestMergeGitignoreKeepsTheUmbrellaBlanket(t *testing.T) {
	in := strings.Join(ignoreLines, "\n") + "\n.rota/\n.worktrees/\n"
	if got := MergeGitignore(in, true, true); got != in {
		t.Errorf("umbrella root rewrote .gitignore:\n%q", got)
	}
	if got := MergeGitignore(in, true, false); strings.Contains(got, "\n.rota/\n") {
		t.Errorf("single repo kept the blanket line:\n%q", got)
	}
}

func TestMergeGitignore(t *testing.T) {
	block := strings.Join(ignoreLines, "\n") + "\n"
	oldHeaderBlock := strings.Join(append([]string{"# ── hv-skills ──"}, ignoreLines[1:]...), "\n") + "\n"
	cases := []struct {
		name, in string
		exists   bool
		want     string
	}{
		{"new", "", false, block + worktreesBlock},
		{"empty file", "", true, "\n" + block + worktreesBlock},
		{"complete", block + ".worktrees/\n", true, block + ".worktrees/\n"},
		{"slash spelling", block + "/.worktrees\n", true, block + "/.worktrees\n"},
		{"crlf worktrees", block + ".worktrees/\r\n", true, block + ".worktrees/\r\n"},
		{"blanket stripped", "a\n.rota/\nb\n", true, "a\nb\n\n" + block + worktreesBlock},
		{"only blanket kept", ".rota/\n", true, "\n" + block + worktreesBlock},
		{"no trailing newline", "a", true, "a\n" + block + worktreesBlock},
		// A block written before the rename (#231) keeps its old header: the
		// header is cosmetic and never checked, so nothing is appended.
		{"pre-rename header", oldHeaderBlock + ".worktrees/\n", true, oldHeaderBlock + ".worktrees/\n"},
	}
	for _, c := range cases {
		got := MergeGitignore(c.in, c.exists, false)
		if got != c.want {
			t.Errorf("%s:\n got %q\nwant %q", c.name, got, c.want)
		}
	}
}

// Each migration step alone makes the run changed, though nothing is created.
func TestInitChangedWhenOnlyAMigrationWrote(t *testing.T) {
	seeded := func(t *testing.T) string {
		dir := t.TempDir()
		if _, err := Init(dir); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	for name, mutate := range map[string]func(dir string){
		"counters backfill": func(d string) {
			os.WriteFile(filepath.Join(d, ".rota", "counters.json"), []byte(`{"bugs": 3}`), 0o644)
		},
		"gitignore block": func(d string) { os.WriteFile(filepath.Join(d, ".gitignore"), []byte("x\n"), 0o644) },
		"milestones heading": func(d string) {
			os.WriteFile(filepath.Join(d, ".rota", "MILESTONES.md"), []byte("# Vision\n"), 0o644)
		},
		"knowledge preamble": func(d string) {
			os.WriteFile(filepath.Join(d, ".rota", "KNOWLEDGE.md"), []byte("Use `/hv:learn`.\n"), 0o644)
		},
	} {
		dir := seeded(t)
		mutate(dir)
		res, err := Init(dir)
		if err != nil {
			t.Fatal(err)
		}
		if len(res.Created) != 0 || !res.Changed() {
			t.Errorf("%s: created %v changed %v", name, res.Created, res.Changed())
		}
		if again, _ := Init(dir); again.Changed() {
			t.Errorf("%s: second run changed", name)
		}
	}
}
