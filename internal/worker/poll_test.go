package worker

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/pytest"
)

// paneFixtures are static pane texts covering every rule of the classifier,
// including the edge cases the rules are written around.
var paneFixtures = map[string]string{
	"blank":               "",
	"idle":                "  claude ready\n> \n",
	"done url":            "work\nHV-DONE w1 https://github.com/o/r/pull/12\n",
	"done branch":         "HV-DONE w1 hv-worker/w1-t1\n",
	"done bare":           "HV-DONE w1\nnext line\n",
	"done multiline":      "HV-DONE w1\nsomething after\n",
	"blocked":             "HV-BLOCKED w1: which of A or B?\n",
	"blocked + done":      "HV-DONE w1 x\nHV-BLOCKED w1: still a question\n",
	"blocked indent":      "   HV-BLOCKED   w1 :   spaced out  \n",
	"retry":               "API Error: Overloaded\nRetrying in 4 seconds\n",
	"api error":           "doing things\nAPI Error: 529 Overloaded\n",
	"crashed":             "Resume this session with: claude --resume abc\n",
	"limit":               "You've hit your usage limit. resets at 5pm\n",
	"limit funds":         "You've hit your limit\nAdd funds to continue\n",
	"limit approaching":   "Approaching usage limit\n",
	"limit reset":         "limit will reset at 3am\n",
	"limit prose":         "I read the rate limit code in limiter.go\n",
	"permission":          "Do you want to proceed?\n 1. Yes\n 2. No, and tell Claude what to do differently\n",
	"permission allow":    "Allow Bash(git push) to run?\n",
	"permission dont":     "Yes, and don't ask again for this\n",
	"sentinel over limit": "reached your usage limit\nHV-DONE w1 https://gitlab.com/o/r/-/merge_requests/3\n",
	"unicode":             "héllo wörld — ünïcode ✓\n❯ \n",
	"crlf":                "HV-BLOCKED w1: windows\r\nline\r\n",
	"long limit line":     "usage limit reached " + strings.Repeat("x", 200) + "\n",
}

// TestClassify checks every pane fixture under every polled status against the
// state and evidence the retired shell classifier gave.
func TestClassify(t *testing.T) {
	statuses := []string{"", "idle", "working", "blocked", "done", "unknown", "gone"}
	var want map[string][2]string // "<pane>/<status>" -> state, evidence
	pytest.Golden(t, map[string]any{"panes": paneFixtures, "statuses": statuses, "argv": "--fixture <pane> --slot w1 [--status <status>]"}, &want)
	for name, text := range paneFixtures {
		for _, status := range statuses {
			t.Run(name+"/"+status, func(t *testing.T) {
				old, ok := want[name+"/"+status]
				if !ok {
					t.Fatal("no recorded result")
				}
				state, evidence := Classify(text, false, 60, status)
				if state != old[0] || evidence != old[1] {
					t.Errorf("go %s %q, golden %s %q", state, evidence, old[0], old[1])
				}
			})
		}
	}
}

func TestClassifyMovementAndTailWindow(t *testing.T) {
	if st, ev := Classify("anything\n", true, 60, ""); st != StateBusy || ev != "pane changed between captures" {
		t.Errorf("moved: %s %q", st, ev)
	}
	// a sentinel outranks movement
	if st, _ := Classify("HV-DONE w1 hv-worker/w1\n", true, 60, "working"); st != StateDone {
		t.Errorf("sentinel vs movement: %s", st)
	}
	// LIMITED outranks movement
	if st, _ := Classify("usage limit reached\n", true, 60, ""); st != StateLimited {
		t.Errorf("limit vs movement: %s", st)
	}
	// only the last N lines count
	text := "HV-DONE w1 old\n" + strings.Repeat("noise\n", 80)
	if st, _ := Classify(text, false, 60, ""); st != StateIdle {
		t.Errorf("a sentinel scrolled out of the window still counted: %s", st)
	}
	if st, _ := Classify(text, false, 100, ""); st != StateDone {
		t.Errorf("a sentinel inside the window was missed: %s", st)
	}
}

func TestPollFixtureMode(t *testing.T) {
	fx := filepath.Join(t.TempDir(), "p.txt")
	os.WriteFile(fx, []byte("HV-BLOCKED w1: ?\n"), 0o644)
	res, err := PollFixture(fx, "", "", 0)
	if err != nil || len(res.Slots) != 1 || res.Slots[0].Name != "fixture" || res.Slots[0].State != StateBlocked || res.Changed {
		t.Errorf("%+v %v", res, err)
	}
	if res, _ = PollFixture(fx, "w3", "", 0); res.Slots[0].Name != "w3" {
		t.Errorf("name = %s", res.Slots[0].Name)
	}
	if _, err = PollFixture("/no/such/file", "", "", 0); exitOf(err) != ExitUsage {
		t.Errorf("missing fixture: %v", err)
	}
}

func pollRegistry(t *testing.T, kind string) (string, *fakeHost) {
	dir := newProject(t, `{}`)
	goInit(t, dir, InitOpts{Slots: 2, Base: "main"})
	f := &fakeHost{name: kind, inSession: true, panes: map[string][]string{}, status: map[string]string{}}
	return dir, f
}

