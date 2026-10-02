package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const decFixture = `# Decisions

## Architecture

### Keep modules small

*Why.* Reviews stay short.

**Forbids.**
- god packages

**Permits.**
- many small ones

<!-- [Auto:Loop] plan-1 2026-09-30 — review and articulate Forbids/Permits -->

## Build

### Gate first

*Why.* Cheap.

**Forbids.**
- _(Unresolved — user must articulate)_

**Permits.**
- tests

<!-- [Auto:Loop] plan-2 2026-10-02 — review and articulate Forbids/Permits -->

### Never skip

*Why.* Safety.

**Forbids.**
- _(Unresolved — user must articulate)_

**Permits.**
- _(Unresolved — user must articulate)_

<!-- [Auto:Loop] plan-3 2026-10-03 — review and articulate Forbids/Permits -->
`

func decProject(t *testing.T, decisions, status string) string {
	dir := knProject(t, false)
	if decisions != "" {
		knWrite(t, filepath.Join(dir, ".hv", "DECISIONS.md"), decisions)
	}
	if status != "" {
		knWrite(t, filepath.Join(dir, ".hv", "status.json"), status)
	}
	return dir
}

func TestDecisionsQueryMatchesOldHelper(t *testing.T) {
	dir := decProject(t, decFixture, "")
	for _, topics := range [][]string{{"build"}, {"Build", "architecture"}, {"nothing"}} {
		o := knOld(t, dir, "", "hv-decisions-query", topics...)
		n := knNew(t, dir, "", append([]string{"decisions", "query"}, topics...)...)
		if o.stdout != n.stdout || n.rc != 0 {
			t.Errorf("%v\n--- old ---\n%s\n--- new ---\n%s", topics, o.stdout, n.stdout)
		}
	}
	j := knNew(t, dir, "", "decisions", "query", "Build", "ghost", "--json")
	if !strings.Contains(j.stdout, `"missing": ["ghost"]`) {
		t.Errorf("missing not reported: %s", j.stdout)
	}
	if got := knNew(t, dir, "", "decisions", "query"); got.rc != 2 {
		t.Errorf("no topic: rc=%d", got.rc)
	}
	if got := knNew(t, dir, "", "decisions", "query", "--repo", "web", "Build"); got.rc != 2 {
		t.Errorf("--repo accepted: rc=%d", got.rc)
	}
}

func TestDecisionsAutoLogMatchesOldHelper(t *testing.T) {
	cases := []struct {
		name         string
		decisions    string
		oldArgs      []string
		newArgs      []string
		wantMarker   string
		wantUnchange bool
	}{
		{"new entry in existing topic", decFixture,
			[]string{"Build", "Fresh rule", "because", "plan-9", "2026-10-05"},
			[]string{"decisions", "auto-log", "--topic", "Build", "--title", "Fresh rule", "--why", "because", "--plan-key", "plan-9", "--date", "2026-10-05"}, "### Fresh rule", false},
		{"new topic", decFixture,
			[]string{"Release", "Tag first", "why not", "", "2026-10-05"},
			[]string{"decisions", "auto-log", "--topic", "Release", "--title", "Tag first", "--why", "why not", "--date", "2026-10-05"}, "## Release", false},
		{"repeat is a no-op", decFixture,
			[]string{"Build", "Gate first", "again", "", "2026-10-05"},
			[]string{"decisions", "auto-log", "--topic", "Build", "--title", "Gate first", "--why", "again", "--date", "2026-10-05"}, "", true},
		{"file does not exist yet", "",
			[]string{"Build", "First", "w", "", "2026-10-05"},
			[]string{"decisions", "auto-log", "--topic", "Build", "--title", "First", "--why", "w", "--date", "2026-10-05"}, "### First", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			oldDir, newDir := decProject(t, c.decisions, ""), decProject(t, c.decisions, "")
			o := knOld(t, oldDir, "", "hv-auto-decision-log", c.oldArgs...)
			n := knNew(t, newDir, "", c.newArgs...)
			if o.rc != 0 || n.rc != 0 {
				t.Fatalf("rc old=%d new=%d %s %s", o.rc, n.rc, o.stderr, n.stderr)
			}
			knSameTree(t, oldDir, newDir)
			j := knNew(t, newDir, "", append(c.newArgs, "--json")...)
			if !strings.Contains(j.stdout, `"changed": false`) {
				t.Errorf("second call not idempotent: %s", j.stdout)
			}
		})
	}
	dir := decProject(t, decFixture, "")
	if got := knNew(t, dir, "", "decisions", "auto-log", "--topic", "Build", "--title", "t"); got.rc != 2 {
		t.Errorf("missing --why: rc=%d", got.rc)
	}
}

