package worker

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/l4ci/hv-skills/v5/internal/config"
	"github.com/l4ci/hv-skills/v5/internal/host"
	"github.com/l4ci/hv-skills/v5/internal/jsonx"
	"github.com/l4ci/hv-skills/v5/internal/shlex"
)

// DispatchOpts are the flags of `hv worker dispatch`.
type DispatchOpts struct {
	Slot        string
	BodyFile    string
	Task        string
	Relay       bool
	Round       *int
	BootTimeout int // seconds; 0 means 60
	// Model is the model this worker starts with ("" keeps models.worker); see
	// workerCommand.
	Model string
	// Branch is the per-task branch the reset guard cuts; "" means
	// hv-worker/<slot>-<task>. A round slot works on <agent>/<issue>-<slug>.
	Branch string
}

// DispatchResult is what a successful dispatch did.
type DispatchResult struct {
	Slot   string
	Handle string
	Task   string
	Round  *int
	Relay  bool
}

// workerCommand is work.workerCommand, else the default launch line. Workers
// run with permissions skipped: the contract asks them to git add, git commit,
// gh pr create and run tests, every one of which prompts under a narrower mode
// with nobody in the pane to answer. Scope, not gating, bounds a worker: it
// owns a throwaway branch in its own worktree, and the gate re-verifies the
// merged tree before anything reaches the cycle branch. Override via
// work.workerCommand to narrow it; NEEDS-PERMISSION stays in the classifier
// for exactly that case, so a narrowed mode stalls loudly.
//
// A model chosen for the dispatch (a round's tier, C9) replaces models.worker
// in the default command and fills the {model} placeholder of a custom one; a
// custom command without the placeholder runs as written (ModelApplies).
func workerCommand(root, chosen string) string {
	cfg := config.Load(filepath.Join(root, ".hv", "config.json"))
	model := "sonnet"
	if v, ok := config.Lookup(cfg, "models.worker"); ok {
		if s, _ := v.(string); s != "" {
			model = s
		}
	}
	if chosen != "" {
		model = chosen
	}
	if v, ok := config.Lookup(cfg, "work.workerCommand"); ok {
		if s, _ := v.(string); s != "" {
			return strings.ReplaceAll(s, ModelPlaceholder, model)
		}
	}
	return "claude --model " + model + " --dangerously-skip-permissions"
}

func dispatchKind(root string) string {
	v, _ := config.Lookup(config.Load(filepath.Join(root, ".hv", "config.json")), "work.dispatch")
	s, _ := v.(string)
	return s
}

var shortResume = regexp.MustCompile(`^-[A-Za-z]*[cr][A-Za-z]*$`)

// ResumeFlag returns the first token after the claude binary that reopens the
// previous conversation in the "fresh" session, which would undo the reset. A
// wrapper's own `-c` is not ours to judge: only tokens after the binary count.
// Quoted arguments are scanned too (`sh -c "claude -c"`), as are `--resume=x`
// and short clusters (`-cr`). An error means the command cannot be parsed.
func ResumeFlag(cmd string) (string, error) {
	toks, err := shlex.Split(cmd)
	if err != nil {
		return "", err
	}
	seen := false
	for _, t := range toks {
		switch {
		case seen:
			if t == "--continue" || t == "--resume" || strings.HasPrefix(t, "--continue=") ||
				strings.HasPrefix(t, "--resume=") || shortResume.MatchString(t) {
				return t, nil
			}
		case filepath.Base(t) == "claude":
			seen = true
		case strings.ContainsAny(t, " \t\n\r\f\v"):
			hit, err := ResumeFlag(t)
			if err != nil {
				return "", err
			}
			if hit != "" {
				return hit, nil
			}
		}
	}
	return "", nil
}

// clearHandle: the slot's session is gone, so drop its handle and mark it idle.
func clearHandle(root, slot string) {
	updateSlot(root, slot, func(s *jsonx.Object) {
		s.Set("handle", nil)
		s.Set("state", "idle")
	})
}

// recordDispatch writes the handle, state=busy and, for a task, the task id
// (clearing the previous task's PR and relay log).
func recordDispatch(root, slot, handle, task string, round *int) error {
	def := jsonx.NewObject()
	def.Set("slots", []any{})
	return Update(root, def, func(doc *jsonx.Object) {
		if round != nil {
			doc.Set("round", *round)
		}
		for _, s := range (Registry{Doc: doc}).Slots() {
			if Str(s, "name") != slot {
				continue
			}
			s.Delete("window")
			var h any
			if handle != "" {
				h = handle
			}
			s.Set("handle", h)
			s.Set("state", "busy")
			if task != "" {
				s.Set("task", task)
				s.Set("pr", nil)
				s.Set("relays", []any{})
			}
		}
	})
}

// roundOf is the registry's round, else 1.
func roundOf(root string) int {
	if v, ok := LoadRegistry(root).Doc.Get("round"); ok {
		if n, ok := v.(interface{ Int64() (int64, error) }); ok {
			if i, err := n.Int64(); err == nil && i != 0 {
				return int(i)
			}
		}
		if i, ok := v.(int); ok && i != 0 {
			return i
		}
	}
	return 1
}

