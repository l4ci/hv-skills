// Package pytest runs the bin/ Python helpers from Go tests, so the Go ports
// can be checked byte-for-byte against the code they replace. Tests skip when
// python3 is not on PATH.
package pytest

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
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

// JSON runs a Python snippet that reads one JSON document from the file named
// by sys.argv[1] and prints one JSON document, so a test can compare hundreds
// of generated cases in a single interpreter start. in is marshalled with
// encoding/json; the snippet's output is decoded into out.
func JSON(t testing.TB, script string, in, out any) {
	t.Helper()
	Require(t)
	raw, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal oracle input: %v", err)
	}
	path := filepath.Join(t.TempDir(), "in.json")
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	res, err := Try(".", script, path)
	if err != nil {
		t.Fatalf("python3 failed: %v", err)
	}
	if err := json.Unmarshal([]byte(res), out); err != nil {
		t.Fatalf("decode oracle output: %v\n%s", err, res)
	}
}

// Compare checks that got and want, two slices with one result per case,
// agree after a JSON round trip, and reports up to five mismatches with the
// input that produced them. It returns the number of cases compared.
func Compare(t testing.TB, name string, inputs, got, want any) int {
	t.Helper()
	in, g, w := roundTrip(t, inputs), roundTrip(t, got), roundTrip(t, want)
	if len(g) != len(w) || len(g) != len(in) {
		t.Fatalf("%s: %d inputs, %d Go results, %d Python results", name, len(in), len(g), len(w))
	}
	bad := 0
	for i := range g {
		if reflect.DeepEqual(g[i], w[i]) {
			continue
		}
		bad++
		if bad <= 5 {
			t.Errorf("%s case %d\n input:  %s\n go:     %s\n python: %s", name, i, show(in[i]), show(g[i]), show(w[i]))
		}
	}
	if bad > 0 {
		t.Fatalf("%s: %d of %d cases differ from Python", name, bad, len(g))
	}
	return len(g)
}

func roundTrip(t testing.TB, v any) []any {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	var out []any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func show(v any) string {
	raw, _ := json.Marshal(v)
	return string(raw)
}
