---
name: hv:work
description: Orchestrator-driven parallel implementation — plans tasks, dispatches worker subagents, verifies, and commits atomically per task. Supports branch or worktree isolation and direct merge or PR. Trigger on "implement this", "build these", or any multi-step implementation request.
user-invocable: true
---

# hv:work

Orchestrator-driven parallel implementation with per-task verification and commits.

## Configuration

Read `.hv/config.json`:

- `models.orchestrator` — model for planning and verification (default `opus`)
- `models.worker` — model for implementation subagents (default `sonnet`)
- `work.isolation` — `"branch"` (default) or `"worktree"`
- `work.mergeStrategy` — `"direct"` (default) or `"pr"`

## When to Use

- User describes a task, feature, or list of improvements
- Conversation has enough spec to act on
- Work is decomposable into 2+ independent pieces

## Flow

```
Guard → Status → Plan → Isolate → Dispatch → Verify → TODO → Merge/PR → Status
```

## Step 1 — Preflight & Guard

If `.hv/bin/hv-guard-clean` doesn't exist, invoke `hv:init` via the `Skill` tool, then continue. Then:

```bash
.hv/bin/hv-guard-clean "/hv:work"
```

Non-zero exit = stop and surface the script's message.

## Step 2 — Register in Status

After picking the branch name:

```bash
.hv/bin/hv-status-add <branch> <ID1>,<ID2>[,...] [worktree-path]
```

Idempotent on branch name — call again with the worktree path once Step 4 creates it.

## Step 3 — Plan Tasks

From the conversation context:

1. **Consult project knowledge.** Read the `hv:knowledge` block in `CLAUDE.md` for the current topic list. For topics that plausibly touch the planned work, pull just those sections:

   ```bash
   .hv/bin/hv-knowledge-query "Architecture" "Testing"
   ```

   Carry the relevant gotchas/conventions into the task briefs (Step 5) under a `**Known gotchas:**` block — only the bullets that apply, not the whole file. Skip silently if nothing looks relevant.

2. Identify discrete tasks — files to create/modify, what changes, acceptance criteria.
3. Group into dependency waves:
   - **Wave 1:** independent files → parallel
   - **Wave 2+:** depend on wave 1 outputs → sequential or next parallel batch

## Step 4 — Create Branch or Worktree

Choose a descriptive name (e.g., `hv/quick-switch`, `hv/fix-timer-badge`).

**Branch isolation:**

```bash
git checkout -b <branch-name>
```

**Worktree isolation:**

```bash
git branch <branch-name>
git worktree add .claude/worktrees/<branch-name> <branch-name>
.hv/bin/hv-status-add <branch> <ID1>,<ID2>[,...] .claude/worktrees/<branch-name>
```

Orchestrator stays in the main worktree (retains `.hv/` access). Workers get the absolute worktree path in their briefs and work there.

## Step 5 — Dispatch Parallel Worker Agents

For each independent task, dispatch a subagent with the **worker** model:

```
You are implementing Task N of [total].
[WORKTREE: "Working directory: <absolute-worktree-path>. cd there before any file operations."]

**Goal:** [one sentence]

**Files:**
- Create: [paths]
- Modify: [paths with line references]

**What to do:**
[Precise instructions — what to read, what to change, exact code where possible]

**Known gotchas:**
[Relevant bullets from hv-knowledge-query output]

**Critical constraints:**
[Behavior preservation, patterns to follow, things NOT to touch]

**Commit with message:**
[exact commit message to use]
```

Rules for briefs: exact paths + line numbers; show the pattern to follow; name the commit message (agents commit themselves); read-first, minimal-diff, no unrelated changes.

Launch all independent agents in one message (parallel tool calls). Don't announce — just do it.

## Step 6 — Verify Each Completion

Orchestrator verifies internally (don't narrate):

1. Commit exists: `git log --oneline -1`
2. Read modified files — changes match the brief
3. Structural checks: grep for expected patterns, no regressions

**PASS** → move on silently. **FAIL** → dispatch a fix agent, re-verify. Surface failures only if they persist.

## Step 7 — Sequential Waves

For dependent tasks: wait for wave 1 to complete and verify, then dispatch wave 2 with updated context. Same verification.

## Step 8 — Update TODO.md

```bash
.hv/bin/hv-complete <ID> <commit-hash>
```

Run per resolved item. Match by keyword overlap between task description and TODO entry title. If unsure whether an item was addressed, leave it — don't move items you didn't work on.

## Step 9 — Merge or PR

**Direct merge:**

```bash
printf 'merge: <summary>\n\n- task 1 description\n- task 2 description\n' | .hv/bin/hv-merge <branch>
```

The helper removes any worktree for the branch, checks out main, merges `--no-ff` with the piped message, deletes the branch, and prints the merge commit's short hash.

**PR:**

```bash
printf '## Summary\n- item 1\n- item 2\n\n## Items resolved\n- [B01] Title\n- [F03] Title\n\n## Test plan\n- [ ] ...\n' \
  | .hv/bin/hv-pr <branch> "<short title>"
```

The helper removes any worktree, pushes the branch with `-u`, and runs `gh pr create`. Share the PR URL with the user.

## Step 10 — Update Status

```bash
.hv/bin/hv-status-remove <branch>
```

## Step 11 — Report to User

One compact summary:

```
Done — merged `hv/fix-timer-badge` into main.

- [B01] Timer badge shows stale duration — fixed invalidation in MenuBarManager
- [F03] Quick-switch projects — added Cmd+Tab overlay to project picker

Commit: a1b2c3d
```

Don't recap the plan, list verification results, or describe intermediate steps.

## Step 12 — Learn Nudge

If the session produced non-trivial learning material — **2 or more items resolved**, or **≥5 files touched**, or a **hard bug** that took multiple debug cycles — suggest capturing it while it's fresh:

*"Capture learnings from this session? Run `/hv:learn` to save durable knowledge before context fades."*

One line, opt-in. Skip the nudge for single-item fixes or tasks that were pure mechanical changes. Don't repeat in the same session.

## Step 13 — Refactor Nudge

```bash
.hv/bin/hv-refactor-age
```

Returns JSON: `{"features": N, "bugs": M}` — count of items completed since the last `refactor:` commit. If `features >= 5` or `bugs >= 10`, tell the user:

*"You've shipped [N] features / [M] bug fixes since the last refactor. Might be a good time to run `/hv:refactor` to clean up accumulated friction."*

Suggestion, not a blocker. Don't repeat in the same session.

## Key Principles

- **No noise.** Report results, not process. Don't narrate steps that produced nothing.
- **Orchestrator plans and verifies; worker executes.** Never dispatch without a clear brief. Never trust completion without reading the result.
- **Orchestrator owns `.hv/` state.** Only the orchestrator touches `status.json` and `TODO.md`. Workers focus on implementation.
- **Isolation protects main.** Branch or worktree — never work directly on main.
- **One commit per task.** Clean history, easy revert granularity.
