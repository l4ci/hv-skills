package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// contractPaths reads the verb paths out of the contract, the same way the
// generated list was made: "### hv <path>" headings, argument and flag words
// dropped.
func contractPaths(t *testing.T) []string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "docs", "design", "5.0-verb-contract.md"))
	if err != nil {
		t.Fatal(err)
	}
	re := regexp.MustCompile(`(?m)^### hv (.*)$`)
	seen := map[string]bool{}
	var out []string
	for _, m := range re.FindAllStringSubmatch(string(b), -1) {
		var w []string
		for _, tok := range strings.Fields(m[1]) {
			if strings.ContainsAny(tok[:1], "<[-") {
				break
			}
			w = append(w, tok)
		}
		if p := strings.Join(w, " "); p != "" && !seen[p] {
			seen[p] = true
			out = append(out, p)
		}
	}
	sort.Strings(out)
	return out
}

func TestContractVerbsMatchTheContract(t *testing.T) {
	want := contractPaths(t)
	if strings.Join(want, "\n") != strings.Join(contractVerbs, "\n") {
		var b strings.Builder
		for _, p := range want {
			b.WriteString("\t\"" + p + "\",\n")
		}
		t.Fatalf("contractVerbs (internal/cli/contract_verbs.go) drifted from the contract; replace its entries with:\n%s", b.String())
	}
}

func stubRun(args ...string) (int, string, string) {
	var so, se bytes.Buffer
	code := Main(args, strings.NewReader(""), &so, &se)
	return code, so.String(), se.String()
}

// A contract verb the Go binary lacks answers exit 71, whatever follows it,
// not "unknown command" (exit 2).
func TestUnimplementedContractVerbExits71(t *testing.T) {
	for _, args := range [][]string{
		{"init"},
		{"init", "check"},
		{"init", "umbrella", "--json"},
		{"init", "--no-such-flag", "x"},
		{"init", "check", "--repo", "web"},
	} {
		code, out, errOut := stubRun(args...)
		if code != 71 || !strings.Contains(errOut, "is not ported yet") {
			t.Errorf("%v: exit %d stderr %q", args, code, errOut)
		}
		if hasJSON := containsJSON(args); hasJSON != strings.Contains(out, `"code": "not_implemented"`) || (hasJSON && !strings.Contains(out, `"exit": 71`)) {
			t.Errorf("%v: envelope %q", args, out)
		}
	}
	_, _, errOut := stubRun("init", "check")
	if !strings.Contains(errOut, "hv init check is not ported yet") {
		t.Errorf("the message names the full verb path: %q", errOut)
	}
	// -h still reaches help
	if code, out, _ := stubRun("init", "check", "--help"); code != 0 || !strings.Contains(out, "hv init check") {
		t.Errorf("help: %d %q", code, out)
	}
	// a typo under an implemented group stays an unknown command
	if code, _, errOut := stubRun("knowledge", "nosuch"); code != 2 || !strings.Contains(errOut, "unknown command") {
		t.Errorf("unknown: %d %q", code, errOut)
	}
}

// `hv __verbs` is what test/hv-hybrid routes by: stubs must stay out of it.
func TestVerbsExcludesStubs(t *testing.T) {
	_, out, _ := stubRun("__verbs")
	listed := map[string]bool{}
	for _, l := range strings.Split(strings.TrimSpace(out), "\n") {
		listed[l] = true
	}
	for _, stub := range []string{"init", "init check", "init umbrella"} {
		if listed[stub] {
			t.Errorf("stub %q listed by __verbs", stub)
		}
	}
	if !listed["version"] || !listed["knowledge query"] {
		t.Errorf("implemented verbs missing: %v", listed)
	}
	// every listed verb really runs; every other contract verb is a stub. The
	// probe runs in an empty directory: from the package directory a verb such
	// as `block skills` walks up to this repo's .hv/ and rewrites AGENTS.md.
	empty := t.TempDir()
	for _, p := range contractVerbs {
		if listed[p] {
			continue
		}
		if code, _, _ := stubRun(append([]string{"-C", empty}, append(strings.Fields(p), "--json")...)...); code == 2 && !strings.HasPrefix(p, "block ") {
			t.Errorf("contract verb %q is neither implemented nor a stub (exit 2)", p)
		}
	}
}
