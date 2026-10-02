// Package pytest runs the bin/ Python helpers from Go tests, so the Go ports
// can be checked byte-for-byte against the code they replace. Tests skip when
// python3 is not on PATH.
package pytest

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// binDir is the repo's bin/ directory, found from this source file.
func binDir() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(file), "..", "..", "bin")
}

// Run executes a Python snippet with bin/ on PYTHONPATH and returns stdout.
// It fails the test when Python exits non-zero.
func Run(t testing.TB, dir, script string, args ...string) string {
	t.Helper()
	Require(t)
	out, err := Try(dir, script, args...)
	if err != nil {
		t.Fatalf("python3 failed: %v", err)
	}
	return out
}

// Require skips the test when python3 is not on PATH.
func Require(t testing.TB) {
	t.Helper()
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 not on PATH")
	}
}

// Try is Run for snippets that are expected to fail: it returns the error
// (with stderr) instead of failing the test.
func Try(dir, script string, args ...string) (string, error) {
	cmd := exec.Command("python3", append([]string{"-c", script}, args...)...)
	cmd.Dir = dir
	cmd.Env = append(cmd.Environ(), "PYTHONPATH="+binDir())
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return string(out), fmt.Errorf("%w\n%s", err, stderr.String())
	}
	return string(out), nil
}
