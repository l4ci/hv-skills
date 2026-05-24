<div align="center">

<img src="docs/hv-skills_logo.png" alt="hv-skills logo" width="80" />

# hv-skills

**A project memory layer for Claude Code: KNOWLEDGE.md, DECISIONS.md, and a handoff note that survives `/clear`. With a loop around them that captures, works, reviews, and ships.**

[![Release](https://img.shields.io/github/v/release/l4ci/hv-skills?color=blue&sort=semver)](https://github.com/l4ci/hv-skills/releases)
[![License](https://img.shields.io/github/license/l4ci/hv-skills?color=green)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/l4ci/hv-skills)](https://github.com/l4ci/hv-skills/commits)
[![Stars](https://img.shields.io/github/stars/l4ci/hv-skills?style=social)](https://github.com/l4ci/hv-skills/stargazers)
[![For Claude Code](https://img.shields.io/badge/for-Claude%20Code-8A2BE2)](https://claude.com/claude-code)

[Install](#install) · [What you get](#what-you-get) · [Configuration](#configuration) · [FAQ](#faq) · [Docs](docs/)

</div>

---

## The wedge and the loop

💾 **Persist (the wedge).** This is why hv-skills exists. Three files outlive every `/clear`. `KNOWLEDGE.md` carries durable learnings, written by `/hv-learn`, verified before they land, and auto-consulted by future `/hv-work`, `/hv-debug`, and `/hv-review` runs. `DECISIONS.md` carries hard-boundary commitments captured by `/hv-decide` with explicit forbids and permits. A handoff note carries the live hypothesis: `/hv-pause` writes the current state mid-investigation (hypothesis, next step, files mid-edit) so the next `/hv-next` after `/clear` picks up exactly where you left off. `/hv-learn --term <name>` lands domain terms under a pinned `## Glossary` topic in `KNOWLEDGE.md`. Cycle skills bump the hand-authored project map (`.hv/map/<name>.md`) post-cycle, and `/hv-ship --docs` keeps public docs in sync with the code.

📥 **Capture.** `/hv-capture` is the brain-dump entry point. It splits, classifies, and routes items to `BACKLOG.md` with auto-incrementing IDs (`B01`, `F01`, `T01`). `/hv-go` collapses capture and execute into a single pass for hot-path fixes. `/hv-capture --from-github` / `--from-gitlab` syncs open upstream issues into the backlog with `GH: #N` / `GL: #N` cross-references, and round-trips closing via `/hv-ship`. `/hv-capture --remove <ID>` is the local inverse: it strips a captured item and cleans up its dependencies behind a dry-run preview and confirmation gate.

🧭 **Plan.** `/hv-vision` brainstorms milestones with Socratic discovery, web research, and a deliberate critique pass. `/hv-brainstorm` explores design for size-Major features or P0 bugs before planning. `/hv-plan` writes the implementation plan to its own file, keyed by milestone slice or item. `/hv-spike` runs throwaway feasibility experiments on a branch that never merges; only findings come back. `/hv-work --preview <ID>` shows the orchestrator's intended approach without writing anything, a cheap gate before code lands on high-stakes items.

⚡ **Execute.** `/hv-work` is the orchestrator. It reads the plan (or decomposes ad-hoc if none exists), dispatches worker subagents in parallel, and commits one verifiable task at a time. `/hv-debug` runs a systematic reproduce, hypothesize, verify, fix cycle for bugs. `/hv-refactor` does the same shape for architectural friction.

🚢 **Ship.** `/hv-review` reads the branch diff, resolved item IDs, and matching `KNOWLEDGE.md` topics across a two-stage pass (spec compliance, then code quality) and returns `PASS` / `CONCERNS` / `FAIL`. `/hv-qa` answers the orthogonal question, *"does the product actually work?"*, by executing per-target runners (Playwright, smoke, lighthouse, axe, ZAP, contract tests) from `.hv/qa/<target>.md`. `/hv-ship` builds an ID-linked PR body or direct-merges based on configured strategy; opt-in gates layer in a fresh-eyes second-opinion review and a product QA run before integration. `/hv-ship --undo` rolls back the last direct-merge cycle in one operation, restoring TODO entries.

> **Upgrading from v3?** Run `/hv-migrate v4` after install. See the [v4.0 announcement](docs/announcements/v4-0.md).

## Install

```bash
npx skills add l4ci/hv-skills
```

Then run `/hv-init` once at the project root. See [Getting started](docs/getting-started.md) for the five-minute walkthrough.

For other install methods (Claude Code plugin marketplace, GNU Stow, local clone) see [install alternatives](docs/install.md).

## What you get

A short list of the things that actually distinguish hv-skills from a TODO file and a willingness to think hard:

- **Knowledge that survives `/clear`.** `/hv-learn` writes durable gotchas to `KNOWLEDGE.md` with verification; `/hv-work`, `/hv-debug`, and `/hv-review` consult them automatically on future runs.
- **Handoff notes for the live hypothesis.** `/hv-pause` writes what's in your head (current hypothesis, next planned step, files mid-edit) so `/hv-next` after a `/clear` picks up where you left off, not just where git left off.
- **Parallel execution with atomic commits.** An orchestrator decomposes the plan, worker subagents implement in parallel, one verifiable commit per task. Branch or worktree isolation keeps main clean.
- **Two-stage review plus opt-in fresh-eyes.** `/hv-review` splits spec-compliance from code-quality. `ship.secondOpinion` adds a no-prior-context adversarial pass after the contextualized one signs off.
- **Plan-as-artifact and design exploration.** `/hv-plan` writes the plan to its own file; `/hv-brainstorm` negotiates shape and tradeoffs for Major features or P0 bugs before planning; `/hv-work --preview` prints the intended approach before code lands.
- **Umbrella mode.** One coordinator across N independent sub-repos. Shared `KNOWLEDGE.md` / `DECISIONS.md` / `BACKLOG.md` at the umbrella; commits land in each sub-repo's own `.git/`. No submodules.

A full feature list (autonomy chaining, product QA gate, throwaway spikes, backlog reconciliation, GitHub/GitLab issue round-trip, refactor cycles) is in the [docs](docs/).

## Configuration

Defaults in `.hv/config.json` are conservative: branch isolation, direct merge, review gate on, no autonomous chaining. Flip `autonomy.level` to `"auto"` to chain `/hv-work` → `/hv-learn` and `/hv-debug` → `/hv-ship`, or `"loop"` to drain the backlog. Use `/hv-config` to edit interactively; full key list in [docs/usage/configuration.md](docs/usage/configuration.md).

## FAQ

**Why hv-skills over GSD?**

GSD models projects as formal phases: discuss, plan, execute, verify (with optional audit profiles). Each phase gets its own agent and `.planning/` sign-off artifacts. That's the right shape for regulated work, hard requirements, or anywhere a defensible verification trail matters more than speed. hv-skills runs differently: a tight `capture → next → work → ship → learn` loop with markdown artifacts you can edit by hand, and no phase ceremony unless you ask for it. Plan-as-artifact exists (`/hv-plan` writes one file per slice or item), but it's optional rather than the spine of the workflow. If you need sign-off rigor, GSD fits better. If you want a faster loop with knowledge that carries across sessions, hv-skills is built for that.

**Why hv-skills over Octo?**

Octo orchestrates up to eight AI providers (Codex, Gemini, Copilot, Qwen, Ollama, Perplexity, and OpenRouter alongside Claude) for debates, consensus, 100-point PRD scoring across providers, and a Discover/Define/Develop/Deliver pipeline. If cross-model validation is where your value comes from, Octo is purpose-built for it. hv-skills is deliberately single-provider. Instead of cross-AI debate it leans hard into Claude Code: `AskUserQuestion`, subagent dispatch, branch and worktree isolation, atomic commits, and handoff notes that survive `/clear`. Use Octo when you want multiple models second-guessing each other. Use hv-skills when you've decided on Claude Code and want the workflow built around it.

**Why hv-skills over a TODO.md and good intentions?**

Most workflows start that way and most stay there. Three things tend to drift, and hv-skills addresses each. (1) Knowledge stops accumulating: you re-discover the same gotcha three sessions in a row because nothing reads it back. (2) Sessions don't survive `/clear`: you lose the live hypothesis the moment you step away. (3) Commits stop being atomic: one PR ends up touching six unrelated things. `/hv-learn` writes durable gotchas that future runs auto-consult, `/hv-pause` / `/hv-next` carry intent across context resets, and `/hv-work` enforces atomic per-task commits. If none of those bite you in practice, stock Claude Code is fine. If they do, that's the gap hv-skills fills.

## Testing

Smoke-test the CLI helpers against a throwaway `.hv/` in a tmpdir:

```bash
bash test/smoke.sh
```

Exercises all `hv-*` helpers across 234 assertions. Exits non-zero on any failure.

## Contributing

Issues and PRs welcome. Keep changes minimal, include a smoke-test assertion if you touch or add a helper, and follow the commit style in `git log`.

## License

[MIT](LICENSE)
