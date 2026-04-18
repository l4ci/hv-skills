# hv-skills Guide

A detailed guide to the hv-skills workflow system for Claude Code.

## Overview

hv-skills is a lightweight project backlog and execution system. It lives entirely in a `.hv/` folder inside your project (gitignored) and uses Claude Code skills to capture work items, prioritize them, execute them with parallel subagents, and carry durable learnings forward.

The workflow is: **capture → prioritize → execute → learn → refactor**.

## The .hv/ Folder

Run `/hv:init` once per project to create the folder. It contains:

| File | Purpose |
|------|---------|
| `TODO.md` | Active backlog — bugs, features, tasks, and recent completions |
| `KNOWLEDGE.md` | Durable learnings grouped by topic — gotchas, conventions, constraints |
| `counters.json` | Auto-incrementing IDs for each item type |
| `config.json` | Model selection, isolation mode, merge strategy, refactor and learn settings |
| `status.json` | Active work streams — which items are being worked on, on which branch/worktree |
| `bin/` | CLI helpers — `hv-next-id`, `hv-append`, `hv-complete` |
| `bugs/` | Overflow detail files for large bug reports |
| `features/` | Overflow detail files for large feature specs |
| `tasks/` | Overflow detail files for large task descriptions |
| `ARCHIVE.md` | Completed items older than 5 days, moved here automatically |

`/hv:init` also adds a managed block to `CLAUDE.md` at the project root that lists the current `KNOWLEDGE.md` topics. `/hv:work` reads this index to know when to consult `KNOWLEDGE.md`.

All files are gitignored. The backlog is local to your machine.

## Skills Reference

### /hv:init

Creates the `.hv/` folder with all required files. Safe to run multiple times — never overwrites existing files. Also adds `.hv/` to `.gitignore` if not already present.

### /hv:capture

Single entry point for capturing all work items. Automatically classifies each item as a bug, feature, or task and routes it to the correct section in `TODO.md`. Asks 2-4 quick questions to gather context, assigns priority (P0/P1/P2) for bugs and size (Major/Minor/Cosmetic) for features. Tasks get no tag.

Each item gets a zero-padded auto-incrementing ID — `[B01]` for bugs, `[F01]` for features, `[T01]` for tasks. Scans existing items (including the archive) for related entries and links them. Handles mixed input naturally — mention a bug, a feature, and a task in the same message and all three get captured with the correct ID type and section. Large input overflows into detail files at `.hv/bugs/B{NN}.md`, `.hv/features/F{NN}.md`, or `.hv/tasks/T{NN}.md`.

### /hv:c

Shortcut alias for `/hv:capture`. Identical behavior — useful when capturing is frequent and you want the keystroke savings.

### /hv:go

Capture + execute in one pass. The item still gets written to `TODO.md` with a real ID (counters increment, detail files land where needed, history is preserved), but the normal `/hv:next` review round-trip is skipped — `/hv:go` hands directly off to `/hv:work` after capture completes.

**Flow:** clean-tree guard → capture via `/hv:capture` → work via `/hv:work`.

**When to use:**
- You describe a fix and want it done now, not queued — *"fix the off-by-one in RingBuffer"*, *"add a Cmd+K shortcut to the project picker"*
- Hot-path work: you spot a bug during a session and want to resolve it on the spot

**When NOT to use:**
- Brainstorming or dumping ideas → use `/hv:capture`
- Picking from an existing backlog → use `/hv:next`
- Multiple unrelated items that need prioritization → `/hv:capture` first, then `/hv:next`

`/hv:go` inherits all `/hv:capture` rules (classification, detail-file overflow, ID assignment) and all `/hv:work` rules (branch/worktree isolation, parallel workers, per-task commits). The only difference is that it suppresses both the capture confirmation prompt and the backlog selection step — one invocation, one pass.

### /hv:learn

Distills durable knowledge from the current session into `.hv/KNOWLEDGE.md`, grouped by topic. A learning is worth capturing if it would save a future `/hv:work` run from re-discovering it.

