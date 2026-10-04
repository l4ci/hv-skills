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

hv is built around Claude Code's skill system, `AskUserQuestion`, and subagent dispatch. The `.hv/` folder, the `hv` binary, and the `BACKLOG.md` format are agent-agnostic and work on their own; you can call `hv` from any shell. The slash commands themselves only run inside Claude Code.

Other agent harnesses with comparable primitives (Gemini CLI, some Copilot builds) may load the skills with reduced functionality. Where `AskUserQuestion` isn't available, those interactions fall back to plain text prompts instead of native UI. Don't expect full functionality outside Claude Code.

## How do I update hv when a new release ships?

Run `hv update`. It detects your install type (plugin, repo clone, or stow), reads the current version, fetches the latest GitHub release, and prints the exact update command for your setup. It doesn't run the update itself, since there are too many install paths to handle automatically.

After updating, there is nothing to refresh in your projects: `hv` ships with the plugin. Run `hv version --drift` in a project to see whether its stamped version trails the installed one.

Requires `gh` on the PATH. See [slash commands](reference/slash-commands.md) for the verb list.

## Does this work with monorepos?

Yes. `.hv/` lives at the root of whatever directory you run `hv init` from. For monorepos you have two reasonable options:

- **One `.hv/` at the monorepo root** for project-wide work and cross-package tracking.
- **One `.hv/` per package or app subdirectory** for scoped backlogs that stay close to the code they track.

`hv` and the managed `CLAUDE.md` blocks resolve relative to the current working directory, so per-package setups work as long as you run hv from inside the package. You can mix both styles in one repo; each `.hv/` is independent.
