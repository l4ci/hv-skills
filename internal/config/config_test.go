package config

import (
	"os"
	"path/filepath"
	"strings"
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
		if c.Name() == "golden" { // the recorded Python outputs, not a fixture
			continue
		}
		t.Run(c.Name(), func(t *testing.T) {
			path, _ := filepath.Abs(filepath.Join("testdata", c.Name(), "config.json"))
			got, err := jsonx.Marshal(Load(path))
			if err != nil {
				t.Fatal(err)
			}
			files := map[string]string{}
			for _, n := range []string{"config.json", "config.local.json"} {
				if raw, err := os.ReadFile(filepath.Join("testdata", c.Name(), n)); err == nil {
					files[n] = string(raw)
				}
			}
			var want string
			pytest.Golden(t, map[string]any{"script": pyLoad, "files": files}, &want, func() { want = pytest.Run(t, ".", pyLoad, path) })
			if string(got) != want {
				t.Fatalf("\n--- go\n%s\n--- python\n%s", got, want)
			}
		})
	}
}

// Divergences from Python, kept on purpose and listed in the conventions doc
// (Config). The test also runs Python, so the doc stays true if Python changes.
func TestDivergentInputs(t *testing.T) {
	t.Run("NaN and Infinity", func(t *testing.T) {
		path, _ := filepath.Abs("divergent/nan/config.json")
		// Go: not valid JSON, so the file counts as absent.
		if got, _ := jsonx.MarshalCompact(Load(path)); string(got) != "{}" {
			t.Fatalf("Go Load = %s, want {}", got)
		}
		// Python: json.loads accepts NaN and Infinity.
		if py := pytest.Run(t, ".", pyLoad, path); !strings.Contains(py, "NaN") {
			t.Fatalf("Python no longer loads NaN; update the doc. Got %s", py)
		}
	})
	t.Run("invalid UTF-8", func(t *testing.T) {
		path, _ := filepath.Abs("divergent/badutf8/config.json")
		// Go: loads, with U+FFFD for the bad byte.
		v, ok := Lookup(Load(path), "work.dispatch")
		if !ok || v != "tm\uFFFDux" {
			t.Fatalf("Go Load work.dispatch = %q", v)
		}
		pytest.Require(t)
		// Python: read_text raises UnicodeDecodeError, which load_json does not catch.
		if _, err := pytest.Try(".", pyLoad, path); err == nil {
			t.Fatal("Python no longer fails on invalid UTF-8; update the doc")
		}
	})
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
