---
name: hv-brainstorm
description: Per-item design exploration before /hv-plan — Socratic discovery, 2-3 approaches with tradeoffs, sectioned design with per-section approval, writes .hv/designs/<ID>.md, hands off to /hv-plan. Use when a Major feature or P0 bug needs design negotiation before implementation planning.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  💡  hv-brainstorm  ·  per-item design exploration before /hv-plan
  triggers: "brainstorm F03", "design B07"  ·  pairs: hv-plan, hv-vision
════════════════════════════════════════════════════════════════════════
```

# hv-brainstorm — Per-item Design Exploration

`/hv-brainstorm` fills the gap between `/hv-capture` (records what to build) and `/hv-plan` (decomposes how to build it) by negotiating *whether this is the right thing and what its shape should be*. Scope is a single backlog item (`[B##]` or `[F##]` or `[T##]`); project-level exploration stays with `/hv-vision`. The artifact lands at `.hv/designs/<ID>.md` and feeds `/hv-plan` as soft input — never required.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Autonomy gate.** Read `autonomy.level` and exit silently under `loop`:

```bash
LEVEL=$(jq -r '.autonomy.level // "off"' .hv/config.json)
```

If `LEVEL == "loop"`, print *"Note: /hv-brainstorm is skipped under loop autonomy (throughput mode). Re-run with `/hv-config` set to off or auto if you want to brainstorm."* and exit 0. Per the 2026-05-09 KNOWLEDGE inline-autonomy-directives convention, the check lives at every dispatch point including this one.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below. Mark each `in_progress` when starting and `completed` when its observable outcome lands.

Phases:

1. *Resolve target* — item ID parsed, existence verified, re-run mode picked (Step 2)
2. *Load context* — TODO entry, detail file, K+D+C queries gathered in parallel (Step 3)
3. *Discover* — Socratic clarifying rounds, capped at 5 (Step 4)
4. *Propose approaches* — 2-3 candidates with tradeoffs, user picks one (Step 5)
5. *Section drafts* — Goal → Design → Approaches → Open questions → Assumptions with per-section approval (Step 6)
6. *Write* — artifact persisted to `.hv/designs/<ID>.md` (Step 7)
7. *Self-review* — placeholder/contradiction/scope/ambiguity scan (Step 8)
8. *User review* — final approval gate (Step 9)

## Step 2 — Resolve Target

Parse the item ID from the invocation. It must match `[BFT]\d{2,}`. Reject milestone IDs (`M01`) and slice IDs (`S01`) with: *"Error: /hv-brainstorm operates on a single backlog item. For project-level exploration use /hv-vision; for slice planning use /hv-plan."*

Verify the item exists in `.hv/TODO.md`:

```bash
.hv/bin/hv-todo-field <ID> title
```

Exit 1 from the helper means the ID is not in the backlog. Refuse with: *"Error: [<ID>] not found in TODO.md. Run /hv-capture first to add it."*

**Re-run check.** If `.hv/designs/<ID>.md` already exists, ask via `AskUserQuestion` (single-select, 3 options):

- **View** — print the existing design and exit
- **Edit** — enter brainstorm with existing design loaded as starting context
- **Replace** — discard the existing design and re-run discovery from scratch

Plain-text fallback per `references/ask-user-question-fallback.md`; default rule: opt-in-off / cancel (replace is destructive). Routing:

- **View** → invoke `.hv/bin/hv-design-show <ID>` and exit 0.
- **Edit** → load the existing design content; the first Step 4 clarifying question is *"What would you change about the existing design?"*
- **Replace** → run `.hv/bin/hv-design-rm <ID>` then proceed to Step 3.

## Step 3 — Load Context Silently

Pull the picture in parallel — these reads are independent and latency-bound:

- `.hv/bin/hv-todo-field <ID> title`
- `.hv/bin/hv-todo-field <ID> milestone`
- `.hv/bin/hv-todo-field <ID> related`
- Detail file: `.hv/bugs/<ID>.md`, `.hv/features/<ID>.md`, or `.hv/tasks/<ID>.md` (read whichever exists)
- `.hv/bin/hv-knowledge-query <topic>` for topics inferred from the TODO entry and detail file
- `.hv/bin/hv-decisions-query <topic>` for the same topics — committed boundaries the design must respect
- `.hv/bin/hv-context-query <term>` for any domain terms the item references

**Issue all of these as parallel tool calls in a single response.** Don't narrate the loading. Form a picture; carry findings forward into Steps 4 and 5.

DECISIONS matches are hard boundaries. If the brainstorm would violate any, surface the conflict before proposing approaches and ask whether to update the decision first.

## Step 4 — Frame & Discover

Socratic clarifying questions, one at a time. Use `AskUserQuestion` with one question per round, multi-choice preferred, ≤ 4 options per the picker cap. **Cap: 5 clarifying rounds**; after the fifth, switch to plain-text prose and stop counting picker rounds.

Section gates (Step 6) and the final review (Step 9) are check-ins, not exploratory questions, and do **not** count against the 5-question budget.

Good clarifying-question shapes:

- **Scope** — *"Does this need to handle umbrella sub-repos in V1, or is single-repo fine?"*
- **Interaction** — *"Should this run automatically after /hv-capture, or only on explicit invocation?"*
- **Gotcha boundaries** — *"What existing skill must this NOT touch?"*
- **Failure modes** — *"What happens when <key precondition> is false?"*

Plain-text fallback: ask once in prose; default rule per the site is honor yes/no for binary cases, default to Recommended for routing cases. See `references/ask-user-question-fallback.md`.

**Spike handoff.** When a clarifying question or candidate approach needs code-touching evidence to answer (feasibility, library support, performance characteristics), surface:

> *"This warrants a spike. Run `/hv-spike <name>` first to gather evidence, then re-invoke `/hv-brainstorm <ID>` to finish the design."*

Don't guess at the answer to keep the brainstorm moving.

## Step 5 — Propose 2-3 Approaches

Present 2 or 3 candidate approaches inline as plain markdown — not yet committed to disk. Each approach gets:

- **Shape** — one paragraph naming the moving parts and where they live
- **Pros** — 2-4 bullets on what this approach wins
- **Cons** — 2-4 bullets on what it costs
- **Why this might or might not be the right answer** — one sentence on the deciding factor

Then ask the user to pick via `AskUserQuestion` (single-select, ≤ 4 options: one per approach plus *"Ask more questions first"* as an escape back to Step 4). Plain-text fallback: list the approach labels in prose and parse the reply against them; default rule: honor yes/no — silence means the user wants more discussion, not a pick.

The picked approach is the design. Carry it into Step 6.

## Step 6 — Sectioned Design with Per-Section Approval

Draft the design one section at a time in this order: Goal → Design → Approaches considered → Open questions → Assumptions. Present each section inline, then ask via `AskUserQuestion` (single-select, 3 options):

- **Approve this section**
- **Suggest changes** — user redlines; restate; ask again
- **Approve all remaining sections** — short-circuit Step 6 and jump to Step 7

Plain-text fallback: `yes` / `changes` / `approve all`. Default rule: honor yes/no — silence does not approve, restate and re-ask.

Section content rules:

- **Goal** — one sentence on what shipping this design means
- **Design** — 3-8 sentences on the chosen shape, moving parts, where they live
- **Approaches considered** — the 2-3 candidates from Step 5 with Pros/Cons/Why summarized
- **Open questions** — questions that need answering before or during `/hv-plan`; mark spike candidates explicitly
- **Assumptions** — implicit constraints made explicit (*"assumes single-repo"*, *"assumes K+D queries return ≤ 20 hits"*)

## Step 7 — Write Artifact

Mint the design stub:

```bash
.hv/bin/hv-design-add <ID> "<title>"
```

The helper creates `.hv/designs/<ID>.md` with frontmatter (`id`, `title`, `status: draft`, `created`) and the five placeholder section headers. Use the `Edit` tool to overwrite each placeholder section body with the approved content from Step 6. Keep the frontmatter intact.

## Step 8 — Self-Review

Scan the written artifact in one pass for:

- **Placeholders** — `_(placeholder)_`, `TBD`, `???`, empty sections
- **Internal contradictions** — Step 5's chosen approach matches the Design section; Open questions don't conflict with Assumptions
- **Scope creep** — every claim ties back to the item ID; nothing leaks into a sibling item or future milestone
- **Ambiguous adjectives** — *"a few"*, *"many"*, *"high quality"*, *"reasonable"*. Replace with numbers or assertive verbs (per the 2026-05-11 KNOWLEDGE entry on soft adjectives).

Surface findings in one block. If any landed, offer to revise — this is a check-in, not counted against the Step 4 budget.

## Step 9 — User Review Gate

Print the final artifact (or invoke `.hv/bin/hv-design-show <ID>`) and ask via `AskUserQuestion` (single-select, 3 options):

- **Approve and hand off to `/hv-plan`**
- **Revise** — return to Step 6 with the user's redlines
- **Stop here** — design is enough for now; no plan handoff

Plain-text fallback: `approve` / `revise` / `stop`. Default rule: honor yes/no.

## Step 10 — Report

One compact summary:

```
Design written: F58 — <title>
  Artifact: .hv/designs/F58.md
  Approaches considered: 3
  Open questions: 2
  Status: draft
```

If the user approved-and-hand-off:

- Milestone-tagged item → *"Run `/hv-plan <milestone>-<ID>` next."*
- Untagged item → *"Run `/hv-plan` next (it will prompt for milestone)."*

If the user picked *Stop here* → exit without a `/hv-plan` nudge.

## Anti-pattern guard

> *"This item is too simple to need a design"* is rationalization. Every brainstormed item gets a design pass, but the design can be short — a few sentences in Goal and Design with empty Approaches-considered is a valid output for a truly simple item. The artifact captures the negotiated outcome, not a word count.

## Key Principles

- **No noise.** Don't narrate context loads; don't recap discovery rounds; don't pad the artifact with adjectives.
- **Design is negotiable; the artifact captures the negotiated outcome.** Step 9 is where alignment lands on disk.
- **Soft input to `/hv-plan` — never required.** Plans without a design stay valid; the `design:` pointer is additive.
- **Scope is single-item.** Project-level exploration is `/hv-vision`; slice-level is `/hv-plan` slice mode.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`references/ask-user-question-fallback.md`](../references/ask-user-question-fallback.md) — Plain-text fallback shape for AskUserQuestion-less hosts.
