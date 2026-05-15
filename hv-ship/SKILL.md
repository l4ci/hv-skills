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
- `ship.secondOpinion` — `false` (default) skips the fresh-eyes gate; `true` runs a no-prior-context adversarial review after `/hv-review` passes
- `ship.qa` — `false` (default) skips product QA; `true` runs `/hv-qa run` after `/hv-review` (and `secondOpinion`) and before merge/PR. Routed per `qa.gate` (`"advisory"` reports only; `"blocking"` halts on FAIL).
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

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

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
.hv/bin/hv-issues-imported
```

Parse the JSON array. Filter to entries whose `item_id` is in the shipped item list (the resolved IDs from Step 2). If the filtered list is empty, skip the rest of this step silently.

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
| [`post-cycle-trigger-gate.md`](../references/post-cycle-trigger-gate.md) | Trigger condition for post-cycle nudges (2+ items / ≥5 files / hard bug). |
| [`review-verdict-routing.md`](../references/review-verdict-routing.md) | PASS / CONCERNS / FAIL routing for `/hv-review` consumers. |
