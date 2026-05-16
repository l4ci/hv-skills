---
name: hv-go
description: Capture one item and immediately implement it — combines /hv-capture and /hv-work, skipping the /hv-next review. Use when the user wants one specific thing done right now ("fix X", "add Y", "do Z") and it's not yet captured. For brain-dumping use /hv-capture; for items already in BACKLOG.md use /hv-work.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  ⚡  hv-go  ·  capture and implement in one pass
  triggers: "fix X", "add Y", "do Z"  ·  pairs: hv-capture, hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-go — Capture & Execute in One Pass

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

Invoke `hv-capture` via the `Skill` tool. Prefix the args passed to capture with `(hv-go — cap clarification at 1-2 questions)` so capture applies the speed-path question limit; then pass the user's input verbatim. `hv-capture` handles classification, ID assignment, detail files, and the `BACKLOG.md` write.

Capture runs before the clean-tree guard on purpose: `BACKLOG.md` lives under gitignored `.hv/`, so capture never dirties the tree. If Step 3 then fails, the item is safely on the backlog and the user can run `/hv-work` after cleaning up instead of re-describing it.

Record the captured IDs (e.g., `[F05]`, `[B07]`) — you need them for Step 4.

## Step 3 — Guard: Clean Working Tree

```bash
.hv/bin/hv-guard-clean "/hv-go"
```

Non-zero exit = stop and surface the script's message. Tell the user *"Captured `[ID] Title` — clean your working tree and run `/hv-work` to execute."* so they know the capture survived.

## Step 4 — Hand Off to /hv-work

Invoke `hv-work` via the `Skill` tool with a brief containing:

- The captured IDs
- Their titles and short descriptions (copy from what you just wrote to `BACKLOG.md`)
- Any detail-file paths if `hv-capture` created overflow files

`hv-work` owns the rest — plan → branch/worktree → dispatch workers → verify → commit → mark complete. No confirmation prompt; the `/hv-go` invocation is the confirmation.

## Rules

- **Delegate, don't duplicate.** Capture mechanics (ID minting, classification, detail files, `Repos:` tagging in umbrella mode) live in `/hv-capture`. Execution and post-cycle nudges (branch creation, worker dispatch, commits, post-cycle map bump via `hv-map-index`, soft-cap check, `/hv-learn`) live in `/hv-work`. `/hv-go` is a pass-through orchestrator — it does not own any of these rules independently.
- **Capture survives clean-tree guard failure.** Step 2 writes to gitignored `BACKLOG.md` before Step 3's guard. If the guard fails, the captured item is safely on the backlog; the user runs `/hv-work <ID>` after cleanup instead of re-describing the work.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
