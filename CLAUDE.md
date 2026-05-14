<!-- hv-knowledge-start -->
## Project Knowledge

Durable learnings live in `.hv/KNOWLEDGE.md`. Consult it when work touches these topics:

- Build & Tooling

<!-- hv-knowledge-end -->

<!-- hv-vision-start -->
## Project Vision

Project milestones live in `.hv/MILESTONES.md`.

_(no milestones yet — run `/hv-vision` to brainstorm)_
<!-- hv-vision-end -->

## Working in this repo

**Never edit anything inside `.hv/`.** That folder is the project's gitignored runtime — it gets regenerated when skills are updated (re-running `/hv-init` or a skill update copies fresh files from canonical `bin/` and re-seeds data). Any edit you make there will be overwritten on the next update, so it's wasted work and obscures intent. All real changes go in canonical sources: skill folders (`hv-*/SKILL.md`), `bin/`, `docs/`, `test/`, etc.

**Run `bash test/smoke.sh` only at integration boundaries — not per task.** The full 30-section suite is slow (sequential by design, state accumulates across sections). Per-task verification inside `/hv-work` and `/hv-debug` stays structural: `git status` / `git diff` / targeted greps / re-running the specific reproducer. Run the full smoke in `/hv-ship` and `/hv-review` (pre-merge / pre-PR), or when explicitly asked. If a single section is clearly relevant to the change in flight, sourcing just that section file in a sandbox is fine; defer the full run to ship time.

<!-- hv-skills-start -->
## hv-skills

This project uses hv-skills for backlog tracking, planning, and skill orchestration. State lives in `.hv/` — the gitignored runtime that gets regenerated on skill updates; never edit it by hand. Edit canonical sources (`bin/`, `hv-*/`, `docs/`, `test/`) only.

**Capture & pick** — `/hv-capture` (alias `/hv-c`), `/hv-go`, `/hv-rm`, `/hv-next`, `/hv-pause`
**Plan & build** — `/hv-brainstorm`, `/hv-plan`, `/hv-spike`, `/hv-assume`, `/hv-work`, `/hv-debug`
**Review & ship** — `/hv-review`, `/hv-ship`
**Persist** — `/hv-learn` (durable knowledge), `/hv-decide` (hard boundaries — manual only), `/hv-context` (terminology glossary)
**Vision & docs** — `/hv-vision`, `/hv-docs`, `/hv-refactor`
**Maintenance** — `/hv-init`, `/hv-config`, `/hv-update`, `/hv-release`

Before acting on work that touches a topic listed in `## Project Knowledge`, `## Project Decisions`, `## Project Vision`, or `## Project Context`, pull only the relevant sections:

- `.hv/bin/hv-knowledge-query <topic>…`
- `.hv/bin/hv-decisions-query <topic>…`
- `.hv/bin/hv-context-query <term>…`
- `.hv/bin/hv-vision-active` (then `.hv/bin/hv-todo-by-milestone <id>` per active milestone)
<!-- hv-skills-end -->

<!-- hv-decisions-start -->
## Project Decisions

Hard boundaries live in `.hv/DECISIONS.md`. Consult them before acting on work that touches these topics:

- _(no decisions yet — run `/hv-decide` to capture a hard boundary)_

<!-- hv-decisions-end -->

<!-- hv-map-start -->
## Project Map

Subsystems live in `.hv/MAP.md` (detail in `.hv/map/<name>.md`). Pull with `.hv/bin/hv-map-query <name>`.

- _(no subsystems yet — run `/hv-map first-run` to scaffold)_
<!-- hv-map-end -->

<!-- hv-context-start -->
## Project Context

Domain terminology lives in `.hv/CONTEXT.md`. Use these canonical names; if a term you're using conflicts (synonym or drift), call it out.

- _(no terms yet — run `/hv-context` to capture domain terminology)_
<!-- hv-context-end -->
