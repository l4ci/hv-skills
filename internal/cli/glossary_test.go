package cli

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/knowledge"
)

const glFixture = `# Knowledge

## Architecture

- **Alpha rule** — Keep modules small. <!-- 2026-01-01 -->

## Glossary

_(no terms yet — use /hv-learn --term)_
`

const glFixtureTerms = `# Knowledge

## Architecture

- **Alpha rule** — Keep modules small. <!-- 2026-01-01 -->

## Glossary

- **Worker** — an agent in a round
  - **Aliases:** agent, slot
  - **Not:** orchestrator
  <!-- 2026-02-02 -->

- **Round** — one cycle of work
  - **Aliases:** _none_
  <!-- 2026-02-03 -->
`

func glProject(t *testing.T, umbrella bool, knowledge string) string {
	dir := knProject(t, umbrella)
	knWrite(t, filepath.Join(dir, ".hv", "KNOWLEDGE.md"), knowledge)
	knWrite(t, filepath.Join(dir, "AGENTS.md"), "# Agents\n\nintro\n")
	if umbrella {
		knWrite(t, filepath.Join(dir, ".hv", "knowledge", "web", "KNOWLEDGE.md"), "# Web\n\n## Architecture\n\n- **Web rule** — UI. <!-- 2026-04-01 -->\n\n## Glossary\n\n_(no terms yet)_\n")
		knWrite(t, filepath.Join(dir, "web", "CLAUDE.md"), "# Web\n")
	}
	return dir
}

func TestGlossaryWriteMatchesOldHelper(t *testing.T) {
	cases := []struct {
		name     string
		fixture  string
		umbrella bool
		oldArgs  []string
		newArgs  []string
		oldRC    int
		wantRC   int
	}{
		{"new term in empty glossary", glFixture, false,
			[]string{"Worker", "--def", "an agent", "--alias", "agent, slot", "--not", "orchestrator"},
			[]string{"glossary", "write", "Worker", "--def", "an agent", "--alias", "agent, slot", "--not", "orchestrator"}, 0, 0},
		{"second term sorts alphabetically", glFixtureTerms, false,
			[]string{"Batch", "--def", "a group"},
			[]string{"glossary", "write", "Batch", "--def", "a group"}, 0, 0},
		{"update keeps date and unions aliases", glFixtureTerms, false,
			[]string{"worker", "--def", "a new def", "--alias", "Agent,runner"},
			[]string{"glossary", "write", "worker", "--def", "a new def", "--alias", "Agent,runner"}, 0, 0},
		{"touch restamps the date", glFixtureTerms, false,
			[]string{"Round", "--def", "one cycle", "--touch"},
			[]string{"glossary", "write", "Round", "--def", "one cycle", "--touch"}, 0, 0},
		{"empty --not clears the list", glFixtureTerms, false,
			[]string{"Worker", "--def", "d", "--not", ""},
			[]string{"glossary", "write", "Worker", "--def", "d", "--not", ""}, 0, 0},
		{"omitting --not keeps the list", glFixtureTerms, false,
			[]string{"Worker", "--def", "d"},
			[]string{"glossary", "write", "Worker", "--def", "d"}, 0, 0},
		{"alias collision refuses", glFixtureTerms, false,
			[]string{"Newbie", "--def", "d", "--alias", "agent"},
			[]string{"glossary", "write", "Newbie", "--def", "d", "--alias", "agent"}, 3, 4},
		{"sub-repo scope", glFixture, true,
			[]string{"Page", "--def", "a view", "--repo", "web"},
			[]string{"glossary", "write", "Page", "--def", "a view", "--repo", "web"}, 0, 0},
		{"missing Glossary heading", "# K\n\n## Architecture\n\n- **a** — b <!-- 2026-01-01 -->\n", false,
			[]string{"T", "--def", "d"},
			[]string{"glossary", "write", "T", "--def", "d"}, 2, 3},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			oldDir, newDir := glProject(t, c.umbrella, c.fixture), glProject(t, c.umbrella, c.fixture)
			o := knOld(t, oldDir, "", "hv-glossary-write", c.oldArgs...)
			n := knNew(t, newDir, "", c.newArgs...)
			if o.rc != c.oldRC || n.rc != c.wantRC {
				t.Fatalf("rc old=%d (want %d) new=%d (want %d)\nold: %s\nnew: %s", o.rc, c.oldRC, n.rc, c.wantRC, o.stderr, n.stderr)
			}
			knSameTree(t, oldDir, newDir)
		})
	}
}

