package main

// Frozen parity (#53, S7 prep). The parity suites compare the Go binary with
// the old helpers, which S7 deletes. Before that happens, every scenario that
// passes parity records what the Go side did into
// testdata/frozen/<suite>.jsonl: the exit code, the --json envelope, the plain
// text for text scenarios, a hash of every .hv/ file the run changed and a
// hash of the fake forge's database. Go agreed with the oracle on each
// recorded scenario, so the record stands in for the oracle.
//
// TestFrozen<Suite> runs the suite's own scenario table with the Go side only
// and compares each run against its record. It needs neither bin/ nor the
// shim; the forge suites still need python3 for test/fakes, which stay.
//
// Recording: HV_PARITY_FREEZE=1 go test ./cmd/hv -run '^TestParity' rewrites
// the files of the suites that ran (only while the oracle exists). To accept a
// deliberate change without the oracle, go test ./cmd/hv -run '^TestFrozenX$'
// -update-frozen rewrites the records from the current Go output. A suite's
// file holds one recording day: the fixtures commit at noon of that day and
// {dN} dates count back from it, so its git hashes and dates repeat. A
// TestFrozen run on another day re-runs its suite in a child process with the
// harness pinned to that day (HV_FROZEN_DAY), sets HV_TEST_TODAY so archive and
// stale measure age from it, and maps today's date in the output back to it.

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

// localDay is the local date the fixtures' {dN} tokens count back from.
var localDay = time.Now().Format("2006-01-02")

// realUTC and realLocal are the actual dates; the run under test stamps them.
var (
	realUTC   = startDay
	realLocal = localDay
)

// pinDay applies HV_FROZEN_DAY ("<utc>,<local>") from TestMain.
func pinDay() {
	if v := os.Getenv("HV_FROZEN_DAY"); v != "" {
		if utc, local, ok := strings.Cut(v, ","); ok {
			startDay, localDay = utc, local
		}
	}
}

var recording = os.Getenv("HV_PARITY_FREEZE") != ""

// updateFrozen accepts the Go side as it is now: TestFrozen rewrites the
// records instead of comparing. Review the jsonl diff before committing.
var updateFrozen = flag.Bool("update-frozen", false, "TestFrozen: rewrite testdata/frozen from the current Go output")

// frozenStep is one Go run of a scenario.
type frozenStep struct {
	Exit int               `json:"exit"`
	Env  any               `json:"env"`
	Text *string           `json:"text,omitempty"`
	Tree map[string]string `json:"tree,omitempty"` // changed .hv/ path -> content hash, or "deleted"
	DB   string            `json:"db,omitempty"`   // hash of the forge database(s) after the run
	// raw keeps what the hashes were taken of, for a readable failure.
	raw map[string]string
}

type frozenRec struct {
	Name  string       `json:"name"`
	Steps []frozenStep `json:"steps"`
}

type frozenHeader struct {
	UTC   string `json:"utc"`
	Local string `json:"local"`
}

type frozenFile struct {
	frozenHeader
	recs map[string]frozenRec
	used map[string]bool
	mu   sync.Mutex
}

func frozenPath(suite string) string {
	return filepath.Join(repoDir, "cmd", "hv", "testdata", "frozen", suite+".jsonl")
}

func loadFrozen(suite string) (*frozenFile, error) {
	f := &frozenFile{recs: map[string]frozenRec{}, used: map[string]bool{}}
	b, err := os.ReadFile(frozenPath(suite))
	if err != nil {
		return f, err
	}
	sc := bufio.NewScanner(bytes.NewReader(b))
	sc.Buffer(nil, 64<<20)
	for n := 0; sc.Scan(); n++ {
		if n == 0 {
			if err := json.Unmarshal(sc.Bytes(), &f.frozenHeader); err != nil {
				return f, fmt.Errorf("%s header: %v", suite, err)
			}
			continue
		}
		var r frozenRec
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return f, fmt.Errorf("%s line %d: %v", suite, n+1, err)
		}
		f.recs[r.Name] = r
	}
	return f, sc.Err()
}

func (f *frozenFile) write(suite string) error {
	names := make([]string, 0, len(f.recs))
	for n := range f.recs {
		names = append(names, n)
	}
	sort.Strings(names)
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.Encode(f.frozenHeader)
	for _, n := range names {
		enc.Encode(f.recs[n])
	}
	p := frozenPath(suite)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	return os.WriteFile(p, buf.Bytes(), 0o644)
}

