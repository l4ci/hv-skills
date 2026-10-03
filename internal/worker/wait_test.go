package worker

import (
	"context"
	"errors"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/l4ci/hv-skills/v5/internal/host"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
)

// waitHost is a host whose panes and native status the test steers. With
// events set it is also a host.Watcher; each value sent is one status change
// of the named slot.
type waitHost struct {
	*fakeHost
	mu      sync.Mutex
	text    map[string]string // pane text per slot, "" is a static idle pane
	events  chan string
	watched []host.WatchTarget
	watchOK error
	// steps run on each Capture of a slot, to script a pane that changes.
	onCapture func(slot string)
}

func (h *waitHost) Capture(_ context.Context, slot, _ string, _ int) string {
	if h.onCapture != nil {
		h.onCapture(slot)
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.text[slot]
}

func (h *waitHost) Status(_ context.Context, slot, _ string) string {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.status[slot]
}

func (h *waitHost) set(slot, text, native string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.text[slot], h.status[slot] = text, native
}

type waitWatch struct{ h *waitHost }

func (w waitWatch) Next(ctx context.Context) (string, error) {
	select {
	case s, ok := <-w.h.events:
		if !ok {
			return "", errors.New("herdr closed the event stream")
		}
		return s, nil
	case <-ctx.Done():
		return "", ctx.Err()
	}
}
func (waitWatch) Close() {}

// watcherHost adds Watch; tmux-style tests use waitHost alone.
type watcherHost struct{ *waitHost }

func (h watcherHost) Watch(_ context.Context, t []host.WatchTarget) (host.Watch, error) {
	h.watched = t
	h.waitHost.watched = t
	return waitWatch{h.waitHost}, h.watchOK
}

func newWaitHost(name string) *waitHost {
	f := tmuxFake()
	f.name = name
	f.status = map[string]string{}
	return &waitHost{fakeHost: f, text: map[string]string{}, events: make(chan string, 8)}
}

func withHandles(t *testing.T, dir string, handles map[string]string) {
	t.Helper()
	def := jsonx.NewObject()
	def.Set("slots", []any{})
	if err := Update(dir, def, func(doc *jsonx.Object) {
		for _, s := range (Registry{Doc: doc}).Slots() {
			if h, ok := handles[Str(s, "name")]; ok {
				s.Set("handle", h)
				s.Set("state", "busy")
			} else {
				s.Set("handle", nil) // a slot never dispatched has no session
			}
		}
	}); err != nil {
		t.Fatal(err)
	}
}

func waitProject(t *testing.T, slots int, handles map[string]string) string {
	t.Helper()
	dir := newProject(t, `{}`)
	goInit(t, dir, InitOpts{Slots: slots, Base: "main"})
	withHandles(t, dir, handles)
	return dir
}

func TestWaitReturnsASlotThatAlreadyNeedsAttention(t *testing.T) {
	dir := waitProject(t, 2, map[string]string{"w1": "w9:t1", "w2": "w9:t2"})
	h := newWaitHost("herdr")
	h.set("w1", "working...\n", "working")
	h.set("w2", "HV-BLOCKED w2: A or B?\n", "idle")
	before, _ := os.ReadFile(RegistryPath(dir))
	res, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{})
	if err != nil {
		t.Fatal(err)
	}
	if res.Slot != "w2" || res.State != StateBlocked || res.Evidence != "A or B?" || res.Source != SourceSnapshot {
		t.Errorf("%+v", res)
	}
	if len(h.watched) != 2 {
		t.Errorf("watched = %v, want both slots", h.watched)
	}
	if after, _ := os.ReadFile(RegistryPath(dir)); string(after) != string(before) {
		t.Error("wait wrote the registry")
	}
}

