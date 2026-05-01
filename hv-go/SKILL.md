---
name: hv-go
description: Capture one item and immediately implement it — combines /hv-capture and /hv-work, skipping the /hv-next review. Use when the user wants one specific thing done right now ("fix X", "add Y", "do Z") and it's not yet captured. For brain-dumping use /hv-capture; for items already in TODO.md use /hv-work.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  ⚡  hv-go  ·  capture and implement in one pass
  triggers: "fix X", "add Y", "do Z"  ·  pairs: hv-capture, hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-go — Capture & Execute in One Pass

Route a freshly-described bug, feature, or task straight into implementation. The item is still written to `TODO.md` with a real ID so history is preserved, but the `/hv-next` review step is skipped.

**Use for** hot-path work — fixes you want done now, not queued. **Don't use for** brainstorming (`/hv-capture`) or picking from the backlog (`/hv-next`).

## Flow

```
Init guard → Capture → Clean-tree guard → Hand off to /hv-work
```

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

## Step 2 — Capture

Invoke `hv-capture` via the `Skill` tool. Prefix the args passed to capture with `(hv-go — cap clarification at 1-2 questions)` so capture applies the speed-path question limit; then pass the user's input verbatim. `hv-capture` handles classification, ID assignment, detail files, and the `TODO.md` write.

Capture runs before the clean-tree guard on purpose: `TODO.md` lives under gitignored `.hv/`, so capture never dirties the tree. If Step 3 then fails, the item is safely on the backlog and the user can run `/hv-work` after cleaning up instead of re-describing it.

Record the captured IDs (e.g., `[F05]`, `[B07]`) — you need them for Step 4.

## Step 3 — Guard: Clean Working Tree

```bash
.hv/bin/hv-guard-clean "/hv-go"
```

Non-zero exit = stop and surface the script's message. Tell the user *"Captured `[ID] Title` — clean your working tree and run `/hv-work` to execute."* so they know the capture survived.

## Step 4 — Hand Off to /hv-work

Invoke `hv-work` via the `Skill` tool with a brief containing:

- The captured IDs
- Their titles and short descriptions (copy from what you just wrote to `TODO.md`)
- Any detail-file paths if `hv-capture` created overflow files

`hv-work` owns the rest — plan → branch/worktree → dispatch workers → verify → commit → mark complete. No confirmation prompt; the `/hv-go` invocation is the confirmation.

## Rules

- **Capture is real.** IDs increment, entries land in `TODO.md`, detail files get written. Preserves audit trail.
- **Multiple items OK.** If the user mentioned 3 items, all get captured and all get passed to `/hv-work` as a batch.
- **Delegate, don't duplicate.** Every capture rule lives in `/hv-capture`; every execution rule lives in `/hv-work`.
