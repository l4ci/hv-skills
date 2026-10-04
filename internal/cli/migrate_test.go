package cli

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

const migBacklog = "# Backlog\n\n## Bugs\n\n- **[B01] Fix** — use /hv-c to add, then /hv-rm B01. See `/hv-c` and hv-map-query.\n\n```\n/hv-undo inside a fence\n```\n\nAsk /hv-issues or /hv-map later; /hv-docs and /hv-assume work.\n"

const migContext = "# Context\n\n## Worker\n\nan agent in a round\nspanning two lines\n\n**Aliases:** agent, slot\n**Not:** orchestrator\n<!-- 2026-01-01 -->\n\n## Round\n\none cycle\n"

const migKnowledge = "# Knowledge\n\n## Glossary\n\n_(no terms yet)_\n"

func migGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"}, args...)...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

// migProject builds a committed v3 project.
func migProject(t *testing.T, umbrella bool) string {
	t.Helper()
	dir := knProject(t, umbrella)
	knWrite(t, filepath.Join(dir, ".hv", "config.json"), "{\n  \"version\": \"3.2.0\",\n  \"keep\": true\n}\n")
	knWrite(t, filepath.Join(dir, ".hv", "BACKLOG.md"), migBacklog)
	knWrite(t, filepath.Join(dir, ".hv", "KNOWLEDGE.md"), migKnowledge)
	knWrite(t, filepath.Join(dir, ".hv", "plans", "P1.md"), "plan: run /hv-undo then /hv-c\n")
	knWrite(t, filepath.Join(dir, ".hv", "CONTEXT.md"), migContext)
	knWrite(t, filepath.Join(dir, ".hv", "bin", "hv-context-add"), "#!/bin/sh\n")
	knWrite(t, filepath.Join(dir, "AGENTS.md"), "# Agents\n\nrun /hv-context\n\n<!-- hv-context-start -->\nold\n<!-- hv-context-end -->\n\nend\n")
	if umbrella {
		knWrite(t, filepath.Join(dir, ".hv", "knowledge", "web", "KNOWLEDGE.md"), migKnowledge)
		knWrite(t, filepath.Join(dir, ".hv", "contexts", "web", "CONTEXT.md"), "## Page\n\na view\n")
		knWrite(t, filepath.Join(dir, ".hv", "contexts", "api", "CONTEXT.md"), "# nothing but a placeholder\n")
		knWrite(t, filepath.Join(dir, ".hv", "knowledge", "api", "KNOWLEDGE.md"), migKnowledge)
	}
	if err := os.WriteFile(filepath.Join(dir, ".gitignore"), []byte(".hv/\n"), 0o666); err != nil {
		t.Fatal(err)
	}
	migGit(t, dir, "init", "-q")
	migGit(t, dir, "add", "-A", "-f")
	migGit(t, dir, "commit", "-q", "-m", "init")
	return dir
}

var migTS = regexp.MustCompile(`migrate-backup/\d{8}T\d{6}`)

func migPlugin(t *testing.T) {
	old := installedVersionFn
	installedVersionFn = func() string { return "4.9.9" }
	t.Cleanup(func() { installedVersionFn = old })
}

