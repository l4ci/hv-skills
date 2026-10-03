package hook

import (
	"fmt"
	"os"
	"strings"
	"time"
)

// HandoffMarker is the first line of a handoff the Stop hook asked for.
const HandoffMarker = "<!-- hv-handoff: orchestrator -->"

// Handoff is what the filesystem says about the handoff file.
type Handoff struct {
	Exists  bool
	ModTime time.Time
}

// Fresh is the freshness rule of every D1 and D2 decision: the handoff exists
// and was written no more than maxAge ago. A consumed handoff (renamed to
// .consumed) does not exist, so it is never fresh.
func (h Handoff) Fresh(maxAge time.Duration, now time.Time) bool {
	return h.Exists && now.Sub(h.ModTime) <= maxAge
}

// StatHandoff reads the handoff file's presence and mtime.
func StatHandoff(path string) Handoff {
	fi, err := os.Stat(path)
	if err != nil || !fi.Mode().IsRegular() {
		return Handoff{}
	}
	return Handoff{Exists: true, ModTime: fi.ModTime()}
}

// StopIn is the Stop payload's relevant fields.
type StopIn struct {
	StopHookActive bool
}

// StopDecision is what the Stop hook does. Block false means print nothing.
type StopDecision struct {
	Block   bool
	Reason  string
	State   State // the state to persist; Persist says whether it changed
	Persist bool
}

// DecideStop applies the contract's Stop rules to an orchestrator session's
// state. The caller has already established that the session is the
// orchestrator and found a readable state file (st). handoffPath only
// appears in the block reason.
func DecideStop(in StopIn, st State, set Settings, ho Handoff, handoffPath string, now time.Time) StopDecision {
	d := StopDecision{State: st}
	if st.HandoffFailed {
		return d // gave up already: never hold the session again
	}
	at, err := time.Parse(time.RFC3339, st.UpdatedAt)
	if err != nil || now.Sub(at) > time.Duration(set.StateMaxAge)*time.Second {
		return d // a stale reading is not acted on
	}
	if st.ContextPct == nil || *st.ContextPct < float64(set.Threshold) {
		return d
	}
	var blockedAt time.Time
	if st.BlockedAt != "" {
		blockedAt, _ = time.Parse(time.RFC3339, st.BlockedAt)
	}
	if ho.Exists {
		newer := !ho.ModTime.Before(blockedAt)
		fresh := ho.Fresh(time.Duration(set.HandoffMaxAge)*time.Second, now)
		if (in.StopHookActive && newer) || (!in.StopHookActive && fresh && newer) {
			return d // the handoff is written: the orchestrator is exiting
		}
	}
	if in.StopHookActive {
		if st.HandoffBlocks >= set.HandoffMaxBlks {
			d.State.HandoffFailed = true
			d.Persist = true
			return d
		}
		d.State.HandoffBlocks++
	}
	d.State.BlockedAt = now.UTC().Format(time.RFC3339)
	d.Persist = true
	d.Block = true
	d.Reason = blockReason(*st.ContextPct, set.Threshold, handoffPath)
	return d
}

func blockReason(pct float64, threshold int, path string) string {
	return fmt.Sprintf("Context is at %s%%, at or above the handoff threshold of %d%%. "+
		"Write the handoff for the next orchestrator session to %s now: first line %q, "+
		"second line \"<!-- written <UTC timestamp, YYYY-MM-DDTHH:MM:SSZ> -->\", then the body from "+
		"references/handoff-template.md with a \"## Round state\" section (slots, who holds what, merges pending, escalations open). "+
		"Commit nothing you do not own. Then run /exit.",
		trimPct(pct), threshold, path, HandoffMarker)
}

func trimPct(p float64) string {
	s := fmt.Sprintf("%.1f", p)
	return strings.TrimSuffix(s, ".0")
}

// StopOutput is the JSON the hook prints for a block.
func StopOutput(reason string) map[string]string {
	return map[string]string{"decision": "block", "reason": reason}
}
