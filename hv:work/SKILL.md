---
name: hv:work
description: Use when the user has described a task, feature, or set of improvements to implement — orchestrator plans, parallel worker subagents execute each piece, orchestrator verifies, and atomic commits are created per task. Supports branch or worktree isolation and direct merge or PR. Trigger on "implement this", "build these", "do this work", or any multi-step implementation request.
user-invocable: true
---

# hv:work

Orchestrator-driven parallel implementation with per-task verification and commits.

## Configuration

Before starting, read `.hv/config.json` if it exists. It contains:

```json
{
  "models": {
    "orchestrator": "opus",
    "worker": "sonnet"
  },
  "work": {
    "isolation": "branch",
    "mergeStrategy": "direct"
  }
}
```

- `models.orchestrator` — model for planning and verification (Agent `model` parameter)
- `models.worker` — model for implementation subagents (Agent `model` parameter)
- `work.isolation` — `"branch"` (default) or `"worktree"`
- `work.mergeStrategy` — `"direct"` (default) or `"pr"`

If `.hv/config.json` doesn't exist, default to `opus`/`sonnet`, `branch` isolation, `direct` merge.

## When to Use

- User describes a task, feature, or list of improvements
- Conversation context contains enough spec to act on
- Work is decomposable into 2+ independent pieces

## Flow

```
Guard → Status → Plan → Isolate → Dispatch → Verify → TODO → Merge/PR → Status
```

## Step 1 — Guard: Clean Working Tree

Check for uncommitted changes: `git status --porcelain`

- If the output is empty → proceed
- If there are uncommitted changes → **stop and warn the user**:
  *"You have uncommitted changes. Stash them (`git stash`) or commit them before running /hv:work, so work happens on a clean base."*
  Do not proceed until the working tree is clean.

## Step 2 — Register in Status

Read `.hv/status.json`. Add an entry for this work session:

```json
{
  "items": ["F-1", "B-2"],
  "branch": "hv/quick-switch",
  "worktree": null,
  "startedAt": "2026-04-15T12:00:00Z"
}
```

Set `worktree` to `null` for branch isolation, or the worktree path for worktree isolation (filled in Step 4). Write status.json immediately — this registers the work so `/hv:next` in another session can see it.

## Step 3 — Plan Tasks

From the conversation context (user request, prior analysis, existing code):

1. Identify all discrete tasks to implement
2. For each task, determine: files to create/modify, what changes, acceptance criteria
3. Group into dependency waves:
   - **Wave 1:** All tasks that touch independent files (run in parallel)
   - **Wave 2+:** Tasks that depend on wave 1 outputs (sequential or next parallel batch)

## Step 4 — Create Branch or Worktree

Choose a descriptive name based on the work (e.g., `hv/quick-switch`, `hv/fix-timer-badge`).

**If `isolation` is `"branch"`:**

```bash
git checkout -b <branch-name>
```

Sub-agents work in the current directory.

**If `isolation` is `"worktree"`:**

```bash
git branch <branch-name>
git worktree add .claude/worktrees/<branch-name> <branch-name>
```

Update the `worktree` field in `.hv/status.json` with the worktree path (e.g., `.claude/worktrees/hv-quick-switch`).

The **orchestrator stays in the main worktree** and retains access to `.hv/`. Sub-agents receive the absolute worktree path in their briefs and work there. All git operations in agent briefs use the worktree path.

## Step 5 — Dispatch Parallel Worker Agents

For each independent task, dispatch a subagent using the configured **worker** model with:

```
You are implementing Task N of [total].
[WORKTREE: if worktree isolation, include "Working directory: <absolute-worktree-path>. cd there before any file operations."]

**Goal:** [one sentence]

**Files:**
- Create: [paths]
- Modify: [paths with line references]

**What to do:**
[Precise instructions — what to read, what to change, exact code where possible]

**Critical constraints:**
[Behavior preservation rules, patterns to follow, things NOT to touch]

**Commit with message:**
[exact commit message to use]
```

**Rules for agent briefs:**
- Include enough context that the agent can work without asking questions
- Specify exact file paths and relevant line numbers
- Show the code pattern to follow (from existing codebase)
- Name the commit message — agents commit their own work
- Constraint: read files first, minimal diff, no unrelated changes
- If worktree isolation: always include the absolute worktree path and instruct the agent to work there

Launch all independent agents in a single message (parallel tool calls).

## Step 6 — Verify Each Completion

As each agent completes, the orchestrator verifies:

1. **Check the commit exists:** `git log --oneline -1` (in the worktree if applicable)
2. **Read the modified files** — confirm changes match the brief
3. **Structural verification:** grep for expected patterns, count functions, check no regressions

