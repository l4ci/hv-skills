// Package repos reads the umbrella sub-repo registry, .hv/repos.json. It is
// the one parser of that file (hvlib_repos.load_repos): an entry counts when
// it has a non-empty string name and path; paths are relative to the
// project root.
package repos

import (
	"path/filepath"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// Repo is one registered sub-repo: Rel as written in repos.json, Path
// absolute, with symlinks resolved when it exists.
type Repo struct {
	Name, Rel, Path string
}

// Load returns root's registered sub-repos in file order. A missing or
// unreadable registry is empty.
func Load(root string) []Repo {
	reg, ok := fsio.LoadJSON(filepath.Join(root, ".hv", "repos.json"), nil).(*jsonx.Object)
	if !ok {
		return nil
	}
	entries, _ := reg.Get("repos")
	items, _ := entries.([]any)
	var out []Repo
	for _, e := range items {
		obj, ok := e.(*jsonx.Object)
		if !ok {
			continue
		}
		name, _ := obj.Get("name")
		rel, _ := obj.Get("path")
		n, _ := name.(string)
		r, _ := rel.(string)
		if n == "" || r == "" {
			continue
		}
		p := r
		if !filepath.IsAbs(p) {
			p = filepath.Join(root, p)
		}
		if real, err := filepath.EvalSymlinks(p); err == nil {
			p = real
		}
		out = append(out, Repo{Name: n, Rel: r, Path: filepath.Clean(p)})
	}
	return out
}

// Paths is Load as name to absolute path; a repeated name keeps the last.
func Paths(root string) map[string]string {
	out := map[string]string{}
	for _, r := range Load(root) {
		out[r.Name] = r.Path
	}
	return out
}
