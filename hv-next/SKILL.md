---
name: hv:next
description: Review all items in TODO.md, reconcile active work from status.json and git state, archive old completed items, show a backlog table with relationship clusters, suggest the next thing to work on, and route to /hv:work for implementation. Use when the user wants to pick up the next task, asks "what should I work on", or wants to see their backlog.
user-invocable: true
---

# hv:next — Pick & Work the Next Item

Review the project backlog, suggest what to tackle next, and execute it.

## Step 1 — Read State

Check if `.hv/TODO.md` exists. If not, tell the user there's nothing tracked yet and suggest running `/hv:init` to set up, then `/hv:capture` to add items. If `.hv/TODO.md` exists but `.hv/bin/hv-next-id` doesn't, run `/hv:init` to refresh helpers.

Read `.hv/TODO.md` and `.hv/status.json` (if it exists).

## Step 2 — Reconcile Active Work

Delegate to the helper — it validates `status.json` against git, auto-cleans stale entries (dead branches), nulls missing worktree paths, and emits JSON:

```bash
.hv/bin/hv-reconcile
```

Parse the JSON. Two arrays:

- `cleaned` — entries removed silently. No output needed.
- `needsAction` — entries where the branch still exists. Fields: `branch`, `items`, `worktree`, `startedAt`, `hasCommits`, `commitCount`, `worktreeMissing`.

For each `needsAction` entry, present one line before the backlog:

- **`hasCommits: true`** → *"[items] look complete on `<branch>` (<commitCount> commits). Merge or open a PR?"*
- **`hasCommits: false`** → *"[items] in progress on `<branch>` (started <startedAt>). Resume or abandon?"*
- Append *"(worktree was cleaned up)"* if `worktreeMissing: true`.

Resume routes to `/hv:work` on the existing branch. Abandon = `git branch -D <branch>` then `.hv/bin/hv-status-remove <branch>`.

If `needsAction` is empty, produce no output.

## Step 3 — Archive Completed Items

Delegate:

```bash
.hv/bin/hv-archive-old 5
```

Prints the count of items moved (or nothing). Archive silently — don't report the count to the user.

## Step 4 — Build Relationship Map

Scan all items in `## Bugs`, `## Features`, and `## Tasks` for `Related: [B01], [F02]` suffixes. Build a bidirectional relationship map — if B03 lists `Related: [F02]`, then F02 is also related to B03, even if F02 doesn't have an explicit `Related:` suffix.

Identify **clusters**: groups of 2+ items that are connected (directly or transitively). These clusters inform the suggestion in Step 6.

## Step 5 — Present the Backlog

Render a table for each non-empty section. Exclude items that are currently active (present in `status.json`) — show them separately as "In Progress" instead.

**If any items are active**, show them first:

### In Progress

| ID | Title | Branch | Started |
|----|-------|--------|---------|
| F01 | Quick-switch projects | hv/quick-switch | 2026-04-15 |

### Bugs

| ID | Prio | Title | Related |
|----|------|-------|---------|
| B01 | P0 | Crash on launch | |
| B02 | P1 | Stale badge | F03 |

Sort by priority: P0 first, then P1, then P2. Flag P0 items with a note that they're urgent.

### Features

| ID | Size | Title | Related |
|----|------|-------|---------|
| F03 | Minor | Quick-switch projects | B02 |

Sort by size: Cosmetic first (quick wins), then Minor, then Major.

### Tasks

| ID | Title | Related |
|----|-------|---------|
| T01 | Update Swift toolchain | F04 |

The **Related** column shows IDs from the relationship map (both explicit and inferred). Leave it empty when the item has no links.

If clusters exist, add a brief note after the tables:

```
Clusters:
  [F03] ↔ [B02] — fix the badge bug before or alongside the feature
  [T01] → [F04] — toolchain update unblocks the feature
```

If no clusters exist, omit the clusters section entirely — don't mention their absence.

If all sections are empty, say so and suggest `/hv:capture`.

## Step 6 — Suggest Next

Recommend what to work on next using this logic:

1. **Any P0 bug?** → Always suggest P0 bugs first, they block usage
2. **Cluster with blocking bugs?** → If a feature has related bugs, suggest fixing the bugs first or tackling the cluster together
3. **Quick win available?** → If there's a Cosmetic feature or P2 bug that takes minutes, suggest bundling 2–3 of them together
4. **Highest-impact P1 bug** → Bugs that degrade daily experience
5. **Blocking tasks** → Chores that unblock other items (check `Related:` links)
6. **Minor features** → Good default when no urgent bugs
7. **Major features** → Only suggest if nothing else is pending, or the user specifically wants to tackle something big

Skip items that are already active in another work stream.

When suggesting a cluster, present it as a batch: *"These are related — tackle them together?"*

Present your recommendation clearly:

```
Suggested next: [ID] [Title] ([tag])
[Why this one — 1 sentence]
```

If there are 2–3 small items that make sense together, suggest them as a batch.

## Step 7 — Confirm & Execute

Ask the user: **"Work on this?"** (or "Work on these?" for a batch)

- If **yes** → invoke the `/hv:work` skill with the selected item(s) as the task description. Include the full context from TODO.md so the work skill has everything it needs.
- If **no** → ask what they'd prefer to work on instead, then route that to `/hv:work`.
- If the user picks something specific from the list (by ID or title) → route that to `/hv:work`.

## Rules

- **No noise** — never report on a step that found nothing. "No active work", "nothing to archive", "no clusters" are all zero-information messages. Skip them silently. The user sees the backlog table and the suggestion — that's the output.
- **Always reconcile before presenting** — check status.json and git state first
- **Always render the table** — the table is the default view, not optional
- **Don't auto-start work** — always confirm with the user first
- **Respect the user's choice** — your suggestion is a recommendation, not a mandate
- **Pass full context to /hv:work** — include the TODO.md description so the work skill doesn't need to re-read it
- **Reference items by ID** — use `[B01]`, `[F03]`, `[T02]` in suggestions and when talking about items
- **Git is the source of truth** — if status.json disagrees with git state, trust git and fix status.json
