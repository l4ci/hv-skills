---
name: hv-ship
description: Bundle completed work on a feature branch into a PR (or direct merge) — extracts commits, resolved item IDs with titles, optionally runs /hv-review, and calls hv-pr or hv-merge. Use on "ship it", "open the PR", "finish this branch", when work is done and you want to integrate.
user-invocable: true
---

```
════════════════════════════════════════════════════════════════════════
  🟩  hv-ship  ·  bundle work into a PR or merge
  triggers: "ship it", "open the PR"  ·  pairs: hv-review
════════════════════════════════════════════════════════════════════════
```

# hv-ship — Finish a Feature Branch

Turn the commits on the current feature branch into either a GitHub PR or a direct merge. Optionally runs `/hv-review` first so the diff gets a staff-engineer pass before it leaves your machine.

## Configuration

Read `.hv/config.json`:

- `work.mergeStrategy` — `"pr"` or `"direct"` (falls back to asking if the key is unset)
- `ship.review` — `true` (default) runs `/hv-review` before integrating; `false` skips the review
- `autonomy.level` — `"off"` (default), `"auto"`, or `"loop"`. Controls whether Step 8.5 (Learn) and Step 10 (Loop continuation) nudge or invoke directly. See `GUIDE.md` § Autonomy.

## When to Use

- Feature branch has 1+ commits, work is done, you want to integrate
- After `/hv-work` finished with `mergeStrategy: "pr"` and you want to open the PR now
- Any branch you want reviewed + merged/pushed in one pass

## When NOT to Use

- Work is still in progress → finish implementing via `/hv-work`
- Nothing committed yet → clean up, then come back
- You want to resume a paused branch → `/hv-resume`

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

If the helper is absent or exits non-zero, invoke `hv-init` via the `Skill` tool, then continue. See GUIDE.md § Preflight for exit codes.

Determine the current branch:

```bash
git rev-parse --abbrev-ref HEAD
```

If it's `main`/`master`/`trunk`, stop and tell the user to check out the feature branch first.

## Step 2 — Scope the Work

```bash
.hv/bin/hv-review-scope
```

Emits JSON with commits, touched files, referenced IDs, and matched TODO entries. Keep the JSON in memory — Step 4 needs it.

If `commitCount` is 0, tell the user the branch has no commits beyond the base and stop.

## Step 3 — Review (opt-in)

Read `ship.review` from `.hv/config.json`. Default `true`.

If enabled, invoke `hv-review` via the `Skill` tool for this branch. Pass through the verdict:

- **PASS** → continue to Step 4
- **CONCERNS** → surface each concern, then use `AskUserQuestion` to decide:
  - **Header:** `"Concerns"`
  - **Question:** *"Review surfaced N concerns on `<branch>`. How should I proceed?"*
  - **Options** (single-select):
    1. "Address via `/hv-work` (Recommended)" — *"Route the concerns to `/hv-work` as a fix list; rerun `/hv-ship` after."*
    2. "Ship anyway" — *"Proceed with the merge or PR despite the concerns."*
    3. "Stop" — *"Leave the branch as-is; no integration now."*
  - Plain-text fallback: *"Address first, ship anyway, or stop?"*
- **FAIL** → stop. Surface the findings. Let the user fix and rerun `/hv-ship`.

If `ship.review` is `false`, skip this step.

## Step 4 — Build the PR Body

```bash
.hv/bin/hv-ship-body <branch>
```

Prints `## Summary` and `## Items resolved`. Capture the output.

Append a `## Test plan` section. Build the list from the touched files in the scope JSON — one checkbox per meaningful area, not per file. Keep it short (2-5 items). Example:

```markdown
## Test plan

- [ ] Start/stop the timer and confirm badge updates
- [ ] Switch between projects with Cmd+Tab
```

If a scope area is unclear, pick the most visible behavior change. Don't pad with generic checks.

## Step 5 — Pick Strategy

Check `work.mergeStrategy` in `.hv/config.json`.

