package migrate

import (
	"strings"
	"testing"
)

func TestRewriteSkipsCodeAndHelperNames(t *testing.T) {
	in := "run /hv-c now\n`/hv-c` stays\n```\n/hv-rm in fence\n```\nuse hv-map-query and .hv/bin/hv-context-add\nthen /hv-undo, /hv-c.\n/hv-cx is not it\n"
	out, n, manual := Rewrite(in, "f.md")
	want := "run /hv-capture now\n`/hv-c` stays\n```\n/hv-rm in fence\n```\nuse hv-map-query and .hv/bin/hv-context-add\nthen /hv-ship --undo, /hv-capture.\n/hv-cx is not it\n"
	if out != want || n != 3 || len(manual) != 0 {
		t.Errorf("out=%q n=%d manual=%v", out, n, manual)
	}
}

func TestRewriteReportsAmbiguousCommands(t *testing.T) {
	_, n, manual := Rewrite("a\nb /hv-issues c\n`/hv-map` skipped\n/hv-map\n", "x/y.md")
	if n != 0 || len(manual) != 2 {
		t.Fatalf("n=%d manual=%v", n, manual)
	}
	if manual[0] != "x/y.md:2: hv-issues\\b — ambiguous — could be --from-github or --from-gitlab" || !strings.HasPrefix(manual[1], "x/y.md:4: hv-map\\b") {
		t.Errorf("manual = %q", manual)
	}
}

func TestRewriteIsIdempotent(t *testing.T) {
	once, _, _ := Rewrite("/hv-c /hv-rm /hv-undo /hv-docs /hv-assume /hv-context", "f")
	twice, n, _ := Rewrite(once, "f")
	if twice != once || n != 0 {
		t.Errorf("second pass changed %q -> %q (%d)", once, twice, n)
	}
}

func TestUnifiedDiffMergesCloseHunks(t *testing.T) {
	var a, b []string
	for i := 1; i <= 30; i++ {
		a = append(a, "line\n")
		b = append(b, "line\n")
	}
	b[2], b[8] = "X\n", "Y\n" // 5 unchanged lines between: one hunk
	b[25] = "Z\n"             // far away: a second hunk
	got := UnifiedDiff(strings.Join(a, ""), strings.Join(b, ""), "f")
	if strings.Count(got, "@@ -") != 2 || !strings.Contains(got, "@@ -1,12 +1,12 @@\n") || !strings.Contains(got, "@@ -23,7 +23,7 @@\n") {
		t.Errorf("hunks:\n%s", got)
	}
	if UnifiedDiff("same\n", "same\n", "f") != "" {
		t.Error("identical texts produced a diff")
	}
}