**What gets captured** — gotchas (non-obvious failure modes), conventions (project-specific patterns that aren't obvious from reading code), constraints (invariants, compatibility rules), debugging insights (root causes for hard-won bugs), decisions with rationale, and tool quirks.

**What doesn't** — things already documented in code or README, transient session state, obvious facts derivable from the codebase, restatements of framework docs, personal preferences.

Entries are grouped by short topic headings (`Build & Tooling`, `Testing`, `Networking`, etc.) with newest bullets at the top of each topic. New entries carry an HTML-comment date stamp: `<!-- YYYY-MM-DD -->`.

After writing, `/hv:learn` updates the managed `hv:knowledge` block in `CLAUDE.md` so its topic list matches the current `KNOWLEDGE.md` headings. `/hv:work` reads this index to know when the task at hand should consult `KNOWLEDGE.md`.

**Verification (opt-in).** By default, the skill writes and reports. If `learn.verify` is set to `true` in `.hv/config.json`, it dispatches an Opus verifier subagent that reads the updated files with fresh eyes and judges whether the new entries are durable, sharp, non-obvious, correctly topic'd, and non-duplicated. Use this if you want a second-opinion pass before learnings become part of your project's long-term context.

### /hv:next

Reviews the backlog and suggests what to work on. Does several things before presenting the table:

1. **Reconciles active work** — reads `status.json` and validates against git state. Detects completed branches that were never merged, interrupted work that can be resumed, and stale entries that need cleanup.
2. **Archives old completions** — moves items completed more than 5 days ago from `TODO.md` to `ARCHIVE.md`.
3. **Builds a relationship map** — finds `Related:` links across all items and identifies clusters of connected work.
4. **Presents the backlog** — tables sorted by priority/size, with a Related column and cluster notes.
5. **Suggests next work** — P0 bugs first, then clusters with blocking bugs, quick wins, P1 bugs, blocking tasks, features.
6. **Routes to /hv:work** — after the user confirms.

### /hv:work

Executes a batch of work items with parallel subagents. The orchestrator (default: opus) plans the tasks, the workers (default: sonnet) implement them.

**Isolation modes** (configured in `config.json`):

- `"branch"` (default) — creates a feature branch in the current worktree. Simple, works everywhere.
- `"worktree"` — creates an isolated git worktree under `.claude/worktrees/`. The orchestrator stays in the main worktree (retaining access to `.hv/`), while sub-agents work in the worktree. This lets you keep working on main while agents execute, and supports running multiple `/hv:work` sessions in parallel on different item batches.

**Merge strategies** (configured in `config.json`):

- `"direct"` (default) — merges the branch into main with `--no-ff` after all verification passes, then deletes the branch.
- `"pr"` — pushes the branch and creates a GitHub PR with a summary of items resolved and a test plan. The branch stays open for review.

**Safety**: refuses to start on a dirty working tree. Stash or commit first.

**Status tracking**: registers in `status.json` at the start, removes the entry on completion. This lets `/hv:next` in another session see what's in progress and avoid suggesting the same items.

### /hv:refactor

Runs a full architectural refactor cycle. The orchestrator explores the codebase for friction, categorizes each finding by dependency type, classifies it as simple or structural, and then fixes everything.

**For structural changes** (module boundary reshaping, concept consolidation), it spawns 3-4 parallel design agents with competing constraints (minimal interface, maximum flexibility, caller-optimized, ports & adapters), compares the results, and recommends the strongest approach.

**User checkpoints** (configurable): when `confirmBeforeExecute` is `true` (default), pauses after presenting findings and after design selection so the user can steer. Set `false` for full autonomy.

**Safety**: refuses to start on a dirty working tree.

## Configuration

All settings live in `.hv/config.json`. Edit it directly — no special command needed.

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
  },
  "learn": {
    "verify": false
  }
}
```

### Model choices

| Value | Best for |
|-------|----------|
| `"opus"` | Deep reasoning — planning, exploration, verification, design |
| `"sonnet"` | Fast execution — implementing well-specified tasks |
| `"haiku"` | Quick, cheap — simple fixes, small tasks |

### Isolation modes

| Mode | How it works | When to use |
|------|-------------|-------------|
| `"branch"` | Feature branch in current worktree | Solo work, simple workflows |
| `"worktree"` | Isolated directory under `.claude/worktrees/` | Parallel work streams, keep main clean while agents work |

### Merge strategies

| Strategy | How it works | When to use |
|----------|-------------|-------------|
| `"direct"` | Merge to main, delete branch | Solo work, fast iteration |
| `"pr"` | Push branch, create GitHub PR | Team work, code review required |

### Learn verification

| Value | Behavior |
|-------|----------|
| `false` (default) | `/hv:learn` writes entries and reports. Fast, cheap. |
| `true` | After writing, dispatches an Opus verifier subagent for a cold review pass. Flags weak, duplicate, or wrong-topic entries. Adds cost and latency. |

## CLI Helpers

`/hv:init` installs bash scripts to `.hv/bin/` that collapse multi-step agent logic into a single call. Each helper is small, idempotent, and `python3`-based where JSON parsing is needed.

| Script | What it does | Example |
|--------|-------------|---------|
| `hv-next-id` | Increment counter, return zero-padded ID | `.hv/bin/hv-next-id bugs` → `B07` |
| `hv-append` | Append entry to a section in TODO.md | `.hv/bin/hv-append "## Bugs" "- **[B07] [P1] Title.** Desc."` |
| `hv-complete` | Move item to `## Completed` with strikethrough | `.hv/bin/hv-complete B07 a1b2c3d` |
| `hv-guard-clean` | Exit non-zero if git tree is dirty or not a repo | `.hv/bin/hv-guard-clean /hv:work` |
| `hv-status-add` | Register an active work entry (idempotent on branch) | `.hv/bin/hv-status-add hv/foo B01,F02 .claude/worktrees/hv-foo` |
| `hv-status-remove` | Clear an active entry by branch | `.hv/bin/hv-status-remove hv/foo` |
| `hv-archive-old` | Move `## Completed` items older than N days to `ARCHIVE.md` | `.hv/bin/hv-archive-old 5` |
| `hv-knowledge-index` | Regenerate the managed `hv:knowledge` block in `CLAUDE.md` | `.hv/bin/hv-knowledge-index` |
| `hv-reconcile` | Validate `status.json` vs git, auto-clean stale entries, emit JSON | `.hv/bin/hv-reconcile` |

