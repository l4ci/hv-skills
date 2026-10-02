package cli

import (
	"bytes"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// The parity tests run an old bin/ helper and the matching hv verb on copies
// of one fixture and diff the resulting .hv/ trees: the files must be
// byte-identical (docs: round-3 porter rules, parity target).

const knFixtureKnowledge = `# Knowledge

## Architecture

- **Alpha rule** — Keep modules small. <!-- 2026-01-01 -->
- **Beta rule** — Prefer files. <!-- 2026-01-02 -->
- **Old rule** — Retired. <!-- 2026-01-03 -->

## Build

- **Gamma tip** — Run the gate. <!-- 2026-02-01 -->

## Glossary

- **Term** — a definition
`

const knFixtureTier = `{
  "version": 1,
  "entries": {
    "Architecture::Alpha rule": {
      "tier": "confirmed",
      "hits": 4,
      "lastSeen": "2026-03-01"
    },
    "Architecture::Beta rule": {
      "tier": "provisional",
      "hits": 1,
      "lastSeen": "2026-03-02"
    },
    "Architecture::Old rule": {
      "tier": "deprecated",
      "hits": 0,
      "lastSeen": "2026-03-03"
    }
  }
}
`

func knWrite(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o777); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o666); err != nil {
		t.Fatal(err)
	}
}

// knProject writes a fixture project; umbrella adds two registered sub-repos.
func knProject(t *testing.T, umbrella bool) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	knWrite(t, filepath.Join(dir, ".hv", "KNOWLEDGE.md"), knFixtureKnowledge)
	knWrite(t, filepath.Join(dir, ".hv", "knowledge-tier.json"), knFixtureTier)
	if umbrella {
		for _, n := range []string{"web", "api"} {
			if err := os.MkdirAll(filepath.Join(dir, n), 0o777); err != nil {
				t.Fatal(err)
			}
		}
		knWrite(t, filepath.Join(dir, ".hv", "repos.json"), `{
  "repos": [
    {
      "name": "web",
      "path": "web"
    },
    {
      "name": "api",
      "path": "api"
    }
  ]
}
`)
		knWrite(t, filepath.Join(dir, ".hv", "knowledge", "web", "KNOWLEDGE.md"), "# Web\n\n## Architecture\n\n- **Web rule** — Own the UI. <!-- 2026-04-01 -->\n\n## Glossary\n\n- **Page** — a view\n")
	}
	return dir
}

type knOut struct {
	stdout, stderr string
	rc             int
}

func knRepoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Join(wd, "..", "..")
}

// knOld runs an old helper from bin/ in dir.
func knOld(t *testing.T, dir, stdin, helper string, args ...string) knOut {
	t.Helper()
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 not available")
	}
	cmd := exec.Command(filepath.Join(knRepoRoot(t), "bin", helper), args...)
	cmd.Dir = dir
	cmd.Stdin = strings.NewReader(stdin)
	var so, se bytes.Buffer
	cmd.Stdout, cmd.Stderr = &so, &se
	rc := 0
	if err := cmd.Run(); err != nil {
		ee, ok := err.(*exec.ExitError)
		if !ok {
			t.Fatalf("%s: %v", helper, err)
		}
		rc = ee.ExitCode()
	}
	return knOut{so.String(), se.String(), rc}
}

// knNew runs hv in dir.
func knNew(t *testing.T, dir, stdin string, args ...string) knOut {
	t.Helper()
	old, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(old)
	var so, se bytes.Buffer
	rc := Main(args, strings.NewReader(stdin), &so, &se)
	return knOut{so.String(), se.String(), rc}
}

