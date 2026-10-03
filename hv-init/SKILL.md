---
name: hv-init
description: Initialize the .hv/ folder structure with BACKLOG.md, KNOWLEDGE.md, counters.json, config.json and status.json via `hv init`. Also sets up AGENTS.md (with CLAUDE.md importing it) and seeds the managed knowledge-index blocks in it so future /hv-work runs can consult learnings. Called automatically by other hv: skills when the folder doesn't exist, or manually to set up a new project.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🌱  hv-init  ·  initialize .hv/ folder structure
  triggers: auto-called by other hv skills  ·  pairs: all hv-*
════════════════════════════════════════════════════════════════════════
```

# hv-init — Initialize Project Backlog

Set up `.hv/` for a project. `hv init` does the seeding, the `.gitignore` block, `AGENTS.md`/`CLAUDE.md` and the six managed blocks; this skill only makes the calls that need a human: git, umbrella and the config questions.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate(…)` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases: 1. *Detect* (Step 1) · 2. *Write artifacts* (Step 2) · 3. *Configure* (Step 3) · 4. *Confirm* (Step 4)

## Step 1 — Detect

`git` is a hard requirement:

```bash
command -v git >/dev/null 2>&1 || { echo "error: git is required but not installed" >&2; exit 1; }
hv init umbrella --list --json
```

`--list` is read-only. Read `data.isGitRepo` (is the cwd a git repo) and `data.candidates` (immediate child git repos, sorted). Branch on `isGitRepo` and the candidate count:

**Case A — git repo, fewer than 2 candidates:** continue silently to Step 2.

**Case B — git repo, 2+ candidates:** an existing repo that also holds sub-repos. Use `AskUserQuestion`:

- **Header:** `"Umbrella"`
- **Question:** *"Found multiple git repos here: \<list\>. Enable umbrella mode? (`.hv/` stays at this level; verbs operate per sub-repo.)"*
- **Options** (single-select):
  1. *"Yes, enable umbrella mode (Recommended)"* — *"Registers the child repos with `hv init umbrella`. Sets `umbrella.enabled: true` in config."*
  2. *"No, single-repo init"* — *"Skip umbrella; `/hv-init` proceeds as if the detection didn't fire."*

**Yes** → `UMBRELLA=true` (all repos; a follow-up multiSelect may pick a subset). **No** → `UMBRELLA=false`. Plain-text fallback: ask *"Found N git repos here: \<list\>. Enable umbrella mode? (yes/no)"*; with no reply, default to **No** and note: *"Skipping umbrella mode. Re-run `/hv-init` from this cwd to enable, or toggle `umbrella.enabled` via `/hv-config` later."* `umbrella.enabled` is an opt-in flag (`references/authoring-conventions.md`, *Opt-in feature flags default to `false`*): the cwd signal alone is not approval.

**Case C — not a git repo, fewer than 2 candidates:** `/hv-work`, `/hv-debug`, `/hv-ship` and `/hv-refactor` need git. Use `AskUserQuestion`:

- **Header:** `"Git"`
- **Question:** *"This directory isn't a git repository. Initialize one?"*
- **Options** (single-select):
  1. *"Yes, `git init` now (Recommended)"* — *"Enables all hv skills. Reversible with `rm -rf .git`."*
  2. *"No, backlog-only"* — *"Skip init; capture/next/learn/status still work. Git skills fail until you init manually."*
  3. *"Stop"* — *"Cancel `/hv-init`."*

**Yes** → run `git init`, mention the created branch in the Step 4 summary. **No** → warn *"Warning: not a git repository. /hv-work, /hv-debug, /hv-ship, /hv-refactor will fail until you run `git init`."* **Stop** → exit. Plain-text fallback: run `git init` straight through (Recommended and reversible).

**Case D — not a git repo, 2+ candidates:** fold both questions into one `AskUserQuestion`. List the first 3 candidates; with 4+, append *"and N more"*.

- **Header:** `"Setup"`
- **Question:** *"Found multiple git repos here: `<list>`. This directory isn't itself a git repo. How should `/hv-init` set up?"*
- **Options** (single-select):
  1. *"Umbrella mode (Recommended)"* — *"Register the child repos; `.hv/` stays here. No `git init` at this level — the umbrella is a non-git wrapper."*
  2. *"`git init` here, single-repo"* — *"Initialize this directory as a git repo; ignore sub-repos (vendored, leftover clones)."*
  3. *"Skip git, backlog-only"* — *"Capture/next/learn/status work; `/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-refactor` fail until you init manually."*
  4. *"Stop"* — *"Cancel `/hv-init`."*

