# Slash commands

Quick-reference table of every `/hv-*` command. Detailed entries follow below.

| Skill | Description |
|-------|-------------|
| `/hv-init` | Initialize `.hv/` with `BACKLOG.md`, `KNOWLEDGE.md`, `MILESTONES.md`, `CONTEXT.md`, `counters.json`, `config.json`, `status.json`, and helpers |
| `/hv-migrate v4` | One-shot codemod for v3 → v4 upgrades. Rewrites cut-command references across `.hv/` and the project `CLAUDE.md`, migrates `.hv/CONTEXT.md` terms into `KNOWLEDGE.md` (`## Glossary`), removes stale `bin/hv-context-*`. Dry-run default; `--apply` writes; idempotent; refuses umbrella mode (F21) |
| `/hv-config` | Edit `.hv/config.json` interactively (checklist + native pickers) or via positional shortcuts: `/hv-config <key>` jumps to the picker, `/hv-config <key>=<value>` applies directly |
| `/hv-vision` | Brainstorm a project's bigger vision and milestones using Socratic discovery, web research, and a critique pass; writes `MILESTONES.md` plus per-milestone detail files |
| `/hv-brainstorm` | Per-item design exploration before `/hv-plan` — Socratic discovery, 2-3 approaches with tradeoffs, sectioned design with per-section approval; writes `.hv/designs/<ID>.md` which `/hv-plan` reads as soft input |
| `/hv-capture` | Capture bugs, features, and tasks — auto-classifies, assigns priority/size, routes to the correct section. On milestone-spec captures, audits the diff for ship-evidence and asks per flagged title before appending |
| `/hv-go` | Capture an item and immediately implement it — combines `/hv-capture` + `/hv-work` in one pass |
| `/hv-capture --from-github` / `--from-gitlab` | Pull open GitHub/GitLab issues into BACKLOG.md with round-trip closing |
| `/hv-capture --remove` | Remove a captured backlog item and clean up its dependencies — dry-run preview by default, asks before applying |
| `/hv-next` | Review backlog, reconcile active work against git state, suggest the next item, route to `/hv-work` |
| `/hv-pause` | Gracefully stop mid-session — writes a handoff note (next step, hypothesis, mid-edit files) for the next session's `/hv-next` |
| `/hv-plan` | Write an implementation plan for a milestone slice or item (`M01-S01`, `M01-B07`) — task decomposition with verifiable outcomes, named assumptions, open questions; `/hv-work` consults if present |
| `/hv-spike` | Throwaway feasibility experiment on a `spike/<name>` branch — branch never merges, only findings come back as `.hv/spikes/<name>.md` |
| `/hv-work` | Orchestrated parallel implementation with per-task commits; consults `KNOWLEDGE.md` and `.hv/plans/<key>.md` if present. Pass `--preview <ID>` for a read-only peek of the intended approach (files, tests, assumptions, unknowns) that gates high-stakes work without writing anything |
| `/hv-debug` | Systematic bug cycle — reproduce, hypothesize, verify, fix with one atomic commit; auto-escalates to a fresh-context subagent after 3 hypothesis cycles, hard-stops via the Iron Law after 3 failed committed fixes, nudges `/hv-learn` |
| `/hv-decide` | Capture a hard-boundary decision into `.hv/DECISIONS.md` — manually confirmed, never auto-invoked; decisions differ from learnings by being active commitments with explicit forbids/permits |
| `/hv-review` | Two-stage review of a branch (Stage 1 spec-compliance vs `PLAN.md`, Stage 2 code-quality with silent-failure-hunter + decision-violations) vs `KNOWLEDGE.md`; returns PASS / CONCERNS / FAIL. Short-circuits Stage 2 on Stage 1 `FAIL` |
| `/hv-qa` | Product-level QA: executes per-target strategy files (`.hv/qa/<target>.md`) with Playwright / smoke / lighthouse / axe / ZAP / contract runners; emits PASS / CONCERNS / FAIL. Modes — first-run / run / restructure |
| `/hv-ship` | Bundle commits into a PR (or direct merge) with ID-linked body; runs `/hv-review` first by default, plus opt-in second-opinion (`ship.secondOpinion`) and product QA (`ship.qa`) gates. Flags: `--undo` (guided rollback of the last cycle on the base branch) and `--docs` (public-docs maintenance — first-run / after-work / restructure modes; auto-fires inline at ship time when `docs.afterWork: true`) |
| `/hv-learn` | Extract durable session learnings into `KNOWLEDGE.md`, grouped by topic; Opus verification on by default |
| `/hv-refactor` | Full architectural refactor cycle with parallel design + implementation subagents |
| `/hv-release` | Cut a release: walk per-project checklist, bump version, generate notes, tag, push, publish to GitHub/GitLab |
| `/hv-update` | Check for a newer hv-skills release on GitHub and print the exact update command for your install type |

