---
name: hv-undo
description: Guided rollback of the last /hv-work cycle on the base branch. Use on "/hv-undo", "roll back the last cycle", "revert that merge", "undo /hv-work", or right after a bad /hv-work cycle landed on the base branch. Resets the merge commit, restores TODO entries to their type sections, refuses on cycles with post-merge commits unless --allow-post-merge is passed. Direct-merge cycles only (MVP); PR-mode is detected and refused with a manual-recovery pointer. Defaults to a dry-run preview; the slash command always asks before applying. Inverse of /hv-work's commit + completion steps.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  ↩️  hv-undo  ·  guided rollback of the last /hv-work cycle
  triggers: "undo last cycle", "roll back the merge"  ·  pairs: hv-work, hv-rm
════════════════════════════════════════════════════════════════════════
```

# hv-undo — Rollback the Last Cycle

The inverse of `/hv-work`'s commit + completion steps: reset the most recent `merge: …` commit on the base branch and restore the resolved items as TODO entries under their original type sections. The safe default is dry-run — every invocation previews what would change before touching anything. PR-mode cycles are refused with a manual-recovery pointer (the merge happened upstream, not locally). Post-merge commits on the base branch are refused by default; `--allow-post-merge` is opt-in. The confirmation gate is manual and never auto-picked in loop mode — `git reset --hard` is destructive past `git reflog`'s window.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Detect cycle* — most recent `merge: ` commit on base branch identified (Step 2 dry-run)
2. *Surface preview* — dry-run output rendered verbatim to user (Step 3)
3. *Confirm* — manual `AskUserQuestion` gate (Step 4)
4. *Apply rollback* — engine runs with `--force`, base resets, items restored (Step 5)
5. *Report* — summary line printed; no post-cycle nudges (Step 6)

## Step 2 — Detect Cycle (Dry-Run Preview)

Run the engine with no `--force` flag; it defaults to dry-run and prints what would change:

```bash
.hv/bin/hv-undo
```

Exit codes:

- **0** — dry-run printed successfully. Surface stdout verbatim to the user, then continue to Step 3.
- **1** — precondition error (no cycle on base, subject doesn't match `^merge: `, post-merge commits without `--allow-post-merge`, invalid arg, PR-mode cycle, not on base branch). Surface stderr verbatim and **stop** — do not proceed to Step 3.
- **2** — dirty tree. Print *"Working tree is dirty — commit, stash, or discard before /hv-undo can run."* and stop.

If the user wants to target a specific cycle other than the most recent, they invoke `.hv/bin/hv-undo --cycle <hash>` directly; the slash-command default is always the most recent.

If the base branch has commits past the cycle merge, `hv-undo` refuses by default. Resolve manually (`git reset` to before those commits) or re-run with `--allow-post-merge` to discard them. The skill surfaces the helper's stderr verbatim — no extra prompting.

## Step 3 — Surface the Plan

Render the helper's stdout to the user verbatim. The preview shows the merge commit being reset, the items being restored to BACKLOG.md, and any caveats (e.g. post-merge commits flagged for discard when `--allow-post-merge` is in play).

## Step 4 — Confirmation Gate

Use a single `AskUserQuestion` call. Show the dry-run output above the question so the user can review the plan before committing.

- **Header:** `"Apply"`
- **Question:** `"Apply this rollback plan?"`
- **Options** (single-select):
  1. `"Apply (Recommended)"` — runs `.hv/bin/hv-undo --force`. Resets the base branch and restores the TODO entries.
  2. `"Cancel"` — print *"No changes."* and stop; nothing is written.

Plain-text fallback (when `AskUserQuestion` is not available): ask once — *"Apply rollback? (yes/no)"* — `yes` → Apply; anything else → Cancel.

> Per the `hv-init` authoring convention "manual gates that are destructive or file public artifacts are never auto-invoked regardless of autonomy", `/hv-undo`'s confirmation gate always surfaces to the user — loop mode does not accelerate it. `git reset --hard` is destructive and unrecoverable past `git reflog`'s window; the user must confirm.

## Step 5 — Apply (when not Cancel)

```bash
.hv/bin/hv-undo --force
```

(Or `.hv/bin/hv-undo --force --allow-post-merge` when the user opted into discarding post-merge commits in Step 2 — but Step 2 errored out and re-routed for that case; the simpler `--force` is the common path.)

Pass the helper's stdout to the user verbatim. Then continue to Step 6.

## Step 6 — Report

Print the engine's final summary line as-is. Do **not** invoke `/hv-learn`, `/hv-docs`, `/hv-refactor`, or `/hv-next` — this is a terminal skill. The user re-runs `/hv-next` themselves to see the restored backlog.

## Step 7 — When to Use

Use `/hv-undo` when:

- The cycle landed but the implementation turned out wrong on closer inspection.
- A reviewer flagged a regression and the simplest fix is "roll back, redesign, re-cycle".
- The cycle resolved an item that should not have been resolved (premise was wrong; item should be re-opened for redesign).
- A `/hv-go` cycle landed something the user didn't actually want — `/hv-undo` is the fast inverse.

`/hv-undo` is **not** for:

- Undoing a cycle whose merge was a PR — use `gh pr close <num>` for open PRs, `git revert` for merged PRs.
- Undoing more than one cycle at a time — invoke twice.
- Editing what landed — that's `/hv-go` or a new `/hv-capture` + `/hv-work`.

## Rules

- Default is dry-run; `--force` is the only way to apply changes.
- The base-branch + clean-tree preconditions are enforced by the helper; the skill never tries to bypass them.
- Post-merge commits on the base branch refuse by default; `--allow-post-merge` is opt-in.
- Manual confirmation gate; loop mode does not auto-pick.
- Terminal skill — no post-cycle nudges. The user re-orients with `/hv-next`.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
