---
name: hv-status
description: Compact project-state overview — backlog counts, active work, recent completions, knowledge topics. Read-only and fast. Use when the user asks "what's the state", "summary", "give me a glance" — lighter than /hv-next which runs reconciliation and suggests next work.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  📊  hv-status  ·  compact project state overview
  triggers: "status", "summary"  ·  pairs: hv-next, hv-resume
════════════════════════════════════════════════════════════════════════
```

# hv-status — Quick State Glance

## When to Use

- *"What's the state of the backlog?"*
- *"Summary?"* / *"Quick overview"*
- Before deciding whether to run `/hv-next` or `/hv-capture`

## When NOT to Use

- User wants to pick work → `/hv-next` (reconciles + suggests)
- User wants to add items → `/hv-capture`

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

## Step 2 — Render

```bash
.hv/bin/hv-summary
```

Pass the output through to the user verbatim. The helper emits 1-5 lines: backlog counts, any active work, recent completions, knowledge topics, archive size. Empty categories are omitted silently.

**Umbrella mode.** Active entries display an inline `(repo: <name>)` suffix when their `repo` field is non-null; `bin/hv-backlog` (used elsewhere) renders a `Repo` column in the In Progress table when any active entry has a repo. Single-repo cycles see neither — the skill stays a pure pass-through, no umbrella-specific code path here.

## Rules

- **Pass-through only.** Don't add commentary, don't fetch more state, don't suggest next actions — that's `/hv-next`'s job.
- **No mutation.** This skill never writes. Safe to run anywhere, anytime.
- **No git calls.** The helper reads only `.hv/` files. If you want git reconciliation, route to `/hv-next`.
