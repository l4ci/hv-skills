---
name: hv-docs
description: Scaffold and maintain a public-facing user guide under <docs.path>/ (default docs/) at repo root — aimed at consumers of the project, not contributors. Four invocation modes — first-run (discovery + scaffold), after-work (post-cycle proposals), restructure (audit + reorganize), and manual. This version implements the first-run mode; after-work lands in M01-S02 and restructure in M01-S04.
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

Scaffolds and maintains a public user guide under `<docs.path>/` (default `docs/`) for the people who *use* the project — CLI users, library consumers, API clients, app users — not contributors. Three runtime modes (first-run, after-work, restructure) plus a `.docsignore` boundary and on-write secret scrub for safety. This slice adds the after-work mode (propose mode, `autoCreate=false`) on top of the previously-shipped first-run flow. Restructure mode and the autoCreate path land in M01-S04 / M01-S03.

## Modes

| Detected when | Mode | Status |
|---|---|---|
| `<docs.path>/` doesn't exist or is empty | First-run (discovery + scaffold) | **Implemented in this slice** |
| Invoked by `/hv-work` / `/hv-ship` post-cycle | After-work (propose/write doc updates) | **Implemented in this slice (propose mode)** |
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

On failure, invoke `hv-init` via the `Skill` tool.

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

Plain-text fallback: ask once in prose. If the answer is ambiguous, default to the Recommended option, name it explicitly, and proceed.

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

## After-work Flow

This flow is invoked by `/hv-work` Step 13.5 / `/hv-ship` Step 8.6 (those wires land in M01-S05; this slice defines the SKILL.md side).

## Step A1 — Trigger Gate

Trigger condition (same as `/hv-learn`'s): **2+ items resolved**, OR **≥5 files touched**, OR a **hard bug** that took multiple debug cycles. Skip entirely for single-item fixes and pure mechanical changes. Don't repeat in the same session.

If `<docs.path>/` doesn't exist or is empty, **don't run this flow** — print one line: *"`/hv-docs` not yet initialized — run `/hv-docs` to scaffold."* and exit. Don't auto-scaffold mid-cycle.

## Step A2 — Gather Context

In a **single parallel batch** (one tool-call response, multiple reads), gather:

- `git log --oneline <last-docs-marker>..HEAD` — boundary is the last `docs:` commit's SHA. Fall back to last 20 commits if no `docs:` commit exists yet.
- `git diff <last-docs-marker>..HEAD -- <changed-paths>` — filtered through `.docsignore` (Layer-1 filter; in this slice that filter is a **pass-through stub**: read all paths as-is. Note: `bin/hv-docs-filter` lands in M01-S03).
- Current `<docs.path>/` tree (one-level listing) and each existing page's H1+H2 outline (`grep -E '^#{1,2} ' <page>`).

Issue these as parallel tool calls in a single response. Don't do them sequentially.

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

Layer-2 scrub on the final draft text is a **pass-through stub** in this slice — note: `bin/hv-docs-scrub` lands in M01-S03.

## Step A5 — Approval Gate

Show all drafts in one batch (plain markdown — same as the first-run proposal in Step 4). Then ask via `AskUserQuestion`:

- **Header:** `"Docs"`
- **Question:** *"Apply these doc updates?"*
- **Options** (single-select):
  1. *"Apply all (Recommended)"*
  2. *"Apply selectively"* — free text. User lists the page paths to apply; revise the apply set and proceed.
  3. *"Skip"* — don't write anything; exit cleanly. Doesn't advance the `docs:` marker.
  4. *"Cancel"* — same as Skip in this slice; reserved for future-divergent semantics.

Plain-text fallback: ask once in prose. If the answer is ambiguous, default to the Recommended option, name it explicitly, and proceed.

## Step A6 — Commit

Write the chosen edits idempotently (don't overwrite unrelated content). Then a **single** `docs:` commit. Message format:

```
docs: <one-line summary>

- <page>: <one-line per-page change>
- <page>: <…>

Resolves: [B07], [F03]
```

`Resolves:` lists the item IDs of the work cycle that triggered this run (passed in by the calling skill's Skill-tool brief). If no IDs were passed (manual `/hv-docs` invocation), omit the `Resolves:` line.

`autoCreate: true` (auto-write path) lands in M01-S03 and adds Layer-3 LLM safety review before commit. This slice ships propose-mode only.

## Key Principles

- **First-run is interactive — never auto-scaffold.** Always go through Step 4's `AskUserQuestion` before writing.
- **Stubs are honest empty sections, not hallucinated content.** The user fills the substance; the skill provides the spine.
- **`<docs.path>/README.md` is the spine.** Every other page links from there.
- **`.docsignore` is the safety boundary.** Seeded with safe defaults; user extends.
- **Don't narrate the discovery analysis.** It shapes the proposal silently.
- **After-work runs in propose mode by default.** `docs.autoCreate: false` (the default) means every batch goes through user approval; `true` (auto-write + Layer-3 LLM review) lands in M01-S03.