func TestWaitWakesOnAnEventAndReclassifies(t *testing.T) {
	dir := waitProject(t, 1, map[string]string{"w1": "w9:t1"})
	h := newWaitHost("herdr")
	h.set("w1", "working...\n", "working")
	go func() {
		time.Sleep(20 * time.Millisecond)
		h.events <- "w1" // status changed, but the pane still moves: nothing to return
		time.Sleep(20 * time.Millisecond)
		h.set("w1", "HV-DONE w1 https://github.com/o/r/pull/9\n", "done")
		h.events <- "w1"
	}()
	res, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{Timeout: 5 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if res.Slot != "w1" || res.State != StateDone || res.Source != SourceEvent {
		t.Errorf("%+v", res)
	}
}

func TestWaitOnAHostWithoutEventsPollsUntilTheSlotChanges(t *testing.T) {
	dir := waitProject(t, 1, map[string]string{"w1": "w9:t1"})
	h := newWaitHost("tmux")
	n := 0
	h.onCapture = func(string) { // the pane moves for two classifications, then settles on HV-DONE
		n++
		if n <= 4 {
			h.set("w1", strings.Repeat("x", n)+"\n", "")
		} else {
			h.set("w1", "HV-DONE w1 hv-worker/w1\n", "")
		}
	}
	res, err := envWith(h).Wait(bg, dir, WaitOpts{Settle: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if res.State != StateDone || res.Source != SourcePoll {
		t.Errorf("%+v", res)
	}
}

func TestWaitTimeoutIsAnAnswerWithTheSlotStates(t *testing.T) {
	dir := waitProject(t, 1, map[string]string{"w1": "w9:t1"})
	h := newWaitHost("herdr")
	h.set("w1", "working...\n", "working")
	res, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{Timeout: 30 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	if !res.TimedOut || len(res.Slots) != 1 || res.Slots[0].State != StateBusy {
		t.Errorf("%+v", res)
	}
}

func TestWaitSkipsHandlelessSlotsUnlessNamed(t *testing.T) {
	dir := waitProject(t, 2, map[string]string{"w2": "w9:t2"})
	h := newWaitHost("herdr")
	h.set("w2", "HV-DONE w2 x\n", "done")
	res, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{})
	if err != nil || res.Slot != "w2" {
		t.Fatalf("%+v %v", res, err)
	}
	if len(h.watched) != 1 || h.watched[0].Slot != "w2" {
		t.Errorf("watched = %v", h.watched)
	}
	for _, name := range []string{"w1", "nope"} {
		_, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{Slots: []string{name}})
		if exitOf(err) != ExitResolution {
			t.Errorf("named %s: %v, want exit 3", name, err)
		}
	}
}

func TestWaitDoesNotWatchSlotsRecordedIdle(t *testing.T) {
	dir := waitProject(t, 2, map[string]string{"w1": "hv:w1", "w2": "hv:w2"})
	def := jsonx.NewObject()
	def.Set("slots", []any{})
	Update(dir, def, func(doc *jsonx.Object) { // w1 was polled idle, w2 is running
		(Registry{Doc: doc}).Slot("w1").Set("state", "idle")
	})
	h := newWaitHost("herdr")
	h.set("w2", "HV-DONE w2 x\n", "done")
	res, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{})
	if err != nil || res.Slot != "w2" || len(h.watched) != 1 {
		t.Fatalf("%+v %v watched=%v", res, err, h.watched)
	}
	// Naming a slot watches it whatever its recorded state.
	h.set("w1", "HV-DONE w1 x\n", "done")
	if res, err = envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{Slots: []string{"w1"}}); err != nil || res.Slot != "w1" {
		t.Errorf("named: %+v %v", res, err)
	}
}

func TestWaitWithNothingToWatchIsAResolutionError(t *testing.T) {
	dir := waitProject(t, 1, nil)
	_, err := envWith(newWaitHost("tmux")).Wait(bg, dir, WaitOpts{})
	if exitOf(err) != ExitResolution {
		t.Errorf("%v, want exit 3", err)
	}
}

func TestWaitHostFailuresAreUnavailable(t *testing.T) {
	dir := waitProject(t, 1, map[string]string{"w1": "w9:t1"})
	h := newWaitHost("herdr")
	h.watchOK = host.ErrUnsupportedHerdr
	if _, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{}); exitOf(err) != ExitUnavailable {
		t.Errorf("watch failure: %v, want exit 5", err)
	}
	h = newWaitHost("herdr")
	h.set("w1", "working\n", "working")
	close(h.events) // herdr went away mid-wait
	if _, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{}); exitOf(err) != ExitUnavailable {
		t.Errorf("stream closed: %v, want exit 5", err)
	}
	h = newWaitHost("herdr")
	h.requireErr = errors.New("herdr is not installed")
	if _, err := envWith(watcherHost{h}).Wait(bg, dir, WaitOpts{}); exitOf(err) != ExitUnavailable {
		t.Errorf("not installed: %v, want exit 5", err)
	}
}

func TestWaitCancelIsNotATimeout(t *testing.T) {
	dir := waitProject(t, 1, map[string]string{"w1": "w9:t1"})
	h := newWaitHost("herdr")
	h.set("w1", "working\n", "working")
	ctx, cancel := context.WithCancel(bg)
	go func() { time.Sleep(20 * time.Millisecond); cancel() }()
	res, err := envWith(watcherHost{h}).Wait(ctx, dir, WaitOpts{})
	if exitOf(err) != ExitFailed || res.TimedOut {
		t.Errorf("%+v %v", res, err)
	}
}
