package round

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/backlog"
	"github.com/l4ci/hv-skills/v5/internal/host"
	"github.com/l4ci/hv-skills/v5/internal/roundcfg"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

// Workflow side of the fake board.
type boardFake struct {
	*fakeBacklog
	claims    map[string]string // id -> claim holder
	claimedBy string            // when set, Claim loses to this holder
	states    map[string]string
	notes     []string
}

func (b *boardFake) Claim(ref, claimID string) (bool, string, error) {
	if b.claimedBy != "" {
		return false, b.claimedBy, nil
	}
	if b.claims == nil {
		b.claims = map[string]string{}
	}
	b.claims[ref] = claimID
	return true, claimID, nil
}
func (b *boardFake) Release(ref, claimID string) (bool, error) {
	if b.claims[ref] == claimID {
		delete(b.claims, ref)
		return true, nil
	}
	return false, nil
}
func (b *boardFake) SetState(ref, state string) (bool, error) {
	if b.states == nil {
		b.states = map[string]string{}
	}
	if state == "none" {
		delete(b.states, ref)
	} else {
		b.states[ref] = state
	}
	return true, nil
}
func (b *boardFake) AddComment(ref, kind, text string) (string, error) {
	b.notes = append(b.notes, ref+": "+text)
	return "1", nil
}

// hostFake is a tmux host that accepts everything.
type hostFake struct {
	spawned []string
	sent    string
}

func (h *hostFake) Name() string    { return "tmux" }
func (h *hostFake) Require() error  { return nil }
func (h *hostFake) InSession() bool { return true }
func (h *hostFake) Where() string   { return "main" }
func (h *hostFake) Spawn(_ context.Context, o host.SpawnOpts) (string, error) {
	h.spawned = append(h.spawned, o.Slot+" "+o.Cwd)
	return "w1:t1", nil
}
func (h *hostFake) Send(_ context.Context, slot, handle, file string) error {
	b, _ := os.ReadFile(file)
	h.sent = string(b)
	return nil
}
func (h *hostFake) Capture(context.Context, string, string, int) string { return "" }
func (h *hostFake) Status(context.Context, string, string) string       { return "" }
func (h *hostFake) Kill(context.Context, string, string) error          { return nil }
func (h *hostFake) Notify(context.Context, string, string)              {}

type assignFixture struct {
	root string
	env  Env
	be   *boardFake
	host *hostFake
	set  roundcfg.Settings
}

func newAssignFixture(t *testing.T) *assignFixture {
	t.Helper()
	root := newRepo(t, nil)
	milestoneDoc(t, root, "M01", "active")
	if err := os.MkdirAll(filepath.Join(root, "references"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "references", "worker-contract.md"), []byte("contract"), 0o644); err != nil {
		t.Fatal(err)
	}
	h := &hostFake{}
	f := &assignFixture{root: root, host: h}
	f.env = Env{Git: worker.ExecGit, Base: "main", Lease: fakeLease("h", 100)}
	f.env.Worker = worker.Env{Git: worker.ExecGit, NewHost: func(string) host.Host { return h },
		Sleep: func(time.Duration) {}, Now: time.Now}
	fb := &fakeBacklog{}
	fb.add("12", "Add the round assign verb now please", "M01", false, "## Acceptance\n- [ ] works\n\nedits internal/cli/round.go")
	fb.add("13", "Second issue", "M01", false, "## Acceptance\n- [ ] ok\n\nalso edits internal/cli/round.go")
	fb.add("14", "No criteria", "M01", false, "")
	fb.ready = map[string][]string{"14": {"no acceptance criteria in the issue body", "no design or plan note"}}
	f.be = &boardFake{fakeBacklog: fb}
	f.set, _ = roundcfg.Load(os.TempDir())
	if _, err := f.env.Start(bg, root, startOpts(roundcfg.ScopeMilestone, 100)); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *assignFixture) assign(id, agent string, mod func(*AssignOpts)) (Assigned, error) {
	o := AssignOpts{ID: id, Agent: agent, HolderPID: 100, Settings: f.set, Getenv: func(string) string { return "" }}
	if mod != nil {
		mod(&o)
	}
	return f.env.Assign(bg, f.root, f.be, o)
}

func blockedBy(t *testing.T, err error) string {
	t.Helper()
	var b *BlockedError
	if !errors.As(err, &b) {
		t.Fatalf("want a BlockedError, got %v", err)
	}
	return b.By
}

func TestBranchName(t *testing.T) {
	for _, c := range []struct{ agent, id, title, want string }{
		{"ben", "59", "C3: hv round start / assign / wind-down with autonomy levels", "ben/59-c3-hv-round-start-assign"},
		{"dana", "B07", "Fix it!", "dana/b07-fix-it"},
		{"kit", "1", "", "kit/1"},
		{"kit", "2", "Supercalifragilisticexpialidocious-averyveryverylongwordhere", "kit/2-supercalifragilisticexpialidocious-avery"},
	} {
		if got := BranchName(c.agent, c.id, c.title); got != c.want {
			t.Errorf("%q: %q want %q", c.title, got, c.want)
		}
	}
}

