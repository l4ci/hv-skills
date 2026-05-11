---
name: hv-docs
description: Scaffold and maintain a public-facing user guide under <docs.path>/ (default docs/) — aimed at consumers, not contributors. Modes — first-run (discovery + scaffold), after-work (post-cycle proposals), restructure (audit + reorganize). Use on "/hv-docs", "update docs"; auto-invoked by /hv-work and /hv-ship post-cycle.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  📖  hv-docs  ·  public user-guide maintainer
  triggers: "/hv-docs", "update docs"  ·  pairs: hv-work, hv-refactor
════════════════════════════════════════════════════════════════════════
```

# hv-docs — Public User-Guide Maintainer

## Modes

| Detected when | Mode |
|---|---|
| `<docs.path>/` doesn't exist or is empty | First-run (discovery + scaffold) |
| Invoked by `/hv-work` / `/hv-ship` post-cycle | After-work (propose doc updates) |
| Invoked by `/hv-refactor`, or `/hv-docs restructure` | Restructure (audit + reorganize) |
| Manual invoke, no signal | First-run if `<docs.path>/` missing; else nudge |

If invoked in a not-yet-implemented mode, print one line citing the slice and exit cleanly.

`/hv-docs` and `/hv-map` share the three-mode skeleton (scaffold / after-work / audit) and intentionally diverge on artifact root, gate strength, and authoring tier — see `references/three-mode-skill-shape.md`.

## Configuration

Read `.hv/config.json`:

- `docs.path` — relative path to the docs folder (default `"docs"`)
- `docs.autoCreate` — whether after-work mode auto-writes (default `false`; when `true`, after-work commits go in without the per-batch approval gate)
- `docs.afterWork` — whether `/hv-work` and `/hv-ship` invoke `/hv-docs` post-cycle (default `false`). Toggled via `/hv-config` or by running `/hv-docs` manually (first-run scaffold flips it `true` automatically; manual run on an existing `<docs.path>/` asks).

Missing keys fall back to defaults silently — `/hv-init` migration adds them on schema upgrade.

> **Architecture rule — one `docs/` tree per project.** A single hv-skills project has exactly one `docs/` tree, located either at the umbrella root or inside one chosen sub-repo (recorded via `docs.repo` config when needed). Forbids: multiple `docs/` trees inside a single hv-skills project, per-sub-repo `docs/` *in addition to* an umbrella `docs/`, `/hv-docs` writing to more than one target. Permits: a single `docs/` at the umbrella root (cross-cutting docs); a single `docs/` inside one chosen sub-repo (when that sub-repo owns the project's public surface); cross-cutting documentation living in the chosen tree.
>
> **`docs/` is the public surface.** It's consumer-facing — contributor and contract content lives in the skill that owns it (`hv-*/SKILL.md`), not in a parallel reference file. Cross-refs from `docs/` and `README.md` point at `docs/` pages or specific SKILL.md files, never at a centralized internals doc.

## Step 1 — Preflight & First-Run Detection

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

Read `docs.path` from `.hv/config.json` (default `"docs"`). Check whether `<docs.path>/` exists and is non-empty:

```bash
[ -d "<docs.path>" ] && [ -n "$(ls -A "<docs.path>" 2>/dev/null)" ]
```

- **Empty or missing** → continue with first-run mode (Steps 2–6).
- **Non-empty** → not a first-run scenario. Branch on `docs.afterWork`:
  - **Already `true`** → After-work mode is already enabled. Print *"`<docs.path>/` already exists and after-work mode is on. Re-running `/hv-docs` manually has no further effect; the flow auto-runs after `/hv-work` and `/hv-ship` cycles. Use `/hv-config` to toggle off."* and exit.
  - **`false` (default)** → ask via `AskUserQuestion`:
    - **Header:** `"After-work"`
    - **Question:** *"`<docs.path>/` is initialized but `docs.afterWork` is off. Enable after-work mode? `/hv-work` and `/hv-ship` will then auto-invoke `/hv-docs` to propose doc updates after each cycle."*
    - **Options** (single-select):
      1. *"Enable (Recommended)"* — write `docs.afterWork: true` to `.hv/config.json`, print *"After-work mode enabled. `/hv-work` and `/hv-ship` will now invoke `/hv-docs` post-cycle."*, exit.
      2. *"Leave off"* — exit without changes.
    - Plain-text fallback: ask once. Default to "Leave off" if ambiguous (opt-in semantics — never silently flip a config flag the user didn't ask for).

The config write uses the shared helper:

```bash
.hv/bin/hv-config-set docs.afterWork true
```

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Mode select", description="Decide first-run / after-work / restructure based on docs/ state and config")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (after-work mode opt-out, no doc updates needed) get `completed` with the no-op reason in the description.

Phases:

1. *Mode select* — first-run / after-work / restructure resolved from `docs.path` state + config (Step 1)
2. *Inspect docs/* — current pages and structure read (Step 2)
3. *Discover topics* — touched files + recent commits scanned for doc-worthy changes (Step 3)
4. *Propose plan* — doc updates drafted and shown to user (Step 4)
5. *Write/update* — pages created or edited (Step 5)
6. *Cross-link* — internal links and indices updated (Step 6)
7. *Report* — summary printed, autonomy nudges fired

## Step 2 — Read Project Signals

In a **single parallel batch** (one tool-call response, multiple reads), gather:

- `README.md` (or `README.rst`) at repo root — if present
- Manifest files at repo root: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`, `setup.py`, `*.gemspec`, `Gemfile` — read whichever exist
- Top-level `bin/` listing (one level only) — entry points hint at CLI surface
- Top-level `src/` listing (one level only) — high-level module shape; don't read contents
- Recent git history: `git log --oneline -20`
- Root-level `.md` files other than README (CHANGELOG, CONTRIBUTING, LICENSE) — note presence; don't duplicate

