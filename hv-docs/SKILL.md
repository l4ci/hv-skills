---
name: hv-docs
description: Scaffold and maintain a public-facing user guide under <docs.path>/ (default docs/) at repo root — aimed at consumers of the project, not contributors. Four invocation modes — first-run (discovery + scaffold), after-work (post-cycle proposals), restructure (audit + reorganize), and manual. This version implements the first-run mode; after-work lands in M01-S02 and restructure in M01-S04. See GUIDE.md § Documentation for the full surface.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  📖  hv-docs  ·  public user-guide maintainer
  triggers: "/hv-docs", "update docs"  ·  pairs: hv-work, hv-refactor
════════════════════════════════════════════════════════════════════════
```

# hv-docs — Public User-Guide Maintainer

Scaffolds and maintains a public user guide under `<docs.path>/` (default `docs/`) for the people who *use* the project — CLI users, library consumers, API clients, app users — not contributors. Three runtime modes (first-run, after-work, restructure) plus a `.docsignore` boundary and on-write secret scrub for safety. This slice implements the first-run discovery + scaffold flow.

## Modes

| Detected when | Mode | Status |
|---|---|---|
| `<docs.path>/` doesn't exist or is empty | First-run (discovery + scaffold) | **Implemented in this slice** |
| Invoked by `/hv-work` / `/hv-ship` post-cycle | After-work (propose/write doc updates) | _Coming in M01-S02_ |
| Invoked by `/hv-refactor`, or `/hv-docs restructure` | Restructure (audit + propose splits/merges) | _Coming in M01-S04_ |
| Manual invoke, no signal | Falls through to first-run if `<docs.path>/` missing; else nudge | _Partial — first-run path implemented_ |

If invoked in a not-yet-implemented mode, print one line stating the mode is coming in a later slice (cite the slice key) and exit cleanly.

## Configuration

Read `.hv/config.json`:

- `docs.path` — relative path to the docs folder (default `"docs"`)
- `docs.autoCreate` — whether after-work mode auto-writes (default `false`; consumed by M01-S02 onward, not this slice)

Missing keys fall back to defaults silently — `/hv-init` migration adds them in M01-S05.

## Step 1 — Preflight & First-Run Detection

```bash
.hv/bin/hv-preflight
```

On failure, invoke `hv-init` via the `Skill` tool. See GUIDE.md § Preflight.

Read `docs.path` from `.hv/config.json` (default `"docs"`). Check whether `<docs.path>/` exists and is non-empty:

```bash
[ -d "<docs.path>" ] && [ -n "$(ls -A "<docs.path>" 2>/dev/null)" ]
```

- **Empty or missing** → continue with first-run mode (Steps 2–6).
- **Non-empty** → not a first-run scenario. Print one line: *"`<docs.path>/` already exists. After-work mode coming in M01-S02; restructure mode coming in M01-S04."* and exit.

## Step 2 — Read Project Signals

In a **single parallel batch** (one tool-call response, multiple reads), gather:

- `README.md` (or `README.rst`) at repo root — if present
- Manifest files at repo root: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`, `setup.py`, `*.gemspec`, `Gemfile` — read whichever exist
- Top-level `bin/` listing (one level only) — entry points hint at CLI surface
- Top-level `src/` listing (one level only) — high-level module shape; don't read contents
- Recent git history: `git log --oneline -20`
- Root-level `.md` files other than README (CHANGELOG, CONTRIBUTING, LICENSE) — note presence; don't duplicate

Issue these as parallel tool calls in a single response. Load latency dominates this step.

Don't dump the contents to the user. Form a picture and use what's relevant in Step 3.

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

Plain-text fallback: ask once in prose. If the answer is ambiguous, default to the Recommended option, name it explicitly, and proceed. (See GUIDE.md § Host Question Conventions.)

On **Cancel** — print *"Scaffold cancelled. Run `/hv-docs` again whenever you're ready."* and exit.

## Step 5 — Scaffold on Approval

For each proposed file, write it with:

- Title heading (`# Page Title`)
- One-line purpose comment (HTML comment or italics — match the convention you see in the existing project's `.md` files)
- Honest empty section stubs (`## What you'll learn`, `## Steps`, etc., depending on page type) — **no LLM-hallucinated content**

Write `<docs.path>/README.md` as a real index — TOC linking every other proposed page. This is the only page that ships with non-stub content (the TOC itself).

Seed `.docsignore` at repo root if it doesn't already exist:

```
# hv-docs — never read these as source material for public docs
.env
.env.*
**/secrets/**
**/credentials*
**/*.key
**/*.pem
**/internal/**
**/private/**

# Common build/dependency dirs (also kept out for noise reasons)
node_modules/
dist/
build/
.next/
target/
```

Make all writes idempotent — never overwrite an existing file.

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

## Key Principles

- **First-run is interactive — never auto-scaffold.** Always go through Step 4's `AskUserQuestion` before writing.
- **Stubs are honest empty sections, not hallucinated content.** The user fills the substance; the skill provides the spine.
- **`<docs.path>/README.md` is the spine.** Every other page links from there.
- **`.docsignore` is the safety boundary.** Seeded with safe defaults; user extends.
- **Don't narrate the discovery analysis.** It shapes the proposal silently.
