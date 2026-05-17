# The `.hv/` folder

[`/hv-init`](slash-commands.md#hv-init) creates this folder once per project. Everything inside is Markdown or JSON, and most of it is tracked by default — only six machine-specific or regenerated paths are gitignored. Use the skill helpers to update tracked content; reach for hand-editing only when investigating or fixing something that drifted.

## Overview

| File | Purpose |
|------|---------|
| `BACKLOG.md` | Active backlog — bugs, features, tasks, and recent completions |
| `KNOWLEDGE.md` | Durable learnings grouped by topic — gotchas, conventions, constraints |
| `DECISIONS.md` | Hard-boundary decisions with explicit forbids/permits — active commitments future work must respect |
| `MILESTONES.md` | Milestone overview — one short section per milestone, with a vision intro paragraph and an active list |
| `MAP.md` + `map/<subsystem>.md` | Project map — AI-facing narratives describing one coherent area each. Source-of-truth for the `## Project Map` block in `CLAUDE.md`. Hand-authored; `touched:` auto-bumped by cycle skills (`/hv-work`, `/hv-debug`, `/hv-go`). |
| `counters.json` | Auto-incrementing IDs for each item type |
| `config.json` | Model selection, isolation mode, merge strategy, ship/learn/refactor gates, autonomy level (team-shared defaults) |
| `config.local.json` | _(gitignored)_ Per-developer config overrides — deep-merged on top of `config.json` by `load_config()`. Use for `autonomy.level`, model preferences, or any setting that varies per machine. |
| `status.json` | _(gitignored)_ Active work streams — which items are being worked on, on which branch/worktree (per-developer) |
| `repos.json` | _(gitignored, umbrella mode only)_ Sub-repo registry with absolute paths — machine-specific |
| `bin/` | _(gitignored)_ CLI helpers — `hv-next-id`, `hv-append`, `hv-complete`, … Regenerated mirror of canonical `bin/`, overwritten on every `/hv-init` |
| `bugs/` | Overflow detail files for large bug reports |
| `features/` | Overflow detail files for large feature specs |
| `tasks/` | Overflow detail files for large task descriptions |
| `milestones/` | One detail file per milestone (`M01.md`, `M02.md`, …) — full plan with goal, acceptance, rationale, risks, research findings, notes |
| `plans/` | Implementation plans keyed by `<milestone>-<unit>.md` (slices: `M01-S01.md`; items: `M01-B07.md`) |
| `spikes/` | Spike findings — one Markdown file per spike; the experimental code lives on the `spike/<name>` git branch and is never merged |
| `handoff/` | _(gitignored)_ `/hv-pause` notes — one file per branch capturing hypothesis, next step, mid-edit files; consumed by `/hv-next`. Per-developer scratch. |
| `qa-runs/` | _(gitignored)_ Timestamped `/hv-qa` run artifacts — bulky, regeneratable from the strategy in `qa/<target>.md` |
| `RELEASE.md` | Release checklist — `- [ ]` items `/hv-release` walks as gates before bumping version. Tracked, shared with the team. |
| `ARCHIVE.md` | Completed items older than 5 days, moved here automatically |

## BACKLOG.md — active backlog

`BACKLOG.md` is the single source of truth for everything in flight. It holds open bugs, features, and tasks organised by type, plus a "recently completed" section at the bottom. [`/hv-capture`](../usage/capturing-work.md) appends new items, and [`/hv-next`](../usage/picking-work.md) reads it to suggest what to work on next.

A typical entry looks like:

```
- [ ] B03 — login redirect loops after OAuth token refresh
```

Edit this file by hand whenever you want: reorder items, bump priorities, or delete things no longer relevant. The skills re-read it on every invocation, so any manual change takes effect immediately.

## KNOWLEDGE.md — durable learnings + glossary

`KNOWLEDGE.md` stores durable project knowledge: gotchas, team conventions, architectural constraints, and anything else you don't want to rediscover later. Entries sit under free-form topic headings. [`/hv-learn`](../usage/learning.md) appends new learnings at the end of a session.

One topic is special-cased: `## Glossary` holds domain-terminology entries as nested bullets (`- **<term>** — <definition>` with indented `**Aliases:**` / optional `**Not:**` / date stamp). The Glossary topic is pinned at `/hv-init` time; entries are written via `/hv-learn --term <name>` (helper `hv-glossary-write`) and read via `hv-glossary-read <term>`. The F03 tier lifecycle skips Glossary — terms are canonical, not probationary.

See [../usage/learning.md](../usage/learning.md) for how to capture and review knowledge.

`/hv-init` inserts a managed block in `CLAUDE.md` that lists the current topics (`Glossary` surfaces here like any other topic). That block keeps knowledge visible to the model across context clears without re-reading the full file.

## DECISIONS.md — hard-boundary decisions

`DECISIONS.md` records hard boundaries the project has committed to. It is the sibling of `KNOWLEDGE.md`, but where knowledge is passive (gotchas, conventions), decisions are active commitments with explicit `forbids:` and `permits:` clauses. [`/hv-decide`](../usage/decisions.md) writes new entries; [`/hv-work`](../usage/running-work.md), [`/hv-debug`](../usage/debugging.md), [`/hv-plan`](../usage/vision-and-plans.md), [`/hv-refactor`](slash-commands.md#hv-refactor), [`/hv-review`](../usage/review-and-ship.md), and [`/hv-vision`](../usage/vision-and-plans.md) consult them as constraints.

A companion managed block in `CLAUDE.md` lists the current decision topics so the model can pull only the relevant entries on demand.

See [../usage/decisions.md](../usage/decisions.md) for the full capture flow and the difference between decisions and learnings.

## MILESTONES.md — milestone overview

`MILESTONES.md` lists the milestones, each with a one-paragraph overview and status, opened by a short vision intro paragraph as preamble. `/hv-vision` writes the initial version, and you update it as the project evolves.

See [../usage/vision-and-plans.md](../usage/vision-and-plans.md) for how milestones work with planning and implementation skills.

A companion managed block in `CLAUDE.md` lists active milestones so `/hv-next` and [`/hv-pause`](../usage/pausing-and-resuming.md) can scope their suggestions to what is in progress.

## MAP.md — project map

`MAP.md` is an AI-facing index of project subsystems. It holds a brief summary for each named area; full narratives live in `map/<subsystem>.md` and are loaded on demand via `hv-map-query <name>`. Write `.hv/map/<name>.md` files by hand as you discover subsystems — one file per coherent area, with `subsystem:`/`summary:`/`touched:` frontmatter and free-form body sections (Purpose, Entry points, Key files / dirs, Conventions, Notes / gotchas). Cycle skills (`/hv-work`, `/hv-debug`, `/hv-go`) bump `touched:` post-cycle when their changes overlap a subsystem's key files or entry points, and regenerate the always-on `## Project Map` block in `CLAUDE.md` via `.hv/bin/hv-map-index`. When subsystems drift or duplicate, edit or retire `.hv/map/<name>.md` entries directly; the index helper picks up the change on the next run.

A managed `## Project Map` block in `CLAUDE.md` surfaces the thin summary so the model can orient without loading detail files.

## counters.json — auto-incrementing IDs

`counters.json` tracks the highest ID assigned for each item type so that IDs never collide across sessions.

```json
{ "bug": 3, "feature": 7, "task": 12, "milestone": 2, "spike": 1 }
```

You should not need to edit this by hand. If you ever manually delete items from `BACKLOG.md`, the counters are safe to leave as-is; IDs are never reused.

## config.json — settings

`config.json` stores project-level preferences: which model to use, whether branch isolation is on, how merges are handled, the ship/learn/refactor gate thresholds, and the autonomy level for orchestration.

See [../usage/configuration.md](../usage/configuration.md) for the full list of options and how to change them with `/hv-config`.

## status.json — active work streams

`status.json` records which items are currently being worked on and which git branch or worktree each one lives in. It is written when work starts and cleared when work completes or is paused.

See [../usage/picking-work.md](../usage/picking-work.md) for how `/hv-next` uses this file to orient the model after a context clear.

## bin/ — CLI helpers

`bin/` contains small shell scripts that the skills rely on for safe, idempotent file mutations: appending a new item, marking an item complete, or fetching the next available ID. `/hv-init` generates them, and they are not intended to be called directly. See the [CLI helpers reference](./cli-helpers.md) for full documentation.

## bugs/, features/, tasks/ — overflow detail files

When a bug report, feature spec, or task description is too long to fit inline in `BACKLOG.md`, the overflow content goes into a separate file in the matching subdirectory (e.g. `bugs/B03.md`). The `BACKLOG.md` entry links to it. This keeps `BACKLOG.md` scannable while preserving full detail.

Create these files by hand, or let `/hv-capture` handle it when you supply a long description.

## milestones/ — per-milestone plans

Each milestone gets its own detail file (`milestones/M01.md`, `milestones/M02.md`, …) containing the full plan: goal, acceptance criteria, rationale, risks, research findings, and working notes. `/hv-vision` creates an initial file for each milestone it defines.

## plans/ — implementation plans

`plans/` holds the output of `/hv-plan`: one Markdown file per planning unit, named after the milestone and item it covers (`M01-S01.md` for a slice, `M01-B07.md` for a specific bug). Plans are consumed by `/hv-work` when it orchestrates implementation.

See [../usage/vision-and-plans.md](../usage/vision-and-plans.md) for the full planning workflow.

## spikes/ — feasibility findings

`spikes/` stores the written findings from [`/hv-spike`](../usage/spikes.md) runs: one Markdown file per spike summarising what was learned, what was tried, and what the recommendation is. The throwaway experimental code lives on its own `spike/<name>` git branch and is never merged.

## handoff/ — pause notes

When you run `/hv-pause`, the current state of the session (active hypothesis, next planned step, files mid-edit, gotchas just discovered, uncommitted-work strategy) is written to `handoff/<branch>.md`. `/hv-next` reads any matching note for an active branch and uses it to restore intent that pure git state can't carry across `/clear` or a fresh session.

Notes are scoped per branch and overwritten by subsequent `/hv-pause` runs on the same branch. They are not auto-cleaned, so delete them by hand once the branch is shipped.

See [../usage/pausing-and-resuming.md](../usage/pausing-and-resuming.md) for the pause/resume flow.

## ARCHIVE.md — old completions

Completed items are moved from `BACKLOG.md` to `ARCHIVE.md` automatically after they have been in the completed section for more than five days. This keeps `BACKLOG.md` short without losing history. You can read `ARCHIVE.md` at any time; no skill reads it during normal operation.

## What's tracked and what's gitignored

The backlog is shared by default — state travels with the repo so collaborators see the same `BACKLOG.md`, learn from the same `KNOWLEDGE.md`, and respect the same `DECISIONS.md`. Six paths stay gitignored because they're machine-specific, per-developer, or regenerated on demand:

| Path | Why ignored |
|------|-------------|
| `.hv/bin/` | Regenerated mirror of canonical `bin/`; overwritten on every `/hv-init` |
| `.hv/status.json` | Per-developer active-work tracking, branch-aware |
| `.hv/repos.json` | Umbrella sub-repo registry with absolute paths (machine-specific) |
| `.hv/config.local.json` | Per-developer config overrides (see below) |
| `.hv/handoff/` | Per-developer `/hv-pause` scratch notes |
| `.hv/qa-runs/` | Bulky timestamped `/hv-qa` artifacts; regeneratable |

`/hv-init` writes these under a `# ── hv-skills ──` header in your project's `.gitignore`. Projects upgrading from blanket-ignore (v4.0.x and earlier) have the legacy `.hv/` line migrated automatically.

### `config.local.json` — per-developer overrides

Drop a JSON file at `.hv/config.local.json` to override any setting from `.hv/config.json` for your machine only. `load_config()` (in `bin/hvlib_io.py`) deep-merges it on top of the shared config — nested keys merge recursively; scalars and arrays replace. Example:

```json
{
  "autonomy": { "level": "off" },
  "models": { "worker": "haiku" }
}
```

This overrides `autonomy.level` and `models.worker` while inheriting every other key (including `models.orchestrator`) from the shared `config.json`. Typical uses: per-developer autonomy preferences, model selection for cost or latency, or experimenting with a setting without committing it to the team default.

### Opting out — fully private backlog

If you'd rather keep the whole `.hv/` folder private (solo development, or experimentation that isn't ready to share), add a blanket `.hv/` line to `.gitignore` before your first commit. The pattern is supported but is no longer the default.
