# Picking work

Two flows help you orient and pick what to do next. `/hv-next` reconciles git state, surfaces any [`/hv-pause`](pausing-and-resuming.md) handoff note for active streams, presents the backlog, and suggests work. `/hv-work --preview <ID>` lets you peek at the orchestrator's plan before code lands.

## /hv-next

Reconciles the backlog against actual git state, then suggests what to pick up.

Before presenting results it:

1. Validates active branches and worktrees against git; stale entries get cleaned automatically.
2. Archives completions older than five days to `ARCHIVE.md`.
3. Builds a relationship map from `Related:` links and finds clusters.
4. Sorts the backlog by priority and size, with cluster notes.
5. Suggests one item or a connected batch. P0 bugs jump the queue.

```mermaid
flowchart TD
    A[/hv-next] --> B[Reconcile status.json vs git]
    B --> C{Active streams?}
    C -->|Yes| D[Read handoff notes per stream]
    D --> E[Ask: resume / ship / abandon]
    E --> F[Archive completions older than 5d]
    C -->|No| F
    F --> G[Present backlog tables + clusters]
    G --> H[Suggest one item or batch]
    H --> I{User picks…}
    I -->|Start| J[/hv-work]
    I -->|Peek first| K[/hv-work --preview]
    I -->|Different pick| H
    I -->|Stop| L[End]
```

After you confirm the pick, `/hv-next` routes you to [running work](running-work.md) via `/hv-work`.

**Example:**

```
/hv-next
```

Output: a backlog table with a highlighted suggestion, e.g. `→ Suggest: B03 (P0 bug): fix auth token expiry`. Answer `y` (or pick a different item) and work begins.

If the suggestion is a size-Major feature or a P0/P1 bug, `/hv-next` offers `/hv-work --preview` as a question option before routing to `/hv-work`.

Items with a `Related:` field that share a cluster surface together so you can tackle them as a unit.

## /hv-work --preview: peek before you commit

Prints the orchestrator's intended approach for an item before any code is written. Read-only: no writes, no commits.

Output structure:

- One-paragraph approach summary
- Bulleted lists: *Files I'd touch*, *Files I'd create*, *Tests I'd add*, *Assumptions I'm making*, *Known unknowns*

Use it as a cheap gate before `/hv-work` on size-Major-or-larger items or P0/P1 bugs, where corrections after the fact are expensive. Review the output, then push back, ask for a durable plan ([`/hv-plan`](vision-and-plans.md)), or proceed to [running work](running-work.md) by re-invoking `/hv-work` without the flag.

**Example:**

```
/hv-work --preview F08
```

Output: specific file paths, test names, and function names the orchestrator would touch, not generic descriptions.

If a plan already exists at [`.hv/plans/<key>.md`](../reference/hv-folder.md), the peek restates it. Without a plan, the output is an ad-hoc decomposition; reach for `/hv-plan` when alignment needs to survive beyond the current session.

## How reconciliation keeps state honest

The status cache is a speed optimisation; git is the source of truth. Each `/hv-next` run checks which branches and worktrees actually exist: deleted branches become stale entries and get cleaned up, removed worktrees get updated in kind. If state drifts (crashed session, manual git operations), the next `/hv-next` run repairs it without manual intervention.
