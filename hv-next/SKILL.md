---
name: hv:next
description: Review the backlog, reconcile active work against git state, archive old completions, show sorted tables with relationship clusters, suggest the next item, and route to /hv:work. Use on "what should I work on", "pick up the next task", or when the user wants to see their backlog.
user-invocable: true
---

# hv:next — Pick & Work the Next Item

Review the project backlog, suggest what to tackle next, and execute it.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

Branch on exit code:
- `0` — continue.
- `2` (uninitialized) or helper absent — tell the user *"Nothing tracked yet — run `/hv:init` then `/hv:capture`."* and stop.
- `3` (partial install) — invoke `hv:init` via the `Skill` tool to refresh helpers, then continue.

See GUIDE.md § Preflight for details.

## Step 2 — Reconcile Active Work

```bash
.hv/bin/hv-reconcile
```

Validates `status.json` against git, auto-cleans stale entries (dead branches), nulls missing worktree paths, and emits JSON with two arrays:

- `cleaned` — removed silently. No output needed.
- `needsAction` — branch still exists. Fields: `branch`, `items`, `worktree`, `startedAt`, `hasCommits`, `commitCount`, `worktreeMissing`.

If `needsAction` is empty, produce no output and continue. Otherwise, use the `AskUserQuestion` tool so the user can resolve each stream with the host's native question UI. Batch up to 4 streams into one `AskUserQuestion` call; if there are more than 4, present the rest in a second call after the first resolves.

For each entry, build one question:

- **Header:** `"<branch>"` (truncate to 12 chars)
- **Question:** context line describing the stream. Examples:
  - `hasCommits: true` — *"[B01], [F03] look complete on `hv/timer-fix` (3 commits). What should I do?"*
  - `hasCommits: false` — *"[F07] is in progress on `hv/auth-refresh` (started 2026-04-18, no commits yet). What should I do?"*
  - Append *" (worktree was cleaned up)"* to the question if `worktreeMissing: true`.
- **Options** (single-select):
  - `hasCommits: true`:
    1. "Ship via `/hv:ship` (Recommended)" — *"Run `/hv:ship` on the branch — runs review, then merges or opens a PR."*
    2. "Resume with `/hv:work`" — *"Keep adding to the branch."*
    3. "Leave as-is" — *"No action now; stream stays in `status.json`."*
  - `hasCommits: false`:
    1. "Resume with `/hv:work` (Recommended)" — *"Pick up where it left off."*
    2. "Abandon" — *"Delete the branch and clear `status.json`."*
    3. "Leave as-is" — *"No action now; stream stays in `status.json`."*

Route each resolution:

| Answer | Action |
|--------|--------|
| Ship via `/hv:ship` | Invoke `hv:ship` via the `Skill` tool with this branch |
| Resume with `/hv:work` | Invoke `hv:work` on the existing branch |
| Abandon | `git branch -D <branch>` then `.hv/bin/hv-status-remove <branch>` |
| Leave as-is | Print *"Skipped `<branch>` — still in `status.json`."* and continue |

If `AskUserQuestion` is unavailable on the host, fall back to the plain-text prompts: *"Merge or open a PR?"* and *"Resume or abandon?"* — honor the user's free-text reply.

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

Use the `AskUserQuestion` tool so the user picks with the host's native UI. Build a single question:

- **Header:** `"Next"`
- **Question:** *"Work on the suggested item(s)?"* (substitute "items" for a batch)
- **Options** (single-select):
  1. `"Start [ID] (Recommended)"` — *"Invoke `/hv:work` with the suggested item(s) and their TODO descriptions."* (list IDs in the label if it's a batch, else the single ID)
  2. `"Pick different items"` — *"Choose from the backlog yourself."*
  3. `"Stop here"` — *"No execution now; just leave me with the backlog view."*

Route the answer:

| Answer | Action |
|--------|--------|
| Start (Recommended) | Invoke `hv:work` via the `Skill` tool with the selected items + their TODO entries |
| Pick different items | Second `AskUserQuestion` call with a `multiSelect: true` question listing up to 4 alternative items (or ask the user to name them if the backlog has more than 4). Then invoke `hv:work` on the chosen set |
| Stop here | Print *"OK — run `/hv:next` again when you're ready."* and exit |
| "Other" (free text) | Treat the user's text as the item spec; route to `/hv:work` |

If `AskUserQuestion` isn't available on the host, fall back to plain-text: *"Work on this?"* and honor yes/no/"pick specific IDs" replies.

## Rules

- **No noise** — never report on a step that found nothing. Silence is signal.
- **Pass full context to /hv:work** — include TODO.md descriptions so work doesn't re-read.
- **Reference items by ID** — `[B01]`, `[F03]`, `[T02]` in suggestions and messages.
- **Git is the source of truth** — if `status.json` disagrees with git state, trust git.
