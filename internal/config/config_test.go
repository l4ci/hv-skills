package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/pytest"
)

const pyLoad = `import json, sys
from hvlib_io import load_config
print(json.dumps(load_config(sys.argv[1]), indent=2), end="")`

// Each testdata/<case>/ directory is a shared fixture: Go's Load and
// Python's hvlib_io.load_config must produce byte-identical JSON.
func TestLoadMatchesPython(t *testing.T) {
	cases, err := os.ReadDir("testdata")
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		t.Run(c.Name(), func(t *testing.T) {
			path, _ := filepath.Abs(filepath.Join("testdata", c.Name(), "config.json"))
			got, err := jsonx.Marshal(Load(path))
			if err != nil {
				t.Fatal(err)
			}
			want := pytest.Run(t, ".", pyLoad, path)
			if string(got) != want {
				t.Fatalf("\n--- go\n%s\n--- python\n%s", got, want)
			}
		})
	}
}

func TestMergeDoesNotMutateInputs(t *testing.T) {
	base, _ := jsonx.Decode([]byte(`{"a": {"b": 1}}`))
	over, _ := jsonx.Decode([]byte(`{"a": {"c": 2}}`))
	Merge(base, over)
	got, _ := jsonx.MarshalCompact(base)
	if string(got) != `{"a": {"b": 1}}` {
		t.Fatalf("base changed: %s", got)
	}
}

func TestLookup(t *testing.T) {
	cfg, _ := jsonx.Decode([]byte(`{"work": {"mergeStrategy": "pr"}, "x": 1}`))
	if v, ok := Lookup(cfg, "work.mergeStrategy"); !ok || v != "pr" {
		t.Fatalf("got %v %v", v, ok)
	}
	for _, k := range []string{"work.missing", "x.y", "nope"} {
		if _, ok := Lookup(cfg, k); ok {
			t.Errorf("Lookup(%q) should miss", k)
		}
	}
}
