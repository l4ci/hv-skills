package backlog

import (
	"errors"
	"path/filepath"

	"github.com/l4ci/hv-skills/v5/internal/config"
	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// Backend is the read side of a backlog, whichever store holds it.
type Backend interface {
	// Name is "file" or "issues".
	Name() string
	// Get returns an item, open or closed/archived. The error wraps
	// ErrNotFound when the reference is unknown.
	Get(ref string) (*Item, error)
	// Markdown renders the backlog as BACKLOG.md-shaped text. The file backend
	// returns the file verbatim and ignores closedLimit; a missing BACKLOG.md
	// is an error wrapping ErrNotFound. The issue backend renders the open
	// issues and the newest closedLimit closed ones (all when negative).
	Markdown(closedLimit int) (string, error)
	// Detail returns the detail file, or the issue body without its fields
	// block. ok is false when there is none.
	Detail(ref string) (text string, ok bool, err error)
}

// Open returns the backend selected by backlog.backend in cfg, the loaded
// config, for the project rooted at root (the directory holding .hv/). The
// issue backend reads through tr. Umbrella issue mode, where .hv/repos.json
// registers sub-repos, is not ported yet and is an error.
func Open(root string, cfg any, tr Tracker) (Backend, error) {
	name, err := config.Backend(cfg)
	if err != nil {
		return nil, err
	}
	if name == "file" {
		return &File{Root: root}, nil
	}
	if hasRepos(root) {
		return nil, errors.New("umbrella issue mode not ported yet")
	}
	if tr == nil {
		return nil, errors.New("backlog.backend \"issues\" needs a tracker")
	}
	return &Issues{Cfg: cfg, Tracker: tr}, nil
}

// hasRepos is whether .hv/repos.json registers at least one sub-repo, as
// hvlib_repos.load_repos counts them: an entry needs a name and a path.
func hasRepos(root string) bool {
	data, ok := fsio.LoadJSON(filepath.Join(root, ".hv", "repos.json"), nil).(*jsonx.Object)
	if !ok {
		return false
	}
	list, _ := data.Get("repos")
	entries, _ := list.([]any)
	for _, e := range entries {
		obj, ok := e.(*jsonx.Object)
		if !ok {
			continue
		}
		name, _ := obj.Get("name")
		path, _ := obj.Get("path")
		if n, ok := name.(string); ok && n != "" {
			if p, ok := path.(string); ok && p != "" {
				return true
			}
		}
	}
	return false
}

var (
	_ Backend = (*File)(nil)
	_ Backend = (*Issues)(nil)
)
