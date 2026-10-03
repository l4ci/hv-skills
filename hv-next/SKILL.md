---
name: hv-next
description: Review the backlog, reconcile active work against git state, archive old completions, show sorted tables with relationship clusters, suggest the next item, and route to /hv-work. Detects handoff notes from /hv-pause on active streams (post-/clear reorientation flow). Use on "what's next", "what should I work on", "where was I", "pick up the next task", "resume", or when the user wants to see their backlog.
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  👉  hv-next  ·  current state, handoff detection, next item
  triggers: "what's next", "where was I", "resume"  ·  pairs: hv-pause, hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-next — Pick & Work the Next Item

Review the project backlog, suggest what to tackle next, and execute it.

## Step 1 — Task List

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Reconcile* — `status.json` cross-checked against git state (Step 2)
2. *Archive* — completed items moved to `ARCHIVE.md` (Step 3)
3. *Present backlog* — sorted tables and relationship clusters shown (Steps 4–5)
4. *Suggest* — single recommended item picked (Step 6)
5. *Execute* — `/hv-work` dispatched per autonomy + user choice (Step 7)

## Step 2 — Reconcile Active Work

**Dispatch the Steps 2–6 read-heavy work as a single parallel wave.** Per `references/subagent-dispatch.md`, the reconcile + archive + per-milestone summary + relevance-query work is four independent operations on disjoint inputs. The orchestrator dispatches four workers in one tool-call batch and merges their returns before Step 5's backlog presentation: **Worker A** (reconcile active streams), **Worker B** (archive scan), **Worker C** (milestone summary), **Worker D** (relevance map).

| Worker | Model | Inputs | Returns |
|--------|-------|--------|---------|
| **Worker A — Reconcile** | sonnet | `status.json`, git refs | `{cleaned, needsAction, todoDrift, todoSymbolDrift}`, built per **Reconcile procedure** below. |
| **Worker B — Archive scan** | haiku | `BACKLOG.md`, `archive.ttl` config | List of completion-dated entries past TTL (runs `hv backlog archive --days 5`, returns the moved count). |
| **Worker C — Milestones** | sonnet | `MILESTONES.md`, `.hv/milestones/M*.md`, active IDs from `hv milestone active` | `milestone → remaining map` (per active milestone: ID set from `hv backlog ids --milestone <MNN>`, slice summary). In issue mode (`references/issue-mode.md`) the inputs are `hv milestone active`, `hv milestone list`, `hv milestone show <MNN>` and `hv backlog ids --milestone <MNN>`; never read `.hv/milestones/*.md`. |
| **Worker D — Relevance** | sonnet | Top-N candidate IDs from current `BACKLOG.md` sorted by `hv backlog list`, plus topic strings from each candidate | Relevance map: `{candidate ID → matching knowledge bullets, decisions, context terms}` via the canonical K+D query pattern (`references/knowledge-consult.md`). |

Each brief uses the small-brief template from the reference: Goal · Inputs (paths/IDs only) · Constraints (cite the worktree-isolation rule when commit-producing waves are involved, though this wave is read-only) · Return shape (the table above) · Word budget ≤200 words.

**Reconcile procedure (Worker A).** Read `.hv/status.json`; for each `active` entry (`branch`, `repo`, `items`, `worktree`, `startedAt`), with `-C <path>` pointing git at the entry's sub-repo when `repo` is non-null (path from `hv repo resolve <repo> --json`):

1. `repo` not registered (`hv repo resolve` exits 3) → add to `cleaned` with reason `repo_unregistered`; leave the entry in place.
2. `git branch --list <branch>` empty → run `hv status rm <branch>` (add `--repo <repo>` when non-null) and add to `cleaned` with reason `branch_gone`.
3. Otherwise add to `needsAction`: `hasCommits` is `git rev-list --count <base>..<branch>` > 0, where `<base>` comes from `hv git base`; `worktreeMissing` is a non-null `worktree` that is not a directory. In umbrella mode, an entry with `repo: null` whose umbrella has no base branch (`hv git base` fails) gets `noBase: true`; treat it as indeterminate, not zero commits.