func TestMigrateV4ApplyMatchGolden(t *testing.T) {
	for _, umbrella := range []bool{false, true} {
		migPlugin(t)
		newDir := migProject(t, umbrella)
		want, got := knFrozen(t, newDir, "", "migrate", "v4", "--apply")
		if want.RC != 0 || got.RC != 0 {
			t.Fatalf("umbrella=%v rc frozen=%d new=%d\nfrozen: %s %s\nnew: %s %s", umbrella, want.RC, got.RC, want.Stdout, want.Stderr, got.Stdout, got.Stderr)
		}
		knSameDelta(t, want, got)
		tree := knTree(t, newDir)
		if got := tree["BACKLOG.md"]; !strings.Contains(got, "/hv-capture to add") || !strings.Contains(got, "`/hv-c`") || !strings.Contains(got, "/hv-undo inside a fence") || !strings.Contains(got, "/hv-issues") {
			t.Errorf("rewrite rules misapplied:\n%s", got)
		}
		if !strings.Contains(tree["config.json"], `"version": "4.9.9"`) || strings.Contains(tree["config.json"], `"version": "3.2.0"`) {
			t.Errorf("version not stamped:\n%s", tree["config.json"])
		}
		// Summary lines agree on the counts.
		for _, w := range []string{"files scanned:", "files rewritten:", "references rewritten:", "manual review:", "removed binaries:"} {
			if line(want.Stdout, w) != line(got.Stdout, w) {
				t.Errorf("%q frozen=%q new=%q", w, line(want.Stdout, w), line(got.Stdout, w))
			}
		}
		// A second run is a no-op once the first one's changes are committed.
		migGit(t, newDir, "add", "-A", "-f")
		migGit(t, newDir, "commit", "-q", "-m", "migrated")
		again := knNew(t, newDir, "", "migrate", "v4", "--apply", "--json")
		if !strings.Contains(again.stdout, `"noop": true`) || !strings.Contains(again.stdout, `"changed": false`) {
			t.Errorf("second apply: %s", again.stdout)
		}
	}
}

func line(s, prefix string) string {
	for _, l := range strings.Split(s, "\n") {
		if strings.Contains(l, prefix) {
			return strings.TrimSpace(l)
		}
	}
	return ""
}

func TestMigrateV4PreviewWritesNothingAndMatchesVerboseDiffs(t *testing.T) {
	migPlugin(t)
	dir := migProject(t, true)
	before := knTree(t, dir)
	want, got := knFrozen(t, dir, "", "migrate", "v4", "--verbose")
	o, n := knOut{want.Stdout, want.Stderr, want.RC}, knOut{got.Stdout, got.Stderr, got.RC}
	if o.rc != 0 || n.rc != 0 {
		t.Fatalf("rc frozen=%d new=%d %s %s", o.rc, n.rc, o.stderr, n.stderr)
	}
	after := knTree(t, dir)
	if len(before) != len(after) {
		t.Errorf("preview wrote files: %d -> %d", len(before), len(after))
	}
	for k, v := range before {
		if after[k] != v {
			t.Errorf("preview changed %s", k)
		}
	}
	section := func(s string) string {
		a := strings.Index(s, "— per-file diffs —")
		b := strings.Index(s, "— rewrites —")
		if a < 0 || b < 0 {
			return ""
		}
		return s[a:b]
	}
	if section(o.stdout) == "" || section(o.stdout) != section(n.stdout) {
		t.Errorf("diffs differ\n--- old ---\n%s\n--- new ---\n%s", section(o.stdout), section(n.stdout))
	}
	for _, want := range []string{"files rewritten:", "manual review:", "CONTEXT.md (web):", "— manual review —", "Run with --apply"} {
		if !strings.Contains(n.stdout, want) {
			t.Errorf("preview output lacks %q:\n%s", want, n.stdout)
		}
	}
	j := knNew(t, dir, "", "migrate", "v4", "--json")
	if !strings.Contains(j.stdout, `"applied": false`) || !strings.Contains(j.stdout, `preview only; pass --apply`) || !strings.Contains(j.stdout, `"strippedBlocks": ["context"]`) {
		t.Errorf("preview json: %s", j.stdout)
	}
}

