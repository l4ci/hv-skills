---
name: hv-work
description: Orchestrator-driven parallel implementation — plans tasks, dispatches worker subagents, verifies, commits atomically per task. Supports branch or worktree isolation and direct merge or PR. Use when items already exist in BACKLOG.md and need implementation ("implement [B07]", "build these"); for an item not yet captured use /hv-go.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

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
Guard → Clarify (if needed) → Status → Plan → Isolate → Dispatch → Verify → Commit → TODO → Merge/PR → Status
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

**Greenfield variant.** On a fresh `git init`'d repo (no commits yet), `hv-guard-clean` emits a tailored message pointing at the `chore: import initial files` baseline commit. Run it and re-invoke — the guard then sees a clean tree.

Don't narrate the sweep unless it happened; silent pass-through is the common case.

**On any Step 1 guard failure that stops `/hv-work` (exit 2 not-a-repo, or exit 1 user-change dirty tree)** — this is a terminal path; the user is about to step away from the loop to resolve. Per the F19 terminal-path-only convention (mirrored in `/hv-next` empty-backlog and `/hv-pause`), surface any `[Auto:Loop]` decisions logged during this loop session before printing the guard message:

```bash
.hv/bin/hv-auto-decisions-since   # empty stdout when nothing matches; print verbatim above the guard message when nonempty
.hv/bin/hv-loop-stamp clear       # clear the session marker — the loop is broken and the next /hv-next entry will stamp a fresh start
```

If `hv-auto-decisions-since` produces no output, skip silently.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Preflight and guard", description="Run hv-preflight and hv-guard-clean; sweep tool siblings if dirty")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (e.g. no `[Auto:Loop]` decisions to surface) get `completed` with the no-op reason in the description.

Phases:

1. *Preflight & guard* — clean tree + repo confirmed (Step 1)
2. *Register status* — branch named, `hv-status-add` recorded (Steps 3, 5)
3. *Plan tasks* — wave layout + briefs ready (Step 4)
4. *Branch / worktree* — isolation set up per `work.isolation` (Step 5)
5. *Dispatch & verify per wave* — workers run, orchestrator verifies each completion (Steps 6–8)
6. *Commit + TODO + sweep* — per-task commits, TODO entries marked complete, item plans tombstoned, tool siblings swept (Steps 7.5, 8.5, 9, 9.5)
7. *Merge/PR & report* — integration + status removal + summary + post-cycle nudges (Steps 10–15)

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

Plain-text fallback: ask once; on ambiguity, default to Recommended and state it explicitly in the dispatch brief. See `references/ask-user-question-fallback.md`.

