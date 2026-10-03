package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// doctorFakes writes fake tools into a fresh dir and points the tool lookup at it.
func doctorFakes(t *testing.T, tools map[string]string) {
	t.Helper()
	dir := t.TempDir()
	for name, body := range tools {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("HV_TEST_DOCTOR_PATH", dir)
}

func doctorData(t *testing.T, out string) (bool, map[string]map[string]any) {
	t.Helper()
	var env struct {
		Data struct {
			OK     bool             `json:"ok"`
			Checks []map[string]any `json:"checks"`
		} `json:"data"`
	}
	if err := json.Unmarshal([]byte(out), &env); err != nil {
		t.Fatalf("%v: %s", err, out)
	}
	byName := map[string]map[string]any{}
	order := ""
	for _, c := range env.Data.Checks {
		byName[c["name"].(string)] = c
		order += c["name"].(string) + ","
	}
	if order != "git,host,tracker,accounts,hook,statusline,stop-hook,hv,codex," {
		t.Errorf("check order %s", order)
	}
	return env.Data.OK, byName
}

func TestDoctorPassesWithoutHv(t *testing.T) {
	// no .hv/: defaults, host skipped; git is a fake that says .worktrees/ is ignored
	doctorFakes(t, map[string]string{"git": `case "$1" in remote) exit 2;; esac; exit 0`})
	dir, _ := filepath.EvalSymlinks(t.TempDir())
	code, out, _ := hvIn(t, dir, "doctor", "--json")
	if code != 0 {
		t.Fatalf("exit %d: %s", code, out)
	}
	ok, c := doctorData(t, out)
	if !ok || c["git"]["status"] != "pass" || c["host"]["status"] != "skip" || c["tracker"]["status"] != "skip" {
		t.Errorf("%v", c)
	}
	if _, has := c["git"]["hint"]; has {
		t.Error("a passing check has no hint")
	}
	var env map[string]any
	json.Unmarshal([]byte(out), &env)
	if _, has := env["data"].(map[string]any)["changed"]; has {
		t.Error("doctor is read-only: no changed")
	}
}

func TestDoctorFailsWithSameData(t *testing.T) {
	// herdr dispatch with an old herdr and no git on PATH
	doctorFakes(t, map[string]string{"herdr": `echo "herdr 0.8.2"`})
	dir, _ := filepath.EvalSymlinks(t.TempDir())
	os.MkdirAll(filepath.Join(dir, ".hv"), 0o755)
	os.WriteFile(filepath.Join(dir, ".hv", "config.json"), []byte(`{"work":{"dispatch":"herdr"}}`), 0o644)
	code, out, _ := hvIn(t, dir, "doctor", "--json")
	if code != 1 {
		t.Fatalf("exit %d, want 1: %s", code, out)
	}
	ok, c := doctorData(t, out)
	if ok || c["git"]["status"] != "fail" || c["host"]["status"] != "fail" {
		t.Fatalf("%v", c)
	}
	if c["host"]["detail"] != "herdr 0.8.2, need 0.9.x" || c["git"]["hint"] == "" {
		t.Errorf("%v", c)
	}
}

func TestDoctorRejectsArgsAndRepo(t *testing.T) {
	dir, _ := filepath.EvalSymlinks(t.TempDir())
	if code, _, _ := hvIn(t, dir, "doctor", "extra"); code != 2 {
		t.Errorf("positional: %d", code)
	}
	if code, _, _ := hvIn(t, dir, "doctor", "--repo", "x"); code != 2 {
		t.Errorf("--repo: %d", code)
	}
}
