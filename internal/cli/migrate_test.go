package cli

import (
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

// migNormalise makes two trees comparable: backup timestamps differ.
func migNormalise(tree map[string]string) map[string]string {
	out := map[string]string{}
	for k, v := range tree {
		out[migTS.ReplaceAllString(k, "migrate-backup/TS")] = v
	}
	return out
}

func migSameTree(t *testing.T, a, b string) {
	t.Helper()
	ta, tb := migNormalise(knTree(t, a)), migNormalise(knTree(t, b))
	for k, va := range ta {
		if vb, ok := tb[k]; !ok {
			t.Errorf(".hv/%s only in old", k)
		} else if va != vb {
			t.Errorf(".hv/%s differs\n--- old ---\n%s\n--- new ---\n%s", k, va, vb)
		}
	}
	for k := range tb {
		if _, ok := ta[k]; !ok {
			t.Errorf(".hv/%s only in new", k)
		}
	}
}

func migPlugin(t *testing.T) {
	root := t.TempDir()
	knWrite(t, filepath.Join(root, ".claude-plugin", "plugin.json"), `{"name": "hv-skills", "version": "4.9.9"}`)
	t.Setenv("HV_INSTALL_ROOT", root)
	old := installedVersionFn
	installedVersionFn = func() string { return "4.9.9" }
	t.Cleanup(func() { installedVersionFn = old })
}

func TestMigrateV4ApplyMatchesOldHelper(t *testing.T) {
	for _, umbrella := range []bool{false, true} {
		migPlugin(t)
		oldDir, newDir := migProject(t, umbrella), migProject(t, umbrella)
		o := knOld(t, oldDir, "", "hv-migrate", "v4", "--apply")
		n := knNew(t, newDir, "", "migrate", "v4", "--apply")
		if o.rc != 0 || n.rc != 0 {
			t.Fatalf("umbrella=%v rc old=%d new=%d\nold: %s %s\nnew: %s %s", umbrella, o.rc, n.rc, o.stdout, o.stderr, n.stdout, n.stderr)
		}
		migSameTree(t, oldDir, newDir)
		tree := knTree(t, newDir)
		if got := tree["BACKLOG.md"]; !strings.Contains(got, "/hv-capture to add") || !strings.Contains(got, "`/hv-c`") || !strings.Contains(got, "/hv-undo inside a fence") || !strings.Contains(got, "/hv-issues") {
			t.Errorf("rewrite rules misapplied:\n%s", got)
		}
		if !strings.Contains(tree["config.json"], `"version": "4.9.9"`) || strings.Contains(tree["config.json"], `"version": "3.2.0"`) {
			t.Errorf("version not stamped:\n%s", tree["config.json"])
		}
		// Summary lines agree on the counts.
		for _, want := range []string{"files scanned:", "files rewritten:", "references rewritten:", "manual review:", "removed binaries:"} {
			if line(o.stdout, want) != line(n.stdout, want) {
				t.Errorf("%q old=%q new=%q", want, line(o.stdout, want), line(n.stdout, want))
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
	o := knOld(t, dir, "", "hv-migrate", "v4", "--verbose")
	n := knNew(t, dir, "", "migrate", "v4", "--verbose")
	if o.rc != 0 || n.rc != 0 {
		t.Fatalf("rc old=%d new=%d %s %s", o.rc, n.rc, o.stderr, n.stderr)
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
		oldRC  int
		wantRC int
	}{
		{"dirty outside .hv", func(t *testing.T, d string) { knWrite(t, filepath.Join(d, "stray.txt"), "x") }, 1, 4},
		{"pre-3.0 project", func(t *testing.T, d string) {
			knWrite(t, filepath.Join(d, ".hv", "config.json"), `{"version": "2.1.0"}`)
		}, 1, 4},
		{"no version field", func(t *testing.T, d string) { knWrite(t, filepath.Join(d, ".hv", "config.json"), `{}`) }, 1, 3},
		{"no config", func(t *testing.T, d string) { os.Remove(filepath.Join(d, ".hv", "config.json")) }, 1, 3},
		{"not a git repo", func(t *testing.T, d string) { os.RemoveAll(filepath.Join(d, ".git")) }, 1, 5},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			oldDir, newDir := migProject(t, false), migProject(t, false)
			c.mutate(t, oldDir)
			c.mutate(t, newDir)
			o := knOld(t, oldDir, "", "hv-migrate", "v4", "--apply")
			n := knNew(t, newDir, "", "migrate", "v4", "--apply")
			if o.rc != c.oldRC || n.rc != c.wantRC {
				t.Fatalf("rc old=%d (want %d) new=%d (want %d)\n%s\n%s", o.rc, c.oldRC, n.rc, c.wantRC, o.stderr, n.stderr)
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
	if n.rc != 4 || !strings.Contains(n.stdout, `"blockedBy": "glossary import"`) || !strings.Contains(n.stdout, `"changed": true`) {
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
