---
name: hv-resume
description: Reorient after a context clear or a fresh session — shows active work streams reconciled against git, recent commits per stream, backlog counts, and routes to /hv-work, /hv-ship, or /hv-next. Use on "where was I", "pick up where I left off", "resume work", or right after /clear.
user-invocable: true
---

# hv-resume — Pick Up Where You Left Off

Read-only reorientation. Surfaces active work, recent commits per branch, and backlog counts — then routes to the right next action. No mutation.

## When to Use

- Right after `/clear` when you want to recover session context
- Starting a fresh terminal in a project that had work in flight
- *"Where was I?"*, *"What's still open?"*, *"Resume"*

## When NOT to Use

- Nothing is in progress → `/hv-next` to pick work
- You just want a state glance, no routing → `/hv-status`
- You want to commit + ship → `/hv-ship`

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

If the helper is absent or exits non-zero, tell the user *"Nothing tracked — run `/hv-init` first."* and stop. Don't auto-init: resume on an empty project has nothing to reorient around. See GUIDE.md § Preflight for exit codes.

## Step 2 — Reconcile Active Work

```bash
.hv/bin/hv-reconcile
```

Parses JSON output:

- `cleaned` — stale entries already removed. Silent; no output needed.
- `needsAction` — real work streams with fields `branch`, `items`, `worktree`, `startedAt`, `hasCommits`, `commitCount`, `worktreeMissing`.

## Step 3 — Enrich Each Stream

For each entry in `needsAction`, fetch recent commit subjects so the user can see what's there without reading the diff:

```bash
git log --no-merges --format='- %h %s' <base>..<branch> | head -5
```

(Use `main` or `master` as base; match how `hv-reconcile` picked it.)

If `worktreeMissing: true`, note *"(worktree was cleaned up — run `/hv-work` to re-create)"*.

**Check for a handoff note** from `/hv-pause`:

```bash
HANDOFF=".hv/handoff/<branch>.md"
[ -f "$HANDOFF" ] && cat "$HANDOFF"
```

If the note exists, the orchestrator paused this branch deliberately — treat it as the source of truth for *intent*, not just git. Extract the **Next planned step** and **Current hypothesis** sections; they drive routing in Step 5.

## Step 4 — Summarize Backlog

```bash
.hv/bin/hv-summary
```

One-shot overview: backlog counts, any active streams (redundant with Step 2 but harmless), active milestones, recent completions, knowledge topics, archive size.

The summary now includes an *Active milestones* line when any milestone has `status: active`. Surface that line as-is in Step 5's present block — it tells the user what's in focus when they pick what to resume.

## Step 5 — Present & Route

Emit one compact block, structured by stream. When a handoff note exists, surface its **Next planned step** and **Current hypothesis** inline — that's the signal the user cares about. Example:

```
Active work:

  `hv/fix-B07-timer-badge` — [B07] (paused 2026-04-18 14:32, 1 commit)
    - a1b2c3d fix: invalidate timer before badge update
    Handoff:
      Stage: mid-hypothesis verification for B07
      Next: run the verification probe in MenuBarManager.swift:54
      Uncommitted: wip commit a1b2c3d
    → Resume with /hv-work (handoff will be consumed)

  `hv/auth-refresh` — [F07] (started 2026-04-18, 0 commits)
    → In progress — run /hv-work to continue

Backlog: 4 bugs, 6 features, 2 tasks
Active milestones: M01 — Auth foundation
Knowledge: 5 topics
```

Omit the `Active milestones` line if no milestone is active.

Then use `AskUserQuestion`. Build one question per stream (up to 4 streams in one call; present any overflow in a second call). Each stream's question:

- **Header:** the first 12 chars of the branch name.
- **Question:** the stream's one-line summary (same text you just printed, minus the commit list).
- **Options** (single-select) derived from the stream state — mark the best fit `(Recommended)`:

| State | Recommended | Other options |
|-------|-------------|---------------|
| Handoff note present | "Resume with `/hv-work`" (consumes the note) | "Leave handoff for later", "Abandon branch" |
| `hasCommits: true`, commits look complete, no handoff | "Ship via `/hv-ship`" | "Keep working with `/hv-work`", "Leave as-is" |
| `hasCommits: true`, mid-implementation | "Resume with `/hv-work`" | "Ship via `/hv-ship`", "Leave as-is" |
| `hasCommits: false`, no handoff | "Resume with `/hv-work`" | "Abandon branch", "Leave as-is" |

If there are no active streams, skip the stream questions entirely and ask a single:

- **Header:** `"Next"`
- **Question:** *"No active streams. Pick new work with `/hv-next`?"*
- **Options:** "Open backlog (Recommended)" (→ `/hv-next`) / "Stop here".

Plain-text fallback: *"Resume one of these, or pick new work with `/hv-next`?"*

## Step 6 — Execute User's Choice

Route each stream's answer via the `Skill` tool. Pass the branch name and item IDs as context so the downstream skill doesn't re-read state.

| Answer | Action |
|--------|--------|
| "Resume with `/hv-work`" | Invoke `hv-work` on the branch; if a handoff note was consumed, include its full content in the brief |
| "Ship via `/hv-ship`" | Invoke `hv-ship` on the branch |
| "Abandon branch" | `git branch -D <branch>` then `.hv/bin/hv-status-remove <branch>` |
| "Leave as-is" / "Leave handoff for later" | Print *"Skipped `<branch>`."* and continue |
| "Open backlog" | Invoke `hv-next` |
| "Stop here" | Print *"OK — run `/hv-resume` again when you're ready."* and exit |

**Handoff consumption**: only delete `.hv/handoff/<branch>.md` when the user chose to resume that specific branch. For "Leave handoff for later" and every other non-resume answer, the note stays in place so the next `/hv-resume` surfaces it again:

```bash
rm .hv/handoff/<branch>.md   # only after dispatching /hv-work or /hv-debug
```

## Rules

- **Minimal mutation.** Only two writes happen: `hv-reconcile` normalizes `status.json` (clears dead-branch entries, nulls missing worktree paths) and the handoff note is deleted after the user picks its branch to resume. `TODO.md` and `KNOWLEDGE.md` stay untouched.
- **Trust git over status.** `hv-reconcile` already reconciles; don't second-guess its output.
- **Don't re-plan.** If the user picks `/hv-work`, hand off — don't re-narrate the plan.
- **Silent on empty.** No active streams and an empty backlog → say *"Nothing in flight."* and stop. Don't manufacture work.