// suiteOf splits a subtest name into the suite file and the scenario name:
// TestParityA4B/list/std and TestFrozenA4B/list/std are both a4b, list/std.
func suiteOf(t *testing.T) (suite, name string) {
	top, rest, _ := strings.Cut(t.Name(), "/")
	top = strings.TrimPrefix(strings.TrimPrefix(top, "TestParity"), "TestFrozen")
	return strings.ToLower(top), rest
}

// ---- recording -----------------------------------------------------------------

var recorded = struct {
	sync.Mutex
	m map[string]map[string]frozenRec
}{m: map[string]map[string]frozenRec{}}

// record keeps a passing scenario's Go side for writeRecords; a scenario that
// failed parity records nothing.
func record(t *testing.T, side func(t *testing.T) frozenRec) {
	t.Helper()
	if !recording || t.Failed() {
		return
	}
	keep(t, side)
}

func keep(t *testing.T, side func(t *testing.T) frozenRec) {
	t.Helper()
	r := side(t)
	if t.Failed() {
		return
	}
	suite, name := suiteOf(t)
	r.Name = name
	recorded.Lock()
	defer recorded.Unlock()
	if recorded.m[suite] == nil {
		recorded.m[suite] = map[string]frozenRec{}
	}
	recorded.m[suite][name] = r
}

// writeRecords merges what this run recorded into the suite files. A file from
// another day is replaced, never merged: one file, one fixture day. A whole
// suite run with -update-frozen replaces its file too, dropping stale records.
func writeRecords() error {
	recorded.Lock()
	defer recorded.Unlock()
	for suite, recs := range recorded.m {
		f, err := loadFrozen(suite)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		hdr := frozenHeader{startDay, localDay}
		whole := *updateFrozen && !strings.Contains(flag.Lookup("test.run").Value.String(), "/")
		if f.frozenHeader != hdr || whole {
			f.recs = map[string]frozenRec{}
		}
		f.frozenHeader = hdr
		for n, r := range recs {
			f.recs[n] = r
		}
		if err := f.write(suite); err != nil {
			return err
		}
		fmt.Fprintf(os.Stderr, "frozen: %s: recorded %d, %d in file\n", suite, len(recs), len(f.recs))
	}
	return nil
}

// ---- the frozen run --------------------------------------------------------------

var frozenOn *frozenFile

// runFrozen runs a parity suite's table against its record. parity is the
// suite's TestParity function; in frozen mode its scenarios run frozenCheck
// instead of the oracle comparison.
func runFrozen(t *testing.T, parity func(*testing.T)) {
	suite, _ := suiteOf(t)
	f, err := loadFrozen(suite)
	if err != nil {
		t.Fatalf("no frozen record for %s: %v (record with HV_PARITY_FREEZE=1 while bin/ exists)", suite, err)
	}
	if f.UTC != startDay || f.Local != localDay {
		if os.Getenv("HV_FROZEN_DAY") != "" {
			t.Fatalf("pinned day %s,%s but %s was recorded on %s,%s", startDay, localDay, suite, f.UTC, f.Local)
		}
		reexec(t, f.frozenHeader)
		return
	}
	frozenOn = f
	t.Cleanup(func() {
		frozenOn = nil
		if t.Failed() || *updateFrozen || strings.Contains(flag.Lookup("test.run").Value.String(), "/") {
			return
		}
		var stale []string
		for n := range f.recs {
			if !f.used[n] {
				stale = append(stale, n)
			}
		}
		sort.Strings(stale)
		if len(stale) > 0 {
			t.Errorf("%d records have no scenario (renamed or removed? re-record): %v", len(stale), stale)
		}
	})
	parity(t)
}

// reexec runs the one TestFrozen function in a child process pinned to the
// recording day.
func reexec(t *testing.T, day frozenHeader) {
	t.Helper()
	args := []string{"-test.run=^" + t.Name() + "$", "-test.count=1", "-test.timeout=30m"}
	if *updateFrozen {
		args = append(args, "-update-frozen")
	}
	if testing.Verbose() {
		args = append(args, "-test.v")
	}
	cmd := exec.Command(os.Args[0], args...)
	cmd.Env = append(os.Environ(), "HV_FROZEN_DAY="+day.UTC+","+day.Local)
	out, err := cmd.CombinedOutput()
	if err != nil || testing.Verbose() {
		t.Logf("pinned to %s,%s:\n%s", day.UTC, day.Local, out)
	}
	if err != nil {
		t.Fatalf("frozen run pinned to %s: %v", day.UTC, err)
	}
}

