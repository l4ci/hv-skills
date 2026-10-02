package backlog

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/pystr"
)

// File is the backlog kept in .hv/BACKLOG.md, with finished items in
// .hv/ARCHIVE.md (FileBackend in hvlib_backend.py).
type File struct {
	Root string // project root, the directory that holds .hv/
}

// Name is "file".
func (f *File) Name() string { return "file" }

func (f *File) hv(parts ...string) string {
	return filepath.Join(append([]string{f.Root, ".hv"}, parts...)...)
}

// readText reads a file the way Path.read_text does: universal newlines, so
// CRLF files read as LF.
func readText(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return pystr.Universal(string(raw)), nil
}

// Corpus is BACKLOG.md with its trailing newlines trimmed, a newline, then
// ARCHIVE.md: the text an item ID is looked up in (load_backlog_corpus). A
// missing or unreadable file counts as empty.
func (f *File) Corpus() string {
	primary, _ := readText(f.hv("BACKLOG.md"))
	archive, _ := readText(f.hv("ARCHIVE.md"))
	return strings.TrimRight(primary, "\n") + "\n" + archive
}

// Get looks up an item by its exact ID ("B07"; B7 does not find B07), in the
// backlog or the archive. Fields come from the origin line; Closed, Reason and
// Note from the done line.
func (f *File) Get(ref string) (*Item, error) {
	corpus := f.Corpus()
	line, title, ok := FindOrigin(corpus, ref)
	if !ok {
		return nil, fmt.Errorf("%w: %s", ErrNotFound, ref)
	}
	it := &Item{ID: ref, Fields: ParseFields(line), Line: line, Title: title}
	if r, _ := utf8.DecodeRuneInString(ref); strings.ContainsRune(ItemLetters, r) {
		it.Type = string(r)
	}
	if b, ok := ParseOpen("- " + line); ok {
		it.Tag, it.Title = b.Tag, b.Title
	}
	// The closure reason lives on the done marker, which FindOrigin strips.
	doneLine := regexp.MustCompile(`(?m)^- ~~\*\*\[` + regexp.QuoteMeta(ref) + `\].*$`).FindString(corpus)
	if d, ok := ParseDone(doneLine); ok {
		it.Closed, it.Reason, it.Note = true, d.Reason, d.Note
	}
	return it, nil
}

// Markdown returns BACKLOG.md verbatim; closedLimit is ignored.
func (f *File) Markdown(int) (string, error) {
	text, err := readText(f.hv("BACKLOG.md"))
	if errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("%w: .hv/BACKLOG.md does not exist", ErrNotFound)
	}
	return text, err
}

// Detail returns the content of the item's detail file,
// .hv/<kind>/<ID>.md. ok is false when the ID has no type, the file is
// missing or it cannot be read.
func (f *File) Detail(ref string) (string, bool, error) {
	if ref == "" {
		return "", false, nil
	}
	r, _ := utf8.DecodeRuneInString(ref)
	t, ok := TypeByLetter(strings.ToUpper(string(r)))
	if !ok || t.Kind == "" {
		return "", false, nil
	}
	text, err := readText(f.hv(t.Kind, ref+".md"))
	if err != nil {
		return "", false, nil
	}
	return text, true, nil
}

var kindPrefix = map[string]string{"bugs": "B", "features": "F", "tasks": "T", "milestones": "M"}

// NextID bumps the counter for kind (bugs, features, tasks or milestones) in
// .hv/counters.json and returns the new zero-padded ID such as "B07". The
// counter never lags the highest ID already in BACKLOG.md or ARCHIVE.md.
// Existing keys keep their position and a new key is appended, so the file
// matches what the Python helper writes.
func (f *File) NextID(kind string) (string, error) {
	prefix, ok := kindPrefix[kind]
	if !ok {
		return "", fmt.Errorf("unknown counter kind %q (want bugs|features|tasks|milestones)", kind)
	}
	pat := regexp.MustCompile(`\[` + prefix + `(\p{Nd}+)\]`)
	highest := 0
	for _, name := range []string{"BACKLOG.md", "ARCHIVE.md"} {
		text, err := readText(f.hv(name))
		if err != nil {
			continue
		}
		for _, m := range pat.FindAllStringSubmatch(text, -1) {
			n, err := atoi(m[1])
			if err != nil {
				return "", err
			}
			highest = max(highest, n)
		}
	}
	var next int
	var floatCounter bool // a non-integer counter above every ID: Python bumps it, then fails to format it
	err := fsio.UpdateJSON(f.hv("counters.json"), jsonx.NewObject(), func(v any) (any, error) {
		d, ok := v.(*jsonx.Object)
		if !ok {
			return nil, errors.New("counters.json is not a JSON object")
		}
		cur := 0
		if raw, ok := d.Get(kind); ok {
			num, isNum := raw.(json.Number)
			if !isNum {
				return nil, fmt.Errorf("counters.json: %s is not a number", kind)
			}
			n, err := strconv.Atoi(string(num))
			if err != nil {
				fl, ferr := strconv.ParseFloat(string(num), 64)
				if ferr != nil {
					return nil, fmt.Errorf("counters.json: %s is not a number", kind)
				}
				if float64(highest) > fl {
					n = highest // max() picks the int, so the float never shows
				} else {
					floatCounter = true
					d.Set(kind, json.Number(jsonx.PyFloat(fl+1)))
					return d, nil
				}
			}
			cur = n
		}
		next = max(cur, highest) + 1
		d.Set(kind, json.Number(strconv.Itoa(next)))
		return d, nil
	})
	if err != nil {
		return "", err
	}
	if floatCounter {
		return "", fmt.Errorf("counters.json: %s is not an integer", kind)
	}
	return fmt.Sprintf("%s%02d", prefix, next), nil
}
