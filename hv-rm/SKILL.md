---
name: hv-rm
description: Remove a captured backlog item and clean up its dependencies — strips the TODO entry, removes Related cross-references, deletes the detail file (.hv/{bugs,features,tasks}/<ID>.md), removes any plan keyed to it (.hv/plans/<milestone>-<ID>.md), and refuses if the item is active in status.json. Defaults to a dry-run preview; the slash command always asks before applying. Inverse of /hv-capture.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🗑️  hv-rm  ·  remove a backlog item and clean up its dependencies
  triggers: "remove backlog item", "delete this entry"  ·  pairs: hv-capture, hv-next
════════════════════════════════════════════════════════════════════════
```

# hv-rm — Remove Backlog Items

The inverse of `/hv-capture`: remove one or more items from the backlog and clean up every trace — the BACKLOG.md entry, Related cross-references, the detail file (`.hv/{bugs,features,tasks}/<ID>.md`), and any plan keyed to the item (`.hv/plans/<milestone>-<ID>.md`). The safe default is dry-run: every invocation previews what would change before touching anything. Items currently active in `status.json` are refused outright unless `--force` is passed, which strips them with a warning. The ARCHIVE.md historical record is preserved by default; pass `--scrub-archive` alongside `--force` to remove it too — opt-in only, since a removed item's ARCHIVE entry is the only audit trail left. Counters do not decrement — minted IDs stay claimed forever.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Resolve IDs", description="Parse and validate each ID against BACKLOG.md")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (user aborts at confirm, no cross-references found) get `completed` with the no-op reason in the description.

Phases:

1. *Resolve IDs* — args parsed, each ID matched to a TODO entry (Step 2)
2. *Dry-run preview* — removal plan rendered, cross-references identified (Step 3)
3. *De-tag upstream issues* — optional manual gate to remove the upstream label before local delete (Step 3.5)
4. *Confirm* — three-option `AskUserQuestion` gate (apply / abort / customize) (Step 4)
5. *Apply removals + cross-ref sweep* — TODO entries deleted, detail files removed, cross-references swept (Step 5)

## Step 2 — Parse Arguments

Pass the user's argument verbatim as `<CSV>` to `bin/hv-rm` in Step 3. The helper validates IDs (split-and-strip on commas — `B01, F03` and `B01,F03` resolve identically), exits 1 with a usage message on empty or missing argv, and exits 1 again on unknown IDs (not in BACKLOG.md or ARCHIVE.md). No skill-side validation needed.

## Step 3 — Dry-Run Preview

Run the helper with no `--force` flag; it defaults to dry-run and prints what would change:

```bash
.hv/bin/hv-rm <CSV>
```

Exit codes:

- **0** — preview printed successfully. Surface the full stdout to the user verbatim, then continue to Step 4.
- **1** — one of the IDs was not found in BACKLOG.md or ARCHIVE.md, or an unrecognised flag was given. Surface the stderr message to the user verbatim and **stop** — do not proceed to Step 4.
- **2** — one or more IDs are currently active in `status.json`. Surface the stderr message verbatim and inform the user: *"The item is active. Proceeding via Step 4 with `--force` will strip it from the active stream and leave a warning in the output."*

## Step 3.5 — De-tag Upstream Issues (manual gate)

> **Manual gate — removing the upstream label.** Removing the `in-progress` label on the upstream issue is externally-visible — collaborators see the issue no longer claimed. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. The item delete proceeds regardless; this step decides whether to clean up the label upstream too. See `references/manual-gates.md`.

Run the lookup helper to discover cross-references for the items about to be removed:

```bash
.hv/bin/hv-issues-imported
```

The helper always exits 0 and emits a JSON array. Filter it to entries whose `item_id` is in the to-be-removed set (the `<CSV>` from Step 2):

```bash
# Example: CSV = "F69,B12"
IDS_JSON=$(echo "<CSV>" | tr ',' '\n' | jq -Rn '[inputs | gsub("^\\s+|\\s+$"; "")]')
REFS=$(
  .hv/bin/hv-issues-imported \
  | jq --argjson ids "$IDS_JSON" '[.[] | select(.item_id as $id | $ids | index($id) != null)]'
)
```

Read the label name from config (default `"in-progress"`):

```bash
LABEL=$(jq -r '.issues.label // "in-progress"' .hv/config.json 2>/dev/null || echo "in-progress")
```

**If `$REFS` is an empty array (`[]`), skip the gate entirely and proceed to Step 4.**

If `$REFS` is non-empty, surface the `AskUserQuestion` below. **In loop mode this question is still surfaced and never auto-picked — it is a manual gate.**

- **Header:** `"De-tag"`
- **Question:** `"Remove the \`<label>\` label on <N> upstream issue(s)? <list of #N>."`
  (Substitute `<label>` from `$LABEL`, `<N>` from `$REFS | length`, and list each `#<issue>` from `$REFS`.)
- **Options** (single-select):
  1. `"Yes, remove the label upstream"` — for each entry in `$REFS`, call in parallel:
     ```bash
     .hv/bin/hv-issues-label remove --issue <issue> --label "$LABEL" [--repo <repo>]
     ```
     Include `--repo <repo>` only when the entry's `repo` field is non-null. Propagate exit 1 if any call fails.
  2. `"No, just delete the item"` — print the warning below and continue:
     ```
     Note: upstream issues still carry the `<label>` label. Remove via
     `gh issue edit <N> --remove-label <label>` or `glab issue update <N> --unlabel <label>` if desired.
     ```

Proceed to Step 4 regardless of which option was chosen.

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

`/hv-rm` is the local inverse of `/hv-capture` — it does **not** close upstream GitHub/GitLab issues. If the removed item has a linked issue, Step 3.5 offers to remove the `in-progress` label upstream; closing the issue itself is always manual. Counters intentionally do not decrement; minted IDs remain claimed so there is never ambiguity about what `[F36]` referred to.

## Rules

- Default is dry-run; `--force` is the only way to apply changes.
- Active-stream items (in `status.json`) are refused without `--force`; with `--force`, the ID is stripped and a warning surfaces in the output.
- ARCHIVE.md is preserved by default; `--scrub-archive` is opt-in.
- Counters do not decrement — minted IDs stay claimed.
- Upstream `in-progress` labels are removed only when the user approves the Step 3.5 manual gate; closing upstream issues is always manual.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
