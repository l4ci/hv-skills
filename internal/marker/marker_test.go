package marker

import "testing"

func TestLine(t *testing.T) {
	for _, c := range []struct {
		kind string
		args []string
		want string
	}{
		{"blocked", nil, "<!-- hv:blocked -->"},
		{"escalation", []string{"e1"}, "<!-- hv:escalation e1 -->"},
		{"x", []string{"a", "b"}, "<!-- hv:x a b -->"},
	} {
		if got := Line(c.kind, c.args...); got != c.want {
			t.Errorf("Line(%q,%v) = %q, want %q", c.kind, c.args, got, c.want)
		}
	}
}

func TestHas(t *testing.T) {
	if !Has("text\n\n" + Line("done")) {
		t.Error("marked body not detected")
	}
	if Has("plain <!-- html comment --> text") {
		t.Error("plain comment detected as marker")
	}
}
