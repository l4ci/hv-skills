---
name: hv:resume
description: Reorient after a context clear or a fresh session — shows active work streams reconciled against git, recent commits per stream, backlog counts, and routes to /hv:work, /hv:ship, or /hv:next. Use on "where was I", "pick up where I left off", "resume work", or right after /clear.
user-invocable: true
---

# hv:resume — Pick Up Where You Left Off

Read-only reorientation. Surfaces active work, recent commits per branch, and backlog counts — then routes to the right next action. No mutation.

## When to Use

- Right after `/clear` when you want to recover session context
- Starting a fresh terminal in a project that had work in flight
- *"Where was I?"*, *"What's still open?"*, *"Resume"*

## When NOT to Use

- Nothing is in progress → `/hv:next` to pick work
- You just want a state glance, no routing → `/hv:status`
- You want to commit + ship → `/hv:ship`

## Step 1 — Preflight

If `.hv/bin/hv-reconcile` doesn't exist, tell the user nothing is tracked and suggest `/hv:init`. Don't auto-init here — resume on an unset project is meaningless.

## Step 2 — Reconcile Active Work

```bash
.hv/bin/hv-reconcile
```

Parses JSON output:

- `cleaned` — stale entries already removed. Silent; no output needed.
- `needsAction` — real work streams with fields `branch`, `items`, `worktree`, `startedAt`, `hasCommits`, `commitCount`, `worktreeMissing`.

## Step 3 — Enrich Each Stream

For each entry in `needsAction`, fetch recent commit subjects so the user can see what's there without reading the diff:

```bash
git log --no-merges --format='- %h %s' <base>..<branch> | head -5
```

(Use `main` or `master` as base; match how `hv-reconcile` picked it.)

If `worktreeMissing: true`, note *"(worktree was cleaned up — run `/hv:work` to re-create)"*.

**Check for a handoff note** from `/hv:pause`:

```bash
HANDOFF=".hv/handoff/<branch>.md"
[ -f "$HANDOFF" ] && cat "$HANDOFF"
```

If the note exists, the orchestrator paused this branch deliberately — treat it as the source of truth for *intent*, not just git. Extract the **Next planned step** and **Current hypothesis** sections; they drive routing in Step 5.

## Step 4 — Summarize Backlog

```bash
.hv/bin/hv-summary
```

One-shot overview: backlog counts, any active streams (redundant with Step 2 but harmless), recent completions, knowledge topics, archive size.

## Step 5 — Present & Route

Emit one compact block, structured by stream. When a handoff note exists, surface its **Next planned step** and **Current hypothesis** inline — that's the signal the user cares about. Example:

```
Active work:

  `hv/fix-B07-timer-badge` — [B07] (paused 2026-04-18 14:32, 1 commit)
    - a1b2c3d fix: invalidate timer before badge update
    Handoff:
      Stage: mid-hypothesis verification for B07
      Next: run the verification probe in MenuBarManager.swift:54
      Uncommitted: wip commit a1b2c3d
    → Resume with /hv:work (handoff will be consumed)

  `hv/auth-refresh` — [F07] (started 2026-04-18, 0 commits)
    → In progress — run /hv:work to continue

Backlog: 4 bugs, 6 features, 2 tasks
Knowledge: 5 topics
```

Then ask: *"Resume one of these, or pick new work with `/hv:next`?"*

Routing cheat sheet by stream state:

| State | Suggest |
|-------|---------|
| Handoff note present | `/hv:work` with the handoff's "Next planned step" as the task |
| `hasCommits: true`, commits look complete, no handoff | `/hv:ship` |
| `hasCommits: true`, still mid-implementation | `/hv:work` (continue) |
| `hasCommits: false`, no handoff | `/hv:work` (pick up) or `git branch -D` to abandon |
| no active streams | `/hv:next` |

## Step 6 — Execute User's Choice

Whatever they pick, invoke the corresponding skill via the `Skill` tool. Pass the branch name and item IDs as context so the downstream skill doesn't re-read state.

**If a handoff note was consumed**, include the note's full content in the brief you pass downstream — `/hv:work` or `/hv:debug` needs the "Next planned step", "Current hypothesis", and "Do not" sections to pick up cleanly. Then delete the note:

```bash
rm .hv/handoff/<branch>.md
```

Don't delete if the user declined to resume that branch; leave the note for later.

## Rules

- **Minimal mutation.** Only two writes happen: `hv-reconcile` normalizes `status.json` (clears dead-branch entries, nulls missing worktree paths) and the handoff note is deleted after the user picks its branch to resume. `TODO.md` and `KNOWLEDGE.md` stay untouched.
- **Trust git over status.** `hv-reconcile` already reconciles; don't second-guess its output.
- **Don't re-plan.** If the user picks `/hv:work`, hand off — don't re-narrate the plan.
- **Silent on empty.** No active streams and an empty backlog → say *"Nothing in flight."* and stop. Don't manufacture work.
