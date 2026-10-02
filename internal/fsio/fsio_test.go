package fsio

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/pytest"
)

func counter(v any) int {
	o, ok := v.(*jsonx.Object)
	if !ok {
		return 0
	}
	n, _ := o.Get("n")
	num, ok := n.(json.Number)
	if !ok {
		return 0
	}
	i, _ := strconv.Atoi(string(num))
	return i
}

func bump(v any) (any, error) {
	o, ok := v.(*jsonx.Object)
	if !ok {
		o = jsonx.NewObject()
	}
	o.Set("n", counter(o)+1)
	return o, nil
}

// Concurrent writers each do a read-modify-write under the lock. Any lost
// update leaves the counter short, so the final value proves exclusion.
func TestConcurrentWritersLoseNoUpdates(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	const writers, rounds = 8, 25
	var wg sync.WaitGroup
	errs := make(chan error, writers)
	for range writers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range rounds {
				if err := UpdateJSON(path, nil, bump); err != nil {
					errs <- err
					return
				}
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
	if got := counter(LoadJSON(path, nil)); got != writers*rounds {
		t.Fatalf("counter = %d, want %d", got, writers*rounds)
	}
	if _, err := os.Stat(path + ".tmp"); !os.IsNotExist(err) {
		t.Fatal("tmp file left behind")
	}
}

// Python's hvlib_io.locked and Go's Locked must exclude each other, since
// hv and the old helpers share state files until A9.
func TestLockExcludesPythonWriters(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state.json")
	const pyRounds, goRounds = 40, 40
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		pytest.Run(t, dir, `import sys
from hvlib_io import locked, load_json, dump_json_atomic
p = sys.argv[1]
for _ in range(int(sys.argv[2])):
    with locked(p):
        d = load_json(p, {})
        d["n"] = d.get("n", 0) + 1
        dump_json_atomic(p, d)`, path, strconv.Itoa(pyRounds))
	}()
	for range goRounds {
		if err := UpdateJSON(path, nil, bump); err != nil {
			t.Fatal(err)
		}
	}
	wg.Wait()
	if got := counter(LoadJSON(path, nil)); got != pyRounds+goRounds {
		t.Fatalf("counter = %d, want %d", got, pyRounds+goRounds)
	}
}

func TestLockTimeout(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	held := make(chan struct{})
	release := make(chan struct{})
	go Locked(path, time.Second, func() error { close(held); <-release; return nil })
	<-held
	err := Locked(path, 120*time.Millisecond, func() error { return nil })
	close(release)
	if !errors.Is(err, ErrLockTimeout) {
		t.Fatalf("err = %v, want lock timeout", err)
	}
}

func TestWriteJSONAtomicMatchesPython(t *testing.T) {
	dir := t.TempDir()
	goPath, pyPath := filepath.Join(dir, "go.json"), filepath.Join(dir, "py.json")
	v, _ := jsonx.Decode([]byte(`{"b": [1, {"x": "é"}], "a": {}}`))
	if err := WriteJSONAtomic(goPath, v); err != nil {
		t.Fatal(err)
	}
	pytest.Run(t, dir, `import sys, json
from hvlib_io import dump_json_atomic
dump_json_atomic(sys.argv[1], json.loads('{"b": [1, {"x": "é"}], "a": {}}'))`, pyPath)
	g, _ := os.ReadFile(goPath)
	p, _ := os.ReadFile(pyPath)
	if string(g) != string(p) {
		t.Fatalf("\n--- go\n%s--- python\n%s", g, p)
	}
}

func TestLoadJSONDefaults(t *testing.T) {
	dir := t.TempDir()
	if LoadJSON(filepath.Join(dir, "missing.json"), "d") != "d" {
		t.Fatal("missing file must return default")
	}
	bad := filepath.Join(dir, "bad.json")
	os.WriteFile(bad, []byte("{not json"), 0o644)
	if LoadJSON(bad, "d") != "d" {
		t.Fatal("corrupt file must return default")
	}
}

func TestDirSyncUnsupportedIsNotAFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	orig := dirSync
	t.Cleanup(func() { dirSync = orig })
	for _, errno := range []syscall.Errno{syscall.EINVAL, syscall.ENOTSUP} {
		dirSync = func(*os.File) error { return &os.PathError{Op: "sync", Path: "dir", Err: errno} }
		if err := WriteFileAtomic(path, []byte("x")); err != nil {
			t.Errorf("%v from dir fsync must be ignored, got %v", errno, err)
		}
	}
	dirSync = func(*os.File) error { return &os.PathError{Op: "sync", Path: "dir", Err: syscall.EIO} }
	if err := WriteFileAtomic(path, []byte("y")); !errors.Is(err, syscall.EIO) {
		t.Errorf("EIO from dir fsync must be reported, got %v", err)
	}
	if got, _ := os.ReadFile(path); string(got) != "y" {
		t.Errorf("the rename happened before the dir fsync; file = %q", got)
	}
}

func TestReadTextNormalizesNewlines(t *testing.T) {
	p := filepath.Join(t.TempDir(), "f.md")
	os.WriteFile(p, []byte("a\r\nb\rc\nd\r\r\ne"), 0o666)
	got, err := ReadText(p)
	if err != nil || got != "a\nb\nc\nd\n\ne" {
		t.Errorf("got %q, %v", got, err)
	}
	if _, err := ReadText(filepath.Join(t.TempDir(), "none")); !os.IsNotExist(err) {
		t.Errorf("missing file: %v", err)
	}
}
