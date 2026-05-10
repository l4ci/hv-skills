---
name: hv-rm
description: Remove a captured backlog item and clean up its dependencies — strips the TODO entry, removes Related cross-references, deletes the detail file (.hv/{bugs,features,tasks}/<ID>.md), removes any plan keyed to it (.hv/plans/<milestone>-<ID>.md), and refuses if the item is active in status.json. Defaults to a dry-run preview; the slash command always asks before applying. Inverse of /hv-capture.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  🗑️  hv-rm  ·  remove a backlog item and clean up its dependencies
  triggers: "remove backlog item", "delete this entry"  ·  pairs: hv-capture, hv-next
════════════════════════════════════════════════════════════════════════
```

# hv-rm — Remove Backlog Items

The inverse of `/hv-capture`: remove one or more items from the backlog and clean up every trace — the TODO.md entry, Related cross-references, the detail file (`.hv/{bugs,features,tasks}/<ID>.md`), and any plan keyed to the item (`.hv/plans/<milestone>-<ID>.md`). The safe default is dry-run: every invocation previews what would change before touching anything. Items currently active in `status.json` are refused outright unless `--force` is passed, which strips them with a warning. The ARCHIVE.md historical record is preserved by default; pass `--scrub-archive` alongside `--force` to remove it too — opt-in only, since a removed item's ARCHIVE entry is the only audit trail left. Counters do not decrement — minted IDs stay claimed forever.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Resolve IDs", description="Parse and validate each ID against TODO.md")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (user aborts at confirm, no cross-references found) get `completed` with the no-op reason in the description.

Phases:

1. *Resolve IDs* — args parsed, each ID matched to a TODO entry (Step 2)
2. *Dry-run preview* — removal plan rendered, cross-references identified (Steps 3–4)
3. *Confirm* — three-option `AskUserQuestion` gate (apply / abort / customize) (Step 5)
4. *Apply removals + cross-ref sweep* — TODO entries deleted, detail files removed, cross-references swept (Steps 6–7)

## Step 2 — Parse Arguments

The argument passed to `/hv-rm` is a CSV of one or more IDs, for example `F36` or `B01,F03,T05`. Normalise whitespace around commas; treat `B01, F03` the same as `B01,F03`.

If the argument is empty or missing, stop immediately with:

> *"Provide one or more IDs, e.g. `/hv-rm F36` or `/hv-rm B01,F03`."*

Carry the normalised CSV as `<CSV>` into the remaining steps.

## Step 3 — Dry-Run Preview

Run the helper with no `--force` flag; it defaults to dry-run and prints what would change:

```bash
.hv/bin/hv-rm <CSV>
```

Exit codes:

- **0** — preview printed successfully. Surface the full stdout to the user verbatim, then continue to Step 4.
- **1** — one of the IDs was not found in TODO.md or ARCHIVE.md, or an unrecognised flag was given. Surface the stderr message to the user verbatim and **stop** — do not proceed to Step 4.
- **2** — one or more IDs are currently active in `status.json`. Surface the stderr message verbatim and inform the user: *"The item is active. Proceeding via Step 4 with `--force` will strip it from the active stream and leave a warning in the output."*

## Step 4 — Confirmation Gate

Use a single `AskUserQuestion` call. Show the dry-run output above the question so the user can review the plan before committing.

- **Header:** `"Apply"`
- **Question:** `"Apply this removal plan for <CSV>?"`
- **Options** (single-select):
  1. `"Apply (Recommended)"` — runs `.hv/bin/hv-rm --force <CSV>`. Strips the TODO entry and Related cross-references; ARCHIVE entries stay intact as the historical record.
  2. `"Apply + scrub ARCHIVE"` — runs `.hv/bin/hv-rm --force --scrub-archive <CSV>`. Same as Apply, plus removes the ARCHIVE.md historical entry and strips any Related cross-references there too.
  3. `"Cancel"` — print *"No changes."* and stop; nothing is written.

Plain-text fallback (when `AskUserQuestion` is not available): ask once — *"Apply changes? (yes/no/scrub-archive)"* — `yes` → Apply; `scrub-archive` → Apply + scrub ARCHIVE; anything else → Cancel.

> Per the `hv-init` authoring convention "manual gates that are destructive or file public artifacts are never auto-invoked regardless of autonomy", `/hv-rm`'s confirmation gate always surfaces to the user — loop mode does not accelerate it.

## Step 5 — Apply (when not Cancel)

Invoke the chosen helper command. The helper prints a per-ID summary line for each item processed. Pass the full output through to the user verbatim. Then stop — do not nudge any other skill.

## Step 6 — When to Use

Use `/hv-rm` when:

- An item was captured as a duplicate and the original already covers it.
- The underlying premise turned out to be wrong — the bug doesn't exist, or the feature was based on a misunderstanding.
- Another item's implementation made this one obsolete before it was started.
- The item was captured against the wrong project context (wrong repo, wrong milestone scope).
- A spike or decision ruled out the approach the item depended on.
- You simply changed your mind and the work is no longer worth doing.

`/hv-rm` is the local inverse of `/hv-capture` — it does **not** close upstream GitHub issues. If the removed item has a linked GH issue, closing it is a manual gesture. Counters intentionally do not decrement; minted IDs remain claimed so there is never ambiguity about what `[F36]` referred to.

## Rules

- Default is dry-run; `--force` is the only way to apply changes.
- Active-stream items (in `status.json`) are refused without `--force`; with `--force`, the ID is stripped and a warning surfaces in the output.
- ARCHIVE.md is preserved by default; `--scrub-archive` is opt-in.
- Counters do not decrement — minted IDs stay claimed.
- GH issue references are not touched; close upstream issues manually if needed.
