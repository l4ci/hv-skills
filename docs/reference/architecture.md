# Architecture

Everything Claude reads or mutates lives under `.hv/` in your project. Git is the source of truth; `status.json` is just a cache, and `/hv-work` (no argument) reconciles drift between the two whenever it runs.

## `.hv/` layout

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
├── workers.json      # round state: slots, escalations, usage-limit log (gitignored)
├── verdicts.json     # recorded review, second-opinion and QA verdicts (gitignored)
├── bugs/ features/ tasks/   # overflow detail files
├── milestones/       # one detail file per milestone (M01.md, M02.md, ...)
├── plans/            # /hv-plan output (M01-S01.md slice plans, M01-B07.md item plans)
├── spikes/           # /hv-spike findings — one file per spike, branch lives in git
└── handoff/          # /hv-pause notes, and the orchestrator's handoff (<base>.md)
```

`hv` verbs collapse multi-step agent logic into single subprocess calls. Per-invocation context stays smaller and the output format stays consistent. In umbrella mode the same `.hv/` lives at the umbrella root and coordinates work across sub-repos; see [umbrella mode](../usage/umbrella-mode.md).

## Round state outside `.hv/`

A [parallel round](../usage/parallel-rounds.md) keeps its per-repo state in the git common directory (`git rev-parse --git-common-dir`, which is `.git` in a plain checkout). Every worktree of the repo shares it, so the orchestrator and every worker see the same files, and none of it is tracked. It lives under `<git-common-dir>/hv/`:

```
<git-common-dir>/hv/
├── round-lease.json     # who the orchestrator is: pid, start time, pane, round number
├── session/<id>.json    # one per Claude session: context %, rate limits, last refresh
├── keepalive.json       # the keepalive supervisor's state (hv keepalive run)
├── limit-watch.json     # the running usage-limit watcher, if any
└── codex/<slot>/        # CODEX_HOME for each Codex worker slot
```

| File | Written by | Read by |
|---|---|---|
| `round-lease.json` | `hv round start` (or the supervisor); released by `hv round wind-down`, cleared when stale by `hv reap --kind lease` | every round verb, the hooks, `hv keepalive status` |
| `session/<id>.json` | the statusline (`hv statusline dump`) on every refresh; files idle for 24 hours are dropped by the next dump | `hv hook stop`, `hv limit watch` |
| `keepalive.json` | `hv keepalive run` on every transition | `hv keepalive status`, the Stop hook (the usage hold) |
| `limit-watch.json` | `hv limit watch`, or the supervisor's own watcher | `hv limit status`, a second `watch` (to refuse it) |
| `codex/<slot>/` | `hv round assign --kind codex`, and `codex login` | the Codex worker |

The lease is what makes a session "the orchestrator". The Stop and SessionStart hooks act only for the session that holds it, so installing them wide leaves workers alone. Under `hv keepalive run` the supervisor holds the lease for its whole life, across restarts, and hands the pid to the orchestrator it starts through `HV_ROUND_HOLDER_PID`.

The Codex homes sit outside `.worktrees/`, so `hv reap` never sees them and a `wind-down` keeps each slot's login. `~/.codex` is never used for a slot.

The registry the round writes inside the project is `.hv/workers.json`: see [`.hv/` folder](hv-folder.md#workersjson-round-state). The orchestrator's handoff is `.hv/handoff/<base>.md`, delivered to the next session by the SessionStart hook.

## Drift detection

`hv version --drift` compares the project's recorded `hvSkills.version` against the installed binary. On drift, rerun `hv init` to re-stamp the project.

## Related

- [How hv works](../how-it-works.md): system diagram and lane overview
- [Slash commands](slash-commands.md): every `/hv-*` command
- [`hv` verb reference](cli-helpers.md): every verb
- [`.hv/` folder reference](hv-folder.md): per-file detail