---

Alphabetical reference of every `/hv-*` command.

## /hv-capture

Captures bugs, features, and tasks into [`BACKLOG.md`](hv-folder.md). Auto-classifies each item, assigns priority (P0/P1/P2) for bugs and size (Major/Minor/Cosmetic) for features, and routes it to the correct section with a zero-padded auto-incrementing ID (`[B01]`, `[F01]`, `[T01]`). See [capturing work](../usage/capturing-work.md) for the full flow.

## /hv-config

Interactive editor for [`.hv/config.json`](../usage/configuration.md). Shows current values for all configurable fields, lets you pick which to change from a checklist, then asks each selected key using the same option vocabulary as `/hv-init`. Only the changed keys are written; everything else stays untouched.

## /hv-debug

Systematic root-cause cycle for a single `[B##]` bug: reproduce, hypothesize with the orchestrator model, verify the hypothesis before touching code, fix with the worker model, confirm the reproducer passes, commit, mark complete. Two circuit breakers: (1) if the hypothesize → verify loop iterates 3 times without converging (single-hypothesis mode only), escalates to a fresh-context subagent with a "for-next-agent" brief; (2) if 3 committed fixes fail to resolve the reproducer (counter persisted at `.hv/debug/<session>.json`, survives `/clear`), the Iron Law fires a hard stop — no further agents, surface to the user. Uses the same isolation mode as `/hv-work`, and nudges you toward [`/hv-learn`](../usage/learning.md) when the root cause was non-obvious. See [debugging](../usage/debugging.md) for the full flow.

## /hv-decide

Captures a hard-boundary decision into `.hv/DECISIONS.md`. Manually confirmed, never auto-invoked. Decisions differ from learnings in `KNOWLEDGE.md` by being commitments with explicit forbids/permits; `/hv-work`, `/hv-debug`, `/hv-refactor`, and [`/hv-review`](../usage/review-and-ship.md) consult them as constraints. Accepts `--from-learning <topic>` to promote a hardened `KNOWLEDGE.md` bullet into a decision (rule/why are pre-filled; you supply the forbids/permits), and `--from-spike <name>` to promote a `.hv/spikes/<name>.md` finding the same way (`inconclusive` spikes are refused). See [decisions](../usage/decisions.md) for the full flow.

## /hv-go

Captures an item and immediately implements it in one pass. The item still gets a real ID in `BACKLOG.md`, but the normal backlog-review round-trip is skipped. Use it when you describe a fix or feature and want it done now rather than queued. See [running work](../usage/running-work.md).

## /hv-init

One-time setup that creates the `.hv/` folder with all required files and asks five configuration questions (model profile, isolation mode, merge strategy, quality gates, autonomy level). Re-running on an existing project never re-prompts for keys that already exist. New schema keys added by upgrades trigger a migration for only the missing keys. See also [getting started](../getting-started.md).

## /hv-capture --from-github / --from-gitlab

Pulls open issues from GitHub or GitLab into `BACKLOG.md` via a multiSelect picker (provider chosen by the flag). Lists candidates from the upstream repo(s), subtracts ones already imported, mints IDs for the rest, writes detail files with the upstream URL, and appends entries carrying a `GH: #N` or `GL: #N` cross-reference. An optional manual-gated step applies an `in-progress` label upstream. Round-trip closing is handled separately by `/hv-ship`, which emits `Closes #N` in PR bodies and offers a manual-gated close prompt on direct-push. See [the upstream-issues reference](hv-issues.md) for prerequisites and umbrella-mode semantics.

## /hv-learn

