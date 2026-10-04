// Package initproj is `hv init`: it seeds .hv/ in a directory, migrates what
// older versions left behind, and checks that a project is initialized. It is
// the port of bin/hv-bootstrap and bin/hv-preflight; the trees the old
// bootstrap left, frozen in testdata/golden, are what the tests compare
// against (see TestInitMatchesBootstrapGolden).
//
// Init, Check and the block orchestration act on the directory they are given,
// with no walk-up: they run before a project root exists.
package initproj

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/l4ci/hv/v5/internal/fsio"
	"github.com/l4ci/hv/v5/internal/jsonx"
	"github.com/l4ci/hv/v5/internal/repos"
)

// ErrSeed is wrapped by every failure of seeding: a file that is unreadable,
// not writable or corrupt. The cli maps it to exit 70.
var ErrSeed = errors.New("seeding .hv/ failed")

func seedErr(format string, a ...any) error {
	return fmt.Errorf("%w: %s", ErrSeed, fmt.Sprintf(format, a...))
}

// Result is what Init did. Created is the diff of `find .hv .gitignore` before
// and after, sorted and relative to the root, directories included.
type Result struct {
	Created []string
	// Removed lists what the stale-mirror cleanup deleted, relative to the root.
	Removed []string
	// Migrated is whether a migration step rewrote an existing file: the
	// MILESTONES.md heading, the counters backfill, the .gitignore block or the
	// KNOWLEDGE.md preamble.
	Migrated bool
	// Warnings are things the caller should surface: a legacy TODO.md left in
	// place, custom files left in .hv/bin.
	Warnings []string
}

// Changed is whether Init touched anything.
func (r Result) Changed() bool {
	return len(r.Created) > 0 || len(r.Removed) > 0 || r.Migrated
}

var seedDirs = []string{"bugs", "features", "tasks", "milestones", "plans", "spikes", "map"}

// Init seeds .hv/ under root. It never overwrites an existing file, and a
// second run is a no-op, as hv-bootstrap was. Beyond it, Init removes the
// `.hv/bin` mirror that 4.x wrote (see removeMirror).
func Init(root string) (Result, error) {
	var res Result
	before := snapshot(root)
	hv := filepath.Join(root, ".hv")
	// A corrupt counters.json is refused before anything is written, so exit 70
	// leaves the tree as it was.
	if err := checkCounters(filepath.Join(hv, "counters.json")); err != nil {
		return res, err
	}
	step := func(wrote bool, err error) error {
		res.Migrated = res.Migrated || wrote
		return err
	}
	for _, d := range seedDirs {
		if err := os.MkdirAll(filepath.Join(hv, d), 0o777); err != nil {
			return res, seedErr("%v", err)
		}
	}

	// A legacy .hv/TODO.md becomes BACKLOG.md; with both present BACKLOG.md wins.
	todo, backlog := filepath.Join(hv, "TODO.md"), filepath.Join(hv, "BACKLOG.md")
	if isFile(todo) {
		if !isFile(backlog) {
			if err := os.Rename(todo, backlog); err != nil {
				return res, seedErr("%v", err)
			}
		} else {
			res.Warnings = append(res.Warnings, "legacy .hv/TODO.md still present; not overwriting .hv/BACKLOG.md")
		}
	}

	for _, f := range []struct{ name, text string }{
		{"BACKLOG.md", backlogSeed},
		{"KNOWLEDGE.md", knowledgeSeed},
		{"DECISIONS.md", decisionsSeed},
		{"MAP.md", mapSeed},
		{"MILESTONES.md", milestonesSeed},
	} {
		if err := seedFile(filepath.Join(hv, f.name), f.text); err != nil {
			return res, err
		}
	}
	if err := step(migrateMilestonesHeading(filepath.Join(hv, "MILESTONES.md"))); err != nil {
		return res, err
	}

	if err := seedFile(filepath.Join(hv, "counters.json"), countersSeed); err != nil {
		return res, err
	}
	if err := step(backfillCounters(filepath.Join(hv, "counters.json"))); err != nil {
		return res, err
	}
	for _, f := range []struct{ name, text string }{
		{"status.json", statusSeed},
		{"repos.json", reposSeed},
		{"config.json", configSeed},
	} {
		if err := seedFile(filepath.Join(hv, f.name), f.text); err != nil {
			return res, err
		}
	}

	if err := step(updateGitignore(filepath.Join(root, ".gitignore"), len(repos.Load(root)) > 0)); err != nil {
		return res, err
	}
	if err := step(migrateKnowledgePreamble(filepath.Join(hv, "KNOWLEDGE.md"))); err != nil {
		return res, err
	}

	res.Removed, res.Warnings = removeMirror(root, res.Warnings)

	after := snapshot(root)
	for p := range after {
		if !before[p] {
			res.Created = append(res.Created, p)
		}
	}
	sort.Strings(res.Created)
	return res, nil
}

func isFile(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.Mode().IsRegular()
}

// seedFile writes text to path unless something is already there.
func seedFile(path, text string) error {
	if _, err := os.Lstat(path); err == nil {
		return nil
	} else if !errors.Is(err, fs.ErrNotExist) {
		return seedErr("%v", err)
	}
	if err := fsio.WriteFileAtomic(path, []byte(text)); err != nil {
		return seedErr("%v", err)
	}
	return nil
}

