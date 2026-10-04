# Parallel work

When `work.isolation` is set to `"worktree"`, you can run multiple [`/hv-work`](running-work.md)
sessions side by side from separate terminals. Each session gets its own
directory and branch, so they don't step on each other. You start and watch each one yourself.

If you'd rather have one orchestrator assign issues to standing workers, wait on them and merge their
PRs, that is a [parallel round](parallel-rounds.md). Use this page for two or three sessions you are
watching; use a round for a queue.

## When to use this

- Long-running cycles you don't want to block on while other work proceeds.
- Independent feature tracks that shouldn't share a branch.
- Keeping `main` clean while agents work in parallel.
- Batching unrelated bug fixes that gain nothing from sharing context.

## Setting it up

Flip `work.isolation` to `"worktree"` via `hv config set work.isolation worktree` or by editing
`.hv/config.json` directly. See [configuration](configuration.md) for the full
option set. Once set, `/hv-work` creates a new directory under
`.claude/worktrees/<branch-name>` for each cycle instead of switching the
current worktree. The main worktree stays on `main` throughout.

## Two terminals, two streams

Start each stream in its own terminal. [`/hv-work` (no argument)](picking-work.md) picks items that aren't
already in progress, so the two sessions claim different work.

**Terminal 1** picks `[B02]` and `[F01]`:

```
/hv-work
# → suggests B02, F01
/hv-work
# → creates .claude/worktrees/fix/b02-timer-crash
#    and .claude/worktrees/feat/f01-dark-mode
```

**Terminal 2** picks `[F03]` (B02 and F01 are already in progress):

```
/hv-work
# → suggests F03 (B02 and F01 shown as In Progress, skipped)
/hv-work
# → creates .claude/worktrees/feat/f03-export-csv
```

Both streams run independently. See [running work](running-work.md) for the
full `/hv-work` lifecycle.

## How status.json stays consistent

Both sessions write to the same `.hv/status.json` in the main worktree,
but each owns different entries (one per active branch), so they don't
conflict under normal operation. `/hv-work` (no argument) in a third terminal sees both
streams as "In Progress" and skips those items when suggesting new work. If
you run `/hv-work` (no argument) while `/hv-work` is mid-update, the last writer wins; the
next `/hv-work` (no argument) run reconciles drift by validating status against actual
git state. For more on how `/hv-work` (no argument) reads and updates status, see
[picking work](picking-work.md).

## Caveats

Don't run `hv init` or `hv config set` from inside a worktree. Those write to
`.hv/` and must run in the main worktree. `/hv-work` runs, with or without an argument, are fine
in either place.
