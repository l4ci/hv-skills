---
name: hv:init
description: Initialize the .hv/ folder structure with TODO.md, counters.json, config.json, and status.json. Called automatically by other hv: skills when the folder doesn't exist, or manually to set up a new project.
user-invocable: true
---

# hv:init — Initialize Project Backlog

Set up the `.hv/` folder with the TODO file, counter state, config, and status tracking for a project.

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
  },
  "work": {
    "isolation": "branch",
    "mergeStrategy": "direct"
  },
  "refactor": {
    "confirmBeforeExecute": true
  }
}
```

- `models.orchestrator` — the model used for planning, exploration, design, and verification (in `/hv:work` and `/hv:refactor`)
- `models.worker` — the model used for implementation subagents
- `work.isolation` — `"branch"` (default) creates a feature branch in the current worktree. `"worktree"` creates an isolated git worktree under `.claude/worktrees/`.
- `work.mergeStrategy` — `"direct"` (default) merges the branch into main after verification. `"pr"` pushes the branch and creates a GitHub PR instead.
- `refactor.confirmBeforeExecute` — when `true`, `/hv:refactor` pauses for user approval before executing fixes. Set `false` for full autonomy.

Valid model values: `"opus"`, `"sonnet"`, `"haiku"`.

**If `.hv/config.json` already exists, do not overwrite it.**

## Step 5 — Create status.json

Create `.hv/status.json` with:

```json
{"active": []}
```

This file tracks in-progress work streams. It is managed by `/hv:work` and read by `/hv:next`. Do not edit it manually.

**If `.hv/status.json` already exists, do not overwrite it.**

## Step 6 — Ensure .gitignore Covers .hv/

Check the project's `.gitignore`. If `.hv/` is not already listed, append it:

```
# ── hv backlog ──
.hv/
```

## Step 7 — Confirm

Tell the user:

```
Initialized .hv/ backlog:
  .hv/TODO.md        — bugs, features, todos
  .hv/counters.json  — auto-increment IDs
  .hv/config.json    — model, isolation, and merge settings
  .hv/status.json    — active work stream tracking
  .gitignore          — .hv/ excluded

Use /hv:bug, /hv:feature, or /hv:todo to add items.
Use /hv:next to see what to work on.
Edit .hv/config.json to change models, isolation, or merge strategy.
```