func TestPollRecordsStateAndPRURL(t *testing.T) {
	dir, f := pollRegistry(t, "tmux")
	f.panes["w1"] = []string{"static\n", "static\nHV-DONE w1 https://github.com/o/r/pull/9\n"}
	f.panes["w2"] = []string{"a\n", "a\n"}
	before, _ := os.ReadFile(RegistryPath(dir))
	res, err := envWith(f).Poll(bg, dir, PollOpts{Lines: 60})
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Slots) != 2 || res.Slots[0] != (PollRow{"w1", StateDone, "https://github.com/o/r/pull/9"}) ||
		res.Slots[1] != (PollRow{"w2", StateIdle, "static pane, no sentinel"}) || !res.Changed {
		t.Errorf("%+v", res)
	}
	if got := slotField(t, dir, "w1", "state"); got != "done" {
		t.Errorf("state = %s", got)
	}
	if got := slotField(t, dir, "w1", "pr"); got != "https://github.com/o/r/pull/9" {
		t.Errorf("pr = %s", got)
	}
	if got := slotField(t, dir, "w2", "pr"); got != "<null>" {
		t.Errorf("pr = %s", got)
	}
	after, _ := os.ReadFile(RegistryPath(dir))
	if string(before) == string(after) {
		t.Error("registry unchanged")
	}
	// the same poll again changes nothing
	f.panes["w1"] = []string{"x\nHV-DONE w1 https://github.com/o/r/pull/9\n", "x\nHV-DONE w1 https://github.com/o/r/pull/9\n"}
	f.panes["w2"] = []string{"a\n", "a\n"}
	if res, _ = envWith(f).Poll(bg, dir, PollOpts{Lines: 60}); res.Changed {
		t.Error("an unchanged poll must report changed=false")
	}
}

// A branch name after HV-DONE must not become slot.pr: `gh pr merge` on a
// branch fails where the gate's local merge would have worked.
func TestPollOnlyURLShapedDoneBecomesThePR(t *testing.T) {
	dir, f := pollRegistry(t, "tmux")
	f.panes["w1"] = []string{"x\n", "HV-DONE w1 hv-worker/w1-t1\n"}
	f.panes["w2"] = []string{"x\n", "HV-DONE w2 https://example.com/not/a/pr\n"}
	envWith(f).Poll(bg, dir, PollOpts{Lines: 60})
	for _, s := range []string{"w1", "w2"} {
		if got := slotField(t, dir, s, "pr"); got != "<null>" {
			t.Errorf("%s pr = %s", s, got)
		}
		if got := slotField(t, dir, s, "state"); got != "done" {
			t.Errorf("%s state = %s", s, got)
		}
	}
}

func TestPollNamedSlotAndSettle(t *testing.T) {
	dir, f := pollRegistry(t, "tmux")
	f.panes["w2"] = []string{"a\n", "b\n"}
	res, err := envWith(f).Poll(bg, dir, PollOpts{Slot: "w2", Lines: 60})
	if err != nil || len(res.Slots) != 1 || res.Slots[0].State != StateBusy {
		t.Fatalf("%+v %v", res, err)
	}
	for _, c := range f.calls {
		if strings.Contains(c, "w1") {
			t.Errorf("polled an unnamed slot: %v", f.calls)
		}
	}
	if _, err = envWith(f).Poll(bg, dir, PollOpts{Slot: "w9"}); exitOf(err) != ExitResolution {
		t.Errorf("unknown slot: %v", err)
	}
}

func TestPollNotifiesOnTheTransitionOnly(t *testing.T) {
	dir, f := pollRegistry(t, "herdr")
	f.status["w1"] = "blocked"
	f.panes["w1"] = []string{"dialog\n", "dialog\n", "dialog\n", "dialog\n"}
	f.panes["w2"] = []string{"x\n", "x\n", "x\n", "x\n"}
	e := envWith(f)
	if _, err := e.Poll(bg, dir, PollOpts{Lines: 60}); err != nil {
		t.Fatal(err)
	}
	if _, err := e.Poll(bg, dir, PollOpts{Lines: 60}); err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, c := range f.calls {
		if strings.HasPrefix(c, "notify hv worker w1: NEEDS-PERMISSION") {
			n++
		}
	}
	if n != 1 {
		t.Errorf("notifications = %d, want 1 (a poll loop must not ring every few seconds): %v", n, f.calls)
	}
	if got := slotField(t, dir, "w1", "state"); got != "needs-permission" {
		t.Errorf("state = %s", got)
	}
}

func TestPollHostFailureAndNoRegistry(t *testing.T) {
	dir := newProject(t, `{}`)
	f := tmuxFake()
	res, err := envWith(f).Poll(bg, dir, PollOpts{})
	if err != nil || len(res.Slots) != 0 || res.Changed {
		t.Errorf("no registry: %+v %v", res, err)
	}
	f.requireErr = fmt.Errorf("tmux is not installed")
	if _, err = envWith(f).Poll(bg, dir, PollOpts{}); exitOf(err) != ExitUnavailable {
		t.Errorf("host missing: %v", err)
	}
}