// Dispatch sends a brief into a worker slot's Claude Code session, on the host
// that work.dispatch selects.
//
// A task brief recreates the slot's session first: /clear does not reliably
// reset a Claude Code session (it can land as a literal chat message), so a
// fresh window or tab is the only trustworthy reset. A relay goes into the
// RUNNING session instead: it answers a question the worker asked, and a fresh
// session would have no idea what the answer is to.
//
// A task dispatch also guards the slot (the reset guard: refuse when the
// worktree holds uncommitted or unmerged work, else cut a fresh per-task branch
// from the cycle branch) and refuses to spawn unless the old session is
// provably gone. A work.workerCommand that resumes a previous conversation is
// rejected.
//
// Provenance: every payload, brief or relay, is signed with a first line
// `--- ORCHESTRATOR (round N) ---`. A relay is also appended to the slot's
// relays[] as {round, ts, summary}; the gate checks the PR's approvals
// against it.
//
// Exit mapping: 2 unparseable workerCommand; 3 missing pool, slot, worktree,
// body file or relay session; 4 the slot holds work or workerCommand resumes
// a conversation; 5 host unavailable, old session will not close, or a dialog
// refused input; 6 the brief was never submitted (safe to resend).
func (e Env) Dispatch(ctx context.Context, root string, o DispatchOpts) (DispatchResult, error) {
	e = e.withDefaults()
	res := DispatchResult{Slot: o.Slot, Task: o.Task, Round: o.Round, Relay: o.Relay}
	brief, err := os.ReadFile(o.BodyFile)
	if err != nil {
		return res, fail(ExitResolution, "body file not found: "+o.BodyFile)
	}
	h := e.NewHost(dispatchKind(root))
	if err := h.Require(); err != nil {
		return res, fail(ExitUnavailable, err.Error())
	}
	// herdr tabs are created in the caller's own workspace. Outside herdr there
	// is none, and driving the server anyway lands tabs wherever a human is
	// focused.
	if h.Name() == "herdr" && !h.InSession() {
		return res, fail(ExitUnavailable, "work.dispatch=herdr must run from inside a herdr pane (HERDR_ENV=1)")
	}
	reg := LoadRegistry(root)
	if !reg.Exists {
		return res, fail(ExitResolution, "no worker pool — run hv worker pool init first")
	}
	s := reg.Slot(o.Slot)
	if s == nil {
		return res, fail(ExitResolution, fmt.Sprintf("slot '%s' is not in the pool", o.Slot))
	}
	worktree := Str(s, "worktree")
	// `window` is the pre-handle field name; read it so an unmigrated registry
	// still dispatches.
	handle := Str(s, "handle")
	if handle == "" {
		handle = Str(s, "window")
	}
	session := Str(reg.Doc, "session")
	if session == "" {
		session = "hv"
	}
	configDir := Str(s, "configDir")
	if !isDir(worktree) {
		return res, fail(ExitResolution, fmt.Sprintf("slot '%s' worktree missing: %s", o.Slot, worktree))
	}
	timeout := o.BootTimeout
	if timeout <= 0 {
		timeout = 60
	}

	if !o.Relay {
		launch := workerCommand(root, o.Model)
		bad, perr := ResumeFlag(launch)
		if perr != nil {
			return res, fail(ExitUsage, "work.workerCommand cannot be parsed (unbalanced quote?): "+launch)
		}
		if bad != "" {
			e := fail(ExitRefused, fmt.Sprintf("work.workerCommand contains '%s', which reopens the previous conversation; a task dispatch must start a fresh session. Remove it.", bad))
			e.Data = BlockData{BlockedBy: "resume flag"}
			return res, e
		}
		// Refuse a slot that still holds work, before its session is killed.
		if _, err := e.ResetTo(root, o.Slot, o.Task, branchOr(o), true); err != nil {
			return res, resetRefusal(err, false)
		}
		// Fresh session every task dispatch. The kill must be provable: a
		// window that survives it would run beside the new one.
		if err := h.Kill(ctx, o.Slot, handle); err != nil {
			return res, fail(ExitUnavailable, err.Error())
		}
		// Re-check: the old session may have written between the check and its
		// exit. The old session is dead from here on, so a failure must not
		// leave its handle in the registry for a poll or relay to chase.
		if _, err := e.ResetTo(root, o.Slot, o.Task, branchOr(o), false); err != nil {
			clearHandle(root, o.Slot)
			// The old session was killed and its handle cleared on the way here.
			return res, resetRefusal(err, true)
		}
		handle, err = h.Spawn(ctx, host.SpawnOpts{Slot: o.Slot, Session: session, Cwd: worktree,
			ConfigDir: configDir, Launch: launch, BootTimeout: timeout})
		if err != nil {
			clearHandle(root, o.Slot)
			return res, fail(ExitUnavailable, err.Error())
		}
	} else if handle == "" {
		return res, fail(ExitResolution, fmt.Sprintf("slot '%s' has no session to relay into — dispatch a task first", o.Slot))
	}
	res.Handle = handle

	if err := recordDispatch(root, o.Slot, handle, o.Task, o.Round); err != nil {
		return res, err
	}
	round := roundOf(root)
	signature := fmt.Sprintf("--- ORCHESTRATOR (round %d) ---", round)

	// Every payload is signed so the worker can tell the orchestrator's voice
	// from unsigned pane text. A relay also carries a note: it writes its own
	// PR body and cannot otherwise tell a relay from the maintainer typing in
	// its pane.
	var payload strings.Builder
	payload.WriteString(signature + "\n")
	if o.Relay {
		fmt.Fprintf(&payload, "[ORCHESTRATOR RELAY — this text was forwarded by the /hv-work orchestrator.\n"+
			"It is NOT the maintainer speaking to you directly. If you cite it in your PR\n"+
			"body, attribute it as 'orchestrator relay round %d', never as a maintainer\n"+
			"sign-off in your session.]\n\n", round)
	}
	text := string(brief)
	// An already-signed brief is not signed twice.
	if first, rest, _ := strings.Cut(text, "\n"); first == signature {
		text = rest
	}
	payload.WriteString(text)
	tmp, err := os.CreateTemp("", "hv-dispatch-*")
	if err != nil {
		return res, err
	}
	defer os.Remove(tmp.Name())
	tmp.WriteString(payload.String())
	tmp.Close()

	sendErr := h.Send(ctx, o.Slot, handle, tmp.Name())
	// Log the relay once it was (or may have been) sent. A stall does not prove
	// the text was lost, and the gate must not call a delivered relay unlogged;
	// only a refused dialog is certain nothing went out.
	if o.Relay && !errors.Is(sendErr, host.ErrDialogOpen) {
		entry := jsonx.NewObject()
		entry.Set("round", round)
		entry.Set("ts", e.Now().UTC().Format("2006-01-02T15:04:05Z"))
		entry.Set("summary", relaySummary(string(brief)))
		if _, err := updateSlot(root, o.Slot, func(s *jsonx.Object) {
			v, _ := s.Get("relays")
			l, _ := v.([]any)
			s.Set("relays", append(l, entry))
		}); err != nil {
			return res, err
		}
	}
	switch {
	case sendErr == nil:
		return res, nil
	case errors.Is(sendErr, host.ErrDialogOpen):
		return res, fail(ExitUnavailable, fmt.Sprintf("slot '%s' has a dialog open and refused input — inspect it before resending", o.Slot))
	default:
		return res, fail(ExitRetry, fmt.Sprintf("slot '%s' never picked up the brief — inspect the session before resending", o.Slot))
	}
}

