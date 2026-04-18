# hv-skills

A lightweight project backlog and workflow system for Claude Code. Capture bugs, features, and tasks into a per-project `.hv/` folder, pick items off the backlog, execute them with parallel subagents, and carry durable learnings forward.

[How to use](#how-to-use) · [Install](#install) · [Full guide](GUIDE.md)

## Skills

| Skill | Description |
|-------|-------------|
| `/hv:init` | Initialize `.hv/` folder with `TODO.md`, `KNOWLEDGE.md`, `counters.json`, `config.json`, `status.json`, and a managed knowledge-index block in `CLAUDE.md` |
| `/hv:capture` | Capture bugs, features, and tasks — auto-classifies, assigns priority/size, routes to the correct section |
| `/hv:c` | Shortcut for `/hv:capture` |
| `/hv:go` | Capture an item and immediately implement it — combines `/hv:capture` and `/hv:work` in one pass |
| `/hv:learn` | Extract durable learnings from the current session into `.hv/KNOWLEDGE.md`, grouped by topic; updates the `CLAUDE.md` topic index. Opus verification is opt-in via `config.json` |
| `/hv:next` | Review backlog, reconcile active work against git state, suggest what to work on, route to `/hv:work` |
| `/hv:work` | Orchestrated parallel implementation with per-task commits; consults `.hv/KNOWLEDGE.md` for relevant learnings |
| `/hv:refactor` | Full architectural refactor cycle with parallel subagents |

## How to use

**1. Initialize once per project**

Run `/hv:init` in your project root. This creates `.hv/` with a TODO file, knowledge file, counters, model config, status tracking, and CLI helpers that keep tool calls minimal.

**2. Capture work as you go**

Whenever you spot something, capture it without breaking your flow — just run `/hv:capture` (or the shorter `/hv:c`). It auto-classifies each item as a bug, feature, or task and routes it to the correct section:

- **Bugs** — broken behavior, defects, regressions → `[B01]` with priority (P0/P1/P2)
- **Features** — ideas, enhancements, new capabilities → `[F01]` with size (Major/Minor/Cosmetic)
- **Tasks** — chores, refactoring, docs, dependency updates → `[T01]`

Mixed input works naturally — mention a bug and a feature in the same message and both get captured. Large input (crash dumps, specs, logs) overflows into detail files under `.hv/bugs/`, `.hv/features/`, or `.hv/tasks/`.

**3. Pick what to work on**

Run `/hv:next` to review the backlog. It reconciles active work against git state, cleans up completed entries, shows a priority table, and suggests what to tackle next.

**4. Build it**

Run `/hv:work` to implement the selected items. It plans the tasks, dispatches parallel subagents, verifies each result, and commits per task. If you paused mid-work, `/hv:work` picks up where you left off.

**Shortcut: `/hv:go`** — if you want to describe something and have it done right now (no backlog round-trip), run `/hv:go fix the timer bug`. It captures the item with a proper ID, then immediately hands off to `/hv:work`. Useful for hot-path fixes you don't want to queue.

**5. Capture learnings**

At the end of a productive session, run `/hv:learn`. It distills durable gotchas, conventions, and constraints into `.hv/KNOWLEDGE.md`, grouped by topic. Future `/hv:work` runs consult this file when the task touches a relevant topic, so nothing gets re-discovered. Opus verification is opt-in — enable it in `config.json` if you want a second-opinion pass.

**6. Refactor periodically**

After a few rounds of feature work, run `/hv:refactor` to clean up accumulated friction. It explores the codebase, categorizes findings, designs competing approaches for structural changes, and fixes everything in one pass.

## Install

### npx (one-liner)

```bash
npx @anthropic-ai/claude-code plugin marketplace add l4ci/hv-skills
npx @anthropic-ai/claude-code plugin install hv-skills
```

### Claude Code CLI

If you already have Claude Code installed:

```bash
claude plugin marketplace add l4ci/hv-skills
claude plugin install hv-skills
```

### Local development (GNU Stow)

Clone the repo and use `stow` to symlink all skills into `~/.agents/skills/`:

```bash
git clone https://github.com/l4ci/hv-skills.git ~/Code/hv-skills
stow --dir="$HOME/Code" --target="$HOME/.agents/skills" hv-skills
```

To remove the symlinks:

```bash
stow --dir="$HOME/Code" --target="$HOME/.agents/skills" -D hv-skills
```

## Testing

Smoke-test the CLI helpers without touching your project:

```bash
bash test/smoke.sh
```

This creates a throwaway `.hv/` in a tmpdir, exercises `hv-next-id`, `hv-append`, and `hv-complete`, and asserts the expected state. Exits non-zero on any failure.
