---
name: hv:init
description: Initialize the .hv/ folder structure with TODO.md, counters.json, config.json, status.json, and CLI helpers. Called automatically by other hv: skills when the folder doesn't exist, or manually to set up a new project.
user-invocable: true
---

# hv:init — Initialize Project Backlog

Set up the `.hv/` folder with data files and CLI helpers for a project.

## Step 1 — Create Directories and Data Files

Run this in the project root:

```bash
set -euo pipefail
HV=".hv"
mkdir -p "$HV"/{bugs,features,tasks,bin}

[ -f "$HV/TODO.md" ] || cat > "$HV/TODO.md" <<'EOF'
# TODO

## Bugs

## Features

## Tasks

## Completed
EOF

[ -f "$HV/counters.json" ] || echo '{"bugs":0,"features":0,"tasks":0}' > "$HV/counters.json"

[ -f "$HV/config.json" ] || cat > "$HV/config.json" <<'CONF'
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
CONF

[ -f "$HV/status.json" ] || echo '{"active":[]}' > "$HV/status.json"

if [ -f .gitignore ]; then
  grep -qxF '.hv/' .gitignore 2>/dev/null || printf '\n# ── hv backlog ──\n.hv/\n' >> .gitignore
else
  printf '# ── hv backlog ──\n.hv/\n' > .gitignore
fi
```

Data files are never overwritten if they already exist.

## Step 2 — Install CLI Helpers

Find the hv-skills `bin/` directory and copy the helpers to `.hv/bin/`:

1. Use Glob to find `**/bin/hv-next-id` under `~/.agents/skills/` or `~/.claude/`
2. Copy all `hv-*` scripts from that directory to `.hv/bin/` and make them executable:

```bash
cp <source-bin>/hv-* .hv/bin/ && chmod +x .hv/bin/hv-*
```

Helpers are always refreshed — they're tools, not data.

The scripts are: `hv-next-id`, `hv-append`, `hv-complete`. They require `python3`.

## Step 3 — Confirm

Tell the user:

```
Initialized .hv/ backlog:
  .hv/TODO.md         — bugs, features, tasks
  .hv/counters.json   — auto-increment IDs
  .hv/config.json     — model, isolation, and merge settings
  .hv/status.json     — active work stream tracking
  .hv/bin/             — CLI helpers (hv-next-id, hv-append, hv-complete)
  .hv/bugs/            — overflow detail files for bug reports
  .hv/features/        — overflow detail files for feature specs
  .hv/tasks/           — overflow detail files for task descriptions
  .gitignore           — .hv/ excluded

Use /hv:capture to add bugs, features, or tasks.
Use /hv:next to see what to work on.
Edit .hv/config.json to change models, isolation, or merge strategy.
```

If `.hv/TODO.md` already existed, tell the user it was already initialized and that helper scripts were refreshed.

## Config Reference

- `models.orchestrator` — model for planning, exploration, design, and verification (`"opus"`, `"sonnet"`, `"haiku"`)
- `models.worker` — model for implementation subagents
- `work.isolation` — `"branch"` (default) or `"worktree"` (isolated directory under `.claude/worktrees/`)
- `work.mergeStrategy` — `"direct"` (default, merge to main) or `"pr"` (push and create GitHub PR)
- `refactor.confirmBeforeExecute` — `true` (default, pause for approval) or `false` (full autonomy)
