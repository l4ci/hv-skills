package roundcfg

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func project(t *testing.T, cfg string) string {
	t.Helper()
	root := t.TempDir()
	os.MkdirAll(filepath.Join(root, ".hv"), 0o755)
	if cfg != "" {
		os.WriteFile(filepath.Join(root, ".hv", "config.json"), []byte(cfg), 0o644)
	}
	return root
}

func TestDefaults(t *testing.T) {
	s, err := Load(project(t, ""))
	if err != nil {
		t.Fatal(err)
	}
	if s.Scope != ScopeMilestone || !reflect.DeepEqual(s.Roster, []string{"ben", "dana", "nia", "kit"}) || s.Brief != "" || len(s.SharedPaths) != 0 {
		t.Fatalf("%+v", s)
	}
}

func TestOverrides(t *testing.T) {
	s, err := Load(project(t, `{"round":{"scope":"slate","roster":["ann","bo"],"brief":"docs/b.md","sharedPaths":["docs/*.md"]}}`))
	if err != nil {
		t.Fatal(err)
	}
	if s.Scope != "slate" || !reflect.DeepEqual(s.Roster, []string{"ann", "bo"}) || s.Brief != "docs/b.md" || !reflect.DeepEqual(s.SharedPaths, []string{"docs/*.md"}) {
		t.Fatalf("%+v", s)
	}
}

func TestInvalid(t *testing.T) {
	for cfg, want := range map[string]string{
		`{"round":{"scope":"all"}}`:      "round.scope",
		`{"round":{"roster":["a","a"]}}`: "twice",
		`{"round":{"roster":["Ann"]}}`:   "branch",
		`{"round":{"roster":["a/b"]}}`:   "branch",
		`{"round":{"roster":[]}}`:        "empty",
		`{"round":{"roster":"ben"}}`:     "list",
		`{"round":{"sharedPaths":[1]}}`:  "list of strings",
	} {
		_, err := Load(project(t, cfg))
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%s: want %q, got %v", cfg, want, err)
		}
	}
}
