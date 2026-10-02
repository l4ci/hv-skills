// Package pytest runs the bin/ Python helpers from Go tests, so the Go ports
// can be checked byte-for-byte against the code they replace. Tests skip when
// python3 is not on PATH.
package pytest

import (
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// BinDir is the repo's bin/ directory, found from this source file.
func BinDir(t testing.TB) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("pytest: cannot locate source file")
	}
	return filepath.Join(filepath.Dir(file), "..", "..", "bin")
}

// Run executes a Python snippet with bin/ on PYTHONPATH and returns stdout.
func Run(t testing.TB, dir, script string, args ...string) string {
	t.Helper()
	py, err := exec.LookPath("python3")
	if err != nil {
		t.Skip("python3 not on PATH")
	}
	cmd := exec.Command(py, append([]string{"-c", script}, args...)...)
	cmd.Dir = dir
	cmd.Env = append(cmd.Environ(), "PYTHONPATH="+BinDir(t))
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 failed: %v\n%s", err, stderr.String())
	}
	return string(out)
}
