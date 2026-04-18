---
name: hv:next
description: Review the backlog, reconcile active work against git state, archive old completions, show sorted tables with relationship clusters, suggest the next item, and route to /hv:work. Use on "what should I work on", "pick up the next task", or when the user wants to see their backlog.
user-invocable: true
---

# hv:next — Pick & Work the Next Item

Review the project backlog, suggest what to tackle next, and execute it.

## Step 1 — Read State

If `.hv/TODO.md` is missing, tell the user nothing is tracked yet and suggest `/hv:init` then `/hv:capture`. If `TODO.md` exists but `.hv/bin/hv-next-id` doesn't, run `/hv:init` to refresh helpers.

## Step 2 — Reconcile Active Work

```bash
.hv/bin/hv-reconcile
```

Validates `status.json` against git, auto-cleans stale entries (dead branches), nulls missing worktree paths, and emits JSON with two arrays:

- `cleaned` — removed silently. No output needed.
- `needsAction` — branch still exists. Fields: `branch`, `items`, `worktree`, `startedAt`, `hasCommits`, `commitCount`, `worktreeMissing`.

For each `needsAction` entry, present one line before the backlog:

- `hasCommits: true` → *"[items] look complete on `<branch>` (<commitCount> commits). Merge or open a PR?"*
- `hasCommits: false` → *"[items] in progress on `<branch>` (started <startedAt>). Resume or abandon?"*
- Append *"(worktree was cleaned up)"* if `worktreeMissing: true`.

Resume → `/hv:work` on the existing branch. Abandon → `git branch -D <branch>` then `.hv/bin/hv-status-remove <branch>`.

If `needsAction` is empty, produce no output.

## Step 3 — Archive Completed Items

```bash
.hv/bin/hv-archive-old 5
```

Moves `## Completed` items older than 5 days to `ARCHIVE.md`. Silent — don't report the count.

## Step 4 — Build Relationship Map

Scan all items in `## Bugs`, `## Features`, `## Tasks` for `Related: [B01], [F02]` suffixes. Build a bidirectional map — if B03 lists `Related: [F02]`, F02 is also related to B03.

Identify **clusters**: groups of 2+ connected items. These inform Step 6.

## Step 5 — Present the Backlog

```bash
.hv/bin/hv-backlog
```

Prints pre-sorted markdown tables: "In Progress" (active items from `status.json`), "Bugs" (P0→P2), "Features" (Cosmetic→Major), "Tasks". Empty sections are omitted. If the backlog is empty, the helper prints a placeholder — pass it through and stop.

Pass the helper's output through to the user verbatim. Then, if clusters exist from Step 4, add a brief note after the tables:

```
Clusters:
  [F03] ↔ [B02] — fix the badge bug before or alongside the feature
  [T01] → [F04] — toolchain update unblocks the feature
```

If no clusters exist, omit the section entirely.

## Step 6 — Suggest Next

Recommend using this priority order:

1. P0 bugs first — they block usage
2. Clusters with blocking bugs — fix bugs first or tackle the cluster together
3. Quick wins — Cosmetic features or P2 bugs; bundle 2–3 if small
4. Highest-impact P1 bugs
5. Blocking tasks (check `Related:` links)
6. Minor features — default when no urgent bugs
7. Major features — only if nothing else is pending or the user asks

Skip items already active. Present:

```
Suggested next: [ID] [Title] ([tag])
[Why this one — 1 sentence]
```

## Step 7 — Confirm & Execute

Ask: **"Work on this?"** (or "Work on these?" for a batch).

- **Yes** → invoke `/hv:work` with the selected item(s) and their TODO.md descriptions as context
- **No** → ask for an alternative, then route that to `/hv:work`
- **User picks specific items** → route those to `/hv:work`

## Rules

- **No noise** — never report on a step that found nothing. Silence is signal.
- **Pass full context to /hv:work** — include TODO.md descriptions so work doesn't re-read.
- **Reference items by ID** — `[B01]`, `[F03]`, `[T02]` in suggestions and messages.
- **Git is the source of truth** — if `status.json` disagrees with git state, trust git.
