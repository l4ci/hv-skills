---
name: hv-plan
description: Write an implementation plan as a first-class artifact before execution — keyed by milestone and slice or item (M01-S01.md, M01-B07.md). Captures goal, approach, task decomposition with verifiable outcomes, open questions, and named assumptions. /hv-work consults the plan if present. Use when an item or slice is too big to one-shot, or when alignment matters before code lands.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  📋  hv-plan  ·  write implementation plan before execution
  triggers: "plan M01-S01", "plan B07"  ·  pairs: hv-vision, hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-plan — Implementation Plan as Artifact

Write a plan to disk that the user signs off on before `/hv-work` runs. The plan is keyed under a milestone and a slice or backlog item — `.hv/plans/M01-S01.md` for a slice, `.hv/plans/M01-B07.md` for a single backlog item that warrants its own plan.

`/hv-plan` runs in one of two modes:

- **Interactive (default)** — the user redlines via `AskUserQuestion` + free-text iteration. Used in off/auto autonomy.
- **`--auto-loop`** — invoked exclusively from `/hv-work` Step 4 when `autonomy.level == "loop"` and the dispatch site decides a plan is needed. Suppresses `AskUserQuestion` entirely; runs the auto-resolution pipeline (see `## Auto-loop mode` below); logs each fresh pick into `DECISIONS.md` as an `[Auto:Loop]` entry; surfaces unresolved open questions as `_(Unresolved — surfaced for review)_` placeholders in the written plan. Off and auto autonomy modes never invoke this — they always surface open questions through `AskUserQuestion`.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Resolve target", description="Resolve the milestone-and-unit key from the invocation")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (no detail file yet, single iteration sufficient) get `completed` with the no-op reason in the description.

Phases:

1. *Resolve target* — milestone-and-unit key extracted from args / cwd (Step 2)
2. *Load context* — TODO entry, detail file, codebase greps gathered (Step 3)
3. *Propose* — goal, approach, task decomposition drafted for the user (Step 4)
4. *Iterate* — feedback rounds until alignment (Step 5)
5. *Write* — plan persisted to `.hv/plans/<key>.md` (Step 6)

## Step 2 — Resolve Target

The user's input may be:

- **A milestone ID** (`M01`) — slice mode; mint the next slice number
- **A backlog item ID** (`B07`, `F03`, `T11`) — item mode; the plan key is `<milestone>-<itemId>`
- **Free-form** (*"plan the auth foundation"*, *"for the OAuth work"*) — ask which milestone

For an item target, read its `TODO.md` entry and overflow file (`.hv/<bugs|features|tasks>/<id>.md` if it exists) and look for a `Milestone:` field. That's the parent. If the item lacks a milestone tag, ask the user to either:

- Tag the item under an active milestone (then proceed)
- Skip planning and use `/hv-go` for one-shot execution

When the item carries a `Repos:` field, capture that value as the plan's target sub-repo(s) so `/hv-work` can resolve dispatch from the plan alone. The plan key shape (`<milestone>-<itemId>`) does not change — repo is frontmatter, not key. Multi-repo items pass the full comma-list through (`--repo "web, api"`); the frontmatter key stays singular `repo:` and just carries the joined string. Slice and milestone targets do not carry a repo (umbrella-flat per M02 acceptance).

For a slice target, read `.hv/milestones/<MID>.md` for goal/acceptance/risks context.

If the same key already exists at `.hv/plans/<key>.md`, ask whether to view (`hv-plan-show`), edit (skip to Step 4 with current content as the starting point), or replace (`hv-plan-rm` first, then re-create).

## Step 3 — Load Context Silently

Apply the canonical pre-planning context-load protocol (`references/context-load-protocol.md`) — it lists the common reads (TODO entry, plan, milestone, milestone-scoped items via `hv-todo-by-milestone`, K+D queries, recent git history) and cites the K+D query mechanics. For this skill, the reads also include:

- Existing plans for this milestone: `.hv/bin/hv-plan-list <MID>`
- For item targets carrying a `Repos:` field: resolve it to an absolute sub-repo path via `.hv/repos.json` (`load_repos()`). Skipped for slice / milestone targets and when umbrella mode is off.
- For item targets whose ID matches `[BFT]\d{2,}`: `[ -f .hv/designs/<ID>.md ] && cat .hv/designs/<ID>.md` to load any design artifact from `/hv-brainstorm`. Skipped for slice targets. When a design artifact exists, it carries the negotiated Goal/Design/Approaches-considered — Step 4's proposal mirrors the design's chosen approach rather than re-exploring.

