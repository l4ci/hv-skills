package update

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestMain is the safety net: hv update must never reach the network from a
// test. Any gh lookup that does not land in test/fakes stops the run.
func TestMain(m *testing.M) {
	wd, _ := os.Getwd()
	fakes, _ := filepath.Abs(filepath.Join(wd, "..", "..", "test", "fakes"))
	os.Setenv("PATH", fakes+string(os.PathListSeparator)+os.Getenv("PATH"))
	os.Unsetenv("HV_TEST_LATEST_VERSION")
	os.Unsetenv("HV_LATEST_VERSION")
	lookPath = func(name string) (string, error) {
		p, err := exec.LookPath(name)
		if err != nil {
			return "", err
		}
		if !strings.HasPrefix(p, fakes+string(os.PathSeparator)) {
			panic("update would exec " + p + " outside test/fakes")
		}
		return p, nil
	}
	os.Exit(m.Run())
}

func TestCompare(t *testing.T) {
	for _, c := range []struct {
		a, b string
		want int
	}{
		{"1.2.3", "1.2.3", 0}, {"1.2.3", "1.2.4", -1}, {"1.10.0", "1.9.9", 1}, {"2", "2.0.0", 0},
		{"v1.2.3", "1.2.3", 0}, {"1.2.3.9", "1.2.3", 0}, {"dev", "0.0.1", -1}, {"dev", "", 0},
		{"1.2.3-rc1", "1.2.3", 0}, {"99999999999999999999.0.0", "1.0.0", 1}, {"5.0.0-dev", "4.9.9", 1},
	} {
		if got := Compare(c.a, c.b); got != c.want {
			t.Errorf("Compare(%q,%q) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func plugin(t *testing.T, dir, version string) {
	t.Helper()
	os.MkdirAll(filepath.Join(dir, ".claude-plugin"), 0o755)
	os.WriteFile(filepath.Join(dir, ".claude-plugin", "plugin.json"), []byte(`{"name": "hv-skills", "version": "`+version+`"}`), 0o644)
}

func env(home string, vars map[string]string, latest string) Env {
	return Env{Getenv: func(k string) string { return vars[k] }, Home: home, ExeDir: filepath.Join(home, "nowhere"), Current: "1.0.0",
		Latest: func() string { return latest }}
}

func TestDetectOverride(t *testing.T) {
	dir := t.TempDir()
	plugin(t, dir, "1.0.0")
	r := Check(env(t.TempDir(), map[string]string{"HV_INSTALL_ROOT": dir}, "1.1.0"))
	if r.InstallType != Override || r.InstallRoot != dir || r.Status != "behind" || r.UpdateCommand != "manual — HV_INSTALL_ROOT was set" {
		t.Errorf("%+v", r)
	}
	// a missing override directory falls through
	r = Check(env(t.TempDir(), map[string]string{"HV_INSTALL_ROOT": filepath.Join(dir, "gone")}, "1.1.0"))
	if r.InstallType != Unknown {
		t.Errorf("%+v", r)
	}
}

func TestDetectPlugin(t *testing.T) {
	home := t.TempDir()
	cpr := t.TempDir()
	plugin(t, cpr, "1.0.0")
	r := Check(env(home, map[string]string{"CLAUDE_PLUGIN_ROOT": cpr}, "1.0.0"))
	if r.InstallType != Plugin || r.InstallRoot != cpr || r.Status != "current" || r.UpdateCommand != "claude plugin update hv-skills" {
		t.Errorf("CLAUDE_PLUGIN_ROOT: %+v", r)
	}
	// another plugin's manifest is not ours
	other := t.TempDir()
	os.MkdirAll(filepath.Join(other, ".claude-plugin"), 0o755)
	os.WriteFile(filepath.Join(other, ".claude-plugin", "plugin.json"), []byte(`{"name": "other"}`), 0o644)
	if r := Check(env(home, map[string]string{"CLAUDE_PLUGIN_ROOT": other}, "1.0.0")); r.InstallType != Unknown {
		t.Errorf("foreign plugin: %+v", r)
	}
	// marketplace layout
	plugin(t, filepath.Join(home, ".claude/plugins/market/hv-skills"), "1.0.0")
	if r := Check(env(home, nil, "1.0.0")); r.InstallType != Plugin || !strings.HasSuffix(r.InstallRoot, "market/hv-skills") {
		t.Errorf("marketplace: %+v", r)
	}
}

func TestDetectPluginCacheNewestWins(t *testing.T) {
	home := t.TempDir()
	cache := filepath.Join(home, ".claude/plugins/cache/hv-skills/hv-skills")
	for _, v := range []string{"4.9.0", "4.10.0", "4.2.0"} {
		plugin(t, filepath.Join(cache, v), v)
	}
	os.MkdirAll(filepath.Join(cache, "9.9.9"), 0o755) // newest, but no manifest
	r := Check(env(home, nil, ""))
	if r.InstallType != Plugin || filepath.Base(r.InstallRoot) != "4.10.0" {
		t.Errorf("%+v", r)
	}
}

func TestDetectStow(t *testing.T) {
	home := t.TempDir()
	plugin(t, filepath.Join(home, ".agents/skills/hv-skills"), "1.0.0")
	r := Check(env(home, nil, "2.0.0"))
	want := filepath.Join(home, ".agents/skills/hv-skills")
	if r.InstallType != Stow || r.InstallRoot != want || r.UpdateCommand != "cd "+want+" && git pull" {
		t.Errorf("agents skills: %+v", r)
	}
	// the skill-symlink walk: ~/.claude/skills/hv-work -> <clone>/hv-work
	home = t.TempDir()
	clone := t.TempDir()
	clone, _ = filepath.EvalSymlinks(clone)
	plugin(t, clone, "1.0.0")
	os.MkdirAll(filepath.Join(clone, "hv-work"), 0o755)
	os.MkdirAll(filepath.Join(home, ".claude/skills"), 0o755)
	if err := os.Symlink(filepath.Join(clone, "hv-work"), filepath.Join(home, ".claude/skills/hv-work")); err != nil {
		t.Fatal(err)
	}
	r = Check(env(home, nil, "2.0.0"))
	if r.InstallType != Stow || r.InstallRoot != clone || r.Status != "behind" {
		t.Errorf("symlink walk: %+v", r)
	}
}

func TestDetectRepoClone(t *testing.T) {
	home := t.TempDir()
	clone := t.TempDir()
	plugin(t, clone, "1.0.0")
	e := env(home, nil, "1.0.0")
	for _, rel := range []string{"", "bin", "bin/deep"} {
		os.MkdirAll(filepath.Join(clone, rel), 0o755)
		e.ExeDir = filepath.Join(clone, rel)
		if r := Check(e); r.InstallType != RepoType || r.InstallRoot != clone || r.UpdateCommand != "cd "+clone+" && git pull" {
			t.Errorf("%q: %+v", rel, r)
		}
	}
}

// With no install root, currentVersion falls back to the binary's stamped
// version (env's Current), so the status still compares.
func TestUnknownInstallUsesStampedVersion(t *testing.T) {
	r := Check(env(t.TempDir(), nil, "1.0.0"))
	if r.InstallType != Unknown || r.InstallRoot != "" || r.CurrentVersion != "1.0.0" || r.Status != "current" ||
		r.UpdateCommand != "reinstall: claude plugin install hv-skills" || r.LatestVersion != "1.0.0" {
		t.Errorf("%+v", r)
	}
}

func TestStatuses(t *testing.T) {
	dir := t.TempDir()
	plugin(t, dir, "1.0.0")
	for latest, want := range map[string]string{"1.1.0": "behind", "1.0.0": "current", "0.9.0": "ahead", "": "unknown"} {
		if r := Check(env(t.TempDir(), map[string]string{"HV_INSTALL_ROOT": dir}, latest)); r.Status != want {
			t.Errorf("latest %q: %s, want %s", latest, r.Status, want)
		}
	}
}

func TestLatestFromTestVariable(t *testing.T) {
	t.Setenv("HV_TEST_LATEST_VERSION", "7.8.9")
	if got := ghLatest(); got != "7.8.9" {
		t.Errorf("ghLatest = %q", got)
	}
}

// With no override, the only gh that may run is the fake, and it answers no
// release: latest stays empty and status unknown, never a network result.
func TestGhLookupStaysInFakes(t *testing.T) {
	p, err := lookPath("gh")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(p, filepath.Join("test", "fakes")) {
		t.Fatalf("gh = %s", p)
	}
	t.Setenv("FAKE_TRACKER_DB", filepath.Join(t.TempDir(), "db.json"))
	if got := ghLatest(); got != "" {
		t.Errorf("fake gh returned release %q", got)
	}
}

func TestGuardRefusesForeignGh(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "gh"), []byte("#!/bin/sh\nexit 0\n"), 0o755)
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	defer func() {
		if recover() == nil {
			t.Error("a gh outside test/fakes was not refused")
		}
	}()
	ghLatest()
}

// currentVersion is the installed plugin's version, not the binary's: a fake
// install at 1.2.0 run by a 4.5.0 binary is behind 1.3.0. A root without a
// readable version gives "" and status unknown, as the old helper did.
func TestCurrentVersionFromInstallRoot(t *testing.T) {
	dir := t.TempDir()
	plugin(t, dir, "1.2.0")
	e := env(t.TempDir(), map[string]string{"HV_INSTALL_ROOT": dir}, "1.3.0")
	e.Current = "4.5.0"
	if r := Check(e); r.CurrentVersion != "1.2.0" || r.Status != "behind" {
		t.Errorf("%+v", r)
	}
	bare := t.TempDir()
	e = env(t.TempDir(), map[string]string{"HV_INSTALL_ROOT": bare}, "1.3.0")
	e.Current = "4.5.0"
	if r := Check(e); r.CurrentVersion != "" || r.Status != "unknown" {
		t.Errorf("no manifest: %+v", r)
	}
}
