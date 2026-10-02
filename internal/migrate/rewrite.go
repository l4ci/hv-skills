package migrate

import (
	"fmt"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

// rule is one retired slash command. repl == "" marks a command whose
// replacement is ambiguous, so it is reported instead of rewritten. A match
// is lit followed by a word boundary; the boundary is checked by hand because
// RE2's \b and \w are ASCII-only while Python's are Unicode-aware.
type rule struct {
	lit  string
	repl string
	why  string
}

// rules are the eight commands cut in v4.
var rules = []rule{
	{"/hv-c", "/hv-capture", ""},
	{"/hv-assume", "/hv-work --preview", ""},
	{"/hv-rm", "/hv-capture --remove", ""},
	{"/hv-undo", "/hv-ship --undo", ""},
	{"/hv-context", "/hv-learn --term", ""},
	{"/hv-docs", "/hv-ship --docs", ""},
	{"/hv-issues", "", "ambiguous — could be --from-github or --from-gitlab"},
	{"/hv-map", "", "ambiguous — could be --init --map (first-run) or delete-the-line"},
}

// pattern is how the rule is shown in manual-review lines.
func (r rule) pattern() string { return r.lit[1:] + `\b` }

// isWord reports whether r is a Python \w character.
func isWord(r rune) bool { return r == '_' || unicode.IsLetter(r) || unicode.IsNumber(r) }

// find returns the [start, end) of every lit followed by a word boundary.
func (r rule) find(text string) [][]int {
	var out [][]int
	for from := 0; ; {
		i := strings.Index(text[from:], r.lit)
		if i < 0 {
			return out
		}
		start := from + i
		end := start + len(r.lit)
		next, _ := utf8.DecodeRuneInString(text[end:])
		if end == len(text) || !isWord(next) {
			out = append(out, []int{start, end})
			from = end
		} else {
			from = start + 1
		}
	}
}

var (
	fenced     = regexp.MustCompile("(?s)```.*?```")
	inlineCode = regexp.MustCompile("`[^`\n]+`")
	// helperTail is a helper name from "hv-" on: two or more dash-joined
	// Unicode word segments. A name with no path prefix also needs a word
	// boundary before "hv-", checked in helperPaths.
	helperTail = regexp.MustCompile(`(?:[\p{L}\p{N}_./]+/)?hv-[\p{L}\p{N}_]+(?:-[\p{L}\p{N}_]+)+`)
)

// helperPaths returns the spans of literal helper names such as hv-map-query
// or .hv/bin/hv-foo.
func helperPaths(text string) []span {
	var out []span
	for from := 0; from < len(text); {
		loc := helperTail.FindStringIndex(text[from:])
		if loc == nil {
			break
		}
		start, end := from+loc[0], from+loc[1]
		if strings.HasPrefix(text[start:], "hv-") {
			if prev, _ := utf8.DecodeLastRuneInString(text[:start]); start > 0 && isWord(prev) {
				from = start + 1
				continue
			}
		}
		out = append(out, span{start, end})
		from = end
	}
	return out
}

type span struct{ start, end int }

// skipMask returns the byte ranges where rewrites must not apply: fenced code
// blocks, inline code spans, and literal helper names such as `hv-map-query`
// or `.hv/bin/hv-foo`, which are not slash-command usages.
func skipMask(text string) []span {
	var out []span
	for _, re := range []*regexp.Regexp{fenced, inlineCode} {
		for _, m := range re.FindAllStringIndex(text, -1) {
			out = append(out, span{m[0], m[1]})
		}
	}
	return append(out, helperPaths(text)...)
}

func overlaps(start, end int, masks []span) bool {
	for _, m := range masks {
		if !(end <= m.start || m.end <= start) {
			return true
		}
	}
	return false
}

// Rewrite applies the eight rules to text. It returns the new text, how many
// references it rewrote, and one "file:line: rule — reason" string per
// ambiguous match left in place (line numbers refer to the input text).
func Rewrite(text, file string) (string, int, []string) {
	masks := skipMask(text)
	var manual []string
	for _, r := range rules {
		if r.repl != "" {
			continue
		}
		for _, m := range r.find(text) {
			if overlaps(m[0], m[1], masks) {
				continue
			}
			line := strings.Count(text[:m[0]], "\n") + 1
			manual = append(manual, fmt.Sprintf("%s:%d: %s — %s", file, line, r.pattern(), r.why))
		}
	}
	out, count := text, 0
	for _, r := range rules {
		if r.repl == "" {
			continue
		}
		masks := skipMask(out)
		var b strings.Builder
		last, n := 0, 0
		for _, m := range r.find(out) {
			if overlaps(m[0], m[1], masks) {
				continue
			}
			b.WriteString(out[last:m[0]])
			b.WriteString(r.repl)
			last = m[1]
			n++
		}
		b.WriteString(out[last:])
		out = b.String()
		count += n
	}
	return out, count, manual
}

// UnifiedDiff renders a unified diff with three lines of context in the
// layout of difflib.unified_diff. A rewrite replaces tokens inside lines and
// never adds or removes a line, so the two texts line up one to one.
func UnifiedDiff(old, new, label string) string {
	a, b := splitLines(old), splitLines(new)
	if len(a) != len(b) {
		return fmt.Sprintf("--- %s\n+++ %s (rewritten)\n", label, label)
	}
	const ctx = 3
	var changed []int
	for i := range a {
		if a[i] != b[i] {
			changed = append(changed, i)
		}
	}
	if len(changed) == 0 {
		return ""
	}
	var out strings.Builder
	fmt.Fprintf(&out, "--- %s\n+++ %s (rewritten)\n", label, label)
	// Group changed lines into hunks: two changes belong together when no more
	// than 2*ctx unchanged lines separate them.
	i := 0
	for i < len(changed) {
		j := i
		for j+1 < len(changed) && changed[j+1]-changed[j]-1 <= 2*ctx {
			j++
		}
		start, stop := max(changed[i]-ctx, 0), min(changed[j]+1+ctx, len(a))
		fmt.Fprintf(&out, "@@ -%s +%s @@\n", diffRange(start, stop), diffRange(start, stop))
		for k := start; k < stop; {
			if a[k] == b[k] {
				out.WriteString(" " + a[k])
				k++
				continue
			}
			end := k
			for end < stop && a[end] != b[end] {
				end++
			}
			for x := k; x < end; x++ {
				out.WriteString("-" + a[x])
			}
			for x := k; x < end; x++ {
				out.WriteString("+" + b[x])
			}
			k = end
		}
		i = j + 1
	}
	return out.String()
}

func diffRange(start, stop int) string {
	begin, length := start+1, stop-start
	if length == 1 {
		return fmt.Sprint(begin)
	}
	if length == 0 {
		begin--
	}
	return fmt.Sprintf("%d,%d", begin, length)
}

func splitLines(s string) []string {
	var out []string
	for len(s) > 0 {
		i := strings.IndexByte(s, '\n')
		if i < 0 {
			out = append(out, s)
			break
		}
		out = append(out, s[:i+1])
		s = s[i+1:]
	}
	return out
}