func TestDecisionsAutoSince(t *testing.T) {
	status := `{"loopStartedAt": "2026-10-01T09:00:00Z"}`
	dir := decProject(t, decFixture, status)
	n := knNew(t, dir, "", "decisions", "auto-since", "--json")
	want := `"since": "2026-10-01T09:00:00Z", "decisions": [` +
		`{"topic": "Build", "title": "Gate first", "date": "2026-10-02", "status": "partial"}, ` +
		`{"topic": "Build", "title": "Never skip", "date": "2026-10-03", "status": "unresolved"}]`
	if !strings.Contains(n.stdout, want) {
		t.Errorf("got %s\nwant to contain %s", n.stdout, want)
	}
	// Text output and the old helper agree on the entries it can see.
	o := knOld(t, dir, "", "hv-auto-decisions-since")
	if o.stdout != knNew(t, dir, "", "decisions", "auto-since").stdout {
		t.Errorf("text differs\nold: %q\nnew: %q", o.stdout, knNew(t, dir, "", "decisions", "auto-since").stdout)
	}
	// No loop, no file: empty.
	for _, d := range []string{decProject(t, decFixture, ""), decProject(t, "", status)} {
		j := knNew(t, d, "", "decisions", "auto-since", "--json")
		if !strings.Contains(j.stdout, `"decisions": []`) || j.rc != 0 {
			t.Errorf("expected none: rc=%d %s", j.rc, j.stdout)
		}
	}
}

// An auto-logged entry with no plan key has a footer the old helper's
// auto-since pattern (and so this port) does not match.
func TestDecisionsAutoSinceIgnoresFootersWithoutPlanKey(t *testing.T) {
	dir := decProject(t, "", `{"loopStartedAt": "2026-10-01T00:00:00Z"}`)
	knNew(t, dir, "", "decisions", "auto-log", "--topic", "T", "--title", "No key", "--why", "w", "--date", "2026-10-02")
	knNew(t, dir, "", "decisions", "auto-log", "--topic", "T", "--title", "With key", "--why", "w", "--plan-key", "p", "--date", "2026-10-02")
	n := knNew(t, dir, "", "decisions", "auto-since")
	if !strings.Contains(n.stdout, "With key") || strings.Contains(n.stdout, "No key") {
		t.Errorf("got %q", n.stdout)
	}
	o := knOld(t, dir, "", "hv-auto-decisions-since")
	if o.stdout != n.stdout {
		t.Errorf("old=%q new=%q", o.stdout, n.stdout)
	}
}

const mapFileA = "---\nsubsystem: cli\nsummary: The command line\ntouched: 2026-09-01\n---\n\n# CLI\n\ntext\n\n## Entry points\n\n- cmd/main.go:2\n- cmd/main.go:99\n- gone/file.go:1\n"
const mapFileB = "---\nsubsystem: alpha\n---\n\n# Alpha\n"

func mapProject(t *testing.T) string {
	dir := knProject(t, false)
	knWrite(t, filepath.Join(dir, ".hv", "map", "cli.md"), mapFileA)
	knWrite(t, filepath.Join(dir, ".hv", "map", "alpha.md"), mapFileB)
	knWrite(t, filepath.Join(dir, ".hv", "map", "nofm.md"), "no frontmatter\n")
	knWrite(t, filepath.Join(dir, "cmd", "main.go"), "package main\n\nfunc main() {}\n")
	knWrite(t, filepath.Join(dir, "AGENTS.md"), "# Agents\n")
	return dir
}

func TestMapQueryAndQAQueryMatchOldHelpers(t *testing.T) {
	dir := mapProject(t)
	knWrite(t, filepath.Join(dir, ".hv", "qa", "web.md"), "---\nsurface: web\nsummary: browser\n---\n\n# Web QA\n")
	for _, c := range []struct{ old, group string }{{"hv-map-query", "map"}, {"hv-qa-query", "qa"}} {
		names := []string{"cli", "ghost", "alpha", "web"}
		o := knOld(t, dir, "", c.old, names...)
		n := knNew(t, dir, "", append([]string{c.group, "query"}, names...)...)
		if o.stdout != n.stdout || n.rc != 0 {
			t.Errorf("%s\n--- old ---\n%s\n--- new ---\n%s", c.group, o.stdout, n.stdout)
		}
		if got := knNew(t, dir, "", c.group, "query"); got.rc != 2 {
			t.Errorf("%s with no name: rc=%d", c.group, got.rc)
		}
	}
	j := knNew(t, dir, "", "map", "query", "ghost", "../x", "--json")
	if !strings.Contains(j.stdout, `"missing": ["ghost", "../x"]`) {
		t.Errorf("missing: %s", j.stdout)
	}
}

