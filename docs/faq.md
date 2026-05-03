# FAQ

Common questions about hv-skills.

## How is this different from a TODO file or issue tracker?

That's how every workflow starts, and how most of them stay. The places it tends to drift are the ones hv-skills tries to address: commits stop being atomic and one PR ends up touching six unrelated things, you re-discover the same gotcha three sessions in a row because nothing reads it back, and sessions don't survive `/clear` because you lose the live hypothesis when you step away. `/hv-work` enforces atomic per-task commits, `/hv-learn` writes durable gotchas that future runs auto-consult, and `/hv-pause` / `/hv-resume` carry intent across context resets. If those problems never bite you, stock Claude Code is fine.

## Why is `.hv/` gitignored by default?

The backlog is personal context for your machine: your current hypotheses, your captures, your handoff notes. Other people on the team have their own captures and milestones. Sharing a backlog as a work queue belongs in an issue tracker, not in markdown files in the repo.

If you want to share state with a team you can opt in by removing `.hv/` from `.gitignore`, but that's a choice you make on purpose, not the default.

## Can I share `.hv/` with my team?

Yes. Remove `.hv/` from `.gitignore` and commit the folder. A few things change once you do: item ID counters become shared, so coordinating ID numbering starts to matter; `status.json` reflects whoever last reconciled; and `KNOWLEDGE.md` ends up with team content rather than personal notes.

This works for small teams. For larger ones a real issue tracker is usually a better fit, since the file-based format doesn't have the conflict-resolution or permissions model that scales.

## What if I'm not using Claude Code?

hv-skills is built around Claude Code's skill system, `AskUserQuestion`, and subagent dispatch. The `.hv/` folder, CLI helpers, and `TODO.md` format are agent-agnostic and work on their own; you can call the helpers from any shell. The slash commands themselves only run inside Claude Code.

Other agent harnesses with comparable primitives (Gemini CLI, some Copilot builds) may load the skills with reduced functionality. Where `AskUserQuestion` isn't available, those interactions fall back to plain text prompts instead of native UI. Don't expect full functionality outside Claude Code.

## How do I update hv-skills when a new release ships?

Run `/hv-update`. It detects your install type (plugin, repo clone, or stow), reads the current version, fetches the latest GitHub release, and prints the exact update command for your setup. It doesn't run the update itself, since there are too many install paths to get right automatically.

After updating, rerun `/hv-init` in each project to refresh `.hv/bin/` with any new helpers.

Requires `gh` on the PATH. See the [/hv-update reference](reference/slash-commands.md#hv-update) for details.

## Does this work with monorepos?

Yes. `.hv/` lives at the root of whatever directory you run `/hv-init` from. For monorepos you have two reasonable options:

- **One `.hv/` at the monorepo root** for project-wide work and cross-package tracking.
- **One `.hv/` per package or app subdirectory** for scoped backlogs that stay close to the code they track.

The CLI helpers and managed `CLAUDE.md` blocks resolve relative to the current working directory, so per-package setups work as long as you run hv-skills from inside the package. You can mix both styles in one repo; each `.hv/` is independent.
