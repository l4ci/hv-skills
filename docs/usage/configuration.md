# Configuration

All settings live in [`.hv/config.json`](../reference/hv-folder.md). Edit the file directly or run `/hv-config` for an interactive picker that offers four common profiles (Balanced, Premium, Fast, Minimal) that map to the values below. `/hv-config <key>` jumps straight to the value picker for that key; `/hv-config <key>=<value>` applies the value directly.

For the exact wording of the interactive picker's questions and option labels, see [Configuration options](../reference/config-options.md).

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
    "autoCreate": false
  },
  "git": {
    "baseBranch": ""
  },
  "hvSkills": {
    "version": ""
  }
}
```

## models — orchestrator and worker

`models.orchestrator` drives planning, exploration, verification, and design. `models.worker` handles implementation sub-tasks. Set them independently to trade off quality against cost and speed.

| Value | Best for |
|-------|----------|
| `"opus"` | Deep reasoning: planning, exploration, verification, design |
| `"sonnet"` | Fast execution of well-specified tasks |
| `"haiku"` | Quick, cheap fixes and small tasks |

`/hv-config` and [`/hv-init`](../reference/slash-commands.md#hv-init) offer four ready-made profiles (Balanced, Premium, Fast, Minimal) that set both values at once.

## work.isolation — branch or worktree

Controls where skill work happens.

| Mode | How it works | When to use |
|------|-------------|-------------|
| `"branch"` | Feature branch in current worktree | Solo work, simple workflows |
| `"worktree"` | Isolated directory under `.claude/worktrees/` | Parallel work streams, keep main clean while agents work |

Switch to `"worktree"` when you want multiple work streams in flight without context bleeding between them. See [parallel work](parallel-work.md) for the full pattern.

## work.mergeStrategy — direct or pr

Controls how [`/hv-ship`](review-and-ship.md) integrates completed work.

| Strategy | How it works | When to use |
|----------|-------------|-------------|
| `"direct"` | Merge to main, delete branch | Solo work, fast iteration |
| `"pr"` | Push branch, create GitHub PR | Team work, code review required |

## refactor.confirmBeforeExecute

When `true` (default), [`/hv-refactor`](../reference/slash-commands.md#hv-refactor) pauses for your approval after presenting its findings and again after you select a design. You review the proposed changes before anything is written. Set to `false` for full autonomy: `/hv-refactor` proceeds end-to-end without checkpoints.

## refactor.verifyCommands

Array of shell commands that [`/hv-refactor`](../reference/slash-commands.md#hv-refactor) Step 7 runs as CI-shape gates before committing. Default: `[]` (read-only verification, behavior unchanged).

When non-empty, the Step 7 verifier executes each command in order and refuses to PASS unless every command exits zero. This catches formatter drift, import-sort failures, and type errors locally instead of on push. See [hv-skills #9](https://github.com/l4ci/hv-skills/issues/9) for the motivating incident.

Example for a Python project using ruff + pytest:

```json
"refactor": {
  "confirmBeforeExecute": false,
  "verifyCommands": [
    "uv run ruff check .",
    "uv run ruff format --check .",
    "uv run pytest -q"
  ]
}
```

Commands run from the repo root (or, in umbrella mode, the sub-repo's root). Set via `hv-config-set` (which parses argv[2] as JSON):

```bash
.hv/bin/hv-config-set refactor.verifyCommands '["uv run ruff check .","uv run ruff format --check ."]'
```

## learn.verify

Controls whether [`/hv-learn`](learning.md) runs a second-opinion pass on what it just wrote. The verifier is a fresh Opus sub-agent with no session context that reads only the updated `KNOWLEDGE.md` diff. It judges each new bullet on four criteria: durable (not ephemeral), sharp (concrete claim, not vague), correctly topic'd, and non-duplicate. It can demote weak entries, sharpen vague wording, re-file wrong-topic bullets, or delete restatements of existing knowledge.

| Value | Behavior |
|-------|----------|
| `true` (default) | After writing, dispatches the verifier. Catches weak, duplicate, or wrong-topic entries before they accrete in `KNOWLEDGE.md`. Adds one Opus roundtrip per `/hv-learn` call. |
| `false` | Skip the verifier. `/hv-learn` writes and reports. Fast and cheap. Use when you're iterating rapidly and the occasional weak entry is acceptable. |

A weak bullet consulted by 20 future `/hv-work` runs is worse than one extra Opus call now, so the default favors quality. Flip to `false` only when the noise doesn't matter.

See [learning](learning.md) for the full `/hv-learn` workflow.

## ship.review

Controls whether `/hv-ship` runs a review pass before integrating.

| Value | Behavior |
|-------|----------|
| `true` (default) | `/hv-ship` runs `/hv-review` before integrating. FAIL blocks, CONCERNS ask, PASS flows through. |
| `false` | `/hv-ship` integrates directly without a review pass. Use when you want raw speed and already reviewed manually. |

See [review and ship](review-and-ship.md) for the full `/hv-ship` workflow.

## debug.competingHypotheses

Controls whether [`/hv-debug`](debugging.md) Step 6 dispatches a single hypothesis agent or fans out three parallel agents from different angles (recent-changes, data-shape, concurrency-lifecycle). The orchestrator deduplicates the ranked outputs and picks the strongest hypothesis regardless of which agent surfaced it.

| Value | Behavior |
|-------|----------|
| `false` (default) | Single hypothesis agent. Cheaper and faster; fine for most bugs where one angle is obviously primary. |
| `true` | Three parallel hypothesis agents in one tool-call batch. Better diversity on hard bugs where the right framing isn't obvious upfront, at ~3× orchestrator cost on every `/hv-debug` run. Step 6 latency stays roughly the same since the agents run concurrently. |

Flip on when you have a class of bugs that consistently take multiple cycles to land. The diversity of framings makes the difference. Keep off when most bugs are single-cause and you're paying for cycles you don't need.

## autonomy.level

Controls whether skills nudge or invoke the next skill directly. Three levels: `"off"` (default), `"auto"`, `"loop"`. See [autonomy levels](autonomy.md) for the full breakdown: when each level fires, what gates still apply, stop conditions in loop mode, and how to pick.

## docs.path

- **Type:** string
- **Default:** `"docs"`

Relative path (from the project root) to the documentation folder that [`/hv-docs`](../reference/slash-commands.md#hv-docs) reads and writes. Set this when your project keeps docs somewhere other than the default, for example `"documentation"`, `"site/content"`, or `"wiki"`.

```json
{ "docs": { "path": "documentation" } }
```

## docs.autoCreate

- **Type:** boolean
- **Default:** `false`

Controls whether `/hv-docs` after-work mode automatically writes proposed doc updates without pausing for approval. When `false` (the default), `/hv-docs` proposes changes and waits for your confirmation before writing. That's the safe propose-mode path. When `true`, `/hv-docs` writes changes and reports what it did. The `true` path will gain a Layer-3 LLM safety review before commit when M01-S03 ships; until then, `false` is the recommended default and `true` is opt-in.

| Value | Behavior |
|-------|----------|
| `false` (default) | After-work mode proposes updates and waits for approval before writing. Recommended until M01-S03 ships the auto-write safety review. |
| `true` | After-work mode writes doc updates automatically. Fast; assumes you trust the agent's judgment on doc prose. Best paired with a `git diff` review per cycle. |

## docs.afterWork

- **Type:** boolean
- **Default:** `false`

Gate for the after-work docs flow. When `true`, the skills [`/hv-work`](running-work.md), `/hv-ship`, and [`/hv-release`](../reference/slash-commands.md#hv-release) trigger `/hv-docs` after their primary action completes. `/hv-work` and `/hv-ship` only fire on cycles that resolve 2+ items or touch 5+ files (small fixes don't trigger); `/hv-release` fires on every successful release (release notes are inherently user-facing). Under `autonomy.level: off`, the trigger is a one-line nudge in the terminal report; under `auto` or `loop`, the skill auto-dispatches `/hv-docs` directly.

```json
{ "docs": { "afterWork": true } }
```

Leave `false` while you're shaping docs by hand. Flip on once your docs structure is stable enough that `/hv-docs`'s propose-mode adds value rather than noise.

## release.confirmLargePushCommits

- **Type:** integer
- **Default:** `10`

Threshold for the number of unpushed commits above which `/hv-release` will interject one confirmation prompt before pushing, even under `autonomy.level: auto` or `loop`. Below the threshold, auto/loop autonomy silently pushes the unpushed range as part of the release (the existing speed-contract behavior). Above it, the skill always asks. Releases that push 10+ commits are not the common case and the user usually wants a beat to confirm.

```json
{ "release": { "confirmLargePushCommits": 25 } }
```

Set higher to suppress the prompt for typical project velocities; set lower (e.g., `5`) for projects where every push is consequential.

## release.nudgeAfterCommits

- **Type:** integer
- **Default:** `10`

Number of commits since the last release tag at which [`/hv-next`](picking-work.md) (terminal paths only) and `/hv-ship` (post-ship report) start surfacing a one-line nudge: *"<N> commits since <tag>; consider `/hv-release`."* Informational only; no skill is auto-invoked.

## release.nudgeAfterDays

- **Type:** integer
- **Default:** `14`

Companion to `release.nudgeAfterCommits`. The release nudge fires when EITHER threshold is reached: high-velocity projects hit the commits threshold first, slow-burn projects hit the days threshold first. Set one or both higher to suppress more aggressively, or lower to release more often.

## git.baseBranch

- **Type:** string
- **Default:** `""` (auto-detect)

Override the base branch that `hv-base-branch` resolves to. When empty (the default), the helper auto-detects by probing `main`, `master`, `trunk`, then `origin/HEAD` in that order. Set this explicitly when your project uses a non-default base branch such as `develop` (gitflow), `release`, or any other name that won't be found by auto-detection.

```json
{ "git": { "baseBranch": "develop" } }
```

Skills that use the base branch (including `/hv-reconcile`, `/hv-ship`, `/hv-review`, and `/hv-merge`) all call `hv-base-branch` and will pick up this override automatically.

## hvSkills.version (auto-managed)

- **Type:** string
- **Default:** `""` (unstamped on first init if the plugin couldn't be resolved)

Records the hv-skills plugin version that was installed when `/hv-init` last ran. Auto-managed: `/hv-init` re-stamps this on every run, including STALE migrations. Don't edit by hand.

[`bin/hv-preflight`](../reference/preflight.md) calls `bin/hv-version-check` after every `/hv-preflight` invocation. If the stamped value differs from the currently-installed plugin's version, preflight prints one informational line to stderr:

```
hv-skills drift: project at 1.16.0, plugin at 1.17.0 — run /hv-init to refresh helpers
```

Re-running `/hv-init` copies the new helpers into `.hv/bin/` and re-stamps `hvSkills.version`. Distinct from `/hv-update` (which compares installed vs latest GitHub release): this is *project drift*, surfaced when the plugin updated under you and the project hasn't been re-initialised yet.

When `autonomy.level` is `"auto"` or `"loop"`, [`/hv-update`](../reference/slash-commands.md#hv-update) Step 4 also offers (or auto-dispatches) `/hv-init` after a plugin upgrade so drift clears without an extra step. Under `"off"`, you still re-run `/hv-init` manually. See [autonomy](autonomy.md) for the full chain semantics.
