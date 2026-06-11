---
name: hv-ship
description: Bundle completed work on a feature branch into a PR (or direct merge) — extracts commits, resolved item IDs with titles, optionally runs /hv-review, and calls hv-pr or hv-merge. Use on "ship it", "open the PR", "finish this branch", when work is done and you want to integrate. Also supports --undo (guided rollback of the last cycle on the base branch, replaces /hv-undo) and --docs (public-docs maintenance, replaces /hv-docs). Use --undo on "roll back the last cycle", "revert that merge". Use --docs on "/hv-docs", "update docs"; auto-invoked post-cycle when docs/ exists.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🚀  hv-ship  ·  bundle work into a PR or merge
  triggers: "ship it", "open the PR"  ·  pairs: hv-review
════════════════════════════════════════════════════════════════════════
```

## Step 0 — Mode Dispatch

Read `$ARGUMENTS` (the slash-command's free-text args). Route on the first flag present:

| Args contain | Route to | Purpose |
|---|---|---|
| `--undo` | **Undo Mode** (Steps U1–U5) | Guided rollback of the last `/hv-work` cycle on the base branch. Replaces the standalone `/hv-undo`. |
| `--docs` (or `--docs restructure`) | **Docs Mode** (Steps D1+) | Maintain public user-guide under `<docs.path>/`. Replaces the standalone `/hv-docs`. |
| (no recognized flag) | **Normal Ship Mode** (Steps 1–10) | Bundle a feature branch into a PR or direct merge. |

In Normal Ship Mode, the final step (`Step 8.6`) inline-runs Docs Mode's after-work flow when `docs.afterWork: true` AND the post-cycle trigger fires — no separate skill dispatch.

`--undo` is **terminal** — it never falls through to Docs Mode auto-trigger (rolling back a cycle and then syncing docs would be incoherent).

# hv-ship — Finish a Feature Branch

## Configuration

Read `.hv/config.json`:

- `work.mergeStrategy` — `"pr"` or `"direct"` (falls back to asking if the key is unset)
- `ship.review` — `true` (default) runs `/hv-review` before integrating; `false` skips the review
- `ship.secondOpinion` — `false` (default) skips the fresh-eyes gate; `true` runs a no-prior-context adversarial review after `/hv-review` passes
- `ship.qa` — `false` (default) skips product QA; `true` runs `/hv-qa run` after `/hv-review` (and `secondOpinion`) and before merge/PR. Routed per `qa.gate` (`"advisory"` reports only; `"blocking"` halts on FAIL).
- `autonomy.level` — `"off"` (default), `"auto"`, or `"loop"`. Controls whether Step 8.5 (Learn) and Step 10 (Loop continuation) nudge or invoke directly.
- `docs.path` — relative path to the docs folder used by Docs Mode (default `"docs"`)
- `docs.autoCreate` — whether Docs Mode's after-work flow auto-writes without per-batch approval (default `false`)
- `docs.afterWork` — whether `/hv-work` Step 13.6 and `/hv-ship` Step 8.6 trigger Docs Mode's after-work flow (default `false`)

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

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Preflight & branch check* — feature branch confirmed, not on main (Step 1)
2. *Extract commits & items* — branch range read, item IDs resolved (Step 2)
3. *Review* — `/hv-review` runs when `ship.review: true` (Step 3)
4. *Second-opinion gate* — fresh-eyes adversarial review when `ship.secondOpinion: true` (Step 3.5)
5. *QA gate* — product `/hv-qa run` when `ship.qa: true` (Step 3.75)
6. *CONCERNS routing* — verdict-gated branch selection (Step 4)
7. *Merge or PR* — integration via `hv-merge` or `hv-pr` (Steps 5–8)
8. *Report & nudges* — summary + post-cycle nudges (Steps 9–10)

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

If enabled, invoke `hv-review` via the `Skill` tool for this branch. The review brief carries the silent-failure-hunter rubric (`references/silent-failure-hunter.md`) as the silent-failure rubric item (the dedicated SILENT-FAIL check in /hv-review's Stage 2 brief) — `SILENT-FAIL` flags surface as CONCERNS in the same verdict block as intent / convention / quality concerns; no separate dispatch. Route on the returned verdict per `references/review-verdict-routing.md` — short summary:

- **PASS** → continue to Step 4.
- **CONCERNS** → surface each concern, then branch on `autonomy.level`:
  - **`"off"` or `"auto"`** — ask via `AskUserQuestion` with three options (Address via `/hv-work` Recommended / Ship anyway / Stop). See the reference for the canonical option labels, descriptions, and plain-text fallback.
  - **`"loop"`** — silently auto-pick "Address via `/hv-work` (Recommended)": invoke `hv-work` via the `Skill` tool with the concerns as the brief, then re-invoke `/hv-ship` once the fixes are committed. Per the authoring convention "routine routing/tagging auto-picks Recommended in loop mode" (see `references/authoring-conventions.md` rule #5). A review FAIL still stops the loop unconditionally as a guard failure.
- **FAIL** → stop. Surface the findings. Let the user fix and rerun `/hv-ship`.

**Capture the choice.** When the verdict is CONCERNS and the user picks via `AskUserQuestion`, remember the answer in this cycle's working state as `REVIEW_CHOICE` (one of `address`, `ship-anyway`, `stop`). Step 3.5 reads `REVIEW_CHOICE` to skip the second-opinion gate when the user already accepted CONCERNS; Step 9 reads it to decide whether to append the "concerns the user proceeded through" line. Loop mode auto-picks `address` per the verdict-routing reference.

If `ship.review` is `false`, skip this step.

## Step 3.5 — Second-Opinion Gate (opt-in)

Read `ship.secondOpinion` from `.hv/config.json`. Default `false`. If `false`, skip this step entirely.

When `true`, dispatch a fresh subagent with **no prior conversation context** and give it only the diff plus the stated goal. The /hv-review reviewer (Step 3) shares context with the work it produced — the same conventions, the same KNOWLEDGE bullets, the same plan. A reviewer with that context naturalizes blind spots. A reviewer without it must reason from the diff alone, catching what the contextualized reviewer normalized.

Skip the gate when any of these apply (no work to second-opinion):

- Step 3 was skipped (`ship.review: false`) AND the user hasn't explicitly asked for a second opinion this session — the trade-off is the user already opted out of pre-merge review.
- Step 3 returned **FAIL** — already stopped above.
- Step 3 returned **CONCERNS** and `REVIEW_CHOICE == ship-anyway` — they already accepted residual risk; a second adversarial pass would re-litigate the decision.

Otherwise, run the gate:

```bash
.hv/bin/hv-second-opinion-brief [--repo "$REPO"] <branch>
```

(Pass `--repo "$REPO"` in umbrella mode using the value from Step 2.)

The helper emits a markdown brief that includes only the goal (resolved item titles + their TODO entry text), the commit list, and per-file diff content — no KNOWLEDGE, no DECISIONS, no plan, no conventions. That minimal context is the entire point.

Dispatch the brief to a **fresh subagent**:

- `Agent` tool, `subagent_type: "general-purpose"` (default — fresh context, no inherited project memory)
- `model: "sonnet"` — the MVP is same-model-fresh-context per F04's note that cross-model (Codex/Gemini) is the gold standard but not the cheap MVP
- Prompt: the brief's stdout verbatim
- `description: "Second-opinion review of <branch>"`

The agent returns a markdown report. Parse the last non-empty line for the all-caps verdict (`PASS` / `CONCERNS` / `FAIL`).

Route the verdict per `references/review-verdict-routing.md` — same contract as Step 3:

- **PASS** → continue to Step 4 silently.
- **CONCERNS** → surface each concern with the label "Second-opinion concerns" (per the carrier-label convention in `references/review-verdict-routing.md`), then route per the reference's Consumer routing table.
- **FAIL** → stop. Surface the findings. The user fixes via `/hv-work` or `/hv-debug` and reruns `/hv-ship`. Loop mode treats a second-opinion FAIL as a guard failure (loop stops), same as a /hv-review FAIL.

The gate runs after Step 3 because there's no point burning a second-opinion roundtrip on a diff that already failed the contextualized review. It runs before Step 4 because surfaced concerns may change the PR body's framing.

## Step 3.75 — QA Gate (opt-in)

Read `ship.qa` from `.hv/config.json`. Default `false`. If `false`, skip this step entirely.

`/hv-review` (Step 3) and the second-opinion gate (Step 3.5) answer *"does the diff make sense"* — both reason from commits and diff. They do not run the product. `/hv-qa` answers the orthogonal question — *"does the product actually work"* — by executing the per-target strategy in `.hv/qa/<target>.md` (Playwright, smoke, lighthouse, axe, ZAP, contract tests, whatever the target's strategy declares). The two gates are deliberately separate; this step layers QA in after diff-level review without merging them.

Skip the gate when any of these apply (no work to QA, or already short-circuited):

- Step 3 returned **FAIL** — already stopped above.
- Step 3 returned **CONCERNS** and `REVIEW_CHOICE == ship-anyway` — the user already accepted residual risk; QA findings on the same diff are unlikely to change that decision. Loop mode picks `address` instead, which never reaches this step.
- `.hv/qa/` is empty for the active target (single-repo: no `.hv/qa/*.md`; umbrella: no `.hv/qa/<REPO>.md`) — surface a one-line note *"`ship.qa: true` but no QA strategy for `<scope>`. Run `/hv-qa first-run` to bootstrap, or set `ship.qa: false` to skip."* and continue to Step 4 without running QA.

Otherwise, invoke `/hv-qa run` via the `Skill` tool, scoped to the resolved repo in umbrella mode:

- Single-repo: `Skill(skill="hv-skills:hv-qa", args="run")`.
- Umbrella: `Skill(skill="hv-skills:hv-qa", args="run --repo $REPO")`.

`/hv-qa` emits one of three verdicts on its final line, all caps — `PASS`, `CONCERNS`, or `FAIL`. Route per `references/review-verdict-routing.md`, **gated by `qa.gate`**:

| `qa.gate` | `PASS` | `CONCERNS` | `FAIL` |
|---|---|---|---|
| `"advisory"` (default) | continue to Step 4 silently | surface findings with carrier label *"QA concerns:"*; continue to Step 4 | surface findings with carrier label *"QA concerns:"*; continue to Step 4 (the ship is not blocked — advisory means advisory) |
| `"blocking"` | continue to Step 4 silently | surface findings, branch on `autonomy.level` (same shape as Step 3): off/auto → `AskUserQuestion` Address-via-`/hv-work` (Recommended) / Ship anyway / Stop; loop → auto-pick `address` and re-invoke `/hv-work` then `/hv-ship` | stop; surface findings; user fixes via `/hv-work` or `/hv-debug` and reruns `/hv-ship`. Loop mode treats `FAIL` as a guard failure (loop stops). |

Surface QA concerns with the carrier label *"QA concerns:"* per `references/review-verdict-routing.md` (Carrier-label override) — keeps them visually distinct from `/hv-review` concerns and second-opinion concerns in a single ship pass.

The gate runs after Step 3.5 because there's no point spinning up infra-bound QA runs on a diff that the contextualized or fresh-eyes reviewers already failed. It runs before Step 4 because QA findings may change the PR body's framing (test-plan adjustments, follow-up tasks). When `INFRA-FAIL` returns from `/hv-qa` (dev server / creds / binary missing), treat it as advisory — surface the missing requirements as a note and continue. QA can't run, but ship shouldn't break because the dev server happened to be down.

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

**Run the self-audit before Step 5.** The PR body lands on GitHub/GitLab and stays in the PR history; the `## Summary` text is the first thing a reviewer reads. Apply the rule sheet and self-audit pass in `references/humanizing-prose.md` to the assembled body silently — show the post-audit draft, not the pre-audit one.

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

## Step 6c — Close Upstream Issues (Direct-Push Path)

This step runs only on the **direct-merge path** (after `hv-merge` returns a commit hash). Skip entirely on the PR path — `hv-ship-body` already emits `Closes #N` lines into the PR body, and GitHub/GitLab auto-close the issues on PR merge.

**1. Identify candidates.**

From the scope JSON's `referencedIds` (already in memory from Step 2), call:

```bash
.hv/bin/hv-issues-imported --open-only
```

`--open-only` drops entries whose upstream issue is already closed so the gate doesn't surface no-ops. Parse the JSON array; filter to entries whose `item_id` is in the shipped item list (the resolved IDs from Step 2). If the filtered list is empty, skip the rest of this step silently.

**2. Manual gate.**

> **Manual gate — closing public upstream issues.** Closing the issues posts a tracking comment and changes their state on the remote — externally-visible. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. The merge already happened; this step decides whether to close the upstream issues too. See `references/manual-gates.md`.

**3. Ask the user.**

Invoke `AskUserQuestion` (single-select, ≤4 options):

- Header: `"Close"`
- Question: *"Close N upstream issue(s) tied to the shipped items? (`<comma-separated list of #N>`)"*
- Options: `"Yes, close all"`, `"Pick subset"`, `"No, leave open"`

This gate is **always manual** — never auto-picked in loop mode. Stop the loop here and wait for the user's answer.

**4. On "Yes, close all":** dispatch parallel `hv-issues-close` calls (one per candidate, all in a single batch of tool calls):

```bash
.hv/bin/hv-issues-close --issue <N> --commit <merge-sha> --item <ID> [--repo <name>]
```

Pass `--repo` only in umbrella mode (`$REPO` non-empty from Step 2).

**5. On "Pick subset":** invoke a second `AskUserQuestion` (multiSelect, ≤4 candidates per call; chunk if N>4):

- Header: `"Pick issues"`
- Question: *"Which issue(s) should be closed?"*
- Options: one entry per candidate formatted as `"#N (item <ID>)"`

Then dispatch parallel `hv-issues-close` calls for each selected entry as in step 4.

**6. On "No, leave open":** print:

```
Skipping upstream issue close — N issue(s) left open. Run `gh issue close <N>` / `glab issue close <N>` manually if desired.
```

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

`hv-complete` is idempotent — already-completed IDs silent no-op, only typos (IDs absent from `BACKLOG.md` entirely) produce an error. No grep needed.

## Step 8.5 — Learn (Nudge or Auto-Invoke)

Integration is a natural capture moment — the user just finished a cohesive unit of work and is about to move on, so session-specific insights are maximally fresh.

Run the post-cycle choreography in `references/post-cycle-trigger-gate.md` with these parameters:

- **Nudge (`"off"`):** append one line to the Step 9 report — *"Capture learnings before context fades? Run `/hv-learn` — this cycle has the fresh session context."*
- **Target (`"auto"`/`"loop"`):** **dispatch `hv-learn` via `Skill` immediately — no prompt, no confirmation, no "want me to" question.**
- **Brief:** the resolved IDs and touched files.

## Step 8.6 — Docs After-Work (inline)

Run the post-cycle choreography in `references/post-cycle-trigger-gate.md` — **inline variant** — with these parameters:

- **Config flag:** `docs.afterWork` (default `false`). Users opt in via `/hv-config` or by running `/hv-ship --docs` manually once.
- **On trigger:** **inline-run Docs Mode's after-work flow** — Steps D-A1 through D-A6 in this file. Do not dispatch a separate skill; the docs flow is part of /hv-ship. No `autonomy.level` branch here — Step D-A5's approval gate is the user checkpoint.
- **Context:** the resolved item IDs and touched files from the cycle's scope JSON.

If `<docs.path>/` doesn't exist or is empty, the after-work flow self-skips (printing a one-line "not yet initialized" notice) — no extra check needed here.

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

If `REVIEW_CHOICE == ship-anyway`, append the concerns one-liner at the end of the report.

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

## Undo Mode (--undo)

> Entered via `/hv-ship --undo`. The inverse of `/hv-work`'s commit + completion steps: reset the most recent `merge: …` commit on the base branch and restore the resolved items as TODO entries under their original type sections. The safe default is dry-run — every invocation previews what would change before touching anything. PR-mode cycles are refused with a manual-recovery pointer (the merge happened upstream, not locally). Post-merge commits on the base branch are refused by default; `--allow-post-merge` is opt-in. The confirmation gate is manual and never auto-picked in loop mode — `git reset --hard` is destructive past `git reflog`'s window.

The /hv-ship banner already printed at Step 0; Undo Mode runs from the same skill invocation.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Detect cycle* — most recent `merge: ` commit on base branch identified (Step U1 dry-run)
2. *Surface preview* — dry-run output rendered verbatim to user (Step U2)
3. *Confirm* — manual `AskUserQuestion` gate (Step U3)
4. *Apply rollback* — engine runs with `--force`, base resets, items restored (Step U4)
5. *Report* — summary line printed; no post-cycle nudges (Step U5)

### Step U1 — Detect Cycle (Dry-Run Preview)

Run the engine with no `--force` flag; it defaults to dry-run and prints what would change:

```bash
.hv/bin/hv-undo
```

Exit codes:

- **0** — dry-run printed successfully. Surface stdout verbatim to the user, then continue to Step U2.
- **1** — precondition error (no cycle on base, subject doesn't match `^merge: `, post-merge commits without `--allow-post-merge`, invalid arg, PR-mode cycle, not on base branch). Surface stderr verbatim and **stop** — do not proceed to Step U2.
- **2** — dirty tree. Print *"Working tree is dirty — commit, stash, or discard before /hv-ship --undo can run."* and stop.

If the user wants to target a specific cycle other than the most recent, they invoke `.hv/bin/hv-undo --cycle <hash>` directly; the slash-command default is always the most recent.

If the base branch has commits past the cycle merge, `hv-undo` refuses by default. Resolve manually (`git reset` to before those commits) or re-run with `--allow-post-merge` to discard them. Surface the helper's stderr verbatim — no extra prompting.

### Step U2 — Surface the Plan

Render the helper's stdout to the user verbatim. The preview shows the merge commit being reset, the items being restored to BACKLOG.md, and any caveats (e.g. post-merge commits flagged for discard when `--allow-post-merge` is in play).

### Step U3 — Confirmation Gate

Use a single `AskUserQuestion` call. Show the dry-run output above the question so the user can review the plan before committing.

- **Header:** `"Apply"`
- **Question:** `"Apply this rollback plan?"`
- **Options** (single-select):
  1. `"Apply (Recommended)"` — runs `.hv/bin/hv-undo --force`. Resets the base branch and restores the TODO entries.
  2. `"Cancel"` — print *"No changes."* and stop; nothing is written.

Plain-text fallback (when `AskUserQuestion` is not available): ask once — *"Apply rollback? (yes/no)"* — `yes` → Apply; anything else → Cancel.

> Per the `hv-init` authoring convention "manual gates that are destructive or file public artifacts are never auto-invoked regardless of autonomy", Undo Mode's confirmation gate always surfaces to the user — loop mode does not accelerate it. `git reset --hard` is destructive and unrecoverable past `git reflog`'s window; the user must confirm.

### Step U4 — Apply (when not Cancel)

```bash
.hv/bin/hv-undo --force
```

(Or `.hv/bin/hv-undo --force --allow-post-merge` when the user opted into discarding post-merge commits in Step U1 — but Step U1 errored out and re-routed for that case; the simpler `--force` is the common path.)

Pass the helper's stdout to the user verbatim. Then continue to Step U5.

### Step U5 — Report

Print the engine's final summary line as-is. Do **not** invoke `/hv-learn`, `/hv-ship --docs`, `/hv-refactor`, or `/hv-next` — Undo Mode is terminal. The user re-runs `/hv-next` themselves to see the restored backlog.

### When to Use Undo Mode

Use `/hv-ship --undo` when:

- The cycle landed but the implementation turned out wrong on closer inspection.
- A reviewer flagged a regression and the simplest fix is "roll back, redesign, re-cycle".
- The cycle resolved an item that should not have been resolved (premise was wrong; item should be re-opened for redesign).
- A `/hv-go` cycle landed something the user didn't actually want — `/hv-ship --undo` is the fast inverse.

`/hv-ship --undo` is **not** for:

- Undoing a cycle whose merge was a PR — use `gh pr close <num>` for open PRs, `git revert` for merged PRs.
- Undoing more than one cycle at a time — invoke twice.
- Editing what landed — that's `/hv-go` or a new `/hv-capture` + `/hv-work`.

### Undo Mode Rules

- Default is dry-run; `--force` is the only way to apply changes.
- The base-branch + clean-tree preconditions are enforced by the helper; never bypass them.
- Post-merge commits on the base branch refuse by default; `--allow-post-merge` is opt-in.
- Manual confirmation gate; loop mode does not auto-pick.
- Terminal mode — no post-cycle nudges. The user re-orients with `/hv-next`.

## Docs Mode (--docs)

*Docs Mode banner already printed at Step 0; this section runs from the same /hv-ship invocation.*

### Modes

| Detected when | Mode |
|---|---|
| `<docs.path>/` doesn't exist or is empty | First-run (discovery + scaffold) |
| Invoked by `/hv-work` / `/hv-ship` post-cycle | After-work (propose doc updates) |
| Invoked by `/hv-refactor`, or `/hv-ship --docs restructure` | Restructure (audit + reorganize) |
| Manual invoke, no signal | First-run if `<docs.path>/` missing; else after-work in manual mode (gate bypassed — see Step D1) |

If invoked in a not-yet-implemented mode, print one line citing the slice and exit cleanly.

Docs Mode and `/hv-qa` share the three-mode skeleton (scaffold / after-work / audit) and intentionally diverge on artifact root, gate strength, and authoring tier — see `references/three-mode-skill-shape.md`.

> **Architecture rule — one `docs/` tree per project.** A single hv-skills project has exactly one `docs/` tree, located either at the umbrella root or inside one chosen sub-repo (recorded via `docs.repo` config when needed). Forbids: multiple `docs/` trees inside a single hv-skills project, per-sub-repo `docs/` *in addition to* an umbrella `docs/`, Docs Mode writing to more than one target. Permits: a single `docs/` at the umbrella root (cross-cutting docs); a single `docs/` inside one chosen sub-repo (when that sub-repo owns the project's public surface); cross-cutting documentation living in the chosen tree.
>
> **`docs/` is the public surface.** It's consumer-facing — contributor and contract content lives in the skill that owns it (`hv-*/SKILL.md`), not in a parallel reference file. Cross-refs from `docs/` and `README.md` point at `docs/` pages or specific SKILL.md files, never at a centralized internals doc.

### Step D1 — Preflight & First-Run Detection

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

Read `docs.path` from `.hv/config.json` (default `"docs"`). Check whether `<docs.path>/` exists and is non-empty:

```bash
[ -d "<docs.path>" ] && [ -n "$(ls -A "<docs.path>" 2>/dev/null)" ]
```

- **Empty or missing** → continue with first-run mode (Steps D2–D6).
- **Non-empty** → not a first-run scenario. Branch on `docs.afterWork`:
  - **Already `true`** → After-work mode is already enabled. **Route to the After-work sub-flow (Step D-A1 onward) as manual mode** — the user re-invoked `/hv-ship --docs` precisely to check whether docs are still aligned with recent changes, which is what after-work does. Print one line first so the user sees the routing: *"After-work mode is on. Checking docs against changes since the last `docs:` commit."* Then proceed to Step D-A1. **Manual invocation bypasses the post-cycle trigger gate** (`references/post-cycle-trigger-gate.md`) — the user running `/hv-ship --docs` by hand is itself the trigger, so the gate's condition never applies on this path. There's also no upstream cycle brief, so Step D-A6 omits its `Resolves:` line.
  - **`false` (default)** → ask via `AskUserQuestion`:
    - **Header:** `"After-work"`
    - **Question:** *"`<docs.path>/` is initialized but `docs.afterWork` is off. Enable after-work mode? `/hv-work` and `/hv-ship` will then auto-invoke `/hv-ship --docs` to propose doc updates after each cycle."*
    - **Options** (single-select):
      1. *"Enable (Recommended)"* — write `docs.afterWork: true` to `.hv/config.json`, print *"After-work mode enabled. `/hv-work` and `/hv-ship` will now invoke `/hv-ship --docs` post-cycle."*, exit.
      2. *"Leave off"* — exit without changes.
    - Plain-text fallback: ask once. Default to "Leave off" if ambiguous (opt-in semantics — never silently flip a config flag the user didn't ask for).

The config write uses the shared helper:

```bash
.hv/bin/hv-config-set docs.afterWork true
```

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Mode select* — first-run / after-work / restructure resolved from `docs.path` state + config (Step D1)
2. *Inspect docs/* — current pages and structure read (Step D2)
3. *Discover topics* — touched files + recent commits scanned for doc-worthy changes (Step D3)
4. *Propose plan* — doc updates drafted and shown to user (Step D4)
5. *Write/update* — pages created or edited (Step D5)
6. *Cross-link* — internal links and indices updated (Step D6)
7. *Report* — summary printed, autonomy nudges fired

### Step D2 — Read Project Signals

In a **single parallel batch** (one tool-call response, multiple reads), gather:

- `README.md` (or `README.rst`) at repo root — if present
- Manifest files at repo root: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`, `setup.py`, `*.gemspec`, `Gemfile` — read whichever exist
- Top-level `bin/` listing (one level only) — entry points hint at CLI surface
- Top-level `src/` listing (one level only) — high-level module shape; don't read contents
- Recent git history: `git log --oneline -20`
- Root-level `.md` files other than README (CHANGELOG, CONTRIBUTING, LICENSE) — note presence; don't duplicate