Option 1 → `UMBRELLA=true`. Option 2 → `git init`, mention the branch in the summary. Option 3 → the Case C warning. Option 4 → exit. Plain-text fallback: ask once — *"(1) Umbrella mode, (2) git init here, (3) Skip git, (4) Stop?"* — honoring a number or first word; with no reply, default to Option 1 and note *"Defaulting to umbrella mode — `.hv/` will stay here and child repos will be registered. Re-run `/hv-init` to change."* (`references/ask-user-question-fallback.md`).

Umbrella sub-repos are never git submodules; see `.hv/DECISIONS.md` (Architecture) and `docs/usage/umbrella-mode.md`.

## Step 2 — Write Artifacts

```bash
hv init --json
```

Idempotent, never overwrites: seeds `.hv/` and the `.gitignore` block, runs legacy migrations, removes the retired helper mirror, sets up `AGENTS.md` (imported by `CLAUDE.md`) and writes the six managed blocks. Note `data.created` (empty means the project was already initialized) and surface every `data.warnings` line. Exit 70 means a seed file is unreadable or corrupt: show the message and stop.

If `UMBRELLA=true`, register the sub-repos:

```bash
hv init umbrella --all --json        # or --repos a,b for a picked subset
```

It writes `.hv/repos.json` (keeping prior registrations still on disk) and, in a git umbrella, its `.gitignore` block. Keep `data.registered` for the summary.

## Step 3 — Configure

```bash
hv config check --json
```

Exit 1 is a verdict, not an error: branch on `data.status`. `upToDate` → nothing to ask; skip to the version stamp. `corrupt` → tell the user to fix or delete `.hv/config.json`, then rerun `/hv-init`; stop. `stale` → `data.missing` lists the absent keys: all of them on a fresh project, only the newly added ones on an upgrade. `fresh` (no `config.json`, rare after `hv init`) → treat as `stale` with every key missing: ask all five.

Ask, in one `AskUserQuestion` call, only the questions whose keys appear in `missing`: Q1 `models.*`, Q2 `work.isolation`, Q3 `work.mergeStrategy`, Q4 `ship.review`/`learn.verify`/`refactor.confirmBeforeExecute`/`debug.competingHypotheses`, Q5 `autonomy.level`. Wording, options and the answer-to-value mapping are canonical in [`docs/reference/config-options.md`](../docs/reference/config-options.md). "(Recommended)" marks the default; a native skip or plain-text no-reply takes the Recommended answers. The `orchestrator.*` keys (handoff threshold and ages) are silent defaults: not asked, not seeded.

Then fill every other missing key with its schema default and write the answers, the umbrella flag and the version stamp:

```bash
hv config fill
hv config set <key> <value>                  # once per answered key
hv config set umbrella.enabled true          # only when UMBRELLA=true
hv config set hvSkills.version <version>     # always; data.version from `hv version --json`
```

`fill` never touches a key already present, so upgrades keep every prior value. It does not seed the silent keys either (`round.scope`, `round.roster`, `round.brief`, `round.sharedPaths`, `round.stallMinutes`, `issues.labels.needsHuman`): they take their default until someone sets them. The stamp is rewritten on every run: re-running `/hv-init` is how version drift clears.

## Step 4 — Confirm

```bash
hv init check --json
```

Exit 1 (`data.initialized: false`) means a core file is still missing: report every path in `data.missing` and stop. Surface the envelope's top-level `warnings` (umbrella-flag mismatch, version drift) as one line each.

Tell the user one compact block:

```
Initialized .hv/ in <project>.
Config: <"defaults" if all Recommended, else a one-liner e.g. "Balanced models, worktree isolation, PR merges, verifier on">.
Next: /hv-capture to add items, /hv-next to pick work, /hv-learn to save learnings, /hv-learn --term <name> for glossary terms.
Edit .hv/config.json or run /hv-config to change these later.
```

If `hv init` created nothing, say it was already initialized and the blocks were refreshed. Config `upToDate` → drop the config line; an upgrade → *"Config migrated: added `<keys>` (Recommended)."* (`fill`'s `data.filled` plus the answered keys). `UMBRELLA=true` → add *"Umbrella mode enabled — registered sub-repos: <data.registered>"*.

**Version line.** Run `hv update --json` and branch on `data.status`:

- `current` → *"hv-skills `<currentVersion>` (latest)"*
- `behind` → *"hv-skills `<currentVersion>` → `<latestVersion>` available — run `/hv-update`"*
- `ahead` → *"hv-skills `<currentVersion>` (ahead of `<latestVersion>` — likely a dev install)"*
- `unknown`, a non-zero exit or empty data → *"hv-skills `<currentVersion>`"*

## References

- [`references/authoring-conventions.md`](../references/authoring-conventions.md) — Authoring rules shared across SKILL.md files; edit rules there, not here.
- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`references/ask-user-question-fallback.md`](../references/ask-user-question-fallback.md) — Plain-text fallback shape.
