# Autonomy levels

`autonomy.level` controls whether each skill nudges you with a one-line suggestion at decision points or invokes the next skill directly. Three levels, mutually exclusive: `"off"`, `"auto"`, `"loop"`.

## The three levels

| Value | Behavior |
|-------|----------|
| `"off"` (default) | Skills surface a one-line suggestion at each decision point and stop. The user picks. Same hand-on-the-wheel feel as 1.5.x. |
| `"auto"` | One-hop chaining. After `/hv-work` finishes a cycle, `/hv-learn` is invoked automatically (when its threshold trips), and `/hv-refactor` is invoked when the refactor-age threshold trips. After `/hv-debug` commits a fix, `/hv-ship` is invoked automatically. After `/hv-ship` integrates, `/hv-learn` is invoked. The chain stops after the chained step — the user picks the next item themselves. |
| `"loop"` | Auto chain plus loop continuation. After each `/hv-work` or `/hv-ship` cycle, `/hv-next` is invoked. `/hv-next` (also reading `autonomy.level`) auto-selects the suggested item and dispatches `/hv-work` without asking. The loop sustains itself until the backlog drains, a guard fails, or the user interrupts. |

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

## When to flip it on

`"auto"` is good when you want the obvious follow-up step of each cycle (capture learnings, ship the fix) without typing the command yourself. `"loop"` is good when you have a known queue you want drained: milestone seed items, a pile of P2 bugs, a multi-day backlog that's well-specified. You'd rather inspect the result than steer each pick. Leave it `"off"` when you're exploring, when items in the backlog need different judgement calls, or when you'd rather not run a long session of model spend without checkpoints.

## Picking by phase

A rough phase mapping:

- `"off"` for exploring or steering. You're shaping the work, not draining a queue.
- `"auto"` once a milestone is in flight and a plan is sketched. The follow-up step of each cycle (learn, ship) gets handled; you still pick the next item.
- `"loop"` for a known, well-specified queue. `/hv-next` picks and dispatches for you until the backlog is empty.

See [vision and plans](vision-and-plans.md) for milestone-driven planning and [running work](running-work.md) for the work-cycle endpoints where autonomy fires.
