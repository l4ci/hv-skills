---
name: hv-plan
description: Write an implementation plan as a first-class artifact before execution — keyed by milestone and slice or item (M01-S01.md, M01-B07.md). Captures goal, approach, task decomposition with verifiable outcomes, open questions, and named assumptions. /hv-work consults the plan if present. Use when an item or slice is too big to one-shot, or when alignment matters before code lands.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  📋  hv-plan  ·  write implementation plan before execution
  triggers: "plan M01-S01", "plan B07"  ·  pairs: hv-vision, hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-plan — Implementation Plan as Artifact

Write a plan to disk that the user signs off on before `/hv-work` runs. The plan is keyed under a milestone and a slice or backlog item — `.hv/plans/M01-S01.md` for a slice, `.hv/plans/M01-B07.md` for a single backlog item that warrants its own plan.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

## Step 2 — Resolve Target

The user's input may be:

- **A milestone ID** (`M01`) — slice mode; mint the next slice number
- **A backlog item ID** (`B07`, `F03`, `T11`) — item mode; the plan key is `<milestone>-<itemId>`
- **Free-form** (*"plan the auth foundation"*, *"for the OAuth work"*) — ask which milestone

For an item target, read its `TODO.md` entry and overflow file (`.hv/<bugs|features|tasks>/<id>.md` if it exists) and look for a `Milestone:` field. That's the parent. If the item lacks a milestone tag, ask the user to either:

- Tag the item under an active milestone (then proceed)
- Skip planning and use `/hv-go` for one-shot execution

When the item carries a `Repos:` field, capture that value as the plan's target sub-repo so `/hv-work` can resolve dispatch from the plan alone. The plan key shape (`<milestone>-<itemId>`) does not change — repo is frontmatter, not key. Slice and milestone targets do not carry a repo (umbrella-flat per M02 acceptance).

For a slice target, read `.hv/milestones/<MID>.md` for goal/acceptance/risks context.

If the same key already exists at `.hv/plans/<key>.md`, ask whether to view (`hv-plan-show`), edit (skip to Step 4 with current content as the starting point), or replace (`hv-plan-rm` first, then re-create).

## Step 3 — Load Context Silently

- `.hv/milestones/<MID>.md` — full milestone plan
- Items scoped to this milestone: `.hv/bin/hv-todo-by-milestone <MID>`
- `.hv/<bugs|features|tasks>/<itemId>.md` — overflow detail for the item if any
- Existing plans for this milestone: `.hv/bin/hv-plan-list <MID>`
- For item targets carrying a `Repos:` field: resolve it to an absolute sub-repo path via `.hv/repos.json` (`load_repos()`). Skipped for slice / milestone targets and when umbrella mode is off.
- Relevant `KNOWLEDGE.md` topics: `.hv/bin/hv-knowledge-query <topics…>`
- Relevant `DECISIONS.md` topics: `.hv/bin/hv-decisions-query <topics…>` — committed boundaries the plan must respect. If the plan would violate any, **redesign before writing**, or surface the conflict and ask the user whether to update the decision first.
- Recent git history: `git log --oneline -20`

**Issue these as parallel tool calls in a single response** — they're independent. Form a picture; don't dump it.

## Step 4 — Propose the Plan

Output the plan as plain markdown — not yet committed to disk. Required sections:

- **Goal** — one sentence, what shipping this means
- **Approach** — 3–6 sentences describing the design choice and why this over the alternatives
- **Tasks** — decomposition. Each task gets:
  - **Observable behavior** — what's true after this task ships (visible to a user, a test, or another developer)
  - **Files** — paths the orchestrator will touch or create
  - **Verify** — specific command or manual check that proves the task done
- **Open questions** — explicit unknowns that need decisions before or during execution
- **Assumptions** — implicit constraints made explicit (*"assumes single-tenant"*, *"assumes Postgres ≥14"*)

Rules for the plan:

- **Tasks fit one execution window.** A task too big to ship in one focused pass is two tasks.
- **Every task has a verify step.** No verify = the task isn't well-defined.
- **No half-implementations.** Each task results in real, runnable code — no stubs or placeholders.
- **Name assumptions you'd otherwise leave implicit.** Forces the user to confirm or push back.
- **List open questions you'd resolve mid-flight.** If they should be answered before `/hv-work` runs, ask now.

## Step 5 — Iterate

The user redlines. Common edits:

- *"T2 and T3 should be merged"* — combine and restate
- *"Files for T1 are wrong, the auth lives in `auth/session.ts`"* — correct the plan
- *"Add T5 for the migration"* — extend
- *"Assumption #2 is wrong, we're multi-tenant from day one"* — replace; this likely changes Approach

Iterate until the user explicitly confirms.

## Step 6 — Write to Disk

```bash
# Slice mode — auto-mint slice number (umbrella-flat, no --repo):
KEY=$(.hv/bin/hv-plan-add <MID> slice "<title>")

# Item mode — explicit unit ID; pass --repo for umbrella items:
KEY=$(.hv/bin/hv-plan-add <MID> <itemId> "<title>")
# or, if the item carries Repos: <name>
KEY=$(.hv/bin/hv-plan-add --repo <name> <MID> <itemId> "<title>")
```

Pass `--repo` only for item-mode targets that carry a `Repos:` value. Slice mode never sets `--repo`.

The helper creates `.hv/plans/<key>.md` with frontmatter and stub sections. Use the `Edit` tool to fill in Goal, Approach, Tasks, Open questions, and Assumptions — replacing the placeholder sections with confirmed content. Keep the frontmatter intact.

## Step 7 — Report

Compact summary:

```
Plan written: M01-B07 — Auth foundation
  Repo: web                              # omit when no repo tag
  Tasks: 4
  Open questions: 1
  Status: planned

Next: /hv-work M01-B07 to execute, or /hv-assume M01-B07 to peek before running.
```

Include `Repo: <name>` only when the plan was tagged with a sub-repo (item targets with `Repos:` under umbrella mode). Slice and milestone plans omit the line entirely.

If `/hv-work` is the natural next step and the user is ready, offer it as a one-line prompt rather than just printing the hint.

## Key Principles

- **Plans are committed alignment, not rough notes.** If the user wouldn't sign off, it isn't ready to write.
- **Verify is non-negotiable.** Every task has a check that proves it done.
- **Open questions beat hidden assumptions.** Surface what you don't know.
- **Tasks fit one execution.** If they don't, split.
- **The plan key relates to a milestone.** Items without a milestone get tagged before planning.
