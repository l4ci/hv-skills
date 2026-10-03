package initproj

import (
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
)

// ErrNoSkillsRoot: no hv-*/SKILL.md directly under the skills root.
var ErrNoSkillsRoot = errors.New("no hv-*/SKILL.md skills found")

const (
	codexIgnoreLine  = ".agents/skills/hv-*"
	codexIgnoreBlock = "\n# hv-skills Codex discovery (machine-specific symlinks)\n" + codexIgnoreLine + "\n"
)

// CodexLink is one .agents/skills/<name> symlink. Status is created,
// unchanged or skipped.
type CodexLink struct {
	Name, Target, Status string
}

// CodexResult is what Codex did. Warnings name the paths it left alone.
type CodexResult struct {
	SkillsDir string
	Links     []CodexLink
	Gitignore bool // .gitignore was written
	Warnings  []string
}

// Changed is whether Codex wrote a link or the .gitignore.
func (r CodexResult) Changed() bool {
	if r.Gitignore {
		return true
	}
	for _, l := range r.Links {
		if l.Status == "created" {
			return true
		}
	}
	return false
}

// SkillNames lists the hv-* directories under skillsDir that hold a SKILL.md,
// sorted. Empty means skillsDir is not a skills root.
func SkillNames(skillsDir string) []string {
	entries, err := os.ReadDir(skillsDir)
	if err != nil {
		return nil
	}
	var names []string
	for _, e := range entries {
		if !strings.HasPrefix(e.Name(), "hv-") {
			continue
		}
		if fi, err := os.Stat(filepath.Join(skillsDir, e.Name(), "SKILL.md")); err == nil && fi.Mode().IsRegular() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names
}

// ValidSkillsRoot reports whether skillsDir holds at least one hv-*/SKILL.md.
func ValidSkillsRoot(skillsDir string) bool { return len(SkillNames(skillsDir)) > 0 }

// Codex links every hv skill under skillsDir into root/.agents/skills so Codex
// discovers them, and ignores the machine-specific links in root/.gitignore.
// It links rather than copies because the skills reach ../references through
// the link. It never overwrites: anything already at a link path is skipped.
// An invalid skillsDir returns ErrNoSkillsRoot before anything is written.
func Codex(root, skillsDir string) (CodexResult, error) {
	res := CodexResult{SkillsDir: skillsDir}
	abs, err := filepath.Abs(skillsDir)
	if err != nil {
		return res, seedErr("%v", err)
	}
	res.SkillsDir = abs
	names := SkillNames(abs)
	if len(names) == 0 {
		return res, ErrNoSkillsRoot
	}
	dir := filepath.Join(root, ".agents", "skills")
	if err := os.MkdirAll(dir, 0o777); err != nil {
		return res, seedErr("%v", err)
	}
	for _, name := range names {
		target := filepath.Join(abs, name)
		link := filepath.Join(dir, name)
		l := CodexLink{Name: name, Target: target}
		rel := filepath.ToSlash(filepath.Join(".agents", "skills", name))
		if cur, err := os.Readlink(link); err == nil && cur == target {
			l.Status = "unchanged"
		} else if _, err := os.Lstat(link); err == nil {
			l.Status = "skipped"
			res.Warnings = append(res.Warnings, "left "+rel+" alone: something else is already there")
		} else if !errors.Is(err, os.ErrNotExist) {
			return res, seedErr("%v", err)
		} else if err := os.Symlink(target, link); err != nil {
			return res, seedErr("%v", err)
		} else {
			l.Status = "created"
		}
		res.Links = append(res.Links, l)
	}

	gi := filepath.Join(root, ".gitignore")
	raw, err := os.ReadFile(gi)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return res, seedErr("%v", err)
	}
	if !hasLine(string(raw), codexIgnoreLine) {
		if err := fsio.WriteFileAtomic(gi, append(raw, codexIgnoreBlock...)); err != nil {
			return res, seedErr("%v", err)
		}
		res.Gitignore = true
	}
	return res, nil
}