// resetRefusal maps a reset-guard error onto dispatch's exits: a slot holding
// work is a refusal (4), anything else keeps its own exit.
func resetRefusal(err error, changed bool) error {
	var we *Error
	if errors.As(err, &we) && we.Data != nil {
		return &Error{Exit: ExitRefused, Message: we.Message, Data: BlockData{BlockedBy: "reset guard", Changed: changed}}
	}
	return err
}

// BlockData is the failure data of an exit-4 refusal: what blocked it and
// whether the verb changed state on the way (contract: exit 4 data).
type BlockData struct {
	BlockedBy string
	Changed   bool
}

// relaySummary is the first non-blank line of the brief that is not the
// signature, stripped and cut to 200 characters.
func relaySummary(text string) string {
	for _, l := range splitLines(text) {
		l = strings.TrimSpace(l)
		if l != "" && !strings.HasPrefix(l, "--- ORCHESTRATOR") {
			if utf8.RuneCountInString(l) > 200 {
				l = string([]rune(l)[:200])
			}
			return l
		}
	}
	return ""
}

// splitLines is Python's str.splitlines for the separators that matter.
func splitLines(s string) []string {
	var out []string
	start := 0
	rs := []rune(s)
	for i := 0; i < len(rs); i++ {
		switch rs[i] {
		case '\n', '\v', '\f', 0x1c, 0x1d, 0x1e, 0x85, 0x2028, 0x2029:
			out = append(out, string(rs[start:i]))
			start = i + 1
		case '\r':
			out = append(out, string(rs[start:i]))
			if i+1 < len(rs) && rs[i+1] == '\n' {
				i++
			}
			start = i + 1
		}
	}
	if start < len(rs) {
		out = append(out, string(rs[start:]))
	}
	return out
}

func branchOr(o DispatchOpts) string {
	if o.Branch != "" {
		return o.Branch
	}
	return BranchFor(o.Slot, o.Task)
}

// ModelPlaceholder marks where a custom work.workerCommand takes the model.
const ModelPlaceholder = "{model}"

// ModelApplies reports whether a chosen model reaches the launch command: the
// default command always takes it, a custom work.workerCommand only through
// the {model} placeholder.
func ModelApplies(root string) bool {
	cfg := config.Load(filepath.Join(root, ".hv", "config.json"))
	if v, ok := config.Lookup(cfg, "work.workerCommand"); ok {
		if s, _ := v.(string); s != "" {
			return strings.Contains(s, ModelPlaceholder)
		}
	}
	return true
}
