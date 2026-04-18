---
name: hv:init
description: Initialize the .hv/ folder structure with TODO.md, KNOWLEDGE.md, counters.json, config.json, status.json, and CLI helpers. Also seeds a managed knowledge-index block in CLAUDE.md so future /hv:work runs can consult learnings. Called automatically by other hv: skills when the folder doesn't exist, or manually to set up a new project.
user-invocable: true
---

# hv:init — Initialize Project Backlog

Set up the `.hv/` folder with data files and CLI helpers for a project.

## Step 1 — Verify Environment

Before touching the filesystem, make sure the tools we depend on are present:

```bash
command -v git >/dev/null 2>&1 || { echo "error: git is required but not installed" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required but not installed" >&2; exit 1; }
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "warning: not a git repository — /hv:work and /hv:refactor require git. Initialize with \`git init\` before using those skills." >&2
fi
```

The `git init` suggestion is a warning, not a hard stop — `/hv:capture`, `/hv:next`, and `/hv:learn` work fine without a repo.

## Step 2 — Create Directories and Data Files

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

[ -f "$HV/KNOWLEDGE.md" ] || cat > "$HV/KNOWLEDGE.md" <<'EOF'
# Knowledge

Durable learnings captured from sessions — gotchas, conventions, constraints, and hard-won debugging insights. Grouped by topic, newest first within each topic.

Use `/hv:learn` at the end of a session to capture new learnings. `/hv:work` consults this file when its topics are relevant to the task.
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
  },
  "learn": {
    "verify": false
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

## Step 3 — Install CLI Helpers

Copy the helpers from the hv-skills plugin `bin/` directory into `.hv/bin/`. Helpers are always refreshed — they're tools, not data.

Resolve the source `bin/` in this order, stopping at the first match:

1. **Plugin env var** — `$CLAUDE_PLUGIN_ROOT/bin/` (set by Claude Code when the skill runs from an installed plugin)
2. **Standard install locations** — glob these paths, first match wins:
   - `~/.claude/plugins/*/hv-skills/bin/`
   - `~/.claude/plugins/hv-skills/bin/`
   - `~/.agents/skills/hv-skills/bin/`
   - `~/.agents/skills/bin/`
3. **Repo-local clone** — if the skill is running from a cloned repo, `bin/` sits next to the `hv-init/` folder. Walk up from the skill directory.

Once resolved, copy and chmod:

```bash
SRC=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT/bin" ]; then
  SRC="$CLAUDE_PLUGIN_ROOT/bin"
else
  for candidate in \
    "$HOME"/.claude/plugins/*/hv-skills/bin \
    "$HOME"/.claude/plugins/hv-skills/bin \
    "$HOME"/.agents/skills/hv-skills/bin \
    "$HOME"/.agents/skills/bin; do
    [ -d "$candidate" ] && SRC="$candidate" && break
  done
fi
[ -z "$SRC" ] && { echo "error: could not locate hv-skills bin/ — set CLAUDE_PLUGIN_ROOT or install the plugin" >&2; exit 1; }
cp "$SRC"/hv-* .hv/bin/ && chmod +x .hv/bin/hv-*
```

All helpers are installed together. They require `python3`:

| Script | Purpose |
|--------|---------|
| `hv-next-id` | Increment counter, return zero-padded ID |
| `hv-append` | Append entry to a section in `TODO.md` |
| `hv-complete` | Move item to `## Completed` with strikethrough |
| `hv-guard-clean` | Exit non-zero if the git tree is dirty or not a repo |
| `hv-status-add` | Register an active work entry in `status.json` |
| `hv-status-remove` | Clear an active entry by branch name |
| `hv-archive-old` | Move `## Completed` items >N days old to `ARCHIVE.md` |
| `hv-knowledge-index` | Regenerate the managed `hv:knowledge` block in `CLAUDE.md` |
| `hv-reconcile` | Validate `status.json` vs git state, auto-clean stale entries |

## Step 4 — Seed CLAUDE.md Knowledge Block

Ensure `CLAUDE.md` in the project root contains a managed knowledge-index block. `/hv:learn` keeps this block in sync with `.hv/KNOWLEDGE.md` topics, and `/hv:work` reads it to know when to consult knowledge.

Delegate to the helper — it creates `CLAUDE.md` if missing, updates the block in place if present, or appends it if `CLAUDE.md` exists without a block:

```bash
.hv/bin/hv-knowledge-index
```

The helper never touches any other content in `CLAUDE.md`.

## Step 5 — Confirm

Tell the user:

```
Initialized .hv/ backlog:
  .hv/TODO.md         — bugs, features, tasks
  .hv/KNOWLEDGE.md    — durable learnings, grouped by topic
  .hv/counters.json   — auto-increment IDs
  .hv/config.json     — model, isolation, and merge settings
  .hv/status.json     — active work stream tracking
  .hv/bin/             — CLI helpers (hv-next-id, hv-append, hv-complete)
  .hv/bugs/            — overflow detail files for bug reports
  .hv/features/        — overflow detail files for feature specs
  .hv/tasks/           — overflow detail files for task descriptions
  CLAUDE.md            — managed knowledge-index block added
  .gitignore           — .hv/ excluded

Use /hv:capture to add bugs, features, or tasks.
Use /hv:learn to capture durable learnings at the end of a session.
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
- `learn.verify` — `false` (default, trust the writer) or `true` (dispatch an Opus verifier subagent to review new entries)
