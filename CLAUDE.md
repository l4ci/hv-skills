<!-- hv-knowledge-start -->
## Project Knowledge

Durable learnings live in `.hv/KNOWLEDGE.md`. Consult it when work touches these topics:

- Architecture
- Build & Tooling

<!-- hv-knowledge-end -->

<!-- hv-vision-start -->
## Project Vision

Active milestones live in `.hv/MILESTONES.md` (detail in `.hv/milestones/MNN.md`). Tag captured items with their milestone via the `Milestone:` field where applicable.

- **M01** — "v4.0: The Loop, simplified" (depends: —)
<!-- hv-vision-end -->

## Working in this repo

**Never edit anything inside `.hv/`.** That folder is the project's gitignored runtime — it gets regenerated when skills are updated (re-running `/hv-init` or a skill update copies fresh files from canonical `bin/` and re-seeds data). Any edit you make there will be overwritten on the next update, so it's wasted work and obscures intent. All real changes go in canonical sources: skill folders (`hv-*/SKILL.md`), `bin/`, `docs/`, `test/`, etc.

**Run `bash test/smoke.sh` only at integration boundaries — not per task.** The full 30-section suite is slow (sequential by design, state accumulates across sections). Per-task verification inside `/hv-work` and `/hv-debug` stays structural: `git status` / `git diff` / targeted greps / re-running the specific reproducer. Run the full smoke in `/hv-ship` and `/hv-review` (pre-merge / pre-PR), or when explicitly asked. If a single section is clearly relevant to the change in flight, sourcing just that section file in a sandbox is fine; defer the full run to ship time.

<!-- hv-skills-start -->
## hv-skills

This project uses hv-skills for backlog tracking, planning, and skill orchestration. State lives in `.hv/` — the gitignored runtime that gets regenerated on skill updates; never edit it by hand. Edit canonical sources (`bin/`, `hv-*/`, `docs/`, `test/`) only.

**Capture & pick** — `/hv-capture` (with `--remove <ID>` to delete items), `/hv-go`, `/hv-next`, `/hv-pause`
**Plan & build** — `/hv-brainstorm`, `/hv-plan`, `/hv-spike`, `/hv-work` (`--preview` for read-only peek), `/hv-debug`
**Review & ship** — `/hv-review`, `/hv-ship` (`--undo` to roll back the last cycle, `--docs` to maintain public docs)
**Persist** — `/hv-learn` (durable knowledge; `--term <name>` for glossary), `/hv-decide` (hard boundaries — manual only)
**Vision & maps** — `/hv-vision`, `/hv-refactor`
**Maintenance** — `/hv-init`, `/hv-config`, `/hv-update`, `/hv-release`

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
