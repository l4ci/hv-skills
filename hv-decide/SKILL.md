---
name: hv-decide
description: Capture a hard-boundary decision into .hv/DECISIONS.md — manually confirmed, never auto-invoked. Decisions differ from learnings in KNOWLEDGE.md by being active commitments with explicit forbids/permits. Use on "decide on X", "we're committing to X", "lock in the boundary that Y", or when a session has produced a constraint future work must respect. Accepts `--from-learning <topic>` to promote a hardened KNOWLEDGE.md learning into a decision, and `--from-spike <name>` to promote a `.hv/spikes/<name>.md` finding.
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

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Identify candidate", description="Surface the boundary the user wants to lock in (with the three-gate check)")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (three-gate refuses to promote) get `completed` with the no-op reason in the description.

Phases:

1. *Mode* — default vs `--from-learning` vs `--from-spike` resolved (Step 1.5)
2. *Identify candidate* — boundary articulated; three-gate check passes (Step 2)
3. *Compose four parts* — rule, *Why*, **Forbids**, **Permits** drafted (Step 3)
4. *Confirmation gate* — manual user approval (never auto-invoked, Step 5)
5. *Merge & index update* — append to `DECISIONS.md`, regenerate CLAUDE.md index (Steps 6–7)

## Step 1.5 — Mode (default vs source-prefill)

Inspect the invocation arguments and pick a mode for the rest of the run:

- **No flag** — default mode. Step 2 elicits the candidate decision conversationally, as today.
- **`--from-learning <topic>`** — Source-Prefill Mode (Learning). Carry `<topic>` forward; Step 2 branches into the source-prefill path and seeds the draft from `.hv/KNOWLEDGE.md`.
- **`--from-spike <name>`** — Source-Prefill Mode (Spike). Carry `<name>` forward; Step 2 branches into the source-prefill path and seeds the draft from `.hv/spikes/<name>.md`.

Both flags simultaneously is invalid — error with *"`/hv-decide` accepts at most one of `--from-learning <topic>` or `--from-spike <name>` per invocation."* and stop.

## Step 2 — Identify the Candidate Decision

A decision is worth capturing if it is:

- **Active** — the project has *committed* to it. Violating it is a regression, not a missed opportunity.
- **Bounded** — it has a concrete shape: forbids X, permits Y.
- **Justified** — there's a why behind it (past incident, deadline, stakeholder ask, strong preference).

**Three-gate trigger (pre-write check).**

Active/Bounded/Justified is the conceptual definition; these three gates are the operational filter that catches preference choices that pass it. **All three must pass** for a candidate to proceed past Step 2 — across all modes (default, `--from-learning`, `--from-spike`):

(a) **Hard to reverse.** Undoing the rule would require coordinated edits across many files, retraining habits, or migrating data. If undoing is `git revert` plus a small refactor, it's a preference, not a decision.

(b) **Surprising without context.** A future contributor reading the code would not infer the rule from the existing patterns. If the rule is self-evident from the codebase — "we use TypeScript" in a TS-only repo, "tests live in `tests/`" in a project where every test already does — it's a convention the code already documents.

(c) **Real trade-off.** Genuine alternatives existed and the project deliberately didn't pick them. If only one option was ever on the table, the "rule" is documenting a default, not a decision.

If **any** gate fails, do **not** write to `DECISIONS.md`. Surface to the user:

> "This reads like a [preference / convention / default] rather than a hard boundary — gate (X) failed. Run `/hv-learn` to capture it as durable knowledge instead, or leave it inline at the call site."

Substitute the failing gate's letter for `(X)`. Suggest the redirect (`/hv-learn` if there's still a useful learning to capture, "leave inline" if it's just code-level) and stop. **Do not auto-invoke `/hv-learn`** — same manual-gate policy as the no-forbids/no-permits redirect below.

Codified from grill-with-docs's ADR triggers — prevents `/hv-decide` bloat from preference choices that aren't actually hard boundaries.

**Default mode.**

If the user invoked `/hv-decide` with a clear candidate from the conversation, surface it. If not, ask:

> "What boundary do you want to lock in? State it as one sentence — what the decision says."

If after one round the user can't articulate **forbids** *or* **permits**, surface that — it's a signal this is a learning, not a decision. Suggest `/hv-learn` instead and stop. **Do not auto-invoke `/hv-learn`** — the user re-runs it deliberately.

**`--from-learning <topic>` mode.**

