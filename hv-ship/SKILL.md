---
name: hv-ship
description: Bundle completed work on a feature branch into a PR (or direct merge) — extracts commits, resolved item IDs with titles, optionally runs /hv-review, and calls hv-pr or hv-merge. Use on "ship it", "open the PR", "finish this branch", when work is done and you want to integrate.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🚀  hv-ship  ·  bundle work into a PR or merge
  triggers: "ship it", "open the PR"  ·  pairs: hv-review
════════════════════════════════════════════════════════════════════════
```

# hv-ship — Finish a Feature Branch

## Configuration

Read `.hv/config.json`:

- `work.mergeStrategy` — `"pr"` or `"direct"` (falls back to asking if the key is unset)
- `ship.review` — `true` (default) runs `/hv-review` before integrating; `false` skips the review
- `autonomy.level` — `"off"` (default), `"auto"`, or `"loop"`. Controls whether Step 8.5 (Learn) and Step 10 (Loop continuation) nudge or invoke directly.

## When to Use

- Feature branch has 1+ commits, work is done, you want to integrate
- After `/hv-work` finished with `mergeStrategy: "pr"` and you want to open the PR now
- Any branch you want reviewed + merged/pushed in one pass

## When NOT to Use

- Work is still in progress → finish implementing via `/hv-work`
- Nothing committed yet → clean up, then come back
- You want to resume a paused branch → `/hv-next`

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

Confirm a feature branch is checked out:

```bash
.hv/bin/hv-guard-feature-branch
```

Exit 1 (with the helper's stderr message naming the base branch) means the user is on `main`/`master`/`trunk` (or the configured base) — pass the message through and stop. Exit 0 means a feature branch is checked out; continue.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Extract commits & items", description="Read branch commits and resolve linked TODO IDs")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (review skipped via config) get `completed` with the no-op reason in the description.

Phases:

1. *Preflight & branch check* — feature branch confirmed, not on main (Step 1)
2. *Extract commits & items* — branch range read, item IDs resolved (Step 2)
3. *Review* — `/hv-review` runs when `ship.review: true` (Step 3)
4. *CONCERNS routing* — verdict-gated branch selection (Step 4)
5. *Merge or PR* — integration via `hv-merge` or `hv-pr` (Steps 5–8)
6. *Report & nudges* — summary + post-cycle nudges (Steps 9–10)

## Step 2 — Scope the Work

Resolve the active entry's repo (umbrella mode; empty in single-repo projects):

```bash
REPO=$(.hv/bin/hv-status-repo-for <branch>)
```

**Single-repo:**

```bash
.hv/bin/hv-review-scope <branch>
```

**Umbrella mode** (when `$REPO` is non-empty):

```bash
.hv/bin/hv-review-scope --repo "$REPO" <branch>
```

Emits JSON with commits, touched files, referenced IDs, and matched TODO entries. Keep the JSON in memory — Step 4 needs it.

If `commitCount` is 0, tell the user the branch has no commits beyond the base and stop.

## Step 3 — Review (opt-in)

Read `ship.review` from `.hv/config.json`. Default `true`.

If enabled, invoke `hv-review` via the `Skill` tool for this branch. Route on the returned verdict per `references/review-verdict-routing.md` — short summary:

- **PASS** → continue to Step 4.
- **CONCERNS** → surface each concern, then branch on `autonomy.level`:
  - **`"off"` or `"auto"`** — ask via `AskUserQuestion` with three options (Address via `/hv-work` Recommended / Ship anyway / Stop). See the reference for the canonical option labels, descriptions, and plain-text fallback.
  - **`"loop"`** — silently auto-pick "Address via `/hv-work` (Recommended)": invoke `hv-work` via the `Skill` tool with the concerns as the brief, then re-invoke `/hv-ship` once the fixes are committed. Per the authoring convention "routine routing/tagging auto-picks Recommended in loop mode" (see `references/authoring-conventions.md` rule #5). A review FAIL still stops the loop unconditionally as a guard failure.
- **FAIL** → stop. Surface the findings. Let the user fix and rerun `/hv-ship`.

If `ship.review` is `false`, skip this step.

## Step 4 — Build the PR Body

```bash
.hv/bin/hv-ship-body <branch>
```

Prints `## Summary` and `## Items resolved`. Capture the output, then append a `## Test plan` section — 2-5 checkboxes, one per meaningful area (not per file), built from the scope JSON's touched files. Example:

```markdown
## Test plan

- [ ] Start/stop the timer and confirm badge updates
- [ ] Switch between projects with Cmd+Tab
```

If a scope area is unclear, pick the most visible behavior change. Don't pad with generic checks.

## Step 5 — Pick Strategy

Check `work.mergeStrategy` in `.hv/config.json`.

- If set to `"direct"` or `"pr"` and the user hasn't explicitly overridden in this session, use it silently and skip to Step 6a or 6b accordingly.
- If unset, or the user said something that suggests the other option, ask via `AskUserQuestion` using the Strategy picker shape in `references/merge-strategy-gate.md` (Header `"Strategy"`, Question *"How should I integrate `<branch>`?"*, two options with the matching strategy marked `(Recommended)`).

Plain-text fallback: *"Ship `<branch>` as a PR or direct merge?"* — see `references/ask-user-question-fallback.md` for canonical fallback mechanics.

## Step 6a — Open a PR

> **Manual gate — filing a public artifact.** Opening a PR creates externally-visible state. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. The orchestrator may compose the title and body and run the `AskUserQuestion` prompt in Step 5 (Pick Strategy), but the user presses the button there before this step runs. See `references/manual-gates.md`.

```bash
printf '%s' "$BODY" | .hv/bin/hv-pr <branch> "<short title>"
```