DECISIONS matches are committed boundaries the plan must respect. If the plan would violate any, **redesign before writing**, or surface the conflict and ask the user whether to update the decision first.

**Issue these as parallel tool calls in a single response** — they're independent. Form a picture; don't dump it.

## Step 4 — Propose the Plan

**Under `--auto-loop`**, skip "Propose"/"Iterate" semantics entirely: run the auto-resolution pipeline below for every open question, build the final plan markdown directly, then go to Step 6. No AskUserQuestion call fires anywhere in the run. See `## Auto-loop mode` below for the pipeline.

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
- **Tasks are vertical slivers, not horizontal layers.** Each task crosses every layer it needs to be observable — UI + logic + data together for one feature path, not "all UI first, all logic second". The **Observable behavior** requirement and the **No half-implementations** rule already enforce this implicitly; calling it out by name keeps slice plans from drifting into the horizontal anti-pattern that AI agents fall into by default. For a hotel-reservation slice: "Reserve" button is one task end-to-end; "Cancel" is a separate task end-to-end; "email confirmation" is a third. Not "build all the UI in T1, then all the controllers in T2, then all the persistence in T3."
- **Name assumptions you'd otherwise leave implicit.** Forces the user to confirm or push back.
- **List open questions you'd resolve mid-flight.** If they should be answered before `/hv-work` runs, ask now.

## Step 5 — Iterate

**Skipped under `--auto-loop`** — the auto-resolution pipeline already produced the final plan. Proceed directly to Step 6.

The user redlines. Common edits:

- *"T2 and T3 should be merged"* — combine and restate
- *"Files for T1 are wrong, the auth lives in `auth/session.ts`"* — correct the plan
- *"Add T5 for the migration"* — extend
- *"Assumption #2 is wrong, we're multi-tenant from day one"* — replace; this likely changes Approach

Iterate until the user explicitly confirms.

**Loop semantics:**

- **Round budget — up to 5 iterations** of *propose → user redlines → re-propose*. After the 5th revision without an explicit confirmation, stop drafting further changes and surface *"We've been iterating for a while — is this plan close enough to ship, or should we step back and rescope?"*
- **What counts as explicit confirmation** — a short affirmative reply directed at the plan: *yes*, *ship it*, *go*, *looks good*, *approved*, *lgtm*, *confirmed*, *do it*, or equivalent. Silence and topic-shift do **not** count — when the user pivots to a different question or stays quiet, ask *"Confirm this plan? (yes / changes)"* once and wait for a direct answer before Step 6 fires.
- **Exit conditions** — (a) explicit confirmation → proceed to Step 6; (b) 5-round budget hit → halt drafting and surface the check-in above; (c) the user redirects scope so far that the original **Goal** no longer matches → restart from Step 4 with the new spec rather than retrofitting the existing plan.

## Step 6 — Write to Disk

```bash
# Slice mode — auto-mint slice number (umbrella-flat, no --repo):
KEY=$(.hv/bin/hv-plan-add <MID> slice "<title>")

# Item mode — explicit unit ID; pass --repo for umbrella items:
KEY=$(.hv/bin/hv-plan-add <MID> <itemId> "<title>")
# or, if the item carries Repos: <name>
KEY=$(.hv/bin/hv-plan-add --repo <name> <MID> <itemId> "<title>")
# multi-repo items pass the full comma-list verbatim:
KEY=$(.hv/bin/hv-plan-add --repo "web, api" <MID> <itemId> "<title>")
```

Pass `--repo` only for item-mode targets that carry a `Repos:` value. Slice mode never sets `--repo`. Multi-repo items keep all names in one `--repo` argument; `hv-plan-add` validates each name against `.hv/repos.json` before writing the plan.

When `.hv/designs/<ID>.md` exists for the plan's item, pass `--design .hv/designs/<ID>.md` to `hv-plan-add`. The plan's frontmatter records `design: .hv/designs/<ID>.md` as a traceability pointer.

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

Include `Repo: <names>` only when the plan was tagged with a sub-repo (item targets with `Repos:` under umbrella mode). Render multi-repo plans with the joined list — e.g. `Repo: web, api`. Slice and milestone plans omit the line entirely.

If `/hv-work` is the natural next step and the user is ready, offer it as a one-line prompt rather than just printing the hint.

## Auto-loop mode

