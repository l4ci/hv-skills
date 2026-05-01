---
name: hv-decide
description: Capture a hard-boundary decision into .hv/DECISIONS.md — manually confirmed, never auto-invoked. Decisions differ from learnings in KNOWLEDGE.md by being active commitments with explicit forbids/permits. Use on "decide on X", "we're committing to X", "lock in the boundary that Y", or when a session has produced a constraint future work must respect.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  ⚖️   hv-decide  ·  capture hard-boundary decisions to DECISIONS.md
  triggers: "decide on X", "lock in Y"  ·  pairs: hv-learn (passive)
════════════════════════════════════════════════════════════════════════
```

# hv-decide — Capture Hard-Boundary Decisions

Distill an active commitment from the current session into `.hv/DECISIONS.md`, organized by topic, so future work consults it as a hard constraint. Decisions are *active* (committed boundaries with forbids/permits) — distinct from `/hv-learn` which captures *passive* knowledge (gotchas, conventions, constraints to remember).

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

## Step 2 — Identify the Candidate Decision

A decision is worth capturing if it is:

- **Active** — the project has *committed* to it. Violating it is a regression, not a missed opportunity.
- **Bounded** — it has a concrete shape: forbids X, permits Y.
- **Justified** — there's a why behind it (past incident, deadline, stakeholder ask, strong preference).

If the user invoked `/hv-decide` with a clear candidate from the conversation, surface it. If not, ask:

> "What boundary do you want to lock in? State it as one sentence — what the decision says."

If after one round the user can't articulate **forbids** *or* **permits**, surface that — it's a signal this is a learning, not a decision. Suggest `/hv-learn` instead and stop. **Do not auto-invoke `/hv-learn`** — the user re-runs it deliberately.

## Step 3 — Compose the Four Parts

Every decision entry has four parts:

1. **Rule** — one-sentence statement of what the decision says
2. **Why** — one paragraph rationale (past incident, constraint, deadline, stakeholder ask)
3. **Forbids** — concrete things this rules out at apply time (patterns, files, approaches)
4. **Permits** — concrete things this still allows (anchors the boundary so it's not over-applied)

**Draft all four from conversation context.** Use a single `AskUserQuestion` call only when one of the four parts is genuinely ambiguous from context — otherwise show the assembled draft and let Step 5 handle approval.

## Step 4 — Classify by Topic

Open `.hv/DECISIONS.md` first and reuse existing `## Topic` headings when they fit. Also reuse `KNOWLEDGE.md` topics where overlap exists (`Architecture`, `Testing`, `Build & Tooling`, etc.) so a single topic name maps to both files. Create a new topic only if nothing fits.

Don't create a topic per decision — they should be coarser than learnings.

## Step 5 — Confirmation Gate

Present the assembled entry to the user via `AskUserQuestion`:

- **Header:** `"Decide"`
- **Question:** *"Lock in this decision?"*
- **Options** (single-select):
  1. *"Write it (Recommended)"* — *"Append to `.hv/DECISIONS.md` under `<topic>` and update CLAUDE.md decisions index."*
  2. *"Edit first"* — *"Show the draft inline so you can rewrite any of the four parts before writing."*
  3. *"Cancel"* — *"Skip — nothing is written."*

Show the full draft entry (rule, why, forbids, permits) above the question. **Never write without explicit "Write it" confirmation.** This is the active/passive distinction made operational.

If the user picks **Edit first**, present the draft as inline text, accept revisions, and re-prompt with the same three options.

If the user picks **Cancel**, stop with one line: *"Decision not captured."*

Plain-text fallback: write only if the user types `yes` or `write`. Anything else is a cancel.

## Step 6 — Merge into DECISIONS.md

`.hv/DECISIONS.md` is organized as:

```markdown
# Decisions

Hard boundaries for this project. Each entry is a commitment, not a preference — re-read before proposing changes that touch its area.

## <Topic>

### <Decision title>

<One-sentence rule.>

*Why.* <One paragraph rationale.>

**Forbids.** <Concrete patterns/files/approaches.>

**Permits.** <What this still allows.>

<!-- 2026-05-01 -->
```

**Merge rules:**

- Preserve existing topics — never rewrite sections you didn't change.
- Insert new `### Decision title` blocks at the **top** of their topic (newest first).
- Stamp new entries with today's absolute date as an HTML comment: `<!-- YYYY-MM-DD -->`.
- New topics go alphabetically, except `Architecture` and `Build & Tooling` may be pinned near the top (matching `KNOWLEDGE.md` convention).

Use `Edit` for surgical updates, not `Write`.

## Step 7 — Update CLAUDE.md Decisions Index

```bash
.hv/bin/hv-decisions-index
```

Reads `.hv/DECISIONS.md`, extracts `## Topic` headings in order, and updates the managed `<!-- hv-decisions-start -->` block in `CLAUDE.md`. Creates or appends as needed; never touches other content. The read-site skills (`/hv-work`, `/hv-debug`, `/hv-plan`, `/hv-refactor`, `/hv-review`, `/hv-vision`) read this block to know when to consult `DECISIONS.md`.

## Step 8 — Confirm

Tell the user, in one compact block, what was captured:

```
Captured 1 decision into .hv/DECISIONS.md:
  Architecture — "Background jobs run in-process, never via external queue"

Updated CLAUDE.md decisions index — /hv-work, /hv-debug, /hv-plan, /hv-refactor, /hv-review, /hv-vision will consult it.
```

If the entry created a new topic, prepend a line: *"New topic: `<topic>`."*

## Key Principles

- **Never auto-invoked.** Regardless of `autonomy.level` — the active/passive distinction depends on this.
- **Forbids and permits are required.** If you can't articulate both, it's a learning — redirect to `/hv-learn`.
- **One sentence rule, one paragraph why.** If a decision needs more, link to a plan or knowledge entry.
- **No verifier.** Manual confirmation is the verification.
