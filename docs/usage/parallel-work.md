# Parallel work

When `work.isolation` is set to `"worktree"`, you can run multiple `/hv-work`
sessions side by side from separate terminals — each session gets its own
isolated directory and branch, so they never step on each other.

## When to use this

- Long-running cycles you don't want to block on while other work proceeds.
- Multiple independent feature tracks that shouldn't share a branch.
- Keeping `main` clean while agents work in parallel.
- Batching unrelated bug fixes that have nothing to gain from sharing context.

## Setting it up

Flip `work.isolation` to `"worktree"` via `/hv-config` or by editing
`.hv/config.json` directly. See [configuration](configuration.md) for the full
option set. Once set, `/hv-work` creates a new directory under
`.claude/worktrees/<branch-name>` for each cycle instead of switching the
current worktree. The main worktree stays on `main` throughout.

## Two terminals, two streams

Start each stream in its own terminal. `/hv-next` picks items that aren't
already in progress, so the two sessions naturally claim different work.

**Terminal 1** — picks `[B02]` and `[F01]`:

```
/hv-next
# → suggests B02, F01
/hv-work
# → creates .claude/worktrees/fix/b02-timer-crash
#    and .claude/worktrees/feat/f01-dark-mode
```

**Terminal 2** — picks `[F03]` (B02 and F01 are already in progress):

```
/hv-next
# → suggests F03 (B02 and F01 shown as In Progress, skipped)
/hv-work
# → creates .claude/worktrees/feat/f03-export-csv
```

Both streams run independently. See [running work](running-work.md) for the
full `/hv-work` lifecycle.

## How status.json stays consistent

Both orchestrators write to the same `.hv/status.json` in the main worktree,
but each owns different entries — one per active branch — so there are no
conflicts under normal operation. `/hv-next` in a third terminal sees both
streams as "In Progress" and skips those items when suggesting new work. If
you run `/hv-next` while `/hv-work` is mid-update, the last writer wins; the
next `/hv-next` run reconciles any drift by validating status against actual
git state. For more on how `/hv-next` reads and updates status, see
[reviewing and picking work](next-and-status.md).

## Caveats

Don't run `/hv-init` or `/hv-config` from inside a worktree — those write to
`.hv/` and must run in the main worktree. `/hv-status`, `/hv-next`, and
`/hv-work` are fine in either place.
