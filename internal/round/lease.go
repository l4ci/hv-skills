package round

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/l4ci/hv-skills/v5/internal/roundlease"
	"github.com/l4ci/hv-skills/v5/internal/worker"
)

// LeaseStale is the drift kind for a lease whose holder is gone. It is never
// repaired by Reconcile: `hv reap` clears it (ClearStaleLease), and
// `hv round start` reclaims it.
const LeaseStale = "lease-stale"

// Lease aliases, so reconcile and reap import one package.
type (
	Lease      = roundlease.Lease
	LeaseState = roundlease.State
)

func (e Env) leaseEnv() roundlease.Env {
	if e.Lease.Alive == nil {
		return roundlease.DefaultEnv()
	}
	return e.Lease
}

// commonDir is the git common dir of root, through the Env's git.
func (e Env) commonDir(ctx context.Context, root string) (string, error) {
	out, errOut, code, err := e.Git(ctx, root, "rev-parse", "--git-common-dir")
	if err != nil || code != 0 {
		return "", &worker.Error{Exit: worker.ExitUnavailable, Message: "git rev-parse --git-common-dir failed: " + strings.TrimSpace(errOut)}
	}
	p := strings.TrimSpace(out)
	if !filepath.IsAbs(p) {
		p = filepath.Join(root, p)
	}
	if r, err := filepath.EvalSymlinks(p); err == nil {
		p = r
	}
	return filepath.Clean(p), nil
}

// ReadLease is the repo's orchestrator lease and its state.
func (e Env) ReadLease(ctx context.Context, root string) (Lease, LeaseState, error) {
	cd, err := e.commonDir(ctx, root)
	if err != nil {
		return Lease{}, roundlease.None, err
	}
	return e.leaseEnv().Read(cd)
}

// ClearStaleLease removes the lease when its holder is gone and reports what
// it removed. A live or foreign lease is left alone. It is the seam `hv reap`
// calls.
func (e Env) ClearStaleLease(ctx context.Context, root string) (Lease, bool, error) {
	cd, err := e.commonDir(ctx, root)
	if err != nil {
		return Lease{}, false, err
	}
	return e.leaseEnv().ClearStale(cd)
}

// leaseFinding adds the lease-stale drift when the lease's holder is gone.
func (e Env) leaseFinding(ctx context.Context, root string, rep *Report) {
	l, st, err := e.ReadLease(ctx, root)
	if err != nil || st != roundlease.Stale {
		return
	}
	who := "an unreadable lease file"
	if l.PID > 0 {
		who = fmt.Sprintf("pid %d (round %d, started %s)", l.PID, l.Round, l.StartedAt)
	}
	rep.add(Finding{Kind: LeaseStale, Detail: "the round lease is held by " + who + ", which is gone; `hv round start` reclaims it, `hv reap` clears it"})
}
