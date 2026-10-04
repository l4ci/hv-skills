# hv cheat sheet

What each `/hv-*` skill does, one line each. For details: [`reference/slash-commands.md`](reference/slash-commands.md).

## Capture & pick
- **`/hv-capture`**: add bugs, features, tasks to the backlog. No code yet. Ends with an optional hand-off to `/hv-work`. Flags: `--from-github`, `--from-gitlab`, `--remove`.
- **`/hv-pause`**: stop cleanly; leave a handoff note for the next session.

## Plan & build
- **`/hv-brainstorm`**: design exploration before planning. For big items.
- **`/hv-plan`**: write the implementation plan with verifiable tasks.
- **`/hv-spike`**: throwaway experiment on a dedicated branch. Only findings come back.
- **`/hv-work`**: execute the plan in parallel with per-task commits. `--preview` for a read-only peek. No argument: reconcile the backlog and suggest the next item.
- **`/hv-debug`**: systematic bug cycle. Reproduce, hypothesize, fix.
- **`/hv-orchestrate`**: run a parallel round: choose the slate, route workers, merge. The `hv round` verbs do the mechanics.

## Review & ship
- **`/hv-review`**: two-stage review (spec match, then code quality).
- **`/hv-qa`**: product-level QA. Playwright, smoke, lighthouse, axe, ZAP.
- **`/hv-ship`**: open a PR or direct merge. `--undo` rolls back; `--docs` syncs public docs.

## Persist
- **`/hv-learn`**: capture reusable lessons in `KNOWLEDGE.md`.
- **`/hv-decide`**: lock in a hard-boundary decision. Manual only.

## Vision & shape
- **`/hv-vision`**: brainstorm milestones and the project roadmap.
- **`/hv-refactor`**: full architectural refactor cycle.

## Maintenance
- **`/hv-release`**: cut a release.

## Verbs, not skills
- **`hv init`** (`hv init umbrella`): scaffold `.hv/` and fill config defaults.
- **`hv config show` / `hv config set`**: read and change settings.
- **`hv update`**: check for a newer release.
- **`hv migrate v4` / `hv migrate issues`**: v3 to v4 codemod; backlog to issues.
- **`hv skills install` / `update` / `status`**: write the skills for Claude Code and Codex, refresh them after an upgrade, compare with the binary.
- **`hv round start` / `assign` / `wait` / `status` / `wind-down`**: run a round: take the lease, hand an issue to a slot, block until a worker needs you, list slots, park everything and release the lease.
- **`hv worker`**: slot registry, worktrees, dispatch, polling and the merge gate (`hv worker gate`).
- **`hv doctor`**: preflight for git, host, forge, accounts, hooks, skills and Codex.
- **`hv reap`**: preview leftovers a round left behind; `--apply` removes those holding no work.
- **`hv keepalive run`**: restart the orchestrator in its pane when it exits with a fresh handoff.
- **`hv limit watch`**: sleep until a usage limit resets, or switch accounts.
- **`hv hook` / `hv statusline`**: Claude Code hooks and the statusline command that hand the orchestrator off before its context fills.
- **`hv verdict add` / `route` / `show`**: record typed review, second-opinion and QA verdicts and route on them.

See [parallel rounds](usage/parallel-rounds.md) and [unattended rounds](usage/unattended-rounds.md).
