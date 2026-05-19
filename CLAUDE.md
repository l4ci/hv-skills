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

Active milestones live in `.hv/MILESTONES.md` (detail in `.hv/milestones/MNN.md`). Tag captured items with their milestone via the `Milestone:` field where applicable.

- **M01** — "v4.0: The Loop, simplified" (depends: —)
- **M06** — v4.1: umbrella-aware persistence (depends: M01) ⚠ blocked
<!-- hv-vision-end -->

## Working in this repo

**Don't edit `.hv/` by hand — use the skill helpers.** Most of `.hv/` is tracked (knowledge, decisions, backlog, milestones, designs, plans, spikes, per-item detail, release checklist, config). Six paths stay gitignored: `.hv/bin/` (regenerated mirror of canonical `bin/`, overwritten on every `/hv-init`); `.hv/status.json` and `.hv/repos.json` (per-developer runtime state); `.hv/config.local.json` (per-developer config overrides deep-merged on top of `.hv/config.json` by `load_config()`); `.hv/handoff/` (per-developer `/hv-pause` scratch); and `.hv/qa-runs/` (bulky `/hv-qa` artifacts). Tracked `.hv/` content is skill-owned — capture via `/hv-capture`, learn via `/hv-learn`, decide via `/hv-decide`, etc. Real code/skill changes still go in canonical sources: skill folders (`hv-*/SKILL.md`), `bin/`, `docs/`, `test/`.

**Run `bash test/smoke.sh` only at integration boundaries — not per task.** The full 30-section suite is slow (sequential by design, state accumulates across sections). Per-task verification inside `/hv-work` and `/hv-debug` stays structural: `git status` / `git diff` / targeted greps / re-running the specific reproducer. Run the full smoke in `/hv-ship` and `/hv-review` (pre-merge / pre-PR), or when explicitly asked. If a single section is clearly relevant to the change in flight, sourcing just that section file in a sandbox is fine; defer the full run to ship time.

<!-- hv-skills-start -->
## hv-skills

This project uses hv-skills for backlog tracking, planning, and skill orchestration. State lives in `.hv/` — most content is tracked (backlog, knowledge, decisions, plans, designs, milestones) so it travels with the repo. Only `.hv/bin/` (regenerated mirror of canonical `bin/`, overwritten on every `/hv-init`), `.hv/status.json`, `.hv/repos.json`, `.hv/config.local.json`, `.hv/handoff/`, and `.hv/qa-runs/` are gitignored. Use the skill helpers to update tracked content (never edit by hand). Edit canonical sources (`bin/`, `hv-*/`, `docs/`, `test/`) for skill changes.

**Capture & pick** — `/hv-capture` (with `--remove <ID>` to delete items), `/hv-go`, `/hv-next`, `/hv-pause`
**Plan & build** — `/hv-brainstorm`, `/hv-plan`, `/hv-spike`, `/hv-work` (`--preview` for read-only peek), `/hv-debug`
**Review & ship** — `/hv-review`, `/hv-qa` (opt-in gate via `ship.qa`), `/hv-ship` (`--undo` to roll back the last cycle, `--docs` to maintain public docs)
**Persist** — `/hv-learn` (durable knowledge; `--term <name>` for glossary), `/hv-decide` (hard boundaries — manual only)
**Vision & maps** — `/hv-vision`, `/hv-refactor`
**Maintenance** — `/hv-init`, `/hv-config`, `/hv-update`, `/hv-migrate` (v3→v4 codemod), `/hv-release`

Before acting on work that touches a topic listed in `## Project Knowledge`, `## Project Decisions`, or `## Project Vision`, pull only the relevant sections:

- `.hv/bin/hv-knowledge-query <topic>…`
- `.hv/bin/hv-decisions-query <topic>…`
- `.hv/bin/hv-glossary-read <term>…` (terms live as nested-bullet entries under `## Glossary` in `.hv/KNOWLEDGE.md`)
- `.hv/bin/hv-vision-active` (then `.hv/bin/hv-todo-by-milestone <id>` per active milestone)
<!-- hv-skills-end -->

<!-- hv-decisions-start -->
## Project Decisions

Hard boundaries live in `.hv/DECISIONS.md`. Consult them before acting on work that touches these topics:

- Architecture

<!-- hv-decisions-end -->

<!-- hv-map-start -->
## Project Map

Subsystems live in `.hv/MAP.md` (detail in `.hv/map/<name>.md`). Pull with `.hv/bin/hv-map-query <name>`.

- _(no subsystems yet — write `.hv/map/<name>.md` as you discover subsystems)_
<!-- hv-map-end -->

<!-- hv-qa-start -->
## Project QA

QA strategies live in `.hv/QA.md` (detail in `.hv/qa/<target>.md`). Pull with `.hv/bin/hv-qa-query <target>`. `/hv-qa run` consumes these; the skill never hardcodes runners.

- _(no QA strategy yet — run `/hv-qa first-run` to scaffold)_
<!-- hv-qa-end -->
