# Configuration options

This page documents the questions `/hv-init` and `/hv-config` ask, with their exact option labels and descriptions. For a concept-first walk through each config key, see [`usage/configuration.md`](../usage/configuration.md).

Two sources feed this vocabulary:

- **`/hv-init`** runs FRESH on first setup. It asks all five questions below (Q1–Q5) in one `AskUserQuestion` call, and writes the answers to `.hv/config.json`. On a STALE upgrade, it asks only the questions whose keys are missing.
- **`/hv-config`** lets you edit individual keys later. Its Step 4 reuses the Q1–Q5 option vocabulary verbatim, plus five additional keys (docs path, docs auto-create, docs after-work, git base branch, umbrella mode) that `/hv-init` does not prompt for.

The "(Recommended)" tag on each option marks the install-time default. `/hv-config` retags the user's *current* value as `(current)` instead, so users always see what they're replacing.

## /hv-config invocation shapes

`/hv-config` supports three positional invocation shapes, parsed in Step 1.5 of its skill flow (see `hv-config/SKILL.md`).

| Shape | Behavior |
|-------|----------|
| `/hv-config` (no args) | Full guided flow: category checklist, then key checklist, then value pickers. |
| `/hv-config <key>` | Jumps straight to the value picker for that key, skipping the category and key checklists. |
| `/hv-config <key>=<value>` | Applies the value directly without any interactive prompts, then prints the one-line diff. |

Valid keys, allowed values, and validation rules (enum vs. boolean vs. free-text) are enumerated in `hv-config/SKILL.md` Step 1.5. An unknown key or invalid value stops the skill with an explicit error; it does not fall through to the guided flow.

## Q1 — Models

`header: "Models"`, single-select.

> *"Which model profile should hv-skills use for orchestration and implementation?"*

| Label | Description |
|-------|-------------|
| Balanced — Opus + Sonnet (Recommended) | Opus plans and verifies, Sonnet executes. Strong reasoning where it matters; fast execution elsewhere. |
| Premium — Opus only | Opus for everything. Highest quality, highest cost. |
| Fast — Sonnet only | Sonnet for both roles. Faster and cheaper; fine for well-specified tasks. |
| Minimal — Sonnet + Haiku | Sonnet plans, Haiku executes. Cheapest. Best for mechanical, low-risk work. |

## Q2 — Isolation

`header: "Isolation"`, single-select.

> *"How should `/hv-work` isolate changes from main?"*

| Label | Description |
|-------|-------------|
| Branch (Recommended) | Feature branch in the current worktree. Simple, works everywhere. |
| Worktree | Isolated directory under `.claude/worktrees/`. Lets you keep using main while agents work; supports parallel sessions. |

## Q3 — Integration

`header: "Integration"`, single-select.

> *"How should `/hv-work` and `/hv-ship` integrate finished work?"*

| Label | Description |
|-------|-------------|
| Direct merge (Recommended) | Merge into main with `--no-ff` and delete the branch. Fast solo iteration. |
| GitHub PR | Push the branch and open a PR with `gh pr create`. Required for team review. |

## Q4 — Quality gates

`header: "Gates"`, `multiSelect: true` — a checklist where users can pick any subset (or none).

> *"Which quality gates should run by default? (Uncheck anything you want off.)"*

| Label | Description |
|-------|-------------|
| Review before ship (Recommended) | `/hv-ship` runs `/hv-review` first. FAIL blocks, CONCERNS ask, PASS flows through. |
| Verify learnings (Recommended) | `/hv-learn` dispatches an Opus verifier for a cold pass on new entries. Knowledge quality compounds. |
| Confirm before refactor (Recommended) | `/hv-refactor` pauses for approval after finding friction and after selecting a design. Off = full autonomy. |
| Competing hypotheses (debug) | `/hv-debug` dispatches 3 parallel hypothesis agents from different angles. Better diversity on hard bugs, ~3× orchestrator cost. |

## Q5 — Autonomy

`header: "Autonomy"`, single-select.

> *"How autonomously should hv-skills chain to the next logical step?"*

| Label | Description |
|-------|-------------|
| Off (Recommended) | Skills nudge with a one-line suggestion at decision points. You stay in the driver's seat. |
| Auto chain | One-hop chaining: `/hv-work` → `/hv-learn`, `/hv-debug` → `/hv-ship`, `/hv-ship` → `/hv-learn`, refactor threshold → `/hv-refactor`. Stops after the chained step. |
| Full loop | Auto chain + after each cycle, invoke `/hv-next` and start the next item. Runs until the backlog drains, a guard fails, or a brief is genuinely ambiguous. |

