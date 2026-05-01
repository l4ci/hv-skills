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
strategy, quality gates, autonomy level) with Recommended defaults highlighted — the defaults
are sane, so accept them unless you have a specific reason to deviate.

Two settings worth a second of thought:

- **Isolation** — `branch` is fine for solo work; switch to `worktree` if you want `main`
  untouched while agents run or plan to run parallel `/hv-work` sessions.
- **Merge strategy** — `direct` for fast iteration; `pr` if your team requires GitHub review.

To change any setting later, run `/hv-config` — don't hand-edit the JSON files.

## Your first cycle (Path A — drop into an existing project)

You have code and work piling up. This five-step loop captures it, executes it, and retains
what was learned.

```
/hv-capture "sidebar flickers + add keyboard shortcuts + update linter config"
                                       # auto-classifies into B/F/T items with IDs
/hv-next                               # reconciles state, picks next item, routes to:
                                       # → /hv-work (parallel tasks, atomic commits)
/hv-ship                               # review-gated merge or PR
/hv-learn                              # distill durable gotchas into KNOWLEDGE.md
```

**Capture.** Don't curate — dump everything in one sentence. `/hv-capture` (or `/hv-c`)
splits the input into individual items, assigns IDs (`B0N` for bugs, `F0N` for features,
`T0N` for tasks), and routes them to the correct `TODO.md` sections. Long logs or specs
overflow into per-item files automatically.

**Pick and execute.** `/hv-next` reconciles `status.json` against actual git state, archives
stale completions, and presents a sorted backlog. P0 bugs jump the queue. It suggests one
item or batch, then routes to `/hv-work` after you confirm. For high-stakes picks, run
`/hv-assume` first — it prints the intended files, tests, and assumptions before any code
lands.

**Ship.** `/hv-ship` runs a staff-engineer review (`/hv-review`) against the original intent
and `KNOWLEDGE.md`, then merges or opens a PR with an ID-linked body. FAIL blocks; CONCERNS
surface but proceed; PASS flows through.

**Learn.** `/hv-learn` writes durable gotchas, conventions, and constraints into
`KNOWLEDGE.md`, grouped by topic. A verifier judges each bullet for durability before it
lands — vague restatements are skipped.

After the second or third cycle you mostly live in `/hv-capture` and `/hv-next`. Other
skills you'll reach for: `/hv-go` for hot-path fixes that don't need a queue, `/hv-debug`
for systematic bug cycles, `/hv-pause` before stepping away, `/hv-resume` after `/clear`.

## If you're starting from a sketch (Path B — vision-driven)

You have an empty repo or a rough sketch and want to think about where the project is going
before any code lands. The flow is the same as Path A but routed through `/hv-vision` and
`/hv-plan` first: vision → milestones → implementation plan → backlog → execute → ship →
learn. When a milestone ships, mark it `shipped` to unblock dependents, then activate the
next one or run `/hv-vision` again to plan further.

See [usage/vision-and-plans.md](usage/vision-and-plans.md) for the full walkthrough.

## Where to go next

**Capture and backlog**
- [Capturing work](usage/capturing-work.md)
- [Reviewing and picking work](usage/next-and-status.md)

**Execution**
- [Running work](usage/running-work.md)
- [Debugging](usage/debugging.md)
- [Pausing and resuming](usage/pausing-and-resuming.md)

**Shipping**
- [Review and ship](usage/review-and-ship.md)
- [Learning and KNOWLEDGE.md](usage/learning.md)

**Vision and planning**
- [Vision and plans](usage/vision-and-plans.md)
- [Spikes](usage/spikes.md)

**Reference**
- [Configuration](usage/configuration.md)
- [Autonomy levels](usage/autonomy.md)
