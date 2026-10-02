// Package design ports hv-design-add, -list, -show, -put and -rm for file
// mode: the per-item design files under .hv/designs/<ID>.md.
package design

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/artifact"
	"github.com/l4ci/hv-skills/v5/internal/frontmatter"
	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/section"
)

var idRe = regexp.MustCompile(`^[BFT]\d{2,}$`)

// ValidID reports whether id is a file-mode design ID: [BFT]\d{2,}.
func ValidID(id string) bool { return idRe.MatchString(id) }

// Type is the item type letter of a valid ID.
func Type(id string) string { return id[:1] }

func check(id string) error {
	if !ValidID(id) {
		return artifact.Errf(artifact.ExitUsage, "ID must match [BFT]\\d{2,} (e.g. B07, F03, T11); designs are per-item, not per-slice or per-milestone, got %q", id)
	}
	return nil
}

func path(root, id string) string { return filepath.Join(root, ".hv", "designs", id+".md") }

func notFound(root, id string) *artifact.Error {
	return artifact.Errf(artifact.ExitResolution, "design %s not found (.hv/designs/%s.md)", id, id)
}

// Add creates the design stub; an existing design is exit 4.
func Add(root, id, title string) error {
	if err := check(id); err != nil {
		return err
	}
	p := path(root, id)
	return fsio.Locked(p, fsio.LockTimeout, func() error {
		if _, err := os.Stat(p); err == nil {
			return artifact.Errf(artifact.ExitRefused, ".hv/designs/%s.md already exists", id)
		}
		stub := fmt.Sprintf(`---
id: %[1]s
title: %[2]s
status: draft
created: %[3]s
---

# %[1]s — %[2]s

## Goal

_(one sentence — what shipping this design means)_

## Design

_(3–8 sentences — the chosen shape, the moving parts, where they live)_

## Approaches considered

_(2–3 alternatives weighed with Pros / Cons / Why this might or might not be the right answer)_

## Open questions

_(unresolved questions to answer before /hv-plan or during execution)_

## Assumptions

_(named assumptions made implicit by the chosen design)_
`, id, title, time.Now().Format("2006-01-02"))
		return fsio.WriteFileAtomic(p, []byte(stub))
	})
}

// Entry is one row of List.
type Entry struct{ ID, Title, Status, Created string }

// List reads .hv/designs/*.md in name order; files without frontmatter are
// skipped. status defaults to draft and id to the file stem.
func List(root string) ([]Entry, error) {
	docs, err := artifact.ListDocs(filepath.Join(root, ".hv", "designs"))
	if err != nil {
		return nil, err
	}
	out := []Entry{}
	for _, d := range docs {
		e := Entry{ID: frontmatter.Str(d.FM, "id"), Title: frontmatter.Str(d.FM, "title"),
			Status: frontmatter.Str(d.FM, "status"), Created: frontmatter.Str(d.FM, "created")}
		if e.ID == "" {
			e.ID = d.Stem
		}
		if e.Status == "" {
			e.Status = "draft"
		}
		out = append(out, e)
	}
	return out, nil
}

// Show is the stored design, verbatim.
func Show(root, id string) (string, error) {
	if err := check(id); err != nil {
		return "", err
	}
	b, err := os.ReadFile(path(root, id))
	if err != nil {
		return "", notFound(root, id)
	}
	return string(b), nil
}

// Put replaces an existing design's text; changed is false when the text is
// already identical.
func Put(root, id, text string) (changed bool, err error) {
	if err = check(id); err != nil {
		return
	}
	p := path(root, id)
	if _, serr := os.Stat(p); serr != nil { // no lock file or directory for a missing design
		return false, notFound(root, id).WithHint("hv design add " + id + " --title <text>")
	}
	err = fsio.Locked(p, fsio.LockTimeout, func() error {
		old, rerr := os.ReadFile(p)
		if rerr != nil {
			return notFound(root, id).WithHint("hv design add " + id + " --title <text>")
		}
		if string(old) == text {
			return nil
		}
		changed = true
		return fsio.WriteFileAtomic(p, []byte(text))
	})
	return
}

// Rm deletes a design; a missing one is exit 3, never a no-op.
func Rm(root, id string) error {
	if err := check(id); err != nil {
		return err
	}
	p := path(root, id)
	if _, err := os.Stat(p); err != nil {
		return notFound(root, id)
	}
	return fsio.Locked(p, fsio.LockTimeout, func() error {
		if err := os.Remove(p); err != nil {
			return notFound(root, id)
		}
		return nil
	})
}

// Amend replaces or appends to the body of "## <heading>" in a design, as
// hv-design-amend did: trailing newlines of text are dropped and the block
// is "\n<text>\n\n". mode is "append" or "replace". A missing design or
// heading is exit 3. changed is false when the file would not change.
func Amend(root, id, heading, mode, text string) (changed bool, err error) {
	if err = check(id); err != nil {
		return
	}
	if mode != "append" && mode != "replace" {
		return false, artifact.Errf(artifact.ExitUsage, "mode must be 'append' or 'replace', got %q", mode)
	}
	p := path(root, id)
	if _, serr := os.Stat(p); serr != nil {
		return false, notFound(root, id)
	}
	block := "\n" + strings.TrimRight(text, "\n") + "\n\n"
	err = fsio.Locked(p, fsio.LockTimeout, func() error {
		content, rerr := fsio.ReadText(p)
		if rerr != nil {
			return notFound(root, id)
		}
		_, _, ok := section.Find(content, heading)
		if !ok {
			return artifact.Errf(artifact.ExitResolution, "section '## %s' not found in .hv/designs/%s.md", heading, id)
		}
		var updated string
		if mode == "replace" {
			updated = section.Replace(content, heading, block)
		} else {
			updated, _ = artifact.AppendSection(content, heading, block)
		}
		if updated == content {
			return nil
		}
		changed = true
		return fsio.WriteFileAtomic(p, []byte(updated))
	})
	return
}
