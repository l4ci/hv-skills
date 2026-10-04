## Parallel rounds

Larger rounds run as one orchestrator plus several workers in parallel, each worker a
standing agent with its own git worktree and herdr workspace, taking one issue at a time.
Agents are named people (ben, dana, nia, kit) reused across issues; work goes on
`<agent>/<issue>-<slug>` and its worktree parks on `park/<agent>` between issues. Workers
implement, verify and open a PR; they never merge. The orchestrator assigns issues, relays
decisions, merges PRs and re-verifies on `main` after every merge.

**"You are the orchestrator" is the kickoff trigger: invoke the `hv-orchestrate` skill.**
Read it and `docs/contributing/rounds.md` (the project brief: gate, repo rules, roster)
before running or joining a round. A worker reads `references/worker-contract.md`.

<!-- hv-knowledge-start -->
## Project Knowledge

Durable learnings live in `.hv/KNOWLEDGE.md`. Consult it when work touches these topics:

- Architecture: Module extraction & migration safety
- Architecture: Helper conventions & invariants
- Architecture: Skill authoring
- Build & Tooling: Helpers & migrations
- Build & Tooling: Smoke testing
- Build & Tooling: Git & isolation

<!-- hv-knowledge-end -->

<!-- hv-vision-start -->
## Project Vision

Project milestones live in `.hv/MILESTONES.md`.

_(no active milestones — all shipped or archived; run `/hv-vision` to plan more)_
<!-- hv-vision-end -->

## Working in this repo

**Don't edit `.hv/` by hand — use the skills and `hv` verbs.** Most of `.hv/` is tracked (knowledge, decisions, backlog, milestones, designs, plans, spikes, per-item detail, release checklist, config). These paths stay gitignored: `.hv/status.json` and `.hv/repos.json` (per-developer runtime state); `.hv/config.local.json` (per-developer config overrides deep-merged on top of `.hv/config.json`); `.hv/handoff/` (per-developer `/hv-pause` scratch); `.hv/qa-runs/` (bulky `/hv-qa` artifacts); `.hv/gate-audit.jsonl` (per-developer log of manual-gate approvals); `.hv/workers.json` (per-developer worker slot registry); and `.hv/**/*.lock` (transient sidecar lockfiles `hv` takes around read-modify-write). Tracked `.hv/` content is skill-owned — capture via `/hv-capture`, learn via `/hv-learn`, decide via `/hv-decide`, etc. Real code/skill changes still go in canonical sources: skill folders (`hv-*/SKILL.md`), `cmd/` and `internal/` (the `hv` binary), `docs/`, `test/`.

**Run `bash test/smoke.sh` only at integration boundaries — not per task.** The full smoke suite is slow (sequential by design, state accumulates across sections). Per-task verification inside `/hv-work` and `/hv-debug` stays structural: `git status` / `git diff` / targeted greps / re-running the specific reproducer. Run the full smoke in `/hv-ship` and `/hv-review` (pre-merge / pre-PR), or when explicitly asked. If a single section is clearly relevant to the change in flight, sourcing just that section file in a sandbox is fine; defer the full run to ship time.

<!-- hv-skills-start -->
## hv-skills

This project uses hv-skills for backlog tracking, planning, and skill orchestration. State lives in `.hv/` — most content is tracked (backlog, knowledge, decisions, plans, designs, milestones) so it travels with the repo. Only `.hv/status.json`, `.hv/repos.json`, `.hv/config.local.json`, `.hv/handoff/`, `.hv/qa-runs/`, `.hv/verdicts.json`, `.hv/gate-audit.jsonl`, `.hv/workers.json`, and `.hv/**/*.lock` files are gitignored. Use the skills and `hv` verbs to update tracked content (never edit by hand). Edit canonical sources (`bin/`, `hv-*/`, `docs/`, `test/`) for skill changes.

**Capture & pick** — `/hv-capture` (with `--remove <ID>` to delete items; offers to hand off to `/hv-work`), `/hv-pause`
**Plan & build** — `/hv-brainstorm`, `/hv-plan`, `/hv-spike`, `/hv-work` (no argument reconciles active work and suggests the next item; `--preview` for read-only peek), `/hv-debug`
**Rounds** — `/hv-orchestrate` (run a parallel round as the orchestrator)
**Review & ship** — `/hv-review`, `/hv-qa` (opt-in gate via `ship.qa`), `/hv-ship` (`--undo` to roll back the last cycle, `--docs` to maintain public docs)
**Persist** — `/hv-learn` (durable knowledge; `--term <name>` for glossary), `/hv-decide` (hard boundaries — manual only)
**Vision & maps** — `/hv-vision`, `/hv-refactor`
**Maintenance** — `/hv-release`. Setup and upkeep are `hv` verbs: `hv init`, `hv config`, `hv update`, `hv migrate`

Before acting on work that touches a topic listed in `## Project Knowledge`, `## Project Decisions`, or `## Project Vision`, pull only the relevant sections:

- `hv knowledge query <topic>…`
- `hv decisions query <topic>…`
- `hv glossary read <term>…` (terms live as nested-bullet entries under `## Glossary` in `.hv/KNOWLEDGE.md`)
- `hv milestone active` (then `hv backlog ids --milestone <id>` per active milestone)
<!-- hv-skills-end -->

<!-- hv-decisions-start -->
## Project Decisions

Hard boundaries live in `.hv/DECISIONS.md`. Consult them before acting on work that touches these topics:

- Architecture

<!-- hv-decisions-end -->

<!-- hv-map-start -->
## Project Map

Subsystems live in `.hv/MAP.md` (detail in `.hv/map/<name>.md`). Pull with `hv map query <name>`.

- _(no subsystems yet — write `.hv/map/<name>.md` as you discover subsystems)_
<!-- hv-map-end -->

<!-- hv-qa-start -->
## Project QA

QA strategies live in `.hv/QA.md` (detail in `.hv/qa/<target>.md`). Pull with `hv qa query <target>`. `/hv-qa run` consumes these; the skill never hardcodes runners.

- _(no QA strategy yet — run `/hv-qa first-run` to scaffold)_
<!-- hv-qa-end -->
