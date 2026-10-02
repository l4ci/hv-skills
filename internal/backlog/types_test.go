package backlog

import (
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/pytest"
)

// Types must stay the registry line of bin/hv-types.sh, which bash and
// hvlib_types.py both derive from.
func TestTypesMatchRegistry(t *testing.T) {
	raw, err := os.ReadFile("../../bin/hv-types.sh")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^HV_TYPE_REGISTRY="([^"]*)"`).FindSubmatch(raw)
	if m == nil {
		t.Fatal("no HV_TYPE_REGISTRY line in bin/hv-types.sh")
	}
	rows := strings.Fields(string(m[1]))
	if len(rows) != len(Types) {
		t.Fatalf("registry has %d rows, Types has %d", len(rows), len(Types))
	}
	var letters string
	var sections []string
	for i, row := range rows {
		p := strings.Split(row, ":")
		if len(p) != 4 {
			t.Fatalf("malformed row %q", row)
		}
		want := Type{p[0], p[1], p[2], strings.Contains(p[3], "C"), strings.Contains(p[3], "P")}
		if Types[i] != want {
			t.Errorf("row %d: Types has %+v, registry says %+v", i, Types[i], want)
		}
		if p[1] != "" {
			letters += p[0]
			sections = append(sections, p[1])
		}
	}
	if letters != ItemLetters {
		t.Errorf("ItemLetters = %q, registry gives %q", ItemLetters, letters)
	}
	if strings.Join(sections, ",") != strings.Join(OpenSections, ",") {
		t.Errorf("OpenSections = %v, registry gives %v", OpenSections, sections)
	}
}

func TestTypesMatchPython(t *testing.T) {
	var want map[string]any
	pytest.JSON(t, `import json
import hvlib_types as h
print(json.dumps({"items": h.ITEM_TYPES, "open": h.OPEN_SECTIONS, "countable": h.COUNTABLE_TYPES,
  "plannable": h.PLANNABLE_TYPES, "dir": h.DIR_FOR_PREFIX, "section": h.SECTION_FOR_DIR}))`, nil, &want)
	var countable, plannable string
	dirs, sections := map[string]any{}, map[string]any{}
	for _, ty := range Types {
		if ty.Countable {
			countable += ty.Letter
		}
		if ty.Plannable {
			plannable += ty.Letter
		}
		if ty.Kind != "" {
			dirs[ty.Letter], sections[ty.Kind] = ty.Kind, ty.Section
		}
	}
	got := map[string]any{"items": ItemLetters, "countable": countable, "plannable": plannable, "dir": dirs, "section": sections}
	for k, g := range got {
		if !sameJSON(g, want[k]) {
			t.Errorf("%s: Go %v, Python %v", k, g, want[k])
		}
	}
}

func TestTypeLookups(t *testing.T) {
	if ty, ok := TypeByLetter("F"); !ok || ty.Kind != "features" {
		t.Fatalf("TypeByLetter(F) = %+v, %v", ty, ok)
	}
	if ty, ok := TypeByKind("bugs"); !ok || ty.Letter != "B" {
		t.Fatalf("TypeByKind(bugs) = %+v, %v", ty, ok)
	}
	if _, ok := TypeByKind(""); ok {
		t.Fatal("TypeByKind(\"\") must not match the Slice row")
	}
	if _, ok := TypeByLetter("X"); ok {
		t.Fatal("unknown letter matched")
	}
}
