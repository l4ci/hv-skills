// Package artifact holds what the A6 file-mode verbs (milestone, plan,
// design, spike, proof, debug counter) share: the exit-coded error their
// packages return and the flat frontmatter subset their files use. It does
// not import internal/cli; internal/cli's A6 glue maps Error to the exit table.
//
// ParseFrontmatter and UpdateFrontmatterField are hv's one frontmatter
// implementation, byte-compatible with bin/hvlib_frontmatter.py; other
// phases (A5 map and qa files) reuse them rather than parse again. Keep the
// API to those two plus Str: flat `key: value` and inline `[a, b]` lists only.
package artifact

import (
	"fmt"
	"regexp"
	"strings"
)

// Exit codes an Error may carry; same numbers as docs/design/5.0-cli-conventions.md.
const (
	ExitFailed      = 1
	ExitUsage       = 2
	ExitResolution  = 3
	ExitRefused     = 4
	ExitUnavailable = 5
	ExitInternal    = 70
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

var fmEnd = regexp.MustCompile(`(?m)^---[ \t\r\f\v]*$`)

func hasFM(text string) bool {
	return strings.HasPrefix(text, "---\n") || strings.HasPrefix(text, "---\r\n")
}

// ParseFrontmatter mirrors hvlib_frontmatter.parse_frontmatter: a flat
// `key: value` / `key: [a, b]` subset between `---` lines. Values stay
// strings; an inline list comes back as []string. It returns (nil, text)
// when there is no frontmatter, and never fails. Keys keep file order.
func ParseFrontmatter(text string) (map[string]any, []string, string) {
	if !hasFM(text) {
		return nil, nil, text
	}
	rest := ""
	if i := strings.Index(text, "\n"); i >= 0 {
		rest = text[i+1:]
	}
	loc := fmEnd.FindStringIndex(rest)
	if loc == nil {
		return nil, nil, text
	}
	block := rest[:loc[0]]
	body := strings.TrimLeft(rest[loc[1]:], "\n")
	fm := map[string]any{}
	var order []string
	for _, raw := range strings.Split(strings.ReplaceAll(block, "\r\n", "\n"), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		key, value = strings.TrimSpace(key), strings.TrimSpace(value)
		if _, seen := fm[key]; !seen {
			order = append(order, key)
		}
		if strings.HasPrefix(value, "[") && strings.HasSuffix(value, "]") {
			list := []string{}
			for _, v := range strings.Split(strings.TrimSpace(value[1:len(value)-1]), ",") {
				if v = strings.TrimSpace(v); v != "" {
					list = append(list, v)
				}
			}
			fm[key] = list
		} else {
			fm[key] = value
		}
	}
	if len(fm) == 0 {
		return nil, nil, text
	}
	return fm, order, body
}

// Str returns a frontmatter value as a string ("" when absent or a list).
func Str(fm map[string]any, key string) string {
	s, _ := fm[key].(string)
	return s
}

// UpdateFrontmatterField mirrors hvlib_frontmatter.update_frontmatter_field:
// it replaces the first `<field>: <value>` in the frontmatter slice and
// reports whether it found one.
func UpdateFrontmatterField(content, field, value string) (string, bool) {
	if !hasFM(content) {
		return content, false
	}
	start := strings.Index(content, "\n") + 1
	rest := content[start:]
	loc := fmEnd.FindStringIndex(rest)
	if loc == nil {
		return content, false
	}
	fm, after := rest[:loc[0]], rest[loc[0]:]
	pat := regexp.MustCompile(`(?m)^(` + regexp.QuoteMeta(field) + `:[ \t\r\n\f\v]*)\S+`)
	done := false
	newFM := pat.ReplaceAllStringFunc(fm, func(m string) string {
		if done {
			return m
		}
		done = true
		return pat.FindStringSubmatch(m)[1] + value
	})
	if !done {
		return content, false
	}
	return content[:start] + newFM + after, true
}
