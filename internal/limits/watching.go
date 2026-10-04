package limits

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"github.com/l4ci/hv/v5/internal/fsio"
)

// WatchFileName is the record of a running watcher under <git-common-dir>/hv/,
// next to the lease. It says which process is acting on the limits list, so
// `hv limit status` can answer "watching" and a second `hv limit watch` does
// not act twice.
const WatchFileName = "limit-watch.json"

// Watching is the content of that file.
type Watching struct {
	PID       int    `json:"pid"`
	StartedAt string `json:"startedAt"`
	// Mode is "watch" for `hv limit watch` or "supervisor" for the loop
	// inside `hv keepalive run`.
	Mode string `json:"mode"`
}

// Modes of Watching.
const (
	ModeWatch      = "watch"
	ModeSupervisor = "supervisor"
)

// WatchPath is the file of a repo, by its git common dir.
func WatchPath(commonDir string) string { return filepath.Join(commonDir, "hv", WatchFileName) }

// ReadWatching loads the record; found is false when there is none or it does
// not parse.
func ReadWatching(commonDir string) (w Watching, found bool) {
	b, err := os.ReadFile(WatchPath(commonDir))
	if err != nil || json.Unmarshal(b, &w) != nil || w.PID <= 0 {
		return Watching{}, false
	}
	return w, true
}

// WriteWatching records the running watcher.
func WriteWatching(commonDir string, w Watching) error {
	b, err := json.MarshalIndent(w, "", "  ")
	if err != nil {
		return err
	}
	p := WatchPath(commonDir)
	if err := os.MkdirAll(filepath.Dir(p), 0o777); err != nil {
		return err
	}
	return fsio.WriteFileAtomic(p, append(b, '\n'))
}

// RemoveWatching deletes the record when it is still this process's.
func RemoveWatching(commonDir string, pid int) {
	if w, ok := ReadWatching(commonDir); ok && w.PID == pid {
		if err := os.Remove(WatchPath(commonDir)); err != nil && !errors.Is(err, os.ErrNotExist) {
			return
		}
	}
}
