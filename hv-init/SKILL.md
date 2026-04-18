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

[ -f "$HV/status.json" ] || echo '{"active":[]}' > "$HV/status.json"

if [ -f .gitignore ]; then
  grep -qxF '.hv/' .gitignore 2>/dev/null || printf '\n# ── hv backlog ──\n.hv/\n' >> .gitignore
else
  printf '# ── hv backlog ──\n.hv/\n' > .gitignore
fi
```

Data files are never overwritten if they already exist. `config.json` is created interactively in Step 3.

## Step 3 — Configure (Interactive)

If `.hv/config.json` already exists, skip this entire step — the user's prior config is the source of truth.

Otherwise, use the `AskUserQuestion` tool to gather the four most impactful choices in a single turn. The "(Recommended)" option on each is the existing default; selecting it (or "Other" with no alternative) writes the default value. The user can decline the whole thing with the native "skip" — if that happens, write all defaults and continue.

Call `AskUserQuestion` with these four questions in one call:

**Q1 — Models** (`header: "Models"`, single-select)

> *"Which model profile should hv-skills use for orchestration and implementation?"*

| Label | Description |
|-------|-------------|
| Balanced — Opus + Sonnet (Recommended) | Opus plans and verifies, Sonnet executes. Strong reasoning where it matters; fast execution elsewhere. |
| Premium — Opus only | Opus for everything. Highest quality, highest cost. Pick when correctness dominates. |
| Fast — Sonnet only | Sonnet for both roles. Faster and cheaper; fine for well-specified tasks. |
| Minimal — Sonnet + Haiku | Sonnet plans, Haiku executes. Cheapest. Best for mechanical, low-risk work. |

**Q2 — Isolation** (`header: "Isolation"`, single-select)

> *"How should `/hv:work` isolate changes from main?"*

| Label | Description |
|-------|-------------|
| Branch (Recommended) | Feature branch in the current worktree. Simple, works everywhere. |
| Worktree | Isolated directory under `.claude/worktrees/`. Lets you keep using main while agents work; supports parallel sessions. |

**Q3 — Integration** (`header: "Integration"`, single-select)

> *"How should `/hv:work` and `/hv:ship` integrate finished work?"*

| Label | Description |
|-------|-------------|
| Direct merge (Recommended) | Merge into main with `--no-ff` and delete the branch. Fast solo iteration. |
| GitHub PR | Push the branch and open a PR with `gh pr create`. Required for team review. |

**Q4 — Quality gates** (`header: "Gates"`, `multiSelect: true`)

> *"Which quality gates should run by default? (Uncheck anything you want off.)"*

| Label | Description |
|-------|-------------|
| Review before ship (Recommended) | `/hv:ship` runs `/hv:review` first. FAIL blocks, CONCERNS ask, PASS flows through. |
| Verify learnings (Recommended) | `/hv:learn` dispatches an Opus verifier for a cold pass on new entries. Knowledge quality compounds. |
| Confirm before refactor (Recommended) | `/hv:refactor` pauses for approval after finding friction and after selecting a design. Off = full autonomy. |

Map answers to config values:

| Answer | Config |
|--------|--------|
| Q1 Balanced | `models: {orchestrator: "opus", worker: "sonnet"}` |
| Q1 Premium | `models: {orchestrator: "opus", worker: "opus"}` |
| Q1 Fast | `models: {orchestrator: "sonnet", worker: "sonnet"}` |
| Q1 Minimal | `models: {orchestrator: "sonnet", worker: "haiku"}` |
| Q2 Branch | `work.isolation: "branch"` |
| Q2 Worktree | `work.isolation: "worktree"` |
| Q3 Direct merge | `work.mergeStrategy: "direct"` |
| Q3 GitHub PR | `work.mergeStrategy: "pr"` |
| Q4 includes "Review before ship" | `ship.review: true` (else `false`) |
| Q4 includes "Verify learnings" | `learn.verify: true` (else `false`) |
| Q4 includes "Confirm before refactor" | `refactor.confirmBeforeExecute: true` (else `false`) |

If the user picked "Other" with custom text, honor it only if it's a valid value for that key (`"opus"/"sonnet"/"haiku"`, `"branch"/"worktree"`, `"direct"/"pr"`); otherwise silently fall back to the Recommended value.

If `AskUserQuestion` is unavailable on the current platform (Gemini CLI, Copilot CLI with no equivalent, or tool call fails), write the defaults straight through — don't stall the init on a missing tool.

Write the resolved config:

```bash
python3 - <<PY
import json
from pathlib import Path
Path(".hv/config.json").write_text(json.dumps({
  "models":   {"orchestrator": "<Q1-orchestrator>", "worker": "<Q1-worker>"},
  "work":     {"isolation": "<Q2>", "mergeStrategy": "<Q3>"},
  "refactor": {"confirmBeforeExecute": <Q4-refactor>},
  "learn":    {"verify": <Q4-learn>},
  "ship":     {"review": <Q4-ship>}
}, indent=2) + "\n")
PY
```

Briefly confirm the chosen profile in the Step 6 summary; users who picked all Recommended should just see *"Config: defaults."* — no itemization.

## Step 4 — Install CLI Helpers

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

All helpers are installed together and require `python3`. See `GUIDE.md` § CLI Helpers for the full reference of what each one does.

## Step 5 — Seed CLAUDE.md Knowledge Block

Ensure `CLAUDE.md` in the project root contains a managed knowledge-index block. `/hv:learn` keeps this block in sync with `.hv/KNOWLEDGE.md` topics, and `/hv:work` reads it to know when to consult knowledge.

Delegate to the helper — it creates `CLAUDE.md` if missing, updates the block in place if present, or appends it if `CLAUDE.md` exists without a block:

```bash
.hv/bin/hv-knowledge-index
```

The helper never touches any other content in `CLAUDE.md`.

## Step 6 — Confirm

Tell the user one compact block:

```
Initialized .hv/ in <project>.
Config: <summary — "defaults" if all Recommended, else a one-liner e.g. "Balanced models, worktree isolation, PR merges, verifier on">.
Next: /hv:capture to add items, /hv:next to pick work, /hv:learn to save learnings.
Edit .hv/config.json to change any of these later.
```

If `.hv/TODO.md` already existed, say it was already initialized and helper scripts were refreshed — skip the config line (nothing was asked).

Config keys: `models.{orchestrator,worker}`, `work.{isolation,mergeStrategy}`, `refactor.confirmBeforeExecute`, `learn.verify`, `ship.review`. See `GUIDE.md` for full reference.
