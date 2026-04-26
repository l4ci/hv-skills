---
name: hv-vision
description: Brainstorm a project's bigger vision and break it into milestones — Socratic discovery, web research for outside perspective, deliberate challenge, then write MILESTONES.md and per-milestone detail files. Handles both creating a fresh vision and editing/extending an existing one. Use on "let's plan", "what's the bigger picture", "create a roadmap", "brainstorm milestones", or when the user wants strategy above the day-to-day backlog.
user-invocable: true
---

# hv-vision — Brainstorm Project Vision & Milestones

Sit above the day-to-day backlog. The user describes where they want the project to go; this skill challenges that framing, grounds it in outside research, and produces a milestone plan with explicit dependencies. Multiple milestones can be active at once when they don't depend on each other.

`MILESTONES.md` is the overview (vision paragraph, active list, one short section per milestone). `.hv/milestones/MNN.md` holds the full plan for each milestone (goal, acceptance criteria, rationale, open risks, research findings, free-form notes).

## Step 1 — Preflight & Mode

```bash
.hv/bin/hv-preflight
```

If the helper is absent or exits non-zero, invoke `hv-init` via the `Skill` tool, then continue. See GUIDE.md § Preflight for exit codes.

Determine the mode silently:

```bash
.hv/bin/hv-vision-list
```

- **Empty list** → **Create mode** (no milestones yet, building the vision from scratch)
- **Non-empty** → **Edit mode** (extend, refine, retire, or re-prioritize existing milestones)

Don't announce the mode — it shapes the questions you ask, not the user's view.

## Step 2 — Load Context Silently

Before opening the conversation, gather everything that should inform the brainstorm:

- `.hv/MILESTONES.md` (current vision paragraph and overviews)
- Every `.hv/milestones/M*.md` (full per-milestone plans — read whatever exists)
- `.hv/TODO.md` (what's already on the backlog hints at the user's mental model)
- `.hv/KNOWLEDGE.md` topics via `hv-knowledge-query` if any topic plausibly relates to the project's domain
- `README.md`, `package.json`, `Cargo.toml`, `pyproject.toml`, or whatever stack file exists at the root
- Recent git history: `git log --oneline -20`

Don't dump these to the user. Read them, form a picture, and use what's relevant in Step 3.

## Step 3 — Frame & Discover

Open with one short paragraph (3–4 sentences max) summarizing what you see — the project's apparent shape, the existing milestones if any, the obvious gaps. This grounds the conversation; it's not a status report.

Then ask discovery questions via `AskUserQuestion`. Tailor them to the mode:

**Create mode** — single call with 2–3 questions:

- **Header `"Scope"`** — *"What kind of work is this?"*
  - New product / new major feature line
  - Strategic refactor or platform shift
  - Research / discovery project
  - Other (free text)