1. Run `.hv/bin/hv-knowledge-query "<topic>"` to load the topic section. If the helper output is empty, error: *"Topic `<topic>` not found in `.hv/KNOWLEDGE.md`. Run `.hv/bin/hv-knowledge-stats` to list topics."* and stop.
2. Parse the matched topic's bullets. Each is a one-line `- <text> <!-- YYYY-MM-DD -->`.
3. Pick the bullet to promote:
   - **1 bullet** — use it directly, no question.
   - **2-4 bullets** — call `AskUserQuestion` with header `"Bullet"` and question *"Which bullet from `<topic>` should become the decision?"*, one option per bullet. Truncate each option label to ≤80 chars; the option's description carries the full bullet text plus its date stamp.
   - **5+ bullets** — call `AskUserQuestion` the same way but with the 4 most-recent bullets as options. The 4-cap (Skill Authoring: Conventions, 2026-05-08) makes a multiSelect chunked picker overkill for this volume — if the user wants a less-recent bullet, they re-run with a more specific topic.
4. Draft the four parts from the picked bullet:
   - **Rule** = the bullet's text (the user can edit in Step 3 / Step 5).
   - **Why** = *"Promoted from KNOWLEDGE.md `<topic>` (<date>)."* plus any sub-bullet context attached to the picked bullet.
   - **Forbids** = `_(user must articulate — a bullet is passive context, a decision needs an explicit prohibit)_`
   - **Permits** = `_(user must articulate — anchors the boundary so it isn't over-applied)_`
5. Surface to the user: *"Pre-filled rule and why from KNOWLEDGE.md. Now name the forbids and permits — those are what make this a decision, not a learning."* Block until the user replies, plug their answer into Forbids / Permits, then continue to Step 3.

**`--from-spike <name>` mode.**

1. Read `.hv/spikes/<name>.md`. If absent, error: *"Spike `<name>` not found at `.hv/spikes/<name>.md`. Run `.hv/bin/hv-spike-list` to see open and closed spikes."* and stop. (Spike files always live at `.hv/spikes/<name>.md` even in umbrella mode — the `repo:` frontmatter only points at the branch's git history.)
2. Parse the spike file:
   - YAML frontmatter (`status`, `created`, `finished`, optional `repo`).
   - `## Question` — the original yes/no/conditional question.
   - `## Decision` — the verdict (`viable` / `not viable` / `depends-on-X` / `inconclusive`).
   - `## Recommended approach` — present iff verdict is `viable`.
3. Refuse to promote `inconclusive` spikes. Print *"Spike `<name>` is `inconclusive` — not enough evidence for a decision. Add findings on the spike branch and re-run `/hv-spike done <name>`, then come back."* and stop.
4. Draft the four parts from the spike content:
   - **Rule** is verdict-driven:
     - `viable` → *"Use `<X derived from question/recommended>` as the supported approach."*
     - `not viable` → *"Do not use `<X derived from question>`."*
     - `depends-on-X` → *"Use `<X>` only when `<the depends-on condition>`."*
   - **Why** = the original `## Question` plus a 1-2 sentence summary of the spike's `## Findings` section. Keep it tight — most-impactful bullets only, one paragraph max.
   - **Forbids** = `_(user must articulate — what specific patterns/files/approaches does this rule out?)_`
   - **Permits** = `_(user must articulate — what alternatives stay allowed?)_`
5. Surface the same prompt as the learning-mode path: *"Pre-filled rule and why from spike `<name>`. Now name the forbids and permits — those are what make this a decision, not a learning."* Block until the user replies, plug their answer into Forbids / Permits, then continue to Step 3.

## Step 3 — Compose the Four Parts

Every decision entry has four parts:

1. **Rule** — one-sentence statement of what the decision says
2. **Why** — one paragraph rationale (past incident, constraint, deadline, stakeholder ask)
3. **Forbids** — concrete things this rules out at apply time (patterns, files, approaches)
4. **Permits** — concrete things this still allows (anchors the boundary so it's not over-applied)

**Draft all four from conversation context.** Use a single `AskUserQuestion` call only when one of the four parts is genuinely ambiguous from context — otherwise show the assembled draft and let Step 5 handle approval.

In source-prefill modes, Step 2 has already drafted rule/why/forbids/permits — Step 3 is the user's chance to redline the draft before Step 5's confirmation gate.

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
- **`--from-learning <topic>` and `--from-spike <name>` only seed the rule and why from the source artifact.** The forbids/permits are still user-articulated — that's what makes a decision a decision.
- **`inconclusive` spikes can't be promoted.** Promotion requires a verdict the project is committing to.
