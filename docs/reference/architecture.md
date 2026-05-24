# Architecture

Everything Claude reads or mutates lives under `.hv/` in your project. Git is the source of truth; `status.json` is just a cache, and `/hv-next` reconciles drift between the two whenever it runs.

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
├── bugs/ features/ tasks/   # overflow detail files
├── milestones/       # one detail file per milestone (M01.md, M02.md, ...)
├── plans/            # /hv-plan output (M01-S01.md slice plans, M01-B07.md item plans)
├── spikes/           # /hv-spike findings — one file per spike, branch lives in git
├── handoff/          # /hv-pause notes; one per branch (or per (branch, repo) under umbrella)
└── bin/              # CLI helpers — see cli-helpers.md
```

Helpers collapse multi-step agent logic into single subprocess calls. Per-invocation context stays smaller and the output format stays consistent. In umbrella mode the same `.hv/` lives at the umbrella root and coordinates work across sub-repos; see [umbrella mode](../usage/umbrella-mode.md).

## Drift detection

Every `bin/hv-preflight` (run by most hv-skills) compares the project's recorded `hvSkills.version` against the currently-installed plugin. On drift it prints one informational line nudging `/hv-init` so the project picks up new helpers. Under `autonomy.level: "auto"` or `"loop"`, `/hv-update` also offers (or auto-dispatches) `/hv-init` after a plugin upgrade so the drift clears in one step.

## Related

- [How hv-skills works](../how-it-works.md): system diagram and lane overview
- [Slash commands](slash-commands.md): every `/hv-*` command
- [CLI helpers](cli-helpers.md): the `.hv/bin/` scripts
- [`.hv/` folder reference](hv-folder.md): per-file detail