func TestGlossaryImportMatchesOldHelper(t *testing.T) {
	good := "# comment\nWorker\tan agent\tagent,slot\torchestrator\n\nRound\tone cycle\t\t\nBatch\ta group\tbunch\t\n"
	cases := []struct {
		name, manifest string
		args           []string
		oldRC, wantRC  int
	}{
		{"imports a batch", good, nil, 0, 0},
		{"touch", good, []string{"--touch"}, 0, 0},
		{"empty manifest is a no-op", "# only a comment\n", nil, 0, 0},
		{"alias collision inside the batch", "A\td\tx\t\nB\td\tX\t\n", nil, 3, 4},
		{"repeated term", "A\td\t\t\nA\te\t\t\n", nil, 3, 4},
		{"missing definition", "A\t\t\t\n", nil, 2, 2},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			oldDir, newDir := glProject(t, false, glFixtureTerms), glProject(t, false, glFixtureTerms)
			mf := filepath.Join(t.TempDir(), "manifest.tsv")
			os.WriteFile(mf, []byte(c.manifest), 0o666)
			o := knOld(t, oldDir, "", "hv-glossary-import", append([]string{mf}, c.args...)...)
			n := knNew(t, newDir, c.manifest, append([]string{"glossary", "import", "--body-file", "-"}, c.args...)...)
			if o.rc != c.oldRC || n.rc != c.wantRC {
				t.Fatalf("rc old=%d (want %d) new=%d (want %d)\nold: %s\nnew: %s", o.rc, c.oldRC, n.rc, c.wantRC, o.stderr, n.stderr)
			}
			knSameTree(t, oldDir, newDir)
		})
	}
}

func TestGlossaryReadMatchesOldHelper(t *testing.T) {
	for _, umbrella := range []bool{false, true} {
		dir := glProject(t, umbrella, glFixtureTerms)
		if umbrella {
			knWrite(t, filepath.Join(dir, ".hv", "knowledge", "web", "KNOWLEDGE.md"), "## Glossary\n\n- **Page** — a view\n  - **Aliases:** _none_\n  <!-- 2026-04-01 -->\n\n- **Round** — web round\n  - **Aliases:** _none_\n  <!-- 2026-04-02 -->\n")
		}
		oldArgs := []string{"worker", "ROUND", "ghost"}
		newArgs := []string{"glossary", "read", "worker", "ROUND", "ghost"}
		if umbrella {
			oldArgs = append([]string{"--repo", "web", "Page"}, oldArgs...)
			newArgs = append(newArgs, "--repo", "web", "Page")
		}
		o := knOld(t, dir, "", "hv-glossary-read", oldArgs...)
		n := knNew(t, dir, "", newArgs...)
		if o.stdout != n.stdout || n.rc != 0 {
			t.Errorf("umbrella=%v\n--- old ---\n%s\n--- new ---\n%s\nrc=%d %s", umbrella, o.stdout, n.stdout, n.rc, n.stderr)
		}
		if !strings.Contains(n.stdout, "> from: .hv/KNOWLEDGE.md (## Glossary)") {
			t.Errorf("no provenance line: %s", n.stdout)
		}
	}
	dir := glProject(t, false, glFixtureTerms)
	j := knNew(t, dir, "", "glossary", "read", "ghost", "--json")
	if !strings.Contains(j.stdout, `"missing": ["ghost"]`) || j.rc != 0 {
		t.Errorf("missing not reported: rc=%d %s", j.rc, j.stdout)
	}
	if got := knNew(t, dir, "", "glossary", "read"); got.rc != 2 {
		t.Errorf("no terms: rc=%d", got.rc)
	}
}

