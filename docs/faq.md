# FAQ

Common questions about hv-skills.

## How is this different from a TODO file or issue tracker?

That's how every workflow starts and how most stay. The drift happens at three places hv-skills addresses by design: (1) commits stop being atomic — one PR ends up touching six unrelated things; (2) knowledge stops compounding — you re-discover the same gotcha three sessions in a row because nothing reads it back; (3) sessions don't survive `/clear` — you lose the live hypothesis when you step away. `/hv-work` enforces atomic per-task commits, `/hv-learn` writes durable gotchas that future runs auto-consult, and `/hv-pause` / `/hv-resume` carry intent across context resets. If those three never bite you, stock Claude Code is fine. If they do, that's why hv-skills exists.

## Why is `.hv/` gitignored by default?

The backlog is personal context for your machine — your in-flight hypotheses, your captures, your handoff notes. Other people on the team have their own captures and milestones. Sharing a backlog like a queue belongs in an issue tracker, not in markdown files in the repo.

If you want to share state with a team, you can opt in by removing `.hv/` from `.gitignore` — that's a deliberate choice, not the default.

## Can I share `.hv/` with my team?

Yes — remove `.hv/` from `.gitignore` and commit the folder. A few practical considerations: item ID counters become shared, so coordinating ID numbering starts to matter; `status.json` reflects whoever last reconciled; and `KNOWLEDGE.md` gains team-level content rather than personal notes.

This works well for small, focused teams. For larger ones, a real issue tracker is usually a better fit — the file-based format doesn't have the conflict-resolution or permissions model that scales.

## What if I'm not using Claude Code?

hv-skills is built around Claude Code's skill system, `AskUserQuestion`, and subagent dispatch. The `.hv/` folder, CLI helpers, and `TODO.md` format are agent-agnostic and useful on their own — you can call the helpers from any shell. But the slash commands themselves only run inside Claude Code.

Other agent harnesses with comparable primitives — Gemini CLI, some Copilot builds — may load the skills with reduced functionality. Where `AskUserQuestion` isn't available, those interactions degrade to plain text prompts rather than native UI. Don't expect full functionality outside Claude Code.

## How do I update hv-skills when a new release ships?

Run `/hv-update`. It detects your install type (plugin, repo clone, or stow), reads the current version, fetches the latest GitHub release, and prints the exact update command for your setup. It doesn't run the update itself — there are too many install paths to get right automatically.

After updating, rerun `/hv-init` in each project to refresh `.hv/bin/` with any new helpers.

Requires `gh` on the PATH. See the [/hv-update reference](reference/slash-commands.md#hv-update) for details.

## Does this work with monorepos?

Yes — `.hv/` lives at the root of whatever directory you run `/hv-init` from. For monorepos you have two reasonable options:

- **One `.hv/` at the monorepo root** for project-wide work and cross-package tracking.
- **One `.hv/` per package or app subdirectory** for scoped backlogs that stay close to the code they track.

The CLI helpers and managed `CLAUDE.md` blocks resolve relative to the current working directory, so per-package setups work as long as you run hv-skills from inside the package. Mixing both is fine — each `.hv/` is independent.
