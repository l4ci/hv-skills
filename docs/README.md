# hv-skills documentation

Public user guide for hv-skills, a zero-dependency dev workflow for Claude Code.

## Contents

### Getting started

- [Getting started](getting-started.md) — install and run your first cycle
- [How it works](how-it-works.md) — system diagram, plus how each skill connects to the artifacts it touches

### Walkthroughs

- [Greenfield — from a brief to a shipped milestone](walkthroughs/greenfield-from-brief.md): empty repo plus a one-page brief, taken end-to-end through `/hv-vision`, `/hv-plan`, `/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-learn`
- [Brownfield — dropping hv-skills into an existing project](walkthroughs/brownfield-existing-project.md): established codebase with open issues and a mental bug list, walked through `/hv-map`, `/hv-issues`, `/hv-capture`, then a P0 cycle plus a debug cycle

### Capture and backlog

- [Capturing work](usage/capturing-work.md) — `/hv-capture`, `/hv-c`, mixed input, related links, detail files
- [Picking work](usage/picking-work.md) — `/hv-next`, `/hv-assume`
- [Removing work](usage/removing-work.md): `/hv-rm`, dry-run preview, batch removal, safety semantics

### Execution

- [Running work](usage/running-work.md) — `/hv-work` parallel cycles, branch vs worktree isolation, `/hv-go` speed-path
- [Debugging](usage/debugging.md) — `/hv-debug` systematic cycle
- [Pausing and resuming](usage/pausing-and-resuming.md) — `/hv-pause`, recovering after `/clear`
- [Parallel work](usage/parallel-work.md) — worktree mode, concurrent `/hv-work` sessions

### Shipping

- [Review and ship](usage/review-and-ship.md) — `/hv-review` and `/hv-ship` gates
- [Rolling back a cycle](usage/undo.md): `/hv-undo` guided rollback, dry-run preview, manual confirmation
- [Learning](usage/learning.md) — `/hv-learn` and `KNOWLEDGE.md`
- [Decisions](usage/decisions.md) — `/hv-decide` and hard-boundary commitments in `DECISIONS.md`
- [Capturing terminology](usage/context.md) — `/hv-context` and the project glossary in `CONTEXT.md`

### Vision and planning

- [Vision and plans](usage/vision-and-plans.md) — `/hv-vision`, `/hv-plan`, milestones
- [Brainstorming a design](usage/brainstorm.md): per-item design exploration with `/hv-brainstorm`, before `/hv-plan`
- [Spikes](usage/spikes.md) — throwaway feasibility experiments via `/hv-spike`

### Configuration

- [Configuration](usage/configuration.md) — every key in `.hv/config.json` and what it does
- [Autonomy levels](usage/autonomy.md) — how `off` / `auto` / `loop` change skill chaining
- [Umbrella mode](usage/umbrella-mode.md) — coordinator at umbrella, work in sub-repos (M02 V1)

### Reference

- [Slash commands](reference/slash-commands.md) — every `/hv-*` command, alphabetical
- [The `.hv/` folder](reference/hv-folder.md) — files and directories created by `/hv-init`
- [CLI helpers](reference/cli-helpers.md) — user-callable scripts in `.hv/bin/`
- [Configuration options](reference/config-options.md) — the questions `/hv-init` and `/hv-config` ask, with their option labels
- [`/hv-issues` reference](reference/hv-issues.md) — pull GitHub/GitLab issues into `BACKLOG.md`, with round-trip closing
- [`CONTEXT.md` reference](reference/context-md.md) — file format and lifecycle of the project glossary
- [Preflight](reference/preflight.md) — what `.hv/bin/hv-preflight` checks before each skill, plus exit-code meanings

### Other

- [FAQ](faq.md) — common questions
