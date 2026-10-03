package main

// Differential harness for the A4 item verbs (#48). Each scenario builds a
// fixture project (git repo with a commit, .hv/ tree), copies it twice and
// runs the old implementation in copy A and the Go binary in copy B with the
// same arguments. It compares the exit code, the --json envelope (parsed,
// deep-equal) and the whole .hv/ tree byte for byte, ignoring *.lock files.
//
// The reference is test/hv-shim for verbs it has an adapter for (id next,
// item create, item complete, item field get|list|set). For the others
// (reopen, rm, shipped, ready, comment add|list) it is the old helper, run
// directly with the old argv from the contract's `old:` line; the Go envelope
// is then checked against what the old stdout implies.
//
// The A4 backlog, summary, status and refactor verbs (parity_a4b_test.go) run
// on this same harness: scn gained env, text, normTS and norm for them, and fx
// gained after and subs for umbrella and git-history fixtures.
//
// Safety: TestMain puts test/fakes first on PATH and checks that gh resolves
// there; helpers never reach the real gh or glab. Fixtures live in temp dirs.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

var (
	hvBin      string // the built Go binary
	repoDir    string
	shimPath   string
	stagedBin  string // copy of bin/ the old helpers run from
	baseEnv    []string
	harnessTmp string
)

func TestMain(m *testing.M) { os.Exit(runMain(m)) }

func runMain(m *testing.M) int {
	wd, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	repoDir = filepath.Clean(filepath.Join(wd, "..", ".."))
	fakes := filepath.Join(repoDir, "test", "fakes")
	os.Setenv("PATH", fakes+string(os.PathListSeparator)+os.Getenv("PATH"))
	if gh, err := exec.LookPath("gh"); err != nil || !strings.HasPrefix(gh, fakes+string(os.PathSeparator)) {
		fmt.Fprintf(os.Stderr, "gh does not resolve into %s (got %q, %v); refusing to run\n", fakes, gh, err)
		return 1
	}
	pinDay()
	pruneOracleCache(3 * 24 * time.Hour)
	harnessTmp, err = os.MkdirTemp("", "hv-parity-*")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer os.RemoveAll(harnessTmp)
	// The old helpers and the shim run as children and call mktemp: root their
	// temp dirs under harnessTmp so the RemoveAll above takes them too (#110).
	childTmp := filepath.Join(harnessTmp, "tmp")
	if err := os.Mkdir(childTmp, 0o755); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	os.Setenv("TMPDIR", childTmp)
	hvBin = filepath.Join(harnessTmp, "hv")
	build := exec.Command("go", "build", "-o", hvBin, ".")
	build.Dir = filepath.Join(repoDir, "cmd", "hv")
	if out, err := build.CombinedOutput(); err != nil {
		fmt.Fprintf(os.Stderr, "go build: %v\n%s", err, out)
		return 1
	}
	shimPath = filepath.Join(repoDir, "test", "hv-shim")
	stagedBin = filepath.Join(harnessTmp, "bin")
	if out, err := exec.Command("cp", "-a", filepath.Join(repoDir, "bin"), stagedBin).CombinedOutput(); err != nil {
		fmt.Fprintf(os.Stderr, "stage bin: %v\n%s", err, out)
		return 1
	}
	baseEnv = []string{
		"PATH=" + os.Getenv("PATH"),
		"HOME=" + harnessTmp,
		"HV_SHIM_HELPERS=" + stagedBin,
		"FAKE_TRACKER_DB=" + filepath.Join(harnessTmp, "tracker.json"),
		"LC_ALL=C.UTF-8",
	}
	code := m.Run()
	if recording {
		if err := writeRecords(); err != nil {
			fmt.Fprintln(os.Stderr, "frozen:", err)
			return 1
		}
	}
	return code
}

// TestFakesFirst is the guard: tests must never reach the real gh or glab.
func TestFakesFirst(t *testing.T) {
	fakes := filepath.Join(repoDir, "test", "fakes") + string(os.PathSeparator)
	for _, tool := range []string{"gh", "glab"} {
		p, err := exec.LookPath(tool)
		if err != nil || !strings.HasPrefix(p, fakes) {
			t.Fatalf("%s resolves to %q (%v), not test/fakes", tool, p, err)
		}
	}
}

// ---- fixtures ---------------------------------------------------------------

type info struct {
	h1, refactor, head string
	x                  map[string]string
}

// fx describes a fixture project; the zero value is the standard one.
type fx struct {
	archive   string            // "" none, "plain" (no headings, as hv-archive-old writes it), "sectioned"
	noBacklog bool              // no .hv/BACKLOG.md
	noCommit  bool              // git repo without a commit
	noHV      bool              // no .hv/ at all
	backlog   string            // replaces BACKLOG.md ("{h1}" etc. are expanded)
	config    string            // replaces config.json
	counters  string            // replaces counters.json; "-" deletes it
	status    string            // status.json content
	commits   int               // extra commits that mention parser-core and lexer-v2
	files     map[string]string // extra files, path relative to the project; "{h1}" etc. expanded
	// subs makes umbrella sub-repos after the project's last commit: name to the
	// commit subjects to create, and a .hv/repos.json registering them by name.
	subs map[string][]string
	// after runs last, with the project built; it may commit, write files and
	// publish tokens with in.x["name"], which expand as {x:name}.
	after func(t *testing.T, dir string, in *info)
}

const stdBacklog = `# TODO

## Bugs
- **[B01] [P1] First bug.** Something broke. Detail: ` + "`.hv/bugs/B01.md`" + ` Related: [F01] Milestone: M01 Since: {h1}
- **[B02] [P2] Second bug.** Other thing. Related: [B01], [F01] Since: {h1}
- **[B03] [P3] Third bug.** Third. Milestone: M02 Repos: web Subsystem: capture Since: {h1}
- **[B04] [P2] Fix v1.2 parser.** Dotted title. Since: {h1}

## Features
- **[F01] [Major] First feature.** Feature body. Detail: ` + "`.hv/features/F01.md`" + ` Related: [B01] Repos: web Since: {h1}
- **[F02] [Minor] Second feature.** Body. Related: [B01] Subsystem: capture Since: {h1}

## Tasks
- **[T01] First task.** Task body.
- **[T02] Second task.** Related: [F01]

## Completed
- ~~**[B08] [P2] Done bug.** body Since: {h1}~~ Done 2026-09-30 [` + "`{h1}`" + `]
- ~~**[F08] [Major] Done refactor feature.** body~~ Done 2026-09-30 [` + "`{refactor}`" + `]
- ~~**[T08] Done task.** body~~ Done 2026-09-30 [` + "`{h1}`" + `]
- ~~**[B09] [P2] Old bug.** x Related: [B01]~~ Done 2026-09-30 [` + "`abc1234`" + `] (dropped: no longer needed)
`

const stdCounters = `{
  "bugs": 4,
  "features": 2,
  "tasks": 2,
  "milestones": 1,
  "since_refactor": {
    "features": 1,
    "bugs": 2
  }
}
`

const stdConfig = `{
  "backlog": {
    "backend": "file"
  }
}
`

const issuesConfig = `{
  "backlog": {
    "backend": "issues"
  }
}
`

const archiveItems = "- ~~**[B05] [P2] Archived bug.** old Related: [B01]~~ Done 2026-05-15 [`e4abdbe`]\n" +
	"- ~~**[F05] [Minor] Archived feature.** old~~ Done 2026-05-15 [`e4abdbe`]\n"

var stdFiles = map[string]string{
	".hv/bugs/B01.md": "# B01: First bug\n\n## Acceptance\n- [ ] it works\n\n## Proof\n- build · PASS · ok\n- tests · PASS · ok\n\n## Log\n" +
		"- 2026-09-01 · question · Why?\n  more detail\n- 2026-09-02 · answer · Because.\n",
	".hv/features/F01.md":  "# F01: First feature\n\n## Plan\nno criteria here\n",
	".hv/designs/F02.md":   "# design\n",
	".hv/plans/M01-B02.md": "plan b02\n",
	".hv/plans/M02-F01.md": "plan f01\n",
	"src/main.go":          "package main\n",
	"body.md":              "# {ID}\n\nSee [{ID}] in the backlog.\n",
}

var (
	dayTok = regexp.MustCompile(`\{d(\d+)\}`)
	xTok   = regexp.MustCompile(`\{x:([a-z0-9-]+)\}`)
)

