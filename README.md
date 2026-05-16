<div align="center">

<img src="docs/hv-skills_logo.png" alt="hv-skills logo" width="160" />

# hv-skills

**A workflow for Claude Code that plans before coding, makes one commit per task, and keeps a project knowledge layer that survives `/clear`.**

[![Release](https://img.shields.io/github/v/release/l4ci/hv-skills?color=blue&sort=semver)](https://github.com/l4ci/hv-skills/releases)
[![License](https://img.shields.io/github/license/l4ci/hv-skills?color=green)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/l4ci/hv-skills)](https://github.com/l4ci/hv-skills/commits)
[![Stars](https://img.shields.io/github/stars/l4ci/hv-skills?style=social)](https://github.com/l4ci/hv-skills/stargazers)
[![For Claude Code](https://img.shields.io/badge/for-Claude%20Code-8A2BE2)](https://claude.com/claude-code)

[Install](#install) · [Features](#features) · [Configuration](#configuration) · [FAQ](#faq) · [Docs](docs/)

</div>

---

## The five lanes

📥 **Capture.** `/hv-capture` is the brain-dump entry point. It splits, classifies, and routes items to `BACKLOG.md` with auto-incrementing IDs (`B01`, `F01`, `T01`). `/hv-go` collapses capture and execute into a single pass for hot-path fixes. `/hv-capture --from-github` / `--from-gitlab` syncs open upstream issues into the backlog with `GH: #N` / `GL: #N` cross-references, and round-trips closing via `/hv-ship`. `/hv-capture --remove <ID>` is the local inverse — it strips a captured item and cleans up its dependencies behind a dry-run preview and confirmation gate.

🧭 **Plan.** `/hv-vision` brainstorms milestones with Socratic discovery, web research, and a deliberate critique pass. `/hv-brainstorm` explores design for size-Major features or P0 bugs before planning. `/hv-plan` writes the implementation plan to its own file, keyed by milestone slice or item. `/hv-spike` runs throwaway feasibility experiments on a branch that never merges; only findings come back. `/hv-work --preview <ID>` previews the orchestrator's intended approach without writing anything, a cheap gate before code lands on high-stakes items.

⚡ **Execute.** `/hv-work` is the orchestrator. It reads the plan (or decomposes ad-hoc if none exists), dispatches worker subagents in parallel, commits one verifiable task at a time. `/hv-debug` runs a systematic reproduce → hypothesize → verify → fix cycle for bugs. `/hv-refactor` does the same shape for architectural friction. `/hv-pause` writes a handoff note when the context window is filling, so a fresh `/hv-next` session picks up cleanly.

🚢 **Ship.** `/hv-review` reads the branch diff, resolved item IDs, and matching `KNOWLEDGE.md` topics across a two-stage pass (spec compliance → code quality) and returns `PASS` / `CONCERNS` / `FAIL`. `/hv-qa` answers the orthogonal question — *"does the product actually work?"* — by executing per-target runners (Playwright, smoke, lighthouse, axe, ZAP, contract tests) from `.hv/qa/<target>.md`. `/hv-ship` builds an ID-linked PR body or direct-merges based on configured strategy; opt-in gates layer in a fresh-eyes second-opinion review and a product QA run before integration. `/hv-ship --undo` rolls back the last direct-merge cycle in one operation, restoring TODO entries.

💾 **Persist.** `/hv-learn` writes durable session learnings to `KNOWLEDGE.md`, verified before they land. `/hv-decide` captures hard-boundary commitments to `DECISIONS.md` with explicit forbids and permits. `/hv-context` captures domain terms to `CONTEXT.md` (the project's canonical glossary). The project map (`.hv/map/<name>.md` files describing subsystems) is hand-authored; cycle skills (`/hv-work`, `/hv-debug`, `/hv-go`) bump `touched:` post-cycle on matched subsystems. `/hv-ship --docs` keeps the public docs in sync with the code (inline at ship time or via the manual `--docs` flag).

## Install

```bash
npx skills add l4ci/hv-skills
```

Then run `/hv-init` once at the project root. See [Getting started](docs/getting-started.md) for the five-minute walkthrough.

For other install methods (Claude Code plugin marketplace, GNU Stow, local clone) see [install alternatives](docs/install.md).

## Features

|  |  |
|---|---|
| 📥 **Auto-classified capture** — bugs, features, tasks routed with priority/size tags and zero-padded IDs (`[B01]`, `[F01]`, `[T01]`) | ⚡ **Parallel execution** — orchestrator plans, workers implement in parallel, one atomic commit per task |
| 🌿 **Branch or worktree isolation** — main stays clean while agents work, run multiple sessions side by side | 🧠 **Knowledge retention** — `/hv-learn` writes durable learnings; `/hv-work`, `/hv-debug`, and `/hv-review` all consult them |
| ♻️ **Backlog reconciliation** — `/hv-next` validates `status.json` against git state, auto-cleans stale entries | 🐛 **Systematic debugging** — `/hv-debug` reproduces, hypothesizes, verifies, fixes, nudges `/hv-learn` |
| 🚢 **Two-stage review** — `/hv-review` splits spec-compliance (plan vs diff) from code-quality (conventions, security, silent failures); Stage 1 `FAIL` short-circuits Stage 2 | 🧪 **Product QA gate** — `/hv-qa` runs per-target strategy files (`.hv/qa/<target>.md`) with Playwright / smoke / lighthouse / axe / ZAP / contract runners; `ship.qa: true` invokes it from `/hv-ship`, `qa.gate` chooses advisory vs blocking |
| 🕵️ **Fresh-eyes second opinion** — `ship.secondOpinion: true` dispatches a no-prior-context adversarial reviewer after `/hv-review` passes; catches blind spots the contextualized reviewer normalized | 💾 **Context-clear recovery** — `/hv-next` re-reads active streams with recent commits and any handoff note, routing you back to work |
| 🔧 **Refactor cycles** — `/hv-refactor` explores friction, designs competing approaches, fixes in parallel | 🤝 **Graceful handoff** — `/hv-pause` writes what's in your head (hypothesis, next step, mid-edit files) so `/hv-next` picks up after a `/clear` |
| 🧭 **Vision & milestones** — `/hv-vision` brainstorms milestones using web research and a critique pass; `/hv-next` and `/hv-pause` keep work scoped to the active set | 🔗 **Loose milestone tags** — items can carry a `Milestone:` field; multi-active milestones run in parallel when their dependencies allow |
| 💡 **Per-item design exploration** — `/hv-brainstorm` negotiates shape and tradeoffs for a single `[Major]` feature or `[P0]` bug before planning; writes `.hv/designs/<ID>.md` that `/hv-plan` reads as soft input | 📋 **Plan-as-artifact** — `/hv-plan` writes implementation plans to `.hv/plans/<key>.md`; `/hv-work` consults the plan if present instead of decomposing ad-hoc |
| 🧪 **Throwaway spikes** — `/hv-spike` runs feasibility experiments on a dedicated `spike/<name>` branch; the branch never merges, only findings come back to main | 🔍 **Approach peek** — `/hv-work --preview <ID>` prints the orchestrator's intended files, tests, and assumptions before code lands, so corrections happen before `/hv-work` runs |
| 🧰 **Local-first, gitignored** — `.hv/` lives with your code; commit it intentionally to share state, or keep it private (the default) | 🔔 **Design nudges** — `/hv-capture` and `/hv-next` flag `[Major]` features and `[P0]` bugs with no design artifact and suggest `/hv-brainstorm` before planning |
| 🤖 **Autonomy levels** — `autonomy.level: "off"` (default nudges), `"auto"` (chain `/hv-work` → `/hv-learn`, `/hv-debug` → `/hv-ship`), or `"loop"` (drain the backlog; Major items auto-research via `/hv-brainstorm --auto-loop` → auto-plan → work). Quality gates still apply | ⚙️ **Interactive config** — `/hv-config` shows current values, lets you check off which keys to change, and reuses `/hv-init`'s option vocabulary so you never hand-edit JSON |
| 🌐 **Umbrella mode** — one coordinator across N independent sub-repos: shared `KNOWLEDGE.md` / `DECISIONS.md` / `MILESTONES.md` / `BACKLOG.md` at the umbrella with per-sub-repo `CONTEXT.md` under `.hv/contexts/<repo>/`; commits, branches, PRs land in each sub-repo's own `.git/`. No submodules. Tag items with `Repos:` to route work | 🔀 **Per-repo fan-out** — `/hv-refactor` and `/hv-work` route to the resolved sub-repo; `/hv-pause` keys handoffs by `(branch, repo)` so two sub-repos sharing a branch name don't clobber each other |
| 📊 **Visible progress** — multi-step skills (`/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-release`, `/hv-refactor`, …) declare a phase checklist via `TaskCreate` at start and tick each phase off as it lands, so long cycles stay legible instead of scrolling past as a stream of bash output | 🛠️ **Codified authoring conventions** — `hv-init`'s `## Authoring conventions` lists the rules new hv-* skills must follow (autonomy-aware dispatch, opt-in flag defaults, `AskUserQuestion` limits, progress checklists), so contributions stay consistent without rediscovery |

## Configuration

Edit `.hv/config.json`:

```json
{
  "models":   { "orchestrator": "opus",   "worker": "sonnet" },
  "work":     { "isolation": "branch",    "mergeStrategy": "direct" },
  "debug":    { "competingHypotheses": false },
  "refactor": { "confirmBeforeExecute": true, "verifyCommands": [] },
  "learn":    { "verify": true },
  "ship":     { "review": true },
  "docs":     { "path": "docs",           "autoCreate": false },
  "umbrella": { "enabled": false },
  "autonomy": { "level": "off" }
}
```

Defaults are conservative: branch isolation, direct merge, review gate on, knowledge verifier on, docs auto-write off (pending an LLM safety review), no autonomous chaining. Set `autonomy.level` to `"auto"` to chain `/hv-work` → `/hv-learn` and `/hv-debug` → `/hv-ship` automatically, or `"loop"` to keep going until the backlog drains. `umbrella.enabled` is set automatically by `/hv-init` when it detects two or more git children at the parent; see [docs/usage/umbrella-mode.md](docs/usage/umbrella-mode.md). For every key and when to flip it, see [docs/usage/configuration.md](docs/usage/configuration.md).

## FAQ

**Why hv-skills over GSD?**

GSD models projects as formal phases: discuss, plan, execute, verify, audit. Each phase gets its own agent and `.planning/` sign-off artifacts. That's the right shape for regulated work, hard requirements, or anywhere a defensible verification trail matters more than speed. hv-skills runs differently: a tight `capture → next → work → ship → learn` loop with markdown artifacts you can edit by hand, and no phase ceremony unless you ask for it. Plan-as-artifact exists (`/hv-plan` writes one file per slice or item), but it's optional rather than the spine of the workflow. If you need sign-off rigor, GSD fits better. If you want a faster loop with knowledge that carries across sessions, hv-skills is built for that.

**Why hv-skills over Octo?**

Octo orchestrates multiple AI providers (Claude, Gemini, Codex) for debates, consensus, 100-point PRD scoring across providers, and a Discover/Define/Develop/Deliver pipeline. If cross-model validation is where your value comes from, Octo is purpose-built for it. hv-skills is deliberately single-provider. Instead of cross-AI debate it leans hard into Claude Code: `AskUserQuestion`, subagent dispatch, branch and worktree isolation, atomic commits, and handoff notes that survive `/clear`. Use Octo when you want multiple models second-guessing each other. Use hv-skills when you've decided on Claude Code and want the workflow built around it.

**Why hv-skills over a TODO.md and good intentions?**

Most workflows start that way and most stay there. Three things tend to drift, and hv-skills addresses each. (1) Commits stop being atomic: one PR ends up touching six unrelated things. (2) Knowledge stops accumulating: you re-discover the same gotcha three sessions in a row because nothing reads it back. (3) Sessions don't survive `/clear`: you lose the live hypothesis the moment you step away. `/hv-work` enforces atomic per-task commits, `/hv-learn` writes durable gotchas that future runs auto-consult, and `/hv-pause` / `/hv-next` carry intent across context resets. If none of those bite you in practice, stock Claude Code is fine. If they do, that's the gap hv-skills fills.

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
