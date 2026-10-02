package artifact

import (
	"reflect"
	"testing"
)

func TestParseFrontmatter(t *testing.T) {
	fm, order, body := ParseFrontmatter("---\nname: x\n# c\ndepends: [a, b,]\nempty: []\n---\n\nbody\n")
	if Str(fm, "name") != "x" || !reflect.DeepEqual(fm["depends"], []string{"a", "b"}) || !reflect.DeepEqual(fm["empty"], []string{}) {
		t.Fatalf("fm = %#v", fm)
	}
	if !reflect.DeepEqual(order, []string{"name", "depends", "empty"}) || body != "body\n" {
		t.Fatalf("order %v body %q", order, body)
	}
	for _, in := range []string{"no frontmatter", "---\nunterminated: yes\n", "---\n---\nx"} {
		if fm, _, b := ParseFrontmatter(in); fm != nil || b != in {
			t.Errorf("%q: got %v %q", in, fm, b)
		}
	}
}

func TestUpdateFrontmatterField(t *testing.T) {
	in := "---\nname: s\nstatus: open\n---\nstatus: open\n"
	got, ok := UpdateFrontmatterField(in, "status", "done")
	if !ok || got != "---\nname: s\nstatus: done\n---\nstatus: open\n" {
		t.Fatalf("got %q %v", got, ok)
	}
	if _, ok := UpdateFrontmatterField(in, "missing", "x"); ok {
		t.Error("missing field reported found")
	}
	if _, ok := UpdateFrontmatterField("status: open\n", "status", "x"); ok {
		t.Error("no frontmatter reported found")
	}
}