// migrateMilestonesHeading rewrites a first line of exactly "# Vision" to
// "# Milestones" and leaves the rest alone.
func migrateMilestonesHeading(path string) (bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return false, seedErr("%v", err)
	}
	if first, _, _ := strings.Cut(string(raw), "\n"); first != "# Vision" {
		return false, nil
	}
	text, err := fsio.ReadText(path)
	if err != nil {
		return false, seedErr("%v", err)
	}
	lines := strings.SplitAfter(text, "\n")
	lines[0] = "# Milestones" + strings.TrimPrefix(lines[0], "# Vision")
	if err := fsio.WriteFileAtomic(path, []byte(strings.Join(lines, ""))); err != nil {
		return false, seedErr("%v", err)
	}
	return true, nil
}

// backfillCounters adds the keys later versions introduced to an older
// counters.json. A file that is not a JSON object is an error: the old helper
// replaced a corrupt one with just the two backfilled keys, which restarted
// every item counter at zero.
func backfillCounters(path string) (bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return false, seedErr("%v", err)
	}
	v, err := jsonx.Decode(raw)
	d, ok := v.(*jsonx.Object)
	if err != nil || !ok {
		return false, seedErr("%s is not a JSON object; fix or remove it", filepath.ToSlash(filepath.Join(".hv", filepath.Base(path))))
	}
	changed := false
	if _, ok := d.Get("milestones"); !ok {
		d.Set("milestones", jsonNumber("0"))
		changed = true
	}
	if _, ok := d.Get("since_refactor"); !ok {
		sr := jsonx.NewObject()
		sr.Set("features", jsonNumber("0"))
		sr.Set("bugs", jsonNumber("0"))
		d.Set("since_refactor", sr)
		changed = true
	}
	if changed {
		if err := fsio.WriteJSONAtomic(path, d); err != nil {
			return false, seedErr("%v", err)
		}
	}
	return changed, nil
}

// checkCounters refuses a counters.json that exists but is not a JSON object.
func checkCounters(path string) error {
	raw, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return seedErr("%v", err)
	}
	if v, err := jsonx.Decode(raw); err != nil {
		return seedErr(".hv/counters.json is not valid JSON; fix or remove it")
	} else if _, ok := v.(*jsonx.Object); !ok {
		return seedErr(".hv/counters.json is not a JSON object; fix or remove it")
	}
	return nil
}

func updateGitignore(path string, umbrella bool) (bool, error) {
	raw, err := os.ReadFile(path)
	exists := err == nil
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return false, seedErr("%v", err)
	}
	next := MergeGitignore(string(raw), exists, umbrella)
	if exists && next == string(raw) {
		return false, nil
	}
	if err := fsio.WriteFileAtomic(path, []byte(next)); err != nil {
		return false, seedErr("%v", err)
	}
	return true, nil
}

var legacySlashRe = regexp.MustCompile(`/hv:([a-z][a-z0-9-]*)`)

// migrateKnowledgePreamble rewrites the legacy `/hv:X` command spelling to
// `/hv-X` above the first `## ` heading. Captured learnings are never touched.
func migrateKnowledgePreamble(path string) (bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return false, seedErr("%v", err)
	}
	legacy := false
	for _, l := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(l, "Use `/hv:") {
			legacy = true
			break
		}
	}
	if !legacy {
		return false, nil
	}
	text, err := fsio.ReadText(path)
	if err != nil {
		return false, seedErr("%v", err)
	}
	lines := strings.SplitAfter(text, "\n")
	changed := false
	for i, l := range lines {
		if strings.HasPrefix(l, "## ") {
			break
		}
		if n := legacySlashRe.ReplaceAllString(l, "/hv-$1"); n != l {
			lines[i] = n
			changed = true
		}
	}
	if !changed {
		return false, nil
	}
	if err := fsio.WriteFileAtomic(path, []byte(strings.Join(lines, ""))); err != nil {
		return false, seedErr("%v", err)
	}
	return true, nil
}

// removeMirror deletes the `.hv/bin` mirror that the 4.x init skill wrote. 5.0 has no
// mirror: the hv binary is on PATH. It removes what the old mirror step
// replaced (`hv-*` and `hvlib*.py` files) and the `__pycache__` Python left
// there, then the directory itself if that emptied it. Anything else stays and
// is reported, since the old step also left it alone. A symlinked `.hv/bin` is
// not followed.
func removeMirror(root string, warnings []string) (removed, warn []string) {
	dir := filepath.Join(root, ".hv", "bin")
	fi, err := os.Lstat(dir)
	if err != nil || !fi.IsDir() {
		return nil, warnings
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, append(warnings, fmt.Sprintf("cannot read .hv/bin: %v", err))
	}
	var kept []string
	for _, e := range entries {
		name := e.Name()
		rel := filepath.ToSlash(filepath.Join(".hv", "bin", name))
		stale := e.Type().IsRegular() && (strings.HasPrefix(name, "hv-") || (strings.HasPrefix(name, "hvlib") && strings.HasSuffix(name, ".py")))
		stale = stale || (e.IsDir() && name == "__pycache__")
		if !stale {
			kept = append(kept, rel)
			continue
		}
		if err := os.RemoveAll(filepath.Join(dir, name)); err != nil {
			warnings = append(warnings, fmt.Sprintf("cannot remove %s: %v", rel, err))
			kept = append(kept, rel)
			continue
		}
		removed = append(removed, rel)
	}
	if len(kept) == 0 {
		if err := os.Remove(dir); err == nil {
			removed = append(removed, ".hv/bin")
		}
	} else {
		warnings = append(warnings, fmt.Sprintf("left %s in .hv/bin: not an hv mirror file (5.0 does not use .hv/bin)", strings.Join(kept, ", ")))
	}
	sort.Strings(removed)
	return removed, warnings
}

func jsonNumber(s string) json.Number { return json.Number(s) }