Don't dump the contents to the user — form a picture and use what's relevant in Step D3.

### Step D3 — Form Hypothesis (silent)

Internally classify the project type. Pick one (or note "mixed" if genuinely ambiguous):

- **CLI tool** — `bin/*` entry points, manifest declares CLI commands, README focuses on `command --flag` examples
- **Library** — exports public functions/classes, README has API examples, no CLI
- **Web app / service** — server entry point, route definitions, deployment-shaped manifest
- **Plugin / extension** — manifest declares it as a plugin (e.g., `claude-plugin/plugin.json`), pairs with a host system
- **Framework** — provides primitives others build on; README has "getting started" + "core concepts" structure
- **Data project** — pipelines, notebooks, dataset-shaped repo

Identify the **user-facing surface** for the chosen type — what consumers actually interact with. For a CLI tool, the commands and flags. For a library, the public API. For a web app, the routes / UI. For a plugin, the host-system integration points.

**Don't dump this analysis to the user.** It shapes the proposal in Step D4.

### Step D4 — Propose Tailored Tree

Output a clear proposal as plain markdown — file tree under `<docs.path>/`, one-line purpose per file. Example shape (the actual tree depends on the project type and surface from Step D3 — tailor it):

```
<docs.path>/
├── README.md            # landing page + table of contents
├── getting-started.md   # 5-minute first-run walkthrough
├── usage/
│   ├── basics.md        # core workflow
│   └── <command>.md     # one page per major user surface
├── configuration.md     # if config exists
└── examples.md          # only if patterns are non-obvious
```

