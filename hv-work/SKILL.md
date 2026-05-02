---
name: hv-work
description: Orchestrator-driven parallel implementation — plans tasks, dispatches worker subagents, verifies, commits atomically per task. Supports branch or worktree isolation and direct merge or PR. Use when items already exist in TODO.md and need implementation ("implement [B07]", "build these"); for an item not yet captured use /hv-go.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  🔨  hv-work  ·  orchestrator-driven parallel implementation
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
- `autonomy.level` — `"off"` (default), `"auto"`, or `"loop"`. Controls whether Step 13 (Learn), Step 14 (Refactor), and Step 15 (Loop continuation) nudge or invoke the next skill directly.

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

See `docs/reference/preflight.md` for exit-code handling.

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

Plain-text fallback: ask once. If the reply still doesn't resolve the ambiguity, pick the Recommended interpretation, state it explicitly in the dispatch brief, and proceed.

**Loop mode exception:** if `autonomy.level == "loop"` and the brief is genuinely ambiguous (you'd otherwise ask Step 2), **stop the loop** and surface the question for the user to resolve. Do not silently pick a default — invisible decisions across N looped items defeat the point of the loop. The user resolves and re-invokes `/hv-next` (or this `/hv-work`) to continue the queue.

## Step 3 — Register in Status

After picking the branch name:

**Single-repo:**

```bash
.hv/bin/hv-status-add <branch> <ID1>,<ID2>[,...] [worktree-path]
```

**Umbrella mode** (when `umbrella.enabled` is true and items carry `Repos:`): parse the `Repos:` field from each item's TODO entry; all items in the wave must share a sub-repo (V1 = single-repo per wave). Pass it via `--repo`:

```bash
.hv/bin/hv-status-add --repo <repo-name> <branch> <ID1>,<ID2>[,...] [worktree-path]
```

Parse the `Repos:` field by grepping the item bullet from `.hv/TODO.md`:

```bash
grep -E "^- \*\*\[<ID>\]" .hv/TODO.md | grep -oE "Repos:\s*[a-zA-Z0-9_-]+" | head -1 | sed 's/Repos:\s*//'
```

Idempotent on `(branch, repo)` — call again with the worktree path once Step 5 creates it.

## Step 4 — Plan Tasks

**Plan-as-artifact check (first).** If the work has a milestone-and-unit key — an item tagged to a milestone (`Milestone: M01` on `B07` → key `M01-B07`) or a slice (`M01-S01`) — check for an existing plan:

```bash
.hv/bin/hv-plan-show <milestone>-<unit> 2>/dev/null
```

If a plan exists, **use it as the orchestrator's plan** — its task decomposition, files, verify steps, and assumptions become the dispatch briefs in Step 6 instead of decomposing ad-hoc. Restate any user redlines from the conversation, but don't silently re-derive what the user already signed off on. If the conversation contradicts the plan, ask the user whether to update the plan first (`/hv-plan` again) or proceed and ignore it. If no plan exists, proceed with the steps below.

From the conversation context:

1. **Consult knowledge + decisions.** Read the `hv-knowledge` and `hv-decisions` blocks in `CLAUDE.md`. For topics that touch the planned work, pull just those sections:

   ```bash
   .hv/bin/hv-knowledge-query "Architecture" "Testing"
   .hv/bin/hv-decisions-query "Architecture" "Testing"
   ```

   Carry matches into Step 6 briefs as `**Known gotchas:**` (relevant knowledge bullets only) and `**Hard boundaries:**` (full decision entries — rule + *Why* + **Forbids** + **Permits**). Workers must treat boundaries as constraints, not hints. If a planned task would violate a decision, **stop and surface to the user** before dispatching. Skip silently if nothing matches.

2. Identify discrete tasks — files to create/modify, what changes, acceptance criteria.
3. Group into dependency waves:
   - **Wave 1:** independent files → parallel
   - **Wave 2+:** depend on wave 1 outputs → sequential or next parallel batch

## Step 4.5 — Umbrella Pre-Flight (when umbrella mode is on)

If `umbrella.enabled` in `.hv/config.json` is true, every item in the planned wave MUST carry a `Repos:` tag pointing at a registered sub-repo in `.hv/repos.json`. Otherwise, `/hv-work` cannot route the work.

**Gate check:**

```bash
python3 -c "
import json, sys
cfg = json.loads(open('.hv/config.json').read())
print('on' if cfg.get('umbrella', {}).get('enabled') else 'off')
"
```

If umbrella mode is **off**, skip this step entirely (single-repo path).

If **on**:

1. For each item ID in the wave, parse `Repos:` from `.hv/TODO.md`. If any item lacks a `Repos:` tag, **stop with this error**:

   > Error: `[<ID>]` lacks a `Repos:` tag. Re-run `/hv-capture` to add it, or capture as multi-repo via M03 (deferred). Cannot route to a sub-repo.

2. All items in the wave must share the same sub-repo name (V1 single-repo-per-wave). If they diverge, surface this error and ask the user to split into separate `/hv-work` runs:

   > Error: items in this wave target different sub-repos: `<list>`. V1 supports one sub-repo per `/hv-work` run. Split into separate runs, or wait for M03 multi-repo support.

3. Confirm the named sub-repo exists in `.hv/repos.json`. If not, error and point at `/hv-init`:

   > Error: `Repos: <name>` not registered in `.hv/repos.json`. Run `/hv-init` from the umbrella root to register sub-repos.

4. **Walk-up convenience.** If `/hv-work` was invoked from a cwd that resolves to a registered sub-repo via `bin/hv-resolve-repo`, default that sub-repo as the wave's scope. Items whose `Repos:` differ from the resolved cwd repo trigger the same divergence error in (2).

When the gate passes, carry the resolved sub-repo name forward to Step 5 (branch/worktree path) and Step 10 (merge/PR --repo flag).

## Step 5 — Create Branch or Worktree

Choose a descriptive name (e.g., `hv/quick-switch`, `hv/fix-timer-badge`).

### Isolation guard (fires before any worker dispatch)

Before any worker is dispatched, if the planned wave has **≥2 commit-producing parallel workers** AND `work.isolation == "branch"`, **abort fatally**:

> Error: this wave plans to dispatch <N> parallel workers (<task IDs>) under branch isolation. The 2026-05-02 isolation decision in `.hv/DECISIONS.md` requires `work.isolation: "worktree"` for ≥2 parallel commit-producing workers in a single wave — branch isolation forces all workers to share `.git/index`, which races even on disjoint files.
>
> Resolve by either:
> - Re-plan the wave to a single worker (sequential commits within one task).
> - Run `/hv-config` and flip `work.isolation` to `"worktree"`.

This guard is **fatal**, not warn-and-proceed. It fires regardless of umbrella mode.

A wave is "commit-producing" by default; "read-only" workers (research, lint-only verifications, smoke validators that don't commit) are exempt — count only workers whose brief instructs them to stage and commit.

### Branch creation (single-repo)

```bash
git checkout -b <branch-name>
```

### Worktree creation (single-repo)

```bash
git branch <branch-name>
git worktree add .claude/worktrees/<branch-name> <branch-name>
.hv/bin/hv-status-add <branch> <ID1>,<ID2>[,...] .claude/worktrees/<branch-name>
```

### Branch creation (umbrella mode)

When the wave's resolved sub-repo is `<repo>` (from Step 4.5):

```bash
(cd <repo> && git checkout -b <branch-name>)
.hv/bin/hv-status-add --repo <repo> <branch> <ID1>,<ID2>[,...]
```

The branch lands in `<umbrella>/<repo>/.git/`, not the umbrella's `.git/`.

### Worktree creation (umbrella mode — Layout B)

```bash
(cd <repo> && git branch <branch-name>)
git -C <repo> worktree add <umbrella>/.claude/worktrees/<repo>/<branch-name> <branch-name>
.hv/bin/hv-status-add --repo <repo> <branch> <ID1>,<ID2>[,...] <umbrella>/.claude/worktrees/<repo>/<branch-name>
```

The worktree path lives at `<umbrella>/.claude/worktrees/<repo>/<branch>` (Layout B); `git worktree add` is run from inside `<repo>` so the worktree is registered against that sub-repo's `.git/`. `hv-worktree-clear --repo` (cleanup helper) finds it via the same Layout B path.

Orchestrator stays in the umbrella worktree (retains `.hv/` access). Workers get the absolute Layout B path in their briefs and work there.

## Step 6 — Dispatch Parallel Worker Agents

For each independent task, dispatch a subagent with the **worker** model:

```
You are implementing Task N of [total].
[UMBRELLA: "Sub-repo: <name>. Run all git operations from <absolute-sub-repo-path>; the umbrella's `.git/` is shared coordinator state, NOT your target."]
[WORKTREE: "Working directory: <absolute-worktree-path>. cd there before any file operations."]

**Goal:** [one sentence]

**Files:**
- Create: [paths]
- Modify: [paths with line references]

**What to do:**
[Precise instructions — what to read, what to change, exact code where possible]

**Known gotchas:**
[Relevant bullets from hv-knowledge-query output]

**Hard boundaries:**
[Relevant entries from hv-decisions-query — full rule + forbids/permits, not just the rule. Workers MUST respect these; the orchestrator's verification step (Step 7) checks the diff for violations.]

**Critical constraints:**
[Behavior preservation, patterns to follow, things NOT to touch]

**Commit with message:**
[exact commit message to use]
```

**Umbrella mode notes:** when umbrella mode is on, the `[UMBRELLA: ...]` line replaces the WORKTREE line if the wave uses branch isolation; both lines appear together if the wave uses Layout B worktrees. The sub-repo path is the absolute path resolved via `.hv/repos.json` (single-repo callers ignore both lines). Workers MUST `cd` to the named directory before any `git` command — the orchestrator stays at the umbrella for `.hv/` access, so worker commands run in the umbrella's cwd by default and would target the wrong `.git/`.

Rules for briefs: exact paths + line numbers; show the pattern to follow; name the commit message (agents commit themselves); read-first, minimal-diff, no unrelated changes.

Launch all independent agents in one message (parallel tool calls). Don't announce — just do it.

## Step 7 — Verify Each Completion

Orchestrator verifies internally (don't narrate):

1. Commit exists: `git log --oneline -1`
2. Read modified files — changes match the brief
3. Structural checks: grep for expected patterns, no regressions

**When the wave produced multiple completions, verify them in parallel** — issue all the `git log`, `Read`, and grep calls for independent tasks in a single tool-call batch, not one task at a time.

**PASS** → move on silently. **FAIL** → dispatch a fix agent, re-verify. Surface failures only if they persist.

## Step 8 — Sequential Waves

For dependent tasks: wait for wave 1 to complete and verify, then dispatch wave 2 with updated context. Same verification.

## Step 8.5 — Sweep Tool-Generated Siblings

Workers create source files without triggering the toolchain, so sibling artifacts (Step 1 patterns) end up untracked. Sweep them now or the next `/hv-work` guard will refuse on a dirty tree:

```bash
git status --porcelain
git add -A -- <matching sibling paths>
git commit -m "chore: track tool-generated siblings"
```

Non-sibling dirt → surface it; a worker produced unexpected changes and the orchestrator should investigate before merging.

If a tool regenerates siblings only when the editor loads (e.g., Godot `class_name` → `.gd.uid`), force generation once in headless mode before the sweep (e.g., `godot --headless --editor --quit`). Capture project-specific commands in `KNOWLEDGE.md`.

## Step 9 — Update TODO.md

```bash
.hv/bin/hv-complete <ID> <commit-hash>
```

Run per resolved item. Match by keyword overlap between task description and TODO entry title. If unsure whether an item was addressed, leave it — don't move items you didn't work on.

## Step 10 — Merge or PR

**Direct merge:**

```bash
# Single-repo:
printf 'merge: <summary>\n\n- task 1 description\n- task 2 description\n' | .hv/bin/hv-merge <branch>

# Umbrella mode:
printf 'merge: <summary>\n\n- task 1 description\n- task 2 description\n' | .hv/bin/hv-merge --repo <repo> <branch>
```

The helper removes any worktree for the branch, checks out main, merges `--no-ff` with the piped message, deletes the branch, and prints the merge commit's short hash.

**PR:**

```bash
# Single-repo:
printf '## Summary\n- item 1\n- item 2\n\n## Items resolved\n- [B01] Title\n- [F03] Title\n\n## Test plan\n- [ ] ...\n' \
  | .hv/bin/hv-pr <branch> "<short title>"

# Umbrella mode:
printf '## Summary\n- item 1\n- item 2\n\n## Items resolved\n- [B01] Title\n- [F03] Title\n\n## Test plan\n- [ ] ...\n' \
  | .hv/bin/hv-pr --repo <repo> <branch> "<short title>"
```

The helper removes any worktree, pushes the branch with `-u`, and runs `gh pr create`. Share the PR URL with the user.

## Step 11 — Update Status

**Single-repo:**

```bash
.hv/bin/hv-status-remove <branch>
```

**Umbrella mode** (when the wave's resolved sub-repo from Step 4.5 is `<repo>`):

```bash
.hv/bin/hv-status-remove --repo <repo> <branch>
```

Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella waves MUST pass `--repo` here or the active entry leaks into the next `/hv-resume` / `/hv-next`.

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

- `"off"` — nudge *"Capture learnings from this session? Run `/hv-learn` to save durable knowledge before context fades."*
- `"auto"` or `"loop"` — **dispatch `hv-learn` via `Skill` immediately — no prompt, no confirmation, no "want me to" question.** Pass a brief naming the cycle's resolved IDs and touched files so the verifier (if `learn.verify: true`) has the right context.

## Step 13.5 — Decide (Nudge Only)

Trigger: same gating as Step 13, OR the orchestrator noticed a non-obvious pick during verification (e.g., chose SQLite over Postgres, locked a pattern not dictated by existing code). Skip trivial fixes. Don't repeat in the same session.

**Always nudge — never auto-invoke**, regardless of `autonomy.level`. The active/passive split (decisions vs learnings) requires the human pressing the button.

> *"Did this cycle codify any boundaries (e.g., 'X always goes through Y', 'never use Z here')? Run `/hv-decide` to lock them in."*

## Step 14 — Refactor (Nudge or Auto-Invoke)

```bash
.hv/bin/hv-refactor-age
```

Returns JSON: `{"features": N, "bugs": M}` — counts since the last `refactor:` commit. Trigger when `features >= 5` OR `bugs >= 10`. Don't repeat in the same session.

Branch on `autonomy.level`:

- `"off"` — nudge *"You've shipped [N] features / [M] bug fixes since the last refactor. Might be a good time to run `/hv-refactor` to clean up accumulated friction."*
- `"auto"` or `"loop"` — **dispatch `hv-refactor` via `Skill` immediately — no prompt, no confirmation.** (`refactor.confirmBeforeExecute` still governs the internal checkpoints.)

## Step 15 — Loop Continuation

Only when `autonomy.level == "loop"`. **Dispatch `hv-next` via `Skill` immediately — no prompt, no confirmation.** `/hv-next` reads autonomy and auto-dispatches `/hv-work`, sustaining the loop.

Loop stops naturally when:
- `/hv-next` reports an empty backlog (or the active milestone has no items and the general backlog is also empty)
- A guard fails downstream (dirty tree, `/hv-review` FAIL, ambiguous brief in Step 2)
- The user interrupts

## Key Principles

- **No noise.** Report results, not process. Don't narrate steps that produced nothing.
- **Orchestrator plans and verifies; worker executes.** Never dispatch without a clear brief. Never trust completion without reading the result.
- **Orchestrator owns `.hv/` state.** Only the orchestrator touches `status.json` and `TODO.md`. Workers focus on implementation.
- **Isolation protects main.** Branch or worktree — never work directly on main.
- **One commit per task.** Clean history, easy revert granularity.
