// Package artifact holds what the A6 file-mode verbs (milestone, plan,
// design, spike, proof, debug counter) share: the exit-coded error their
// packages return. It does not import internal/cli; internal/cli's A6 glue
// maps Error to the exit table.
package artifact

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/config"
	"github.com/l4ci/hv-skills/v5/internal/frontmatter"
	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// Exit codes an Error may carry; same numbers as docs/design/5.0-cli-conventions.md.
const (
	ExitFailed         = 1
	ExitUsage          = 2
	ExitResolution     = 3
	ExitRefused        = 4
	ExitUnavailable    = 5
	ExitInternal       = 70
	ExitNotImplemented = 71
)

// Error is a verb failure: its exit code, message and optional hint.
type Error struct {
	Exit    int
	Message string
	Hint    string
}

func (e *Error) Error() string { return e.Message }

// Errf builds an Error.
func Errf(exit int, format string, a ...any) *Error {
	return &Error{Exit: exit, Message: fmt.Sprintf(format, a...)}
}

// WithHint returns e with a hint line.
func (e *Error) WithHint(h string) *Error { e.Hint = h; return e }

// IssueMode reports whether backlog.backend is "issues". An unreadable
// config or an unknown value counts as file mode, as the old helpers did.
func IssueMode(root string) bool {
	v, ok := config.Lookup(config.Load(filepath.Join(root, ".hv", "config.json")), "backlog.backend")
	s, _ := v.(string)
	return ok && s == "issues"
}

// ErrIssueMode is what a file-only port returns under backlog.backend
// "issues" until internal/tracker (A8) is wired in: exit 71, not a guess.
func ErrIssueMode(verb string) *Error {
	return Errf(ExitNotImplemented, "%s: issue mode (backlog.backend \"issues\") is not ported yet", verb).
		WithHint("needs internal/tracker (A8)")
}

// ReadText reads like Python's read_text: CRLF becomes LF. Replace with
// fsio.ReadText once that lands (#89).
func ReadText(path string) (string, error) {
	b, err := os.ReadFile(path)
	return strings.ReplaceAll(string(b), "\r\n", "\n"), err
}

// ReadBody reads a --body-file ("-" is stdin) the way the old put helpers
// did: raw bytes, each invalid UTF-8 byte replaced by U+FFFD, no newline
// normalisation. An unreadable file is a usage error.
func ReadBody(stdin io.Reader, path string) (string, error) {
	var b []byte
	var err error
	if path == "-" {
		b, err = io.ReadAll(stdin)
	} else {
		b, err = os.ReadFile(path)
	}
	if err != nil {
		return "", Errf(ExitUsage, "cannot read --body-file %s: %v", path, unwrap(err))
	}
	return string([]rune(string(b))), nil
}

func unwrap(err error) error {
	var pe *os.PathError
	if errors.As(err, &pe) {
		return pe.Err
	}
	return err
}

// Doc is one markdown file with parseable frontmatter.
type Doc struct {
	Stem string // file name without .md
	FM   map[string]any
}

// ListDocs globs dir/*.md in name order and returns the files that carry
// frontmatter, like hv-fm-list. A missing dir is an empty list.
func ListDocs(dir string) ([]Doc, error) {
	files, _ := filepath.Glob(filepath.Join(dir, "*.md"))
	sort.Strings(files)
	docs := []Doc{}
	for _, f := range files {
		text, err := ReadText(f)
		if err != nil {
			return nil, err
		}
		if fm, _, _ := frontmatter.Parse(text); fm != nil {
			docs = append(docs, Doc{Stem: strings.TrimSuffix(filepath.Base(f), ".md"), FM: fm})
		}
	}
	return docs, nil
}

// Repos is the sub-repo registry, name to absolute path, from
// .hv/repos.json. Paths there are relative to the project root.
func Repos(root string) map[string]string {
	out := map[string]string{}
	reg, ok := fsio.LoadJSON(filepath.Join(root, ".hv", "repos.json"), nil).(*jsonx.Object)
	if !ok {
		return out
	}
	lv, _ := reg.Get("repos")
	list, _ := lv.([]any)
	for _, e := range list {
		o, ok := e.(*jsonx.Object)
		if !ok {
			continue
		}
		n, _ := o.Get("name")
		p, _ := o.Get("path")
		name, _ := n.(string)
		rel, _ := p.(string)
		if name == "" || rel == "" {
			continue
		}
		if !filepath.IsAbs(rel) {
			rel = filepath.Join(root, rel)
		}
		if real, err := filepath.EvalSymlinks(rel); err == nil {
			rel = real
		}
		out[name] = rel
	}
	return out
}

// SplitCSV splits a comma list, trimming blanks and dropping empties
// (hvlib_repos.parse_repos_csv).
func SplitCSV(s string) []string {
	out := []string{}
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
