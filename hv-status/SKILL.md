---
name: hv:status
description: Compact project-state overview — backlog counts, active work, recent completions, knowledge topics. Read-only and fast. Use when the user asks "what's the state", "summary", "give me a glance" — lighter than /hv:next which runs reconciliation and suggests next work.
user-invocable: true
---

# hv:status — Quick State Glance

Pure read — shows where the project stands without running git reconciliation, archival, or suggestions. Use this when the user wants to orient, not act.

## When to Use

- *"What's the state of the backlog?"*
- *"Summary?"* / *"Quick overview"*
- Before deciding whether to run `/hv:next` or `/hv:capture`

## When NOT to Use

- User wants to pick work → `/hv:next` (reconciles + suggests)
- User wants to add items → `/hv:capture`

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

If the helper is absent or exits non-zero, invoke `hv:init` via the `Skill` tool, then continue. See GUIDE.md § Preflight for exit codes.

## Step 2 — Render

```bash
.hv/bin/hv-summary
```

Pass the output through to the user verbatim. The helper emits 1-5 lines: backlog counts, any active work, recent completions, knowledge topics, archive size. Empty categories are omitted silently.

## Rules

- **Pass-through only.** Don't add commentary, don't fetch more state, don't suggest next actions — that's `/hv:next`'s job.
- **No mutation.** This skill never writes. Safe to run anywhere, anytime.
- **No git calls.** The helper reads only `.hv/` files. If you want git reconciliation, route to `/hv:next`.
