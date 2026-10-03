package round

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/l4ci/hv-skills/v5/internal/roundlease"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

func (f *assignFixture) windDown(mod func(*WindDownOpts)) (WoundDown, error) {
	o := WindDownOpts{HolderPID: 100, Settings: f.set, Getenv: func(string) string { return "" }}
	if mod != nil {
		mod(&o)
	}
	return f.env.WindDown(bg, f.root, f.be, o)
}

func (f *assignFixture) verifyWith(t *testing.T, cmds string) {
	t.Helper()
	cfg := `{"refactor":{"verifyCommands":` + cmds + `}}`
	if err := os.WriteFile(filepath.Join(f.root, ".hv", "config.json"), []byte(cfg), 0o644); err != nil {
		t.Fatal(err)
	}
}

func outcomes(r WoundDown) map[string]string {
	m := map[string]string{}
	for _, s := range r.Slots {
		m[s.Name] = s.Outcome
	}
	return m
}

func TestWindDownParksReleasesAndSummarises(t *testing.T) {
	f := newAssignFixture(t)
	if _, err := f.assign("12", "ben", nil); err != nil {
		t.Fatal(err)
	}
	f.verifyWith(t, `["true"]`)
	res, err := f.windDown(nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.Verdict != VerdictClean || !reflect.DeepEqual(res.Verified, []string{"true"}) || res.Lease != nil || res.Round != 1 {
		t.Fatalf("%+v", res)
	}
	if !reflect.DeepEqual(outcomes(res), map[string]string{"ben": OutcomeParked, "dana": OutcomeUnchanged}) {
		t.Fatalf("outcomes: %v", outcomes(res))
	}
	for _, s := range res.Slots {
		if s.Name == "ben" && s.Issue != "12" {
			t.Errorf("the summary keeps the issue the slot held: %+v", s)
		}
	}
	out, _, _, _ := worker.ExecGit(bg, filepath.Join(f.root, ".worktrees", "ben"), "symbolic-ref", "--short", "HEAD")
	if got := out[:len(out)-1]; got != "park/ben" {
		t.Errorf("ben must be parked, on %q", got)
	}
	s := worker.LoadRegistry(f.root).Slot("ben")
	if worker.Str(s, "task") != "" || worker.Str(s, "claimId") != "" || worker.Str(s, "state") != "idle" {
		t.Errorf("a parked slot holds nothing: %v", s)
	}
	if _, held := f.be.claims["12"]; held {
		t.Error("the claim must be released")
	}
	if _, st, _ := f.env.ReadLease(bg, f.root); st != roundlease.None {
		t.Errorf("a clean wind-down releases the lease: %v", st)
	}
}

func TestWindDownVerifyFailureKeepsTheLeaseButParks(t *testing.T) {
	f := newAssignFixture(t)
	if _, err := f.assign("12", "ben", nil); err != nil {
		t.Fatal(err)
	}
	f.verifyWith(t, `["true","exit 3"]`)
	res, err := f.windDown(nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.Verdict != VerdictVerifyFailed || res.Lease == nil || !reflect.DeepEqual(res.Verified, []string{"true"}) {
		t.Fatalf("%+v", res)
	}
	if outcomes(res)["ben"] != OutcomeParked {
		t.Errorf("slots are parked whatever the verify said: %v", outcomes(res))
	}
	if _, st, _ := f.env.ReadLease(bg, f.root); st != roundlease.Live {
		t.Errorf("a red base keeps the lease: %v", st)
	}
}

func TestWindDownRefusesWhileASlotHoldsWork(t *testing.T) {
	f := newAssignFixture(t)
	if _, err := f.assign("12", "ben", nil); err != nil {
		t.Fatal(err)
	}
	wt := filepath.Join(f.root, ".worktrees", "ben")
	os.WriteFile(filepath.Join(wt, "wip.txt"), []byte("x"), 0o644)
	res, err := f.windDown(nil)
	if err != nil {
		t.Fatal(err)
	}
	if res.Verdict != VerdictHoldsWork || !res.Retained || res.Lease == nil {
		t.Fatalf("%+v", res)
	}
	got := outcomes(res)
	if got["ben"] != OutcomeRetained || got["dana"] != OutcomeUnchanged {
		t.Fatalf("outcomes %v", got)
	}
	for _, s := range res.Slots {
		if s.Name == "ben" && len(s.Dirty) != 1 {
			t.Errorf("the dirty file is reported: %+v", s)
		}
	}
	if s := worker.LoadRegistry(f.root).Slot("ben"); worker.Str(s, "task") != "12" {
		t.Errorf("a retained slot keeps its task: %v", s)
	}
	if _, held := f.be.claims["12"]; !held {
		t.Error("a retained slot keeps its claim")
	}
	// Fix the slot and run again: now it completes.
	os.Remove(filepath.Join(wt, "wip.txt"))
	res, err = f.windDown(nil)
	if err != nil || res.Verdict != VerdictClean || outcomes(res)["ben"] != OutcomeParked {
		t.Fatalf("second run: %v %+v", err, res)
	}
}

func TestWindDownNeedsTheLeaseAndTheBase(t *testing.T) {
	f := newAssignFixture(t)
	var we *worker.Error
	if _, err := f.windDown(func(o *WindDownOpts) { o.HolderPID = 999 }); !errors.As(err, &we) || we.Exit != worker.ExitResolution {
		t.Fatalf("a process without the lease: %v", err)
	}
	f.verifyWith(t, `["true"]`)
	sh(t, f.root, "checkout", "-q", "-b", "side")
	if _, err := f.windDown(nil); !errors.As(err, &we) || we.Exit != worker.ExitResolution {
		t.Fatalf("the root must be on the base: %v", err)
	}
	if _, st, _ := f.env.ReadLease(bg, f.root); st != roundlease.Live {
		t.Errorf("a refusal keeps the lease: %v", st)
	}
	sh(t, f.root, "checkout", "-q", "main")
	// --no-verify needs neither commands nor the base.
	sh(t, f.root, "checkout", "-q", "side")
	res, err := f.windDown(func(o *WindDownOpts) { o.NoVerify = true })
	if err != nil || res.Verdict != VerdictClean || !res.VerifySkipped {
		t.Fatalf("no-verify: %v %+v", err, res)
	}
}

func TestWindDownWithoutVerifyCommandsSaysSo(t *testing.T) {
	f := newAssignFixture(t)
	res, err := f.windDown(nil)
	if err != nil || res.Verdict != VerdictClean || !res.VerifySkipped || len(res.Warnings) == 0 {
		t.Fatalf("%v %+v", err, res)
	}
}
