package pystr

import (
	"regexp"
	"strconv"
	"testing"
	"unicode/utf8"

	"github.com/l4ci/hv-skills/v5/internal/pytest"
)

// Every code point up to U+2FFFF must classify as Python does, for \s, \w, \d
// and the regexp class Go uses in its place.
func TestClassesMatchPython(t *testing.T) {
	var want struct {
		Space, Word, Digit []int
		DigitValue         map[string]int
	}
	pytest.JSON(t, `import json, re
space, word, digit, dv = [], [], [], {}
for c in range(0x30000):
    if 0xd800 <= c <= 0xdfff:
        continue
    ch = chr(c)
    if re.match(r"\s", ch): space.append(c)
    if re.match(r"\w", ch): word.append(c)
    if re.match(r"\d", ch):
        digit.append(c)
        dv[str(c)] = int(ch)
print(json.dumps({"space": space, "word": word, "digit": digit, "digitValue": dv}))`, nil, &want)

	class := regexp.MustCompile(`\A[` + SpaceClass + `]\z`)
	var space, word, digit []int
	for c := 0; c < 0x30000; c++ {
		r := rune(c)
		if !utf8.ValidRune(r) {
			continue
		}
		if IsSpace(r) {
			space = append(space, c)
		}
		if IsWord(r) {
			word = append(word, c)
		}
		if IsDigit(r) {
			digit = append(digit, c)
			if got := DigitValue(r); got != want.DigitValue[itoa(c)] {
				t.Errorf("DigitValue(U+%04X) = %d, Python int() = %d", c, got, want.DigitValue[itoa(c)])
			}
		}
		if class.MatchString(string(r)) != IsSpace(r) {
			t.Errorf("SpaceClass disagrees with IsSpace at U+%04X", c)
		}
	}
	for name, p := range map[string]struct{ got, want []int }{"space": {space, want.Space}, "word": {word, want.Word}, "digit": {digit, want.Digit}} {
		if !equalInts(p.got, p.want) {
			t.Errorf("%s: Go has %d code points, Python %d", name, len(p.got), len(p.want))
		}
	}
}

func itoa(n int) string { return strconv.Itoa(n) }

func equalInts(a, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestStringHelpersMatchPython(t *testing.T) {
	cases := []string{"", "a", "a\nb", "a\n", "\n", "a\r\nb\rc\n\nd", "x\vy\fz", "a\x1cb\x1dc\x1ed\x1fe", "a\u0085b c d", " \t x  　", "\r", "\r\n", "\n\r", "café ", "a\x0b\x0c"}
	var want []map[string]any
	pytest.JSON(t, `import json, sys
out = []
for s in json.load(open(sys.argv[1])):
    out.append({"strip": s.strip(), "rstrip": s.rstrip(), "lines": s.splitlines(), "univ": s.replace("\r\n", "\n").replace("\r", "\n")})
print(json.dumps(out))`, cases, &want)
	var got, w, in []any
	for i, s := range cases {
		lines := Splitlines(s)
		if lines == nil {
			lines = []string{}
		}
		got = append(got, map[string]any{"strip": Strip(s), "rstrip": Rstrip(s), "lines": lines, "univ": Universal(s)})
		w, in = append(w, want[i]), append(in, s)
	}
	pytest.Compare(t, "pystr", in, got, w)
}