## Mapping table — answers to config values

Each Q1–Q5 answer maps to a single `key.path: value` write in `.hv/config.json`:

| Answer | Config |
|--------|--------|
| Q1 Balanced | `models: {orchestrator: "opus", worker: "sonnet"}` |
| Q1 Premium | `models: {orchestrator: "opus", worker: "opus"}` |
| Q1 Fast | `models: {orchestrator: "sonnet", worker: "sonnet"}` |
| Q1 Minimal | `models: {orchestrator: "sonnet", worker: "haiku"}` |
| Q2 Branch | `work.isolation: "branch"` |
| Q2 Worktree | `work.isolation: "worktree"` |
| Q3 Direct merge | `work.mergeStrategy: "direct"` |
| Q3 GitHub PR | `work.mergeStrategy: "pr"` |
| Q4 includes "Review before ship" | `ship.review: true` (else `false`) |
| Q4 includes "Verify learnings" | `learn.verify: true` (else `false`) |
| Q4 includes "Confirm before refactor" | `refactor.confirmBeforeExecute: true` (else `false`) |
| Q4 includes "Competing hypotheses" | `debug.competingHypotheses: true` (else `false`) |
| Q5 Off | `autonomy.level: "off"` |
| Q5 Auto chain | `autonomy.level: "auto"` |
| Q5 Full loop | `autonomy.level: "loop"` |

## Additional /hv-config keys

`/hv-config` Step 4 also exposes five keys that `/hv-init` does not prompt for. Each reuses the Q1–Q5 option wording where it overlaps; the rest are toggles or free text.

### Docs path

> *"Which directory contains your project documentation?"*

Free text. Default: `docs`. Writes `docs.path`.

### Docs auto-create

> *"Should `/hv-docs` auto-write doc updates after work cycles?"*

`On` / `Off`. Writes `docs.autoCreate`.

### Docs after-work

> *"Should `/hv-docs` run automatically after `/hv-work` and `/hv-ship` finish?"*

`On` / `Off` (Recommended `Off`). Writes `docs.afterWork`.

### Git base branch

> *"Enter the base branch for this project, or leave blank to auto-detect (main / master / trunk / origin HEAD)."*

Free text. Default: `""` (auto-detect). Writes `git.baseBranch`.

### Umbrella mode

> *"Enable umbrella mode? (.hv/ stays at the umbrella; helpers operate per sub-repo. Toggling off does not delete `.hv/repos.json` — registered repos remain.)"*

`On` / `Off`. Toggling off does **not** delete `.hv/repos.json`; registered repos remain and are simply ignored until umbrella mode is re-enabled. To add or remove repos from the registry, re-run `/hv-init` from the umbrella root (idempotent).

## Validation rules

Two rules govern how answers are coerced into config writes:

- **"Other" with custom text.** If the user picks `Other` and types a custom value, honor it only if it's a valid value for that key: `"opus"`/`"sonnet"`/`"haiku"` for models, `"branch"`/`"worktree"` for isolation, `"direct"`/`"pr"` for merge strategy, `"off"`/`"auto"`/`"loop"` for autonomy. Anything else silently falls back to the Recommended value.
- **Plain-text fallback.** When `AskUserQuestion` isn't available (older harness, scripted run), the skill writes Recommended defaults for any pending keys rather than stalling. `/hv-config` Step 4 falls back to one-shot prompts per selected key, validates the reply against the allowed values, and falls back to the current value on invalid input.

## Not asked, just set

A few keys are written without ever being asked:

- `hvSkills.version` — stamp of the hv-skills release that wrote the config. Auto-managed by `/hv-init` and `/hv-update`; not exposed in `/hv-config`.
- `refactor.verifyCommands` — array of shell commands run as CI-shape gates by /hv-refactor Step 7. Silent default `[]` (read-only verification). Set via `hv-config-set refactor.verifyCommands '[...]'`.
- `ship.secondOpinion` — opt-in fresh-eyes adversarial gate in /hv-ship Step 3.5. Silent default `false` (Rule 9). Set via `hv-config-set ship.secondOpinion true` or via `/hv-config` (Quality gates category, call 1).

For the full per-key behavior (defaults, value semantics, and how each setting affects skill execution), see [`usage/configuration.md`](../usage/configuration.md).