func TestMigrateV4Refusals(t *testing.T) {
	migPlugin(t)
	cases := []struct {
		name   string
		mutate func(t *testing.T, dir string)
		wantRC int
	}{
		{"dirty outside .hv", func(t *testing.T, d string) { knWrite(t, filepath.Join(d, "stray.txt"), "x") }, 4},
		{"pre-3.0 project", func(t *testing.T, d string) {
			knWrite(t, filepath.Join(d, ".hv", "config.json"), `{"version": "2.1.0"}`)
		}, 4},
		{"no version field", func(t *testing.T, d string) { knWrite(t, filepath.Join(d, ".hv", "config.json"), `{}`) }, 3},
		{"no config", func(t *testing.T, d string) { os.Remove(filepath.Join(d, ".hv", "config.json")) }, 3},
		{"not a git repo", func(t *testing.T, d string) { os.RemoveAll(filepath.Join(d, ".git")) }, 5},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			newDir := migProject(t, false)
			c.mutate(t, newDir)
			n := knNew(t, newDir, "", "migrate", "v4", "--apply")
			if n.rc != c.wantRC {
				t.Fatalf("rc new=%d (want %d)\n%s", n.rc, c.wantRC, n.stderr)
			}
			if _, err := os.Stat(filepath.Join(newDir, ".hv", "migrate-backup")); err == nil {
				t.Error("a refused run left a backup")
			}
			if c.wantRC == 4 {
				j := knNew(t, newDir, "", "migrate", "v4", "--apply", "--json")
				if !strings.Contains(j.stdout, `"blockedBy"`) || !strings.Contains(j.stdout, `"changed": false`) {
					t.Errorf("refusal data: %s", j.stdout)
				}
			}
		})
	}
	// cwd inside a backup directory.
	dir := migProject(t, false)
	inside := filepath.Join(dir, ".hv", "migrate-backup", "x")
	os.MkdirAll(inside, 0o777)
	got := knNew(t, inside, "", "migrate", "v4", "-C", inside)
	if got.rc != 4 || !strings.Contains(got.stderr, "migrate-backup") {
		t.Errorf("inside backup dir: rc=%d %s", got.rc, got.stderr)
	}
}

func TestMigrateV4KeepsBackupWhenImportFails(t *testing.T) {
	migPlugin(t)
	dir := migProject(t, false)
	// A Glossary heading is required for the import.
	knWrite(t, filepath.Join(dir, ".hv", "KNOWLEDGE.md"), "# Knowledge\n")
	n := knNew(t, dir, "", "migrate", "v4", "--apply", "--json")
	if n.rc != 4 || !strings.Contains(n.stdout, `"blockedBy": "glossary-import"`) || !strings.Contains(n.stdout, `"changed": true`) {
		t.Fatalf("rc=%d %s", n.rc, n.stdout)
	}
	if _, err := os.Stat(filepath.Join(dir, ".hv", "CONTEXT.md")); err != nil {
		t.Error("CONTEXT.md was deleted although the import failed")
	}
	matches, _ := filepath.Glob(filepath.Join(dir, ".hv", "migrate-backup", "*", "CONTEXT.md"))
	if len(matches) != 1 {
		t.Errorf("backup of CONTEXT.md missing: %v", matches)
	}
}

func TestMigrateV4CRLFMatchGolden(t *testing.T) {
	migPlugin(t)
	crlf := func(s string) string { return strings.ReplaceAll(s, "\n", "\r\n") }
	newDir := migProject(t, false)
	knWrite(t, filepath.Join(newDir, ".hv", "BACKLOG.md"), crlf(migBacklog))
	knWrite(t, filepath.Join(newDir, ".hv", "CONTEXT.md"), crlf(migContext))
	knWrite(t, filepath.Join(newDir, "AGENTS.md"), crlf("# Agents\n\nrun /hv-context\n\n<!-- hv-context-start -->\nold\n<!-- hv-context-end -->\n\nend\n"))
	migGit(t, newDir, "add", "-A", "-f")
	migGit(t, newDir, "commit", "-q", "-m", "crlf")
	want, got := knFrozen(t, newDir, "", "migrate", "v4", "--apply")
	if want.RC != 0 || got.RC != 0 {
		t.Fatalf("rc frozen=%d new=%d %s %s", want.RC, got.RC, want.Stderr, got.Stderr)
	}
	knSameDelta(t, want, got)
	if strings.Contains(knTree(t, newDir)["BACKLOG.md"], "\r") {
		t.Error("CR survived the rewrite")
	}
}

