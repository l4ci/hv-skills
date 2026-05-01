# Configuration

All settings live in `.hv/config.json`. Edit the file directly or run `/hv-config` for an interactive picker that offers four common profiles — Balanced, Premium, Fast, Minimal — that map to the values below.

Default config:

```json
{
  "models": {
    "orchestrator": "opus",
    "worker": "sonnet"
  },
  "work": {
    "isolation": "branch",
    "mergeStrategy": "direct"
  },
  "refactor": {
    "confirmBeforeExecute": true
  },
  "learn": {
    "verify": true
  },
  "ship": {
    "review": true
  },
  "autonomy": {
    "level": "off"
  },
  "debug": {
    "competingHypotheses": false
  }
}
```

## models — orchestrator and worker

`models.orchestrator` drives planning, exploration, verification, and design. `models.worker` handles implementation sub-tasks. Set them independently to trade off quality against cost and speed.

| Value | Best for |
|-------|----------|
| `"opus"` | Deep reasoning — planning, exploration, verification, design |
| `"sonnet"` | Fast execution — implementing well-specified tasks |
| `"haiku"` | Quick, cheap — simple fixes, small tasks |

`/hv-config` and `/hv-init` offer four ready-made profiles (Balanced, Premium, Fast, Minimal) that set both values at once.

## work.isolation — branch or worktree

Controls where skill work happens.

| Mode | How it works | When to use |
|------|-------------|-------------|
| `"branch"` | Feature branch in current worktree | Solo work, simple workflows |
| `"worktree"` | Isolated directory under `.claude/worktrees/` | Parallel work streams, keep main clean while agents work |

Switch to `"worktree"` when you want multiple work streams in flight without context bleeding between them.

## work.mergeStrategy — direct or pr

Controls how `/hv-ship` integrates completed work.

| Strategy | How it works | When to use |
|----------|-------------|-------------|
| `"direct"` | Merge to main, delete branch | Solo work, fast iteration |
| `"pr"` | Push branch, create GitHub PR | Team work, code review required |

## refactor.confirmBeforeExecute

When `true` (default), `/hv-refactor` pauses for your approval after presenting its findings and again after you select a design. You review the proposed changes before anything is written. Set to `false` for full autonomy — `/hv-refactor` proceeds end-to-end without checkpoints.

## learn.verify

Controls whether `/hv-learn` runs a second-opinion pass on what it just wrote. The verifier is a fresh Opus sub-agent — no session context, reads only the updated `KNOWLEDGE.md` diff — and judges each new bullet on four criteria: durable (not ephemeral), sharp (concrete claim, not vague), correctly topic'd, and non-duplicate. It can demote weak entries, sharpen vague wording, re-file wrong-topic bullets, or delete restatements of existing knowledge.

| Value | Behavior |
|-------|----------|
| `true` (default) | After writing, dispatches the verifier. Catches weak, duplicate, or wrong-topic entries before they accrete in `KNOWLEDGE.md`. Adds one Opus roundtrip per `/hv-learn` call. |
| `false` | Skip the verifier. `/hv-learn` writes and reports. Fast, cheap. Use when you're iterating rapidly and the occasional weak entry is acceptable. |

Knowledge quality compounds — a weak bullet consulted by 20 future `/hv-work` runs is worse than one extra Opus call now. The default favors quality; flip to `false` only when you're sure the noise doesn't matter.

See [learning](usage/learning.md) for the full `/hv-learn` workflow.

## ship.review

Controls whether `/hv-ship` runs a review pass before integrating.

| Value | Behavior |
|-------|----------|
| `true` (default) | `/hv-ship` runs `/hv-review` before integrating. FAIL blocks, CONCERNS ask, PASS flows through. |
| `false` | `/hv-ship` integrates directly without a review pass. Use when you want raw speed and already reviewed manually. |

See [shipping](usage/shipping.md) for the full `/hv-ship` workflow.

## debug.competingHypotheses

Controls whether `/hv-debug` Step 6 dispatches a single hypothesis agent or fans out three parallel agents from different angles (recent-changes, data-shape, concurrency-lifecycle). The orchestrator deduplicates the ranked outputs and picks the strongest hypothesis regardless of which agent surfaced it.

| Value | Behavior |
|-------|----------|
| `false` (default) | Single hypothesis agent. Cheaper and faster; fine for most bugs where one angle is obviously primary. |
| `true` | Three parallel hypothesis agents in one tool-call batch. Better diversity on hard bugs (the right framing isn't obvious upfront), at ~3× orchestrator cost on every `/hv-debug` run. Step 6 latency stays roughly the same — the agents run concurrently. |

Flip on when you have a class of bugs that consistently take multiple cycles to land — the diversity of framings is what makes the difference. Keep off when most bugs are single-cause and you're paying for cycles you don't need.

## autonomy.level

Controls whether skills nudge at decision points or invoke the next skill directly. Three levels, mutually exclusive.

| Value | Behavior |
|-------|----------|
| `"off"` (default) | Skills surface a one-line suggestion at each decision point and stop. The user picks. Same hand-on-the-wheel feel as 1.5.x. |
| `"auto"` | One-hop chaining. After `/hv-work` finishes a cycle, `/hv-learn` is invoked automatically (when its threshold trips), and `/hv-refactor` is invoked when the refactor-age threshold trips. After `/hv-debug` commits a fix, `/hv-ship` is invoked automatically. After `/hv-ship` integrates, `/hv-learn` is invoked. The chain stops after the chained step — the user picks the next item themselves. |
| `"loop"` | Auto chain plus loop continuation. After each `/hv-work` or `/hv-ship` cycle, `/hv-next` is invoked. `/hv-next` (also reading `autonomy.level`) auto-selects the suggested item and dispatches `/hv-work` without asking. The loop sustains itself until the backlog drains, a guard fails, or the user interrupts. |

**What still gates the chain.** Autonomy decides whether to invoke the next skill; the destination skill's own gates still decide whether it pauses. So:

- `learn.verify: true` — `/hv-learn` still runs the Opus verifier even when invoked under autonomy.
- `ship.review: true` — `/hv-ship` still runs `/hv-review` and blocks on FAIL.
- `refactor.confirmBeforeExecute: true` — `/hv-refactor` still pauses for approval at its own checkpoints.

**Stop conditions in loop mode.** The loop stops cleanly on any of:

- `/hv-next` reports an empty backlog (no items in active milestone, no items in general backlog).
- `/hv-work` Step 2 detects a genuinely ambiguous brief — invisible defaults across a queue defeat the loop's point. The user resolves and re-invokes `/hv-next` to continue.
- A guard fails (dirty tree, `/hv-review` FAIL, missing brief).
- The user interrupts.

**When to flip it on.** `"auto"` is good when you want the natural endgame of each cycle (capture learnings, ship the fix) without typing the follow-up command. `"loop"` is good when you have a known queue you want drained — milestone seed items, a pile of P2 bugs, a multi-day backlog that's well-specified — and you'd rather inspect the result than steer each pick. Leave it `"off"` when you're exploring, when items in the backlog need different judgement calls, or when you don't want a long-running session of model spend without checkpoints.

See [implementing](usage/implementing.md) for how autonomy interacts with the `/hv-work` cycle.
