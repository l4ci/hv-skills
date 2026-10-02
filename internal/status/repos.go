package status

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/pystr"
)

// Repo is one registered sub-repo: its name and absolute, symlink-resolved path.
type Repo struct{ Name, Path string }

// LoadRepos reads <base>/.hv/repos.json (hvlib_repos.load_repos). Paths in the
// registry are relative to the umbrella root; each is resolved against base
// with os.path.realpath semantics, so a path that does not exist yet still
// resolves. An entry needs a non-empty name and path; a repeated name keeps
// its first position and takes the last path, as a Python dict does. A missing
// or unreadable registry gives none.
func LoadRepos(base string) []Repo {
	doc, ok := fsio.LoadJSON(filepath.Join(base, ".hv", "repos.json"), nil).(*jsonx.Object)
	if !ok {
		return nil
	}
	list, _ := doc.Get("repos")
	entries, _ := list.([]any)
	var out []Repo
	at := map[string]int{}
	for _, e := range entries {
		o, ok := e.(*jsonx.Object)
		if !ok {
			continue
		}
		name, rel := str(o, "name"), str(o, "path")
		if name == "" || rel == "" {
			continue
		}
		if !filepath.IsAbs(rel) {
			rel = filepath.Join(base, rel)
		}
		p := Realpath(rel)
		if i, seen := at[name]; seen {
			out[i].Path = p
			continue
		}
		at[name] = len(out)
		out = append(out, Repo{Name: name, Path: p})
	}
	return out
}

// Realpath is os.path.realpath: an absolute path with symlinks resolved as far
// as the path exists, and the rest kept as written.
func Realpath(p string) string {
	p, err := filepath.Abs(p)
	if err != nil {
		return filepath.Clean(p)
	}
	rest := ""
	for cur := p; ; {
		if real, err := filepath.EvalSymlinks(cur); err == nil {
			return filepath.Join(real, rest)
		}
		parent := filepath.Dir(cur)
		if parent == cur {
			return p
		}
		rest = filepath.Join(filepath.Base(cur), rest)
		cur = parent
	}
}

// ParseReposCSV is parse_repos_csv: comma-separated names, stripped, empties
// dropped, duplicates kept in order.
func ParseReposCSV(csv string) []string {
	var out []string
	for _, p := range strings.Split(csv, ",") {
		if p = pystr.Strip(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// Missing returns the names in names that repos does not register.
func Missing(repos []Repo, names []string) []string {
	have := map[string]bool{}
	for _, r := range repos {
		have[r.Name] = true
	}
	var out []string
	for _, n := range names {
		if !have[n] {
			out = append(out, n)
		}
	}
	return out
}

// HasCode is whether dir holds anything besides the umbrella's own files and
// the top-level directories of the given sub-repos (hv-refactor-targets).
func HasCode(dir string, repos []Repo) bool {
	real := Realpath(dir)
	sub := map[string]bool{}
	for _, r := range repos {
		rel, err := filepath.Rel(real, r.Path)
		if err != nil || rel == "" || strings.HasPrefix(rel, "..") {
			continue
		}
		sub[strings.SplitN(rel, string(filepath.Separator), 2)[0]] = true
	}
	ignore := map[string]bool{".git": true, ".hv": true, ".claude": true, ".claude-plugin": true,
		".gitignore": true, ".docsignore": true, ".stow-local-ignore": true, ".DS_Store": true}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	for _, e := range entries {
		if !ignore[e.Name()] && !sub[e.Name()] {
			return true
		}
	}
	return false
}
