# Getting started

Install hv-skills and run your first capture → work → ship cycle in about five minutes.

## Install

Add the plugin from the marketplace, then activate it:

```bash
claude plugin marketplace add l4ci/hv-skills
claude plugin install hv-skills
```

For git-clone or GNU stow installs, see the [Install alternatives](../README.md#install-alternatives) section in the project README.

## Initialize the project

Run `/hv-init` once at the project root. It asks five questions (models, isolation, merge
strategy, quality gates, autonomy level) with Recommended defaults highlighted. Accept the
defaults unless you have a reason not to.

Two settings worth a second of thought:

- **Isolation.** `branch` is fine for solo work. Switch to `worktree` if you want `main`
  untouched while agents run, or if you plan to run parallel `/hv-work` sessions.
- **Merge strategy.** `direct` for fast iteration. `pr` if your team requires GitHub review.

To change any setting later, run `/hv-config`. Don't hand-edit the JSON files.

## Your first cycle (Path A: drop into an existing project)

You have code and work piling up. This loop captures it, executes it, and keeps the lessons
around for next time.

```bash
# 1. brain-dump — the model splits and classifies; nothing is curated by hand
/hv-capture "sidebar flickers on first load, add keyboard shortcuts for nav, lint config drifted from team standard"
# → [B01] sidebar flicker on first load     (Bug, P1, Major)
# → [F01] keyboard shortcuts for nav        (Feature, Minor)
# → [T01] align lint config with team       (Task)

# 2. review backlog; reconcile against git; suggest next
/hv-next
# → suggests [B01] (P1 first); on confirm dispatches /hv-work [B01]
#   orchestrator decomposes → workers implement in parallel → atomic commit per task

# 3. (optional) hot-path fix that doesn't deserve a queue round-trip
/hv-go "fix typo in CONTRIBUTING.md"
# → captures [T02] and implements in one pass

# 4. (optional) when /hv-work hits a real bug, run a debug cycle
/hv-debug B01
# → reproduce → hypothesize → verify hypothesis → fix → nudge /hv-learn

# 5. ship — runs /hv-review (PASS / CONCERNS / FAIL), then GitHub PR or direct merge
/hv-ship

# 6. distill what was non-obvious; verifier judges each bullet before it lands
/hv-learn
# → "First-paint flicker came from layout shift in <Sidebar>; reserve width with min-width"
#   filed under "Performance & Rendering" → consulted by future /hv-work
```

**Capture.** Don't curate. Dump everything in one sentence. `/hv-capture` (or `/hv-c`)
splits the input into individual items, assigns IDs (`B0N` for bugs, `F0N` for features,
`T0N` for tasks), and routes them to the correct `BACKLOG.md` sections. Long logs or specs
overflow into per-item files automatically.

**Pick and execute.** `/hv-next` reconciles `status.json` against actual git state, archives
stale completions, and presents a sorted backlog. P0 bugs jump the queue. It suggests one
item or batch, then routes to `/hv-work` after you confirm. For high-stakes picks, run
`/hv-assume B01` first; it prints the intended files, tests, and assumptions before any
code lands.

**Ship.** `/hv-ship` runs a staff-engineer review (`/hv-review`) against the original intent
and `KNOWLEDGE.md`, then merges or opens a PR with an ID-linked body. FAIL blocks; CONCERNS
surface but proceed; PASS flows through.

**Learn.** `/hv-learn` writes durable gotchas, conventions, and constraints into
`KNOWLEDGE.md`, grouped by topic. A verifier judges each bullet for durability before it
lands and skips vague restatements. To encode a hard boundary like "never store tokens
client-side", use `/hv-decide` instead. See [decisions](usage/decisions.md).

**Visible progress.** Multi-step skills (`/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-release`,
`/hv-docs`, `/hv-refactor`, and others) declare a phase checklist via `TaskCreate` at the
start of each run and tick each phase off as it lands. Long cycles stay legible: preflight,
plan, dispatch, verify, commit, and merge are discrete checkpoints rather than an undifferentiated
stream of bash output. The checklist is silently skipped on hosts where the tool isn't loaded.

After the second or third cycle you mostly live in `/hv-capture` and `/hv-next`. Other
skills you'll reach for: `/hv-go` for hot-path fixes that don't need a queue, `/hv-debug`
for systematic bug cycles, `/hv-pause` before stepping away, `/hv-next` after `/clear`.

## If you're starting from a sketch (Path B: vision-driven)

You have an empty repo or a rough sketch and want to think about where the project is going
before any code lands. The flow routes through `/hv-vision` and `/hv-plan` first, then joins
the same execute → ship → learn loop.

```bash
# 1. brainstorm vision and milestones — Socratic discovery, web research, deliberate challenge
/hv-vision
# → MILESTONES.md: M01 active, M02 (depends: M01), M03 (depends: M01)
# → .hv/milestones/M01.md: goal, acceptance, rationale, risks, research notes
# → CLAUDE.md vision-index updated so /hv-next scopes picks to M01

# 2. (optional) de-risk an unknown before committing to a milestone — branch never merges
/hv-spike sse-over-nginx
# → spike/sse-over-nginx + .hv/spikes/sse-over-nginx.md (question / findings / decision)

# 3. write the implementation plan for the first slice — /hv-work consults it later
/hv-plan M01-S01
# → .hv/plans/M01-S01.md: tasks with verifiable outcomes, named assumptions, open questions

# 4. seed the backlog with milestone-tagged items
/hv-capture "OAuth callback handler, secure token storage, refresh-token flow"
# → [F02][F03][F04] all tagged Milestone: M01

# 5. (optional) peek the orchestrator's intended approach before code lands
/hv-assume F02
# → reads M01-S01 plan; prints intended files / tests / assumptions / unknowns; nothing executes

# 6. active milestone scopes the suggestion; /hv-work consults the plan
/hv-next
# → suggests [F02]; runs /hv-work against M01-S01.md

# 7. ship the slice; PR body links resolved IDs and the milestone
/hv-ship

# 8. capture what surfaced
/hv-learn
# → "PKCE callback timing varies in dev — gate on window.location.origin"
#   filed under "Auth & Identity"
```

When the milestone ships, mark it `shipped` to unblock dependents, then activate the next
one or run `/hv-vision` again to plan further. See [usage/vision-and-plans.md](usage/vision-and-plans.md)
for the full walkthrough.

## Where to go next

**Capture and backlog**
- [Capturing work](usage/capturing-work.md)
- [Picking work](usage/picking-work.md)

**Execution**
- [Running work](usage/running-work.md)
- [Debugging](usage/debugging.md)
- [Pausing and resuming](usage/pausing-and-resuming.md)

**Shipping**
- [Review and ship](usage/review-and-ship.md)
- [Learning and KNOWLEDGE.md](usage/learning.md)
- [Decisions and DECISIONS.md](usage/decisions.md)

**Vision and planning**
- [Vision and plans](usage/vision-and-plans.md)
- [Spikes](usage/spikes.md)

**Reference**
- [Configuration](usage/configuration.md)
- [Autonomy levels](usage/autonomy.md)
