# hv-skills Guide

A detailed guide to the hv-skills workflow system for Claude Code.

## Overview

hv-skills is a lightweight project backlog and execution system. It lives entirely in a `.hv/` folder inside your project (gitignored) and uses Claude Code skills to capture work items, prioritize them, and execute them with parallel subagents.

The workflow is: **capture → prioritize → execute → refactor**.

## The .hv/ Folder

Run `/hv:init` once per project to create the folder. It contains:

| File | Purpose |
|------|---------|
| `TODO.md` | Active backlog — bugs, features, todos, and recent completions |
| `counters.json` | Auto-incrementing IDs for each item type |
| `config.json` | Model selection, isolation mode, merge strategy, refactor settings |
| `status.json` | Active work streams — which items are being worked on, on which branch/worktree |
| `ARCHIVE.md` | Completed items older than 5 days, moved here automatically |

All files are gitignored. The backlog is local to your machine.

## Skills Reference

### /hv:init

Creates the `.hv/` folder with all required files. Safe to run multiple times — never overwrites existing files. Also adds `.hv/` to `.gitignore` if not already present.

### /hv:bug

Captures a bug report. Asks 2-4 quick questions to gather context, assigns a priority (P0/P1/P2), and appends it to `TODO.md` with an auto-incrementing `[B-N]` ID. Scans existing items (including the archive) for related entries and links them.

### /hv:feature

Captures a feature idea. Asks 2-4 quick questions, assigns a size (Major/Minor/Cosmetic), and appends it to `TODO.md` with an `[F-N]` ID. Scans for related items.

### /hv:todo

Captures a general task or chore. Asks 1-3 questions and appends to `TODO.md` with a `[T-N]` ID. Use for anything that isn't a bug or feature — refactoring, documentation, dependency updates, research.

### /hv:next

Reviews the backlog and suggests what to work on. Does several things before presenting the table:

1. **Reconciles active work** — reads `status.json` and validates against git state. Detects completed branches that were never merged, interrupted work that can be resumed, and stale entries that need cleanup.
2. **Archives old completions** — moves items completed more than 5 days ago from `TODO.md` to `ARCHIVE.md`.
3. **Builds a relationship map** — finds `Related:` links across all items and identifies clusters of connected work.
4. **Presents the backlog** — tables sorted by priority/size, with a Related column and cluster notes.
5. **Suggests next work** — P0 bugs first, then clusters with blocking bugs, quick wins, P1 bugs, blocking todos, features.
6. **Routes to /hv:work** — after the user confirms.

### /hv:work

Executes a batch of work items with parallel subagents. The orchestrator (default: opus) plans the tasks, the workers (default: sonnet) implement them.

**Isolation modes** (configured in `config.json`):

- `"branch"` (default) — creates a feature branch in the current worktree. Simple, works everywhere.
- `"worktree"` — creates an isolated git worktree under `.claude/worktrees/`. The orchestrator stays in the main worktree (retaining access to `.hv/`), while sub-agents work in the worktree. This lets you keep working on main while agents execute, and supports running multiple `/hv:work` sessions in parallel on different item batches.

**Merge strategies** (configured in `config.json`):

- `"direct"` (default) — merges the branch into main with `--no-ff` after all verification passes, then deletes the branch.
- `"pr"` — pushes the branch and creates a GitHub PR with a summary of items resolved and a test plan. The branch stays open for review.

**Safety**: refuses to start on a dirty working tree. Stash or commit first.

**Status tracking**: registers in `status.json` at the start, removes the entry on completion. This lets `/hv:next` in another session see what's in progress and avoid suggesting the same items.

### /hv:refactor

Runs a full architectural refactor cycle. The orchestrator explores the codebase for friction, categorizes each finding by dependency type, classifies it as simple or structural, and then fixes everything.

**For structural changes** (module boundary reshaping, concept consolidation), it spawns 3-4 parallel design agents with competing constraints (minimal interface, maximum flexibility, caller-optimized, ports & adapters), compares the results, and recommends the strongest approach.

**User checkpoints** (configurable): when `confirmBeforeExecute` is `true` (default), pauses after presenting findings and after design selection so the user can steer. Set `false` for full autonomy.

**Safety**: refuses to start on a dirty working tree.

## Configuration

All settings live in `.hv/config.json`. Edit it directly — no special command needed.

```json
{
  "models": {
    "orchestrator": "opus",
    "worker": "sonnet"
  },
  "work": {
    "isolation": "branch",
    "mergeStrategy": "direct"
  },
  "refactor": {
    "confirmBeforeExecute": true
  }
}
```

### Model choices

| Value | Best for |
|-------|----------|
| `"opus"` | Deep reasoning — planning, exploration, verification, design |
| `"sonnet"` | Fast execution — implementing well-specified tasks |
| `"haiku"` | Quick, cheap — simple fixes, small tasks |

### Isolation modes

| Mode | How it works | When to use |
|------|-------------|-------------|
| `"branch"` | Feature branch in current worktree | Solo work, simple workflows |
| `"worktree"` | Isolated directory under `.claude/worktrees/` | Parallel work streams, keep main clean while agents work |

### Merge strategies

| Strategy | How it works | When to use |
|----------|-------------|-------------|
| `"direct"` | Merge to main, delete branch | Solo work, fast iteration |
| `"pr"` | Push branch, create GitHub PR | Team work, code review required |

## Related Items

Any item can link to other items with a `Related:` suffix:

```markdown
- **[B-5] [P1] Timer badge stale after pause.** Description... Related: [F-3]
```

Links are optional and bidirectional — `/hv:next` infers the reverse link automatically. When linked items form clusters, `/hv:next` suggests tackling them together.

Capture skills scan both `TODO.md` and `ARCHIVE.md` for connections, so a new bug can link to a completed feature.

## Concurrent Work Streams

With `"isolation": "worktree"`, you can run multiple `/hv:work` sessions in parallel from separate terminals:

```
Terminal 1: /hv:next → picks [F-1], [B-2] → /hv:work
Terminal 2: /hv:next → picks [F-3]        → /hv:work
```

Each session creates its own worktree and branch. Both orchestrators write to the same `.hv/status.json` in the main worktree (they own different entries, so no conflicts). `/hv:next` in a third terminal will show both work streams as "In Progress" and skip those items when suggesting new work.

## State Tracking

`status.json` is a cache for speed. **Git is the source of truth.**

`/hv:next` always validates `status.json` against actual git state:
- Branches that exist → work is in progress or ready to merge
- Branches that were deleted → stale status entries, cleaned up automatically
- Worktrees that exist → active parallel work stream
- Worktrees that were removed → entry updated or cleaned up

If `status.json` ever gets out of sync (crashed session, manual git operations), `/hv:next` repairs it by checking `git branch` and `git worktree list`.
