# hv-skills documentation

Public user guide for hv-skills — a zero-dependency development workflow for Claude Code.

This is the consumer-facing docs surface. For contributor reference and internals, see [GUIDE.md](../GUIDE.md) at repo root.

## Contents

### Getting started

- [Getting started](getting-started.md) — install and run your first cycle in five minutes

### Usage

- [Capturing work](usage/capturing-work.md) — `/hv-capture`, `/hv-c`, mixed input, related links, detail files
- [Picking next](usage/picking-next.md) — `/hv-next`, `/hv-status`, `/hv-assume`
- [Implementing](usage/implementing.md) — `/hv-work` parallel cycles, branch vs worktree isolation, `/hv-go` speed-path
- [Debugging](usage/debugging.md) — `/hv-debug` systematic cycle
- [Shipping](usage/shipping.md) — `/hv-review` and `/hv-ship` gates
- [Learning](usage/learning.md) — `/hv-learn` and `KNOWLEDGE.md`
- [Vision and plans](usage/vision-and-plans.md) — `/hv-vision`, `/hv-plan`, `/hv-spike`, milestones
- [Handoff](usage/handoff.md) — `/hv-pause`, `/hv-resume`, recovering after `/clear`
- [Parallel work](usage/parallel-work.md) — worktree mode, concurrent `/hv-work` sessions

### Configuration

- [Configuration](configuration.md) — every key in `.hv/config.json` and what it does

### Reference

- [Slash commands](reference/slash-commands.md) — alphabetical reference of all `/hv-*` commands
- [The `.hv/` folder](reference/hv-folder.md) — files and directories created by `/hv-init`
- [CLI helpers](reference/cli-helpers.md) — user-callable scripts in `.hv/bin/`

### Other

- [FAQ](faq.md) — common questions
