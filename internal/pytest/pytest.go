// Package pytest runs the bin/ Python helpers from Go tests, so the Go ports
// can be checked byte-for-byte against the code they replace.
//
// Parity tests do not need Python by default. They go through Golden (or
// GoldenJSON), which reads the recorded Python outputs from
// testdata/golden/<test>.json in the test's package and compares Go against
// them; the file also records the inputs, and the test fails when the Go
// generator's inputs differ from the recorded ones. That keeps the oracle
// after bin/ is gone.
//
// To refresh the goldens (after changing a generator, a script or the Python
// helpers), run testdata/regen-golden.sh from anywhere. It runs the golden
// tests of every package with -update-golden, which executes Python and
// rewrites the files; review the diff before committing. Run, Try, Require and
// JSON stay live and skip when python3 is not on PATH; the lock tests, which
// test Python's behaviour itself, use them.
package pytest

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"testing"
)

var update = flag.Bool("update-golden", false, "run Python and rewrite testdata/golden (see internal/pytest)")

var goldenSeq sync.Map // test name -> calls so far, so a test can record more than one golden

// goldenPath is testdata/golden/<test name>[-N].json relative to the test's
// package directory, the working directory of go test.
func goldenPath(t testing.TB) string {
	name := strings.NewReplacer("/", "__", " ", "_").Replace(t.Name())
	n, _ := goldenSeq.LoadOrStore(t.Name(), new(int))
	p := n.(*int)
	*p++
	if *p > 1 {
		name += "-" + strconv.Itoa(*p)
	}
	t.Cleanup(func() { goldenSeq.Delete(t.Name()) })
	return filepath.Join("testdata", "golden", name+".json")
}

type golden struct {
	Inputs  json.RawMessage `json:"inputs"`
	Outputs json.RawMessage `json:"outputs"`
}

func marshal(t testing.TB, v any) []byte {
	t.Helper()
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		t.Fatalf("marshal golden: %v", err)
	}
	return bytes.TrimRight(buf.Bytes(), "\n")
}

// Golden is the golden-file form of a Python oracle. inputs describes what
// the Python side was asked; out is a pointer that live fills in by running
// Python.
//
// Normally Golden loads testdata/golden/<test>.json, fails when its recorded
// inputs differ from inputs, and decodes the recorded outputs into out. With
// -update-golden it calls live (which needs python3), then records inputs and
// out.
func Golden(t testing.TB, inputs, out any, live func()) {
	t.Helper()
	path := goldenPath(t)
	if *update {
		Require(t)
		live()
		raw := marshal(t, map[string]any{"inputs": inputs, "outputs": out})
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, append(raw, '\n'), 0o644); err != nil {
			t.Fatal(err)
		}
		t.Logf("wrote %s (%d bytes)", path, len(raw)+1)
		return
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("no golden %s (%v); run internal/pytest/testdata/regen-golden.sh", path, err)
	}
	var g golden
	if err := json.Unmarshal(raw, &g); err != nil {
		t.Fatalf("%s: %v", path, err)
	}
	var have, want any
	if err := json.Unmarshal(marshal(t, inputs), &have); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(g.Inputs, &want); err != nil {
		t.Fatalf("%s: %v", path, err)
	}
	if !reflect.DeepEqual(have, want) {
		t.Fatalf("%s: the test's inputs differ from the recorded ones; run internal/pytest/testdata/regen-golden.sh", path)
	}
	if err := json.Unmarshal(g.Outputs, out); err != nil {
		t.Fatalf("%s: decode outputs: %v", path, err)
	}
}

// GoldenJSON is JSON through a golden file: Python runs script over in only
// with -update-golden; otherwise out is read from the golden. The script is
// recorded with the input, so editing it demands a regeneration.
func GoldenJSON(t testing.TB, script string, in, out any) {
	t.Helper()
	Golden(t, map[string]any{"script": script, "input": in}, out, func() { JSON(t, script, in, out) })
}

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
