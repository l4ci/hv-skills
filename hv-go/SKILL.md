---
name: hv:go
description: Capture a work item and immediately implement it — combines /hv:capture and /hv:work in one pass. Use when the user describes something they want done now, not queued. Writes to TODO.md (history preserved, counters incremented) but skips the backlog-review round-trip that /hv:next does. Trigger on "fix X", "add Y", "do Z and commit" when the user clearly wants action, not a backlog entry.
user-invocable: true
---

# hv:go — Capture & Execute in One Pass

Route a freshly-described bug, feature, or task straight into implementation. The item is still written to `TODO.md` with a real ID and counted, so history is preserved, but you skip the `/hv:next` review step.

## When to Use

- User says "fix X", "add Y", "do Z" — and clearly wants action now, not a backlog entry
- Small, self-contained items where the capture-then-review cadence is overkill
- Hot-path work: you notice a bug while building and want to fix it on the spot

## When NOT to Use

- User is brainstorming or dumping ideas → use `/hv:capture`
- User wants to pick from the existing backlog → use `/hv:next`
- Multiple unrelated items that need prioritization → `/hv:capture` first, then `/hv:next` to decide order

## Flow

```
Init guard → Clean-tree guard → Capture → Hand off to /hv:work
```

## Step 1 — Ensure .hv/ Exists

If `.hv/bin/hv-next-id` is missing, invoke the `hv:init` skill via the `Skill` tool, then continue.

## Step 2 — Guard: Clean Working Tree

```bash
.hv/bin/hv-guard-clean "/hv:go"
```

Fail early — no point capturing if we can't execute. Non-zero exit = stop and surface the script's message to the user.

## Step 3 — Capture

Invoke the `hv:capture` skill via the `Skill` tool, passing the user's input verbatim. `hv:capture` handles classification, ID assignment, detail files, clarifying questions, and the `TODO.md` write.

Keep clarifying questions tight — for `/hv:go` specifically, ask **at most 1-2** questions, and only if the item is too vague to implement. Anything more is better gathered by the worker agent during execution. If the input is clear (e.g., *"fix the off-by-one in RingBuffer.write when buf is empty"*), ask nothing.

**Record the IDs** that were just captured (e.g., `[F05]`, `[B07]`). You need them for Step 4.

## Step 4 — Hand Off to /hv:work

Invoke the `hv:work` skill via the `Skill` tool with a brief containing:

- The IDs just captured (e.g., `[B07]`, `[F05]`)
- Their titles and short descriptions (copy from what you just wrote to `TODO.md`)
- Any detail-file paths (if `hv:capture` created overflow files)

`hv:work` owns the rest: plan → branch/worktree → status register → dispatch workers → verify → commit → mark complete.

Do not require the user to confirm the hand-off. The `/hv:go` invocation itself is the confirmation.

## Rules

- **One pass.** No "confirm before working" prompt — the invocation means go.
- **Capture is still real.** IDs increment, entries land in `TODO.md`, detail files get written. Nothing is fake-captured. This preserves audit trail and lets `/hv:next` show completed items naturally.
- **Guard first.** Clean-tree check runs before capture so we don't write orphan TODO entries we can't act on.
- **Multiple items OK.** If the user mentioned 3 items, all get captured and all get passed to `/hv:work` as a batch.
- **Delegate, don't duplicate.** Every capture rule lives in `/hv:capture`; every execution rule lives in `/hv:work`. `/hv:go` is the conductor, not a rewrite.