func TestAssignMarksResetsAndDispatches(t *testing.T) {
	f := newAssignFixture(t)
	res, err := f.assign("12", "", func(o *AssignOpts) {
		o.Siblings = []string{"13"}
		bf := filepath.Join(t.TempDir(), "d.md")
		os.WriteFile(bf, []byte("m: use the lease"), 0o644)
		o.BodyFile = bf
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.Agent != "ben" || res.Branch != "ben/12-add-the-round-assign-verb" || !res.Dispatched || !res.Ready() {
		t.Fatalf("%+v", res)
	}
	if f.be.claims["12"] != "ben@1" || f.be.states["12"] != "in-progress" || len(f.be.notes) != 1 || !strings.Contains(f.be.notes[0], "ben") {
		t.Errorf("claim, state and comment: %+v %+v %v", f.be.claims, f.be.states, f.be.notes)
	}
	s := worker.LoadRegistry(f.root).Slot("ben")
	if worker.Str(s, "task") != "12" || worker.Str(s, "claimId") != "ben@1" || worker.Str(s, "branch") != res.Branch || worker.Str(s, "state") != "busy" {
		t.Errorf("slot: %v", s)
	}
	out, _, _, _ := worker.ExecGit(bg, filepath.Join(f.root, ".worktrees", "ben"), "symbolic-ref", "--short", "HEAD")
	if strings.TrimSpace(out) != res.Branch {
		t.Errorf("worktree must sit on the issue branch, not %q", out)
	}
	for _, want := range []string{"--- ORCHESTRATOR (round 1) ---", "You are ben", "contract", "issue 12", "Dispute the ticket", "ben/12-", "Sibling issues running now: 13", "m: use the lease"} {
		if !strings.Contains(f.host.sent, want) {
			t.Errorf("brief lacks %q:\n%s", want, f.host.sent)
		}
	}
}

func TestAssignRefusals(t *testing.T) {
	f := newAssignFixture(t)

	_, err := f.assign("14", "ben", nil)
	if by := blockedBy(t, err); by != BlockNotReady || !strings.Contains(err.Error(), "criteria") {
		t.Errorf("no criteria: %v", err)
	}
	if len(f.be.claims) != 0 || len(f.be.states) != 0 || len(f.host.spawned) != 0 {
		t.Fatalf("a refused assign must touch nothing: %+v %+v %v", f.be.claims, f.be.states, f.host.spawned)
	}

	if _, err := f.assign("12", "ben", func(o *AssignOpts) { o.Settings.Roster = []string{"zed"} }); err == nil {
		t.Error("an agent outside the roster must be refused")
	}
	var we *worker.Error
	if _, err := f.assign("12", "zed", nil); !errors.As(err, &we) || we.Exit != worker.ExitUsage {
		t.Errorf("--agent outside the roster is usage: %v", err)
	}

	if _, err := f.assign("12", "ben", func(o *AssignOpts) { o.HolderPID = 999 }); blockedBy(t, err) != BlockNoRound {
		t.Errorf("a process without the lease: %v", err)
	}

	f.be.add("20", "Elsewhere", "M09", false, "## Acceptance\n- [ ] x")
	if _, err := f.assign("20", "ben", nil); blockedBy(t, err) != BlockOutOfScope {
		t.Errorf("outside the milestone: %v", err)
	}

	f.be.claimedBy = "dana@1"
	if _, err := f.assign("12", "ben", nil); blockedBy(t, err) != BlockClaimed || !strings.Contains(err.Error(), "dana@1") {
		t.Errorf("claimed elsewhere: %v", err)
	}
	f.be.claimedBy = ""

	noBrief := func(o *AssignOpts) { o.Settings.Brief = filepath.Join(f.root, "nope.md") }
	if _, err := f.assign("12", "ben", noBrief); blockedBy(t, err) != BlockBriefMissing {
		t.Errorf("missing brief: %v", err)
	}
	if len(f.be.claims) != 0 || len(f.be.states) != 0 {
		t.Fatalf("brief check comes before any marking: %+v", f.be.claims)
	}
}

func TestAssignOverlapAndAcceptOverlap(t *testing.T) {
	f := newAssignFixture(t)
	// A tracked file both issues name.
	os.MkdirAll(filepath.Join(f.root, "internal", "cli"), 0o755)
	os.WriteFile(filepath.Join(f.root, "internal", "cli", "round.go"), []byte("x"), 0o644)
	sh(t, f.root, "add", "internal/cli/round.go")
	sh(t, f.root, "commit", "-q", "-m", "round.go")
	// ben re-provisioned off the new main so both slots see it.
	if _, err := f.assign("12", "ben", nil); err != nil {
		t.Fatal(err)
	}
	_, err := f.assign("13", "dana", nil)
	if by := blockedBy(t, err); by != BlockOverlap {
		t.Fatalf("13 overlaps 12: %v", err)
	}
	var b *BlockedError
	errors.As(err, &b)
	if len(b.Readiness.Overlaps) != 1 || b.Readiness.Overlaps[0].Slot != "ben" {
		t.Errorf("overlap must name the holder: %+v", b.Readiness.Overlaps)
	}
	res, err := f.assign("13", "dana", func(o *AssignOpts) { o.AcceptOverlap = true })
	if err != nil || !res.Dispatched || len(res.Overlaps) != 1 {
		t.Fatalf("accepted overlap still assigns and stays listed: %v %+v", err, res)
	}
}

func TestAssignSlotBusyAndFreeSlot(t *testing.T) {
	f := newAssignFixture(t)
	if _, err := f.assign("12", "ben", nil); err != nil {
		t.Fatal(err)
	}
	if _, err := f.assign("13", "ben", nil); blockedBy(t, err) != BlockSlotBusy {
		t.Errorf("ben holds 12: %v", err)
	}
	// No --agent: the next idle roster slot, in roster order.
	res, err := f.assign("13", "", func(o *AssignOpts) { o.AcceptOverlap = true })
	if err != nil || res.Agent != "dana" {
		t.Fatalf("first idle slot is dana: %v %+v", err, res)
	}
	f.be.add("15", "Third", "M01", false, "## Acceptance\n- [ ] x")
	if _, err := f.assign("15", "", nil); blockedBy(t, err) != BlockNoFreeSlot {
		t.Errorf("both slots busy: %v", err)
	}
}

func TestAssignCheckOnlyWritesNothing(t *testing.T) {
	f := newAssignFixture(t)
	res, err := f.assign("12", "", func(o *AssignOpts) { o.CheckOnly = true })
	if err != nil || !res.Ready() || res.Dispatched {
		t.Fatalf("%v %+v", err, res)
	}
	res, err = f.assign("14", "", func(o *AssignOpts) { o.CheckOnly = true })
	if err != nil || res.Ready() {
		t.Fatalf("not ready is an answer, not an error: %v %+v", err, res)
	}
	if len(f.be.claims) != 0 || len(f.be.states) != 0 || len(f.be.notes) != 0 || f.host.sent != "" {
		t.Fatal("--check-only must write nothing")
	}
}

func TestAssignResumesWithoutDuplicatingTheComment(t *testing.T) {
	f := newAssignFixture(t)
	if _, err := f.assign("12", "ben", nil); err != nil {
		t.Fatal(err)
	}
	res, err := f.assign("12", "", nil) // no --agent: finds the slot already holding it
	if err != nil || res.Agent != "ben" || !res.Dispatched {
		t.Fatalf("resume: %v %+v", err, res)
	}
	if len(f.be.notes) != 1 {
		t.Errorf("a resumed assign must not comment twice: %v", f.be.notes)
	}
}

func TestAssignDispatchFailureKeepsTheMarks(t *testing.T) {
	f := newAssignFixture(t)
	f.env.Worker.NewHost = func(string) host.Host { return &failingHost{hostFake: f.host} }
	_, err := f.assign("12", "ben", nil)
	if err == nil {
		t.Fatal("dispatch failure must surface")
	}
	if f.be.claims["12"] == "" || f.be.states["12"] != "in-progress" {
		t.Errorf("a failure at dispatch keeps claim and state: %+v %+v", f.be.claims, f.be.states)
	}
}

type failingHost struct{ *hostFake }

func (f *failingHost) Send(context.Context, string, string, string) error {
	return errors.New("pane refused input")
}

func TestAssignUndoesWhenNothingWasSent(t *testing.T) {
	f := newAssignFixture(t)
	// Dirty worktree: the reset guard refuses before any dispatch.
	wt := filepath.Join(f.root, ".worktrees", "ben")
	os.WriteFile(filepath.Join(wt, "scratch.txt"), []byte("wip"), 0o644)
	_, err := f.assign("12", "ben", nil)
	if blockedBy(t, err) != BlockSlotBusy {
		t.Fatalf("a slot holding work is busy: %v", err)
	}
	if len(f.be.claims) != 0 || len(f.be.states) != 0 {
		t.Errorf("a failure before dispatch undoes claim and state: %+v %+v", f.be.claims, f.be.states)
	}
	if s := worker.LoadRegistry(f.root).Slot("ben"); worker.Str(s, "task") != "" || worker.Str(s, "claimId") != "" {
		t.Errorf("and the slot: %v", s)
	}
}

func (b *boardFake) Status(string) (*backlog.Status, error)       { return nil, nil }
func (b *boardFake) NoteGet(string, string) (string, bool, error) { return "", false, nil }
func (b *boardFake) NotePut(string, string, string) (bool, error) { return false, nil }
func (b *boardFake) NoteRm(string, string) (bool, error)          { return false, nil }