Activated by the `--auto-loop` flag. Invoked exclusively by `/hv-work` Step 4 in loop mode when no plan exists for a Major + Milestone-tagged item — see `/hv-work`'s Step 4 dispatch directive for the trigger conditions and the inline `Skill`-tool dispatch language. This section describes the run shape once the flag is set; the dispatch decision lives at `/hv-work`'s call site (per the hv-init "Imperative rules in autonomy-aware steps must live inline at every dispatch point" convention).

**Orchestrator-model contract.** `--auto-loop` makes design picks autonomously (no `AskUserQuestion`), so it depends on orchestrator-grade design judgment. The contract: this skill is invoked via the `Skill` tool from `/hv-work` Step 4, which loads it inline in `/hv-work`'s session. Since `/hv-work` runs under `models.orchestrator` (per `.hv/config.json`, default `opus`), `--auto-loop` inherits that model. If a future change moves the dispatch to the `Agent` tool, the call site MUST explicitly pass `model: orchestrator` (resolved from `.hv/config.json`) — running `--auto-loop` under the worker model would push design picks onto an execution-tuned model and degrade plan quality. The interactive (default) mode has no such constraint; it can run under any model since the user redlines via `AskUserQuestion`.

### Pipeline

For each open question the orchestrator would normally surface to the user, run three steps in order:

1. **Local-first.** Grep `DECISIONS.md` / `MILESTONES.md` / `KNOWLEDGE.md` via `hv-decisions-query` / `hv-knowledge-query` on the question's topic keywords. If a matching commitment exists, the answer is "honor the existing commitment" — do **not** log a new `[Auto:Loop]` entry; the existing commitment IS the record.
2. **Bounded web (opt-in).** If unmatched AND the question references an external library, API, or protocol (anything outside the F14 hv-skills surface scan: `/hv-(\w+)`, `bin/hv-*`, `.hv/*` artifacts), AND `loop.webResearch == true` in `.hv/config.json` (default `false`), call `WebSearch` with a budget of **2 queries per question, 6 queries per plan**. Block on results; no async fetch.
3. **Placeholder fallback.** If still unresolved, retain the question literally in the written plan with `_(Unresolved — surfaced for review)_` after the question text. The auto-write proceeds — never stop the loop.

### Logging

Each fresh pick from steps 1 (when no existing commitment matched and you made a new pick) and 2 produces an `[Auto:Loop]` entry via:

```bash
.hv/bin/hv-auto-decision-log "<topic>" "<rule-title>" "<why-text>" "<plan-key>" "$(date +%Y-%m-%d)"
```

The entry follows the standard `DECISIONS.md` template, but **only the rule and `*Why.*` are auto-filled**; `**Forbids.**` and `**Permits.**` stay as `_(Unresolved — user must articulate)_` placeholders the user fills at session end (per the 2026-05-08 source-prefill rule that destination-specific fields stay as placeholders the skill blocks on). A footer comment encodes provenance: `<!-- [Auto:Loop] <plan-key> <date> — review and articulate Forbids/Permits -->`. The helper is idempotent on `(topic, rule-title)` — re-running the same plan key writes each entry exactly once.

After all questions are resolved, write the plan to `.hv/plans/<key>.md` using the same `hv-plan-add` + `Edit` flow as Step 6. The plan's "Open questions" section lists every step-3 placeholder verbatim; "Resolved open questions" lists every step-1/2 outcome with a brief rationale. The `auto: true` frontmatter key marks the plan as auto-written.

### Surfacing

`/hv-plan --auto-loop` itself does not surface auto-decisions to the user — surfacing fires only on terminal paths (`/hv-next` empty-backlog branch, `/hv-work` guard-fail branch, `/hv-pause`) via `bin/hv-auto-decisions-since`. The user sees the running summary at session end, articulates `Forbids/Permits` in `DECISIONS.md`, and removes the `<!-- [Auto:Loop] -->` footer (signaling the entry is now a normal decision).

## Key Principles

- **Plans are committed alignment, not rough notes.** If the user wouldn't sign off, it isn't ready to write.
- **Verify is non-negotiable.** Every task has a check that proves it done.
- **Open questions beat hidden assumptions.** Surface what you don't know.
- **Tasks fit one execution.** If they don't, split.
- **The plan key relates to a milestone.** Items without a milestone get tagged before planning.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`references/context-load-protocol.md`](../references/context-load-protocol.md) — K+D context loading sequence shared by every cycle-starting skill.
