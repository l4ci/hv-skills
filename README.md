<div align="center">

# hv-skills

**A workflow for Claude Code that plans before coding, makes one commit per task, and keeps a project knowledge layer that survives `/clear`.**

[![Release](https://img.shields.io/github/v/release/l4ci/hv-skills?color=blue&sort=semver)](https://github.com/l4ci/hv-skills/releases)
[![License](https://img.shields.io/github/license/l4ci/hv-skills?color=green)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/l4ci/hv-skills)](https://github.com/l4ci/hv-skills/commits)
[![Stars](https://img.shields.io/github/stars/l4ci/hv-skills?style=social)](https://github.com/l4ci/hv-skills/stargazers)
[![For Claude Code](https://img.shields.io/badge/for-Claude%20Code-8A2BE2)](https://claude.com/claude-code)

[Install](#install) · [Walkthroughs](#walkthroughs) · [FAQ](#faq) · [Skills](#skills) · [How it works](docs/how-it-works.md) · [Docs](docs/)

</div>

---

## Why hv-skills?

- **Planning has its own commands.** `/hv-vision` for milestones, `/hv-brainstorm` for per-item design exploration before planning, `/hv-plan` for slice-level plans you can sign off on, `/hv-spike` for feasibility experiments on a throwaway branch, `/hv-assume` to peek at the orchestrator's approach before any code is written.
- **Atomic per-task commits.** Each commit lands one task with one verify step, so reverts stay surgical. Workers run in parallel under a single orchestrator.
- **Knowledge stays around.** `/hv-learn` writes gotchas and conventions into `KNOWLEDGE.md`, grouped by topic. Future runs of `/hv-work`, `/hv-debug`, and `/hv-review` read it back automatically, so you stop re-discovering the same problem three sessions in a row.
- **Local-first.** Everything lives in `.hv/` under your project. No daemon, no MCP server, no cloud, no database. Just bash, Python, git, and optionally `gh`.
- **Survives `/clear`.** `/hv-pause` writes a handoff note with your current hypothesis, next step, and mid-edit files. `/hv-next` reads it back in a fresh session.
- **Project map stays flat.** `/hv-map` maintains `.hv/map/<subsystem>.md` waypoints (entry points, purpose, last-touched date), auto-bumped by `/hv-work` cycles and summarized into a thin `## Project Map` index in `CLAUDE.md` so always-on context stays small as the codebase grows.
- **Vocabulary stays consistent.** `/hv-context` writes domain terms to `.hv/CONTEXT.md`. The `## Project Context` always-on block in `CLAUDE.md` carries term + aliases + first-sentence gloss so synonym/drift conflicts get flagged inline during work; sibling skills consult on demand via `hv-context-query`.

## Features

|  |  |
|---|---|
| 📥 **Auto-classified capture** — bugs, features, tasks routed with priority/size tags and zero-padded IDs (`[B01]`, `[F01]`, `[T01]`) | ⚡ **Parallel execution** — orchestrator plans, workers implement in parallel, one atomic commit per task |
| 🌿 **Branch or worktree isolation** — main stays clean while agents work, run multiple sessions side by side | 🧠 **Knowledge retention** — `/hv-learn` writes durable learnings; `/hv-work`, `/hv-debug`, and `/hv-review` all consult them |
| ♻️ **Backlog reconciliation** — `/hv-next` validates `status.json` against git state, auto-cleans stale entries | 🐛 **Systematic debugging** — `/hv-debug` reproduces, hypothesizes, verifies, fixes, nudges `/hv-learn` |
| 🚢 **Review-gated shipping** — `/hv-ship` runs `/hv-review` against original intent + conventions before PR or merge | 💾 **Context-clear recovery** — `/hv-next` re-reads active streams with recent commits and any handoff note, routing you back to work |
| 🔧 **Refactor cycles** — `/hv-refactor` explores friction, designs competing approaches, fixes in parallel | 🤝 **Graceful handoff** — `/hv-pause` writes what's in your head (hypothesis, next step, mid-edit files) so `/hv-next` picks up after a `/clear` |
| 🧭 **Vision & milestones** — `/hv-vision` brainstorms milestones using web research and a critique pass; `/hv-next` and `/hv-pause` keep work scoped to the active set | 🔗 **Loose milestone tags** — items can carry a `Milestone:` field; multi-active milestones run in parallel when their dependencies allow |
| 💡 **Per-item design exploration** — `/hv-brainstorm` negotiates shape and tradeoffs for a single `[Major]` feature or `[P0]` bug before planning; writes `.hv/designs/<ID>.md` that `/hv-plan` reads as soft input | 📋 **Plan-as-artifact** — `/hv-plan` writes implementation plans to `.hv/plans/<key>.md`; `/hv-work` consults the plan if present instead of decomposing ad-hoc |
| 🧪 **Throwaway spikes** — `/hv-spike` runs feasibility experiments on a dedicated `spike/<name>` branch; the branch never merges, only findings come back to main | 🔍 **Approach peek** — `/hv-assume` prints the orchestrator's intended files, tests, and assumptions before `/hv-work` runs, so corrections happen before code lands |
| 🧰 **Local-first, gitignored** — `.hv/` lives with your code; commit it intentionally to share state, or keep it private (the default) | 🔔 **Design nudges** — `/hv-capture` and `/hv-next` flag `[Major]` features and `[P0]` bugs with no design artifact and suggest `/hv-brainstorm` before planning |
| 🤖 **Autonomy levels** — `autonomy.level: "off"` (default nudges), `"auto"` (chain `/hv-work` → `/hv-learn`, `/hv-debug` → `/hv-ship`), or `"loop"` (drain the backlog; Major items auto-research via `/hv-brainstorm --auto-loop` → auto-plan → work). Quality gates still apply | ⚙️ **Interactive config** — `/hv-config` shows current values, lets you check off which keys to change, and reuses `/hv-init`'s option vocabulary so you never hand-edit JSON |
| 🌐 **Umbrella mode** — one coordinator across N independent sub-repos: shared `KNOWLEDGE.md` / `DECISIONS.md` / `MILESTONES.md` / `BACKLOG.md` at the umbrella with per-sub-repo `CONTEXT.md` under `.hv/contexts/<repo>/`; commits, branches, PRs land in each sub-repo's own `.git/`. No submodules. Tag items with `Repos:` to route work | 🔀 **Per-repo fan-out** — `/hv-refactor` and `/hv-work` route to the resolved sub-repo; `/hv-pause` keys handoffs by `(branch, repo)` so two sub-repos sharing a branch name don't clobber each other |
| 📊 **Visible progress** — multi-step skills (`/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-release`, `/hv-docs`, `/hv-refactor`, …) declare a phase checklist via `TaskCreate` at start and tick each phase off as it lands, so long cycles stay legible instead of scrolling past as a stream of bash output | 🛠️ **Codified authoring conventions** — `hv-init`'s `## Authoring conventions` lists the rules new hv-* skills must follow (autonomy-aware dispatch, opt-in flag defaults, `AskUserQuestion` limits, progress checklists), so contributions stay consistent without rediscovery |

## Install

```bash
claude plugin marketplace add l4ci/hv-skills
claude plugin install hv-skills
```

`/hv-init` is the next step. About thirty seconds, five questions (models, isolation, merge strategy, quality gates, autonomy level) with sensible defaults preselected. Creates `.hv/` with the data files (`BACKLOG.md`, `KNOWLEDGE.md`, `MILESTONES.md`, `DECISIONS.md`, `CONTEXT.md`), per-type subdirectories, the `hv-*` CLI helpers, and managed blocks in `CLAUDE.md`. To change settings later, run `/hv-config` rather than hand-editing JSON.

## Walkthroughs

Two worked examples in the docs carry one concrete project end-to-end:

- [Greenfield: from a brief to a shipped milestone](docs/walkthroughs/greenfield-from-brief.md) — empty repo plus a one-page brief, walked through `/hv-vision`, `/hv-plan`, `/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-learn`.
- [Brownfield: dropping hv-skills into an existing project](docs/walkthroughs/brownfield-existing-project.md) — established codebase with open GitHub issues and a mental bug list, walked through `/hv-map`, `/hv-issues`, `/hv-capture`, then a P0 cycle and a debug cycle.

For the five-minute condensed version see [Getting started](docs/getting-started.md).

## FAQ

**Why hv-skills over GSD?**

GSD models projects as formal phases: discuss, plan, execute, verify, audit. Each phase gets its own agent and `.planning/` sign-off artifacts. That's the right shape for regulated work, hard requirements, or anywhere a defensible verification trail matters more than speed. hv-skills runs differently: a tight `capture → next → work → ship → learn` loop with markdown artifacts you can edit by hand, and no phase ceremony unless you ask for it. Plan-as-artifact exists (`/hv-plan` writes one file per slice or item), but it's optional rather than the spine of the workflow. If you need sign-off rigor, GSD fits better. If you want a faster loop with knowledge that carries across sessions, hv-skills is built for that.

**Why hv-skills over Octo?**

Octo orchestrates multiple AI providers (Claude, Gemini, Codex) for debates, consensus, 100-point PRD scoring across providers, and a Discover/Define/Develop/Deliver pipeline. If cross-model validation is where your value comes from, Octo is purpose-built for it. hv-skills is deliberately single-provider. Instead of cross-AI debate it leans hard into Claude Code: `AskUserQuestion`, subagent dispatch, branch and worktree isolation, atomic commits, and handoff notes that survive `/clear`. Use Octo when you want multiple models second-guessing each other. Use hv-skills when you've decided on Claude Code and want the workflow built around it.

**Why hv-skills over a TODO.md and good intentions?**

Most workflows start that way and most stay there. Three things tend to drift, and hv-skills addresses each. (1) Commits stop being atomic: one PR ends up touching six unrelated things. (2) Knowledge stops accumulating: you re-discover the same gotcha three sessions in a row because nothing reads it back. (3) Sessions don't survive `/clear`: you lose the live hypothesis the moment you step away. `/hv-work` enforces atomic per-task commits, `/hv-learn` writes durable gotchas that future runs auto-consult, and `/hv-pause` / `/hv-next` carry intent across context resets. If none of those bite you in practice, stock Claude Code is fine. If they do, that's the gap hv-skills fills.

## Skills

| Skill | Description |
|-------|-------------|
| `/hv-init` | Initialize `.hv/` with `BACKLOG.md`, `KNOWLEDGE.md`, `MILESTONES.md`, `CONTEXT.md`, `counters.json`, `config.json`, `status.json`, and helpers |
| `/hv-config` | Edit `.hv/config.json` interactively (checklist + native pickers) or via positional shortcuts: `/hv-config <key>` jumps to the picker, `/hv-config <key>=<value>` applies directly |
| `/hv-vision` | Brainstorm a project's bigger vision and milestones using Socratic discovery, web research, and a critique pass; writes `MILESTONES.md` plus per-milestone detail files |
| `/hv-brainstorm` | Per-item design exploration before `/hv-plan` — Socratic discovery, 2-3 approaches with tradeoffs, sectioned design with per-section approval; writes `.hv/designs/<ID>.md` which `/hv-plan` reads as soft input |
| `/hv-capture` | Capture bugs, features, and tasks — auto-classifies, assigns priority/size, routes to the correct section |
| `/hv-c` | Shortcut for `/hv-capture` |
| `/hv-go` | Capture an item and immediately implement it — combines `/hv-capture` + `/hv-work` in one pass |
| `/hv-issues` | Pull open GitHub/GitLab issues into BACKLOG.md with round-trip closing |
| `/hv-rm` | Remove a captured backlog item and clean up its dependencies — dry-run preview by default, asks before applying |
| `/hv-next` | Review backlog, reconcile active work against git state, suggest the next item, route to `/hv-work` |
| `/hv-pause` | Gracefully stop mid-session — writes a handoff note (next step, hypothesis, mid-edit files) for the next session's `/hv-next` |
| `/hv-plan` | Write an implementation plan for a milestone slice or item (`M01-S01`, `M01-B07`) — task decomposition with verifiable outcomes, named assumptions, open questions; `/hv-work` consults if present |
| `/hv-spike` | Throwaway feasibility experiment on a `spike/<name>` branch — branch never merges, only findings come back as `.hv/spikes/<name>.md` |
| `/hv-assume` | Read-only peek of the orchestrator's intended approach — files, tests, assumptions, unknowns; gates `/hv-work` for high-stakes work |
| `/hv-work` | Orchestrated parallel implementation with per-task commits; consults `KNOWLEDGE.md` and `.hv/plans/<key>.md` if present |
| `/hv-debug` | Systematic bug cycle — reproduce, hypothesize, verify, fix with one atomic commit; auto-escalates to a fresh-context subagent after 3 hypothesis cycles, nudges `/hv-learn` |
| `/hv-decide` | Capture a hard-boundary decision into `.hv/DECISIONS.md` — manually confirmed, never auto-invoked; decisions differ from learnings by being active commitments with explicit forbids/permits |
| `/hv-context` | Capture or refine a domain term in `.hv/CONTEXT.md` — the project's canonical glossary; consulted by `/hv-work`, `/hv-debug`, `/hv-vision`, `/hv-capture` |
| `/hv-map` | Maintain `.hv/MAP.md` + `.hv/map/<subsystem>.md` waypoints — entry points, purpose, last-touched date; auto-bumped post-cycle by `/hv-work`, `/hv-debug`, `/hv-go` |
| `/hv-docs` | Scaffold and maintain a public-facing user guide under `docs/` — discovery, scaffold, post-cycle proposals, and restructure modes |
| `/hv-review` | Staff-engineer review of a branch vs original intent + `KNOWLEDGE.md`; returns PASS / CONCERNS / FAIL |
| `/hv-ship` | Bundle commits into a PR (or direct merge) with ID-linked body; runs `/hv-review` first by default |
| `/hv-undo` | Guided rollback of the last `/hv-work` cycle — resets the merge commit, restores TODO entries; dry-run preview, manual confirmation, direct-merge cycles only |
| `/hv-learn` | Extract durable session learnings into `KNOWLEDGE.md`, grouped by topic; Opus verification on by default |
| `/hv-refactor` | Full architectural refactor cycle with parallel design + implementation subagents |
| `/hv-release` | Cut a release: bump version, generate notes, tag, push, publish to GitHub/GitLab. |
| `/hv-update` | Check for a newer hv-skills release on GitHub and print the exact update command for your install type |

## How it works

See [docs/how-it-works.md](docs/how-it-works.md) for the system diagram and how every skill connects to the artifacts it reads or writes.

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

### Drift detection

Every `bin/hv-preflight` (run by most hv-skills) compares the project's recorded `hvSkills.version` against the currently-installed plugin. On drift it prints one informational line nudging `/hv-init` so the project picks up new helpers. Under `autonomy.level: "auto"` or `"loop"`, `/hv-update` also offers (or auto-dispatches) `/hv-init` after a plugin upgrade so the drift clears in one step.

## Architecture

```
.hv/
├── BACKLOG.md        # bugs, features, tasks, recent completions
├── KNOWLEDGE.md      # durable learnings, grouped by topic
├── DECISIONS.md      # hard-boundary decisions with explicit forbids/permits
├── MILESTONES.md     # milestone overview (vision paragraph as intro)
├── ARCHIVE.md        # completions older than 5 days
├── counters.json     # auto-incrementing IDs
├── config.json       # models, isolation, merge, verify, umbrella
├── status.json       # active work streams (keyed by branch, or (branch, repo) in umbrella mode)
├── repos.json        # umbrella mode only — registered sub-repos
├── bugs/ features/ tasks/   # overflow detail files
├── milestones/       # one detail file per milestone (M01.md, M02.md, ...)
├── plans/            # /hv-plan output (M01-S01.md slice plans, M01-B07.md item plans)
├── spikes/           # /hv-spike findings — one file per spike, branch lives in git
├── handoff/          # /hv-pause notes; one per branch (or per (branch, repo) under umbrella)
└── bin/              # CLI helpers — see docs/reference/cli-helpers.md
```

Helpers collapse multi-step agent logic into single subprocess calls. Per-invocation context stays smaller and the output format stays consistent. In umbrella mode the same `.hv/` lives at the umbrella root and coordinates work across sub-repos; see [docs/usage/umbrella-mode.md](docs/usage/umbrella-mode.md).

## Install alternatives

### skills CLI

```bash
npx skills add l4ci/hv-skills
```

### npx one-liner

```bash
npx @anthropic-ai/claude-code plugin marketplace add l4ci/hv-skills
npx @anthropic-ai/claude-code plugin install hv-skills
```

### Local development (GNU Stow)

```bash
git clone https://github.com/l4ci/hv-skills.git ~/Code/hv-skills
stow --dir="$HOME/Code" --target="$HOME/.agents/skills" hv-skills
# remove: stow --dir="$HOME/Code" --target="$HOME/.agents/skills" -D hv-skills
```

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
