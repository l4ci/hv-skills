---
name: hv-next
description: Review the backlog, reconcile active work against git state, archive old completions, show sorted tables with relationship clusters, suggest the next item, and route to /hv-work. Detects handoff notes from /hv-pause on active streams (post-/clear reorientation flow). Use on "what should I work on", "where was I", "pick up the next task", "resume", or when the user wants to see their backlog.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  👉  hv-next  ·  current state, handoff detection, next item
  triggers: "what's next", "where was I", "resume"  ·  pairs: hv-pause, hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-next — Pick & Work the Next Item

Review the project backlog, suggest what to tackle next, and execute it.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling. Observe-only: on exit `2`, surface *"Nothing tracked yet — run `/hv-init` then `/hv-capture`."* and stop (no auto-init).

## Step 2 — Reconcile Active Work

```bash
.hv/bin/hv-reconcile
```

Validates `status.json` against git, auto-cleans stale entries (dead branches), nulls missing worktree paths, and emits JSON with three arrays:

- `cleaned` — removed silently. No output needed.
- `needsAction` — branch still exists. Fields: `branch`, `items`, `worktree`, `startedAt`, `hasCommits`, `commitCount`, `worktreeMissing`.
- `todoDrift` — IDs that shipped in a commit subject but are still listed as open in TODO.md. Each entry: `id` and `commits[]` (each with `repo`, `hash`, `subject`).

When `todoDrift` is non-empty, print one informational line per drifted ID using the most recent commit (last in the `commits` list): `[ID] looks shipped on <hash> but still open in TODO.md`. Then suggest *"Run `.hv/bin/hv-complete <ID> <hash>` to close it, or re-open the work if it isn't actually done."* This is informational only — don't block, don't ask, continue to Step 3 after printing.

If `needsAction` is empty, produce no output and continue.

**Read handoff notes per stream.** Before building the per-stream questions, resolve and read any `/hv-pause` handoff note for each `needsAction` entry. Reconcile output gives `.repo` per stream (may be `null`); the path resolves with an ordered fallback so umbrella streams pick up the `(branch, repo)`-keyed file while single-repo / pre-feature notes keep working:

```bash
# Per stream — reconcile output gives BRANCH and REPO (REPO may be empty)
if [ -n "$REPO" ] && [ -f ".hv/handoff/${BRANCH}@${REPO}.md" ]; then
  HANDOFF=".hv/handoff/${BRANCH}@${REPO}.md"
elif [ -f ".hv/handoff/${BRANCH}.md" ]; then
  HANDOFF=".hv/handoff/${BRANCH}.md"
else
  HANDOFF=""
fi
[ -n "$HANDOFF" ] && cat "$HANDOFF"
```

Issue these reads in parallel — one per stream — in the same tool-call batch as any other independent reads in this step. The bare `<branch>.md` form is a legacy fallback covering single-repo cycles and any handoff written before umbrella keying shipped; the umbrella-keyed `<branch>@<repo>.md` form is preferred whenever the stream has a non-null `repo`.

For each stream that has a handoff, extract the **Stage**, **Next planned step**, and **Current hypothesis** sections — those drive the question text and routing below. Streams without a handoff note keep today's behavior unchanged.

Otherwise, use the `AskUserQuestion` tool so the user can resolve each stream with the host's native question UI. Batch up to 4 streams into one `AskUserQuestion` call; if there are more than 4, present the rest in a second call after the first resolves.

For each entry, build one question:

- **Header:** `"<branch>"` (truncate to 12 chars)
- **Question:** context line describing the stream. Examples:
  - `hasCommits: true` — *"[B01], [F03] look complete on `hv/timer-fix` (3 commits). What should I do?"*
  - `hasCommits: false` — *"[F07] is in progress on `hv/auth-refresh` (started 2026-04-18, no commits yet). What should I do?"*
  - Handoff present — *"`hv/auth-refresh` was paused mid-investigation: 'verify the OAuth callback path'. What should I do?"* (substitute the handoff's **Next planned step** as the verb phrase)
  - Append *" (worktree was cleaned up)"* to the question if `worktreeMissing: true`.
- **Options** (single-select):
  - **Handoff note present** (regardless of `hasCommits`):
    1. "Resume with `/hv-work` (Recommended)" — *"Pick up using the handoff brief; the note will be consumed on dispatch."*
    2. "Leave handoff for later" — *"No action now; the note stays in `.hv/handoff/` and surfaces again on next `/hv-next`."*
    3. "Abandon" — *"Delete the branch, clear `status.json`, and remove the handoff note."*
  - `hasCommits: true`:
    1. "Ship via `/hv-ship` (Recommended)" — *"Run `/hv-ship` on the branch — runs review, then merges or opens a PR."*
    2. "Resume with `/hv-work`" — *"Keep adding to the branch."*
    3. "Leave as-is" — *"No action now; stream stays in `status.json`."*
  - `hasCommits: false`:
    1. "Resume with `/hv-work` (Recommended)" — *"Pick up where it left off."*
    2. "Abandon" — *"Delete the branch and clear `status.json`."*
    3. "Leave as-is" — *"No action now; stream stays in `status.json`."*

Route each resolution:

| Answer | Action |
|--------|--------|
| Ship via `/hv-ship` | Invoke `hv-ship` via the `Skill` tool with this branch |
| Resume with `/hv-work` | Invoke `hv-work` on the existing branch |
| Abandon | `git branch -D <branch>` then `.hv/bin/hv-status-remove [--repo <repo>] <branch>` (pass `--repo` when the active entry has a non-null `repo`) |
| Leave as-is | Print *"Skipped `<branch>` — still in `status.json`."* and continue |
| Resume with `/hv-work` (handoff arm) | Invoke `hv-work` via the `Skill` tool with the branch + the handoff content as the brief; then `rm -f` the handoff path. |
| Leave handoff for later | Print *"Handoff for `<branch>` left in place — re-run `/hv-next` later."* and continue. |

Plain-text fallback: *"Merge or open a PR?"* and *"Resume or abandon?"* — honor the user's free-text reply.

## Step 3 — Archive Completed Items

```bash
.hv/bin/hv-archive-old 5
```

Moves `## Completed` items older than 5 days to `ARCHIVE.md`. Silent — don't report the count.

## Step 4 — Read Active Milestones

```bash
.hv/bin/hv-vision-active
```

If the helper prints nothing, no milestones are active — Step 6 ranks the whole backlog without milestone bias. Otherwise capture the list (one or more IDs); it shapes both the backlog presentation in Step 5 and the suggestion in Step 6.

If at least one milestone is active, also gather items already tagged to each. **Issue one `hv-todo-by-milestone` call per active milestone in parallel** (one tool-call batch, not the sequential shell loop):

```bash
.hv/bin/hv-todo-by-milestone M01
.hv/bin/hv-todo-by-milestone M03
# …one per active milestone, all dispatched in the same response
```

Carry the per-milestone ID set forward. Step 3 (`hv-archive-old`), Step 4 (`hv-vision-active` and the per-milestone reads above), and Step 5's `hv-backlog` can also share the same parallel batch — none of them mutate shared state, so there's no ordering constraint beyond the reconcile in Step 2.

## Step 5 — Present the Backlog

```bash
.hv/bin/hv-backlog
```

Prints pre-sorted markdown tables: "In Progress" (active items from `status.json`), "Bugs" (P0→P2), "Features" (Cosmetic→Major), "Tasks". Empty sections are omitted. If the backlog is empty, the helper prints a placeholder — pass it through and stop.

**Always print the full helper output verbatim — every row, every section.** Do not summarize, truncate, omit rows, collapse sections, wrap in code fences, or replace with a count ("12 bugs pending"). The user invoked `/hv-next` specifically to *see* the backlog; a missing or shortened table defeats the command. This applies even if the table is long or a word-budget hint suggests otherwise — backlog tables are exempt from response-length limits.

`hv-backlog` emits a `### Clusters` section automatically when 2+ items are joined by `Related:` references — pairs render as `[A] ↔ [B]`, larger groups as comma-separated. The section is part of the verbatim output; don't reformat or restate it. You may add a single editorial line after a cluster if a tactical hint is genuinely useful (e.g. *"fix the bug before the feature"*) — otherwise leave the helper's output to stand on its own.

If Step 4 found active milestones, prefix the backlog with a one-line header so the user knows what's in focus:

```
Active milestones: M01 — Auth foundation, M03 — Public API
```

(The `Milestone` column in `hv-backlog`'s tables already shows per-item tags when any are present — don't restate that.)

## Step 6 — Suggest Next

Recommend using this priority order:

1. P0 bugs first — they block usage (always, regardless of milestone)
2. Clusters with blocking bugs — fix bugs first or tackle the cluster together
3. Quick wins — Cosmetic features or P2 bugs; bundle 2–3 if small
4. Highest-impact P1 bugs
5. Blocking tasks (check `Related:` links)
6. Minor features — default when no urgent bugs
7. Major features — only if nothing else is pending or the user asks

**Milestone bias** — when Step 4 found active milestones, prefer items tagged to one of them at *every level except P0*. Concretely: within each priority/size band, items tagged to an active milestone come before untagged items, which come before items tagged to a non-active (planned) milestone. P0 bugs ignore this — production fires don't wait for the milestone schedule.

If the active milestone has no captured items yet, surface that in the suggestion line — *"M01 has no items yet; consider running `/hv-capture` to seed it"* — and then suggest the best general-backlog item.

Skip items already active. Present:

```
Suggested next: [ID] [Title] ([tag])
[Why this one — 1 sentence]
```

## Step 7 — Confirm & Execute

Read `autonomy.level` from `.hv/config.json` (default `"off"`).

**Loop mode auto-pick.** When `autonomy.level == "loop"`, skip the question entirely and invoke `hv-work` via the `Skill` tool with the suggested item(s) and their TODO descriptions. This is what sustains the `/hv-work` → `/hv-learn` → `/hv-next` → `/hv-work` loop. Print one line first so the user sees the pick: *"Loop: starting [ID] [Title]."*

If Step 6 found nothing to suggest (empty backlog, no active milestone items), do **not** invoke `/hv-work`. Print *"Loop: backlog empty — stopping."* and exit. The user re-invokes `/hv-capture` or `/hv-vision` to seed more work.

**Off and auto modes.** Use the `AskUserQuestion` tool so the user picks with the host's native UI. Build a single question:

- **Header:** `"Next"`
- **Question:** *"Work on the suggested item(s)?"* (substitute "items" for a batch)
- **Options** (single-select). Build the list dynamically — option 1 is always present, options 2 and 3 are conditional, options 4–5 always close the list:
  1. `"Start [ID] (Recommended)"` — *"Invoke `/hv-work` with the suggested item(s) and their TODO descriptions."* (list IDs in the label if it's a batch, else the single ID)
  2. `"Peek approach first (/hv-assume)"` — *"Print the orchestrator's intended files, tests, and assumptions; nothing executes."* — **include when** the suggested pick is a size-Major feature, a P0/P1 bug, or a multi-item batch.
  3. `"Write a plan first (/hv-plan)"` — *"Open `/hv-plan` to write a milestone-keyed plan; `/hv-work` will consult it later."* — **include when** the suggested pick is size-Major **and** no plan exists at `.hv/plans/<milestone>-<unit>.md`. Skip the option silently if the item has no `Milestone:` tag (no plan key without a milestone).
  4. `"Pick different items"` — *"Choose from the backlog yourself."*
  5. `"Stop here"` — *"No execution now; just leave me with the backlog view."*

Route the answer:

| Answer | Action |
|--------|--------|
| Start (Recommended) | Invoke `hv-work` via the `Skill` tool with the selected items + their TODO entries |
| Peek approach first | Invoke `hv-assume` via the `Skill` tool with the suggested item ID(s); after the peek prints, the user re-invokes `/hv-next` or `/hv-work` themselves |
| Write a plan first | Invoke `hv-plan` via the `Skill` tool with the milestone tag and item ID; once the plan is written, suggest `/hv-work <milestone>-<id>` as the natural next step |
| Pick different items | Second `AskUserQuestion` call with a `multiSelect: true` question listing up to 4 alternative items (or ask the user to name them if the backlog has more than 4). Then invoke `hv-work` on the chosen set |
| Stop here | Print *"OK — run `/hv-next` again when you're ready."* and exit |
| "Other" (free text) | Treat the user's text as the item spec; route to `/hv-work` |

Plain-text fallback: *"Work on this?"* — honor yes/no/"pick specific IDs" replies.

## Step 8 — Release Nudge

Fires only on the *terminal* paths of /hv-next — when the user picks "Stop here" in Step 7 or when the backlog was empty (loop or off/auto). When Step 7 dispatches into /hv-work, /hv-assume, or /hv-plan, skip this step entirely — those skills run their own tails and the nudge would either be drowned out or surface again at the wrong time.

```bash
.hv/bin/hv-release-pending
```

Parse the JSON output. If `shouldNudge` is `false`, skip silently. If `true`, append the helper's `message` field as a single line of output (after any "OK — run `/hv-next` again..." message). The helper renders the appropriate phrasing based on `reason`; the skill just prints it.

Keep it to one line. Don't expand into a paragraph or a checklist — the nudge is informational and the user might just dismiss it.

If `lastTag == ""` (no tags yet — nothing has been released), skip silently. The first release is the user's call, not a system nudge.

## Rules

- **No noise** — never report on a step that found nothing. Silence is signal.
- **Backlog table is mandatory** — Step 5 output must always reach the user in full. No row-count summaries, no "…and 8 more", no dropping sections, no placing the table inside a collapsed block. If the response would otherwise be trimmed, shorten *your* prose (suggestion, clusters, questions) before touching the table.
- **Pass full context to /hv-work** — include TODO.md descriptions so work doesn't re-read.
- **Reference items by ID** — `[B01]`, `[F03]`, `[T02]` in suggestions and messages.
- **Git is the source of truth** — if `status.json` disagrees with git state, trust git.
- **Handoff consumption is per-stream, on resolve.** When the user picks "Resume with `/hv-work`" on a handoff arm, `rm -f` the handoff file *only* for that stream. "Leave handoff for later" preserves the file. Other streams' handoff files are not touched.