// knTree reads every regular file under dir/.hv into a path → content map.
func knTree(t *testing.T, dir string) map[string]string {
	t.Helper()
	out := map[string]string{}
	root := filepath.Join(dir, ".hv")
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(root, p)
		out[rel] = string(b)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func knSameTree(t *testing.T, a, b string) {
	t.Helper()
	ta, tb := knTree(t, a), knTree(t, b)
	var names []string
	seen := map[string]bool{}
	for k := range ta {
		seen[k] = true
		names = append(names, k)
	}
	for k := range tb {
		if !seen[k] {
			names = append(names, k)
		}
	}
	sort.Strings(names)
	for _, k := range names {
		va, oka := ta[k]
		vb, okb := tb[k]
		switch {
		case oka != okb:
			t.Errorf(".hv/%s: exists in old=%v new=%v", k, oka, okb)
		case va != vb:
			t.Errorf(".hv/%s differs\n--- old ---\n%s\n--- new ---\n%s", k, va, vb)
		}
	}
}

// knStep is one parity case: the old helper call and the hv call that
// replaces it, run on separate copies of the same fixture.
type knStep struct {
	name     string
	oldHelp  string
	oldArgs  []string
	newArgs  []string
	stdin    string
	umbrella bool
	// noStdout skips the stdout comparison (old helpers print status on stderr
	// or nothing, hv prints a human line).
	noStdout bool
	wantRC   int // hv exit code; the old helper's must map to it via rcMap
	oldRC    int
}

func TestKnowledgeWritesMatchOldHelpers(t *testing.T) {
	steps := []knStep{
		{name: "add new bullet", oldHelp: "hv-knowledge-merge",
			oldArgs: []string{"--topic", "Build", "--title", "Delta tip", "--date", "2026-05-05", "--body", "Use the shim."},
			newArgs: []string{"knowledge", "add", "--topic", "Build", "--title", "Delta tip", "--date", "2026-05-05", "--body-file", "-"},
			stdin:   "Use the shim.\n", noStdout: true},
		{name: "add duplicate title is a no-op", oldHelp: "hv-knowledge-merge",
			oldArgs: []string{"--topic", "Architecture", "--title", "alpha RULE", "--body", "x"},
			newArgs: []string{"knowledge", "add", "--topic", "Architecture", "--title", "alpha RULE", "--body-file", "-"},
			stdin:   "x", noStdout: true},
		{name: "add to sub-repo scope", oldHelp: "hv-knowledge-merge", umbrella: true,
			oldArgs: []string{"--repo", "web", "--topic", "Architecture", "--title", "Web two", "--date", "2026-05-06", "--body", "More UI."},
			newArgs: []string{"knowledge", "add", "--repo", "web", "--topic", "Architecture", "--title", "Web two", "--date", "2026-05-06", "--body-file", "-"},
			stdin:   "More UI.", noStdout: true},
		{name: "add under missing topic", oldHelp: "hv-knowledge-merge",
			oldArgs: []string{"--topic", "Nope", "--title", "t", "--body", "b"},
			newArgs: []string{"knowledge", "add", "--topic", "Nope", "--title", "t", "--body-file", "-"},
			stdin:   "b", noStdout: true, oldRC: 1, wantRC: 3},
		{name: "amend", oldHelp: "hv-knowledge-amend",
			oldArgs: []string{"--topic", "Architecture", "--fragment", "Beta", "--append", "(see #12)"},
			newArgs: []string{"knowledge", "amend", "--topic", "Architecture", "--fragment", "Beta", "--mode", "append", "--body-file", "-"},
			stdin:   "(see #12)\n", noStdout: true},
		{name: "amend in sub-repo", oldHelp: "hv-knowledge-amend", umbrella: true,
			oldArgs: []string{"--repo", "web", "--topic", "Architecture", "--fragment", "Web rule", "--append", "extra"},
			newArgs: []string{"knowledge", "amend", "--repo", "web", "--topic", "Architecture", "--fragment", "Web rule", "--mode", "append", "--body-file", "-"},
			stdin:   "extra", noStdout: true},
		{name: "amend finds nothing", oldHelp: "hv-knowledge-amend",
			oldArgs: []string{"--topic", "Architecture", "--fragment", "zzz", "--append", "q"},
			newArgs: []string{"knowledge", "amend", "--topic", "Architecture", "--fragment", "zzz", "--mode", "append", "--body-file", "-"},
			stdin:   "q", noStdout: true, oldRC: 1, wantRC: 3},
		{name: "rename whole topic", oldHelp: "hv-knowledge-rename-topic",
			oldArgs: []string{"--from", "Architecture", "--to", "Design"},
			newArgs: []string{"knowledge", "rename-topic", "--from", "Architecture", "--to", "Design"}, noStdout: true},
		{name: "rename onto existing topic", oldHelp: "hv-knowledge-rename-topic",
			oldArgs: []string{"--from", "Architecture", "--to", "Build"},
			newArgs: []string{"knowledge", "rename-topic", "--from", "Architecture", "--to", "Build"}, noStdout: true, oldRC: 1, wantRC: 4},
		{name: "move one bullet", oldHelp: "hv-knowledge-rename-topic",
			oldArgs: []string{"--from", "Architecture", "--to", "Build", "--title", "Beta rule"},
			newArgs: []string{"knowledge", "rename-topic", "--from", "Architecture", "--to", "Build", "--title", "Beta rule"}, noStdout: true},
		{name: "move one bullet backwards", oldHelp: "hv-knowledge-rename-topic",
			oldArgs: []string{"--from", "Build", "--to", "Architecture", "--title", "Gamma tip"},
			newArgs: []string{"knowledge", "rename-topic", "--from", "Build", "--to", "Architecture", "--title", "Gamma tip"}, noStdout: true},
		{name: "tier set", oldHelp: "hv-knowledge-tier",
			oldArgs: []string{"--set", "--topic", "Architecture", "--title", "Beta rule", "--tier", "confirmed"},
			newArgs: []string{"knowledge", "tier", "set", "--topic", "Architecture", "--title", "Beta rule", "--tier", "confirmed"}, noStdout: true},
		{name: "tier set untracked", oldHelp: "hv-knowledge-tier",
			oldArgs: []string{"--set", "--topic", "Build", "--title", "Gamma tip", "--tier", "deprecated"},
			newArgs: []string{"knowledge", "tier", "set", "--topic", "Build", "--title", "Gamma tip", "--tier", "deprecated"}, noStdout: true},
		{name: "hit increments", oldHelp: "hv-knowledge-hit",
			oldArgs: []string{"--topic", "Architecture", "--title", "Beta rule"},
			newArgs: []string{"knowledge", "hit", "--topic", "Architecture", "--title", "Beta rule"}, noStdout: true},
		{name: "hit creates untracked", oldHelp: "hv-knowledge-hit",
			oldArgs: []string{"--topic", "Build", "--title", "Gamma tip"},
			newArgs: []string{"knowledge", "hit", "--topic", "Build", "--title", "Gamma tip"}, noStdout: true},
		{name: "contradiction add", oldHelp: "hv-knowledge-contradiction",
			oldArgs: []string{"--add", "--topic", "Architecture", "--title", "Beta rule", "--text", "no, use dirs"},
			newArgs: []string{"knowledge", "contradiction", "add", "--topic", "Architecture", "--title", "Beta rule", "--text", "no, use dirs"}, noStdout: true},
		{name: "contradiction clear", oldHelp: "hv-knowledge-contradiction",
			oldArgs: []string{"--clear"},
			newArgs: []string{"knowledge", "contradiction", "clear"}, noStdout: true},
	}
	for _, s := range steps {
		t.Run(s.name, func(t *testing.T) {
			oldDir, newDir := knProject(t, s.umbrella), knProject(t, s.umbrella)
			o := knOld(t, oldDir, s.stdin, s.oldHelp, s.oldArgs...)
			n := knNew(t, newDir, s.stdin, s.newArgs...)
			if o.rc != s.oldRC {
				t.Fatalf("old helper rc = %d, want %d; stderr: %s", o.rc, s.oldRC, o.stderr)
			}
			if n.rc != s.wantRC {
				t.Fatalf("hv rc = %d, want %d; stderr: %s", n.rc, s.wantRC, n.stderr)
			}
			knSameTree(t, oldDir, newDir)
		})
	}
}

// TestKnowledgeSequenceMatchesOldHelpers chains calls so state accumulates,
// including auto-promotion at the hit threshold.
func TestKnowledgeSequenceMatchesOldHelpers(t *testing.T) {
	oldDir, newDir := knProject(t, false), knProject(t, false)
	for i := 0; i < 3; i++ {
		knOld(t, oldDir, "", "hv-knowledge-hit", "--topic", "Architecture", "--title", "Beta rule")
		knNew(t, newDir, "", "knowledge", "hit", "--topic", "Architecture", "--title", "Beta rule")
	}
	knSameTree(t, oldDir, newDir)
	if tier := knTree(t, newDir)["knowledge-tier.json"]; !strings.Contains(tier, `"tier": "confirmed"`) {
		t.Fatalf("Beta rule not promoted:\n%s", tier)
	}

	// A pending contradiction blocks promotion.
	knOld(t, oldDir, "", "hv-knowledge-contradiction", "--add", "--topic", "Build", "--title", "Gamma tip", "--text", "c")
	knNew(t, newDir, "", "knowledge", "contradiction", "add", "--topic", "Build", "--title", "Gamma tip", "--text", "c")
	for i := 0; i < 4; i++ {
		knOld(t, oldDir, "", "hv-knowledge-hit", "--topic", "Build", "--title", "Gamma tip")
		knNew(t, newDir, "", "knowledge", "hit", "--topic", "Build", "--title", "Gamma tip")
	}
	// loggedAt differs by wall clock: compare everything else.
	to, tn := knTree(t, oldDir), knTree(t, newDir)
	if to["knowledge-tier.json"] != tn["knowledge-tier.json"] {
		t.Errorf("tier sidecar differs\nold:\n%s\nnew:\n%s", to["knowledge-tier.json"], tn["knowledge-tier.json"])
	}
	if !strings.Contains(tn["knowledge-tier.json"], `"Build::Gamma tip": {
      "tier": "provisional",
      "hits": 4`) {
		t.Errorf("promotion was not blocked:\n%s", tn["knowledge-tier.json"])
	}
}

func TestKnowledgeQueryMatchesOldHelper(t *testing.T) {
	cases := []struct {
		name     string
		umbrella bool
		oldArgs  []string
		newArgs  []string
	}{
		{"topics in document order", false, []string{"Build", "Architecture"}, []string{"knowledge", "query", "Build", "Architecture"}},
		{"case-insensitive", false, []string{"architecture"}, []string{"knowledge", "query", "architecture"}},
		{"include deprecated", false, []string{"--include-deprecated", "Architecture"}, []string{"knowledge", "query", "--include-deprecated", "Architecture"}},
		{"tier filter", false, []string{"--tier", "confirmed", "Architecture"}, []string{"knowledge", "query", "--tier", "confirmed", "Architecture"}},
		{"unmatched topic", false, []string{"Architecture", "Nope"}, []string{"knowledge", "query", "Architecture", "Nope"}},
		{"sub-repo hybrid", true, []string{"--repo", "web", "Architecture", "Build"}, []string{"knowledge", "query", "--repo", "web", "Architecture", "Build"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := knProject(t, c.umbrella)
			o := knOld(t, dir, "", "hv-knowledge-query", c.oldArgs...)
			n := knNew(t, dir, "", c.newArgs...)
			if o.stdout != n.stdout {
				t.Errorf("stdout differs\n--- old ---\n%s\n--- new ---\n%s", o.stdout, n.stdout)
			}
			if o.rc != 0 || n.rc != 0 {
				t.Errorf("rc old=%d new=%d", o.rc, n.rc)
			}
			warnOld := strings.Count(o.stderr, "no topic heading matches")
			warnNew := strings.Count(n.stderr, "no topic heading matches")
			if warnOld != warnNew {
				t.Errorf("warnings old=%d new=%d\n%s", warnOld, warnNew, n.stderr)
			}
		})
	}
}

func TestKnowledgeStatsMatchesOldHelper(t *testing.T) {
	dir := knProject(t, false)
	o := knOld(t, dir, "", "hv-knowledge-stats")
	n := knNew(t, dir, "", "knowledge", "stats", "--json")
	for _, want := range []string{`"name": "Architecture", "bullets": 3`, `"name": "Glossary"`} {
		if !strings.Contains(n.stdout, want) {
			t.Errorf("stats missing %s: %s", want, n.stdout)
		}
	}
	if !strings.Contains(o.stdout, `"bullets": 3`) {
		t.Fatalf("old stats unexpected: %s", o.stdout)
	}
}

func TestKnowledgeTierReadsMatchOldHelper(t *testing.T) {
	dir := knProject(t, false)
	o := knOld(t, dir, "", "hv-knowledge-tier", "--list", "--tier", "confirmed")
	n := knNew(t, dir, "", "knowledge", "tier", "list", "--tier", "confirmed", "--json")
	if !strings.Contains(o.stdout, `"title": "Alpha rule"`) || !strings.Contains(n.stdout, `"title": "Alpha rule"`) || strings.Contains(n.stdout, "Beta") {
		t.Errorf("old=%s\nnew=%s", o.stdout, n.stdout)
	}
	g := knNew(t, dir, "", "knowledge", "tier", "get", "--topic", "Architecture", "--title", "Nope", "--json")
	if g.rc != 0 || !strings.Contains(g.stdout, `"found": false`) {
		t.Errorf("get untracked: rc=%d %s", g.rc, g.stdout)
	}
	g = knNew(t, dir, "", "knowledge", "tier", "get", "--topic", "Architecture", "--title", "Alpha rule", "--json")
	if !strings.Contains(g.stdout, `"tier": "confirmed", "hits": 4, "lastSeen": "2026-03-01"`) {
		t.Errorf("get: %s", g.stdout)
	}
}

func TestKnowledgeContractErrors(t *testing.T) {
	dir := knProject(t, false)
	cases := []struct {
		name string
		args []string
		rc   int
	}{
		{"query with no topic", []string{"knowledge", "query"}, 2},
		{"query bad tier", []string{"knowledge", "query", "--tier", "x", "Build"}, 2},
		{"add missing flag", []string{"knowledge", "add", "--topic", "Build", "--body-file", "-"}, 2},
		{"amend bad mode", []string{"knowledge", "amend", "--topic", "Build", "--fragment", "G", "--mode", "replace", "--body-file", "-"}, 2},
		{"tier set bad tier", []string{"knowledge", "tier", "set", "--topic", "Build", "--title", "t", "--tier", "bogus"}, 2},
		{"repo outside umbrella", []string{"knowledge", "query", "--repo", "web", "Build"}, 3},
		{"contradiction has miss", []string{"knowledge", "contradiction", "has", "--topic", "Build", "--title", "t"}, 1},
		{"stats rejects --repo", []string{"knowledge", "stats", "--repo", "web"}, 2},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := knNew(t, dir, "x", c.args...); got.rc != c.rc {
				t.Errorf("rc = %d, want %d; stderr: %s", got.rc, c.rc, got.stderr)
			}
		})
	}
}

func TestKnowledgeHitJSON(t *testing.T) {
	dir := knProject(t, false)
	var last knOut
	for i := 0; i < 2; i++ {
		last = knNew(t, dir, "", "knowledge", "hit", "--topic", "Architecture", "--title", "Beta rule", "--json")
	}
	want := `{"ok": true, "data": {"topic": "Architecture", "title": "Beta rule", "hits": 3, "tier": "confirmed", "promoted": true, "promotionBlocked": false, "changed": true}}`
	if strings.TrimSpace(last.stdout) != want {
		t.Errorf("got  %s\nwant %s", last.stdout, want)
	}
	g := knNew(t, dir, "", "knowledge", "hit", "--topic", "Glossary", "--title", "Term", "--json")
	if !strings.Contains(g.stdout, `"hits": 0, "tier": "provisional", "promoted": false, "promotionBlocked": false, "changed": false`) {
		t.Errorf("glossary hit: %s", g.stdout)
	}
}
