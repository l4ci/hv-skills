# Slash commands

Alphabetical reference of every `/hv-*` command.

## /hv-assume

Prints the orchestrator's intended approach for an item, slice, or milestone (files it would touch, tests it would add, assumptions it is making, and known unknowns) without writing anything. Use it as a cheap gate before `/hv-work` for items where a wrong turn is expensive to undo. See [next and status](../usage/next-and-status.md) for how `/hv-next` surfaces it automatically for large or risky picks.

## /hv-c

Shortcut alias for `/hv-capture`. Identical behavior; saves keystrokes when capturing is frequent. See [capturing work](../usage/capturing-work.md) for the full flow.

## /hv-capture

Captures bugs, features, and tasks into `TODO.md`. Auto-classifies each item, assigns priority (P0/P1/P2) for bugs and size (Major/Minor/Cosmetic) for features, and routes it to the correct section with a zero-padded auto-incrementing ID (`[B01]`, `[F01]`, `[T01]`). See [capturing work](../usage/capturing-work.md) for the full flow.

## /hv-config

Interactive editor for `.hv/config.json`. Shows current values for all configurable fields, lets you pick which to change from a checklist, then asks each selected key using the same option vocabulary as `/hv-init`. Only the changed keys are written; everything else is left untouched.

## /hv-debug

Systematic root-cause cycle for a single `[B##]` bug: reproduce, hypothesize with the orchestrator model, verify the hypothesis before touching code, fix with the worker model, confirm the reproducer passes, commit, and mark complete. Uses the same isolation mode as `/hv-work` and nudges you toward `/hv-learn` when the root cause was non-obvious. See [debugging](../usage/debugging.md) for the full flow.

## /hv-decide

Captures a hard-boundary decision into `.hv/DECISIONS.md`. Manually confirmed, never auto-invoked. Decisions differ from learnings in `KNOWLEDGE.md` by being active commitments with explicit forbids/permits; `/hv-work`, `/hv-debug`, `/hv-refactor`, and `/hv-review` consult them as constraints. See [decisions](../usage/decisions.md) for the full flow.

## /hv-docs

Manages the public documentation site under the configured `docs.path` directory. Handles creating, updating, and organizing docs pages so project documentation stays in sync with the codebase.

## /hv-go

Captures an item and immediately implements it in one pass. The item still gets a real ID in `TODO.md`, but the normal backlog-review round-trip is skipped. Use it when you describe a fix or feature and want it done now rather than queued. See [running work](../usage/running-work.md) for the full flow.

## /hv-init

One-time setup that creates the `.hv/` folder with all required files and asks five configuration questions (model profile, isolation mode, merge strategy, quality gates, autonomy level). Re-running on an existing project never re-prompts for keys that already exist; new schema keys added by upgrades trigger a migration for only the missing keys. See also [getting started](../getting-started.md).

## /hv-learn

Writes durable knowledge from the current session into `.hv/KNOWLEDGE.md`, grouped by topic. Captures gotchas, project conventions, constraints, debugging insights, and decisions with rationale; skips anything already obvious from reading the code. See [learning](../usage/learning.md) for the full flow.

## /hv-next

Reviews the backlog, reconciles active work against git state, archives old completions, and suggests what to work on next, then routes to `/hv-work` after confirmation. See [next and status](../usage/next-and-status.md) for the full flow.

## /hv-pause

Gracefully stops mid-session by writing a handoff note to `.hv/handoff/<branch>.md` that captures current hypothesis, next planned step, files mid-edit, and gotchas discovered. Use it when the context window is filling or you need to step away mid-`/hv-work`. See [pausing and resuming](../usage/pausing-and-resuming.md) for the full flow.

## /hv-plan

Writes an implementation plan as a first-class artifact before `/hv-work` runs, keyed under a milestone and unit (e.g. `M01-S01`). Tasks must fit one execution window and each requires a verifiable outcome; `/hv-work` consults the plan automatically if one exists. See [vision and plans](../usage/vision-and-plans.md) for the full flow.

## /hv-refactor

Runs a full architectural refactor cycle: explores the codebase for friction, classifies findings as simple or structural, and fixes everything. For structural changes it spawns parallel design agents with competing constraints, compares the results, and recommends the strongest approach before executing. Pauses for user confirmation before proceeding (configurable).

## /hv-release

Cuts a release end-to-end: bumps the project version (`major`/`minor`/`patch` or explicit semver), generates categorized release notes from commits since the last tag, prepends a section to `CHANGELOG.md` (creating it if absent), creates an annotated git tag, pushes commit + tag, and publishes a release on GitHub or GitLab when origin is set. Auto-detects the version source (`plugin.json`, `package.json`, `pyproject.toml`, `Cargo.toml`, plain `VERSION`); honors `release.versionFile` override.

## /hv-resume

Reorients a fresh session or post-`/clear` context by reading active streams, recent commit subjects, and any handoff notes left by `/hv-pause`. Routes automatically to `/hv-work`, `/hv-ship`, or `/hv-next` depending on the state of each branch. See [pausing and resuming](../usage/pausing-and-resuming.md) for the full flow.

## /hv-review

Staff-engineer review of a feature branch before it leaves your machine: scopes the diff, pulls relevant `KNOWLEDGE.md` topics, and returns PASS / CONCERNS / FAIL with file-and-line evidence. Read-only; no mutations, no commits. See [review and ship](../usage/review-and-ship.md) for the full flow.

## /hv-ship

Finishes a feature branch: runs `/hv-review` (by default), builds a PR body from commit subjects and resolved item IDs, then either opens a GitHub PR or merges directly based on configured strategy. Clears the `status.json` entry and closes referenced items on completion. See [review and ship](../usage/review-and-ship.md) for the full flow.

## /hv-spike

Throwaway feasibility experiment on a dedicated `spike/<name>` branch that is never merged. Answers a specific yes/no/conditional question and records question, what was tried, findings, and decision in `.hv/spikes/<name>.md`. See [spikes](../usage/spikes.md) for the full flow.

## /hv-status

Compact read-only project state glance: prints backlog counts, active work streams, the three most recent completions, knowledge-topic count, and archive size, then stops. Lighter than `/hv-next`; use it to orient before deciding what to do next. See [next and status](../usage/next-and-status.md) for context.

## /hv-update

Checks for a newer hv-skills release on GitHub and prints the exact update command for your install type (plugin, stow, repo clone, or override). Never runs the update itself: prints the command for you to run, after which you rerun `/hv-init` in each project to refresh helpers.

## /hv-vision

Brainstorms a project's bigger vision and breaks it into milestones with explicit dependencies and ready/blocked status, writing `MILESTONES.md` and per-milestone detail files under `.hv/milestones/`. Combines Socratic discovery, web research, and deliberate challenge before proposing milestones. See [vision and plans](../usage/vision-and-plans.md) for the full flow.

## /hv-work

Orchestrated parallel implementation: the orchestrator plans tasks and dispatches worker subagents to implement them, each on a feature branch or isolated worktree. Consults `KNOWLEDGE.md` and any matching `.hv/plans/<key>.md` at the start; registers progress in `status.json` throughout. See [running work](../usage/running-work.md) for the full flow.