Don't dump the contents to the user — form a picture and use what's relevant in Step 3.

## Step 3 — Form Hypothesis (silent)

Internally classify the project type. Pick one (or note "mixed" if genuinely ambiguous):

- **CLI tool** — `bin/*` entry points, manifest declares CLI commands, README focuses on `command --flag` examples
- **Library** — exports public functions/classes, README has API examples, no CLI
- **Web app / service** — server entry point, route definitions, deployment-shaped manifest
- **Plugin / extension** — manifest declares it as a plugin (e.g., `claude-plugin/plugin.json`), pairs with a host system
- **Framework** — provides primitives others build on; README has "getting started" + "core concepts" structure
- **Data project** — pipelines, notebooks, dataset-shaped repo

Identify the **user-facing surface** for the chosen type — what consumers actually interact with. For a CLI tool, the commands and flags. For a library, the public API. For a web app, the routes / UI. For a plugin, the host-system integration points.

**Don't dump this analysis to the user.** It shapes the proposal in Step 4.

## Step 4 — Propose Tailored Tree

Output a clear proposal as plain markdown — file tree under `<docs.path>/`, one-line purpose per file. Example shape (the actual tree depends on the project type and surface from Step 3 — tailor it):

```
<docs.path>/
├── README.md            # landing page + table of contents
├── getting-started.md   # 5-minute first-run walkthrough
├── usage/
│   ├── basics.md        # core workflow
│   └── <command>.md     # one page per major user surface
├── configuration.md     # if config exists
└── examples.md          # only if patterns are non-obvious
```

Then ask via `AskUserQuestion`:

- **Header:** `"Scaffold"`
- **Question:** *"Approve this docs structure?"*
- **Options** (single-select):
  1. *"Approve as proposed (Recommended)"*
  2. *"Edit"* — free text. User describes changes; revise the proposal and re-ask Step 4.
  3. *"Minimal — `README.md` + `getting-started.md` only"*
  4. *"Cancel"* — don't scaffold; exit.

Plain-text fallback: ask once in prose; default to Recommended on ambiguity, naming it explicitly. See `references/ask-user-question-fallback.md`.

On **Cancel** — print *"Scaffold cancelled. Run `/hv-docs` again whenever you're ready."* and exit.

### Page-naming convention

The tailored tree should follow the spine + usage + reference layout documented in `references/docs-conventions.md` (page-naming section). When the tailored proposal doesn't fit (e.g., a CLI tool with no usage phases, or a library with API references but no walkthroughs), describe the deviation in one line in your proposal — *"This project ships only reference material; no `usage/` pages proposed."* — so the user sees the conscious choice.

## Step 5 — Scaffold on Approval

For each proposed file, write it with:

