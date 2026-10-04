package config

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/l4ci/hv/v5/internal/jsonx"
)

func requiredNames() []string {
	var out []string
	for _, k := range Keys {
		if k.Required {
			out = append(out, k.Name)
		}
	}
	return out
}

func TestFillCreatesMissingFileInSchemaOrder(t *testing.T) {
	root := project(t, "", "")
	filled, err := Fill(root)
	if err != nil || !reflect.DeepEqual(filled, requiredNames()) {
		t.Fatalf("filled %v, err %v", filled, err)
	}
	want, _ := jsonx.Marshal(fullConfig())
	if got := read(t, root); got != string(want)+"\n" {
		t.Errorf("file:\n%s", got)
	}
	if st, _ := Check(root); st != UpToDate {
		t.Errorf("check after fill: %s", st)
	}
}

// The seed hv init writes (issues-only keys in schema order) filled out is
// byte-identical to a full config written in schema order (G7).
func TestFillCompletesTheSeedInSchemaOrder(t *testing.T) {
	seed := `{"issues": {"providers": {"github": true, "gitlab": true}, "label": "in-progress", "autoCreateLabel": true, "filterMineOnly": false}}`
	root := project(t, seed, "")
	filled, err := Fill(root)
	if err != nil || len(filled) != len(requiredNames())-2 {
		t.Fatalf("filled %v, err %v", filled, err)
	}
	full := fullConfig()
	issues, _ := getObject(full, "issues")
	issues.Set("label", "in-progress")
	issues.Set("autoCreateLabel", true)
	issues.Set("filterMineOnly", false)
	want, _ := jsonx.Marshal(full)
	if got := read(t, root); got != string(want)+"\n" {
		t.Errorf("file:\n%s\nwant:\n%s", got, want)
	}
}

func TestFillKeepsPresentAndUnknownKeys(t *testing.T) {
	cfg := `{"zzz": 1, "work": {"custom": "x", "dispatch": "herdr"}, "models": {"worker": "haiku"}, "umbrella": {"enabled": null}, "hvSkills": "scalar"}`
	root := project(t, cfg, `{"models": {"orchestrator": "local"}}`)
	if _, err := Fill(root); err != nil {
		t.Fatal(err)
	}
	doc, _ := jsonx.Decode([]byte(read(t, root)))
	o := doc.(*jsonx.Object)
	// present keys keep their order; added ones go before the first later sibling
	want := []string{"zzz", "work", "models", "refactor", "learn", "ship", "qa", "autonomy", "debug", "docs", "git", "umbrella", "issues", "hvSkills"}
	if got := o.Keys(); !reflect.DeepEqual(got, want) {
		t.Errorf("top keys %v", got)
	}
	models, _ := getObject(o, "models")
	if !reflect.DeepEqual(models.Keys(), []string{"orchestrator", "worker"}) {
		t.Errorf("models keys %v", models.Keys())
	}
	if v, _ := Value(o, "models.worker"); v != "haiku" {
		t.Errorf("present key overwritten: %v", v)
	}
	if v, _ := Value(o, "models.orchestrator"); v != "opus" {
		t.Errorf("local layer leaked into config.json: %v", v)
	}
	work, _ := getObject(o, "work")
	if k := work.Keys(); !reflect.DeepEqual(k, []string{"custom", "isolation", "mergeStrategy", "dispatch", "workerSlots", "workerCommand", "accounts", "operatorCommand"}) {
		t.Errorf("work keys %v", k)
	}
	if v, _ := Value(o, "work.dispatch"); v != "herdr" {
		t.Errorf("dispatch %v", v)
	}
	// null and a scalar in the way are replaced in place
	if v, _ := Value(o, "umbrella.enabled"); v != false {
		t.Errorf("umbrella.enabled %v", v)
	}
	if v, _ := Value(o, "hvSkills.version"); v != "" {
		t.Errorf("hvSkills.version %v", v)
	}
	if st, m := Check(root); st != UpToDate {
		t.Errorf("check: %s %v", st, m)
	}
}

func TestFillNothingMissingDoesNotRewrite(t *testing.T) {
	full, _ := jsonx.MarshalCompact(fullConfig())
	root := project(t, string(full), "")
	filled, err := Fill(root)
	if err != nil || filled == nil || len(filled) != 0 {
		t.Fatalf("filled %v, err %v", filled, err)
	}
	if got := read(t, root); got != string(full) {
		t.Errorf("file rewritten:\n%s", got)
	}
}

func TestFillRefusesCorrupt(t *testing.T) {
	for _, body := range []string{"{oops", "[1]", "null", "", "\xff{}"} {
		root := project(t, "", "")
		p := filepath.Join(root, ".hv", "config.json")
		os.WriteFile(p, []byte(body), 0o644)
		if _, err := Fill(root); !errors.Is(err, ErrCorrupt) {
			t.Errorf("%q: %v", body, err)
		}
		if b, _ := os.ReadFile(p); string(b) != body {
			t.Errorf("%q: file changed to %q", body, b)
		}
	}
}