- **Header `"Audience"`** — *"Who's the consumer of the result?"* (single-select with options that match the project's apparent type, plus Other)
- **Header `"Constraint"`** — *"Hard time or scope constraint?"* — options like *"Ship something usable in 4 weeks"*, *"No constraint, optimize for quality"*, *"Hit a specific event/launch date"*, Other.

**Edit mode** — single question, single-select:

- **Header `"Action"`** — *"What do you want to do with the vision?"*
  - Add a new milestone (Recommended if vision feels incomplete)
  - Refine an existing milestone (goal/acceptance/risks)
  - Retire one or activate/deactivate
  - Re-prioritize the active set
  - Explore a new direction the project should consider

Plain-text fallback: ask the same question once in prose; if the answer is ambiguous, pick the Recommended interpretation, name it, and proceed. (See GUIDE.md § Host Question Conventions.)

## Step 4 — Web Research

Before proposing milestones, ground the conversation in outside context. Use `WebSearch` (and `WebFetch` for promising results) to look up:

- Prior art for the project category — what others have built, how they structured it
- Common pitfalls in this space
- Architectural or product patterns worth borrowing
- Recent industry shifts that change the calculus

Run 2–4 searches max — depth over breadth. Pull in 3–5 concrete findings the user can react to. Each finding should be **actionable** in the milestone discussion: *"here's a pitfall to avoid in M01"*, *"here's a pattern worth borrowing"*, *"here's a competitor's mistake."*

Present findings inline with citations. If a search yields nothing useful, say so and move on — don't pad with generic observations.

When you find a finding that contradicts the user's current framing, that's exactly what Step 5 needs. Hold onto it.

## Step 5 — Challenge

Push back on the framing. This is the highest-value step — a polite review wastes the cycle. Concrete tactics:

- **Scope check** — *"M02 has 12 acceptance criteria. That's months. What's the smaller version that ships in two weeks?"*
- **Risk frontloading** — *"M01 assumes auth is straightforward. Research suggests session storage is the bigger risk. Frontload it?"*
- **Overlap detection** — *"M02 and M03 touch the same code 60%. Are they really separate milestones, or one delivered in two phases?"*
- **Cut tradeoff** — *"What would you cut if you had to ship in half the time? That's probably what M01 should be."*
- **Dependency surfacing** — *"You said M03 is independent, but M03 needs M01's auth. Mark the dependency, or change M03's scope?"*
- **Assumption naming** — explicitly name implicit assumptions (*"this assumes single-tenant"*) and force the user to take a stance.
- **"Why this order"** — for each adjacent pair, ask why the earlier one comes first. If the answer is *"it just feels right"*, dig deeper.

If multiple challenge points need user input, batch them into one `AskUserQuestion` call (max 3 questions). Use `multiSelect: true` when the user is choosing which subset of trade-offs to take.

This step is interactive — expect to iterate with the user. Don't move to Step 6 until the framing has survived honest pushback.

## Step 6 — Propose Milestones

Output a clear plan as plain markdown (not yet committed to disk):

```
M01 — Auth foundation     [ready · no deps]
  Goal: OAuth + sessions for end users.
  Acceptance:
    - Google + GitHub OAuth login works
    - Sessions persist across browser restarts
    - Token refresh handles 401 transparently
  Rationale: Foundation for everything user-facing.
  Open risks: Session storage choice (DB vs Redis).

M02 — Multi-tenant         [blocked · depends M01]
  Goal: Org isolation for B2B customers.
  ...
```

Rules for the plan:

- **No hard cap on count.** Take as many milestones as the vision needs. Five is common, two is fine, fifteen is fine.
- **Mark each as `ready` or `blocked`** based on dependencies. Ready = all prerequisite milestones are shipped (or have no deps). Blocked = at least one prerequisite is still planned/active.
- **State dependencies explicitly** in the heading and `Depends:` line. Don't bury them in prose.
- **Ordering is by dependency layer, not chronology.** Independent milestones that could run in parallel sit at the same layer — make this visible (*"M01 and M03 are both ready, no deps between them"*).
- **Each milestone gets a 1-sentence goal**, 3–5 acceptance bullets, a 1–2 sentence rationale, and at least one open risk. If you can't name a risk, the milestone isn't well thought out yet.

## Step 7 — Iterate

The user redlines. Common edits:

- *"Combine M02 and M03"* — merge them in the plan, restate, ask for confirmation
- *"M01 should ship faster, cut acceptance #3"* — adjust, restate
- *"M04 actually depends on M02"* — update the dependency, recompute ready/blocked
- *"Add an M05 for X"* — extend the plan
- *"Retire M03, we're not doing that anymore"* — drop it (or keep it with `status: shipped` if already shipped, or just remove the section)

Iterate until the user explicitly confirms. Don't skip confirmation — the writes in Step 8 mutate disk state.

## Step 8 — Write to Disk

Once confirmed, persist each milestone. Batch all writes, then refresh the index once at the end.

**New milestone:**

```bash
.hv/bin/hv-vision-add "<title>" "<one-line summary>" "<depends-csv>"
```

The helper mints `MNN`, creates `.hv/milestones/MNN.md` with a stub plan, and appends an overview block to `.hv/MILESTONES.md`. Status starts as `planned`.

**Fill in the detail file.** After `hv-vision-add` creates the stub, edit `.hv/milestones/MNN.md` with the full content — replace the placeholder sections (`Goal`, `Acceptance criteria`, `Rationale`, `Open risks`, `Research findings`, `Notes`) with what the brainstorm produced. Use the `Edit` tool, not `Write`, so the frontmatter stays intact.

**Existing milestone edits:** use `Edit` to update `.hv/milestones/MNN.md` directly. If you change the title or the dependencies, also update the `### MNN — Title` section in `.hv/MILESTONES.md` so the overview matches.

**Activate / deactivate:** call `.hv/bin/hv-vision-status MNN <planned|active|shipped>` once per milestone whose status changed. Multi-active is supported — independent milestones (no shared dependencies) can run simultaneously.

**Vision paragraph (Create mode only).** Replace the top-of-file placeholder in `MILESTONES.md` *"(no vision yet — run `/hv-vision` to brainstorm milestones)"* with 2–4 sentences that frame the project's why. In Edit mode, leave the paragraph alone unless the brainstorm meaningfully changed the framing.

**Refresh the index — once, at the end:**

```bash
.hv/bin/hv-vision-index
```

This regenerates `## Active milestones` in `MILESTONES.md` and the managed `<!-- hv-vision-start -->` block in `CLAUDE.md`. It also heals any drift in the per-section `**Status:**` lines from frontmatter — frontmatter is the single source of truth.

## Step 9 — Report (with optional handoff)

One compact summary:

```
Vision updated.
- M01 — Auth foundation         [active · ready]
- M02 — Multi-tenant             [planned · blocked by M01]
- M03 — Public API               [active · ready]
- M04 — Admin dashboard          [planned · blocked by M01, M02]

Active: M01, M03. Run /hv-capture to start filling items, or /hv-next to pick from the existing backlog.
```

If a freshly active milestone has no captured items yet, append a one-line offer instead of just printing the run hint:

> *"M01 has no items yet — start populating now? I can hand off to `/hv-capture` with M01's acceptance criteria as the seed."*

If the user accepts, invoke `/hv-capture` via the `Skill` tool with a brief like:

```
(/hv-vision — capture seed items for M01)

Active milestone: M01 — Auth foundation.
Acceptance criteria:
- ...

Capture these as discrete items, tag each with Milestone: M01.
```

Otherwise the run is done. Don't recap discovery, research, or the challenge round — those happened in the conversation.

## Key Principles

- **Challenge, don't transcribe.** A polite write-down of whatever the user says is failure. The point of `/hv-vision` is to surface assumptions, frontload risks, and force tradeoffs before milestones land on disk.
- **Research is grounding, not decoration.** If a finding doesn't change a milestone's shape, it doesn't belong in the conversation.
- **Dependencies are explicit.** Every blocked relationship is named. `ready` vs `blocked` is computed from disk, not vibes.
- **Multi-active is fine.** Independent milestones can run in parallel. Don't force a single-track ordering when the dependency graph allows more.
- **No hard milestone count.** Two is fine. Fifteen is fine. Take what the vision needs.
- **`MILESTONES.md` is the overview; `milestones/MNN.md` is the plan.** Don't bloat the overview with full plans, and don't scatter the overview across detail files.
- **Active list is generated, not edited.** `## Active milestones` is regenerated by `hv-vision-index` from frontmatter — never hand-edit it.
