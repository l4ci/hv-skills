# Vision and plans

hv-skills supports planning above the day-to-day backlog. `/hv-vision` frames milestones and gives your project a named destination. `/hv-plan` locks an implementation approach for a slice or item before code lands. Together they keep the orchestrator executing your written intent instead of decomposing ad-hoc from an empty context.

## /hv-vision — brainstorm milestones

`/hv-vision` is a brainstorming skill. It runs Socratic discovery (2–3 questions, tailored to whether you are creating a roadmap from scratch or editing an existing one), pulls grounded findings from web research, pushes back on your scope and ordering, and proposes milestones with explicit dependencies. You iterate until the breakdown feels right.

When the session ends, `/hv-vision` writes two things to disk:

- `.hv/MILESTONES.md` — an active milestone list and a one- to two-line overview of every milestone with its status and dependencies; the file opens with a vision intro paragraph as preamble.
- `.hv/milestones/M01.md`, `M02.md`, … — one detail file per milestone with the goal, acceptance criteria, rationale, risks, and research findings.

Run `/hv-vision` whenever the conversation is about strategy, not tactics — *"plan the next quarter"*, *"what's the bigger picture"*, *"create a roadmap"*, *"brainstorm milestones"*. Re-running it on a project that already has milestones enters edit mode automatically.

## Milestones — the four statuses

Each milestone carries one of four statuses:

| Status | Meaning |
|--------|---------|
| `planned` | Not yet started; waiting on a dependency or just queued |
| `active` | In flight; work is happening against this milestone |
| `shipped` | Complete; unblocks any milestone that lists it as a dependency |
| `archived` | Abandoned or superseded; does **not** unblock dependents |

Multiple milestones can be `active` simultaneously when their dependencies allow. [`/hv-next`](picking-work.md) prefers items tagged to active milestones within each priority and size band, so the active set scopes work without being a hard wall. P0 bugs always jump the queue regardless of milestone, and general-backlog items without a tag are never excluded entirely.

When an active milestone has no open items remaining, `/hv-next` surfaces an empty-active notice so you know the milestone is ready to close. Run `.hv/bin/hv-vision-status <MID> shipped` to flip its status, which immediately unblocks any milestone that listed it as a dependency.

Marking a milestone `shipped` immediately unblocks anything that depended on it. Marking it `archived` does not. Use `archived` for milestones you are intentionally dropping, not for ones that finished.

## /hv-plan — write the implementation plan

`/hv-plan` writes a sign-off artifact for a milestone slice or a single backlog item before [`/hv-work`](running-work.md) runs. The plan lives at:

- `.hv/plans/M01-S01.md` for a slice of milestone work
- `.hv/plans/M01-B07.md` for a single item that warrants its own plan

Each plan contains: goal in one sentence, approach in 3–6 sentences, tasks with observable behaviors and verify steps, named assumptions, and open questions. Tasks must fit one execution window. If they don't, split the plan. Every task requires a verify step; a task without one is not well-defined.

When `/hv-work` starts its planning step, it checks for a matching plan file and uses it as the dispatch source instead of decomposing ad-hoc. `/hv-next` actively suggests running `/hv-plan` for size-Major items that do not have a plan yet. `/hv-vision` offers it alongside [`/hv-capture`](capturing-work.md) when you finish seeding a freshly activated milestone.

After `/hv-work` ships an item that had its own plan (e.g. `M01-B07.md`), the plan file is removed automatically — once the cycle commits, the plan's task decomposition and assumptions are stale, and leaving the file would confuse a future cycle on the same key. Slice plans (`M01-S01.md`) stay through their multi-item lifetime; remove the slice plan with `.hv/bin/hv-plan-rm M01-S01` once the slice is fully shipped.

## When to use /hv-plan vs skipping it

For small items (Minor or Cosmetic), the overhead of a plan outweighs the benefit. Capture the item with [capturing work](capturing-work.md) and run `/hv-work` directly.

For larger or higher-stakes items, especially size-Major or anything where you and the orchestrator need to agree on the approach before any worker dispatches, `/hv-plan` earns its keep. The cost is a short focused conversation. The payoff is that six weeks from now the orchestrator is executing your written approach, not its own ad-hoc interpretation.

A rough heuristic: if you would want to review the implementation approach before a colleague started coding, write the plan.

## Throwaway feasibility — /hv-spike

When a milestone hinges on a question you cannot answer from the chair (*"can SSE work over our nginx setup?"*, *"is this library's threading model compatible with ours?"*), [`/hv-spike`](spikes.md) runs an experiment on a dedicated branch that never merges. Only the findings come back as a markdown record; the experimental code stays on the spike branch as reference. See [spikes](spikes.md) for the full flow.

## Tagging items to milestones

`/hv-capture` tags captured items with the active milestone automatically when there is exactly one active. When multiple milestones are active simultaneously, it surfaces them as picks. Items can carry a `Milestone: M01` field or a comma-separated list (`Milestone: M01, M03`) when work spans milestones.

`/hv-next` prefers milestone-tagged items within each priority and size band but never excludes general-backlog items entirely. This makes the active milestone set a soft scope rather than a hard filter, so you stay focused without losing sight of the rest of the backlog.

See [capturing work](capturing-work.md) for how items are filed and [running work](running-work.md) for how `/hv-next` and `/hv-work` use the milestone tag when dispatching.
