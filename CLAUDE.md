<!-- hv-knowledge-start -->
## Project Knowledge

Durable learnings live in `.hv/KNOWLEDGE.md`. Consult it when work touches these topics:

- Build & Tooling: Helpers
- Build & Tooling: Umbrella & Worktrees
- Build & Tooling: Smoke & Plugin
- Documentation
- Skill Authoring: Conventions
- Skill Authoring: Workers & Parallelism

<!-- hv-knowledge-end -->

<!-- hv-vision-start -->
## Project Vision

Active milestones live in `.hv/MILESTONES.md` (detail in `.hv/milestones/MNN.md`). Tag captured items with their milestone via the `Milestone:` field where applicable.

- **M04** — Helper-convention cleanup (depends: M02, M03)
<!-- hv-vision-end -->

## Working in this repo

**Never edit anything inside `.hv/`.** That folder is the project's gitignored runtime — it gets regenerated when skills are updated (re-running `/hv-init` or a skill update copies fresh files from canonical `bin/` and re-seeds data). Any edit you make there will be overwritten on the next update, so it's wasted work and obscures intent. All real changes go in canonical sources: skill folders (`hv-*/SKILL.md`), `bin/`, `docs/`, `test/`, etc.

<!-- hv-skills-start -->
## hv-skills

This project uses hv-skills for backlog tracking, planning, and skill orchestration. State lives in `.hv/` — the gitignored runtime that gets regenerated on skill updates; never edit it by hand. Edit canonical sources (`bin/`, `hv-*/`, `docs/`, `test/`) only.

**Capture & pick** — `/hv-capture` (alias `/hv-c`), `/hv-go`, `/hv-rm`, `/hv-next`, `/hv-pause`
**Plan & build** — `/hv-plan`, `/hv-spike`, `/hv-assume`, `/hv-work`, `/hv-debug`
**Review & ship** — `/hv-review`, `/hv-ship`
**Persist** — `/hv-learn` (durable knowledge), `/hv-decide` (hard boundaries — manual only)
**Vision & docs** — `/hv-vision`, `/hv-docs`, `/hv-refactor`
**Maintenance** — `/hv-init`, `/hv-config`, `/hv-update`, `/hv-release`

Before acting on work that touches a topic listed in `## Project Knowledge`, `## Project Decisions`, or `## Project Vision`, pull only the relevant sections:

- `.hv/bin/hv-knowledge-query <topic>…`
- `.hv/bin/hv-decisions-query <topic>…`
- `.hv/bin/hv-vision-active` (then `.hv/bin/hv-todo-by-milestone <id>` per active milestone)
<!-- hv-skills-end -->

<!-- hv-decisions-start -->
## Project Decisions

Hard boundaries live in `.hv/DECISIONS.md`. Consult them before acting on work that touches these topics:

- Build & Tooling
- Skill Authoring

<!-- hv-decisions-end -->