// expand fills {h1}, {refactor}, {head}, {dN} (the date N days ago, local, as
// the helpers' date.today() sees it) and {x:name} (hook tokens).
func expand(s string, i info) string {
	s = strings.NewReplacer("{h1}", i.h1, "{refactor}", i.refactor, "{head}", i.head).Replace(s)
	s = dayTok.ReplaceAllStringFunc(s, func(m string) string {
		n, _ := strconv.Atoi(dayTok.FindStringSubmatch(m)[1])
		d, _ := time.ParseInLocation("2006-01-02", localDay, time.Local)
		return d.AddDate(0, 0, -n).Format("2006-01-02")
	})
	return xTok.ReplaceAllStringFunc(s, func(m string) string { return i.x[xTok.FindStringSubmatch(m)[1]] })
}

// commitFile writes path and commits it, returning the short hash.
func commitFile(t *testing.T, dir, subject, path, content string) string {
	t.Helper()
	write(t, dir, path, content)
	git(t, dir, "add", path)
	git(t, dir, "commit", "-q", "-m", subject)
	return git(t, dir, "rev-parse", "--short", "HEAD")
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	// Fixed commit time (noon UTC of the harness day) so a fixture's hashes
	// repeat from run to run; the oracle cache (parity_cache_test.go) keys on them.
	when := startDay + "T12:00:00Z"
	cmd.Env = append(append([]string{}, baseEnv...), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null",
		"GIT_AUTHOR_DATE="+when, "GIT_COMMITTER_DATE="+when)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func write(t *testing.T, root, rel, content string) {
	t.Helper()
	p := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// fxTemplates caches built fixtures for the process: most scenarios share a
// handful of fixture shapes, and building one costs about twenty git calls.
var fxTemplates = struct {
	sync.Mutex
	m map[string]*fxTemplate
}{m: map[string]*fxTemplate{}}

type fxTemplate struct {
	once sync.Once
	dir  string
	in   info
}

// build returns a fresh copy of the fixture (a temp dir of the test) with the
// hashes. The fixture is built once per distinct description; the after hook,
// which the description cannot capture, runs on each copy.
func (f fx) build(t *testing.T) (string, info) {
	t.Helper()
	after := f.after
	f.after = nil
	key := fmt.Sprintf("%#v", f)
	fxTemplates.Lock()
	tpl := fxTemplates.m[key]
	if tpl == nil {
		tpl = &fxTemplate{}
		fxTemplates.m[key] = tpl
	}
	fxTemplates.Unlock()
	tpl.once.Do(func() {
		dir, err := os.MkdirTemp(harnessTmp, "fx-")
		if err != nil {
			t.Fatal(err)
		}
		tpl.dir, tpl.in = dir, f.buildIn(t, dir)
	})
	if tpl.dir == "" {
		t.Fatal("fixture template failed to build")
	}
	dir := copyTree(t, tpl.dir)
	in := tpl.in
	in.x = map[string]string{}
	for k, v := range tpl.in.x {
		in.x[k] = v
	}
	if after != nil {
		after(t, dir, &in)
	}
	return dir, in
}

// buildIn makes the fixture in dir and returns the hashes.
func (f fx) buildIn(t *testing.T, dir string) info {
	t.Helper()
	var in info
	git(t, dir, "init", "-q", "-b", "main")
	git(t, dir, "config", "user.name", "Fixture")
	git(t, dir, "config", "user.email", "fixture@example.com")
	git(t, dir, "config", "commit.gpgsign", "false")
	if !f.noCommit {
		write(t, dir, "README.md", "readme\n")
		git(t, dir, "add", "README.md")
		git(t, dir, "commit", "-q", "-m", "chore: initial commit")
		in.h1 = git(t, dir, "rev-parse", "--short", "HEAD")
		write(t, dir, "tidy.txt", "tidy\n")
		git(t, dir, "add", "tidy.txt")
		git(t, dir, "commit", "-q", "-m", "refactor: tidy the lexer")
		in.refactor = git(t, dir, "rev-parse", "--short", "HEAD")
	} else {
		in.h1, in.refactor = "0000000", "0000001"
	}
	if !f.noHV {
		backlog := stdBacklog
		if f.backlog != "" {
			backlog = f.backlog
		}
		if !f.noBacklog {
			write(t, dir, ".hv/BACKLOG.md", expand(backlog, in))
		} else {
			if err := os.MkdirAll(filepath.Join(dir, ".hv"), 0o755); err != nil {
				t.Fatal(err)
			}
		}
		cfg := stdConfig
		if f.config != "" {
			cfg = f.config
		}
		write(t, dir, ".hv/config.json", cfg)
		switch f.counters {
		case "-":
		case "":
			write(t, dir, ".hv/counters.json", stdCounters)
		default:
			write(t, dir, ".hv/counters.json", f.counters)
		}
		switch f.archive {
		case "plain":
			write(t, dir, ".hv/ARCHIVE.md", "# Archive\n\nCompleted items older than the active window.\n"+archiveItems)
		case "sectioned":
			write(t, dir, ".hv/ARCHIVE.md", "# Archive\n\n## Completed\n"+archiveItems)
		}
		if f.status != "" {
			write(t, dir, ".hv/status.json", f.status)
		}
		for p, c := range stdFiles {
			if _, over := f.files[p]; !over {
				write(t, dir, p, expand(c, in))
			}
		}
		for p, c := range f.files {
			if c != "" {
				write(t, dir, p, expand(c, in))
			}
		}
	}
	if !f.noCommit {
		write(t, dir, "feature.txt", "x\n")
		git(t, dir, "add", "-A")
		git(t, dir, "commit", "-q", "-m", "feat: add `parser-core` lexer-v2 support")
		for n := 1; n <= f.commits; n++ {
			write(t, dir, fmt.Sprintf("part%d.txt", n), "x\n")
			git(t, dir, "add", "-A")
			git(t, dir, "commit", "-q", "-m", fmt.Sprintf("feat: add `parser-core` lexer-v2 part %d", n))
		}
		in.head = git(t, dir, "rev-parse", "--short", "HEAD")
	}
	in.x = map[string]string{}
	if len(f.subs) > 0 {
		var names []string
		for n := range f.subs {
			names = append(names, n)
		}
		sort.Strings(names)
		var entries []string
		for _, n := range names {
			sub := filepath.Join(dir, n)
			if err := os.MkdirAll(sub, 0o755); err != nil {
				t.Fatal(err)
			}
			git(t, sub, "init", "-q", "-b", "main")
			git(t, sub, "config", "user.name", "Fixture")
			git(t, sub, "config", "user.email", "fixture@example.com")
			git(t, sub, "config", "commit.gpgsign", "false")
			for k, subject := range f.subs[n] {
				commitFile(t, sub, subject, fmt.Sprintf("f%d.txt", k), "x\n")
			}
			entries = append(entries, fmt.Sprintf(`{"name": %q, "path": %q}`, n, n))
		}
		write(t, dir, ".hv/repos.json", `{"repos": [`+strings.Join(entries, ", ")+`]}`+"\n")
	}
	return in
}

func copyTree(t *testing.T, src string) string {
	t.Helper()
	dst := t.TempDir()
	if out, err := exec.Command("cp", "-a", src+"/.", dst).CombinedOutput(); err != nil {
		t.Fatalf("cp: %v\n%s", err, out)
	}
	return dst
}

// snapshot is the .hv/ tree: relative path to content, lock files left out.
func snapshot(t *testing.T, root string) map[string]string {
	t.Helper()
	out := map[string]string{}
	base := filepath.Join(root, ".hv")
	filepath.Walk(base, func(p string, fi os.FileInfo, err error) error {
		if err != nil || fi.IsDir() || strings.HasSuffix(p, ".lock") {
			return nil
		}
		b, _ := os.ReadFile(p)
		rel, _ := filepath.Rel(root, p)
		out[rel] = string(b)
		return nil
	})
	return out
}

func diffTrees(a, b map[string]string) string {
	var msgs []string
	keys := map[string]bool{}
	for k := range a {
		keys[k] = true
	}
	for k := range b {
		keys[k] = true
	}
	var sorted []string
	for k := range keys {
		sorted = append(sorted, k)
	}
	sort.Strings(sorted)
	for _, k := range sorted {
		av, aok := a[k]
		bv, bok := b[k]
		switch {
		case !aok:
			msgs = append(msgs, fmt.Sprintf("%s: only in Go copy:\n%s", k, bv))
		case !bok:
			msgs = append(msgs, fmt.Sprintf("%s: only in reference copy:\n%s", k, av))
		case av != bv:
			msgs = append(msgs, fmt.Sprintf("%s differs\n--- reference\n%s\n--- go\n%s", k, av, bv))
		}
	}
	return strings.Join(msgs, "\n")
}

// ---- running ----------------------------------------------------------------

type run struct {
	code           int
	stdout, stderr string
	dir            string
}

func exec1(t *testing.T, dir, stdin string, name string, args ...string) run {
	t.Helper()
	return exec1e(t, dir, stdin, nil, name, args...)
}

func exec1e(t *testing.T, dir, stdin string, env []string, name string, args ...string) run {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(append([]string{}, baseEnv...), env...)
	cmd.Stdin = strings.NewReader(stdin)
	var so, se bytes.Buffer
	cmd.Stdout, cmd.Stderr = &so, &se
	err := cmd.Run()
	code := 0
	if err != nil {
		ee, ok := err.(*exec.ExitError)
		if !ok {
			t.Fatalf("%s: %v", name, err)
		}
		code = ee.ExitCode()
	}
	return run{code, so.String(), se.String(), dir}
}

type envl map[string]any

func parseEnv(t *testing.T, who string, r run) envl {
	t.Helper()
	var e envl
	if err := json.Unmarshal([]byte(r.stdout), &e); err != nil {
		t.Fatalf("%s: stdout is not one JSON document: %v\nstdout: %q\nstderr: %s", who, err, r.stdout, r.stderr)
	}
	return e
}

// at walks a dotted path through an envelope ("data.items.0.id").
func at(v any, path string) any {
	for _, part := range strings.Split(path, ".") {
		switch t := v.(type) {
		case envl:
			v = t[part]
		case map[string]any:
			v = t[part]
		case []any:
			i, err := strconv.Atoi(part)
			if err != nil || i >= len(t) {
				return nil
			}
			v = t[i]
		default:
			return nil
		}
	}
	return v
}

func subst(args []string, i info) []string {
	out := make([]string, len(args))
	for k, a := range args {
		out[k] = expand(a, i)
	}
	return out
}

var usageish = regexp.MustCompile(`usage:|unknown argument|expects|invalid|not a valid|empty comment body|comment kind`)

// mapOld is the contract's old backend rc mapping.
func mapOld(rc int, stderr string) int {
	switch rc {
	case 0:
		return 0
	case 1:
		if usageish.MatchString(stderr) {
			return 2
		}
		return 3
	case 2:
		return 4
	case 3:
		return 5
	case 4:
		return 6
	}
	return 70
}

// scn is one differential scenario.
type scn struct {
	name string
	fx   fx
	argv []string // new-shape argv without "hv"; includes --json
	in   string   // stdin
	old  []string // reference helper and its argv; empty means the shim runs argv
	// oldMap maps the helper's rc and stderr to the contract exit (default mapOld).
	oldMap func(rc int, stderr string) int
	want   int // the Go binary's exit, and the reference's mapped exit unless div is set
	check  func(t *testing.T, goEnv envl, ref run)
	// div, when set, documents a place where the reference cannot agree: only
	// the .hv/ tree is compared, the reference must exit refWant, and check
	// asserts the Go side.
	div     string
	refWant int
	// goOnly scenarios run only the Go binary (no reference is available).
	goOnly bool
	// shimNoData: the shim sends no failure data on exit 4; the contract does.
	shimNoData bool
	// env is extra environment for every run of the scenario (HV_TEST_* hooks).
	env []string
	// text also compares the plain, non --json stdout of both sides, for the
	// read-only verbs whose text the old helper's stdout defines.
	text bool
	// normTS replaces timestamps taken after the harness started with <TS> in
	// status.json and in the envelopes, so the stamps the verbs write compare.
	normTS bool
	// norm rewrites both envelopes before they are compared: the places where
	// the shim and the contract disagree.
	norm func(envl) envl
	// cwd is the subdirectory of the project both sides run in ("" is the root).
	cwd string
	// prep runs on each copy of the fixture before the scenario, for state
	// that does not survive a copy (a git worktree points at its origin).
	prep func(t *testing.T, dir string)
	// bin and oldBin replace the Go binary and the staged bin/ for scenarios
	// that need another install layout (the update verb).
	bin, oldBin string
}

func (s scn) goBin() string {
	if s.bin != "" {
		return s.bin
	}
	return hvBin
}

func (s scn) oldPath(name string) string {
	if s.oldBin != "" {
		return filepath.Join(s.oldBin, name)
	}
	return filepath.Join(stagedBin, name)
}

// variants runs a scenario with no archive, a plain archive and a sectioned one.
func variants(s scn) []scn {
	var out []scn
	for _, a := range []string{"", "plain", "sectioned"} {
		v := s
		v.fx.archive = a
		if a == "" {
			v.name = s.name + "/noarchive"
		} else {
			v.name = s.name + "/archive-" + a
		}
		out = append(out, v)
	}
	return out
}

var tsRe = regexp.MustCompile(`\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ`)

// startDay is the UTC date the harness started; a timestamp on or after it was
// written by the run under test, an older one came from a fixture.
var startDay = time.Now().UTC().Format("2006-01-02")

func normStamps(s string) string {
	return tsRe.ReplaceAllStringFunc(s, func(m string) string {
		if m[:10] >= startDay {
			return "<TS>"
		}
		return m
	})
}

func normTree(m map[string]string) map[string]string {
	out := map[string]string{}
	for k, v := range m {
		if k == ".hv/status.json" {
			v = normStamps(v)
		}
		out[k] = v
	}
	return out
}

func normEnvStamps(t *testing.T, e envl) envl {
	t.Helper()
	b, err := json.Marshal(map[string]any(e))
	if err != nil {
		t.Fatal(err)
	}
	var out envl
	if err := json.Unmarshal([]byte(normStamps(string(b))), &out); err != nil {
		t.Fatal(err)
	}
	return out
}

// copyEnv is a deep copy, so a norm function can edit its own.
func copyEnv(t *testing.T, e envl) envl {
	t.Helper()
	b, err := json.Marshal(map[string]any(e))
	if err != nil {
		t.Fatal(err)
	}
	var out envl
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

// oracleCacheable: a scenario whose check reads the oracle's directory, or
// whose prep or install layout the key cannot see, always runs the old side.
func (s scn) oracleCacheable() bool {
	return s.check == nil && s.prep == nil && s.oldBin == "" && s.bin == ""
}

// scnOracle is what the old side did for a scenario: the run, the .hv/ tree
// it left and, for text scenarios, the plain stdout of a second run.
type scnOracle struct {
	Code           int
	Stdout, Stderr string
	Tree           map[string]string
	Text           string
}

// oracle runs the scenario's old side in a copy of base, or replays it from
// the cache when none of its inputs changed (parity_cache_test.go).
func (s scn) oracle(t *testing.T, base string, in info, argv []string) (ref run, tree map[string]string, text string) {
	t.Helper()
	var plain []string
	for _, a := range argv {
		if a != "--json" {
			plain = append(plain, a)
		}
	}
	var old []string
	if len(s.old) > 0 {
		old = subst(s.old, in)
	}
	runOld := func(dir string, args []string, oldArgs []string) run {
		if len(old) > 0 {
			return exec1e(t, filepath.Join(dir, s.cwd), s.in, s.env, s.oldPath(old[0]), oldArgs...)
		}
		return exec1e(t, filepath.Join(dir, s.cwd), s.in, s.env, "python3", append([]string{shimPath}, args...)...)
	}
	var oldTail []string
	if len(old) > 0 {
		oldTail = old[1:]
	}
	cacheable := s.oracleCacheable()
	var key string
	if cacheable {
		key = oracleKey(t, map[string]any{"kind": "scn", "project": projectDigest(base), "argv": argv, "old": old,
			"in": s.in, "env": s.env, "cwd": s.cwd, "text": s.text, "div": s.div})
		var c scnOracle
		if oracleLoad(key, &c) {
			return run{code: c.Code, stdout: c.Stdout, stderr: c.Stderr}, c.Tree, c.Text
		}
	}
	refDir := copyTree(t, base)
	if s.prep != nil {
		s.prep(t, refDir)
	}
	ref = runOld(refDir, argv, oldTail)
	ref.dir = refDir
	tree = snapshot(t, refDir)
	if s.text {
		text = runOld(refDir, plain, oldTail).stdout
	}
	if cacheable {
		oracleStore(t, key, scnOracle{ref.code, ref.stdout, ref.stderr, tree, text})
	}
	return ref, tree, text
}

func (s scn) exec(t *testing.T) {
	t.Parallel()
	if frozenOn != nil && !s.goOnly {
		frozenCheck(t, s.goSide)
		return
	}
	base, in := s.fx.build(t)
	goDir := copyTree(t, base)
	if s.prep != nil {
		s.prep(t, goDir)
	}
	argv := subst(s.argv, in)
	goRun := exec1e(t, filepath.Join(goDir, s.cwd), s.in, s.env, s.goBin(), argv...)
	if goRun.code != s.want {
		t.Errorf("go exit = %d, want %d\nargv: %v\nstdout: %s\nstderr: %s", goRun.code, s.want, argv, goRun.stdout, goRun.stderr)
	}
	goEnv := parseEnv(t, "go", goRun)
	if goEnv["ok"] != (s.want == 0) {
		t.Errorf("go envelope ok = %v for exit %d", goEnv["ok"], goRun.code)
	}
	goEnv["__info"] = in
	goEnv["__godir"] = goDir
	if s.goOnly {
		if s.check != nil {
			s.check(t, goEnv, run{})
		}
		return
	}
	ref, refTree, refText := s.oracle(t, base, in, argv)
	var refCode int
	if len(s.old) > 0 {
		m := s.oldMap
		if m == nil {
			m = mapOld
		}
		refCode = m(ref.code, ref.stderr)
	} else {
		refCode = ref.code
	}
	if s.div != "" {
		if refCode != s.refWant {
			t.Errorf("reference exit = %d, want %d (divergence: %s)\nstdout: %s\nstderr: %s", refCode, s.refWant, s.div, ref.stdout, ref.stderr)
		}
	} else if refCode != goRun.code {
		t.Errorf("exit differs: reference %d, go %d\nargv: %v\nref stdout: %s\nref stderr: %s\ngo stdout: %s\ngo stderr: %s",
			refCode, goRun.code, argv, ref.stdout, ref.stderr, goRun.stdout, goRun.stderr)
	}
	goTree := snapshot(t, goDir)
	if s.normTS {
		refTree, goTree = normTree(refTree), normTree(goTree)
	}
	if d := diffTrees(refTree, goTree); d != "" {
		t.Errorf(".hv/ trees differ:\n%s", d)
	}
	if len(s.old) == 0 && s.div == "" {
		refEnv := parseEnv(t, "shim", ref)
		g := goEnv
		if s.shimNoData {
			g = envl{}
			for k, v := range goEnv {
				if k != "data" {
					g[k] = v
				}
			}
		}
		refEnv, g = stripText(refEnv), stripText(g)
		if s.normTS {
			refEnv, g = normEnvStamps(t, refEnv), normEnvStamps(t, g)
		}
		if s.norm != nil {
			refEnv, g = s.norm(copyEnv(t, refEnv)), s.norm(copyEnv(t, g))
		}
		if !reflect.DeepEqual(map[string]any(refEnv), map[string]any(g)) {
			rj, _ := json.Marshal(refEnv)
			gj, _ := json.Marshal(g)
			t.Errorf("envelopes differ\nargv: %v\nshim: %s\ngo:   %s", argv, rj, gj)
		}
	}
	if s.text {
		var plain []string
		for _, a := range argv {
			if a != "--json" {
				plain = append(plain, a)
			}
		}
		gt := exec1e(t, filepath.Join(goDir, s.cwd), s.in, s.env, s.goBin(), plain...)
		if gt.stdout != refText {
			t.Errorf("text output differs\nargv: %v\nref:\n%q\ngo:\n%q", plain, refText, gt.stdout)
		}
	}
	goEnv["__info"] = in
	goEnv["__godir"] = goDir
	if s.check != nil {
		s.check(t, goEnv, ref)
	}
	record(t, s.goSide)
}

// stripText drops error.message and error.hint, which are free text per the
// conventions, and the harness's own keys; everything else stays. Set
// HV_PARITY_MESSAGES=1 to compare the text too and see where it differs.
func stripText(e envl) envl {
	out := envl{}
	for k, v := range e {
		if k == "__info" || k == "__godir" {
			continue
		}
		if k == "error" {
			m := map[string]any{}
			for ek, ev := range v.(map[string]any) {
				if os.Getenv("HV_PARITY_MESSAGES") != "" || (ek != "message" && ek != "hint") {
					m[ek] = ev
				}
			}
			if msg, _ := v.(map[string]any)["message"].(string); msg == "" && os.Getenv("HV_PARITY_MESSAGES") == "" {
				m["message"] = "<empty>"
			}
			v = m
		}
		out[k] = v
	}
	return out
}

// ---- scenarios --------------------------------------------------------------

func eq(t *testing.T, e envl, path string, want any) {
	t.Helper()
	got := at(e, path)
	if w, ok := want.(string); ok {
		if in, ok := e["__info"].(info); ok {
			want = expand(w, in)
		}
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("%s = %#v, want %#v", path, got, want)
	}
}

func j(args ...string) []string { return append([]string{"--json"}, args...) }

func TestParityA4(t *testing.T) {
	bodyFx := fx{files: map[string]string{"body.md": "# {ID}\n\nSee [{ID}] in the backlog.\n"}}
	relFx := fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n- **[B02] [P2] b.** y Related: [B01], [F01], [T01] Milestone: M01 Since: {h1}\n\n## Features\n- **[F01] [Major] f.** z Related: [B01], [B02]\n\n## Tasks\n- **[T01] t.** w Related: [B01]\n"}
	var all []scn
	add := func(s ...scn) { all = append(all, s...) }

	// ---- id next
	for _, c := range []struct{ kind, id string }{{"bugs", "B10"}, {"features", "F09"}, {"tasks", "T09"}, {"milestones", "M02"}} {
		c := c
		add(variants(scn{name: "idnext/" + c.kind, argv: j("id", "next", "--kind", c.kind), want: 0,
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.id", c.id); eq(t, e, "data.changed", true) }})...)
	}
	add(
		scn{name: "idnext/no-counters-file", fx: fx{counters: "-"}, argv: j("id", "next", "--kind", "tasks"), want: 0},
		scn{name: "idnext/counter-ahead", fx: fx{counters: "{\n  \"bugs\": 50\n}\n"}, argv: j("id", "next", "--kind", "bugs"), want: 0,
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.id", "B51") }},
		scn{name: "idnext/missing-kind", argv: j("id", "next"), want: 2},
		scn{name: "idnext/bad-kind", argv: j("id", "next", "--kind", "stories"), want: 2},
		scn{name: "idnext/positional", argv: j("id", "next", "--kind", "bugs", "extra"), want: 2},
		scn{name: "idnext/unknown-flag", argv: j("id", "next", "--kind", "bugs", "--bogus"), want: 2},
		scn{name: "idnext/no-hv", fx: fx{noHV: true}, argv: j("id", "next", "--kind", "bugs"), want: 3},
		scn{name: "idnext/repo-outside-umbrella", argv: j("id", "next", "--kind", "bugs", "--repo", "web"), want: 3},
		scn{name: "idnext/issues-backend", fx: fx{config: issuesConfig}, argv: j("id", "next", "--kind", "bugs"), want: 4,
			check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.blockedBy", "backend")
				eq(t, e, "data.changed", false)
			}},
	)

	// ---- item create
	add(variants(scn{name: "create/bug-all-fields", want: 0,
		argv: j("item", "create", "--kind", "bugs", "--title", "Crash  on   save", "--tag", "P1", "--desc", "It crashes.",
			"--related", "[B01]", "--milestone", "M01", "--repos", "web", "--subsystem", "io", "--captured", "2026-10-02"),
		check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.id", "B10"); eq(t, e, "data.type", "B") }})...)
	add(variants(scn{name: "create/feature", argv: j("item", "create", "--kind", "features", "--title", "New thing", "--tag", "Major"), want: 0})...)
	add(
		scn{name: "create/task", argv: j("item", "create", "--kind", "tasks", "--title", "Chore!"), want: 0},
		scn{name: "create/title-ends-question", argv: j("item", "create", "--kind", "bugs", "--title", "Why does it fail?", "--tag", "P3"), want: 0},
		scn{name: "create/body-file", fx: bodyFx, argv: j("item", "create", "--kind", "features", "--title", "With body", "--body-file", "body.md"), want: 0,
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.detail", ".hv/features/F09.md") }},
		scn{name: "create/body-stdin", argv: j("item", "create", "--kind", "bugs", "--title", "Stdin body", "--body-file", "-"), in: "# {ID}\nbody from stdin\n", want: 0},
		scn{name: "create/empty-flag-values", argv: j("item", "create", "--kind", "bugs", "--title", "Skips", "--desc", "", "--related", "", "--tag", ""), want: 2},
		scn{name: "create/empty-desc-and-tag-ok", argv: j("item", "create", "--kind", "bugs", "--title", "Skips", "--desc", "", "--tag", ""), want: 0},
		scn{name: "create/unreadable-raw-file", div: "the shim reads a missing --raw-file as empty and reports the missing **[ID] (2); the contract says 3", refWant: 2,
			argv: j("item", "create", "--kind", "bugs", "--raw-file", "missing.md"), want: 3},
		scn{name: "create/invalid-backend", fx: fx{config: `{"backlog": {"backend": "jira"}}`}, goOnly: true, want: 70,
			argv: j("item", "create", "--kind", "bugs", "--title", "x")},
		scn{name: "create/bad-tag-bug", argv: j("item", "create", "--kind", "bugs", "--title", "x", "--tag", "Major"), want: 2},
		scn{name: "create/tag-on-task", argv: j("item", "create", "--kind", "tasks", "--title", "x", "--tag", "P1"), want: 2},
		scn{name: "create/missing-title", argv: j("item", "create", "--kind", "bugs"), want: 2},
		scn{name: "create/bad-kind", argv: j("item", "create", "--kind", "epics", "--title", "x"), want: 2},
		scn{name: "create/no-backlog", fx: fx{noBacklog: true}, argv: j("item", "create", "--kind", "bugs", "--title", "x"), want: 3},
		scn{name: "create/missing-section-burns-id", fx: fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] Only.** x\n"},
			argv: j("item", "create", "--kind", "tasks", "--title", "x"), want: 3},
		scn{name: "create/unreadable-body", argv: j("item", "create", "--kind", "bugs", "--title", "x", "--body-file", "missing.md"), want: 3},
		scn{name: "create/section-in-middle", fx: fx{backlog: "# TODO\n\n## Bugs\n\n## Features\n- **[F01] [Major] f.** x\n\n## Completed\n"},
			argv: j("item", "create", "--kind", "bugs", "--title", "First bug"), want: 0},
		scn{name: "create/raw-file", fx: fx{files: map[string]string{"raw.md": "- **[B77] [P2] Raw bullet.** Verbatim body.\n\n"}},
			argv: j("item", "create", "--kind", "bugs", "--raw-file", "raw.md"), want: 0,
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.id", "B77") }},
		scn{name: "create/raw-file-stdin", argv: j("item", "create", "--kind", "features", "--raw-file", "-"), in: "- **[F77] [Minor] From stdin.** x Since: abc\n", want: 0},
		scn{name: "create/raw-file-no-id", fx: fx{files: map[string]string{"raw.md": "- no id here\n"}},
			argv: j("item", "create", "--kind", "bugs", "--raw-file", "raw.md"), want: 2},
		scn{name: "create/raw-file-with-title", fx: fx{files: map[string]string{"raw.md": "- **[B77] [P2] x.** y\n"}},
			argv: j("item", "create", "--kind", "bugs", "--raw-file", "raw.md", "--title", "t"), want: 2},
		scn{name: "create/raw-file-missing-section", fx: fx{backlog: "# TODO\n\n## Bugs\n", files: map[string]string{"raw.md": "- **[T77] x.** y\n"}},
			argv: j("item", "create", "--kind", "tasks", "--raw-file", "raw.md"), want: 3},
		scn{name: "create/whitespace-title", div: "the shim passes a blank title to the helper and maps its rc to 5; the contract wants usage", refWant: 5,
			argv: j("item", "create", "--kind", "bugs", "--title", "   "), want: 2},
		scn{name: "create/whitespace-field",
			argv: j("item", "create", "--kind", "bugs", "--title", "x", "--related", "  "), want: 2},
		scn{name: "create/issues-backend", fx: fx{config: issuesConfig}, goOnly: true, want: 5,
			argv: j("item", "create", "--kind", "bugs", "--title", "x")},
		scn{name: "create/raw-file-issues-refused", fx: fx{config: issuesConfig, files: map[string]string{"raw.md": "- **[B77] x.** y\n"}}, goOnly: true, want: 4,
			argv:  j("item", "create", "--kind", "bugs", "--raw-file", "raw.md"),
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.blockedBy", "backend") }},
	)

	// ---- item complete
	add(variants(scn{name: "complete/done-with-proof", argv: j("item", "complete", "B01", "--commit", "{h1}"), want: 0,
		check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.changed", true); eq(t, e, "data.commit", "{h1}") }})...)
	add(
		scn{name: "complete/default-commit", argv: j("item", "complete", "B01"), want: 0},
		scn{name: "complete/no-proof-refused", argv: j("item", "complete", "B02", "--commit", "{h1}"), want: 4,
			check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.blockedBy", "proof missing")
				eq(t, e, "data.changed", false)
			}},
		scn{name: "complete/no-proof-flag", argv: j("item", "complete", "B02", "--commit", "{h1}", "--no-proof"), want: 0},
		scn{name: "complete/no-proof-false-still-gated", argv: j("item", "complete", "B02", "--commit", "{h1}", "--no-proof=false"), want: 4},
		scn{name: "complete/feature-bumps-features", argv: j("item", "complete", "F02", "--commit", "{h1}", "--no-proof"), want: 0},
		scn{name: "complete/task-no-bump", argv: j("item", "complete", "T01", "--commit", "{h1}", "--no-proof"), want: 0},
		scn{name: "complete/refactor-commit-no-bump", argv: j("item", "complete", "B03", "--commit", "{refactor}", "--no-proof"), want: 0},
		scn{name: "complete/unresolvable-hash-bumps", argv: j("item", "complete", "B03", "--commit", "deadbee", "--no-proof"), want: 0},
		scn{name: "complete/dropped-with-note", argv: j("item", "complete", "F02", "--commit", "{h1}", "--reason", "dropped", "--note", "line one\nline two"), want: 0},
		scn{name: "complete/handed-off-no-proof-needed", argv: j("item", "complete", "B03", "--commit", "{h1}", "--reason", "handed-off"), want: 0},
		scn{name: "complete/blocked-note", argv: j("item", "complete", "B03", "--commit", "{h1}", "--reason", "blocked", "--note", "waits on X. Related: [B01]"), want: 0},
		scn{name: "complete/done-ignores-note", argv: j("item", "complete", "B01", "--commit", "{h1}", "--note", "ignored"), want: 0},
		scn{name: "complete/already-completed", argv: j("item", "complete", "B08", "--commit", "{h1}"), want: 0,
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.changed", false) }},
		scn{name: "complete/unknown-id", argv: j("item", "complete", "B99", "--commit", "{h1}"), want: 3},
		scn{name: "complete/archived-id-not-found", fx: fx{archive: "plain"}, argv: j("item", "complete", "B05", "--commit", "{h1}"), want: 3},
		scn{name: "complete/bad-reason", argv: j("item", "complete", "B01", "--reason", "wontfix"), want: 2},
		scn{name: "complete/missing-id", argv: j("item", "complete"), want: 2},
		scn{name: "complete/no-head", fx: fx{noCommit: true}, argv: j("item", "complete", "B01", "--no-proof"), want: 5},
		scn{name: "complete/no-head-explicit-commit", fx: fx{noCommit: true}, argv: j("item", "complete", "B03", "--commit", "abc1234", "--no-proof"), want: 0},
		scn{name: "complete/no-counters-file", fx: fx{counters: "-"}, argv: j("item", "complete", "B03", "--commit", "{h1}", "--no-proof"), want: 0},
		scn{name: "complete/no-completed-section", fx: fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] Only.** x\n\n## Features\n- **[F01] [Major] f.** y\n"},
			argv: j("item", "complete", "B01", "--commit", "{h1}", "--no-proof"), want: 0},
		scn{name: "complete/section-after-completed", fx: fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] Only.** x\n\n## Completed\n- ~~**[B08] x.**~~ Done 2026-09-30 [`abc`]\n\n## Notes\nhello\n"},
			argv: j("item", "complete", "B01", "--commit", "{h1}", "--no-proof"), want: 0},
		scn{name: "complete/no-backlog", fx: fx{noBacklog: true}, argv: j("item", "complete", "B01", "--commit", "{h1}", "--no-proof"), want: 3,
			div: "the old helper crashes on a missing BACKLOG.md and the shim maps the traceback to 5; the contract says 3", refWant: 5},
		scn{name: "complete/last-line-no-newline", fx: fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] Last.** x"},
			argv: j("item", "complete", "B01", "--commit", "{h1}", "--no-proof"), want: 0},
		scn{name: "complete/issues-backend", fx: fx{config: issuesConfig}, goOnly: true, want: 5,
			argv: j("item", "complete", "12", "--commit", "abc1234")},
	)

	// ---- item field get / list
	for _, f := range []struct{ id, name, want string }{
		{"B01", "title", "First bug"}, {"B01", "detail", "`.hv/bugs/B01.md`"}, {"B01", "related", "[F01]"},
		{"B01", "milestone", "M01"}, {"B01", "since", "{h1}"}, {"B01", "reason", ""}, {"B03", "repos", "web"},
		{"B03", "subsystem", "capture"}, {"B04", "title", "Fix v1"}, {"B08", "reason", "done"},
		{"B09", "reason", "dropped"}, {"B09", "note", "no longer needed"}, {"F08", "title", "Done refactor feature"},
		{"T01", "title", "First task"},
	} {
		f := f
		add(variants(scn{name: "fieldget/" + f.id + "-" + f.name, argv: j("item", "field", "get", f.id, "--name", f.name), want: 0,
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.value", f.want) }})...)
	}
	add(
		scn{name: "fieldget/archived-title", fx: fx{archive: "plain"}, argv: j("item", "field", "get", "B05", "--name", "title"), want: 0},
		scn{name: "fieldget/archived-title-sectioned", fx: fx{archive: "sectioned"}, argv: j("item", "field", "get", "B05", "--name", "title"), want: 0},
		scn{name: "fieldget/archived-title-no-archive", argv: j("item", "field", "get", "B05", "--name", "title"), want: 3},
		scn{name: "fieldget/archived-reason", fx: fx{archive: "plain"}, argv: j("item", "field", "get", "F05", "--name", "reason"), want: 0},
		scn{name: "fieldget/unknown-id", argv: j("item", "field", "get", "B99", "--name", "title"), want: 3},
		scn{name: "fieldget/short-id-not-padded", argv: j("item", "field", "get", "B1", "--name", "title"), want: 3},
		scn{name: "fieldget/bad-name", argv: j("item", "field", "get", "B01", "--name", "color"), want: 2},
		scn{name: "fieldget/missing-name", argv: j("item", "field", "get", "B01"), want: 2},
		scn{name: "fieldget/no-backlog", fx: fx{noBacklog: true}, argv: j("item", "field", "get", "B01", "--name", "title"), want: 3},
		scn{name: "fieldget/title-without-period", fx: fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] No period here** body\n"},
			div: "a bullet title without a period is None for the old helper (prints None); the contract types value as string", refWant: 0,
			argv: j("item", "field", "get", "B01", "--name", "title"), want: 0,
			check: func(t *testing.T, e envl, ref run) { eq(t, e, "data.value", "") }},
	)
	add(variants(scn{name: "fieldlist/open", argv: j("item", "field", "list", "B01"), want: 0})...)
	add(
		scn{name: "fieldlist/done", argv: j("item", "field", "list", "B09"), want: 0},
		scn{name: "fieldlist/unknown", argv: j("item", "field", "list", "T99"), want: 3},
		scn{name: "fieldlist/task", argv: j("item", "field", "list", "T02"), want: 0},
	)

	// ---- item field set
	set := func(name, id, field, value string, want int, extra ...string) scn {
		return scn{name: "fieldset/" + name, argv: j(append([]string{"item", "field", "set", id, "--name", field, "--value", value}, extra...)...), want: want}
	}
	add(variants(set("milestone-set", "B03", "milestone", "M09", 0))...)
	add(
		set("milestone-idempotent", "B03", "milestone", "M02", 0),
		set("milestone-clear", "B03", "milestone", "", 0),
		set("milestone-add-new", "B04", "milestone", "M05", 0),
		set("related-replace", "B02", "related", "[F02]", 0),
		set("related-clear", "B02", "related", "", 0),
		set("repos", "B01", "repos", "web,api", 0),
		set("subsystem-add", "B01", "subsystem", "io", 0),
		set("clear-absent-field", "B04", "subsystem", "", 0),
		set("dash-value", "B04", "related", "--weird", 0),
		set("detail-existing-file", "B04", "detail", ".hv/features/F01.md", 0),
		set("detail-backticked", "B04", "detail", "`.hv/features/F01.md`", 0),
		set("detail-clear", "B01", "detail", "", 0),
		set("detail-missing-file", "B04", "detail", ".hv/features/nope.md", 3),
		set("detail-only-backticks", "B04", "detail", "``", 2),
		set("closed-item", "B08", "milestone", "M01", 4),
		set("unknown-id", "B99", "milestone", "M01", 3),
		set("read-only-field", "B01", "since", "abc", 2),
		set("unknown-field", "B01", "colour", "red", 2),
		scn{name: "fieldset/missing-value", argv: j("item", "field", "set", "B01", "--name", "milestone"), want: 2},
		scn{name: "fieldset/missing-name", argv: j("item", "field", "set", "B01", "--value", "x"), want: 2},
		scn{name: "fieldset/no-backlog", fx: fx{noBacklog: true}, argv: j("item", "field", "set", "B01", "--name", "milestone", "--value", "x"), want: 3},
		scn{name: "fieldset/issues-detail-refused", fx: fx{config: issuesConfig}, goOnly: true, want: 4,
			argv:  j("item", "field", "set", "12", "--name", "detail", "--value", "x"),
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.blockedBy", "backend") }},
	)
	add(scn{name: "fieldset/archived-item-plain", fx: fx{archive: "plain"}, argv: j("item", "field", "set", "B05", "--name", "milestone", "--value", "M01"), want: 4},
		scn{name: "fieldset/archived-item-sectioned", fx: fx{archive: "sectioned"}, argv: j("item", "field", "set", "B05", "--name", "milestone", "--value", "M01"), want: 4},
		set("archived-item-not-in-archive", "B05", "milestone", "M01", 3))
	// the closed-item failure data comes from the shim as well
	for i := range all {
		if all[i].name == "fieldset/closed-item" {
			all[i].check = func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.blockedBy", "closed item")
				eq(t, e, "data.changed", false)
			}
		}
	}

	// ---- item reopen (old helper: hv-uncomplete)
	reopen := func(name, id string, f fx, want int, chk func(*testing.T, envl, run)) scn {
		return scn{name: "reopen/" + name, fx: f, argv: j("item", "reopen", id), old: []string{"hv-uncomplete", id}, want: want, check: chk}
	}
	changed := func(v bool) func(*testing.T, envl, run) {
		return func(t *testing.T, e envl, _ run) { eq(t, e, "data.changed", v) }
	}
	add(variants(reopen("done-bug", "B08", fx{}, 0, changed(true)))...)
	add(
		reopen("refactor-commit-no-decrement", "F08", fx{}, 0, changed(true)),
		reopen("task-no-decrement", "T08", fx{}, 0, changed(true)),
		reopen("unresolvable-hash", "B09", fx{}, 0, changed(true)),
		reopen("already-active", "B01", fx{}, 0, changed(false)),
		reopen("unknown", "B99", fx{}, 3, nil),
		reopen("no-backlog", "B08", fx{noBacklog: true}, 3, nil),
		reopen("no-counters-file", "B08", fx{counters: "-"}, 0, changed(true)),
		reopen("target-section-missing", "T08", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] x.** y\n\n## Completed\n- ~~**[T08] Done task.** body~~ Done 2026-09-30 [`{h1}`]\n"}, 0, changed(true)),
		reopen("target-section-empty", "T08", fx{backlog: "# TODO\n\n## Tasks\n\n## Completed\n- ~~**[T08] Done task.** body~~ Done 2026-09-30 [`{h1}`]\n"}, 0, changed(true)),
		reopen("no-completed-heading-active", "B01", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] x.** y\n"}, 0, changed(false)),
		reopen("from-plain-archive", "B05", fx{archive: "plain"}, 0, changed(true)),
		reopen("from-sectioned-archive", "F05", fx{archive: "sectioned"}, 0, changed(true)),
		reopen("archive-missing", "B05", fx{}, 3, nil),
		scn{name: "reopen/issues-refused-5", fx: fx{config: issuesConfig}, goOnly: true, want: 5, argv: j("item", "reopen", "12")},
	)

	// ---- item rm (old helper: hv-rm)
	rmPlan := func(name string, f fx, ids string, apply bool, scrub bool, want int, chk func(*testing.T, envl, run)) scn {
		argv := []string{"item", "rm"}
		old := []string{"hv-rm"}
		if apply {
			argv = append(argv, "--apply")
			// An active ID: the contract refuses --apply (exit 4, old rc 2 without --force);
			// old --force would strip the stream instead. Compare against the refusal.
			if want != 4 || f.status == "" {
				old = append(old, "--force")
			}
		}
		if scrub {
			argv = append(argv, "--scrub-archive")
			old = append(old, "--scrub-archive")
		}
		ids2 := strings.Split(ids, ",")
		argv = append(argv, ids2...)
		old = append(old, ids)
		return scn{name: "rm/" + name, fx: f, argv: j(argv...), old: old, want: want, check: chk}
	}
	add(variants(rmPlan("preview-b01", fx{}, "B01", false, false, 0, func(t *testing.T, e envl, _ run) {
		eq(t, e, "data.applied", false)
		eq(t, e, "data.changed", false)
		eq(t, e, "data.items.0.crossRefs", float64(4)) // B02, F01, F02 (strict Related lines) and the done B09
		eq(t, e, "data.items.0.detailFile", ".hv/bugs/B01.md")
		eq(t, e, "data.items.0.todoEntry", true)
		eq(t, e, "warnings.0", "preview only; pass --apply")
	}))...)
	add(variants(rmPlan("apply-b01", fx{}, "B01", true, false, 0, func(t *testing.T, e envl, _ run) {
		eq(t, e, "data.applied", true)
		eq(t, e, "data.changed", true)
	}))...)
	add(variants(rmPlan("apply-b01-scrub", fx{}, "B01", true, true, 0, nil))...)
	add(
		rmPlan("apply-two-sharing-related", fx{}, "B01,F01", true, false, 0, nil),
		rmPlan("apply-three-with-plans", fx{}, "B02,F01,T01", true, false, 0, func(t *testing.T, e envl, _ run) {
			eq(t, e, "data.items.1.planFiles", []any{".hv/plans/M02-F01.md"})
			eq(t, e, "data.items.0.planFiles", []any{".hv/plans/M01-B02.md"})
		}),
		rmPlan("apply-task", fx{}, "T02", true, false, 0, nil),
		rmPlan("apply-completed-item", fx{}, "B09", true, false, 0, nil),
		rmPlan("apply-related-keeps-others", fx{}, "F01", true, false, 0, nil),
		rmPlan("preview-two", fx{}, "B03,T01", false, false, 0, nil),
		rmPlan("apply-no-newline-at-eof", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] x.** a\n\n## Completed\n- ~~**[B08] y.** z Related: [B01]~~ Done 2026-09-30 [`abc`]"},
			"B08", true, false, 0, nil),
		rmPlan("related-keeps-the-others", relFx, "B01", true, false, 0, nil),
		rmPlan("related-keeps-the-others-two-removed", relFx, "B01,F01", true, false, 0, nil),
		rmPlan("related-no-space-after-comma", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n- **[B02] [P2] b.** y Related: [B01],[F01],[T01] Since: {h1}\n\n## Features\n- **[F01] [Major] f.** z\n"},
			"B01", true, false, 0, nil),
		rmPlan("related-middle-field", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n- **[B02] [P2] b.** y Related: [B01] Milestone: M01 Since: {h1}\n"},
			"B01", true, false, 0, nil),
		rmPlan("related-no-space-after-colon", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n- **[B02] [P2] b.** y Related:[B01] Milestone: M01\n"},
			"B01", true, false, 0, nil),
		rmPlan("related-only-self", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x Related: [B01]\n\n- **[B02] [P2] b.** y\n"},
			"B01", true, false, 0, nil),
		rmPlan("blank-line-after-bullet-collapses", fx{backlog: "# TODO\n\n## Bugs\n- **[B01] [P1] a.** x\n\n## Features\n- **[F01] [Major] f.** z\n"},
			"B01", true, false, 0, nil),
		rmPlan("unknown", fx{}, "B99", true, false, 3, nil),
		rmPlan("one-unknown-among-known", fx{}, "B01,B99", true, false, 3, nil),
		rmPlan("no-backlog", fx{noBacklog: true}, "B01", true, false, 3, nil),
		rmPlan("plain-archive-entry-not-found", fx{archive: "plain"}, "B05", true, true, 3, nil),
		rmPlan("sectioned-archive-without-scrub", fx{archive: "sectioned"}, "B05", true, false, 0, func(t *testing.T, e envl, _ run) {
			eq(t, e, "data.items.0.archive", true)
			eq(t, e, "data.items.0.todoEntry", false)
		}),
		rmPlan("sectioned-archive-with-scrub", fx{archive: "sectioned"}, "B05", true, true, 0, nil),
		rmPlan("sectioned-archive-scrub-other-item", fx{archive: "sectioned"}, "B01", true, true, 0, func(t *testing.T, e envl, _ run) {
			eq(t, e, "data.items.0.crossRefs", float64(5))
		}),
		rmPlan("active-branch-apply-refused", fx{status: "{\n  \"active\": [\n    {\n      \"branch\": \"feat/x\",\n      \"items\": [\"B01\"]\n    }\n  ]\n}\n"},
			"B01", true, false, 4, func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.blockedBy", "active")
				eq(t, e, "data.id", "B01")
				eq(t, e, "data.activeBranch", "feat/x")
				eq(t, e, "data.changed", false)
			}),
		rmPlan("active-csv-items-apply-refused", fx{status: "{\n  \"active\": [\n    {\n      \"branch\": \"feat/y\",\n      \"items\": \"B03, T01\"\n    }\n  ]\n}\n"},
			"T01", true, false, 4, nil),
		rmPlan("status-other-item-not-blocking", fx{status: "{\n  \"active\": [\n    {\n      \"branch\": \"feat/z\",\n      \"items\": [\"F02\"]\n    }\n  ]\n}\n"},
			"B03", true, false, 0, nil),
		scn{name: "rm/preview-active-shows-branch", fx: fx{status: "{\n  \"active\": [\n    {\n      \"branch\": \"feat/x\",\n      \"items\": [\"B01\"]\n    }\n  ]\n}\n"},
			argv: j("item", "rm", "B01"), old: []string{"hv-rm", "B01"}, want: 0, div: "the contract previews an active ID and exits 0; the old helper refuses the preview with rc 2", refWant: 4,
			check: func(t *testing.T, e envl, _ run) {
				eq(t, e, "data.items.0.activeBranch", "feat/x")
				eq(t, e, "data.applied", false)
			}},
		scn{name: "rm/issues-backend-refused", fx: fx{config: issuesConfig}, argv: j("item", "rm", "--apply", "B01"), old: []string{"hv-rm", "--force", "B01"}, want: 4,
			check: func(t *testing.T, e envl, _ run) { eq(t, e, "data.blockedBy", "backend") }},
		scn{name: "rm/no-ids", argv: j("item", "rm"), goOnly: true, want: 2},
		scn{name: "rm/blank-ids", argv: j("item", "rm", " , "), goOnly: true, want: 2},
	)

	// ---- item shipped (old helper: hv-capture-audit)
	shippedMap := func(rc int, _ string) int { // contract: old 2 (evidence) -> 0, 0 -> 1, 1 -> 2
		switch rc {
		case 2:
			return 0
		case 0:
			return 1
		}
		return 2
	}
	shipped := func(name string, want int, titles ...string) scn {
		return scn{name: "shipped/" + name, fx: fx{commits: map[bool]int{true: 5}[strings.HasPrefix(name, "many-commits")]}, argv: j(append([]string{"item", "shipped"}, titles...)...),
			old: append([]string{"hv-capture-audit"}, titles...), oldMap: shippedMap, want: want,
			check: func(t *testing.T, e envl, ref run) { compareAudit(t, e, ref) }}
	}
	add(
		shipped("strong-distinct", 0, "Add `parser-core` and lexer-v2 support"),
		shipped("path-hit", 0, "Update `src/main.go` handling"),
		shipped("path-and-commit", 0, "Rework `src/main.go` for `parser-core` lexer-v2"),
		shipped("none", 1, "Reticulate the quantum splines"),
		shipped("two-titles-one-hit", 0, "Reticulate splines", "Add `parser-core` and lexer-v2 support"),
		shipped("medium-common-tokens", 0, "Refactor tidy lexer"),
		shipped("stopwords-only", 1, "add the new fix"),
		shipped("blank-title-ignored", 0, "   ", "Add `parser-core` support lexer-v2"),
		shipped("path-with-space-ignored", 1, "Check `src/some file.go` thing"),
		shipped("dotted-token", 0, "Handle `README.md` in lexer"),
		shipped("many-commits-caps-at-three", 0, "Add `parser-core` and lexer-v2 support"),
		shipped("many-commits-medium", 0, "Add parser lexer support"),
		shipped("many-titles", 0, "Add `parser-core` lexer-v2", "Update `src/main.go`", "Nothing relevant zzz"),
		scn{name: "shipped/no-titles", argv: j("item", "shipped"), old: []string{"hv-capture-audit"}, oldMap: shippedMap, want: 2},
		scn{name: "shipped/only-blank", argv: j("item", "shipped", "  "), old: []string{"hv-capture-audit", "  "}, oldMap: shippedMap, want: 2},
	)

	// ---- item ready (old helper: hv-item-ready)
	readyMap := func(rc int, stderr string) int {
		if rc == 1 && !strings.Contains(stderr, "error:") {
			return 1
		}
		return mapOld(rc, stderr)
	}
	ready := func(name, id string, f fx, want int, reasons ...string) scn {
		return scn{name: "ready/" + name, fx: f, argv: j("item", "ready", id), old: []string{"hv-item-ready", id}, oldMap: readyMap, want: want,
			check: func(t *testing.T, e envl, ref run) {
				if want == 3 {
					return
				}
				eq(t, e, "data.ready", want == 0)
				got := []string{}
				for _, r := range at(e, "data.reasons").([]any) {
					got = append(got, r.(string))
				}
				var old []string
				for _, l := range strings.Split(strings.TrimSpace(ref.stdout), "\n") {
					if l != "" {
						old = append(old, l)
					}
				}
				if !reflect.DeepEqual(got, append([]string{}, old...)) && !(len(got) == 0 && len(old) == 0) {
					t.Errorf("reasons = %v, old stdout implies %v", got, old)
				}
			}}
	}
	add(variants(ready("criteria-in-detail", "B01", fx{}, 0))...)
	add(variants(ready("not-ready", "B03", fx{}, 1))...)
	add(
		ready("design-note", "F02", fx{}, 0),
		ready("plan-note", "B02", fx{}, 0),
		ready("detail-without-criteria", "F01", fx{files: map[string]string{".hv/plans/M02-F01.md": ""}}, 1),
		ready("checkbox-line", "T01", fx{files: map[string]string{".hv/tasks/T01.md": "# T01\n\n  * [x] done thing\n"}}, 0),
		ready("heading-acceptance-lowercase", "T02", fx{files: map[string]string{".hv/tasks/T02.md": "# T02\n\n### acceptance criteria\ntext\n"}}, 0),
		ready("heading-needs-level", "T02", fx{files: map[string]string{".hv/tasks/T02.md": "# T02\n\nacceptance but no heading\n"}}, 1),
		ready("completed-item", "B08", fx{}, 1),
		ready("unknown", "B99", fx{}, 3),
		ready("archived", "B05", fx{archive: "plain"}, 1),
		ready("archived-missing", "B05", fx{}, 3),
	)

	// ---- item comment add (old helper: hv-item-comment)
	cAdd := func(name, id, kind, body string, f fx, want int, extra ...string) scn {
		argv := append([]string{"item", "comment", "add", id, "--kind", kind, "--body-file", "-"}, extra...)
		return scn{name: "commentadd/" + name, fx: f, in: body, argv: j(argv...), want: want,
			old: []string{"hv-item-comment", id, "--kind", kind, "--body-file", "-"}}
	}
	add(variants(cAdd("existing-log", "B01", "decision", "Ship it.", fx{}, 0))...)
	add(
		cAdd("multi-line", "B01", "question", "First line\nsecond line\n\nfourth after blank\n", fx{}, 0),
		cAdd("crlf-body", "B01", "feedback", "one\r\ntwo\r\n", fx{}, 0),
		cAdd("detail-without-log", "F01", "answer", "Because.", fx{}, 0),
		cAdd("creates-detail-file", "B03", "question", "Is this needed?", fx{}, 0),
		cAdd("creates-task-detail", "T01", "decision", "Do it.", fx{}, 0),
		cAdd("log-not-last-section", "B03", "answer", "x", fx{files: map[string]string{".hv/bugs/B03.md": "# B03\n\n## Log\n- 2026-01-01 · question · q\n\n## Notes\nn\n"}}, 0),
		cAdd("done-item", "B08", "feedback", "late note", fx{}, 0),
		cAdd("archived-item", "B05", "feedback", "late note", fx{archive: "plain"}, 0),
		cAdd("empty-body", "B01", "question", "  \n\n", fx{}, 2),
		cAdd("bad-kind", "B01", "remark", "x", fx{}, 2),
		cAdd("unknown-id", "B99", "question", "x", fx{}, 3),
		cAdd("no-backlog", "B01", "question", "x", fx{noBacklog: true}, 3),
		scn{name: "commentadd/missing-body-file", argv: j("item", "comment", "add", "B01", "--kind", "question"), want: 2,
			old: []string{"hv-item-comment", "B01", "--kind", "question"}},
		scn{name: "commentadd/issues-5", fx: fx{config: issuesConfig}, goOnly: true, want: 5, in: "x",
			argv: j("item", "comment", "add", "12", "--kind", "question", "--body-file", "-")},
	)

	// ---- item comment list (old helper: hv-item-comment --list)
	cList := func(name, id, kind string, f fx, want int) scn {
		argv := []string{"item", "comment", "list", id}
		old := []string{"hv-item-comment", id, "--list"}
		if kind != "" {
			argv = append(argv, "--kind", kind)
			old = append(old, "--kind", kind)
		}
		return scn{name: "commentlist/" + name, fx: f, argv: j(argv...), old: old, want: want,
			check: func(t *testing.T, e envl, ref run) {
				if want != 0 {
					return
				}
				var rows []string
				for _, c := range at(e, "data.comments").([]any) {
					first, rest, _ := strings.Cut(c.(map[string]any)["text"].(string), "\n")
					rows = append(rows, fmt.Sprintf("- %s · %s · %s", c.(map[string]any)["who"], c.(map[string]any)["kind"], first))
					if rest != "" || strings.Contains(c.(map[string]any)["text"].(string), "\n") {
						for _, l := range strings.Split(rest, "\n") {
							if strings.TrimSpace(l) != "" {
								rows = append(rows, "  "+l)
							} else {
								rows = append(rows, "")
							}
						}
					}
				}
				if got := strings.Join(rows, "\n"); got != strings.TrimRight(ref.stdout, "\n") {
					t.Errorf("rendered rows differ\ngo:  %q\nold: %q", got, ref.stdout)
				}
			}}
	}
	add(variants(cList("all", "B01", "", fx{}, 0))...)
	add(
		cList("filter-question", "B01", "question", fx{}, 0),
		cList("filter-none", "B01", "feedback", fx{}, 0),
		cList("no-log", "F01", "", fx{}, 0),
		cList("no-detail", "B03", "", fx{}, 0),
		cList("bad-kind", "B01", "remark", fx{}, 2),
		cList("unknown", "B99", "", fx{}, 3),
		cList("done-item-no-detail", "B08", "", fx{}, 0),
		cList("task", "T01", "", fx{files: map[string]string{".hv/tasks/T01.md": "# T01\n\n## Log\n- 2026-02-02 · decision · a\n  b\n\n  c\n- 2026-02-03 · answer · d\n"}}, 0),
	)

	seen := map[string]bool{}
	for _, s := range all {
		if seen[s.name] {
			t.Fatalf("duplicate scenario name %q", s.name)
		}
		seen[s.name] = true
	}
	if len(all) < 60 {
		t.Fatalf("only %d scenarios", len(all))
	}
	t.Logf("%d scenarios", len(all))
	for _, s := range all {
		s := s
		t.Run(s.name, s.exec)
	}
}

// compareAudit checks the Go `item shipped` data against the report the old
// helper printed: the same titles with hits, the same hits in the same order.
func compareAudit(t *testing.T, e envl, ref run) {
	t.Helper()
	var want []string
	var cur string
	for _, l := range strings.Split(ref.stdout, "\n") {
		switch {
		case strings.HasPrefix(l, "=== "):
			cur = strings.TrimSuffix(strings.TrimPrefix(l, "=== "), " ===")
			want = append(want, "T "+cur)
		case strings.HasPrefix(l, "  [STRONG] "), strings.HasPrefix(l, "  [MEDIUM] "):
			lvl := strings.ToLower(l[3:9])
			body := l[len("  [STRONG] "):]
			i := strings.LastIndex(body, "  (tokens: ")
			oneline, tokens := body[:i], strings.TrimSuffix(body[i+len("  (tokens: "):], ")")
			hash, subject, _ := strings.Cut(oneline, " ")
			want = append(want, fmt.Sprintf("%s %s|%s|%s", lvl, hash, subject, tokens))
		case strings.HasPrefix(l, "  [PATH]   "):
			tok, p, _ := strings.Cut(l[len("  [PATH]   "):], " → ")
			want = append(want, fmt.Sprintf("path %s|%s", tok, p))
		}
	}
	var got []string
	titles, _ := at(e, "data.titles").([]any)
	for _, ti := range titles {
		m := ti.(map[string]any)
		hits, _ := m["hits"].([]any)
		if len(hits) == 0 {
			continue
		}
		got = append(got, "T "+m["title"].(string))
		for _, hh := range hits {
			h := hh.(map[string]any)
			switch h["level"] {
			case "path":
				got = append(got, fmt.Sprintf("path %s|%s", h["token"], h["path"]))
			default:
				var toks []string
				for _, x := range h["tokens"].([]any) {
					toks = append(toks, x.(string))
				}
				got = append(got, fmt.Sprintf("%s %s|%s|%s", h["level"], h["hash"], h["subject"], strings.Join(toks, ", ")))
			}
		}
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("audit differs from the old report\ngo:   %q\nold:  %q\nreport:\n%s", got, want, ref.stdout)
	}
	if found := at(e, "data.found"); found != (len(want) > 0) {
		t.Errorf("data.found = %v with %d report entries", found, len(want))
	}
}
