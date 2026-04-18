---
name: hv:go
description: Capture a work item and immediately implement it — combines /hv:capture and /hv:work in one pass. Writes to TODO.md (counters increment, history preserved) but skips the backlog-review round-trip. Trigger on "fix X", "add Y", "do Z" when the user clearly wants action, not a backlog entry.
user-invocable: true
---

# hv:go — Capture & Execute in One Pass

Route a freshly-described bug, feature, or task straight into implementation. The item is still written to `TODO.md` with a real ID so history is preserved, but the `/hv:next` review step is skipped.

**Use for** hot-path work — fixes you want done now, not queued. **Don't use for** brainstorming (`/hv:capture`) or picking from the backlog (`/hv:next`).

## Flow

```
Init guard → Clean-tree guard → Capture → Hand off to /hv:work
```

## Step 1 — Ensure .hv/ Exists

If `.hv/bin/hv-next-id` is missing, invoke `hv:init` via the `Skill` tool, then continue.

## Step 2 — Guard: Clean Working Tree

```bash
.hv/bin/hv-guard-clean "/hv:go"
```

Fail early — no point capturing if we can't execute. Non-zero exit = stop and surface the script's message.

## Step 3 — Capture

Invoke `hv:capture` via the `Skill` tool, passing the user's input verbatim. `hv:capture` handles classification, ID assignment, detail files, and the `TODO.md` write.

**Keep clarifying questions tight.** Ask at most 1-2, and only if the item is too vague to implement. Anything more is better gathered by the worker during execution. If the input is clear, ask nothing.

Record the captured IDs (e.g., `[F05]`, `[B07]`) — you need them for Step 4.

## Step 4 — Hand Off to /hv:work

Invoke `hv:work` via the `Skill` tool with a brief containing:

- The captured IDs
- Their titles and short descriptions (copy from what you just wrote to `TODO.md`)
- Any detail-file paths if `hv:capture` created overflow files

`hv:work` owns the rest — plan → branch/worktree → dispatch workers → verify → commit → mark complete. No confirmation prompt; the `/hv:go` invocation is the confirmation.

## Rules

- **Capture is real.** IDs increment, entries land in `TODO.md`, detail files get written. Preserves audit trail.
- **Guard first.** Clean-tree check runs before capture so we don't write orphan TODO entries we can't act on.
- **Multiple items OK.** If the user mentioned 3 items, all get captured and all get passed to `/hv:work` as a batch.
- **Delegate, don't duplicate.** Every capture rule lives in `/hv:capture`; every execution rule lives in `/hv:work`.