func TestBlockMatchesOldHelper(t *testing.T) {
	legacy := "# Project\n\n<!-- hv:knowledge:start -->\nold list\n<!-- hv:knowledge:end -->\n\ntail\n"
	cases := []struct {
		name     string
		agents   string
		umbrella bool
		oldArgs  []string
		newArgs  []string
		stdin    string
		oldRC    int
		wantRC   int
	}{
		{"knowledge block appended", "# Agents\n", false, []string{"knowledge"}, []string{"block", "knowledge"}, "", 0, 0},
		{"knowledge block updated in place", legacy, false, []string{"knowledge"}, []string{"block", "knowledge"}, "", 0, 0},
		{"decisions block", "# Agents\n", false, []string{"decisions"}, []string{"block", "decisions"}, "", 0, 0},
		{"sub-repo knowledge block", "# Agents\n", true, []string{"knowledge", "--repo", "web"}, []string{"block", "knowledge", "--repo", "web"}, "", 0, 0},
		{"custom body", "# Agents\n", false, []string{"vision", "--body-stdin"}, []string{"block", "vision", "--body-file", "-"}, "## Vision\n\nbody\n", 0, 0},
		{"decisions with --repo", "# Agents\n", true, []string{"decisions", "--repo", "web"}, []string{"block", "decisions", "--repo", "web"}, "", 1, 2},
		{"unknown generated key", "# Agents\n", false, []string{"nope"}, []string{"block", "nope"}, "", 1, 2},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			oldDir, newDir := glProject(t, c.umbrella, glFixtureTerms), glProject(t, c.umbrella, glFixtureTerms)
			for _, d := range []string{oldDir, newDir} {
				knWrite(t, filepath.Join(d, "AGENTS.md"), c.agents)
				knWrite(t, filepath.Join(d, ".hv", "DECISIONS.md"), "# Decisions\n\n## Architecture\n\n### Rule\n")
			}
			o := knOld(t, oldDir, c.stdin, "hv-managed-block", c.oldArgs...)
			n := knNew(t, newDir, c.stdin, c.newArgs...)
			if o.rc != c.oldRC || n.rc != c.wantRC {
				t.Fatalf("rc old=%d (want %d) new=%d (want %d)\nold: %s\nnew: %s", o.rc, c.oldRC, n.rc, c.wantRC, o.stderr, n.stderr)
			}
			if c.oldRC == 0 && strings.TrimSpace(o.stdout) != strings.TrimSpace(n.stdout) {
				t.Errorf("status old=%q new=%q", o.stdout, n.stdout)
			}
			knSameTree(t, oldDir, newDir)
		})
	}
}

func TestBlockIsIdempotent(t *testing.T) {
	dir := glProject(t, false, glFixtureTerms)
	first := knNew(t, dir, "", "block", "knowledge", "--json")
	second := knNew(t, dir, "", "block", "knowledge", "--json")
	if !strings.Contains(first.stdout, `"status": "appended", "changed": true`) || !strings.Contains(second.stdout, `"status": "unchanged", "changed": false`) {
		t.Errorf("first=%s second=%s", first.stdout, second.stdout)
	}
	// A glossary write regenerates the block, and a repeat leaves the tree alone.
	knNew(t, dir, "", "glossary", "write", "Zed", "--def", "last")
	before := knTree(t, dir)
	knNew(t, dir, "", "glossary", "write", "Zed", "--def", "last")
	after := knTree(t, dir)
	for k, v := range before {
		if after[k] != v {
			t.Errorf("%s changed on an identical rewrite", k)
		}
	}
}

func TestBlockSkillsMatchesOldHelper(t *testing.T) {
	oldDir, newDir := glProject(t, false, glFixtureTerms), glProject(t, false, glFixtureTerms)
	o := knOld(t, oldDir, "", "hv-skills-index")
	n := knNew(t, newDir, "", "block", "skills")
	if o.rc != 0 || n.rc != 0 {
		t.Fatalf("rc old=%d new=%d %s %s", o.rc, n.rc, o.stderr, n.stderr)
	}
	// The body names hv verbs, a deliberate break from the old helper's text
	// (contract, A9 G4): everything around the body must still match.
	agents := filepath.Join(oldDir, "AGENTS.md")
	b, err := os.ReadFile(agents)
	if err != nil {
		t.Fatal(err)
	}
	block := regexp.MustCompile(`(?s)<!-- hv-skills-start -->\n.*?\n<!-- hv-skills-end -->`)
	if !block.Match(b) {
		t.Fatalf("old helper wrote no skills block:\n%s", b)
	}
	knWrite(t, agents, string(block.ReplaceAllLiteral(b, []byte("<!-- hv-skills-start -->\n"+knowledge.SkillsBlockBody()+"\n<!-- hv-skills-end -->"))))
	knSameTree(t, oldDir, newDir)
	if got := knNew(t, newDir, "x", "block", "skills", "--body-file", "-"); got.rc != 2 {
		t.Errorf("skills with a body: rc=%d", got.rc)
	}
}

