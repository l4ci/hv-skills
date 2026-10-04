<div align="center">

<img src="docs/hv_logo.png" alt="hv logo" width="80" />

# hv

**Autonomous rounds for coding agents: an orchestrator hands issues to parallel workers, merges what passes the gate, and keeps going. Persistent knowledge, decisions and handoffs make that reliable.**

[![Release](https://img.shields.io/github/v/release/l4ci/hv?color=blue&sort=semver)](https://github.com/l4ci/hv/releases)
[![License](https://img.shields.io/github/license/l4ci/hv?color=green)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/l4ci/hv)](https://github.com/l4ci/hv/commits)
[![Stars](https://img.shields.io/github/stars/l4ci/hv?style=social)](https://github.com/l4ci/hv/stargazers)
[![For Claude Code](https://img.shields.io/badge/for-Claude%20Code-8A2BE2)](https://claude.com/claude-code)

[Autonomous rounds](#autonomous-rounds) · [Install](#install) · [Skills](#skills) · [Docs](docs/)

</div>

---

## Autonomous rounds

The main reason to adopt hv. One always-on orchestrator drives the `hv` CLI. It starts a round, assigns each issue to a worker agent (Claude Code or Codex) in its own git worktree and herdr or tmux tab, waits on the workers without polling, runs the gate and merges. When it needs you, it notifies you and comments on the issue or PR, then works on other items until you answer. Without herdr or tmux it runs the workers as subagents. See [parallel rounds](docs/usage/parallel-rounds.md).

Rounds hold up over hours because state persists. `KNOWLEDGE.md` and `DECISIONS.md` carry what earlier work learned and committed to. Handoff notes carry a half-finished task across a `/clear` or a restart. Issues say what work exists; `.hv/` says who is doing it now.

## Install

From v5.0.0, `hv` is one binary and the skills ship inside it:

```bash
curl -fsSL https://raw.githubusercontent.com/l4ci/hv/main/install.sh | sh   # or: brew install l4ci/tap/hv
hv skills install     # skills for Claude Code and Codex
hv init               # once, at the project root
```

The script checks the download against `checksums.txt` and refuses a mismatch. That catches a corrupted download, not a compromised release; signing is tracked in [#220](https://github.com/l4ci/hv/issues/220). [Install](docs/install.md) has the options, upgrading and removal; [getting started](docs/getting-started.md) has the first cycle.

## Skills

| | |
|---|---|
| Plan | `/hv-vision`, `/hv-brainstorm`, `/hv-plan`, `/hv-spike` |
| Build | `/hv-work`, `/hv-debug`, `/hv-refactor` |
| Check | `/hv-review`, `/hv-qa` |
| Rounds | `/hv-orchestrate` |
| Persist | `/hv-learn`, `/hv-decide`, `/hv-pause` |
| Intake and release | `/hv-capture`, `/hv-ship`, `/hv-release` |

Skills hold judgment; `hv` verbs enforce the rules. Settings live in `.hv/config.json` ([options](docs/usage/configuration.md)).

## Contributing

Issues and PRs welcome. Run `python3 test/validate-skills.py` and `bash test/smoke.sh` before a PR; add a smoke assertion when you touch a verb. Running a round on hv itself: [contributing: rounds](docs/contributing/rounds.md).

## License

[MIT](LICENSE)
