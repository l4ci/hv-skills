# Implementing

Items captured in [`BACKLOG.md`](../reference/hv-folder.md) reach "merged" through `/hv-work`, an orchestrator that plans, dispatches parallel workers, and lands one atomic commit per task. For a single ad-hoc fix, `/hv-capture` ends with an optional hand-off to `/hv-work`.

## /hv-work

`/hv-work` is the main implementation driver. The orchestrator plans tasks, dispatches workers in parallel (one per task), verifies each result, then either merges to main or opens a PR based on your `work.mergeStrategy`.

**Trigger phrases:**

- `/hv-work` with no argument reconciles the backlog, suggests an item, then works it
- `/hv-work [B03]` to implement a specific item by ID
- `/hv-work [B03] [F07]` to implement a batch of items together
- `/hv-work "add retry logic to the upload pipeline"` describes the work; it captures and executes

**Precondition:** refuses to start on a dirty working tree. Commit or stash first.

**Status tracking:** registers in `.hv/status.json` at start so [`/hv-work` (no argument)](picking-work.md) in another session knows those items are in progress.

```mermaid
sequenceDiagram
    participant U as User
    participant O as Orchestrator
    participant W1 as Worker 1
    participant W2 as Worker 2
    participant G as Git

    U->>O: /hv-work [B03] [F07]
    O->>G: clean-tree guard
    O->>O: plan tasks into waves
    O->>G: create branch hv/<slug>
    par Wave 1 (parallel, write-only)
        O->>W1: brief: edit files for Task A
        O->>W2: brief: edit files for Task B
    end
    W1-->>O: report files modified
    W2-->>O: report files modified
    O->>O: verify diffs match briefs
    O->>G: commit Task A
    O->>G: commit Task B
    O->>G: merge --no-ff (or open PR)
    O-->>U: summary: branch landed
```

## One commit per task

Each task lands as its own atomic commit. One item, one commit, tagged with the item ID:

```
a1b2c3d fix: retry logic on network timeout [B03]
d4e5f6a feat: per-project theme support [F07]
g7h8i9j task: update CI to Node 20 [T02]
```

That keeps reverts surgical (drop one task without touching others), makes PR review easier (read commit by commit), and leaves a predictable history `/hv-ship` reads to build PR bodies automatically.

## Isolation: branch vs. worktree

Set `work.isolation` in [`config.json`](configuration.md):

| Mode | How it works | When to use |
|------|-------------|-------------|
| `"branch"` (default) | Feature branch in the current worktree | Solo work, simple workflows |
| `"worktree"` | Isolated directory under `.claude/worktrees/` | Parallel sessions, keep main clean while agents work |

With `"branch"`, your main worktree switches to the feature branch for the duration of the run. With `"worktree"`, the main worktree stays on `main`, so you can keep editing there while agents work in isolation.

To run multiple `/hv-work` sessions at the same time on different item batches, pick `"worktree"`. See [parallel-work](parallel-work.md) for the multi-session pattern.

## Capture, then work it now

For a single ad-hoc fix, run `/hv-capture` and accept the hand-off at the end: it offers to work the new item now and routes to `/hv-work`.

```
/hv-capture "fix the off-by-one in RingBuffer"
/hv-capture "add a Cmd+K shortcut to the project picker"
```

The item gets a real ID in `BACKLOG.md` (counters increment, history is preserved). Decline the hand-off and it stays queued. If you're still exploring or the scope is fuzzy, decline and refine the entry first.

**Flow:** `/hv-capture` files the item, then (on accept) `/hv-work` implements it. All `/hv-capture` rules (classification, detail-file overflow, ID assignment) and all `/hv-work` rules (clean-tree guard, branch/worktree isolation, parallel workers, per-task commits) apply.

## Capture vs. Work: picking the right entry

Pick by **intent**, not by the verb typed:

| The user wants to… | Use | Why |
|---------------------|-----|-----|
| Brain-dump items into the backlog without acting now | `/hv-capture` (decline the hand-off) | Records only; no execution, no clean-tree guard |
| Get one specific thing done right now (not yet captured) | `/hv-capture`, accept the hand-off | Captures, then runs `/hv-work` on the new item |
| Implement an item that's already in `BACKLOG.md` | `/hv-work <ID>` | Plans, dispatches workers, verifies, commits per task |
| Pick the next thing from the backlog and execute | `/hv-work` (no argument) | Reconciles, suggests, then works the pick |

**Rules of thumb:**

- *"fix X"* / *"add Y"* / *"do Z"*: clear single thing, not yet captured: `/hv-capture`, then accept the hand-off.
- A list of things, no immediate action, *"capture this"* / *"add to backlog"*: `/hv-capture`, decline the hand-off.
- Reference to an existing `[B##]`/`[F##]`/`[T##]` plus *"implement"* / *"build"* / *"do this one"*: `/hv-work <ID>`.
- *"what's next?"* / *"pick something"* / *"what should I work on?"*: `/hv-work` with no argument.

When intent is ambiguous, `/hv-capture` is the cheapest path: the hand-off is optional, so you can still decline.

See [capturing work](capturing-work.md) for capture details and [picking work](picking-work.md) for how the no-argument `/hv-work` selects and prioritizes.

## Merge or PR

After `/hv-work` finishes, `work.mergeStrategy` in `config.json` controls what happens next:

| Strategy | Behavior |
|----------|----------|
| `"direct"` (default) | Merges the branch to main with `--no-ff`, deletes the branch |
| `"pr"` | Pushes the branch and creates a GitHub PR with a summary |

The actual ship-time gates (review, preflight, PR body composition) live in [review and ship](review-and-ship.md).

## Many items at once

`/hv-work` takes items one session at a time, with subagents inside that session. To run several issues in parallel, each worker in its own worktree and terminal tab, use a round: run `hv doctor`, then ask for `/hv-orchestrate`. See [parallel rounds](parallel-rounds.md), the [`hv round` verbs](../reference/cli-helpers.md#hv-round) and [`/hv-orchestrate`](../reference/slash-commands.md#hv-orchestrate).