func TestInstructionsInitMatchesOldHelper(t *testing.T) {
	blocks := "<!-- hv-knowledge-start -->\nK\n<!-- hv-knowledge-end -->\n\n<!-- hv:decisions:start -->\nD\n<!-- hv:decisions:end -->\n"
	cases := []struct {
		name          string
		claude, agent string // "" means the file does not exist
	}{
		{"nothing exists", "", ""},
		{"only CLAUDE.md with prose", "# Mine\n\nhello\n", ""},
		{"CLAUDE.md with blocks and prose", "# Mine\n\n" + blocks + "\nafter\n", ""},
		{"CLAUDE.md with only blocks", blocks, ""},
		{"AGENTS.md exists, CLAUDE.md does not", "", "# Agents\n"},
		{"AGENTS.md exists, CLAUDE.md lacks the import", "# C\n", "# Agents\n"},
		{"already set up", "# C\n\n@AGENTS.md\n", "# Agents\n"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			oldDir, newDir := knProject(t, false), knProject(t, false)
			for _, d := range []string{oldDir, newDir} {
				if c.claude != "" {
					knWrite(t, filepath.Join(d, "CLAUDE.md"), c.claude)
				}
				if c.agent != "" {
					knWrite(t, filepath.Join(d, "AGENTS.md"), c.agent)
				}
			}
			o := knOld(t, oldDir, "", "hv-instructions-init")
			n := knNew(t, newDir, "", "instructions", "init")
			if o.rc != 0 || n.rc != 0 {
				t.Fatalf("rc old=%d new=%d %s %s", o.rc, n.rc, o.stderr, n.stderr)
			}
			if o.stdout != n.stdout {
				t.Errorf("actions differ\nold: %q\nnew: %q", o.stdout, n.stdout)
			}
			knSameTree(t, oldDir, newDir)
			// A second run has nothing left to do.
			again := knNew(t, newDir, "", "instructions", "init", "--json")
			if !strings.Contains(again.stdout, `"actions": [], "changed": false`) {
				t.Errorf("second run not a no-op: %s", again.stdout)
			}
		})
	}
}

func TestInstructionsInitSkipsSymlinks(t *testing.T) {
	dir := knProject(t, false)
	knWrite(t, filepath.Join(dir, "AGENTS.md"), "# A\n")
	if err := os.Symlink("AGENTS.md", filepath.Join(dir, "CLAUDE.md")); err != nil {
		t.Skip(err)
	}
	n := knNew(t, dir, "", "instructions", "init", "--json")
	if !strings.Contains(n.stdout, `"action": "skippedSymlink"`) {
		t.Errorf("got %s", n.stdout)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "AGENTS.md")); string(b) != "# A\n" {
		t.Errorf("AGENTS.md was rewritten: %q", b)
	}
}

// CRLF files are read as LF and rewritten as pure LF, like the old helpers.
func TestCRLFMatchesOldHelpersForGlossaryBlocksAndInstructions(t *testing.T) {
	crlf := func(s string) string { return strings.ReplaceAll(s, "\n", "\r\n") }
	t.Run("glossary write and block", func(t *testing.T) {
		oldDir, newDir := glProject(t, false, crlf(glFixtureTerms)), glProject(t, false, crlf(glFixtureTerms))
		for _, d := range []string{oldDir, newDir} {
			knWrite(t, filepath.Join(d, "AGENTS.md"), crlf("# Agents\n\ntext\n"))
		}
		o := knOld(t, oldDir, "", "hv-glossary-write", "Batch", "--def", "a group")
		n := knNew(t, newDir, "", "glossary", "write", "Batch", "--def", "a group")
		if o.rc != 0 || n.rc != 0 {
			t.Fatalf("rc old=%d new=%d %s %s", o.rc, n.rc, o.stderr, n.stderr)
		}
		knSameTree(t, oldDir, newDir)
		for k, v := range knTree(t, newDir) {
			if strings.Contains(v, "\r") && !strings.HasSuffix(k, ".lock") {
				t.Errorf("%s kept CR", k)
			}
		}
	})
	t.Run("glossary read", func(t *testing.T) {
		dir := glProject(t, false, crlf(glFixtureTerms))
		o := knOld(t, dir, "", "hv-glossary-read", "worker")
		n := knNew(t, dir, "", "glossary", "read", "worker")
		if o.stdout != n.stdout {
			t.Errorf("old %q new %q", o.stdout, n.stdout)
		}
	})
	t.Run("instructions init", func(t *testing.T) {
		oldDir, newDir := knProject(t, false), knProject(t, false)
		for _, d := range []string{oldDir, newDir} {
			knWrite(t, filepath.Join(d, "CLAUDE.md"), crlf("# Mine\n\n<!-- hv-knowledge-start -->\nK\n<!-- hv-knowledge-end -->\n\nafter\n"))
		}
		knOld(t, oldDir, "", "hv-instructions-init")
		knNew(t, newDir, "", "instructions", "init")
		knSameTree(t, oldDir, newDir)
	})
}
