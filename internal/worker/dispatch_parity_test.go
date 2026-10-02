package worker

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/host"
)

// These tests run the OLD shell helpers and the Go port against the same fake
// herdr/tmux scripts (test/fakes), then compare what reached the host (the
// fake's argv log, the prompt text) and .hv/workers.json. The fakes only write
// to a log, so nothing here can touch a live herdr server or tmux session.

var (
	tsRe  = regexp.MustCompile(`"ts": "[^"]*"`)
	bufRe = regexp.MustCompile(`(load-buffer -b \S+) \S+`)
)

func fakesDir(t *testing.T) string {
	d, err := filepath.Abs("../../test/fakes")
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func normalise(s, root string) string {
	s = strings.ReplaceAll(s, root, "ROOT")
	s = tsRe.ReplaceAllString(s, `"ts": "TS"`)
	return bufRe.ReplaceAllString(s, "$1 TMPFILE")
}

type hostRig struct {
	kind     string
	herdrDir string
	tmuxDir  string
	root     string
	env      []string // for the old helpers
	goEnv    Env
	hostEnv  map[string]string
}

// newRig builds a project and fake state dirs, and an Env whose host drives
// the same fake scripts the old helpers get on PATH.
func newRig(t *testing.T, kind string) *hostRig {
	t.Helper()
	cfg := `{}`
	if kind == "herdr" {
		cfg = `{"work":{"dispatch":"herdr"}}`
	}
	r := &hostRig{kind: kind, herdrDir: t.TempDir(), tmuxDir: t.TempDir(), root: newProject(t, cfg)}
	os.WriteFile(filepath.Join(r.tmuxDir, "pane"), []byte("? for shortcuts\n"), 0o644)
	r.env = []string{
		"PATH=" + fakesDir(t) + string(os.PathListSeparator) + os.Getenv("PATH"),
		"FAKE_HERDR=" + r.herdrDir, "FAKE_TMUX=" + r.tmuxDir,
		"HERDR_ENV=1", "HERDR_WORKSPACE_ID=w9", "HV_HOST_KILL_WAIT=2",
	}
	r.hostEnv = map[string]string{"HERDR_ENV": "1", "HERDR_WORKSPACE_ID": "w9"}
	run := fakeBinRunner(t, r.herdrDir, r.tmuxDir)
	r.goEnv = Env{
		NewHost: func(d string) host.Host { return host.New(d, hostDeps(run, r.hostEnv)) },
		Sleep:   func(time.Duration) {},
	}
	return r
}

func (r *hostRig) log(t *testing.T) string {
	dir := r.tmuxDir
	if r.kind == "herdr" {
		dir = r.herdrDir
	}
	b, _ := os.ReadFile(filepath.Join(dir, "log"))
	return string(b)
}

func (r *hostRig) lastPayload(t *testing.T) string {
	name := "payload"
	dir := r.tmuxDir
	if r.kind == "herdr" {
		name, dir = "last_prompt", r.herdrDir
	}
	b, _ := os.ReadFile(filepath.Join(dir, name))
	return string(b)
}

func TestDispatchParityWithTheOldHelpers(t *testing.T) {
	if testing.Short() {
		t.Skip("the old tmux path sleeps a few seconds per dispatch")
	}
	for _, kind := range []string{"herdr", "tmux"} {
		t.Run(kind, func(t *testing.T) {
			old, goR := newRig(t, kind), newRig(t, kind)
			runOld(t, old.root, old.env, "hv-worker-pool", "init", "--slots", "1", "--base", "main")
			goInit(t, goR.root, InitOpts{Slots: 1, Base: "main"})

			brief := writeBrief(t, "build the thing\nsecond line\n")
			relay := writeBrief(t, "\nuse option B\n")
			signed := writeBrief(t, "--- ORCHESTRATOR (round 9) ---\nsigned already\n")
			round3, round4, round9 := 3, 4, 9

			steps := []struct {
				name string
				old  []string
				go_  DispatchOpts
			}{
				{"first task", []string{"--task", "T1", "--round", "3"}, DispatchOpts{Task: "T1", Round: &round3}},
				{"re-dispatch kills and recreates", []string{"--task", "T2"}, DispatchOpts{Task: "T2"}},
				{"relay", []string{"--relay", "--round", "4"}, DispatchOpts{Relay: true, Round: &round4}},
				{"already signed", []string{"--task", "T3", "--round", "9"}, DispatchOpts{Task: "T3", Round: &round9}},
			}
			for _, st := range steps {
				file := brief
				if st.go_.Relay {
					file = relay
				}
				if st.name == "already signed" {
					file = signed
				}
				r := runOld(t, old.root, old.env, "hv-worker-dispatch", append([]string{"--slot", "w1", "--brief-file", file}, st.old...)...)
				if r.Code != 0 {
					t.Fatalf("%s: old exit %d\n%s", st.name, r.Code, r.Stderr)
				}
				o := st.go_
				o.Slot, o.BodyFile = "w1", file
				if _, err := goR.goEnv.Dispatch(bg, goR.root, o); err != nil {
					t.Fatalf("%s: go: %v", st.name, err)
				}
				mustEqual(t, st.name+": host log", normalise(old.log(t), old.root), normalise(goR.log(t), goR.root))
				mustEqual(t, st.name+": prompt", old.lastPayload(t), goR.lastPayload(t))
				mustEqual(t, st.name+": workers.json", normalise(registry(t, old.root), old.root), normalise(registry(t, goR.root), goR.root))
			}
		})
	}
}

func TestSessionEnsureParityTmux(t *testing.T) {
	if testing.Short() {
		t.Skip("the old tmux path sleeps a few seconds")
	}
	old, goR := newRig(t, "tmux"), newRig(t, "tmux")
	instr := writeBrief(t, "take over\n")
	r := runOld(t, old.root, old.env, "hv-worker-session", "ensure", "--session", "ops", "--instruction-file", instr)
	if r.Code != 0 || !strings.HasPrefix(r.Stdout, "handed off to tmux session 'ops'\n") {
		t.Fatalf("old: %+v", r)
	}
	st, err := goR.goEnv.SessionEnsure(bg, goR.root, SessionOpts{Session: "ops", BodyFile: instr})
	if err != nil || !st.HandedOff || st.Session != "ops" {
		t.Fatalf("go: %+v %v", st, err)
	}
	mustEqual(t, "host log", normalise(old.log(t), old.root), normalise(goR.log(t), goR.root))
	mustEqual(t, "instruction", old.lastPayload(t), goR.lastPayload(t))
}