All helpers are refreshed every time `/hv:init` runs. Data files (`TODO.md`, `counters.json`, etc.) are never overwritten.

### Why helpers matter

Every skill step that would otherwise chain several tool calls (read file → compute → write file, or run several `git` queries and parse them) becomes one subprocess with structured output. This reduces context token consumption on each invocation and keeps the SKILL.md files focused on *what* to do rather than *how* to parse JSON or regex Markdown.

### Resolving the source bin/

`/hv:init` copies helpers from the installed plugin, trying these paths in order:

1. `$CLAUDE_PLUGIN_ROOT/bin/` — set by Claude Code when the skill runs from an installed plugin
2. `~/.claude/plugins/*/hv-skills/bin/`, `~/.claude/plugins/hv-skills/bin/` — standard plugin install locations
3. `~/.agents/skills/hv-skills/bin/`, `~/.agents/skills/bin/` — stow-based install locations
4. Repo-local `bin/` if the skill is running from a cloned repo

If none of these resolve, `/hv:init` exits with a clear error. The scripts themselves are verified by `test/smoke.sh` in the repo — run it if you suspect a helper is misbehaving.

## Mixed-Input Routing

`/hv:capture` handles mixed input. If you mention a bug, a feature, and a task in the same message, the skill splits them into distinct items and routes each to the correct section with the correct ID type.

For example, telling `/hv:capture` *"the sidebar flickers on hover, also we should add keyboard shortcuts, and update the linter config"* produces:

```markdown
## Bugs
- **[B03] [P2] Sidebar flickers on hover.** ...

## Features
- **[F04] [Minor] Keyboard shortcuts for top actions.** ...

## Tasks
- **[T06] Update linter config for new rules.** ...
```

Items created in the same batch can reference each other with `Related:` links.

## Detail Files

When an item's input is too large for a TODO entry (crash dumps, specs, logs, checklists), `/hv:capture` creates a detail file in a subdirectory:

| Type | Directory | Example |
|------|-----------|---------|
| Bug | `.hv/bugs/` | `.hv/bugs/B07.md` |
| Feature | `.hv/features/` | `.hv/features/F08.md` |
| Task | `.hv/tasks/` | `.hv/tasks/T09.md` |

The TODO.md entry gets a `Detail:` reference pointing to the file:

```markdown
- **[B07] [P0] App crashes on launch after iOS 18.2 update.** EXC_BAD_ACCESS in CoreData stack during migration. Detail: `.hv/bugs/B07.md` Related: [F12]
```

Most entries won't need a detail file — they're only created when the input would bloat the TODO entry beyond a few sentences.

## Related Items

Any item can link to other items with a `Related:` suffix:

```markdown
- **[B05] [P1] Timer badge stale after pause.** Description... Related: [F03]
```

Links are optional and bidirectional — `/hv:next` infers the reverse link automatically. When linked items form clusters, `/hv:next` suggests tackling them together.

`/hv:capture` scans both `TODO.md` and `ARCHIVE.md` for connections, so a new bug can link to a completed feature.

## Concurrent Work Streams

With `"isolation": "worktree"`, you can run multiple `/hv:work` sessions in parallel from separate terminals:

```
Terminal 1: /hv:next → picks [F01], [B02] → /hv:work
Terminal 2: /hv:next → picks [F03]        → /hv:work
```

Each session creates its own worktree and branch. Both orchestrators write to the same `.hv/status.json` in the main worktree (they own different entries, so no conflicts). `/hv:next` in a third terminal will show both work streams as "In Progress" and skip those items when suggesting new work.

## State Tracking

`status.json` is a cache for speed. **Git is the source of truth.**

`/hv:next` always validates `status.json` against actual git state:
- Branches that exist → work is in progress or ready to merge
- Branches that were deleted → stale status entries, cleaned up automatically
- Worktrees that exist → active parallel work stream
- Worktrees that were removed → entry updated or cleaned up

If `status.json` ever gets out of sync (crashed session, manual git operations), `/hv:next` repairs it by checking `git branch` and `git worktree list`.

**Concurrency caveat**: `status.json` writes are not file-locked. If you run `/hv:next` while `/hv:work` is mid-update in another terminal, the last writer wins. In practice this is harmless — git state is the source of truth and the next `/hv:next` run will reconcile any drift — but avoid running both simultaneously against the same project if you want clean output.
