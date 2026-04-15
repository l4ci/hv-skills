---
name: hv:next
description: Review all items in TODO.md, clean up old completed entries, show a backlog table, suggest the next thing to work on, and route to /hv:work for implementation. Use when the user wants to pick up the next task, asks "what should I work on", or wants to see their backlog.
user-invocable: true
---

# hv:next — Pick & Work the Next Item

Review the project backlog, suggest what to tackle next, and execute it.

## Step 1 — Read TODO.md

Check if `.hv/TODO.md` exists. If not, tell the user there's nothing tracked yet and suggest running `/hv:init` to set up, then `/hv:bug`, `/hv:feature`, or `/hv:todo` to add items.

Read `.hv/TODO.md`.

## Step 2 — Reconcile Active Items

Scan `## Bugs`, `## Features`, and `## Todos` for entries with an `*(active since YYYY-MM-DD)*` marker. These are items a previous `/hv:work` run started but may not have finished (e.g., session ended, context was lost).

For each active item:

1. **Check git history** — run `git log --oneline --since="YYYY-MM-DD" --all` (using the date from the marker) and search commit messages for keywords from the item's title
2. **If commits exist that clearly resolve the item** → move it to `## Completed` with the commit hash and today's date, same as a normal completion. Tell the user: *"[ID] [Title] was started earlier and looks complete based on git history — moved to Completed."*
3. **If no matching commits found** → remove the active marker (so it returns to normal pending state) and flag it to the user: *"[ID] [Title] was marked active on [date] but doesn't appear finished. Keeping it in the backlog."*

This reconciliation happens silently for resolved items and with a brief notice for unfinished ones. Present the notices before the backlog.

## Step 3 — Archive Completed Items

Check the `## Completed` section. Any entry whose completion date is **more than 5 days old** (compare the `Done YYYY-MM-DD` date against today) gets moved to `.hv/ARCHIVE.md`.

1. If `.hv/ARCHIVE.md` doesn't exist, create it with a `# Archive` heading
2. Append the old entries to the end of ARCHIVE.md (preserve their full text including the strikethrough and commit hash)
3. Remove them from `## Completed` in TODO.md

This keeps the active backlog focused on recent work while preserving history. Archive silently — don't list moved entries to the user.

Write both files back if anything changed.

## Step 4 — Build Relationship Map

Scan all items in `## Bugs`, `## Features`, and `## Todos` for `Related: [X-N], [Y-M]` suffixes. Build a bidirectional relationship map — if B-3 lists `Related: [F-2]`, then F-2 is also related to B-3, even if F-2 doesn't have an explicit `Related:` suffix.

Identify **clusters**: groups of 2+ items that are connected (directly or transitively). These clusters inform the suggestion in Step 6.

## Step 5 — Present the Backlog

Render a table for each non-empty section. Use this format:

### Bugs

| ID | Prio | Title | Related |
|----|------|-------|---------|
| B-1 | P0 | Crash on launch | |
| B-2 | P1 | Stale badge | F-3 |

Sort by priority: P0 first, then P1, then P2. Flag P0 items with a note that they're urgent.

### Features

| ID | Size | Title | Related |
|----|------|-------|---------|
| F-3 | Minor | Quick-switch projects | B-2 |

Sort by size: Cosmetic first (quick wins), then Minor, then Major.

### Todos

| ID | Title | Related |
|----|-------|---------|
| T-1 | Update Swift toolchain | F-4 |

The **Related** column shows IDs from the relationship map (both explicit and inferred). Leave it empty when the item has no links.

If clusters exist, add a brief note after the tables:

```
Clusters:
  [F-3] ↔ [B-2] — fix the badge bug before or alongside the feature
  [T-1] → [F-4] — toolchain update unblocks the feature
```

If all sections are empty, say so and suggest `/hv:bug`, `/hv:feature`, or `/hv:todo`.

## Step 6 — Suggest Next

Recommend what to work on next using this logic:

1. **Any P0 bug?** → Always suggest P0 bugs first, they block usage
2. **Cluster with blocking bugs?** → If a feature has related bugs, suggest fixing the bugs first or tackling the cluster together
3. **Quick win available?** → If there's a Cosmetic feature or P2 bug that takes minutes, suggest bundling 2–3 of them together
4. **Highest-impact P1 bug** → Bugs that degrade daily experience
5. **Blocking todos** → Chores that unblock other items (check `Related:` links)
6. **Minor features** → Good default when no urgent bugs
7. **Major features** → Only suggest if nothing else is pending, or the user specifically wants to tackle something big

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

- **Always clean up before presenting** — stale completed items are noise
- **Always render the table** — the table is the default view, not optional
- **Don't auto-start work** — always confirm with the user first
- **Respect the user's choice** — your suggestion is a recommendation, not a mandate
- **Pass full context to /hv:work** — include the TODO.md description so the work skill doesn't need to re-read it
- **Reference items by ID** — use `[B-1]`, `[F-3]`, `[T-2]` in suggestions and when talking about items
