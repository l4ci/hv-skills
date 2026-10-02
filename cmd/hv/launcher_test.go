package main

// Tests for bin/hv, the plugin launcher. A fake plugin root and a local
// file:// "release" stand in for GitHub, so nothing touches the network.

import (
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
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
	cmd := exec.Command(launcher, args...)
	cmd.Env = append(os.Environ(), "HV_LAUNCHER_MODE=release", "HV_CACHE_DIR="+p.cache,
		"HV_RELEASE_BASE_URL=file://"+filepath.Dir(p.releases), "HV_BINARY=")
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
	if entries, _ := os.ReadDir(filepath.Join(p.cache, "9.9.9")); len(entries) != 0 {
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

// Dev mode on this checkout: the launcher builds from source and stamps
// <plugin version>-dev.
func TestLauncherDevBuild(t *testing.T) {
	cache := t.TempDir()
	cmd := exec.Command(filepath.Join(repoRoot(t), "bin", "hv"), "version")
	cmd.Env = append(os.Environ(), "HV_LAUNCHER_MODE=dev", "HV_CACHE_DIR="+cache, "HV_BINARY=")
	out, err := cmd.CombinedOutput()
	if err != nil || !strings.HasPrefix(string(out), "hv ") || !strings.Contains(string(out), "-dev") {
		t.Fatalf("dev build: err=%v out=%q", err, out)
	}
}
