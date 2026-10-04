# FAQ

Common questions about hv.

## How is this different from a TODO file or issue tracker?

That's how every workflow starts, and how most of them stay. The places it tends to drift are the ones hv tries to address: commits stop being atomic and one PR ends up touching six unrelated things, you re-discover the same gotcha three sessions in a row because nothing reads it back, and sessions don't survive `/clear` because you lose the live hypothesis when you step away. `/hv-work` enforces atomic per-task commits, `/hv-learn` writes durable gotchas that future runs auto-consult, `/hv-pause` and `/hv-work` carry intent across context resets. If those problems never bite you, stock Claude Code is fine.

## Is `.hv/` tracked by default?

Yes. Backlog, knowledge, decisions, plans, designs, milestones, and per-item detail files all travel with the repo so team members share context from the first clone. These paths stay gitignored: `.hv/status.json` (per-developer active work), `.hv/repos.json` (umbrella registry with absolute paths), `.hv/config.local.json` (per-developer config overrides, deep-merged on top of `.hv/config.json`), `.hv/handoff/` (per-developer scratch notes from `/hv-pause`), `.hv/qa-runs/` (bulky timestamped artifacts from `/hv-qa`), `.hv/gate-audit.jsonl` (the log of manual-gate approvals), `.hv/workers.json` (the worker slot registry), and `.hv/**/*.lock` (transient sidecar lockfiles).

If you'd rather keep the whole backlog private (solo development, or experimentation that isn't ready to share), add a blanket `.hv/` line to `.gitignore` before your first commit. The default assumes you want context to travel.

## Can I share `.hv/` with my team?

You already are; sharing is the default. A few things to know: item ID counters in `counters.json` are shared, so coordinating ID numbering matters; `KNOWLEDGE.md` accumulates team learnings; `DECISIONS.md` becomes a team contract. Per-developer settings (autonomy level, model preferences) go in the gitignored `.hv/config.local.json` to avoid stepping on each other.

This works well for small teams. For larger ones a real issue tracker is usually a better fit, since the file-based format lacks the conflict-resolution and permissions model that scales.

## What if I'm not using Claude Code?

Codex is supported. `hv skills install` writes the skills to `~/.agents/skills` as well as the Claude Code directory, and Codex can also run as a worker in a round. See [using the skills in Codex](usage/codex-skills.md) and [Codex workers](usage/codex-workers.md). One caveat: skill bodies still name Claude Code tools (`AskUserQuestion`, `TaskCreate`, `Agent`), so a skill may not run end to end in Codex.

The `.hv/` folder, the `BACKLOG.md` format and the `hv` binary are agent-agnostic; you can call `hv` from any shell. Other harnesses are untested.

## Do I need herdr or tmux?

No. Workers in a [parallel round](usage/parallel-rounds.md) get a tab each in herdr or tmux when the orchestrator runs inside one. Without either, `hv round start` picks solo mode and the orchestrator runs each worker as a subagent in its own worktree. With solo mode there is no host to notify you, so questions go on the issue or PR thread. Solo workers share the orchestrator's account and usage limit, and run Claude only, so keep solo rounds to two or three workers.

## How do I update hv when a new release ships?

Run `hv update` (needs `gh`). It detects how you installed hv (Homebrew, the install script, or a dev build) and prints the command, for example `brew update && brew upgrade hv && hv skills update`, or the install script's `curl` line followed by `hv skills update`. It doesn't run the update itself.

`hv skills update` refreshes the installed skills to match the new binary. Nothing else in your projects needs refreshing. Run `hv version --drift` in a project to see whether its stamped version trails the installed one. See [install](install.md#upgrading).

## Does this work with monorepos?

Yes. `.hv/` lives at the root of whatever directory you run `hv init` from. For monorepos you have two reasonable options:

- **One `.hv/` at the monorepo root** for project-wide work and cross-package tracking.
- **One `.hv/` per package or app subdirectory** for scoped backlogs that stay close to the code they track.

`hv` and the managed `CLAUDE.md` blocks resolve relative to the current working directory, so per-package setups work as long as you run hv from inside the package. You can mix both styles in one repo; each `.hv/` is independent.
