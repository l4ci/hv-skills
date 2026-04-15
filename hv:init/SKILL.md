---
name: hv:init
description: Initialize the .hv/ folder structure with TODO.md and counters.json. Called automatically by other hv: skills when the folder doesn't exist, or manually to set up a new project.
user-invocable: true
---

# hv:init — Initialize Project Backlog

Set up the `.hv/` folder with the TODO file and counter state for a project.

## Step 1 — Create the Directory

Create `.hv/` in the project root if it doesn't exist.

## Step 2 — Create TODO.md

Create `.hv/TODO.md` with this exact structure:

```markdown
# TODO

## Bugs

## Features

## Todos

## Completed
```

**If `.hv/TODO.md` already exists, do not overwrite it.** Tell the user it's already initialized.

## Step 3 — Create counters.json

Create `.hv/counters.json` with:

```json
{"bugs": 0, "features": 0, "todos": 0}
```

**If `.hv/counters.json` already exists, do not overwrite it.**

## Step 4 — Create config.json

Create `.hv/config.json` with:

```json
{
  "models": {
    "orchestrator": "opus",
    "worker": "sonnet"
  }
}
```

- `orchestrator` — the model used for planning, exploration, and verification (in `/hv:work` and `/hv:refactor`)
- `worker` — the model used for implementation subagents

Valid values: `"opus"`, `"sonnet"`, `"haiku"`.

**If `.hv/config.json` already exists, do not overwrite it.**

## Step 5 — Ensure .gitignore Covers .hv/

Check the project's `.gitignore`. If `.hv/` is not already listed, append it:

```
# ── hv backlog ──
.hv/
```

## Step 6 — Confirm

Tell the user:

```
Initialized .hv/ backlog:
  .hv/TODO.md        — bugs, features, todos
  .hv/counters.json  — auto-increment IDs
  .hv/config.json    — model config (orchestrator: opus, worker: sonnet)
  .gitignore          — .hv/ excluded

Use /hv:bug, /hv:feature, or /hv:todo to add items.
Use /hv:next to see what to work on.
Edit .hv/config.json to change which models /hv:work and /hv:refactor use.
```
