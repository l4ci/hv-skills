# hv-skills cheat sheet

What does each `/hv-*` skill do? One line each. For details: [`reference/slash-commands.md`](reference/slash-commands.md).

## Capture & pick
- **`/hv-capture`** — add bugs, features, tasks to the backlog. No code yet. Flags: `--from-github`, `--from-gitlab`, `--remove`.
- **`/hv-go`** — capture + implement in one shot.
- **`/hv-next`** — show the backlog, suggest what to work on next.
- **`/hv-pause`** — stop cleanly; leave a handoff note for next session.

## Plan & build
- **`/hv-brainstorm`** — design exploration before planning. For big items.
- **`/hv-plan`** — write the implementation plan with verifiable tasks.
- **`/hv-spike`** — throwaway experiment on a dedicated branch. Only findings come back.
- **`/hv-work`** — execute the plan in parallel with per-task commits. `--preview` for a read-only peek.
- **`/hv-debug`** — systematic bug cycle: reproduce → hypothesize → fix.

## Review & ship
- **`/hv-review`** — two-stage review (spec match, then code quality).
- **`/hv-qa`** — product-level QA: Playwright, smoke, lighthouse, axe, ZAP.
- **`/hv-ship`** — open a PR or direct merge. `--undo` rolls back; `--docs` syncs public docs.

## Persist
- **`/hv-learn`** — capture reusable lessons in `KNOWLEDGE.md`.
- **`/hv-decide`** — lock in a hard-boundary decision. Manual only.

## Vision & shape
- **`/hv-vision`** — brainstorm milestones and the project roadmap.
- **`/hv-refactor`** — full architectural refactor cycle.

## Maintenance
- **`/hv-init`** — scaffold `.hv/` in a new project.
- **`/hv-config`** — change settings.
- **`/hv-update`** — check for a newer release.
- **`/hv-migrate v4`** — codemod for v3 → v4 upgrades.
- **`/hv-release`** — cut a release.
