package main

// Tests for bin/hv, the plugin launcher. A fake plugin root and a local
// file:// "release" stand in for GitHub, so nothing touches the network.

import (
	"crypto/sha256"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	return root
}

type plugin struct {
	launcher, releases, cache string
	asset                     string
}

// newPlugin lays out <tmp>/plugin/{bin/hv,.claude-plugin/plugin.json} at
// version 9.9.9 and a release dir holding a real hv build for this platform.
func newPlugin(t *testing.T) plugin {
	t.Helper()
	if _, err := exec.LookPath("curl"); err != nil {
		if _, err := exec.LookPath("wget"); err != nil {
			t.Skip("needs curl or wget")
		}
	}
	tmp := t.TempDir()
	p := plugin{
		launcher: filepath.Join(tmp, "plugin", "bin", "hv"),
		releases: filepath.Join(tmp, "releases", "v9.9.9"),
		cache:    filepath.Join(tmp, "cache"),
		asset:    fmt.Sprintf("hv_%s_%s", runtime.GOOS, runtime.GOARCH),
	}
	src, err := os.ReadFile(filepath.Join(repoRoot(t), "bin", "hv"))
	if err != nil {
		t.Fatal(err)
	}
	must(t, os.MkdirAll(filepath.Dir(p.launcher), 0o755))
	must(t, os.WriteFile(p.launcher, src, 0o755))
	must(t, os.MkdirAll(filepath.Join(tmp, "plugin", ".claude-plugin"), 0o755))
	must(t, os.WriteFile(filepath.Join(tmp, "plugin", ".claude-plugin", "plugin.json"),
		[]byte("{\n  \"name\": \"hv-skills\",\n  \"version\": \"9.9.9\"\n}\n"), 0o644))
	must(t, os.MkdirAll(p.releases, 0o755))
	bin := filepath.Join(p.releases, p.asset)
	build := exec.Command("go", "build", "-o", bin,
		"-ldflags", "-X github.com/l4ci/hv-skills/v5/internal/version.Version=9.9.9", ".")
	build.Dir = filepath.Join(repoRoot(t), "cmd", "hv")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("go build: %v\n%s", err, out)
	}
	p.writeSums(t, "")
	return p
}

// writeSums writes checksums.txt; a non-empty override replaces the real sum.
func (p plugin) writeSums(t *testing.T, override string) {
	data, err := os.ReadFile(filepath.Join(p.releases, p.asset))
	must(t, err)
	sum := fmt.Sprintf("%x", sha256.Sum256(data))
	if override != "" {
		sum = override
	}
	must(t, os.WriteFile(filepath.Join(p.releases, "checksums.txt"),
		[]byte(fmt.Sprintf("%s  hv_other_arch\n%s  %s\n", strings.Repeat("0", 64), sum, p.asset)), 0o644))
}

func (p plugin) run(t *testing.T, launcher string, args ...string) (int, string, string) {
	t.Helper()
	return runEnv(t, env(map[string]string{"HV_LAUNCHER_MODE": "release", "HV_CACHE_DIR": p.cache,
		"HV_RELEASE_BASE_URL": "file://" + filepath.Dir(p.releases)}), launcher, args...)
}

// env is os.Environ with HV_* cleared and then the given values; an empty
// value drops the variable instead.
func env(set map[string]string) []string {
	var out []string
	for _, kv := range os.Environ() {
		k, _, _ := strings.Cut(kv, "=")
		if _, override := set[k]; override || strings.HasPrefix(k, "HV_") {
			continue
		}
		out = append(out, kv)
	}
	for k, v := range set {
		if v != "" {
			out = append(out, k+"="+v)
		}
	}
	return out
}

