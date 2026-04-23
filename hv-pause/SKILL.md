---
name: hv-pause
description: Gracefully pause mid-session — writes a handoff note (current hypothesis, next planned step, mid-edit files, uncommitted work strategy) to .hv/handoff/<branch>.md so /hv-resume in a fresh session can pick up with full context, not just git state. Use when the session is approaching a context limit, you need to hand off, or you want to stop a long /hv-work cycle cleanly.
user-invocable: true
---

# hv-pause — Graceful Session Pause

Capture the state living in the orchestrator's head — what you were about to do next, which hypothesis you were on, which files are mid-edit — into a handoff note. `/hv-resume` reads and deletes the note on the next session.

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

If the helper is absent or exits non-zero, tell the user *"Nothing to pause — `/hv-init` the project first."* and stop. Don't auto-init: pause on an empty project has nothing to hand off. See GUIDE.md § Preflight for exit codes.

## Step 2 — Resolve the Branch

Determine the active work branch:

1. Check `.hv/status.json` for an active stream matching the current branch
2. If not found, fall back to `git rev-parse --abbrev-ref HEAD`
3. If the result is `main`/`master`/`trunk`, tell the user there's no feature work to pause and stop

## Step 3 — Handle Uncommitted Work

```bash
git status --porcelain
```

- **Clean** → continue to Step 4
- **Dirty** → use `AskUserQuestion`:
  - **Header:** `"Uncommitted"`
  - **Question:** *"N uncommitted files on `<branch>`. How should I handle them?"*
  - **Options** (single-select):
    1. "WIP commit (Recommended)" — *"`git add -A && git commit -m 'wip: pause before context cutoff'` — keeps changes on the branch."*
    2. "Stash" — *"`git stash push -u -m 'hv-pause <branch>'` — keeps changes out of history."*
    3. "Leave in place" — *"No action; the handoff will note that the tree is dirty."*
  - Plain-text fallback: *"Wrap them in a `wip:` commit, stash them, or leave them in place?"*

Carry out whichever path was chosen and note the artifact (commit hash, stash ref, or "dirty tree") for the handoff in Step 4.

## Step 4 — Write the Handoff Note

```bash
mkdir -p .hv/handoff
```

Write `.hv/handoff/<branch>.md` with this structure. Fill each section from the current session — omit sections that don't apply, but don't manufacture content.

```markdown
# Handoff — <branch>

<!-- Paused YYYY-MM-DD HH:MM UTC -->

## Working on

- **Items:** [B07], [F03]
- **Stage:** <e.g., "mid-hypothesis verification for B07", "implementing wave 2 of 3">

## What's done

- <bullet per completed piece, referencing commit hashes where relevant>

## Next planned step

<one or two sentences — the concrete action /hv-resume should dispatch. Not a summary; a directive.>

## Current hypothesis (if debugging)

<the causal claim under test, with the verification probe that was about to run>

## Files mid-edit

- `path/to/Foo.swift:42-78` — <what was being changed>
- `path/to/Bar.swift` — <what was being changed>

## Uncommitted work

<one of: "clean tree" / "stashed as `stash@{0}` — message: hv-pause <branch>" / "wip commit `a1b2c3d`" / "dirty tree — see `git status`">

## Gotchas discovered

<anything learned this session that isn't yet in KNOWLEDGE.md but would save /hv-resume from re-discovering it>

## Do not

<things /hv-resume should NOT do — dead ends already ruled out, rabbit holes, wrong-turn fixes to revert>
```

Use `Write` for the note (always overwrite — one handoff per branch).

## Step 5 — Pin Status

```bash
# Make sure status.json has the current branch so /hv-resume finds it
.hv/bin/hv-status-add <branch> <item-ids> [worktree-path]
```

Idempotent — if the entry exists, this refreshes the `startedAt` timestamp, which is fine (the handoff note carries the pause timestamp anyway).

## Step 6 — Confirm

One compact block:

```
Paused `hv/fix-B07-timer-badge` — handoff saved.

Stage: mid-hypothesis verification for [B07]
Next: run the verification probe in MenuBarManager.swift:54
Uncommitted: wip commit a1b2c3d

Resume with `/hv-resume` in a fresh session.
```

**Learn nudge (conditional).** Pausing = context loss. If the Step 4 handoff populated a non-trivial **Gotchas discovered** section, the session learned something durable that `/hv-resume` in a new context won't carry forward. Before the user walks away, suggest one line:

*"Handoff has N gotchas. Run `/hv-learn` now to preserve them durably — the handoff gets deleted on `/hv-resume`."*

Skip if Gotchas was empty, a single trivial note, or `/hv-learn` already ran this session. Don't block the pause — the nudge is advisory.

## Rules

- **Write what you know, not what you wish you knew.** The handoff is a snapshot of orchestrator state, not a task spec.
- **One note per branch.** Overwrite on re-pause; don't accumulate stale notes.
- **Never commit `.hv/handoff/`.** `.hv/` is gitignored, so this is automatic — but don't add an exception.
- **`/hv-resume` owns cleanup.** Once resume has read and routed, it deletes the note. Don't self-delete here.
- **No mutation beyond the handoff + optional wip/stash.** This skill's job is capture, not integration.