Title rules and helper behavior — see `references/merge-strategy-gate.md` (Open a PR). Share the PR URL with the user.

## Step 6b — Direct Merge

```bash
printf 'merge: <summary>\n\n- item 1\n- item 2\n' | .hv/bin/hv-merge <branch>
```

Helper behavior — see `references/merge-strategy-gate.md` (Direct merge). Share the hash with the user.

## Step 7 — Update Status

**Single-repo:**

```bash
.hv/bin/hv-status-remove <branch>
```

**Umbrella mode** (reuse `$REPO` from Step 2; re-derive if out of scope):

```bash
.hv/bin/hv-status-remove --repo "$REPO" <branch>
```

Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella waves MUST pass `--repo` here or the active entry leaks into the next `/hv-next`.

Silently clears the entry if one existed. Harmless if not.

## Step 8 — Mark Unfinished Items Complete

Most IDs are already completed by `/hv-work`. This catches manual commits that referenced IDs without closing them.

For each ID in the scope JSON's `referencedIds`:

```bash
.hv/bin/hv-complete <ID> <merge-or-last-commit-hash>
```

`hv-complete` is idempotent — already-completed IDs silent no-op, only typos (IDs absent from `TODO.md` entirely) produce an error. No grep needed.

## Step 8.5 — Learn (Nudge or Auto-Invoke)

Integration is a natural capture moment — the user just finished a cohesive unit of work and is about to move on, so session-specific insights are maximally fresh.

Apply the post-cycle trigger condition defined in `references/post-cycle-trigger-gate.md` (2+ items resolved / ≥5 files touched / hard bug) — for the files count, use the scope JSON's `touchedFiles` field. Skip for single-item fixes and pure mechanical changes; don't repeat in the same session.

When triggered, branch on `autonomy.level`:

- `"off"` — append one line to the Step 9 report — *"Capture learnings before context fades? Run `/hv-learn` — this cycle has the fresh session context."*
- `"auto"` or `"loop"` — **dispatch `hv-learn` via `Skill` immediately — no prompt, no confirmation, no "want me to" question.** Pass a brief naming the resolved IDs and touched files.

## Step 8.6 — Docs After-Work (Nudge or Auto-Invoke)

Read `docs.afterWork` from `.hv/config.json` (default `false`). If it's `false`, skip this step entirely. Users opt in via `/hv-config` or by running `/hv-docs` manually once.

When the flag is on, apply the same post-cycle trigger condition as Step 8.5 — see `references/post-cycle-trigger-gate.md`.

When triggered, branch on `autonomy.level`:

- `"off"` — append one line to the Step 9 report — *"User-facing changes shipped. Run `/hv-docs` to review and update public docs (after-work mode)."*
- `"auto"` or `"loop"` — **dispatch `hv-docs` via `Skill` immediately — no prompt, no confirmation, no "want me to" question.** Pass a brief naming the resolved IDs and touched files so the after-work flow has the right context.

If `<docs.path>/` doesn't exist or is empty, `/hv-docs`'s after-work flow self-skips (printing a one-line "not yet initialized" notice) — no extra check needed here.

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

## Step 9.5 — Release Nudge

After every successful ship, surface unreleased-commit accumulation so the user can decide whether to cut a release before moving on.

```bash
.hv/bin/hv-release-pending
```

Parse the JSON. If `shouldNudge` is `false`, skip silently. If `lastTag` is empty (no release ever cut), skip silently — the first release is the user's call.

When the nudge fires, append the helper's `message` field as one line in the Step 9 report block (after `Resolved: [...]`). The helper renders the phrasing; the skill just prints it.

This step runs after BOTH PR and direct-merge flows; the trigger is "ship completed", not the integration mechanism.

Skip silently if /hv-review FAILed (Step 3) and the ship was halted — there's nothing to release that hasn't already been released.

## Step 10 — Loop Continuation

Only when `autonomy.level == "loop"`. After the report, **dispatch `hv-next` via `Skill` immediately — no prompt, no confirmation.** `/hv-next` reads autonomy and auto-dispatches `/hv-work`. Loop stops naturally when `/hv-next` reports an empty backlog, a guard fails, or the user interrupts.

## Key Principles

- **Read-only until Step 6.** Review, scoping, and body generation never mutate anything.
- **One integration pass.** Don't split into "review, then ship later" — if review passes, ship.
- **Titles stay clean.** PR titles are for humans; strip `[ID]` tags. The body carries the linkage.
- **`hv-complete` is idempotent on re-completion, strict on typos.** Already-completed IDs silent no-op (exit 0); IDs absent from `TODO.md` entirely produce an error (exit 1). No grep needed.

## References

| Reference | Purpose |
|-----------|---------|
| [`ask-user-question-fallback.md`](../references/ask-user-question-fallback.md) | Plain-text fallback shape for AskUserQuestion-less hosts. |
| [`authoring-conventions.md`](../references/authoring-conventions.md) | Authoring rules shared across SKILL.md files (loop-mode auto-picks, mirror-step threshold). |
| [`banner-preamble.md`](../references/banner-preamble.md) | Banner-print rule shared by every skill. |
| [`manual-gates.md`](../references/manual-gates.md) | Steps that must always be manual regardless of autonomy.level (PR opening, upstream issues, runlog dispatch). |
| [`merge-strategy-gate.md`](../references/merge-strategy-gate.md) | Merge-strategy decision UX (Direct vs PR) plus helper invocations. |
| [`post-cycle-trigger-gate.md`](../references/post-cycle-trigger-gate.md) | Trigger condition for post-cycle nudges (2+ items / ≥5 files / hard bug). |
| [`review-verdict-routing.md`](../references/review-verdict-routing.md) | PASS / CONCERNS / FAIL routing for `/hv-review` consumers. |