func runEnv(t *testing.T, environ []string, launcher string, args ...string) (int, string, string) {
	t.Helper()
	cmd := exec.Command(launcher, args...)
	cmd.Env = environ
	var so, se strings.Builder
	cmd.Stdout, cmd.Stderr = &so, &se
	err := cmd.Run()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if err != nil {
		t.Fatal(err)
	}
	return code, so.String(), se.String()
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func TestLauncherDownloadsVerifiesAndCaches(t *testing.T) {
	p := newPlugin(t)
	code, out, errOut := p.run(t, p.launcher, "version")
	if code != 0 || out != "hv 9.9.9\n" {
		t.Fatalf("first run: code=%d out=%q err=%q", code, out, errOut)
	}
	cached := filepath.Join(p.cache, "9.9.9", runtime.GOOS+"-"+runtime.GOARCH, "hv")
	if _, err := os.Stat(cached); err != nil {
		t.Fatalf("binary not cached per os-arch: %v", err)
	}
	if !strings.Contains(errOut, "downloading "+p.asset+" v9.9.9") {
		t.Fatalf("first run should report the download, stderr=%q", errOut)
	}
	must(t, os.RemoveAll(p.releases)) // cached now: no second download
	code, out, errOut = p.run(t, p.launcher, "--json", "version")
	if code != 0 || !strings.HasPrefix(out, `{"ok": true, "data": {"version": "9.9.9"`) || errOut != "" {
		t.Fatalf("cached run: code=%d out=%q err=%q", code, out, errOut)
	}
}

func TestLauncherPassesExitCodes(t *testing.T) {
	p := newPlugin(t)
	if code, _, errOut := p.run(t, p.launcher, "no-such-verb"); code != 2 || !strings.Contains(errOut, `unknown command "no-such-verb"`) {
		t.Fatalf("code=%d err=%q", code, errOut)
	}
}

func TestLauncherRejectsBadChecksum(t *testing.T) {
	p := newPlugin(t)
	p.writeSums(t, strings.Repeat("f", 64))
	code, out, errOut := p.run(t, p.launcher, "version", "--json")
	if code != 5 || !strings.Contains(errOut, "checksum mismatch for "+p.asset) {
		t.Fatalf("code=%d err=%q", code, errOut)
	}
	if !strings.HasPrefix(out, `{"ok": false, "error": {"code": "unavailable", "exit": 5, "message": "checksum mismatch`) {
		t.Fatalf("--json failure envelope: %q", out)
	}
	if entries, _ := os.ReadDir(filepath.Join(p.cache, "9.9.9", runtime.GOOS+"-"+runtime.GOARCH)); len(entries) != 0 {
		t.Fatalf("a rejected binary must leave nothing in the cache, found %v", entries)
	}
}

func TestLauncherMissingRelease(t *testing.T) {
	p := newPlugin(t)
	must(t, os.RemoveAll(p.releases))
	if code, _, errOut := p.run(t, p.launcher, "version"); code != 5 || !strings.Contains(errOut, "download failed") {
		t.Fatalf("code=%d err=%q", code, errOut)
	}
}

func TestLauncherFollowsSymlink(t *testing.T) {
	p := newPlugin(t)
	link := filepath.Join(t.TempDir(), "hv")
	must(t, os.Symlink(p.launcher, link))
	if code, out, errOut := p.run(t, link, "version"); code != 0 || out != "hv 9.9.9\n" {
		t.Fatalf("code=%d out=%q err=%q", code, out, errOut)
	}
}

func TestLauncherNoChecksumEntry(t *testing.T) {
	p := newPlugin(t)
	must(t, os.WriteFile(filepath.Join(p.releases, "checksums.txt"),
		[]byte(strings.Repeat("0", 64)+"  hv_other_arch\n"), 0o644))
	code, _, errOut := p.run(t, p.launcher, "version")
	if code != 5 || !strings.Contains(errOut, "checksums.txt has no entry for "+p.asset) {
		t.Fatalf("code=%d err=%q", code, errOut)
	}
}

// Parallel first runs race on the same cache dir; each must still exec a
// complete, verified binary.
func TestLauncherConcurrentColdStarts(t *testing.T) {
	p := newPlugin(t)
	var wg sync.WaitGroup
	results := make([]string, 8)
	for i := range results {
		wg.Add(1)
		go func() {
			defer wg.Done()
			code, out, errOut := p.run(t, p.launcher, "version")
			results[i] = fmt.Sprintf("code=%d out=%q err=%q", code, out, errOut)
			if code == 0 && out == "hv 9.9.9\n" {
				results[i] = ""
			}
		}()
	}
	wg.Wait()
	for i, r := range results {
		if r != "" {
			t.Errorf("launch %d: %s", i, r)
		}
	}
	leftovers, _ := filepath.Glob(filepath.Join(p.cache, "9.9.9", "*", ".*"))
	if len(leftovers) != 0 {
		t.Errorf("temp files left in the cache: %v", leftovers)
	}
}

func TestLauncherWithoutHome(t *testing.T) {
	p := newPlugin(t)
	code, out, errOut := runEnv(t, env(map[string]string{"HOME": "", "XDG_CACHE_HOME": "", "HV_LAUNCHER_MODE": "release"}),
		p.launcher, "version", "--json")
	if code != 5 || !strings.Contains(errOut, "HOME is not set") || !strings.Contains(errOut, "hint: set HV_CACHE_DIR") {
		t.Fatalf("code=%d err=%q", code, errOut)
	}
	if !strings.HasPrefix(out, `{"ok": false, "error": {"code": "unavailable", "exit": 5`) {
		t.Fatalf("envelope: %q", out)
	}
}

func TestLauncherReleaseURLSchemes(t *testing.T) {
	p := newPlugin(t)
	srv := httptest.NewServer(http.FileServer(http.Dir(filepath.Dir(p.releases))))
	defer srv.Close()
	base := env(map[string]string{"HV_LAUNCHER_MODE": "release", "HV_CACHE_DIR": p.cache})
	if code, out, errOut := runEnv(t, append(base, "HV_RELEASE_BASE_URL="+srv.URL), p.launcher, "version"); code != 0 || out != "hv 9.9.9\n" {
		t.Fatalf("http on 127.0.0.1 must be allowed: code=%d out=%q err=%q", code, out, errOut)
	}
	must(t, os.RemoveAll(p.cache))
	local := strings.Replace(srv.URL, "127.0.0.1", "localhost", 1) + "/"
	if code, out, errOut := runEnv(t, append(base, "HV_RELEASE_BASE_URL="+local), p.launcher, "version"); code != 0 || out != "hv 9.9.9\n" {
		t.Fatalf("http on localhost:<port>/ must be allowed: code=%d out=%q err=%q", code, out, errOut)
	}
	for _, url := range []string{"http://example.com/releases", "ftp://127.0.0.1/x", "http://127.0.0.1.evil.example/x",
		"http://localhost:1@evil.example/x", "http://127.0.0.1@evil.example", "https://user@github.com/x",
		"http://localhost:/x", "http://localhost:80x/x", "http://localhostevil.example/x"} {
		must(t, os.RemoveAll(p.cache))
		code, _, errOut := runEnv(t, append(base, "HV_RELEASE_BASE_URL="+url), p.launcher, "version")
		if code != 5 || !strings.Contains(errOut, "refusing release URL") {
			t.Errorf("%s: code=%d err=%q", url, code, errOut)
		}
	}
}

func TestLauncherBadMode(t *testing.T) {
	p := newPlugin(t)
	code, _, errOut := runEnv(t, env(map[string]string{"HV_LAUNCHER_MODE": "auto", "HV_CACHE_DIR": p.cache}), p.launcher, "version")
	if code != 5 || !strings.Contains(errOut, "must be dev or release") {
		t.Fatalf("code=%d err=%q", code, errOut)
	}
}

// devCheckout copies the Go sources and launcher into a temp checkout, so
// the dev tests can touch plugin.json without editing the real repo.
func devCheckout(t *testing.T) string {
	t.Helper()
	dst := t.TempDir()
	src := repoRoot(t)
	for _, rel := range []string{"go.mod", "cmd", "internal", "bin/hv", ".claude-plugin/plugin.json"} {
		cp := exec.Command("cp", "-R", filepath.Join(src, rel), filepath.Join(dst, rel))
		must(t, os.MkdirAll(filepath.Dir(filepath.Join(dst, rel)), 0o755))
		if out, err := cp.CombinedOutput(); err != nil {
			t.Fatalf("cp %s: %v %s", rel, err, out)
		}
	}
	return dst
}

func TestLauncherDevBuild(t *testing.T) {
	root := devCheckout(t)
	e := env(map[string]string{"HV_LAUNCHER_MODE": "dev", "HV_CACHE_DIR": t.TempDir()})
	code, out, errOut := runEnv(t, e, filepath.Join(root, "bin", "hv"), "version")
	if code != 0 || !strings.HasPrefix(out, "hv ") || !strings.Contains(out, "-dev") {
		t.Fatalf("dev build: code=%d out=%q err=%q", code, out, errOut)
	}
	// A plugin.json bump must rebuild, or the -dev stamp goes stale.
	time.Sleep(1100 * time.Millisecond) // find -newer compares mtimes in seconds on some filesystems
	must(t, os.WriteFile(filepath.Join(root, ".claude-plugin", "plugin.json"), []byte("{\n  \"version\": \"7.7.7\"\n}\n"), 0o644))
	code, out, errOut = runEnv(t, e, filepath.Join(root, "bin", "hv"), "version")
	if code != 0 || !strings.HasPrefix(out, "hv 7.7.7-dev") {
		t.Fatalf("after plugin.json bump: code=%d out=%q err=%q", code, out, errOut)
	}
}

func TestLauncherDevConcurrentColdStarts(t *testing.T) {
	root := devCheckout(t)
	e := env(map[string]string{"HV_LAUNCHER_MODE": "dev", "HV_CACHE_DIR": t.TempDir()})
	var wg sync.WaitGroup
	errs := make(chan string, 8)
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			code, out, errOut := runEnv(t, e, filepath.Join(root, "bin", "hv"), "version")
			if code != 0 || !strings.Contains(out, "-dev") {
				errs <- fmt.Sprintf("code=%d out=%q err=%q", code, out, errOut)
			}
		}()
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Error(e)
	}
}