- If set to `"direct"` or `"pr"` and the user hasn't explicitly overridden in this session, use it silently.
- If unset, or the user said something that suggests they want the other option, use `AskUserQuestion`:
  - **Header:** `"Strategy"`
  - **Question:** *"How should I integrate `<branch>`?"*
  - **Options** (single-select):
    1. Mark whichever matches `work.mergeStrategy` (or `"Direct merge"` if unset) with `(Recommended)`.
    2. The other strategy as a peer option.
    - `"Direct merge"` — *"Merge into main with `--no-ff` and delete the branch."*
    - `"GitHub PR"` — *"Push and `gh pr create` with the body from Step 4."*

Plain-text fallback: *"Ship `<branch>` as a PR or direct merge?"*

## Step 6a — Open a PR

```bash
printf '%s' "$BODY" | .hv/bin/hv-pr <branch> "<short title>"
```

Title rules: derived from the strongest commit subject, ≤70 chars, no `[B##]` tags. `hv-pr` removes any worktree, pushes with `-u`, runs `gh pr create`. Share the PR URL.

## Step 6b — Direct Merge

```bash
printf 'merge: <summary>\n\n- item 1\n- item 2\n' | .hv/bin/hv-merge <branch>
```

`hv-merge` removes any worktree, checks out main, merges `--no-ff`, deletes the branch, and prints the merge commit's short hash. Share the hash.

## Step 7 — Update Status

```bash
.hv/bin/hv-status-remove <branch>
```

Silently clears the entry if one existed. Harmless if not.

## Step 8 — Mark Unfinished Items Complete

Most IDs are already completed by `/hv-work`. This catches manual commits that referenced IDs without closing them.

For each ID in the scope JSON's `referencedIds`:

```bash
.hv/bin/hv-complete <ID> <merge-or-last-commit-hash>
```

`hv-complete` is idempotent — already-completed IDs silent no-op, only typos (IDs absent from `TODO.md` entirely) produce an error. No grep needed.

## Step 8.5 — Learn (Nudge or Auto-Invoke)

Integration is a natural capture moment — the user just finished a cohesive unit of work and is about to move on, so session-specific insights are maximally fresh. Trigger condition (same as `/hv-work`): **2+ items resolved**, OR **≥5 files touched** (from the scope JSON's `touchedFiles`), OR a **hard bug** that took multiple debug cycles to land. Skip when: single trivial item, pure mechanical work, or the branch is a straight dependency bump. Don't trigger if `/hv-learn` already ran this session.

When triggered, branch on `autonomy.level`:

- `"off"` (default) — append one line to the Step 9 report: *"Capture learnings before context fades? Run `/hv-learn` — this cycle has the fresh session context."*
- `"auto"` or `"loop"` — invoke `hv-learn` via the `Skill` tool with a brief naming the resolved IDs and touched files. No prompt.

## Step 9 — Report to User

One compact block.

**PR flow:**

```
PR opened: https://github.com/.../pull/42
Title: fix: timer badge and quick-switch overlay
Resolved: [B01] [F03]
```

**Direct-merge flow:**

```
Merged `hv/demo` into main — commit a1b2c3d
Resolved: [B01] [F03]
```

If `/hv-review` surfaced concerns that the user proceeded through, append them one-liner at the end.

## Step 10 — Loop Continuation

Only when `autonomy.level == "loop"`. After the report, invoke `hv-next` via the `Skill` tool to surface the next item and continue the queue. `/hv-next` reads autonomy too — in loop mode it auto-selects the suggested item and dispatches `/hv-work`.

Loop stops naturally when `/hv-next` reports an empty backlog, a guard fails, or the user interrupts. Skip this step entirely for `"off"` and `"auto"` modes.

## Key Principles

- **Read-only until Step 6.** Review, scoping, and body generation never mutate anything.
- **One integration pass.** Don't split into "review, then ship later" — if review passes, ship.
- **Titles stay clean.** PR titles are for humans; strip `[ID]` tags. The body carries the linkage.
- **`hv-complete` is idempotent on re-completion, strict on typos.** Already-completed IDs silent no-op (exit 0); IDs absent from `TODO.md` entirely produce an error (exit 1). No grep needed.
