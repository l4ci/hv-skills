# hv documentation

Public user guide for hv, a zero-dependency dev workflow for Claude Code and Codex: skills plus a CLI.

## Contents

### Getting started

- [Cheat sheet](cheatsheet.md): one-line summary of every `/hv-*` skill (rapid scan)
- [Install](install.md): the install script, Homebrew, release binaries, upgrading, uninstalling
- [Getting started](getting-started.md): install and run your first cycle
- [How it works](how-it-works.md): system diagram, plus how each skill connects to the artifacts it touches

### Walkthroughs

- [Greenfield: from a brief to a shipped milestone](walkthroughs/greenfield-from-brief.md). Empty repo plus a one-page brief, taken end-to-end through `/hv-vision`, `/hv-plan`, `/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-learn`.
- [Brownfield: dropping hv into an existing project](walkthroughs/brownfield-existing-project.md). Established codebase with open issues and a mental bug list, walked through `hv init`, `/hv-capture --from-github`, `/hv-capture`, then a P0 cycle plus a debug cycle.

### Rounds

- [Parallel rounds](usage/parallel-rounds.md): an orchestrator, standing workers in worktrees, the merge gate, solo mode
- [Unattended rounds](usage/unattended-rounds.md): hooks, statusline, keepalive, usage limits, the orchestrator switch
- [Doctor and reap](usage/doctor-and-reap.md): check the machine before a round, clear leftovers after
- [Codex workers](usage/codex-workers.md): run Codex as a worker in a round
- [Skills in Codex](usage/codex-skills.md): install and call the skills from Codex

### Capture and backlog

- [Capturing work](usage/capturing-work.md): `/hv-capture`, mixed input, related links, detail files
- [Picking work](usage/picking-work.md): `/hv-work` (no argument), `/hv-work --preview`
- [Removing work](usage/removing-work.md): `/hv-capture --remove`, dry-run preview, batch removal, safety semantics

### Execution

- [Running work](usage/running-work.md): `/hv-work` parallel cycles, branch vs worktree isolation, the `/hv-capture` hand-off
- [Debugging](usage/debugging.md): `/hv-debug` systematic cycle
- [Pausing and resuming](usage/pausing-and-resuming.md): `/hv-pause`, recovering after `/clear`
- [Parallel work](usage/parallel-work.md): worktree mode, concurrent `/hv-work` sessions

### Shipping

- [Review and ship](usage/review-and-ship.md): `/hv-review` two-stage pass and `/hv-ship` gates (second-opinion, QA)
- [Product QA](usage/qa.md): `/hv-qa` per-target strategy files and the `ship.qa` gate
- [Rolling back a cycle](usage/undo.md): `/hv-ship --undo` guided rollback, dry-run preview, manual confirmation
- [Learning](usage/learning.md): `/hv-learn` and `KNOWLEDGE.md`, including `--term <name>` for the project Glossary
- [Decisions](usage/decisions.md): `/hv-decide` and hard-boundary commitments in `DECISIONS.md`

### Vision and planning

- [Vision and plans](usage/vision-and-plans.md): `/hv-vision`, `/hv-plan`, milestones
- [Brainstorming a design](usage/brainstorm.md): per-item design exploration with `/hv-brainstorm`, before `/hv-plan`
- [Spikes](usage/spikes.md): throwaway feasibility experiments via `/hv-spike`

### Configuration

- [Configuration](usage/configuration.md): every key in `.hv/config.json` and what it does
- [Autonomy levels](usage/autonomy.md): how `off` / `auto` / `loop` change skill chaining
- [Issue backend](usage/issue-backend.md): backlog on GitHub/GitLab issues, setup, labels, milestones, `hv migrate issues`
- [Umbrella mode](usage/umbrella-mode.md): coordinator at umbrella, work in sub-repos (M02 V1)

### Reference

- [Slash commands](reference/slash-commands.md): every `/hv-*` command, alphabetical
- [The `.hv/` folder](reference/hv-folder.md): files and directories created by `hv init`
- [`hv` verb reference](reference/cli-helpers.md): every `hv` verb, with conventions and exit codes
- [Configuration options](reference/config-options.md): every config key and option label, set via `hv config set`
- [`/hv-capture --from-github` / `--from-gitlab` reference](reference/hv-issues.md): pull GitHub/GitLab issues into `BACKLOG.md`, with round-trip closing
- [Project check](reference/preflight.md): what `hv init check` verifies, plus exit-code meanings

### Contributing

- [Rounds on hv itself](contributing/rounds.md): the gate, repo rules and roster for contributors

### Other

- [FAQ](faq.md): common questions