// frozenCheck compares a scenario's Go side with its record.
func frozenCheck(t *testing.T, side func(t *testing.T) frozenRec) {
	_, name := suiteOf(t)
	f := frozenOn
	f.mu.Lock()
	want, ok := f.recs[name]
	f.used[name] = true
	f.mu.Unlock()
	if !ok {
		if !*updateFrozen {
			t.Fatalf("scenario %q is not frozen (re-record with HV_PARITY_FREEZE=1)", name)
		}
	}
	if *updateFrozen {
		keep(t, side)
		return
	}
	got := side(t)
	if len(got.Steps) != len(want.Steps) {
		t.Fatalf("%d runs, record has %d", len(got.Steps), len(want.Steps))
	}
	for i, g := range got.Steps {
		w := want.Steps[i]
		tag := fmt.Sprintf("run %d", i+1)
		if g.Exit != w.Exit {
			t.Errorf("%s: exit = %d, frozen %d", tag, g.Exit, w.Exit)
		}
		if !reflect.DeepEqual(g.Env, w.Env) {
			gj, _ := json.Marshal(g.Env)
			wj, _ := json.Marshal(w.Env)
			t.Errorf("%s: envelope differs\nfrozen: %s\ngo:     %s", tag, wj, gj)
		}
		if !reflect.DeepEqual(g.Text, w.Text) {
			t.Errorf("%s: text differs\nfrozen: %q\ngo:     %q", tag, deref(w.Text), deref(g.Text))
		}
		for _, p := range unionKeys(g.Tree, w.Tree) {
			if g.Tree[p] != w.Tree[p] {
				t.Errorf("%s: %s: %s, frozen %s; go content:\n%s", tag, p, orNone(g.Tree[p]), orNone(w.Tree[p]), g.raw[p])
			}
		}
		if g.DB != w.DB {
			t.Errorf("%s: forge database %s, frozen %s; go database:\n%s", tag, g.DB, w.DB, g.raw["\x00db"])
		}
	}
}

func deref(s *string) string {
	if s == nil {
		return "<none>"
	}
	return *s
}

func orNone(s string) string {
	if s == "" {
		return "unchanged"
	}
	return s
}

func unionKeys(a, b map[string]string) []string {
	keys := map[string]bool{}
	for k := range a {
		keys[k] = true
	}
	for k := range b {
		keys[k] = true
	}
	out := make([]string, 0, len(keys))
	for k := range keys {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// ---- building a record -------------------------------------------------------

// frozenEnv pins the day archive and stale measure age from; a scenario's own
// HV_TEST_TODAY comes later and wins.
func frozenEnv(env []string) []string {
	return append([]string{"HV_TEST_TODAY=" + localDay}, env...)
}

var (
	stampRe   = regexp.MustCompile(`\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?(Z|[+-]\d\d:\d\d)?`)
	compactRe = regexp.MustCompile(`\b\d{8}T\d{6}\b`)
)

// normFrozen makes one run's output independent of when and where it ran:
// temp dirs become <T>, <TP> and <TMP>, today's date becomes the recording day, and
// timestamps on or after the recording day become <TS>.
func normFrozen(s string) string {
	if harnessTmp != "" {
		tmp := regexp.QuoteMeta(filepath.Join(harnessTmp, "tmp"))
		s = regexp.MustCompile(tmp+`/[^/"\s]+(/\d{3})?`).ReplaceAllStringFunc(s, func(m string) string {
			if strings.Count(m[len(harnessTmp):], "/") == 3 {
				return "<T>" // a t.TempDir()
			}
			return "<TP>" // the test's temp root, the parent of its t.TempDir()s
		})
		s = strings.ReplaceAll(s, harnessTmp, "<TMP>")
	}
	if realUTC != startDay {
		s = strings.ReplaceAll(s, realUTC, startDay)
	}
	if realLocal != localDay {
		s = strings.ReplaceAll(s, realLocal, localDay)
	}
	s = stampRe.ReplaceAllStringFunc(s, func(m string) string {
		if m[:10] >= startDay {
			return "<TS>"
		}
		return m
	})
	return compactRe.ReplaceAllString(s, "<TSC>")
}

func hashOf(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:8])
}

// newStep records one Go run: before is the fixture's .hv/ tree, dir the
// copy the run changed, db the forge database(s) after it (nil for none).
func newStep(t *testing.T, r run, before map[string]string, dir string, db any) frozenStep {
	t.Helper()
	st := frozenStep{Exit: r.code, raw: map[string]string{}}
	if err := json.Unmarshal([]byte(normFrozen(r.stdout)), &st.Env); err != nil {
		t.Fatalf("go stdout is not one JSON document: %v\nstdout: %q\nstderr: %s", err, r.stdout, r.stderr)
	}
	after := snapshot(t, dir)
	for _, p := range unionKeys(before, after) {
		b, inB := before[p]
		a, inA := after[p]
		switch {
		case !inA:
			st.put(p, "deleted", "")
		case !inB || a != b:
			n := normFrozen(a)
			st.put(p, hashOf(n), n)
		}
	}
	if db != nil && !reflect.ValueOf(db).IsNil() {
		raw, _ := json.MarshalIndent(db, "", " ")
		n := normFrozen(string(raw))
		st.DB = hashOf(n)
		st.raw["\x00db"] = n
	}
	return st
}

