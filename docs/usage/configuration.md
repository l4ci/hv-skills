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
  },
  "docs": {
    "path": "docs",
    "autoCreate": true
  },
  "git": {
    "baseBranch": ""
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

See [learning](learning.md) for the full `/hv-learn` workflow.

## ship.review

Controls whether `/hv-ship` runs a review pass before integrating.

| Value | Behavior |
|-------|----------|
| `true` (default) | `/hv-ship` runs `/hv-review` before integrating. FAIL blocks, CONCERNS ask, PASS flows through. |
| `false` | `/hv-ship` integrates directly without a review pass. Use when you want raw speed and already reviewed manually. |

See [review and ship](review-and-ship.md) for the full `/hv-ship` workflow.

## debug.competingHypotheses

Controls whether `/hv-debug` Step 6 dispatches a single hypothesis agent or fans out three parallel agents from different angles (recent-changes, data-shape, concurrency-lifecycle). The orchestrator deduplicates the ranked outputs and picks the strongest hypothesis regardless of which agent surfaced it.

| Value | Behavior |
|-------|----------|
| `false` (default) | Single hypothesis agent. Cheaper and faster; fine for most bugs where one angle is obviously primary. |
| `true` | Three parallel hypothesis agents in one tool-call batch. Better diversity on hard bugs (the right framing isn't obvious upfront), at ~3× orchestrator cost on every `/hv-debug` run. Step 6 latency stays roughly the same — the agents run concurrently. |

Flip on when you have a class of bugs that consistently take multiple cycles to land — the diversity of framings is what makes the difference. Keep off when most bugs are single-cause and you're paying for cycles you don't need.

## autonomy.level

Controls whether skills nudge or invoke the next skill directly. Three levels: `"off"` (default), `"auto"`, `"loop"`. See [autonomy levels](autonomy.md) for the full breakdown — when each level fires, what gates still apply, stop conditions in loop mode, and how to pick.

## docs.path

- **Type:** string
- **Default:** `"docs"`

Relative path (from the project root) to the documentation folder that `/hv-docs` reads and writes. Set this when your project keeps docs somewhere other than the default — for example `"documentation"`, `"site/content"`, or `"wiki"`.

```json
{ "docs": { "path": "documentation" } }
```

## docs.autoCreate

- **Type:** boolean
- **Default:** `true`

Controls whether `/hv-docs` after-work mode automatically writes proposed doc updates without pausing for approval. When `true`, `/hv-docs` writes changes and reports what it did. When `false`, `/hv-docs` proposes changes and waits for your confirmation before writing.

| Value | Behavior |
|-------|----------|
| `true` (default) | After-work mode writes doc updates automatically. Fast; assumes you trust the agent's judgment on doc prose. |
| `false` | After-work mode proposes updates and waits for approval before writing. Safer when doc quality is critical or the agent is unfamiliar with your doc style. |

## git.baseBranch

- **Type:** string
- **Default:** `""` (auto-detect)

Override the base branch that `hv-base-branch` resolves to. When empty (the default), the helper auto-detects by probing `main`, `master`, `trunk`, then `origin/HEAD` in that order. Set this explicitly when your project uses a non-default base branch such as `develop` (gitflow), `release`, or any other name that won't be found by auto-detection.

```json
{ "git": { "baseBranch": "develop" } }
```

Skills that use the base branch — including `/hv-reconcile`, `/hv-ship`, `/hv-review`, and `/hv-merge` — all call `hv-base-branch` and will pick up this override automatically.