- Title heading (`# Page Title`)
- One-line purpose comment (HTML comment or italics — match the convention you see in the existing project's `.md` files)
- Honest empty section stubs (`## What you'll learn`, `## Steps`, etc., depending on page type) — **no LLM-hallucinated content**

Write `<docs.path>/README.md` as a real index — TOC linking every other proposed page. This is the only page that ships with non-stub content (the TOC itself).

Seed `.docsignore` at repo root if it doesn't already exist — use the template in `references/docs-conventions.md` (`.docsignore` seed section). Make all writes idempotent — never overwrite an existing file.

After scaffolding succeeds, set `docs.afterWork: true` in `.hv/config.json` automatically — the user just opted into the docs flow by approving the scaffold, so the after-work gate flips on with the same approval. No separate question needed. Use `.hv/bin/hv-config-set docs.afterWork true` (same pattern as Step 1's manual-toggle branch). Skip silently if `docs.afterWork` is already `true`.

## Step 6 — Closing Summary

Print a short summary block:

```
Scaffolded <docs.path>/ — N pages.

Files:
  - <docs.path>/README.md  (index / TOC)
  - <docs.path>/getting-started.md
  - <docs.path>/usage/basics.md
  - ...

Next:
  Run /hv-work on a feature, then /hv-docs will fill in pages from the changes.
  Or write <docs.path>/getting-started.md yourself first to set the voice.
```

## After-work Flow

This flow is invoked by `/hv-work` Step 13.6 and `/hv-ship` Step 8.6 — those steps gate on `docs.afterWork` (default `false`); when on, they dispatch `/hv-docs` via `Skill` post-cycle and pass the resolved item IDs + touched files. Manual invocation also runs this flow when `<docs.path>/` exists and the flag is on.

## Step A1 — Trigger Gate

Apply the post-cycle trigger condition defined in `references/post-cycle-trigger-gate.md` (2+ items resolved / ≥5 files touched / hard bug). Skip for single-item fixes and pure mechanical changes; don't repeat in the same session.

If `<docs.path>/` doesn't exist or is empty, **don't run this flow** — print one line: *"`/hv-docs` not yet initialized — run `/hv-docs` to scaffold."* and exit. Don't auto-scaffold mid-cycle.

## Step A2 — Gather Context

In a **single parallel batch** (one tool-call response, multiple reads), gather:

- `git log --oneline <last-docs-marker>..HEAD` — boundary is the last `docs:` commit's SHA. Fall back to last 20 commits if no `docs:` commit exists yet.
- `git diff <last-docs-marker>..HEAD -- <changed-paths>` — filtered through `.docsignore` (Layer-1 filter; the orchestrator reads `.docsignore` and skips matching paths from the diff).
- Current `<docs.path>/` tree (one-level listing) and each existing page's H1+H2 outline (`grep -E '^#{1,2} ' <page>`).

## Step A3 — Classify Changes

For each non-ignored diff file, decide: user-facing surface change (doc-relevant) vs internal-only refactor/test/build (not doc-relevant).

**Doc-relevant** heuristics:

- Changes to `bin/*` entry points
- Public API exports
- Route handlers
- CLI flag definitions
- Config-key surface
- Plugin-manifest entries
- README-shaped behavior

**Internal-only** heuristics:

- Tests
- Build scripts
- Internal helpers not re-exported
- Refactors with no visible behavior change
- CI config, lint config
- Dependency bumps

LLM judgment is the primary signal; the heuristics are hints, not hard gates.

If **no** files classify as doc-relevant after this pass, print one line (*"No user-facing changes since last `docs:` commit. Skipping."*) and exit cleanly.

## Step A4 — Map to Pages + Draft Edits

Per doc-relevant change, pick a target page from `<docs.path>/`:

- An existing page that covers the surface (e.g., `usage/<command>.md` for a CLI flag change).
- Or `*needs new page*` — propose a path under `<docs.path>/` with one-line rationale; never auto-create a page in propose mode.

Draft a concrete before/after fragment per page using a simple unified-diff-shaped block:

```
<docs.path>/usage/foo.md
- old line or section
+ new line or section
```

Drafts should reference real file/section anchors (e.g., the H2 heading the edit lands under). No hallucinated content; if no concrete edit can be drafted, mark the entry "*needs prose — author yourself*" and skip it from the apply set.

## Step A5 — Approval Gate

Show all drafts in one batch (plain markdown — same as the first-run proposal in Step 4). Then ask via `AskUserQuestion`:

- **Header:** `"Docs"`
- **Question:** *"Apply these doc updates?"*
- **Options** (single-select):
  1. *"Apply all (Recommended)"*
  2. *"Apply selectively"* — free text. User lists the page paths to apply; revise the apply set and proceed.
  3. *"Skip"* — don't write anything; exit cleanly. Doesn't advance the `docs:` marker.
  4. *"Cancel"* — same as Skip in this slice; reserved for future-divergent semantics.

Plain-text fallback: ask once in prose; default to Recommended on ambiguity, naming it explicitly. See `references/ask-user-question-fallback.md`.

## Step A6 — Commit

Write the chosen edits idempotently (don't overwrite unrelated content). Then a **single** `docs:` commit. Message format:

```
docs: <one-line summary>

- <page>: <one-line per-page change>
- <page>: <…>

Resolves: [B07], [F03]
```

`Resolves:` lists the item IDs of the work cycle that triggered this run (passed in by the calling skill's Skill-tool brief). If no IDs were passed (manual `/hv-docs` invocation), omit the `Resolves:` line.

`autoCreate: true` (auto-write path, default `false`) skips the per-batch approval gate in Step A5 — drafts are written and committed directly. The propose-mode flow above still runs for review/manual-invoke.

## Key Principles

- **First-run is interactive — never auto-scaffold.** Always go through Step 4's `AskUserQuestion` before writing.
- **Stubs are honest empty sections, not hallucinated content.** The user fills the substance; the skill provides the spine.
- **`<docs.path>/README.md` is the spine.** Every other page links from there.
- **`.docsignore` is the safety boundary.** Seeded with safe defaults; user extends.
- **Don't narrate the discovery analysis.** It shapes the proposal silently.
- **After-work runs in propose mode by default.** `docs.autoCreate: false` (the default) means every batch goes through user approval; `true` skips the approval gate and commits directly.
