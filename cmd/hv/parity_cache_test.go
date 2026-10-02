package main

// Oracle cache for the parity suites (#120). A parity scenario runs the old
// implementation (the shim and the bash/Python helpers) beside the Go binary.
// The old side is frozen and by far the slowest (every helper call starts
// python3, and the fake forge is a python process too), so its result is
// cached on disk: a scenario whose oracle inputs are unchanged replays the
// recorded exit code, output, final .hv/ tree and forge database instead of
// running the old code again. The Go side always runs.
//
// The key covers everything the oracle reads: the sources of the old helpers,
// the shim and the fakes, the python3 version, the day (helpers stamp dates),
// the fixture project (its files and its git refs; fixtures commit at a fixed
// time of day so the hashes repeat), the forge seed and every run's argv and
// environment. A change to any of them is a cache miss, never a stale hit.
//
// HV_PARITY_ORACLE selects the mode: unset or "cache" reads and writes the
// cache; "fresh" runs the old side and refreshes the entry; "off" neither
// reads nor writes. HV_PARITY_CACHE overrides the directory (default
// <user cache dir>/hv-skills/parity-oracle).

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

// oracleMode is "cache", "fresh" or "off".
func oracleMode() string {
	switch m := os.Getenv("HV_PARITY_ORACLE"); m {
	case "fresh", "off":
		return m
	}
	return "cache"
}

func oracleCacheDir() string {
	if d := os.Getenv("HV_PARITY_CACHE"); d != "" {
		return d
	}
	base, err := os.UserCacheDir()
	if err != nil {
		return ""
	}
	return filepath.Join(base, "hv-skills", "parity-oracle")
}

// hashFiles adds the relative path and content of every regular file under
// root (skipping skip) to h, in path order.
func hashFiles(h interface{ Write([]byte) (int, error) }, root string, skip func(rel string, d fs.DirEntry) bool) {
	var files []string
	filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(root, p)
		if rel != "." && skip != nil && skip(rel, d) {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if d.Type().IsRegular() {
			files = append(files, rel)
		} else if d.Type()&fs.ModeSymlink != 0 {
			files = append(files, rel)
		}
		return nil
	})
	sort.Strings(files)
	for _, rel := range files {
		p := filepath.Join(root, rel)
		h.Write([]byte(rel + "\x00"))
		if fi, err := os.Lstat(p); err == nil {
			if fi.Mode()&fs.ModeSymlink != 0 {
				l, _ := os.Readlink(p)
				h.Write([]byte("->" + l))
			} else {
				b, _ := os.ReadFile(p)
				h.Write(b)
				h.Write([]byte{byte(fi.Mode().Perm() >> 6)})
			}
		}
		h.Write([]byte{0})
	}
}

var (
	oracleSrcOnce sync.Once
	oracleSrcSum  string
)

// oracleSources digests everything the old side executes: bin/, the shim
// and its adapters, and the fakes.
func oracleSources() string {
	oracleSrcOnce.Do(func() {
		h := sha256.New()
		for _, d := range []string{"bin", "test/shim", "test/fakes"} {
			h.Write([]byte(d + "\x01"))
			hashFiles(h, filepath.Join(repoDir, d), func(rel string, e fs.DirEntry) bool {
				return e.IsDir() && e.Name() == "__pycache__"
			})
		}
		b, _ := os.ReadFile(shimPath)
		h.Write(b)
		py, _ := exec.Command("python3", "--version").CombinedOutput()
		h.Write(py)
		h.Write([]byte(time.Now().UTC().Format("2006-01-02") + time.Now().Format("2006-01-02")))
		oracleSrcSum = hex.EncodeToString(h.Sum(nil))
	})
	return oracleSrcSum
}

// projectDigest digests a fixture project: its files, and from each git
// repository inside it HEAD, the config and the refs (the index, logs and
// objects carry timestamps or are implied by the refs).
func projectDigest(dir string) string {
	h := sha256.New()
	hashFiles(h, dir, func(rel string, d fs.DirEntry) bool {
		if d.IsDir() && d.Name() == ".git" {
			return true
		}
		return false
	})
	var gits []string
	filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err == nil && d.IsDir() && d.Name() == ".git" {
			gits = append(gits, p)
			return filepath.SkipDir
		}
		return nil
	})
	sort.Strings(gits)
	for _, g := range gits {
		rel, _ := filepath.Rel(dir, g)
		h.Write([]byte("git:" + rel + "\x00"))
		hashFiles(h, g, func(rel string, d fs.DirEntry) bool {
			top := strings.SplitN(rel, string(os.PathSeparator), 2)[0]
			if d.IsDir() {
				return top != "refs"
			}
			return top != "HEAD" && top != "config" && top != "refs" && top != "packed-refs"
		})
	}
	return hex.EncodeToString(h.Sum(nil))
}

// oracleKey hashes the oracle sources and the scenario inputs (any JSON-able
// value, in a fixed order) into a cache key.
func oracleKey(t *testing.T, inputs any) string {
	t.Helper()
	b, err := json.Marshal(inputs)
	if err != nil {
		t.Fatalf("oracle key: %v", err)
	}
	sum := sha256.Sum256(append([]byte(oracleSources()+"\x02"), b...))
	return hex.EncodeToString(sum[:])
}

// oracleLoad reads a cached oracle result into v; false on a miss or when
// the cache is off or being refreshed.
func oracleLoad(key string, v any) bool {
	dir := oracleCacheDir()
	if oracleMode() != "cache" || dir == "" {
		return false
	}
	b, err := os.ReadFile(filepath.Join(dir, key+".json"))
	if err != nil {
		return false
	}
	return json.Unmarshal(b, v) == nil
}

// oracleStore writes a result; a failure to write only costs the next run
// time. A test that already failed does not store: whatever went wrong could
// have shaped the old side's output.
func oracleStore(t *testing.T, key string, v any) {
	t.Helper()
	dir := oracleCacheDir()
	if oracleMode() == "off" || dir == "" || t.Failed() {
		return
	}
	b, err := json.Marshal(v)
	if err != nil || os.MkdirAll(dir, 0o755) != nil {
		return
	}
	tmp, err := os.CreateTemp(dir, ".tmp-*")
	if err != nil {
		return
	}
	_, werr := tmp.Write(b)
	cerr := tmp.Close()
	if werr != nil || cerr != nil || os.Rename(tmp.Name(), filepath.Join(dir, key+".json")) != nil {
		os.Remove(tmp.Name())
	}
}

// pruneOracleCache removes cache entries not written for maxAge, so a cache
// that rolls over with the date (the key includes it) does not grow without
// bound. It touches only the *.json and .tmp-* files of the cache directory.
func pruneOracleCache(maxAge time.Duration) {
	dir := oracleCacheDir()
	if dir == "" {
		return
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		n := e.Name()
		if e.IsDir() || !(strings.HasSuffix(n, ".json") || strings.HasPrefix(n, ".tmp-")) {
			continue
		}
		if fi, err := e.Info(); err == nil && time.Since(fi.ModTime()) > maxAge {
			os.Remove(filepath.Join(dir, n))
		}
	}
}
