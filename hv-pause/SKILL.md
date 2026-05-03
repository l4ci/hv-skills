---
name: hv-pause
description: Gracefully pause mid-session — writes a handoff note (current hypothesis, next planned step, mid-edit files, uncommitted work strategy) to .hv/handoff/<branch>.md so /hv-resume in a fresh session can pick up with full context, not just git state. Use when the session is approaching a context limit, you need to hand off, or you want to stop a long /hv-work cycle cleanly.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  💤  hv-pause  ·  write handoff note for clean pause
  triggers: "pause", "hand off"  ·  pairs: hv-resume, hv-learn
════════════════════════════════════════════════════════════════════════
```

# hv-pause — Graceful Session Pause

`/hv-resume` reads and deletes the handoff note on the next session.

## When to Use

- Context window is filling up and you want to stop cleanly
- You have to step away mid-`/hv-work` or mid-`/hv-debug` cycle
- Work will continue in a new session; git commits alone won't carry the intent

## When NOT to Use

- Work is actually complete → `/hv-ship`
- You can finish in this session → just finish
- No active branch / no `/hv-work` running → nothing to hand off

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling. Observe-only: on exit `2`, surface *"Nothing to pause — `/hv-init` the project first."* and stop (no auto-init).

## Step 2 — Resolve the Pause Set

Determine the set of `(branch, repo)` entries to pause. The set has size 1 for single-repo cycles or scoped umbrella pauses; size ≥ 2 when one `/hv-work` wave fanned out across sub-repos and the user wants to pause it as one logical unit.

1. Read `.hv/status.json` and find active streams whose `branch` matches the current branch.
2. **Exactly one match** — pause set is that single `(branch, repo)` entry (`repo` may be `null` for non-umbrella entries).
3. **Multiple matches** (a multi-repo `/hv-work` wave). Run `.hv/bin/hv-resolve-repo` from the current cwd:
   - **cwd resolves to a registered sub-repo** — pause set is the single matching `(branch, repo)` entry. The user explicitly scoped to one repo by `cd`-ing there; the other entries stay active.
   - **cwd doesn't resolve** (umbrella root or outside any sub-repo) — pause set is **all** matching entries, treated as one logical wave. Do not raise an `AskUserQuestion` — entries from a single `/hv-work` wave are paused together.
4. **No match** — fall back to `git rev-parse --abbrev-ref HEAD` for the branch and pause set is `[(branch, null)]` (covers running `/hv-pause` before any `/hv-work` registered status).
5. If the resolved branch is `main`/`master`/`trunk`, tell the user there's no feature work to pause and stop.

Steps 3–6 below operate on the pause set: single-entry sets keep today's behavior byte-for-byte; multi-entry wave sets loop the per-repo work and emit a single combined confirmation in Step 6.

## Step 3 — Handle Uncommitted Work

For each `(branch, repo)` in the pause set, resolve the working directory:

- `repo == null` → run from current cwd.
- `repo != null` → use the sub-repo's absolute path (`.hv/bin/hv-resolve-repos <repo>` returns it).

Run the status check in each working directory:

```bash
git -C <path> status --porcelain
```

For a single-entry set this is identical to today's `git status --porcelain` from cwd.

- **All entries clean** → continue to Step 4 with `clean tree` artifact for every entry.
- **Any entry dirty** → ask once via `AskUserQuestion`:
  - **Header:** `"Uncommitted"`
  - **Question (single-entry set):** *"N uncommitted files on `<branch>`. How should I handle them?"*
  - **Question (wave set):** *"Uncommitted files on `<branch>` in `<repo-a>`, `<repo-c>`. How should I handle them?"*
  - **Options** (single-select):
    1. "WIP commit (Recommended)" — *"`git add -A && git commit -m 'wip: pause before context cutoff'` — keeps changes on the branch."*
    2. "Stash" — *"`git stash push -u -m 'hv-pause <branch>'` — keeps changes out of history."*
    3. "Leave in place" — *"No action; the handoff will note that the tree is dirty."*
  - Plain-text fallback: *"Wrap them in a `wip:` commit, stash them, or leave them in place?"*

Apply the chosen disposition **only to the dirty entries** (use `git -C <path> ...` per repo). Record the per-entry artifact (commit hash, stash ref, `dirty tree`, or `clean tree`) for Step 4.

## Step 4 — Write the Handoff Note

```bash
mkdir -p .hv/handoff
```

Resolve milestone context first — if any active item carries a `Milestone:` tag in `TODO.md` (grep the line for the captured ID), or if `.hv/bin/hv-vision-active` lists a single milestone, include it in the **Working on** block below. Multi-active milestones with mixed-tagged items: list whichever milestone matches the items being paused.

**Loop over the pause set — one handoff file per `(branch, repo)` entry.** The path encoding is unchanged from F05:

- `repo` non-null (umbrella mode): `.hv/handoff/<branch>@<repo>.md`
- `repo` null (single-repo / legacy): `.hv/handoff/<branch>.md`

For wave sets, every entry shares the **Items**, **Milestone**, **Stage**, **Next planned step**, and **Current hypothesis** content — only `Repo:` and the per-repo `Uncommitted work` artifact differ. Don't merge them into one combined file: `/hv-resume`'s lookup is keyed on `(branch, repo)`, so per-entry files keep that path symmetric and survive partial cleanup (one repo abandoned, others resumed).

Branch names already contain `/` (e.g. `hv/fix-X`) and `mkdir -p .hv/handoff` plus the branch path's nested dirs already cover that; the `@<repo>` suffix lives on the filename, not on a directory, so it can't collide with a literal subdirectory.

Fill each section from the current session — omit sections that don't apply, but don't manufacture content.

```markdown
# Handoff — <branch>

