# Brainstorming a design

`/hv-brainstorm` fills the gap between [`/hv-capture`](capturing-work.md) (records what to build) and [`/hv-plan`](vision-and-plans.md) (decomposes how to build it). It negotiates *whether this is the right thing and what shape it should take* for a single backlog item. The artifact lands at `.hv/designs/<ID>.md` and feeds `/hv-plan` as soft input — read when present, never required.

## When to run it

- Right after capturing a `[Major]` feature or a `[P0]` bug, when its design is unclear.
- When two reasonable approaches need negotiation before you commit to one.
- When the item's TODO entry is one sentence but the implementation isn't obvious.
- When `/hv-capture` or `/hv-next` nudges you toward it (the nudge fires on `[Major]` and `[P0]` items that don't yet have a design artifact).

Skip it when the item is `[Minor]`, `[Cosmetic]`, or a plain task with an obvious shape. Skip it when you already know exactly what you want to build — go straight to [`/hv-plan`](vision-and-plans.md) or [`/hv-work`](running-work.md).

## One example end-to-end

You capture an idea:

```
/hv-capture "an /hv-archive command that ages out resolved items older than 90 days"
# → [F12] [Major] /hv-archive command for old resolved items.
```

`/hv-capture` flags it as `[Major]` and prints a nudge:

> `[F12]` is a `[Major]` feature with no design artifact. Run `/hv-brainstorm F12` before `/hv-plan F12` to negotiate shape and tradeoffs.

You take the nudge:

```
/hv-brainstorm F12
```

The skill resolves `F12`, reads its TODO entry, queries relevant `KNOWLEDGE.md` and `DECISIONS.md` topics, and asks 2-3 clarifying questions:

> What signals "resolved"? `## Completed` only, or also `ARCHIVE.md`? Should the 90-day threshold be a flag, a config key, or both?

Once context is anchored, the skill proposes three approaches:

1. **In-place TODO mutation.** `hv-archive` rewrites `BACKLOG.md` directly. Simple, but conflicts with parallel `/hv-work` sessions.
2. **Append-only journal.** Move resolved bullets into a dated section in `ARCHIVE.md`, leave `BACKLOG.md` `## Completed` empty. Survives merge conflicts but loses some recency info.
3. **Two-phase: mark + sweep.** First pass tags bullets with `archived:` frontmatter, second pass moves them on a separate command. More steps, but reversible.

You pick approach 2. The skill then drafts the design section by section — Goal, Design, Approaches considered, Open questions, Assumptions — each approved before moving on. When the artifact is complete, it lands at `.hv/designs/F12.md`.

## The artifact

`.hv/designs/F12.md` is a small markdown file with frontmatter and five sections:

```markdown
---
id: F12
title: /hv-archive command for old resolved items
status: draft
created: 2026-05-12
---

# F12 — /hv-archive command for old resolved items

## Goal

Ship a `/hv-archive` command that ages out `## Completed` items older than 90 days into `ARCHIVE.md` without disturbing active backlog state.

## Design

Append-only journal pattern. ...

## Approaches considered

1. **In-place mutation** — ...
2. **Append-only journal (chosen)** — ...
3. **Two-phase mark + sweep** — ...

## Open questions

- Should the 90-day window be configurable per project?

## Assumptions

- `ARCHIVE.md` exists and is append-safe.
```

## How it feeds `/hv-plan`

When you next run `/hv-plan M01-F12`, the planner reads `.hv/designs/F12.md` if present and reflects its chosen approach in the plan's `## Approach` section. The plan's frontmatter carries a `design:` pointer for traceability:

```yaml
key: M01-F12
milestone: M01
unit: F12
unitKind: item
design: .hv/designs/F12.md
title: /hv-archive command for old resolved items
status: planned
```

The design is soft input: `/hv-plan` doesn't require it, and a plan can override a design's choice if facts changed since the brainstorm.

## Re-running on an existing design

If `.hv/designs/<ID>.md` already exists, `/hv-brainstorm` asks how to proceed:

- **View** — print the artifact and exit.
- **Edit** — open targeted sections and revise them in place.
- **Replace** — start from scratch; the previous artifact is overwritten only after explicit confirm.

## What it does not do

- Project-level design stays with [`/hv-vision`](vision-and-plans.md) — milestones, multi-feature arcs, vision rewrites.
- Code-touching feasibility experiments stay with [`/hv-spike`](spikes.md) — a throwaway branch that proves a thing works before the design hardens.
- Implementation plan with task decomposition stays with [`/hv-plan`](vision-and-plans.md).
- [`/hv-go`](running-work.md) always skips the brainstorm step; it's a single-pass capture-and-implement path for items with an obvious shape.

## Autonomy interaction

Under `autonomy.level: "off"` (default), `/hv-capture` and `/hv-next` print a one-line nudge for `[Major]` features and `[P0]` bugs without a design artifact. Under `"auto"`, the nudge auto-invokes `/hv-brainstorm` before routing to `/hv-plan`. Under `"loop"`, `/hv-work` Step 4 dispatches `/hv-brainstorm --auto-loop <ID>` for Major + Milestone-tagged items without a design — the auto-loop mode resolves design picks via local-first (DECISIONS / KNOWLEDGE / CONTEXT / MILESTONES) → bounded web (when `loop.webResearch=true`) → placeholder, logs `[Auto:Loop]` decisions for fresh picks, and writes `.hv/designs/<ID>.md` with `auto: true` frontmatter. The user articulates Forbids/Permits on the logged decisions later via terminal-path surfacing. See [Autonomy levels](autonomy.md) for the full chaining rules.
