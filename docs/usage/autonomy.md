# Autonomy levels

`autonomy.level` controls whether each skill nudges you with a one-line suggestion at decision points or invokes the next skill directly. Three levels, mutually exclusive: `"off"`, `"auto"`, `"loop"`.

## The three levels

| Value | Behavior |
|-------|----------|
| `"off"` (default) | Skills surface a one-line suggestion at each decision point and stop. The user picks. Same hand-on-the-wheel feel as 1.5.x. |
| `"auto"` | One-hop chaining. After `/hv-work` finishes a cycle, `/hv-learn` is invoked automatically (when its threshold trips), and `/hv-refactor` is invoked when the refactor-age threshold trips. After `/hv-debug` commits a fix, `/hv-ship` is invoked automatically. After `/hv-ship` integrates, `/hv-learn` is invoked. After `/hv-update` reports `behind`, Step 4 asks once via `AskUserQuestion` and dispatches `/hv-init` on confirm so drift clears in one step. The chain stops after the chained step — the user picks the next item themselves. |
| `"loop"` | Auto chain plus loop continuation, plus auto-pick on routine routing. After each `/hv-work` or `/hv-ship` cycle, `/hv-next` is invoked. `/hv-next` (also reading `autonomy.level`) auto-selects the suggested item and dispatches `/hv-work` without asking. Routine routing/tagging questions that present a clear `(Recommended)` option — milestone tagging in `/hv-capture`, reconcile resolution in `/hv-next`, CONCERNS routing in `/hv-ship`, scope and candidate gates in `/hv-refactor` — are silently auto-picked without prompting. Design decisions, manual public-artifact gates, and config flips still surface for explicit user input. After `/hv-update` reports `behind`, Step 4 dispatches `/hv-init` unconditionally (no question) — if the plugin wasn't actually updated, the STALE migration is a no-op. The loop sustains itself until the backlog drains, a guard fails, or the user interrupts. |

## What still gates the chain

Autonomy decides whether to invoke the next skill; the destination skill's own gates still decide whether it pauses. So:

- `learn.verify: true` — `/hv-learn` still runs the Opus verifier even when invoked under autonomy.
- `ship.review: true` — `/hv-ship` still runs `/hv-review` and blocks on FAIL.
- `refactor.confirmBeforeExecute: true` — `/hv-refactor` still pauses for approval at its own checkpoints.

## Stop conditions in loop mode

The loop stops cleanly on any of:

- `/hv-next` reports an empty backlog (no items in active milestone, no items in general backlog).
- `/hv-work` Step 2 detects a genuinely ambiguous brief. Invisible defaults across a queue defeat the loop's point. The user resolves and re-invokes `/hv-next` to continue.
- A guard fails (dirty tree, `/hv-review` FAIL, missing brief).
- The user interrupts.

## What loop mode auto-picks vs. surfaces

In loop mode, AskUserQuestion calls fall into three buckets:

- **Auto-picked silently** — routine routing/tagging questions where the `(Recommended)` option is the obvious right answer. Examples: which milestone to tag captured items with, whether to ship/resume a paused branch, where to send review concerns, which sub-repos to refactor. The loop proceeds as if you'd picked the Recommended option.
- **Surfaced for design decisions** — when an `AskUserQuestion` covers a design pick with multiple plausible interpretations (a competing approach, a version-bump escalation), loop mode stops and asks. F32 (loop-mode auto-planning) extends this further with `[Auto:Loop]` decision logging when /hv-plan needs to resolve open questions, but until then design questions break the loop until you answer them.
- **Always manual regardless of autonomy** — public-artifact gates and committed-boundary gates: `/hv-decide` approvals, `/hv-learn` issue/runlog filing, `/hv-ship` PR strategy, `/hv-release` push/publish gates. These honor their `**Manual gate — ...**` callout no matter what `autonomy.level` says.

If a routine routing prompt does fire under loop mode, that's a sign the auto-pick branch is missing at that call site — file it as a bug.

## When to flip it on

`"auto"` is good when you want the obvious follow-up step of each cycle (capture learnings, ship the fix) without typing the command yourself. `"loop"` is good when you have a known queue you want drained: milestone seed items, a pile of P2 bugs, a multi-day backlog that's well-specified. You'd rather inspect the result than steer each pick. Leave it `"off"` when you're exploring, when items in the backlog need different judgement calls, or when you'd rather not run a long session of model spend without checkpoints.

## Picking by phase

A rough phase mapping:

- `"off"` for exploring or steering. You're shaping the work, not draining a queue.
- `"auto"` once a milestone is in flight and a plan is sketched. The follow-up step of each cycle (learn, ship) gets handled; you still pick the next item.
- `"loop"` for a known, well-specified queue. `/hv-next` picks and dispatches for you until the backlog is empty.

See [vision and plans](vision-and-plans.md) for milestone-driven planning and [running work](running-work.md) for the work-cycle endpoints where autonomy fires.
