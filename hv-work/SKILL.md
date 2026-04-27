---
name: hv-work
description: Orchestrator-driven parallel implementation — plans tasks, dispatches worker subagents, verifies, and commits atomically per task. Supports branch or worktree isolation and direct merge or PR. Trigger on "implement this", "build these", or any multi-step implementation request.
user-invocable: true
---

```
════════════════════════════════════════════════════════════════════════
  🟩  hv-work  ·  orchestrator-driven parallel implementation
  triggers: "implement", "build these"  ·  pairs: hv-ship, hv-review
════════════════════════════════════════════════════════════════════════
```

# hv-work

Orchestrator-driven parallel implementation with per-task verification and commits.

## Configuration

Read `.hv/config.json`:

- `models.orchestrator` — model for planning and verification (default `opus`)
- `models.worker` — model for implementation subagents (default `sonnet`)
- `work.isolation` — `"branch"` (default) or `"worktree"`
- `work.mergeStrategy` — `"direct"` (default) or `"pr"`
- `autonomy.level` — `"off"` (default), `"auto"`, or `"loop"`. Controls whether Step 13 (Learn), Step 14 (Refactor), and Step 15 (Loop continuation) nudge or invoke the next skill directly. See `GUIDE.md` § Autonomy.

## When to Use

- User describes a task, feature, or list of improvements
- Conversation has enough spec to act on
- Work is decomposable into 2+ independent pieces

## Flow

```
Guard → Clarify (if needed) → Status → Plan → Isolate → Dispatch → Verify → TODO → Merge/PR → Status
```

## Step 1 — Preflight & Guard

```bash
.hv/bin/hv-preflight
```

If the helper is absent or exits non-zero, invoke `hv-init` via the `Skill` tool, then continue. See GUIDE.md § Preflight for exit codes.

```bash
.hv/bin/hv-guard-clean "/hv-work"
```

Exit 0 = clean, continue. Exit 2 = not a repo, surface and stop.

**Exit 1 (dirty tree) — auto-sweep known tool siblings first.** Some toolchains generate sibling files *after* a previous `/hv-work` wave finished (Godot `.gd.uid`, Xcode `.xcworkspace/contents.xcworkspacedata`, SwiftPM `Package.resolved`, Tuist-regenerated `.xcodeproj`, `.DS_Store`). If these are all that's dirty, they belong in a `chore:` commit, not a refusal.

```bash
git status --porcelain
```

Classify every line:

- **Sibling artifact** — path matches a sibling of a tracked file (e.g. `Foo.gd.uid` next to tracked `Foo.gd`), or matches one of these patterns: `*.gd.uid`, `*.xcworkspace/contents.xcworkspacedata`, `Package.resolved`, `*.xcodeproj/project.pbxproj` regenerated without meaningful diff, `.DS_Store`.
- **User change** — anything else.

If **every** dirty path is a sibling artifact, sweep them into a single commit and continue:

```bash
git add -A -- <matching paths>
git commit -m "chore: sweep tool-generated siblings before hv-work"
```

If **any** path is a user change, stop with the original guard message — the user decides whether to stash, commit, or discard.

Don't narrate the sweep unless it happened; silent pass-through is the common case.

## Step 2 — Clarify Ambiguous Briefs (only when needed)

If — and only if — the current brief is too thin to plan concrete tasks (missing scope, conflicting requirements, or two equally plausible interpretations), use the `AskUserQuestion` tool to resolve the ambiguity before touching any code. Otherwise skip this step entirely — the default is to proceed.

Good reasons to ask:

- The scope hits 2+ incompatible files or areas, and picking one vs. both changes the plan materially.
- A requirement is vague in a way that yields opposite reasonable implementations (e.g., *"add sorting"* — ascending or descending, stable or not, which columns).
- Multiple captured items imply different orderings, and the user didn't say which to tackle first.

