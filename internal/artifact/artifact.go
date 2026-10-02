// Package artifact holds what the A6 file-mode verbs (milestone, plan,
// design, spike, proof, debug counter) share: the exit-coded error their
// packages return. It does not import internal/cli; internal/cli's A6 glue
// maps Error to the exit table.
package artifact

import (
	"fmt"
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
