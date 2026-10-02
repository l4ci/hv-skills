package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// test/hv-hybrid routes each verb to the Go binary or the shim and can prove,
// afterwards, which one served a phase's verb groups. These tests drive it with
// a fake "Go binary" (a shell script), so no real hv, herdr or tmux is involved.

func fakeGo(t *testing.T, verbs string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "hv")
	script := "#!/bin/sh\nif [ \"$1\" = __verbs ]; then printf '%s' '" + verbs + "'; exit 0; fi\necho GO \"$@\"\n"
	if err := os.WriteFile(p, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

func hybrid(t *testing.T, goBin, log string, extraEnv []string, args ...string) (string, string, int) {
	t.Helper()
	cmd := exec.Command(filepath.Join(repoDir, "test", "hv-hybrid"), args...)
	cmd.Env = append(os.Environ(), "HV_GO_BIN="+goBin, "HV_HYBRID_LOG="+log, "TMPDIR="+t.TempDir(),
		"HV_SHIM_HELPERS="+filepath.Join(repoDir, "bin"))
	cmd.Env = append(cmd.Env, extraEnv...)
	var so, se strings.Builder
	cmd.Stdout, cmd.Stderr = &so, &se
	err := cmd.Run()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	}
	return so.String(), se.String(), code
}

func TestHybridRoutesByTheBinarysVerbList(t *testing.T) {
	goBin := fakeGo(t, "version\nknowledge tier get\nknowledge query\n")
	log := filepath.Join(t.TempDir(), "log")
	out, _, code := hybrid(t, goBin, log, nil, "--json", "-C", "/tmp", "knowledge", "tier", "get", "--topic", "x")
	if code != 0 || !strings.HasPrefix(out, "GO --json -C /tmp knowledge tier get") {
		t.Fatalf("go call: %d %q", code, out)
	}
	hybrid(t, goBin, log, nil, "knowledge", "nosuchverb")
	hybrid(t, goBin, log, nil, "version", "--drift")
	got, _ := os.ReadFile(log)
	want := "go knowledge tier get\nshim knowledge nosuchverb\nshim version\n"
	if string(got) != want {
		t.Errorf("log =\n%s\nwant\n%s", got, want)
	}
}

func TestHybridDiesOnAnUnusableVerbList(t *testing.T) {
	log := filepath.Join(t.TempDir(), "log")
	for name, verbs := range map[string]string{"empty list": "", "no sentinel": "knowledge query\n"} {
		_, errOut, code := hybrid(t, fakeGo(t, verbs), log, nil, "knowledge", "query")
		if code != 70 || !strings.Contains(errOut, "hv-hybrid:") {
			t.Errorf("%s: exit %d %q, want 70", name, code, errOut)
		}
	}
	if b, _ := os.ReadFile(log); len(b) != 0 {
		t.Errorf("a refused call must not be logged as served: %q", b)
	}
	if _, _, code := hybrid(t, filepath.Join(t.TempDir(), "missing"), log, nil, "version"); code != 70 {
		t.Errorf("missing binary: exit %d", code)
	}
}

func TestHybridCheckProvesAPhaseWentThroughGo(t *testing.T) {
	check := func(logText, expect string) (string, int) {
		log := filepath.Join(t.TempDir(), "log")
		if logText != "<unset>" {
			os.WriteFile(log, []byte(logText), 0o644)
		} else {
			log = filepath.Join(t.TempDir(), "absent")
		}
		_, errOut, code := hybrid(t, fakeGo(t, "version\n"), log, []string{"HV_HYBRID_EXPECT=" + expect}, "--check")
		return errOut, code
	}
	if _, code := check("go knowledge query\ngo glossary read\nshim ship body\n", "knowledge,glossary"); code != 0 {
		t.Errorf("all Go: exit %d", code)
	}
	if e, code := check("go knowledge query\nshim knowledge tier get\n", "knowledge"); code != 1 || !strings.Contains(e, "'knowledge tier get' was served by the shim") {
		t.Errorf("a shim call to the group must fail: %d %q", code, e)
	}
	if e, code := check("shim ship body\n", "knowledge"); code != 1 || !strings.Contains(e, "no call to the 'knowledge' group was served by Go") {
		t.Errorf("a run with no Go calls must not pass: %d %q", code, e)
	}
	// an entry may be a verb path: "migrate v4" is Go even though "migrate issues" is not
	if _, code := check("go migrate v4\nshim migrate issues\n", "migrate v4"); code != 0 {
		t.Errorf("verb-path entry: exit %d", code)
	}
	if _, code := check("go migrate v4\nshim migrate issues\n", "migrate"); code != 1 {
		t.Errorf("group entry must see the shim's migrate issues: exit %d", code)
	}
	if _, code := check("", "knowledge"); code != 1 {
		t.Errorf("empty log passed: %d", code)
	}
	if e, code := check("<unset>", "knowledge"); code != 1 || !strings.Contains(e, "unset or unreadable") {
		t.Errorf("missing log: %d %q", code, e)
	}
	if _, code := check("go knowledge query\n", ""); code != 1 {
		t.Errorf("no expected groups must not pass as acceptance: %d", code)
	}
}
