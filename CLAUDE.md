<!-- hv-knowledge-start -->
## Project Knowledge

Durable learnings live in `.hv/KNOWLEDGE.md`. Consult it when work touches these topics:

- Build & Tooling
- Documentation
- Skill Authoring

<!-- hv-knowledge-end -->

<!-- hv-vision-start -->
## Project Vision

Active milestones live in `.hv/MILESTONES.md` (detail in `.hv/milestones/MNN.md`). Tag captured items with their milestone via the `Milestone:` field where applicable.

- **M01** — User-Guide Maintainer (/hv-docs) (depends: —)

<!-- hv-vision-end -->

## Working in this repo

**Never edit anything inside `.hv/`.** That folder is the project's gitignored runtime — it gets regenerated when skills are updated (re-running `/hv-init` or a skill update copies fresh files from canonical `bin/` and re-seeds data). Any edit you make there will be overwritten on the next update, so it's wasted work and obscures intent. All real changes go in canonical sources: skill folders (`hv-*/SKILL.md`), `bin/`, `docs/`, `test/`, etc.
