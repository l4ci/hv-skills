// Package worker is the Go port of the /hv-work worker helpers
// (bin/hv-worker-pool, -reset, -account, -dispatch, -poll, -gate, -session).
// The registry is .hv/workers.json at the project root; its files stay
// byte-identical to what the old helpers write.
package worker

import (
	"context"
	"errors"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/fsio"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// Error is a verb failure with its exit code from the exit table. Data is the
// failure data a verb may attach on exit 1 and 4.
type Error struct {
	Exit    int
	Message string
	Hint    string
	Data    any
}

func (e *Error) Error() string { return e.Message }

func fail(exit int, msg string) *Error { return &Error{Exit: exit, Message: msg} }

// Exit codes, mirrored from internal/cli so this package does not import it.
const (
	ExitFailed      = 1
	ExitUsage       = 2
	ExitResolution  = 3
	ExitRefused     = 4
	ExitUnavailable = 5
	ExitRetry       = 6
)

// RegistryPath is the registry file under the project root.
func RegistryPath(root string) string { return filepath.Join(root, ".hv", "workers.json") }

// Registry is a loaded .hv/workers.json.
type Registry struct {
	Doc    *jsonx.Object
	Exists bool
}

// LoadRegistry reads the registry; a missing or corrupt file reads as
// {"slots": []} with Exists false, like hvlib_io.load_json.
func LoadRegistry(root string) Registry {
	def := jsonx.NewObject()
	def.Set("slots", []any{})
	if o, ok := fsio.LoadJSON(RegistryPath(root), nil).(*jsonx.Object); ok {
		return Registry{Doc: o, Exists: true}
	}
	return Registry{Doc: def}
}

// Slots lists the slot objects of the registry.
func (r Registry) Slots() []*jsonx.Object {
	raw, _ := r.Doc.Get("slots")
	list, _ := raw.([]any)
	var out []*jsonx.Object
	for _, e := range list {
		if o, ok := e.(*jsonx.Object); ok {
			out = append(out, o)
		}
	}
	return out
}

// Slot finds a slot by name.
func (r Registry) Slot(name string) *jsonx.Object {
	for _, s := range r.Slots() {
		if Str(s, "name") == name {
			return s
		}
	}
	return nil
}

// Str reads a string field, "" when absent, null or not a string.
func Str(o *jsonx.Object, key string) string {
	v, _ := o.Get(key)
	s, _ := v.(string)
	return s
}

// Update is a locked read-modify-write of the registry. def is used when the
// file is missing or corrupt, mutate edits the document in place.
func Update(root string, def *jsonx.Object, mutate func(doc *jsonx.Object)) error {
	return fsio.UpdateJSON(RegistryPath(root), def, func(v any) (any, error) {
		doc, ok := v.(*jsonx.Object)
		if !ok {
			doc = def
		}
		mutate(doc)
		return doc, nil
	})
}

// updateSlot edits one slot under the lock, reporting whether it was found.
func updateSlot(root, name string, mutate func(s *jsonx.Object)) (found bool, err error) {
	def := jsonx.NewObject()
	def.Set("slots", []any{})
	err = Update(root, def, func(doc *jsonx.Object) {
		for _, s := range (Registry{Doc: doc}).Slots() {
			if Str(s, "name") == name {
				mutate(s)
				found = true
			}
		}
	})
	return found, err
}

// SlotData is a slot as `data` shows it: null registry fields are absent.
func SlotData(s *jsonx.Object) *jsonx.Object {
	out := jsonx.NewObject()
	for _, k := range s.Keys() {
		v, _ := s.Get(k)
		if v == nil {
			continue
		}
		out.Set(k, v)
	}
	if _, ok := out.Get("relays"); !ok {
		out.Set("relays", []any{})
	}
	return out
}

// GitFunc runs git in dir and returns stdout, stderr and the exit code. A
// non-nil error means git could not run at all.
type GitFunc func(ctx context.Context, dir string, args ...string) (stdout, stderr string, code int, err error)

// gitTimeout bounds one git call.
const gitTimeout = 2 * time.Minute

// ExecGit is the production GitFunc. git is safe to run for real in tests that
// use their own temp repositories; herdr and tmux never go through here.
func ExecGit(ctx context.Context, dir string, args ...string) (string, string, int, error) {
	ctx, cancel := context.WithTimeout(ctx, gitTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Dir = dir
	var out, errb strings.Builder
	cmd.Stdout, cmd.Stderr = &out, &errb
	err := cmd.Run()
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return out.String(), errb.String(), ee.ExitCode(), nil
	}
	return out.String(), errb.String(), 0, err
}

// git runs git and trims one trailing newline from stdout, like $(...).
func (e Env) git(dir string, args ...string) (string, int) {
	out, _, code, err := e.Git(e.context(), dir, args...)
	if err != nil {
		return "", 127
	}
	return strings.TrimRight(out, "\n"), code
}

// Env is what the worker operations touch outside their own memory.
type Env struct {
	// Ctx bounds every git call and is cancelled on SIGINT/SIGTERM by the
	// CLI. Nil means context.Background().
	Ctx context.Context
	Git GitFunc
}

func (e Env) context() context.Context {
	if e.Ctx != nil {
		return e.Ctx
	}
	return context.Background()
}

func (e Env) withDefaults() Env {
	if e.Git == nil {
		e.Git = ExecGit
	}
	return e
}
