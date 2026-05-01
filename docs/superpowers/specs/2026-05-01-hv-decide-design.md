# /hv-decide — design spec

**Status:** approved (brainstorming sign-off 2026-05-01) · **Owner:** Volker Otto · **Implements:** TBD — feature ID gets captured into `.hv/TODO.md` before implementation begins.

## Summary

Add a per-project hard-boundary record (`.hv/DECISIONS.md`) and a manual capture skill (`/hv-decide`) that writes to it. Decisions are **active commitments** — distinct from `KNOWLEDGE.md`'s **passive learnings** — and are consulted by every work-producing skill before acting.

## Motivation

`/hv-learn` already captures durable session knowledge into `.hv/KNOWLEDGE.md`. Knowledge is *passive*: "remember this if relevant." But a class of project state doesn't fit that mould — hard boundaries the project has *committed* to, where violation is a regression, not a missed opportunity. Examples: "tests must hit a real DB, not mocks," "background jobs run in-process, never via external queue," "this surface uses SQLite, not Postgres."

These are *active* — they were decided, they have a why, they have an apply-time shape (forbids/permits). Storing them in `KNOWLEDGE.md` flattens that distinction; relying on memory loses them across sessions; relying on PR review loses them between reviewers. A first-class artifact, written manually with confirmation, fixes both gaps.

## Architecture

| Artifact | Purpose | Mirrors |
|---|---|---|
| `.hv/DECISIONS.md` | Per-project hard-boundary record. Gitignored (consistent with rest of `.hv/`). | `.hv/KNOWLEDGE.md` |
| `/hv-decide` skill | Only way to write decisions. Always manual, always confirmation-gated, never auto-invoked. | `/hv-learn` (structurally) |
| `.hv/bin/hv-decisions-index` | Maintains a managed `<!-- hv-decisions-start --> … <!-- hv-decisions-end -->` block in `CLAUDE.md`, listing topics. | `hv-knowledge-index` |
| `.hv/bin/hv-decisions-query <topic>…` | Pulls just the named topic sections from `.hv/DECISIONS.md` for read-site consults. | `hv-knowledge-query` |

The mirroring is deliberate — consumers learn the pattern once (from `KNOWLEDGE.md`) and apply it twice. Skills consult both files via the same shape.

## File schema

`.hv/DECISIONS.md`:

```markdown
# Decisions

Hard boundaries for this project. Each entry is a commitment, not a preference — re-read before proposing changes that touch its area.

## <Topic>

### <Decision title>

<One-sentence rule — what the decision actually says.>

*Why.* <One paragraph rationale — past incident, deadline, stakeholder ask, or strong preference.>

**Forbids.** <What this rules out at apply time. Concrete patterns/files/approaches.>

**Permits.** <What this still allows. Anchors the boundary so it's not over-applied.>

<!-- 2026-05-01 -->
```

**Rules:**

- **Topics** match `KNOWLEDGE.md` topics where they overlap (`Build & Tooling`, `Architecture`, `Testing`, etc.) so a single topic name maps to both files.
- **Newest first** within each topic.
- **Date stamp** as HTML comment, same convention as `KNOWLEDGE.md`.
- **All four parts required** — rule, why, forbids, permits. The skill enforces this before writing.
- **One sentence rule, one paragraph why.** If a decision needs more, link to a plan or knowledge entry.

The header preamble (`# Decisions` + framing sentence) is seeded once by `hv-bootstrap`. After that, only `### <Decision title>` blocks are appended by `/hv-decide`.

## `/hv-decide` skill flow

Frontmatter and banner conventions match the rest of the `hv-*` skills (`user-invocable: true`, banner printed on entry, skip if subagent-dispatched).

**Step 1 — Preflight.** `.hv/bin/hv-preflight`; on failure invoke `hv-init` via the `Skill` tool.