func TestMigrateV4NoopPreviewWarns(t *testing.T) {
	migPlugin(t)
	dir := migProject(t, false)
	knNew(t, dir, "", "migrate", "v4", "--apply")
	migGit(t, dir, "add", "-A", "-f")
	migGit(t, dir, "commit", "-q", "-m", "done")
	n := knNew(t, dir, "", "migrate", "v4", "--json")
	if !strings.Contains(n.stdout, `"noop": true`) || !strings.Contains(n.stdout, `preview only; pass --apply`) {
		t.Errorf("%s", n.stdout)
	}
}

func TestMigrateV4DevBuildWarnsAndSkipsStamp(t *testing.T) {
	migPlugin(t)
	installedVersionFn = func() string { return "" }
	dir := migProject(t, false)
	before := knTree(t, dir)["config.json"]
	n := knNew(t, dir, "", "migrate", "v4", "--apply", "--json")
	if n.rc != 0 || !strings.Contains(n.stdout, "version unknown (dev build); config.json not stamped") {
		t.Fatalf("rc=%d %s", n.rc, n.stdout)
	}
	if knTree(t, dir)["config.json"] != before {
		t.Error("config.json was stamped")
	}
}

// The strip step reads the instructions file with normalized newlines too: a
// CRLF AGENTS.md that only needs the context block removed ends up pure LF.
func TestMigrateV4StripNormalizesCRLF(t *testing.T) {
	migPlugin(t)
	newDir := migProject(t, false)
	knWrite(t, filepath.Join(newDir, "AGENTS.md"), "# Agents\r\n\r\n<!-- hv-context-start -->\r\nold\r\n<!-- hv-context-end -->\r\n\r\nend\r\n")
	migGit(t, newDir, "add", "-A", "-f")
	migGit(t, newDir, "commit", "-q", "-m", "crlf agents")
	want, got := knFrozen(t, newDir, "", "migrate", "v4", "--apply")
	if want.RC != 0 || got.RC != 0 {
		t.Fatalf("rc frozen=%d new=%d %s %s", want.RC, got.RC, want.Stderr, got.Stderr)
	}
	knSameDelta(t, want, got)
	if strings.Contains(knTree(t, newDir)["../AGENTS.md"], "\r") {
		t.Error("CR kept in AGENTS.md")
	}
}

// The deprecated-block strip runs on every call: a project whose only v3
// leftover is a context block reports it with noop false (contract, A5 gaps).
func TestMigrateV4StripsWhenItIsTheOnlyLeftover(t *testing.T) {
	migPlugin(t)
	dir := migProject(t, false)
	knNew(t, dir, "", "migrate", "v4", "--apply")
	knWrite(t, filepath.Join(dir, "AGENTS.md"), "# Agents\n\n<!-- hv-context-start -->\nold\n<!-- hv-context-end -->\n\nend\n")
	migGit(t, dir, "add", "-A", "-f")
	migGit(t, dir, "commit", "-q", "-m", "stray block")

	p := knNew(t, dir, "", "migrate", "v4", "--json")
	if !strings.Contains(p.stdout, `"noop": false`) || !strings.Contains(p.stdout, `"strippedBlocks": ["context"]`) {
		t.Fatalf("preview: %s", p.stdout)
	}
	a := knNew(t, dir, "", "migrate", "v4", "--apply", "--json")
	if a.rc != 0 || !strings.Contains(a.stdout, `"changed": true`) || !strings.Contains(a.stdout, `"backup": ".hv/migrate-backup/`) {
		t.Fatalf("apply: %d %s", a.rc, a.stdout)
	}
	got, _ := os.ReadFile(filepath.Join(dir, "AGENTS.md"))
	if strings.Contains(string(got), "hv-context") {
		t.Errorf("block not stripped: %s", got)
	}
	migGit(t, dir, "add", "-A", "-f")
	migGit(t, dir, "commit", "-q", "-m", "stripped")
	b := knNew(t, dir, "", "migrate", "v4", "--apply", "--json")
	if !strings.Contains(b.stdout, `"noop": true`) || !strings.Contains(b.stdout, `"changed": false`) {
		t.Errorf("second apply: %s", b.stdout)
	}
}