Writes durable knowledge from the current session into `.hv/KNOWLEDGE.md`, grouped by topic. Captures gotchas, project conventions, constraints, debugging insights, and decisions with rationale. Skips anything already obvious from reading the code. After writing, asks once whether to file an `hv-skills` upstream issue (when a bullet describes hv-skills behavior) and once whether to contribute to [runlog.org](https://runlog.org) via `/runlog-author` (when a bullet is about an external dependency: third-party API, library, protocol). Both follow-ups are always manual, never auto-fired. In umbrella mode the write (and `--term` Glossary entries) routes to the cwd/`--repo`-resolved scope — repo-local vs the umbrella-shared `.hv/KNOWLEDGE.md`. See [learning](../usage/learning.md) and [umbrella mode](../usage/umbrella-mode.md) for the full flow.

## /hv-migrate

One-shot codemod for v3 → v4 upgrades, versioned via the required `v4` arg. Rewrites references to 8 commands cut by M01 (`/hv-c`, `/hv-assume`, `/hv-rm`, `/hv-undo`, `/hv-context`, `/hv-docs`, `/hv-issues`, `/hv-map`) across `BACKLOG.md`, plans, designs, handoffs, qa, milestones, `KNOWLEDGE.md`, `DECISIONS.md`, and the project `CLAUDE.md`. Migrates `.hv/CONTEXT.md` terms into `.hv/KNOWLEDGE.md` (`## Glossary`) and removes stale `bin/hv-context-*` files. **Umbrella projects are supported** (F21): each registered sub-repo's `.hv/contexts/<name>/CONTEXT.md` migrates into that sub-repo's `.hv/knowledge/<name>/KNOWLEDGE.md` Glossary, while the umbrella-root `.hv/CONTEXT.md` migrates into the umbrella KNOWLEDGE.md. `--dry-run` is the default; `--apply` writes; `--verbose` adds per-file diffs. Idempotent: a clean second `--apply` rewrites zero files. Backs up every touched file to `.hv/migrate-backup/<timestamp>/` before any write. Refuses on uncommitted changes outside `.hv/`, pre-3.0 project version, or when run inside an existing backup directory.

## /hv-next

Reviews the backlog, reconciles active work against git state, archives old completions, and suggests what to work on next, then routes to `/hv-work` after confirmation. When active streams exist, also reads any handoff notes left by [`/hv-pause`](../usage/pausing-and-resuming.md) and surfaces Stage, Next planned step, Current hypothesis inline alongside each stream. This is the post-`/clear` reorientation flow. See [picking work](../usage/picking-work.md) for the full flow.

## /hv-pause

Stops mid-session by writing a handoff note to `.hv/handoff/<branch>.md` that captures current hypothesis, next planned step, files mid-edit, and gotchas discovered. Use it when the context window is filling or you need to step away mid-`/hv-work`. See [pausing and resuming](../usage/pausing-and-resuming.md) for the full flow.

## /hv-plan

Writes an implementation plan before `/hv-work` runs, keyed under a milestone and unit (e.g. `M01-S01`). Tasks must fit one execution window and each requires a verifiable outcome. `/hv-work` consults the plan automatically if one exists. See [vision and plans](../usage/vision-and-plans.md) for the full flow.

## /hv-qa

Product-level QA: runs the per-target strategy declared in `.hv/qa/<target>.md` and emits a scored verdict. `/hv-qa` does NOT read commits or the diff — that's `/hv-review`'s job. It runs the built artifact: Playwright, smoke scripts, contract tests, Lighthouse, axe, ZAP, whatever the strategy declares, grouped into executable and audit pillars. Three modes — `first-run` (probe surfaces, propose strategy), `run` (execute, score, verdict), `restructure` (audit strategy files). Returns `PASS` / `CONCERNS` / `FAIL`, or `INFRA-FAIL` when required infra is missing. Invoked from `/hv-ship` when `ship.qa: true`; route on verdict gated by `qa.gate` (`"advisory"` reports only, `"blocking"` halts on `FAIL`). See [product QA](../usage/qa.md) for the full flow.

## /hv-refactor

Runs an architectural refactor cycle: explores the codebase for friction, classifies findings as simple or structural, then fixes everything. For structural changes it spawns parallel design agents with competing constraints, compares the results, and recommends the strongest approach before executing. Pauses for user confirmation before proceeding (configurable).

## /hv-release

Cuts a release end-to-end: walks the project's release checklist (`.hv/RELEASE.md` by default; override via `release.checklistPath`) as a preflight gate, bumps the project version (`major`/`minor`/`patch` or explicit semver), generates categorized release notes from commits since the last tag, prepends a section to `CHANGELOG.md` (creating it if absent), creates an annotated git tag, pushes commit + tag, and publishes a release on GitHub or GitLab when origin is set. Auto-detects the version source (`plugin.json`, `package.json`, `pyproject.toml`, `Cargo.toml`, plain `VERSION`), and honors `release.versionFile` override.

The checklist file is per-project and tracked by default — see [release checklist](../usage/review-and-ship.md#release-checklist) for the format. When absent, the skill offers to scaffold a starter (under `autonomy.level: off`) or silently skips the gate (under `auto`/`loop`). Items ending in `(manual)` always interject even in unattended modes.

## /hv-review

Staff-engineer review of a feature branch before it leaves your machine: scopes the diff, pulls relevant `KNOWLEDGE.md` topics, returns PASS / CONCERNS / FAIL with file-and-line evidence. Read-only; no mutations, no commits. See [review and ship](../usage/review-and-ship.md) for the full flow.

## /hv-capture --remove

Removes a captured backlog item and cleans up its dependencies in one operation. Strips the item's entry from `BACKLOG.md`, removes `Related:` cross-references that point to it from other items, deletes any matching detail file (`.hv/bugs/`, `.hv/features/`, `.hv/tasks/`) and plan file (`.hv/plans/`), and strips the item from `status.json`. Items currently active in `status.json` are refused unless `--force` is passed.

Dry-run-by-default: the first pass shows what would change, then an explicit `AskUserQuestion` confirmation gate must be cleared before any writes happen. `ARCHIVE.md` is preserved by default as the historical record; pass `--scrub-archive` to also remove an archived entry and its cross-references there. Accepts one or more comma-separated IDs (e.g. `B07,F03`). Validation is all-or-nothing: if any ID is unknown, the whole batch aborts before any write. See [removing work](../usage/removing-work.md) for the full flow.

## /hv-ship

Finishes a feature branch: runs `/hv-review` (by default), builds a PR body from commit subjects and resolved item IDs, then either opens a GitHub PR or merges directly based on configured strategy. Clears the `status.json` entry and closes referenced items on completion. See [review and ship](../usage/review-and-ship.md).

Two modes folded in via flags:

- `/hv-ship --undo` — guided rollback of the last `/hv-work` cycle on the base branch. Resets the merge commit and restores the cycle's TODO entries to their type sections in `BACKLOG.md`. Direct-merge cycles only (MVP); PR-mode cycles refused with a manual-recovery pointer. Refuses on cycles that have post-merge commits unless `--allow-post-merge` is passed. Defaults to a dry-run preview; the slash command always asks for explicit confirmation before applying. See [rolling back a cycle](../usage/undo.md) for the full flow.
- `/hv-ship --docs` — public-docs maintainer. Scaffolds `<docs.path>/` on first run (discovery + tailored tree + interactive approval), proposes doc updates in after-work mode, or audits and reorganizes in restructure mode (`/hv-ship --docs restructure`). Auto-fires inline at ship time when `docs.afterWork: true` and the post-cycle trigger condition matches.

## /hv-spike

Throwaway feasibility experiment on a dedicated `spike/<name>` branch that is never merged. Answers a specific yes/no/conditional question and records question, what was tried, findings, and decision in `.hv/spikes/<name>.md`. See [spikes](../usage/spikes.md).

## /hv-update

Checks for a newer hv-skills release on GitHub and prints the exact update command for your install type (plugin, stow, repo clone, or override). Never runs the update itself; prints the command for you to run, after which you rerun `/hv-init` in each project to refresh helpers.

## /hv-vision

Brainstorms a project's bigger vision and breaks it into milestones with explicit dependencies and ready/blocked status, writing `MILESTONES.md` and per-milestone detail files under `.hv/milestones/`. Uses Socratic discovery, web research, and deliberate challenge before proposing milestones. See [vision and plans](../usage/vision-and-plans.md) for the full flow.

## /hv-work

Orchestrated parallel implementation: the orchestrator plans tasks and dispatches worker subagents to implement them, each on a feature branch or isolated worktree. Consults `KNOWLEDGE.md` and any matching `.hv/plans/<key>.md` at the start, then registers progress in `status.json` throughout. See [running work](../usage/running-work.md) for the full flow.