<!-- Paused YYYY-MM-DD HH:MM UTC -->

## Working on

- **Repo:** web                              <!-- omit when single-repo / no umbrella scope -->
- **Items:** [B07], [F03]
- **Milestone:** M01 — Auth foundation  <!-- omit if no active milestone or items aren't tagged -->
- **Stage:** <e.g., "mid-hypothesis verification for B07", "implementing wave 2 of 3">

## Next planned step

<one or two sentences — the concrete action /hv-resume should dispatch. Not a summary; a directive.>

## Current hypothesis (if debugging)

<the causal claim under test, with the verification probe that was about to run>

## Uncommitted work

<one of: "clean tree" / "stashed as `stash@{0}` — message: hv-pause <branch>" / "wip commit `a1b2c3d`" / "dirty tree — see `git status`">
```

Use `Write` for each note (always overwrite — one handoff per `(branch, repo)` pair).

These four sections are exactly what `/hv-resume` reads. Anything else (commit log, files mid-edit, gotchas, dead ends) belongs elsewhere: `git log` and `git status` carry recent commits and mid-edit paths; durable learnings go to `/hv-learn` via the Step 6 nudge.

## Step 5 — Pin Status

Loop over the pause set:

```bash
# Make sure status.json has each entry so /hv-resume finds them
.hv/bin/hv-status-add --if-absent [--repo <repo>] <branch> <item-ids> [worktree-path]
```

Pass `--repo <repo>` for entries with a non-null `repo`; omit it for legacy / single-repo entries. Uniqueness is `(branch, repo)`, so threading `--repo` matters when two sub-repos share a branch name.

Idempotent — `--if-absent` skips the write if the entry already exists, preserving the original `startedAt` so "time in flight" stays accurate. The handoff note carries the pause timestamp separately.

## Step 6 — Confirm

One compact block. For single-entry pause sets:

```
Paused `hv/fix-B07-timer-badge` (web) — handoff saved.

Stage: mid-hypothesis verification for [B07]
Next: run the verification probe in MenuBarManager.swift:54
Uncommitted: wip commit a1b2c3d

Resume with `/hv-resume` in a fresh session.
```

The `(web)` suffix is shown only in umbrella mode (when `<repo>` is non-null); single-repo cycles drop it and just print the branch.

For wave pause sets (≥ 2 entries from one `/hv-work` wave):

```
Paused `hv/api-refactor` across web, api — 2 handoffs saved.

Stage: implementing wave 2 of 3
Next: thread the new repo arg through hv-status-add-multi
Uncommitted:
  - web: wip commit a1b2c3d
  - api: clean tree

Resume with `/hv-resume` in a fresh session.
```

Stage / Next / Hypothesis are shared across the wave; Uncommitted is per-repo because each sub-repo's working tree is independent.

**Learn nudge (conditional).** Pausing = context loss. If the session uncovered a durable gotcha (typical signals: a hypothesis that contradicted initial assumptions, a non-obvious root cause, a tool quirk you'll hit again), suggest one line:

*"Run `/hv-learn` now to preserve session insights durably — handoff captures intent, not learnings."*

Skip if nothing non-obvious surfaced or `/hv-learn` already ran this session. Don't block the pause — the nudge is advisory.

## Rules

- **Write what you know, not what you wish you knew.** The handoff is a snapshot of orchestrator state, not a task spec.
- **One note per `(branch, repo)`.** Overwrite on re-pause; don't accumulate stale notes.
- **Multi-repo waves are one logical pause.** When `status.json` holds multiple `(branch, repo)` entries from one `/hv-work` wave, `/hv-pause` treats them as a single unit by default — no `AskUserQuestion` to pick one repo. Scope the pause to a single sub-repo by `cd`-ing into it before invoking `/hv-pause`; cwd resolves to that repo and the other entries stay active.
- **Umbrella handoff filenames key on `(branch, repo)`.** Two sub-repos sharing a branch name get separate handoff files at `.hv/handoff/<branch>@<repo>.md`; single-repo cycles keep `.hv/handoff/<branch>.md` unchanged.
- **Never commit `.hv/handoff/`.** `.hv/` is gitignored, so this is automatic — but don't add an exception.
- **`/hv-resume` owns cleanup.** Once resume has read and routed, it deletes the note. Don't self-delete here.
- **No mutation beyond the handoff + optional wip/stash.** This skill's job is capture, not integration.