// --apply stamps hv.version with the installed plugin version, drops the
// legacy top-level version, and reports the stamp as data.versionStamp.
func TestMigrateV4StampsInstalledVersion(t *testing.T) {
	migPlugin(t)
	dir := migProject(t, false)
	knWrite(t, filepath.Join(dir, ".hv", "config.json"), `{"version":"3.4.0","hvSkills":{"version":"3.4.0"}}`)
	migGit(t, dir, "add", "-A", "-f")
	migGit(t, dir, "commit", "-q", "-m", "cfg")
	n := knNew(t, dir, "", "migrate", "v4", "--apply", "--json")
	if n.rc != 0 {
		t.Fatalf("rc=%d %s %s", n.rc, n.stdout, n.stderr)
	}
	var env struct {
		Data struct {
			VersionStamp string `json:"versionStamp"`
		} `json:"data"`
	}
	if err := json.Unmarshal([]byte(n.stdout), &env); err != nil {
		t.Fatalf("json: %v\n%s", err, n.stdout)
	}
	raw, err := os.ReadFile(filepath.Join(dir, ".hv", "config.json"))
	if err != nil {
		t.Fatal(err)
	}
	var cfg struct {
		Hv struct {
			Version string `json:"version"`
		} `json:"hv"`
		HvSkills *json.RawMessage `json:"hvSkills"`
		Version  *string          `json:"version"`
	}
	if err := json.Unmarshal(raw, &cfg); err != nil {
		t.Fatalf("config: %v\n%s", err, raw)
	}
	if cfg.Hv.Version != "4.9.9" {
		t.Errorf("hv.version = %q, want 4.9.9", cfg.Hv.Version)
	}
	if env.Data.VersionStamp != cfg.Hv.Version {
		t.Errorf("data.versionStamp = %q, stamped %q", env.Data.VersionStamp, cfg.Hv.Version)
	}
	if cfg.HvSkills != nil {
		t.Errorf("legacy hvSkills kept: %s", raw)
	}
	if cfg.Version != nil {
		t.Errorf("legacy top-level version kept: %s", raw)
	}
}

// A deprecated context block is stripped while a live knowledge block and the
// surrounding prose survive, and the report names the stripped block.
func TestMigrateV4StripKeepsLiveBlockAndProse(t *testing.T) {
	migPlugin(t)
	dir := migProject(t, false)
	knNew(t, dir, "", "migrate", "v4", "--apply")
	// The strip works on AGENTS.md when present, else CLAUDE.md.
	if err := os.Remove(filepath.Join(dir, "AGENTS.md")); err != nil {
		t.Fatal(err)
	}
	knWrite(t, filepath.Join(dir, "CLAUDE.md"), "# Project\n\n<!-- hv-knowledge-start -->\n## Project Knowledge\nLive block - must survive.\n<!-- hv-knowledge-end -->\n\n<!-- hv-context-start -->\n## Project Context\nOrphan block - must be stripped.\n<!-- hv-context-end -->\n\nRegular prose stays.\n")
	migGit(t, dir, "add", "-A", "-f")
	migGit(t, dir, "commit", "-q", "-m", "claude md")
	a := knNew(t, dir, "", "migrate", "v4", "--apply", "--json")
	if a.rc != 0 || !strings.Contains(a.stdout, `"strippedBlocks": ["context"]`) {
		t.Fatalf("apply: %d %s", a.rc, a.stdout)
	}
	b, err := os.ReadFile(filepath.Join(dir, "CLAUDE.md"))
	if err != nil {
		t.Fatal(err)
	}
	got := string(b)
	if strings.Contains(got, "hv-context-start") || strings.Contains(got, "Orphan block") {
		t.Errorf("orphan block not stripped:\n%s", got)
	}
	for _, want := range []string{"hv-knowledge-start", "Live block - must survive.", "Regular prose stays."} {
		if !strings.Contains(got, want) {
			t.Errorf("%q lost:\n%s", want, got)
		}
	}
}