// The generated index blocks name the hv verb where the old ones named the
// .hv/bin helper (verb contract); everything else must be identical.
func TestMapAndQAIndexMatchOldHelpers(t *testing.T) {
	for _, c := range []struct{ old, group, oldPath, newPath string }{
		{"hv-map-index", "map", ".hv/bin/hv-map-query <name>", "hv map query <name>"},
		{"hv-qa-index", "qa", ".hv/bin/hv-qa-query <target>", "hv qa query <target>"},
	} {
		for _, withEntries := range []bool{true, false} {
			oldDir, newDir := mapProject(t), mapProject(t)
			if !withEntries {
				for _, d := range []string{oldDir, newDir} {
					os.RemoveAll(filepath.Join(d, ".hv", "map"))
				}
			} else {
				for _, d := range []string{oldDir, newDir} {
					knWrite(t, filepath.Join(d, ".hv", "qa", "web.md"), "---\nsurface: web\nsummary: browser\n---\n")
					knWrite(t, filepath.Join(d, ".hv", "qa", "bare.md"), "---\n---\n")
				}
			}
			o := knOld(t, oldDir, "", c.old)
			n := knNew(t, newDir, "", c.group, "index")
			if o.rc != 0 || n.rc != 0 {
				t.Fatalf("%s rc old=%d new=%d %s %s", c.group, o.rc, n.rc, o.stderr, n.stderr)
			}
			ot, nt := knTree(t, oldDir), knTree(t, newDir)
			oldAgents := strings.ReplaceAll(ot["../AGENTS.md"], c.oldPath, c.newPath)
			if oldAgents != nt["../AGENTS.md"] {
				t.Errorf("%s (entries=%v) AGENTS.md differs\n--- old ---\n%s\n--- new ---\n%s", c.group, withEntries, oldAgents, nt["../AGENTS.md"])
			}
			again := knNew(t, newDir, "", c.group, "index", "--json")
			if !strings.Contains(again.stdout, `"status": "unchanged", "changed": false`) {
				t.Errorf("%s second run: %s", c.group, again.stdout)
			}
		}
	}
}

func TestMapStatsMatchesOldHelper(t *testing.T) {
	dir := mapProject(t)
	o := knOld(t, dir, "", "hv-map-stats")
	for _, want := range []string{`"name": "alpha"`, `"name": "cli"`, `"entry_points": 3`, `"broken_refs": 2`, `"touched": "2026-09-01"`} {
		if !strings.Contains(o.stdout, want) {
			t.Fatalf("old helper unexpected, missing %s:\n%s", want, o.stdout)
		}
	}
	n := knNew(t, dir, "", "map", "stats", "--json")
	for _, want := range []string{`"name": "alpha"`, `"name": "cli"`, `"entryPoints": 3`, `"brokenRefs": 2`, `"touched": "2026-09-01"`, `"count": 2`} {
		if !strings.Contains(n.stdout, want) {
			t.Errorf("missing %s: %s", want, n.stdout)
		}
	}
	if strings.Index(n.stdout, `"alpha"`) > strings.Index(n.stdout, `"cli"`) {
		t.Errorf("not sorted by name: %s", n.stdout)
	}
	// No map directory: empty, exit 0.
	empty := knProject(t, false)
	if e := knNew(t, empty, "", "map", "stats", "--json"); !strings.Contains(e.stdout, `"subsystems": [], "count": 0`) || e.rc != 0 {
		t.Errorf("empty: rc=%d %s", e.rc, e.stdout)
	}
}

func TestMapStatsCap(t *testing.T) {
	dir := mapProject(t)
	below := knNew(t, dir, "", "map", "stats", "--cap", "--json")
	if !strings.Contains(below.stdout, `"cap": 20, "overCap": false`) || strings.Contains(below.stderr, "note") {
		t.Errorf("below cap: %s / %s", below.stdout, below.stderr)
	}
	knWrite(t, filepath.Join(dir, ".hv", "config.json"), `{"map": {"softcap_subsystems": 2}}`)
	over := knNew(t, dir, "", "map", "stats", "--cap", "--json")
	if !strings.Contains(over.stdout, `"cap": 2, "overCap": true`) || !strings.Contains(over.stdout, `"warnings": ["project map has 2 subsystems (cap 2);`) {
		t.Errorf("over cap: %s", over.stdout)
	}
	// The old nudge text matches.
	o := knOld(t, dir, "", "hv-map-cap-check")
	if !strings.Contains(o.stderr, "project map has 2 subsystems (cap 2); consider merging or retiring stale .hv/map/<name>.md entries") {
		t.Errorf("old nudge: %q", o.stderr)
	}
	if text := knNew(t, dir, "", "map", "stats", "--cap"); !strings.HasPrefix(text.stdout, "note: project map has 2 subsystems") {
		t.Errorf("text mode: %q", text.stdout)
	}
}
