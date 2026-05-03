# Pausing and resuming

Long sessions hit `/clear`, get interrupted, or just need a stop. `/hv-pause` writes what was in your head before you leave; `/hv-resume` picks it back up when you return.

## /hv-pause

`/hv-pause` captures the live state of a mid-session investigation into `.hv/handoff/<branch>.md` before you stop. Git commits carry code. The handoff note carries intent: the current hypothesis, the next planned step, files that are mid-edit, and gotchas you ran into along the way.

**Use it when:**

- Your context window is filling and a `/clear` is coming.
- You're stepping away mid-[`/hv-work`](running-work.md) or mid-debug without a clean stopping point.
- You want a long investigation to survive a session boundary.

**What happens:** The skill resolves the active branch, asks how you want to handle uncommitted work (wip commit, stash, or leave dirty), then writes the handoff note. One note per branch; re-pausing overwrites the previous one.

The note's shape looks like:

```
## Working on
## What's done
## Next planned step
## Current hypothesis
## Files mid-edit
## Uncommitted work
## Gotchas discovered
## Do not
```

You don't need to manage this file directly. `/hv-resume` reads and deletes it.

## /hv-resume

`/hv-resume` reorients you at the start of a fresh session or right after a `/clear`. It reconciles active work streams against git (see [reviewing and picking work](next-and-status.md) for what reconciliation covers), enriches each stream with its recent commits, and checks for a handoff note from `/hv-pause`.

**What you see:** active streams with commit summaries, backlog counts, and a recommended next action.

**Routing logic:**

- Handoff note present → routes to `/hv-work` or `/hv-debug` with the note's "Next planned step" as the brief; note is deleted after you confirm
- Branch looks complete → routes to [review and ship](review-and-ship.md)
- Branch is mid-implementation → routes back to [running work](running-work.md)
- Nothing in flight → routes to [reviewing and picking work](next-and-status.md)

## Recovering after /clear

A typical recovery looks like this:

1. You're mid-investigation on branch `hv/my-feature`, context is filling. You run `/hv-pause`, which writes `.hv/handoff/hv-my-feature.md` with your current hypothesis and the next step you were about to try.
2. You run `/clear`. All conversation context is gone.
3. In the new session, you run `/hv-resume`.
4. The skill reads `status.json`, validates active streams against git, finds the handoff note for `hv/my-feature`, and surfaces something like:

```
Active streams
  hv/my-feature  (3 commits)  — mid-implementation

Handoff note found:
  Next planned step: add the retry path in src/worker.ts
  Current hypothesis: the timeout is in the fetch wrapper, not the caller

→ Resuming /hv-work with handoff brief
```

5. You confirm, and `/hv-work` picks up with the handoff note as its brief. The note is deleted.

## When to /hv-pause vs just commit and walk away

A clean commit is enough when the work is at a natural stopping point: a passing test, a completed subtask, a checkpoint that git state alone can describe. `/hv-pause` is for the messy middle. The live hypothesis, the half-written test, the "I was about to try X" — none of that survives a `/clear` from git state alone. If you'd have to re-read diffs and reconstruct your reasoning to figure out what to do next, pause first.