Then ask via `AskUserQuestion`:

- **Header:** `"Scaffold"`
- **Question:** *"Approve this docs structure?"*
- **Options** (single-select):
  1. *"Approve as proposed (Recommended)"*
  2. *"Edit"* — free text. User describes changes; revise the proposal and re-ask Step D4.
  3. *"Minimal — `README.md` + `getting-started.md` only"*
  4. *"Cancel"* — don't scaffold; exit.

Plain-text fallback: ask once in prose; default to Recommended on ambiguity, naming it explicitly. See `references/ask-user-question-fallback.md`.

On **Cancel** — print *"Scaffold cancelled. Run `/hv-ship --docs` again whenever you're ready."* and exit.

#### Page-naming convention

The tailored tree should follow the spine + usage + reference layout documented in `references/docs-conventions.md` (page-naming section). When the tailored proposal doesn't fit (e.g., a CLI tool with no usage phases, or a library with API references but no walkthroughs), describe the deviation in one line in your proposal — *"This project ships only reference material; no `usage/` pages proposed."* — so the user sees the conscious choice.

### Step D5 — Scaffold on Approval

For each proposed file, write it with:

- Title heading (`# Page Title`)
- One-line purpose comment (HTML comment or italics — match the convention you see in the existing project's `.md` files)
- Honest empty section stubs (`## What you'll learn`, `## Steps`, etc., depending on page type) — **no LLM-hallucinated content**

Write `<docs.path>/README.md` as a real index — TOC linking every other proposed page. This is the only page that ships with non-stub content (the TOC itself).

Seed `.docsignore` at repo root if it doesn't already exist — use the template in `references/docs-conventions.md` (`.docsignore` seed section). Make all writes idempotent — never overwrite an existing file.

After scaffolding succeeds, set `docs.afterWork: true` in `.hv/config.json` automatically — the user just opted into the docs flow by approving the scaffold, so the after-work gate flips on with the same approval. No separate question needed. Use `.hv/bin/hv-config-set docs.afterWork true` (same pattern as Step D1's manual-toggle branch). Skip silently if `docs.afterWork` is already `true`.

### Step D6 — Closing Summary

Print a short summary block:

```
Scaffolded <docs.path>/ — N pages.

Files:
  - <docs.path>/README.md  (index / TOC)
  - <docs.path>/getting-started.md
  - <docs.path>/usage/basics.md
  - ...

Next:
  Run /hv-work on a feature, then /hv-ship --docs will fill in pages from the changes.
  Or write <docs.path>/getting-started.md yourself first to set the voice.
```

### Docs After-Work Sub-Flow

This flow is invoked by `/hv-work` Step 13.6 dispatching `/hv-ship --docs`, and `/hv-ship` Step 8.6 running Docs Mode inline — those steps gate on `docs.afterWork` (default `false`); when on, they hand off the resolved item IDs + touched files. **Manual invocation** (`/hv-ship --docs`) also runs this flow when `<docs.path>/` exists and the flag is on; on that path the trigger gate is bypassed — see Step D1.

### Step D-A1 — Trigger Gate

For **post-cycle dispatches** (called from `/hv-work` Step 13.6 via Skill dispatching `hv-ship --docs`, or `/hv-ship` Step 8.6 running inline), apply the post-cycle trigger condition defined in `references/post-cycle-trigger-gate.md`.

**Manual entry bypasses the gate — see Step D1.** When Step D1 routed here, skip the trigger condition and proceed straight to Step D-A2.

If `<docs.path>/` doesn't exist or is empty, **don't run this flow** — print one line: *"`/hv-ship --docs` not yet initialized — run `/hv-ship --docs` to scaffold."* and exit. Don't auto-scaffold mid-cycle.

### Step D-A2 — Gather Context

In a **single parallel batch** (one tool-call response, multiple reads), gather:

- `git log --oneline <last-docs-marker>..HEAD` — boundary is the last `docs:` commit's SHA. Fall back to last 20 commits if no `docs:` commit exists yet.
- `git diff <last-docs-marker>..HEAD -- <changed-paths>` — filtered through `.docsignore` (Layer-1 filter; the orchestrator reads `.docsignore` and skips matching paths from the diff).
- Current `<docs.path>/` tree (one-level listing) and each existing page's H1+H2 outline (`grep -E '^#{1,2} ' <page>`).

### Step D-A3 — Classify Changes

For each non-ignored diff file, decide: user-facing surface change (doc-relevant) vs internal-only refactor/test/build (not doc-relevant).

**Doc-relevant** heuristics:

- Changes to `bin/*` entry points
- Public API exports
- Route handlers
- CLI flag definitions
- Config-key surface
- Plugin-manifest entries
- README-shaped behavior

**Internal-only** heuristics:

- Tests
- Build scripts
- Internal helpers not re-exported
- Refactors with no visible behavior change
- CI config, lint config
- Dependency bumps

LLM judgment is the primary signal; the heuristics are hints, not hard gates.

If **no** files classify as doc-relevant after this pass, print one line (*"No user-facing changes since last `docs:` commit. Skipping."*) and exit cleanly.

### Step D-A4 — Map to Pages + Draft Edits

Per doc-relevant change, pick a target page from `<docs.path>/`:

- An existing page that covers the surface (e.g., `usage/<command>.md` for a CLI flag change).
- Or `*needs new page*` — propose a path under `<docs.path>/` with one-line rationale; never auto-create a page in propose mode.

Draft a concrete before/after fragment per page using a simple unified-diff-shaped block:

```
<docs.path>/usage/foo.md
- old line or section
+ new line or section
```

Drafts should reference real file/section anchors (e.g., the H2 heading the edit lands under). No hallucinated content; if no concrete edit can be drafted, mark the entry "*needs prose — author yourself*" and skip it from the apply set.

**Run the self-audit before Step D-A5 displays the drafts.** Doc-page edits ship to `<docs.path>/` and are the project's public surface. Apply the rule sheet and self-audit pass in `references/humanizing-prose.md` to every `+` line in the draft fragments silently — show the post-audit drafts, not the pre-audit ones. The audit applies to *added* prose only; `-` lines are existing content and stay untouched.

### Step D-A5 — Approval Gate

Show all drafts in one batch (plain markdown — same as the first-run proposal in Step D4). Then ask via `AskUserQuestion`:

- **Header:** `"Docs"`
- **Question:** *"Apply these doc updates?"*
- **Options** (single-select):
  1. *"Apply all (Recommended)"*
  2. *"Apply selectively"* — free text. User lists the page paths to apply; revise the apply set and proceed.
  3. *"Skip"* — don't write anything; exit cleanly. Doesn't advance the `docs:` marker.
  4. *"Cancel"* — same as Skip in this slice; reserved for future-divergent semantics.

Plain-text fallback: ask once in prose; default to Recommended on ambiguity, naming it explicitly. See `references/ask-user-question-fallback.md`.

### Step D-A6 — Commit

Write the chosen edits idempotently (don't overwrite unrelated content). Then a **single** `docs:` commit. Message format:

```
docs: <one-line summary>

- <page>: <one-line per-page change>
- <page>: <…>

Resolves: [B07], [F03]
```

`Resolves:` lists the item IDs of the work cycle that triggered this run (passed in by the calling skill's brief). If no IDs were passed (manual `/hv-ship --docs` invocation), omit the `Resolves:` line.

`autoCreate: true` (auto-write path, default `false`) skips the per-batch approval gate in Step D-A5 — drafts are written and committed directly. The propose-mode flow above still runs for review/manual-invoke.

### Docs Mode Principles

- **First-run is interactive — never auto-scaffold.** Always go through Step D4's `AskUserQuestion` before writing.
- **Stubs are honest empty sections, not hallucinated content.** The user fills the substance; the skill provides the spine.
- **`<docs.path>/README.md` is the spine.** Every other page links from there.
- **`.docsignore` is the safety boundary.** Seeded with safe defaults; user extends.
- **Don't narrate the discovery analysis.** It shapes the proposal silently.
- **After-work runs in propose mode by default.** `docs.autoCreate: false` (the default) means every batch goes through user approval; `true` skips the approval gate and commits directly.

### When to Use Docs Mode

- Manually: `/hv-ship --docs` runs the manual entry. Behavior depends on `<docs.path>/` state and `docs.afterWork`:
  - Missing/empty `<docs.path>/` → first-run flow (Step D1 onward) — interactive scaffold.
  - Existing `<docs.path>/` AND `docs.afterWork: true` → after-work flow in manual mode — check docs against changes since last `docs:` commit. Trigger gate bypassed — see Step D1.
  - Existing `<docs.path>/` AND `docs.afterWork: false` → ask whether to enable after-work mode (per Step D1's `AskUserQuestion`).
- Auto-invoked by `/hv-work` Step 13.6 (via Skill tool dispatching `hv-ship --docs`) when `docs.afterWork: true` AND the post-cycle trigger fires.
- Inline at `/hv-ship` Step 8.6 when ship-cycle conditions match (same flag set).
- For restructure: `/hv-ship --docs restructure` runs the audit + reorganize flow.

## Key Principles

- **Read-only until Step 6.** Review, scoping, and body generation never mutate anything.
- **One integration pass.** Don't split into "review, then ship later" — if review passes, ship.
- **Titles stay clean.** PR titles are for humans; strip `[ID]` tags. The body carries the linkage.
- **`hv-complete` is idempotent on re-completion, strict on typos.** Already-completed IDs silent no-op (exit 0); IDs absent from `BACKLOG.md` entirely produce an error (exit 1). No grep needed.

## References

| Reference | Purpose |
|-----------|---------|
| [`ask-user-question-fallback.md`](../references/ask-user-question-fallback.md) | Plain-text fallback shape for AskUserQuestion-less hosts. |
| [`authoring-conventions.md`](../references/authoring-conventions.md) | Authoring rules shared across SKILL.md files (loop-mode auto-picks, mirror-step threshold). |
| [`banner-preamble.md`](../references/banner-preamble.md) | Banner-print rule shared by every skill. |
| [`manual-gates.md`](../references/manual-gates.md) | Steps that must always be manual regardless of autonomy.level (PR opening, upstream issues, runlog dispatch). |
| [`merge-strategy-gate.md`](../references/merge-strategy-gate.md) | Merge-strategy decision UX (Direct vs PR) plus helper invocations. |
| [`post-cycle-trigger-gate.md`](../references/post-cycle-trigger-gate.md) | Trigger condition + nudge-or-dispatch choreography for post-cycle steps (8.5, 8.6, D-A1). |
| [`review-verdict-routing.md`](../references/review-verdict-routing.md) | PASS / CONCERNS / FAIL routing for `/hv-review` consumers. |
| [`docs-conventions.md`](../references/docs-conventions.md) | Conventions for content under `docs/` (registration sites, audience split). Consumed by Docs Mode. |
| [`three-mode-skill-shape.md`](../references/three-mode-skill-shape.md) | Three-mode shape (first-run / after-work / restructure) shared with `/hv-qa`. Docs Mode follows this skeleton. |