**Loop mode exception:** if `autonomy.level == "loop"` and the brief is genuinely ambiguous (you'd otherwise ask Step 2), the routing depends on the item's shape:

- **Major + Milestone-tagged item** — defer to Step 4's auto-dispatch chain. The chain auto-resolves design via `/hv-brainstorm --auto-loop` (writes a design artifact with `[Auto:Loop]` decisions for fresh picks), then runs the uncertainty pre-flight + plan dispatch (`/hv-plan --auto-loop`). Step 2 does not stop in this case — the chain owns design resolution under loop.
- **Non-Major or untagged item** — **stop the loop** and surface the question for the user to resolve. Do not silently pick a default — invisible decisions across N looped items defeat the point of the loop. The user resolves and re-invokes `/hv-next` (or this `/hv-work`) to continue the queue.

## Step 3 — Register in Status

After picking the branch name:

**Single-repo:**

```bash
.hv/bin/hv-status-add <branch> <ID1>,<ID2>[,...] [worktree-path]
```

**Umbrella mode** (when `umbrella.enabled` is true and items carry `Repos:`): parse the `Repos:` field from each item's TODO entry. The value is a comma-separated CSV — single-repo items have one name (`Repos: web`), multi-repo items have two or more (`Repos: web, api`). All items in a wave must share the *same* set of repos.

Single-repo wave: pass the one name via `--repo`:

```bash
.hv/bin/hv-status-add --repo <repo-name> <branch> <ID1>,<ID2>[,...] [worktree-path]
```

Multi-repo wave: register one entry per `(branch, repo)` pair via `hv-status-add-multi`:

```bash
.hv/bin/hv-status-add-multi --branch <branch> --items <ID1>,<ID2>[,...] --repos "<repos-csv>"
```

Parse the `Repos:` field for each item using `hv-todo-field`:

```bash
.hv/bin/hv-todo-field <ID> repos
```

This uses the canonical `parse_todo_fields` from hvlib, so multi-repo CSVs (`web, api`) are captured intact and the parser correctly handles `Detail:`/`Related:`/`Milestone:` boundaries that the old grep chain could over-eat. Hand the resulting CSV to `hv-resolve-repos` for validation; if it exits non-zero, surface the missing names and stop.

Idempotent on `(branch, repo)` — call again with the worktree path(s) once Step 5 creates them.

## Step 4 — Plan Tasks

**Plan-as-artifact check (first).** If the work has a milestone-and-unit key — an item tagged to a milestone (`Milestone: M01` on `B07` → key `M01-B07`) or a slice (`M01-S01`) — check for an existing plan:

```bash
.hv/bin/hv-plan-show <milestone>-<unit> 2>/dev/null
```

If a plan exists, **use it as the orchestrator's plan** — its task decomposition, files, verify steps, and assumptions become the dispatch briefs in Step 6 instead of decomposing ad-hoc. Restate any user redlines from the conversation, but don't silently re-derive what the user already signed off on. If the conversation contradicts the plan, ask the user whether to update the plan first (`/hv-plan` again) or proceed and ignore it.

**Loop-mode auto-dispatch chain (B28 / F32 / F34 / F35).** In loop mode with a Major + Milestone-tagged item but no plan, `/hv-work` runs the full research → plan chain in three steps, all via the `Skill` tool so the dispatched skills inherit the orchestrator model:

1. **Design pre-flight (B28).** If `.hv/designs/<itemId>.md` is absent, dispatch `/hv-brainstorm --auto-loop <itemId>`. The dispatched skill auto-resolves design questions (Local-first → Bounded web → Placeholder), logs `[Auto:Loop]` decisions for fresh picks, and writes `.hv/designs/<itemId>.md` with `auto: true` frontmatter. When a design already exists, this step is a no-op.
2. **Uncertainty pre-flight (F34).** Run `.hv/bin/hv-uncertain <itemId>`. Exit 0 (uncertain, reasons on stdout) → dispatch `/hv-assume <itemId>`. Exit 1 (certain) → skip the peek.
3. **Plan dispatch (F32 / F35).** Dispatch `/hv-plan --auto-loop <milestone>-<itemId>`. `/hv-plan` Step 3 reads the design artifact as soft input (already wired), and the auto-resolution pipeline writes the plan with all picks honored.

After the chain returns, re-run the plan-as-artifact check at the top of this step — the plan now exists; use it as the orchestrator's plan. Off and auto modes skip this chain entirely and fall through to manual decomposition. See [`references/loop-mode-plan-dispatch.md`](../references/loop-mode-plan-dispatch.md) for the full choreography.

If no plan exists and the loop-mode dispatch above did not fire (off/auto, or Minor/untagged item), proceed with the steps below.

From the conversation context:

1. **Consult knowledge + decisions.** Apply the canonical K+D query pattern (`references/knowledge-consult.md`) with topics inferred from the planned work areas. Also run `.hv/bin/hv-context-query "<terms appearing in the TODO entry or task plan>"` for any domain term used in the TODO entry, and surface inline conflict-call-outs (synonym or drift) when the user's wording deviates from the canonical term during the cycle. Carry matches into Step 6 briefs as `**Known gotchas:**` (relevant knowledge bullets only) and `**Hard boundaries:**` (full decision entries — rule + *Why* + **Forbids** + **Permits**). Workers must treat boundaries as constraints, not hints. If a planned task would violate a decision, **stop and surface to the user** before dispatching.

   - **Soft-cap check.** Run `.hv/bin/hv-map-cap-check` — emits a one-line nudge to stderr if the subsystem count is at or above the configured soft cap. Never blocks.

2. Identify discrete tasks — files to create/modify, what changes, acceptance criteria.
3. **Detect rename + link-sweep collisions.** Before grouping into waves, scan for rename / link-sweep task pairs that race on shared written files; resolve by merge, clean split-ownership, or serialize-across-waves. Use `.hv/bin/hv-plan-rename-check <old-name> [<scope>...]` as ground truth (re-run at Step 7 to catch enumeration gaps). See [`references/loop-mode-plan-dispatch.md`](../references/loop-mode-plan-dispatch.md) *Detect rename + link-sweep collisions* for the resolution table.
4. Group into dependency waves:
   - **Wave 1:** independent files → parallel
   - **Wave 2+:** depend on wave 1 outputs → sequential or next parallel batch

## Step 4.5 — Umbrella Pre-Flight (when umbrella mode is on)

Umbrella mode is in effect when `.hv/repos.json` registers ≥1 sub-repo (the data is truth; `umbrella.enabled` is informational). Detect with `.hv/bin/hv-umbrella-on` — see `references/umbrella-mode.md` for the registry shape, resolution helpers, and `Repos:` field semantics.

If `hv-umbrella-on` returns `no`, skip this step entirely (single-repo path).

If `yes`:

1. **Every item must carry `Repos:`.** Parse via `.hv/bin/hv-todo-field <ID> repos`. If any item lacks a tag, stop with: *"Error: `[<ID>]` lacks a `Repos:` tag. Re-run `/hv-capture` to add it. Cannot route to a sub-repo."*

2. **All items in a wave must resolve to the same repo set** (as a set, order-independent). Single-repo and multi-repo items can't mix in one wave; two multi-repo items must list the same names. On divergence, stop with: *"Error: items in this wave target different sub-repo sets: `<set-a>` vs `<set-b>`. Split into separate `/hv-work` runs."*

3. **Validate every name in the resolved set** via `.hv/bin/hv-resolve-repos "<csv>"` (exits 1 with stderr on any missing name). On failure, stop with: *"Error: `Repos: <name>` not registered in `.hv/repos.json`. Run `/hv-init` from the umbrella root to register sub-repos."*

4. **Walk-up convenience (single-repo only).** If `/hv-work` was invoked from a cwd that `.hv/bin/hv-resolve-repo` resolves to a registered sub-repo, default that sub-repo as the wave's scope when items lack an explicit `Repos:` tag. Multi-repo items always come from the captured `Repos:` field — no cwd default.

When the gate passes, carry the resolved sub-repo set forward to Step 5 (branch / worktree creation) and Step 10 (merge / PR).

## Step 5 — Create Branch or Worktree

Choose a descriptive name (e.g., `hv/quick-switch`, `hv/fix-timer-badge`).

### Isolation guard (fires before any worker dispatch)

Before any worker is dispatched, abort fatally if the planned wave has **≥2 commit-producing parallel workers** AND `work.isolation == "branch"` — branch isolation forces concurrent commit-producing workers to share `.git/index`, which races even on disjoint files. Read-only workers (research, lint-only verifications, smoke validators that don't commit) are exempt; under the default write-only pattern the guard rarely fires because the orchestrator owns commits in Step 7.5. See [`references/isolation-guard.md`](../references/isolation-guard.md) for the abort message, the M02-S01 incident that motivated the rule, and the full **Forbids / Permits** block.

### Branch / worktree creation

Pick the pattern from `references/isolation-patterns.md` based on `work.isolation` (`"branch"` or `"worktree"` from `.hv/config.json`) and whether umbrella mode is on (Step 4.5 resolved the sub-repo set; carry it forward). The reference's decision table covers all five combinations: single-repo branch, single-repo worktree, umbrella sub-repo branch, umbrella sub-repo worktree (Layout B), umbrella multi-repo branch (via `.hv/bin/hv-multi-branch-create`, which runs an atomic precheck across every named repo before creating any branches).

The most common case — single-repo, branch isolation — is just:

```bash
git checkout -b <branch>
.hv/bin/hv-status-add <branch> <ID>[,<ID>...]
```

For umbrella-mode branch creation (single sub-repo, multi-repo, Layout B worktree), see `references/umbrella-mode.md` *Branch creation* — that reference owns the canonical umbrella ceremony.

Orchestrator stays at the repo root (or umbrella root in umbrella mode); workers `cd` into their assigned directory before any file operation, and use absolute paths in their briefs.

## Step 6 — Dispatch Worker Agents

**Dispatch vs orchestrator-direct.** When the wave is N near-identical mechanical inserts on disjoint files (e.g. an 18-site SKILL.md sweep), prefer orchestrator-direct parallel `Edit` calls over dispatching N write-only subagents — dispatch overhead exceeds the benefit when the orchestrator already has per-site content. Litmus: *"is this task one `Edit` against a uniquely-anchored `old_string`?"* — yes → inline; no → dispatch.

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

**Canonical terms:**
[Relevant terms from hv-context-query — definition + aliases. Workers MUST use these canonical names in code/comments/commit messages where they apply; aliases are listed so divergent user phrasing in the TODO entry maps back to the right term.]

**Critical constraints:**
[Behavior preservation, patterns to follow, things NOT to touch]

**Do NOT run `git add` or `git commit`.** Write changes to files only. The orchestrator owns the commit phase (Step 7.5) — your job is to leave a clean working-tree diff matching the brief.

**Suggested commit message:** [exact commit message — orchestrator uses this in Step 7.5]

**On completion:** report the list of files you modified, plus any tool-generated siblings the toolchain produced, and confirm you did not stage or commit.
```

**Umbrella mode notes:** when umbrella mode is on, the `[UMBRELLA: ...]` line replaces the WORKTREE line if the wave uses branch isolation; both lines appear together if the wave uses Layout B worktrees. The sub-repo path is the absolute path resolved via `.hv/repos.json` (single-repo callers ignore both lines). Workers MUST `cd` to the named directory before any `git` command — the orchestrator stays at the umbrella for `.hv/` access, so worker commands run in the umbrella's cwd by default and would target the wrong `.git/`.

**Multi-repo dispatch:** for a wave with `<N>` sub-repos in its resolved set, dispatch one worker per sub-repo, each with the sub-repo's name and absolute path in its `[UMBRELLA: ...]` line. Workers run in parallel — each repo has its own `.git/index`, so cross-repo parallelism doesn't trip the parallel-waves-require-worktree-isolation guard (which fires only when ≥2 workers share one `.git/`). Each worker's brief lists only the files in its own sub-repo; the orchestrator verifies each repo's commit independently in Step 7.

Rules for briefs: exact paths + line numbers; show the pattern to follow; name the suggested commit message; read-first, minimal-diff, no unrelated changes; workers do NOT stage or commit.

**Cross-referencing parallel artifacts — pre-bake citations.** When two parallel workers author artifacts that cite each other, pre-specify the citation language in each brief; neither worker should need to read the other's output. Works for structural cross-references (cite by path + named role); serialize when citation must quote or restate.

**Doc-writer + helper-writers in the same wave drifts.** Workers authoring docs that show helper output or signatures while sibling workers are writing those helpers will paraphrase the brief and drift from the real code. Pin exact signatures verbatim into the doc-brief, or serialize the doc writer after the helper commit so it reads the actual implementation.

**Rename-task addendum.** Briefs for `git mv old new` (or equivalent rename) tasks MUST carry the Step 4 grep step — instruct the worker to run `git grep -l "<old-name>" -- <scope>` before reporting and extend coverage to every match. Step 7 re-runs the same grep; both layers catch enumerate gaps.

Launch all independent agents in one message (parallel tool calls) — write-only workers don't race on `.git/index`, so this is safe under any isolation mode. Don't announce — just do it.

**Edit-tool race in parallel same-file workers.** When parallel workers edit the same file at different ranges, an `Edit` call may report *"File has been modified since read"* after a sibling worker's edit invalidates the cached state. Mitigation: re-`Read` the file, re-run the same `Edit` with byte-identical `old_string` — do NOT regenerate `old_string` from scratch (risks sibling-edited content).

### Alternative: legacy worker-commits (opt-in)

When a wave touches files that overlap and write-only would racing on disk (rare — usually a planning failure that should be re-decomposed), or when an out-of-band tool requires a commit between worker steps, fall back to the legacy pattern: workers stage and commit themselves. Under this pattern:

- **Single worker per wave under `work.isolation: "branch"`.** Multiple workers committing to the same `.git/index` is forbidden by the [decisions / Skill Authoring / Parallel waves require worktree isolation] rule. Either re-plan as N sequential single-worker waves on a shared branch (the M02 multi-feature pattern), or flip `work.isolation` to `"worktree"` so each worker has its own index.
- **Brief includes `**Commit with message:** [exact text]`** — workers stage their own files and commit, one commit per task. Skip Step 7.5 (orchestrator-side commit) on this path.

This path is documented for completeness; the default write-only pattern above is preferred for new work.

## Step 7 — Verify Each Completion

Orchestrator verifies internally (don't narrate):

Trust the diff, not the worker's narrative — when a worker re-enters files in a later wave, it can mis-attribute its own writes to an earlier wave even when the on-disk output is correct. Verification reads `git diff` and the resulting files; the worker's completion report is supplementary.

1. Inspect pending changes: `git status --porcelain` then `git diff` for the files the worker reported. (Legacy path: `git log --oneline -1` if the worker committed.)
2. Read modified files — changes match the brief.
3. Structural checks: grep for expected patterns, no regressions.
4. **Rename validation (Step 4 rename + link-sweep rule).** Re-run `git grep -l "<old-name>" -- <scope>`; files outside the worker's modified-file set → dispatch a fix-up to extend coverage before staging.
5. **Claim-weight check on gap-fills.** When a worker fills a gap left by extraction (sparse carrier prose, missing rationale), expect plausible-sounding editorial that wasn't in the source. Verify the *claim weight* of any sentence the worker authored, not just structural shape — plausible ≠ sourced.

**When the wave produced multiple completions, verify them in parallel** — issue all the `git log`, `Read`, and grep calls for independent tasks in a single tool-call batch, not one task at a time.

**PASS** → move on silently. **FAIL** → dispatch a fix agent, re-verify. Surface failures only if they persist.

## Step 7.5 — Commit per Task (orchestrator)

Under the default write-only pattern, the orchestrator commits each verified task. One commit per task, sequential, in the order the tasks were dispatched.

```bash
git add <task-N-files>
git commit -m "<suggested-message-from-task-N-brief>"
```

Rules:

- **Stage exactly the files named in that task's brief.** No `git add -A`, no `git add .` — sweeping in another worker's changes breaks atomicity.
- **One commit per task.** Even when two tasks share a wave, they get separate commits.
- **Same-file parallel carve-out.** When two parallel write-only workers edit DIFFERENT non-overlapping ranges of the SAME file, strict per-task commits would need fragile `git add -p`. Pragmatic carve-out: combine into ONE commit covering both task IDs in the message; revert granularity is preserved by the message, not the commit boundary.
- **Suggested commit message is the brief's `**Suggested commit message:**` line verbatim.** If verification surfaced a meaningful adjustment (e.g., a fix-up after a FAIL→re-dispatch loop), edit the message to reflect what landed.
- **Worktree isolation.** Run from the worktree path — the orchestrator's cwd is the umbrella, but the commit must happen against the worktree's index. Use `git -C <worktree-path>` or change directory before staging.
- **Umbrella / multi-repo.** Run each task's commit inside its target sub-repo (`git -C <umbrella>/<repo>` or `cd <repo>`). The orchestrator stays at the umbrella; each commit lands in the right `.git/`.

**Skip this step entirely** when the wave used the legacy worker-commits path (Step 6 alternative) — workers already committed.

## Step 8 — Sequential Waves

For dependent tasks: wait for wave 1 to complete and verify, then dispatch wave 2 with updated context. Same verification. Wave 2 dispatches see a clean working tree because Step 7.5 already committed wave 1's tasks.

## Step 8.5 — Sweep Tool-Generated Siblings

> Run AFTER Step 7.5 has committed each task — siblings get a `chore:` commit of their own, separate from the task commits.

Workers create source files without triggering the toolchain, so sibling artifacts (Step 1 patterns) end up untracked. Sweep them now or the next `/hv-work` guard will refuse on a dirty tree:

```bash
git status --porcelain
git add -A -- <matching sibling paths>
git commit -m "chore: track tool-generated siblings"
```

Non-sibling dirt → surface it; a worker produced unexpected changes and the orchestrator should investigate before merging.

If a tool regenerates siblings only when the editor loads (e.g., Godot `class_name` → `.gd.uid`), force generation once in headless mode before the sweep (e.g., `godot --headless --editor --quit`). Capture project-specific commands in `KNOWLEDGE.md`.

## Step 9 — Update BACKLOG.md

```bash
.hv/bin/hv-complete <ID> <commit-hash>
```

Run per resolved item. Match by keyword overlap between task description and TODO entry title. If unsure whether an item was addressed, leave it — don't move items you didn't work on.

## Step 9.5 — Tombstone Consumed Item Plans

For each item ID that `hv-complete` just resolved, remove its corresponding item plan if one was written:

```bash
# For each <ID> the cycle resolved (B07/F03/T11/…):
MILESTONE=$(.hv/bin/hv-todo-field <ID> milestone)
if [ -n "$MILESTONE" ] && [ -f ".hv/plans/${MILESTONE}-<ID>.md" ]; then
  .hv/bin/hv-plan-rm "${MILESTONE}-<ID>"
fi
```

Item plans (`.hv/plans/M01-B07.md`) describe how to ship one specific item. Once the cycle ships that item, the plan's task decomposition and assumptions are stale — truth now lives in code + commits. Leaving the file means a future cycle on the same key (e.g., re-opened work) re-reads pre-execution intent that no longer matches the implementation.

Skip silently when:

- The item carries no `Milestone:` tag — no plan key exists for it.
- No plan file is at the resolved key — the `[ -f … ]` guard handles this (untagged items, items that one-shot through `/hv-go` or `/hv-work` without a written plan).

**Slice plans (`M01-S01.md`) stay.** A slice covers multiple items; completing one item does not consume the slice plan. Slice cleanup is currently manual via `.hv/bin/hv-plan-rm <key>` once the user is done with the slice.

`.hv/plans/` is gitignored, so the removal is a local-only file operation — no commit, no merge.

## Step 10 — Merge or PR

Use `work.mergeStrategy` from `.hv/config.json` to pick `hv-merge` (direct) or `hv-pr`. See `references/merge-strategy-gate.md` for the canonical invocation (both single-repo and umbrella variants), helper contracts, and the Manual-gate rule for opening a PR.

When `work.mergeStrategy == "direct"` (or unset — the default), use `hv-merge`. When `work.mergeStrategy == "pr"`, use `hv-pr`. The orchestrator never asks at this point in the cycle — the user set the policy via `/hv-config`; respect it silently.

## Step 11 — Update Status

**Single-repo:**

```bash
.hv/bin/hv-status-remove <branch>
```

**Umbrella mode** (when the wave's resolved sub-repo from Step 4.5 is `<repo>`):

```bash
.hv/bin/hv-status-remove --repo <repo> <branch>
```

Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella waves MUST pass `--repo` here or the active entry leaks into the next `/hv-next`.

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

Apply the post-cycle trigger condition defined in `references/post-cycle-trigger-gate.md` (2+ items resolved / ≥5 files touched / hard bug). Skip for single-item fixes and pure mechanical changes; don't repeat in the same session.

When triggered, branch on `autonomy.level`:

- `"off"` — nudge *"Capture learnings from this session? Run `/hv-learn` to save durable knowledge before context fades."*
- `"auto"` or `"loop"` — **dispatch `hv-learn` via `Skill` immediately — no prompt, no confirmation, no "want me to" question.** Pass a brief naming the cycle's resolved IDs and touched files so the verifier (if `learn.verify: true`) has the right context.

## Step 13.5 — Decide (Nudge Only)

Trigger: same gating as Step 13, OR the orchestrator noticed a non-obvious pick during verification (e.g., chose SQLite over Postgres, locked a pattern not dictated by existing code). Skip trivial fixes. Don't repeat in the same session.

**Always nudge — never auto-invoke**, regardless of `autonomy.level`. The active/passive split (decisions vs learnings) requires the human pressing the button.

> *"Did this cycle codify any boundaries (e.g., 'X always goes through Y', 'never use Z here')? Run `/hv-decide` to lock them in."*

## Step 13.6 — Docs After-Work (Nudge or Auto-Invoke)

Read `docs.afterWork` from `.hv/config.json` (default `false`). If it's `false`, skip this step entirely. Users opt in via `/hv-config` or by running `/hv-docs` manually once.

When the flag is on, apply the same post-cycle trigger condition as Step 13 — see `references/post-cycle-trigger-gate.md`.

When triggered, branch on `autonomy.level`:

- `"off"` — nudge *"User-facing changes shipped. Run `/hv-docs` to review and update public docs (after-work mode)."*
- `"auto"` or `"loop"` — **dispatch `hv-docs` via `Skill` immediately — no prompt, no confirmation, no "want me to" question.** Pass a brief naming the cycle's resolved IDs and touched files so the after-work flow has the right context.

If `<docs.path>/` doesn't exist or is empty, `/hv-docs`'s after-work flow self-skips (printing a one-line "not yet initialized" notice) — no extra check needed here.

## Step 13.7 — Map After-Work

- **Update project map.** Invoke `/hv-map after-work` for any subsystem whose `Key files / dirs` or `Entry points` overlap the files touched in this cycle. The map updates are staged as part of the cycle's final commit, not a separate commit.

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
- **Orchestrator owns `.hv/` state.** Only the orchestrator touches `status.json` and `BACKLOG.md`. Workers focus on implementation.
- **Isolation protects main.** Branch or worktree — never work directly on main.
- **One commit per task, owned by the orchestrator.** Workers write files; the orchestrator commits per task. Clean history, easy revert granularity, no `.git/index` races.

## References

| Reference | Purpose |
|-----------|---------|
| [`ask-user-question-fallback.md`](../references/ask-user-question-fallback.md) | Plain-text fallback shape for AskUserQuestion-less hosts. |
| [`banner-preamble.md`](../references/banner-preamble.md) | Banner-print rule shared by every skill. |
| [`isolation-patterns.md`](../references/isolation-patterns.md) | Branch / worktree creation patterns per work.isolation + umbrella mode. |
| [`knowledge-consult.md`](../references/knowledge-consult.md) | Canonical K+D query pattern (`hv-knowledge-query` + `hv-decisions-query`) used by every cycle-starting skill. |
| [`merge-strategy-gate.md`](../references/merge-strategy-gate.md) | Merge-strategy decision UX (Direct vs PR) plus helper invocations. |
| [`post-cycle-trigger-gate.md`](../references/post-cycle-trigger-gate.md) | Trigger condition for post-cycle nudges (2+ items / ≥5 files / hard bug). |
| [`umbrella-mode.md`](../references/umbrella-mode.md) | Umbrella-mode helpers, registry shape, and `Repos:` field semantics. |