func (st *frozenStep) put(path, hash, content string) {
	if st.Tree == nil {
		st.Tree = map[string]string{}
	}
	st.Tree[path] = hash
	st.raw[path] = content
}

func (st *frozenStep) text(stdout string) {
	n := normFrozen(stdout)
	st.Text = &n
}

// ---- the Go side of each scenario kind ---------------------------------------

func (s scn) goSide(t *testing.T) frozenRec {
	t.Helper()
	base, in := s.fx.build(t)
	dir := copyTree(t, base)
	if s.prep != nil {
		s.prep(t, dir)
	}
	argv := subst(s.argv, in)
	env := frozenEnv(s.env)
	r := exec1e(t, filepath.Join(dir, s.cwd), s.in, env, s.goBin(), argv...)
	st := newStep(t, r, snapshot(t, base), dir, nil)
	if s.text {
		st.text(exec1e(t, filepath.Join(dir, s.cwd), s.in, env, s.goBin(), withoutJSON(argv)...).stdout)
	}
	return frozenRec{Steps: []frozenStep{st}}
}

func (s isc) goSide(t *testing.T) frozenRec {
	t.Helper()
	base, in, _ := s.fixture(t)
	dir := copyTree(t, base)
	dbPath := writeDB(t, seedDB())
	argv := subst(s.argv, in)
	env := frozenEnv(append([]string{"FAKE_TRACKER_DB=" + dbPath}, s.env...))
	r := envRun(t, dir, s.in, env, hvBin, argv...)
	st := newStep(t, r, snapshot(t, base), dir, readDB(t, dbPath))
	if s.textSame {
		st.text(envRun(t, dir, s.in, env, hvBin, withoutJSON(argv)...).stdout)
	}
	return frozenRec{Steps: []frozenStep{st}}
}

func (s dsc) goSide(t *testing.T) frozenRec {
	t.Helper()
	base, in, _, seed := s.fixture(t)
	dir := copyTree(t, base)
	dbPath := filepath.Join(t.TempDir(), "go.json")
	if seed != nil {
		raw, _ := json.Marshal(seed)
		if err := os.WriteFile(dbPath, raw, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	var rec frozenRec
	before := snapshot(t, base)
	for _, rn := range s.runs {
		r := envRun(t, dir, "", frozenEnv(append([]string{"FAKE_TRACKER_DB=" + dbPath}, rn.env...)), hvBin, subst(rn.argv, in)...)
		rec.Steps = append(rec.Steps, newStep(t, r, before, dir, readDB(t, dbPath)))
	}
	return rec
}

func (c ubcase) goSide(t *testing.T) frozenRec {
	t.Helper()
	base, repos := ubInit(t, c)
	dir := copyTree(t, base)
	dbDir := ubSeed(t, repos)
	env := frozenEnv(append([]string{"FAKE_TRACKER_DB_DIR=" + dbDir}, c.env...))
	r := envRun(t, filepath.Join(dir, c.cwd), c.in, env, hvBin, c.argv...)
	st := newStep(t, r, snapshot(t, base), dir, ubReadAll(t, dbDir, repos))
	if c.textSame {
		st.text(envRun(t, filepath.Join(dir, c.cwd), c.in, env, hvBin, withoutJSON(c.argv)...).stdout)
	}
	return frozenRec{Steps: []frozenStep{st}}
}

func withoutJSON(argv []string) []string {
	var out []string
	for _, a := range argv {
		if a != "--json" {
			out = append(out, a)
		}
	}
	return out
}

func TestFrozenA4(t *testing.T)             { runFrozen(t, TestParityA4) }
func TestFrozenA4B(t *testing.T)            { runFrozen(t, TestParityA4B) }
func TestFrozenA4C(t *testing.T)            { runFrozen(t, TestParityA4C) }
func TestFrozenA4D(t *testing.T)            { runFrozen(t, TestParityA4D) }
func TestFrozenA4Issue(t *testing.T)        { runFrozen(t, TestParityA4Issue) }
func TestFrozenA4Umbrella(t *testing.T)     { runFrozen(t, TestParityA4Umbrella) }
func TestFrozenA4UmbrellaFile(t *testing.T) { runFrozen(t, TestParityA4UmbrellaFile) }
