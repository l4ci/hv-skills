<div align="center">

<img src="docs/hv-skills_logo.png" alt="hv-skills logo" width="80" />

# hv-skills

**Autonomous rounds for coding agents: an orchestrator hands issues to parallel workers, merges what passes the gate, and keeps going. Persistent knowledge, decisions and handoffs make that reliable.**

[![Release](https://img.shields.io/github/v/release/l4ci/hv-skills?color=blue&sort=semver)](https://github.com/l4ci/hv-skills/releases)
[![License](https://img.shields.io/github/license/l4ci/hv-skills?color=green)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/l4ci/hv-skills)](https://github.com/l4ci/hv-skills/commits)
[![Stars](https://img.shields.io/github/stars/l4ci/hv-skills?style=social)](https://github.com/l4ci/hv-skills/stargazers)
[![For Claude Code](https://img.shields.io/badge/for-Claude%20Code-8A2BE2)](https://claude.com/claude-code)

[Autonomous rounds](#autonomous-rounds) · [Install](#install) · [Skills](#skills) · [Docs](docs/)

</div>

---

## Autonomous rounds

The main reason to adopt hv-skills. One always-on orchestrator drives the `hv` CLI. It starts a round, assigns each issue to a worker agent (Claude Code or Codex) in its own git worktree and herdr or tmux tab, waits on the workers without polling, runs the gate and merges. When it needs you, it notifies you and comments on the issue or PR, then works on other items until you answer. Without herdr or tmux it runs the workers as subagents. See [parallel rounds](docs/usage/parallel-rounds.md).

Rounds hold up over hours because state persists. `KNOWLEDGE.md` and `DECISIONS.md` carry what earlier work learned and committed to. Handoff notes carry a half-finished task across a `/clear` or a restart. Issues say what work exists; `.hv/` says who is doing it now.

## Install

Claude Code plugin (puts `hv` on PATH while enabled):

```bash
claude plugin marketplace add l4ci/hv-skills
claude plugin install hv-skills
```

Standalone `hv`, for Codex and other harnesses:

```bash
brew install l4ci/tap/hv                                  # Homebrew
go install github.com/l4ci/hv-skills/v5/cmd/hv@latest     # Go 1.22+
```

or download `hv_<os>_<arch>` from the [releases](https://github.com/l4ci/hv-skills/releases) page (linux and macOS, amd64 and arm64) and put it on your PATH. Check with `hv version`.

Then run `hv init` once at the project root. [Getting started](docs/getting-started.md) has the first cycle; [install alternatives](docs/install.md) covers `npx skills` and GNU Stow.

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

Issues and PRs welcome. Run `python3 test/validate-skills.py` and `bash test/smoke.sh` before a PR; add a smoke assertion when you touch a verb.

## License

[MIT](LICENSE)
