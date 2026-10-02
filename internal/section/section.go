// Package section scans `## Topic` sections in the markdown state files
// (KNOWLEDGE.md, DECISIONS.md) and writes managed blocks into the project
// instructions file. It ports bin/hvlib_section.py, so hv and the old helpers
// produce byte-identical files.
package section

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
)

var nextHeading = regexp.MustCompile(`(?m)^## `)

// Find locates the body of "## <name>": the offsets just after the heading
// line and of the next "## " heading (or len(content)). ok is false when the
// heading is missing. A column-0 "## " line inside the body ends the section.
func Find(content, name string) (start, end int, ok bool) {
	re := regexp.MustCompile(`(?m)^## ` + regexp.QuoteMeta(name) + `\s*$`)
	m := re.FindStringIndex(content)
	if m == nil {
		return 0, 0, false
	}
	start = m[1]
	if n := nextHeading.FindStringIndex(content[start:]); n != nil {
		return start, start + n[0], true
	}
	return start, len(content), true
}

// Body returns the body of "## <name>", or "" when it is missing.
func Body(content, name string) string {
	if s, e, ok := Find(content, name); ok {
		return content[s:e]
	}
	return ""
}

// Replace swaps the body of "## <name>" for newBody. A missing section is
// appended at the end, after a blank line.
func Replace(content, name, newBody string) string {
	s, e, ok := Find(content, name)
	if !ok {
		return strings.TrimRight(content, "\n") + "\n\n## " + name + "\n" + newBody
	}
	return content[:s] + newBody + content[e:]
}

// Topic is one "## Name" section: Body runs from after the heading line to the
// next "## " heading or EOF, whitespace untouched.
type Topic struct{ Name, Body string }

var topicHeading = regexp.MustCompile(`(?m)^## .+$`)

// Topics returns every "## Topic" section in document order.
func Topics(content string) []Topic {
	locs := topicHeading.FindAllStringIndex(content, -1)
	out := make([]Topic, 0, len(locs))
	for i, l := range locs {
		end := len(content)
		if i+1 < len(locs) {
			end = locs[i+1][0]
		}
		out = append(out, Topic{
			Name: strings.TrimSpace(content[l[0]+3 : l[1]]),
			Body: content[l[1]:end],
		})
	}
	return out
}

// Matching renders each section whose lowercased title is in wanted, in
// document order, separated by a blank line, bodies right-trimmed. Every line
// ends in a newline; the result is "" when nothing matches.
func Matching(content string, wanted map[string]bool) string {
	var b strings.Builder
	first := true
	for _, t := range Topics(content) {
		if !wanted[strings.ToLower(t.Name)] {
			continue
		}
		if !first {
			b.WriteString("\n")
		}
		b.WriteString("## " + t.Name + "\n")
		b.WriteString(strings.TrimRight(t.Body, " \t\n\r\f\v") + "\n")
		first = false
	}
	return b.String()
}

// InstructionsFile is the project-instructions file under root that holds the
// managed hv blocks: AGENTS.md when it exists, else CLAUDE.md (which may not
// exist yet; UpsertBlock creates it).
func InstructionsFile(root string) string {
	agents := filepath.Join(root, "AGENTS.md")
	if _, err := os.Stat(agents); err == nil {
		return agents
	}
	return filepath.Join(root, "CLAUDE.md")
}

// BlockRegex matches a managed block: the canonical
// "<!-- hv-<key>-start -->…<!-- hv-<key>-end -->" and, when legacy is not
// empty, the old "<!-- hv:<legacy>:start -->…<!-- hv:<legacy>:end -->" form.
// consumeNewline also eats one newline after the end marker.
func BlockRegex(key, legacy string, consumeNewline bool) *regexp.Regexp {
	tail := ""
	if consumeNewline {
		tail = `\n?`
	}
	if legacy != "" {
		return regexp.MustCompile(`(?s)<!-- hv(?:-` + regexp.QuoteMeta(key) + `-start|:` + regexp.QuoteMeta(legacy) + `:start) -->` +
			`.*?` +
			`<!-- hv(?:-` + regexp.QuoteMeta(key) + `-end|:` + regexp.QuoteMeta(legacy) + `:end) -->` + tail)
	}
	return regexp.MustCompile(`(?s)<!-- hv-` + regexp.QuoteMeta(key) + `-start -->.*?<!-- hv-` + regexp.QuoteMeta(key) + `-end -->` + tail)
}

// Block statuses returned by UpsertBlock.
const (
	Created   = "created"
	Updated   = "updated"
	Appended  = "appended"
	Unchanged = "unchanged"
)

// UpsertBlock writes block into path: it replaces an existing block for key,
// appends one when none exists, or creates the file holding just the block.
// A second identical call is Unchanged and does not touch the file.
func UpsertBlock(path, key, block, legacy string) (string, error) {
	content, err := fsio.ReadText(path)
	if os.IsNotExist(err) {
		return Created, fsio.WriteFileAtomic(path, []byte(block+"\n"))
	}
	if err != nil {
		return "", err
	}
	re := BlockRegex(key, legacy, false)
	var next, status string
	if re.MatchString(content) {
		// ReplaceAllLiteralString: Python's re.sub would read backslash
		// escapes in block, which managed blocks never rely on.
		next = re.ReplaceAllLiteralString(content, block)
		status = Updated
	} else {
		next = strings.TrimRight(content, " \t\n\r\f\v") + "\n\n" + block + "\n"
		status = Appended
	}
	if next == content {
		return Unchanged, nil
	}
	return status, fsio.WriteFileAtomic(path, []byte(next))
}

// Lines splits s like Python's str.splitlines: at \n, \r, \r\n, \v, \f,
// \x1c-\x1e, \x85, \u2028 and \u2029, dropping the separators and any final
// empty piece.
func Lines(s string) []string {
	var out []string
	start := 0
	rs := []rune(s)
	// Work on byte offsets via a rune walk.
	pos := 0
	for i := 0; i < len(rs); i++ {
		r := rs[i]
		w := len(string(r))
		switch r {
		case '\n', '\r', '\v', '\f', 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029:
			out = append(out, s[start:pos])
			if r == '\r' && i+1 < len(rs) && rs[i+1] == '\n' {
				i++
				pos++
			}
			start = pos + w
		}
		pos += w
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}