Bad reasons to ask (don't):

- To confirm you understand — just act.
- For preferences you can infer from `KNOWLEDGE.md` or the existing codebase.
- Style choices inside an agreed scope — that's implementation.

When asking, use a single `AskUserQuestion` call with 1-3 questions. Each question:

- Short `header` (e.g., `"Scope"`, `"Target"`, `"Order"`).
- Options map to concrete plans. Mark the most likely intent `(Recommended)`.
- For conflicting items, use `multiSelect: true` and ask which subset to include in this run.

Plain-text fallback: ask once. If the reply still doesn't resolve the ambiguity, pick the Recommended interpretation, state it explicitly in the dispatch brief, and proceed. (See GUIDE.md § Host Question Conventions.)

**Loop mode exception:** if `autonomy.level == "loop"` and the brief is genuinely ambiguous (you'd otherwise ask Step 2), **stop the loop** and surface the question for the user to resolve. Do not silently pick a default — invisible decisions across N looped items defeat the point of the loop. The user resolves and re-invokes `/hv-next` (or this `/hv-work`) to continue the queue.

## Step 3 — Register in Status

After picking the branch name:

```bash
.hv/bin/hv-status-add <branch> <ID1>,<ID2>[,...] [worktree-path]
```

Idempotent on branch name — call again with the worktree path once Step 5 creates it.

## Step 4 — Plan Tasks

**Plan-as-artifact check (first).** If the work has a milestone-and-unit key — an item tagged to a milestone (`Milestone: M01` on `B07` → key `M01-B07`) or a slice (`M01-S01`) — check for an existing plan:

```bash
.hv/bin/hv-plan-show <milestone>-<unit> 2>/dev/null
```

If a plan exists, **use it as the orchestrator's plan** — its task decomposition, files, verify steps, and assumptions become the dispatch briefs in Step 6 instead of decomposing ad-hoc. Restate any user redlines from the conversation, but don't silently re-derive what the user already signed off on. If the conversation contradicts the plan, ask the user whether to update the plan first (`/hv-plan` again) or proceed and ignore it. If no plan exists, proceed with the steps below.

From the conversation context:

1. **Consult project knowledge.** Read the `hv-knowledge` block in `CLAUDE.md` for the current topic list. For topics that plausibly touch the planned work, pull just those sections:

   ```bash
   .hv/bin/hv-knowledge-query "Architecture" "Testing"
   ```

   Carry the relevant gotchas/conventions into the task briefs (Step 6) under a `**Known gotchas:**` block — only the bullets that apply, not the whole file. Skip silently if nothing looks relevant.

2. Identify discrete tasks — files to create/modify, what changes, acceptance criteria.
3. Group into dependency waves:
   - **Wave 1:** independent files → parallel
   - **Wave 2+:** depend on wave 1 outputs → sequential or next parallel batch

## Step 5 — Create Branch or Worktree

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

## Step 6 — Dispatch Parallel Worker Agents

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

## Step 7 — Verify Each Completion

Orchestrator verifies internally (don't narrate):

1. Commit exists: `git log --oneline -1`
2. Read modified files — changes match the brief
3. Structural checks: grep for expected patterns, no regressions

**PASS** → move on silently. **FAIL** → dispatch a fix agent, re-verify. Surface failures only if they persist.

## Step 8 — Sequential Waves

For dependent tasks: wait for wave 1 to complete and verify, then dispatch wave 2 with updated context. Same verification.

## Step 8.5 — Sweep Tool-Generated Siblings

Some toolchains produce sibling artifacts when they first see a new source file — Godot's `.gd.uid`, Xcode's regenerated project plists, SwiftPM's `Package.resolved`. Workers often create source files without triggering the tool, leaving the siblings untracked. If left alone, the NEXT `/hv-work` hits Step 1's dirty-tree guard and refuses.

Before moving to the merge step, commit any remaining sibling artifacts as a single `chore:`:

```bash
git status --porcelain
```

If any lines match the sibling patterns from Step 1 (`*.gd.uid`, `*.xcworkspace/contents.xcworkspacedata`, `Package.resolved`, `.DS_Store`, or siblings of tracked files touched in this cycle):

```bash
git add -A -- <matching paths>
git commit -m "chore: track tool-generated siblings"
```

If the tree has non-sibling dirt, surface it — a worker produced unexpected changes and the orchestrator should investigate before merging.

For projects where a tool regenerates siblings only when the editor loads (Godot `class_name`, for example): if the cycle introduced new `class_name` declarations and `.gd.uid` files are missing, force generation once with the tool's headless mode before the sweep — e.g., `godot --headless --editor --quit`. Project-specific commands should be captured in `KNOWLEDGE.md` so subsequent cycles learn the right invocation.

## Step 9 — Update TODO.md

```bash
.hv/bin/hv-complete <ID> <commit-hash>
```

Run per resolved item. Match by keyword overlap between task description and TODO entry title. If unsure whether an item was addressed, leave it — don't move items you didn't work on.

## Step 10 — Merge or PR

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

## Step 11 — Update Status

```bash
.hv/bin/hv-status-remove <branch>
```

## Step 12 — Report to User

One compact summary:

```
Done — merged `hv/fix-timer-badge` into main.

- [B01] Timer badge shows stale duration — fixed invalidation in MenuBarManager
- [F03] Quick-switch projects — added Cmd+Tab overlay to project picker

Commit: a1b2c3d
```

Don't recap the plan, list verification results, or describe intermediate steps.

## Step 13 — Learn (Nudge or Auto-Invoke)

Trigger condition (same in all modes): **2+ items resolved**, OR **≥5 files touched**, OR a **hard bug** that took multiple debug cycles. Skip entirely for single-item fixes and pure mechanical changes. Don't repeat in the same session.

When triggered, branch on `autonomy.level`:

- `"off"` (default) — print one line: *"Capture learnings from this session? Run `/hv-learn` to save durable knowledge before context fades."* — opt-in.
- `"auto"` or `"loop"` — invoke `hv-learn` via the `Skill` tool. Pass a brief that names the cycle's resolved IDs and the touched files so the verifier (if `learn.verify: true`) has the right context. No prompt, no confirmation.

## Step 14 — Refactor (Nudge or Auto-Invoke)

```bash
.hv/bin/hv-refactor-age
```

Returns JSON: `{"features": N, "bugs": M}` — count of items completed since the last `refactor:` commit. Threshold: `features >= 5` OR `bugs >= 10`. If under threshold, skip the step entirely. Don't repeat in the same session.

When triggered, branch on `autonomy.level`:

- `"off"` (default) — print one line: *"You've shipped [N] features / [M] bug fixes since the last refactor. Might be a good time to run `/hv-refactor` to clean up accumulated friction."*
- `"auto"` or `"loop"` — invoke `hv-refactor` via the `Skill` tool. `refactor.confirmBeforeExecute` still governs whether `/hv-refactor` itself pauses for approval at its own checkpoints, so the user retains a steering wheel even under autonomy.

## Step 15 — Loop Continuation

Only when `autonomy.level == "loop"`. Invoke `hv-next` via the `Skill` tool to surface the next item and continue the queue. `/hv-next` reads autonomy too — in loop mode it auto-selects the suggested item and dispatches `/hv-work`, so the loop sustains itself.

Loop stops naturally when:
- `/hv-next` reports an empty backlog (or the active milestone has no items and the general backlog is also empty)
- A guard fails downstream (dirty tree, `/hv-review` FAIL, ambiguous brief in Step 2)
- The user interrupts

Skip this step entirely for `"off"` and `"auto"` modes — the user picks what's next themselves.

## Key Principles

- **No noise.** Report results, not process. Don't narrate steps that produced nothing.
- **Orchestrator plans and verifies; worker executes.** Never dispatch without a clear brief. Never trust completion without reading the result.
- **Orchestrator owns `.hv/` state.** Only the orchestrator touches `status.json` and `TODO.md`. Workers focus on implementation.
- **Isolation protects main.** Branch or worktree — never work directly on main.
- **One commit per task.** Clean history, easy revert granularity.