**Step 2 — Identify the candidate decision.** From the conversation context (or from the user's explicit framing), surface what's being committed to. If invoked with no clear candidate, ask the user to state the boundary in one sentence.

**Step 3 — Compose the four parts.** Draft all four (rule, why, forbids, permits) from context and present the draft. Use a single `AskUserQuestion` only when one of the four parts is genuinely ambiguous — otherwise show the draft and let Step 5 handle approval.

If the user can't articulate **forbids** *or* **permits**, that's a signal it's a learning, not a decision — surface that to the user, suggest `/hv-learn` instead, and stop. Do not auto-invoke `/hv-learn` from `/hv-decide` — the user re-runs it deliberately.

**Step 4 — Classify by topic.** Read `.hv/DECISIONS.md` and reuse existing `## Topic` headings when they fit; reuse `KNOWLEDGE.md` topics where overlap exists; create a new topic only if nothing fits.

**Step 5 — Confirmation gate.** Present the assembled entry via `AskUserQuestion` with three options: *Write it · Edit first · Cancel*. **Never write without explicit confirmation.** This is the active/passive distinction made operational.

**Step 6 — Merge into `DECISIONS.md`.** `Edit`-based surgical insert at the top of the chosen topic, with today's date stamp.

**Step 7 — Update `CLAUDE.md` decisions index.** `.hv/bin/hv-decisions-index`.

**Step 8 — Confirm.** One compact block:

```
Captured 1 decision into .hv/DECISIONS.md:
  Architecture — "Background jobs run in-process, never via external queue"

Updated CLAUDE.md decisions index — /hv-work, /hv-debug, /hv-plan will consult it.
```

**No verifier.** Unlike `/hv-learn`, there's no Opus verification step. Manual confirmation IS the verification.

## Read integration

Each read-site adds a step that consults `DECISIONS.md` for relevant topics, mirroring the existing knowledge consult.

| Skill | Where it slots in | What it does |
|---|---|---|
| `/hv-work` | Step 4 sub-step, right after `hv-knowledge-query` | `.hv/bin/hv-decisions-query "Architecture" "Testing"` → carry into worker briefs as `**Hard boundaries:**` block. Workers MUST respect; orchestrator verifies. |
| `/hv-debug` | Pre-hypothesis step | A boundary may rule out a fix path before cycles are wasted. |
| `/hv-go` | Inherits via its `/hv-work` invocation | No new code path. |
| `/hv-plan` | Plan-write step | Existing decisions become hard constraints in the plan's "Constraints" section. |
| `/hv-refactor` | Design phase | Refactors must respect boundaries — easiest place to introduce violations. |
| `/hv-review` | Review checklist | Reviewer adds *"violates project decisions?"* check; FAIL on violation. |
| `/hv-vision` | Milestone planning | Decisions constrain what milestones can promise. |

**Worker-brief addition** in `/hv-work` Step 6:

```
**Hard boundaries:**
[Relevant entries from hv-decisions-query — full rule + forbids/permits, not just rule. Workers see the whole shape so they understand what's load-bearing.]
```

`/hv-spike` and `/hv-ship` do **not** consult — spikes are throwaway by definition; ship is bundling-only and `/hv-review` already covers it.

## Suggest integration

Suggest sites nudge the user toward `/hv-decide` but never auto-invoke it.

- **End of `/hv-work` Step 13**, after the learn nudge: *"Did this cycle codify any boundaries (e.g., 'X always goes through Y', 'never use Z here')? Run `/hv-decide` to lock them in."*
- **End of `/hv-debug`** — same nudge if the fix path codified a constraint.
- **No suggest at `/hv-plan` start** — read-only consult there, not a capture point.

The nudge fires **regardless of `autonomy.level`** because decisions are always manual. Even in `loop` mode, the loop never invokes `/hv-decide` on the user's behalf.

**Trigger guard for suggests:** fire only when the cycle resolved 2+ items OR touched ≥5 files. Optionally also fire ad-hoc when the orchestrator's verification step noticed a non-obvious pick (e.g., chose SQLite over Postgres, locked a coding pattern that wasn't dictated by existing code). Skip for trivial fixes.

## Init bootstrap

**`/hv-init` Step 2** (`hv-bootstrap`) gets one new line: create `.hv/DECISIONS.md` with the header preamble if absent. Idempotent — never overwritten on re-run, same as `KNOWLEDGE.md`.

**`/hv-init` Step 4** — alongside the existing `hv-knowledge-index` and `hv-vision-index` calls, add `hv-decisions-index`. All three keep their managed blocks in `CLAUDE.md` in sync.

**Helpers** are copied into consumer projects' `.hv/bin/` by `/hv-init` Step 2 alongside the rest of `hv-*`.

**Managed block** seeded into `CLAUDE.md`:

```markdown
## Project Decisions

Hard boundaries live in `.hv/DECISIONS.md`. Consult them before acting on work that touches these topics:

<!-- hv-decisions-start -->
- Architecture
- Testing
<!-- hv-decisions-end -->
```

Skills read the topic list from this block, then call `hv-decisions-query` to pull the relevant sections.

## Cleanup in this repo

Bundled with the feature work, separate from the new artifacts:

- Delete `/home/vo/Code/hv-skills/DECISIONS.md`.
- Remove `## Project Decisions` section from `/home/vo/Code/hv-skills/CLAUDE.md`.
- Remove the surfacing line from `/home/vo/Code/hv-skills/README.md`.

Once the feature lands, this repo dogfoods it: `/hv-decide` writes to `.hv/DECISIONS.md` (gitignored), and `/hv-init` re-run regenerates the managed block in `CLAUDE.md`.

## Documentation

- New `docs/usage/decisions.md` — consumer-facing: what decisions are, when to use `/hv-decide` vs `/hv-learn`, how the consult flow works.
- Update `docs/reference/cli-helpers.md` to list `hv-decisions-index` and `hv-decisions-query`.

## Non-goals

- **No auto-capture.** `/hv-decide` is never invoked by another skill, regardless of `autonomy.level`. The active/passive distinction depends on this.
- **No Opus verifier.** Manual confirmation is the verification. Adding a cold pass would slow capture without adding signal.
- **No promotion-from-knowledge flow.** If a captured learning later turns out to be a decision, the user re-runs `/hv-decide` and removes the knowledge entry by hand. Building a promote pathway is YAGNI.
- **No team-sharing mechanism.** `.hv/DECISIONS.md` is gitignored. Teams that want shared decisions can adjust their own `.gitignore`; the default stays consistent with the rest of `.hv/`.

## Open questions

None — all forks locked during brainstorming.