Then `hv backlog drift --json` gives `data.drift` (`todoDrift`) and `data.symbolDrift` (`todoSymbolDrift`); on any failure (it refuses in issue mode) both are `[]`.

Aggregate the four returns into the working state used by Steps 3–6: drift IDs feed the `[ID] looks shipped on <hash>` lines below; archive output is silent (already moved); milestone map feeds the Step 5 header and the Step 6 milestone-bias check; relevance map feeds the Step 6 Suggested Next reasoning.

When `todoDrift` is non-empty, print one informational line per drifted ID using the most recent commit (last in the `commits` list): `[ID] looks shipped on <hash> but still open in BACKLOG.md`. Then suggest *"If you've verified it, record the check with `hv proof add <ID> --check <what you ran> --result PASS --evidence <output> --sha <hash>` and close it with `hv item complete <ID> --commit <hash>`. If nothing can be re-run, close it with `hv item complete <ID> --commit <hash> --no-proof`. If it isn't actually done, re-open the work."* This is informational only — don't block, don't ask, continue to Step 3 after printing.

When `todoSymbolDrift` is non-empty, print one advisory line per entry: `[ID] names symbol(s) <symbols> that appeared in the tree after capture (e.g. <file>) — verify it isn't already shipped before implementing.` (Use the entry's `symbols` joined and the first `files` entry as `<file>`.) This is a higher-precision "silently shipped without the `[ID]`" hint than `todoDrift`, but still advisory only — don't block, don't ask, and never auto-complete. The user/orchestrator should `git grep`/`git log` the named symbols to confirm the change really landed before implementing. Continue to Step 3 after printing.

If `needsAction` is empty, produce no output and continue.

**Read handoff notes per stream.** Before building the per-stream questions, resolve and read any `/hv-pause` handoff note for each `needsAction` entry. Each `needsAction` entry carries `repo` (may be `null`); the path resolves with an ordered fallback so umbrella streams pick up the `(branch, repo)`-keyed file while single-repo / pre-feature notes keep working:

```bash
# Per stream — the needsAction entry gives BRANCH and REPO (REPO may be empty)
HANDOFF="$(hv status handoff "$BRANCH" ${REPO:+--repo "$REPO"})"
[ -n "$HANDOFF" ] && cat "$HANDOFF"
```

Issue the resolve+read pairs in parallel — one per stream — in the same tool-call batch as any other independent reads in this step. `hv status handoff` is a lookup: it probes `.hv/handoff/<branch>@<repo>.md` first (umbrella-keyed, preferred when `repo` is non-null) and falls back to `.hv/handoff/<branch>.md` (single-repo / legacy); empty stdout (`data.path: null` under `--json`) means no handoff exists for the stream.

For each stream that has a handoff, extract the **Stage**, **Next planned step**, and **Current hypothesis** sections — those drive the question text and routing below. Streams without a handoff note keep today's behavior unchanged.

**Loop mode:** if `autonomy.level == "loop"`, skip AskUserQuestion entirely and auto-pick each stream's Recommended option:

- **Handoff note present** → `Resume with /hv-work` — invoke `hv-work` via the `Skill` tool with the branch + handoff content as the brief; `rm -f` the handoff path after dispatch.
- **`hasCommits: true`** (no handoff) → `Ship via /hv-ship` — invoke `hv-ship` via the `Skill` tool with the branch.
- **`hasCommits: false`** (no handoff) → `Resume with /hv-work` — invoke `hv-work` on the existing branch.

Auto-picking Recommended is exactly what loop mode wants for routine reconcile resolutions: handoff streams resume on the brief, complete streams ship through their own review/PR gates, and incomplete streams keep accumulating commits. Per the authoring convention "routine routing/tagging auto-picks Recommended in loop mode" (see `references/authoring-conventions.md` rule #5). The downstream skills (`/hv-ship`, `/hv-work`) keep their own manual gates intact (review FAIL, PR strategy, etc.) — loop mode auto-picks the **routing** answer, not the **public-artifact** answer.

After resolving every entry under loop mode, continue to Step 3 — do not surface "Skipped" lines, since nothing was skipped.

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
| Abandon | `git branch -D <branch>` then `hv status rm <branch> [--repo <repo>]` (pass `--repo` when the active entry has a non-null `repo`) |
| Leave as-is | Print *"Skipped `<branch>` — still in `status.json`."* and continue |
| Resume with `/hv-work` (handoff arm) | Invoke `hv-work` via the `Skill` tool with the branch + the handoff content as the brief; then `rm -f` the handoff path. |
| Leave handoff for later | Print *"Handoff for `<branch>` left in place — re-run `/hv-next` later."* and continue. |

Plain-text fallback: *"Merge or open a PR?"* and *"Resume or abandon?"* — honor the user's free-text reply.

## Step 3 — Archive Completed Items

```bash
hv backlog archive --days 5
```

Moves `## Completed` items older than 5 days to `ARCHIVE.md`. Silent — don't report the count.

## Step 4 — Read Active Milestones

```bash
hv milestone active
```

If it prints nothing, no milestones are active — Step 6 ranks the whole backlog without milestone bias. Otherwise capture the list (one or more IDs); it shapes both the backlog presentation in Step 5 and the suggestion in Step 6.

If at least one milestone is active, also gather items already tagged to each. **Issue one `hv backlog ids` call per active milestone in parallel** (one tool-call batch, not the sequential shell loop):

```bash
hv backlog ids --milestone M01
hv backlog ids --milestone M03
# …one per active milestone, all dispatched in the same response
```

The per-milestone ID set arrives from Worker C of the Step 2 dispatch wave; Step 5's `hv backlog list` runs on the orchestrator after the wave returns, since its output is presented verbatim and doesn't benefit from worker synthesis.

## Step 5 — Present the Backlog

```bash
hv backlog list
```

Prints pre-sorted tables: "In Progress" (active items from `status.json`), "Bugs" (P0→P2), "Features" (Cosmetic→Major), "Tasks". Empty sections are omitted. If the backlog is empty, it prints a placeholder — pass it through and stop.

**Always print the full output verbatim — every row, every section.** Do not summarize, truncate, omit rows, collapse sections, wrap in code fences, or replace with a count ("12 bugs pending"). The user invoked `/hv-next` specifically to *see* the backlog; a missing or shortened table defeats the command. This applies even if the table is long or a word-budget hint suggests otherwise — backlog tables are exempt from response-length limits.

`hv backlog list` emits a clusters section automatically when 2+ items are joined by `Related:` references — pairs render as `[A] ↔ [B]`, larger groups as comma-separated. The section is part of the verbatim output; don't reformat or restate it. You may add a single editorial line after a cluster if a tactical hint is genuinely useful (e.g. *"fix the bug before the feature"*) — otherwise leave the output to stand on its own.

If Step 4 found active milestones, prefix the backlog with a one-line header so the user knows what's in focus:

```
Active milestones: M01 — Auth foundation, M03 — Public API
```

(The `Milestone` column in `hv backlog list`'s tables already shows per-item tags when any are present — don't restate that.)

- **Stale candidates** — run `hv backlog stale --kind <k> --days 90 --json` for `map`, `knowledge` and `todo` (in parallel) and print one line `stale: map=N, knowledge=M, todo=K` from the `data.entries` counts, dropping zero-count kinds (print nothing if all three are zero). Never blocks output.
- **Empty active milestones** — for each active milestone whose Worker C ID set (`hv backlog ids --milestone <MID>`) is empty, print `empty-active: <MID> — no open items; ship with hv milestone status <MID> --to shipped.` Skip silently when every active milestone still has open items. Never blocks output.

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

**Issue mode** (`backlog.backend: "issues"`; `references/issue-mode.md`): items labelled `changes-requested` rank first (after P0 bugs): a reviewer already asked for changes and the work is half done. The `hv backlog drift` hint does not apply (the verb refuses in issue mode): skip any `todoDrift` / `todoSymbolDrift` nudge. When an item is picked, load its context per the reference's "Resuming an item" (`hv item show <ID>` for state, claim, assignee and comments, `hv item field list <ID>`, `hv item note show <ID> --kind design|plan`, the issue comments) and pass it to `/hv-work`.

Skip items already active. Present:

```
Suggested next: [ID] [Title] ([tag])
[Why this one — 1 sentence]
```

**Brainstorm nudge.** Fires when the suggested item is a `[Major]` feature OR a `[P0]` bug AND `.hv/designs/<ID>.md` does NOT exist. Skip silently for `[Minor]` / `[Cosmetic]` features, `[P1]` / `[P2]` bugs, and any item that already has a design artifact (the design negotiation is done).

Read `autonomy.level` from `.hv/config.json` (default `"off"`):

```bash
LEVEL=$(jq -r '.autonomy.level // "off"' .hv/config.json)
```

Branch inline (per the `hv-init` authoring convention on inline autonomy directives):

- `"off"` — append one line to the suggestion block before Step 7's `AskUserQuestion` fires: *"This is a `[Major]` item without a design — consider `/hv-brainstorm [ID]` before `/hv-work`."* Substitute `[P0]` for the tag when the suggested item is a bug. The existing 4 options in Step 7 are unchanged — the nudge informs the user; the picklist still lets them route to `/hv-work` if they decline.
- `"auto"` — invoke `hv-brainstorm` via the `Skill` tool with the suggested ID as `args`. Print *"Auto: starting /hv-brainstorm [ID] — re-running /hv-next once the design lands."* before the dispatch. When the brainstorm returns (design artifact at `.hv/designs/<ID>.md` written), re-run Step 6 — the freshly-written design will now satisfy the design-exists check and the suggestion proceeds without a second nudge.
- `"loop"` — skip the nudge entirely. Design resolution happens downstream: `/hv-work` Step 4's auto-dispatch chain runs `/hv-brainstorm --auto-loop` for Major + Milestone-tagged items without a design before the plan dispatch, so the design phase lives in `/hv-work` under loop, not here.

## Step 7 — Confirm & Execute

Read `autonomy.level` from `.hv/config.json` (default `"off"`).

**Loop mode auto-pick.** When `autonomy.level == "loop"`, skip the question entirely and invoke `hv-work` via the `Skill` tool with the suggested item(s) and their TODO descriptions. This is what sustains the `/hv-work` → `/hv-learn` → `/hv-next` → `/hv-work` loop. Print one line first so the user sees the pick: *"Loop: starting [ID] [Title]."* Before dispatching, stamp the session start so terminal paths can later filter `[Auto:Loop]` decisions to this loop:

```bash
hv status loop start   # idempotent — first-write only; preserves any existing timestamp
```

If Step 6 found nothing to suggest (empty backlog, no active milestone items), do **not** invoke `/hv-work`. Print *"Loop: backlog empty — stopping."* and exit. The user re-invokes `/hv-capture` or `/hv-vision` to seed more work.

On this empty-backlog branch (terminal path), surface any `[Auto:Loop]` decisions logged during the just-ended loop so the user can articulate `Forbids/Permits` and remove the `<!-- [Auto:Loop] -->` footers in `DECISIONS.md`. Per the F19 terminal-path-only convention, surfacing fires *only* here and from `/hv-work` guard-fail / `/hv-pause` — not from any loop-internal step:

Surface any `[Auto:Loop]` decisions per `references/terminal-loop-surface.md` (silent when empty). Print the surface verbatim above the "OK — run /hv-next again" line.

**Off and auto modes.** Use the `AskUserQuestion` tool so the user picks with the host's native UI. Build a single question:

- **Header:** `"Next"`
- **Question:** *"Work on the suggested item(s)?"* (substitute "items" for a batch)
- **Options** (single-select). Build the list dynamically — option 1 is always present, options 2 and 3 are conditional, options 4–5 always close the list:
  1. `"Start [ID] (Recommended)"` — *"Invoke `/hv-work` with the suggested item(s) and their TODO descriptions."* (list IDs in the label if it's a batch, else the single ID)
  2. `"Peek approach first (/hv-work --preview)"` — *"Print the orchestrator's intended files, tests, and assumptions; nothing executes."* — **include when** the suggested pick is a size-Major feature, a P0/P1 bug, or a multi-item batch.
  3. `"Write a plan first (/hv-plan)"` — *"Open `/hv-plan` to write a milestone-keyed plan; `/hv-work` will consult it later."* — **include when** the suggested pick is size-Major **and** no plan exists at `.hv/plans/<milestone>-<unit>.md`. Skip the option silently if the item has no `Milestone:` tag (no plan key without a milestone).
  4. `"Pick different items"` — *"Choose from the backlog yourself."*
  5. `"Stop here"` — *"No execution now; just leave me with the backlog view."*

Route the answer:

| Answer | Action |
|--------|--------|
| Start (Recommended) | Invoke `hv-work` via the `Skill` tool with the selected items + their TODO entries |
| Peek approach first | Invoke `hv-work` via the `Skill` tool with `--preview <ID>` for the suggested item ID(s); after the peek prints, the user re-invokes `/hv-next` or `/hv-work` themselves |
| Write a plan first | Invoke `hv-plan` via the `Skill` tool with the milestone tag and item ID; once the plan is written, suggest `/hv-work <milestone>-<id>` as the natural next step |
| Pick different items | Second `AskUserQuestion` call with a `multiSelect: true` question listing up to 4 alternative items (or ask the user to name them if the backlog has more than 4). Then invoke `hv-work` on the chosen set |
| Stop here | Print *"OK — run `/hv-next` again when you're ready."* and exit |
| "Other" (free text) | Treat the user's text as the item spec; route to `/hv-work` |

Plain-text fallback: *"Work on this?"* — honor yes/no/"pick specific IDs" replies.

## Step 8 — Release Nudge

Fires only on the *terminal* paths of /hv-next — when the user picks "Stop here" in Step 7 or when the backlog was empty (loop or off/auto). When Step 7 dispatches into /hv-work (with or without `--preview`) or /hv-plan, skip this step entirely — those skills run their own tails and the nudge would either be drowned out or surface again at the wrong time.

```bash
hv release pending --json
```

Read `data`. If `shouldNudge` is `false`, skip silently. If `true`, append its `message` field as a single line of output (after any "OK — run `/hv-next` again..." message). The verb renders the appropriate phrasing based on `reason`; the skill just prints it.

Keep it to one line. Don't expand into a paragraph or a checklist — the nudge is informational and the user might just dismiss it.

If `lastTag == ""` (no tags yet — nothing has been released), skip silently. The first release is the user's call, not a system nudge.

## Rules

- **No noise** — never report on a step that found nothing. Silence is signal.
- **Backlog table is mandatory** — Step 5 output must always reach the user in full. No row-count summaries, no "…and 8 more", no dropping sections, no placing the table inside a collapsed block. If the response would otherwise be trimmed, shorten *your* prose (suggestion, clusters, questions) before touching the table.
- **Pass full context to /hv-work** — include BACKLOG.md descriptions so work doesn't re-read.
- **Reference items by ID** — `[B01]`, `[F03]`, `[T02]` in suggestions and messages.
- **Git is the source of truth** — if `status.json` disagrees with git state, trust git.
- **Handoff consumption is per-stream, on resolve.** When the user picks "Resume with `/hv-work`" on a handoff arm, `rm -f` the handoff file *only* for that stream. "Leave handoff for later" preserves the file. Other streams' handoff files are not touched.

## References

- [`references/issue-mode.md`](../references/issue-mode.md) — Issue-mode differences (`backlog.backend: "issues"`): helper map, labels, resuming an item.
- [`references/authoring-conventions.md`](../references/authoring-conventions.md) — Authoring rules shared across SKILL.md files (loop-mode auto-picks, mirror-step threshold).
- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