Verdicts:
- **PASS** — commit is correct, move on
- **FAIL** — dispatch a fix agent with the specific issue, then re-verify

## Step 7 — Sequential Waves

If tasks have dependencies (shared files, one task's output feeds another):

1. Wait for wave 1 to complete and verify
2. Dispatch wave 2 agents with updated context (they can read wave 1's committed code)
3. Verify wave 2 the same way

## Step 8 — Update TODO.md

After all tasks pass verification, check if `.hv/TODO.md` exists. If it does:

1. Read `.hv/TODO.md`
2. For each completed task, find matching entries in `## Bugs`, `## Features`, or `## Todos`
3. Move matched entries to `## Completed`, appending metadata:

```markdown
## Completed

- ~~**[B-1] [P1] Timer badge shows stale duration.**~~ Done 2025-04-15 [`a1b2c3d`]
- ~~**[F-3] [Minor] Quick-switch recent projects.**~~ Done 2025-04-15 [`f4e5d6c`]
- ~~**[T-1] Update Swift toolchain.**~~ Done 2025-04-15 [`d7e8f9a`]
```

Format: `- ~~**[ID] [tag] Title.**~~ Done YYYY-MM-DD [\`<short-hash>\`]`

Get the commit hash from `git log --oneline -1` (use the short hash of the merge commit or the last task commit).

**Matching rules:**
- Match by keyword overlap between the task description and TODO entry titles
- If unsure whether a TODO item was addressed, leave it in place — don't move items you didn't work on
- If the `## Completed` section doesn't exist, create it at the end of the file

## Step 9 — Merge or PR

**If `mergeStrategy` is `"direct"`:**

```bash
# 1. Remove the worktree (only if worktree isolation was used)
#    Must happen before branch delete — git won't delete a branch checked out in a worktree
git worktree remove .claude/worktrees/<branch-name>

# 2. Merge and clean up
git checkout main
git merge <branch> --no-ff -m "merge: <summary of all work>

- task 1 description
- task 2 description
..."
git branch -d <branch>
```

Skip the `worktree remove` step if branch isolation was used (no worktree exists).

**If `mergeStrategy` is `"pr"`:**

```bash
# Remove the worktree but keep the branch (only if worktree isolation was used)
git worktree remove .claude/worktrees/<branch-name>

git push -u origin <branch>
gh pr create --title "<short summary>" --body "$(cat <<'EOF'
## Summary
- item 1 description
- item 2 description

## Items resolved
- [B-1] Title
- [F-3] Title

## Test plan
- [ ] Verify each item's acceptance criteria
- [ ] Check for regressions
EOF
)"
```

Share the PR URL with the user.

## Step 10 — Update Status

Remove this work session's entry from `.hv/status.json`. This marks the work as complete so `/hv:next` no longer shows these items as in-progress.

## Step 11 — Refactor Nudge

After completing all work, count the entries in `## Completed` and `ARCHIVE.md` (if it exists) that don't have a `refactor:` commit prefix — i.e., items completed by `/hv:work`, not by `/hv:refactor`. Count features (`[F-*]`) and bugs (`[B-*]`) separately.

If **5 or more features** or **10 or more bugs** have been completed since the last refactor, tell the user:

*"You've shipped [N] features / [N] bug fixes since the last refactor. Might be a good time to run `/hv:refactor` to clean up accumulated friction."*

This is a suggestion, not a blocker. Don't repeat it if the user has already been nudged in this session.

## Key Principles

- **Orchestrator plans and verifies, worker executes.** Models are configured in `.hv/config.json` (default: opus/sonnet). Never dispatch work without a clear brief. Never trust completion without reading the result.
- **Orchestrator owns `.hv/` state.** Only the orchestrator reads and writes `.hv/status.json` and `.hv/TODO.md`. Sub-agents never touch these files — they focus on implementation.
- **Clean base.** Never start work on a dirty working tree. Guard against it.
- **One commit per task.** Each agent commits its own atomic change. This gives clean git history and easy revert granularity.
- **Parallel by default.** Independent tasks always run in parallel. Sequential only when there's a real file conflict or data dependency.
- **Agents commit themselves.** Include the commit message in the brief. The orchestrator doesn't batch-commit — each task is self-contained.
- **Isolation protects main.** Branch or worktree — work never happens directly on main.
- **Read before edit.** Every agent brief must instruct reading target files first.
- **Fail fast.** If an agent's work fails verification, fix it before moving to dependent tasks.
- **Track completions.** Always update TODO.md and status.json when items are resolved.
