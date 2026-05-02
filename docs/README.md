# hv-skills documentation

Public user guide for hv-skills — a zero-dependency development workflow for Claude Code.

## Contents

### Getting started

- [Getting started](getting-started.md) — install and run your first cycle in five minutes

### Capture and backlog

- [Capturing work](usage/capturing-work.md) — `/hv-capture`, `/hv-c`, mixed input, related links, detail files
- [Reviewing and picking work](usage/next-and-status.md) — `/hv-next`, `/hv-status`, `/hv-assume`

### Execution

- [Running work](usage/running-work.md) — `/hv-work` parallel cycles, branch vs worktree isolation, `/hv-go` speed-path
- [Debugging](usage/debugging.md) — `/hv-debug` systematic cycle
- [Pausing and resuming](usage/pausing-and-resuming.md) — `/hv-pause`, `/hv-resume`, recovering after `/clear`
- [Parallel work](usage/parallel-work.md) — worktree mode, concurrent `/hv-work` sessions

### Shipping

- [Review and ship](usage/review-and-ship.md) — `/hv-review` and `/hv-ship` gates
- [Learning](usage/learning.md) — `/hv-learn` and `KNOWLEDGE.md`

### Vision and planning

- [Vision and plans](usage/vision-and-plans.md) — `/hv-vision`, `/hv-plan`, milestones
- [Spikes](usage/spikes.md) — throwaway feasibility experiments via `/hv-spike`

### Configuration

- [Configuration](usage/configuration.md) — every key in `.hv/config.json` and what it does
- [Autonomy levels](usage/autonomy.md) — how `off` / `auto` / `loop` change skill chaining
- [Umbrella mode](usage/umbrella-mode.md) — coordinator at umbrella, work in sub-repos (M02 V1)

### Reference

- [Slash commands](reference/slash-commands.md) — alphabetical reference of all `/hv-*` commands
- [The `.hv/` folder](reference/hv-folder.md) — files and directories created by `/hv-init`
- [CLI helpers](reference/cli-helpers.md) — user-callable scripts in `.hv/bin/`

### Other

- [FAQ](faq.md) — common questions
