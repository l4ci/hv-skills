---
name: hv:ship
description: Bundle completed work on a feature branch into a PR (or direct merge) — extracts commits, resolved item IDs with titles, optionally runs /hv:review, and calls hv-pr or hv-merge. Use on "ship it", "open the PR", "finish this branch", when work is done and you want to integrate.
user-invocable: true
---

# hv:ship — Finish a Feature Branch

Turn the commits on the current feature branch into either a GitHub PR or a direct merge. Optionally runs `/hv:review` first so the diff gets a staff-engineer pass before it leaves your machine.

## Configuration

Read `.hv/config.json`:

- `work.mergeStrategy` — `"pr"` or `"direct"` (falls back to asking if the branch isn't managed by `/hv:work`)
- `ship.review` — `true` (default) runs `/hv:review` before integrating; `false` skips the review

## When to Use

- Feature branch has 1+ commits, work is done, you want to integrate
- After `/hv:work` finished with `mergeStrategy: "pr"` and you want to open the PR now
- Any branch you want reviewed + merged/pushed in one pass

## When NOT to Use

- Work is still in progress → finish implementing via `/hv:work`
- Nothing committed yet → clean up, then come back
- You want to resume a paused branch → `/hv:resume`

## Step 1 — Preflight

If `.hv/bin/hv-ship-body` doesn't exist, invoke `hv:init` via the `Skill` tool, then continue.

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

If enabled, invoke `hv:review` via the `Skill` tool for this branch. Pass through the verdict:

- **PASS** → continue to Step 4
- **CONCERNS** → surface concerns to the user, ask *"Proceed anyway?"* Wait for yes/no
- **FAIL** → stop. Surface the findings. Let the user fix and rerun `/hv:ship`

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

Check `work.mergeStrategy` in `.hv/config.json`. If it's unset or the user hasn't been asked recently, ask:

*"Ship `<branch>` as a PR or direct merge?"*

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

Most IDs are already completed by `/hv:work`. This catches manual commits that referenced IDs without closing them.

For each ID in the scope JSON's `referencedIds`, check if the ID appears as an active bullet — `grep -E '^- \*\*\[<ID>\]' .hv/TODO.md`. If it does, close it:

```bash
.hv/bin/hv-complete <ID> <merge-or-last-commit-hash>
```

Skip IDs that aren't active (already completed or not in TODO.md at all). `hv-complete` errors on missing actives, so always grep first.

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

If `/hv:review` surfaced concerns that the user proceeded through, append them one-liner at the end.

## Key Principles

- **Read-only until Step 6.** Review, scoping, and body generation never mutate anything.
- **One integration pass.** Don't split into "review, then ship later" — if review passes, ship.
- **Titles stay clean.** PR titles are for humans; strip `[ID]` tags. The body carries the linkage.
- **`hv-complete` is idempotent-ish.** Running it on an already-completed ID is a no-op in practice — the helper looks for an active bullet and silently skips if none matches.
