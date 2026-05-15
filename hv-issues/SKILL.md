---
name: hv-issues
description: Pull open GitHub/GitLab issues into .hv/BACKLOG.md — list candidates from the upstream repo(s), capture selected ones with GH/GL cross-references, label them in-progress upstream so collaborators see they're claimed. Use on "import issues", "pull open issues from GitHub", "list issues", "capture issues from upstream". Round-trip closing is handled separately by /hv-ship and /hv-merge.
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  📥  hv-issues  ·  pull upstream issues into the backlog
  triggers: "import issues", "pull open issues"  ·  pairs: hv-capture, hv-ship
════════════════════════════════════════════════════════════════════════
```

# hv-issues — Pull Upstream Issues

Inventory-driven capture: fetch open issues from the upstream GitHub or GitLab repo(s), subtract ones already in the backlog, let the user pick which to capture, mint IDs, write detail files, and apply an `in-progress` label upstream behind a manual gate.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Resolve repos* — target repo set determined (Step 2)
2. *Discover candidates* — open issues fetched per repo, already-imported subtracted (Steps 3–4)
3. *Pick issues* — user selects which issues to capture (Step 5)
4. *Capture* — IDs minted, detail files written, BACKLOG.md entries appended (Step 6)
5. *Label upstream* — `in-progress` label applied behind the manual gate (Step 7)
6. *Report* — compact summary printed (Step 8)

## Step 2 — Resolve Target Repo Set

Read `issues.providers.github` and `issues.providers.gitlab` from `.hv/config.json`; if either is `false`, skip repos of that provider type (note the skipped provider inline when the check fires).

**Single-repo mode:** when `.hv/bin/hv-umbrella-on` prints `no` (or `.hv/repos.json` registers 0 sub-repos), target is cwd's repo. Skip the picker and proceed to Step 3 with that single target.

**Umbrella mode:** when `.hv/bin/hv-umbrella-on` prints `yes` AND `.hv/repos.json` registers ≥1 sub-repo:

- Read sub-repo names from `.hv/repos.json`.
- Present them in an AskUserQuestion (multiSelect) chunked to ≤4 options at a time. Header `"Repos"`. Question: *"Which sub-repos to pull issues from?"*. One option per registered repo name; mark all `(Recommended)` when no single repo is obviously favored.
- Include a *"All repos"* option (first option, `Recommended`) and a *"None / cancel"* option (last option).
- **Loop mode:** when `autonomy.level == "loop"`, silently auto-pick the `(Recommended)` option (all repos) without invoking AskUserQuestion — loop mode drains the queue.
- Plain-text fallback: ask once — *"Which repos? (all / <name> / none)"* — `all` picks all; a repo name picks that one; anything ambiguous defaults to all repos.
- If 0 sub-repos resolve after the pick, fall through to single-repo mode.

## Step 3 — Discover Candidates Per Repo

For each target repo, dispatch a **parallel tool-call batch** (all three calls in a single turn):

```bash
.hv/bin/hv-issues-provider [--repo <name>]
.hv/bin/hv-issues-list [--repo <name>] [--label <issues.label>]
.hv/bin/hv-issues-imported [--repo <name>]
```

Read `issues.filterMineOnly` from `.hv/config.json`. When `true`, also pass `--label @me` to `hv-issues-list` — the helper accepts `--label` for filtering; use the value literally (`@me` is a GitHub convention; for GitLab client-side filter the author field after fetching).

Read `issues.label` from `.hv/config.json` (default `"in-progress"`) — this is the label that will be applied in Step 7. Do NOT pass it to `hv-issues-list` as a filter; it is the target label, not a source filter.

Exit-code handling per repo:

- `hv-issues-provider` always exits 0. If it prints `unknown`, skip that repo with: `skipped: <repo> — no recognized remote`.
- `hv-issues-list` exits 0 on success (even empty). If it exits 1 (CLI missing or unauthed), skip that repo with: `skipped: <repo> — <stderr from hv-issues-list>`.
- `hv-issues-imported` always exits 0.

Never hard-fail the whole step on a single repo failure. Continue with the repos that succeeded.

## Step 4 — Subtract Already-Imported Issues

For each repo, filter the `hv-issues-list` output against the `hv-issues-imported` index.

An issue is already imported when a `(provider, repo, issue_number)` triple from `hv-issues-imported` matches. For single-repo mode, `repo` is `null` in the imported index — match on `(provider, issue_number)` only.

Count and report: *"Repo `<name>`: N candidates, K already imported — showing M."*

If the total remaining candidates across all repos is 0, print:

> Nothing to capture — all open issues are already in BACKLOG.md or ARCHIVE.md.

Then stop.

## Step 5 — Show Candidates and Pick

Present candidates in AskUserQuestion (multiSelect) chunked to ≤4 issues at a time. For each chunk:

- **Header:** `"Issues"`
- **Question:** `"Which issues to capture? (<range> of <total>)"`
- **Options** (one per candidate): label `"#<N>: <title truncated to 60 chars>"`, description `"<labels-list> · by @<author> · <url>"`.
- When there is only one chunk (≤4 candidates), omit the range indicator from the question: `"Which issues to capture?"`.

Plain-text fallback: ask once — *"Which issue numbers to capture? (comma-separated, e.g. 12,47,83, or 'none')"* — parse the reply as a comma-separated list of issue numbers; `none` or empty → stop.

**Loop mode:** when `autonomy.level == "loop"`, auto-pick all remaining candidates without invoking AskUserQuestion — loop mode captures everything not already imported. Per the manual-gate rule below, loop mode still surfaces Step 7.

## Step 6 — Classify and Capture Each Pick

For each selected issue:

**6a — Classify section from remote labels.**

| Remote label | Section |
|---|---|
| `bug`, `kind/bug` | `## Bugs` |
| `enhancement`, `feature`, `kind/feature` | `## Features` |
| anything else (or no labels) | `## Tasks` |

When a label maps unambiguously to a section, classify silently (no question). When none of the labels match any classifier key, default to `## Tasks` silently.

**6b — Assign priority / size.**

- Bugs classified from `bug`/`kind/bug` → default `[P1]` silently. Ask only when the issue body suggests `[P0]` (crash, data loss, production outage language) or `[P2]` (cosmetic, wording).
- Features classified from enhancement/feature → default `[Minor]` silently. Ask when the body describes clearly `[Major]` scope (new screens, significant rework, multi-repo).
- Tasks → no tag.

When asking is warranted: one AskUserQuestion per pick (single-select, ≤4 options). Header: `"Classify #<N>"`. Question: `"Priority / size for '<title>'?"`. Options: up to 4 choices relevant to the section (e.g. for Bugs: `"[P0] — crash / data loss"`, `"[P1] — broken feature (Recommended)"`, `"[P2] — cosmetic / edge case"`, `"Leave default"`).

**Loop mode:** when `autonomy.level == "loop"`, skip classification AskUserQuestion calls entirely — use the silent defaults above for every issue.

**6c — Mint ID and write detail file.**

```bash
ID=$(.hv/bin/hv-next-id <bugs|features|tasks>)
```

Write `.hv/<bugs|features|tasks>/<ID>.md` with the issue body as markdown passthrough, followed by:

```markdown
---
**Upstream:** <url>
**Captured from:** <provider> #<N>
```

**6d — Append BACKLOG.md entry.**

```bash
.hv/bin/hv-append "## <Section>" "- **[<ID>] [<Tag>] <Title>.** <first-sentence-or-two-of-body>. Detail: \`.hv/<kind>/<ID>.md\` <provider-tag> Repos: <name>"
```

Where `<provider-tag>` is `GH: #<N>` for GitHub or `GL: #<N>` for GitLab. Omit `Repos: <name>` in single-repo mode. Omit `[<Tag>]` for Tasks (no priority/size tag).

Entry shapes:

- Bug: `- **[B##] [P1] Title.** First sentence of body. Detail: `.hv/bugs/B##.md` GH: #N Repos: <name>`
- Feature: `- **[F##] [Minor] Title.** First sentence of body. Detail: `.hv/features/F##.md` GL: #N Repos: <name>`
- Task: `- **[T##] Title.** First sentence of body. Detail: `.hv/tasks/T##.md` GH: #N Repos: <name>`

Process all selected issues serially in this step (mint → write detail → append) to avoid counter collisions from parallel ID minting.

## Step 7 — Apply the `in-progress` Label Upstream

> **Manual gate — labeling upstream issues.** Applying the `in-progress` label (or the configured `issues.label` value) upstream is externally-visible state — collaborators see the issues marked as claimed. This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. The orchestrator may stage which issues to label, but the user confirms before any label is written. See `references/manual-gates.md`.

Read `issues.label` from `.hv/config.json` (default `"in-progress"`). Present a single AskUserQuestion (single-select):

- **Header:** `"Label upstream"`
- **Question:** `"Apply \`<label>\` to these <N> issues upstream?"` followed by a summary list of picked issue titles and numbers.
- **Options:**
  1. `"Yes — apply \`<label>\` to all (Recommended)"`
  2. `"No — skip labeling"`

Plain-text fallback: ask once — *"Apply `<label>` to these issues upstream? (yes/no)"* — `yes` applies; anything else skips. Default: skip (opt-in-off — this is externally-visible state; silence is not consent).

On **Yes**: fan out parallel `.hv/bin/hv-issues-label` calls — one per picked issue:

```bash
.hv/bin/hv-issues-label apply --issue <N> --label <label> [--repo <name>]
```

On any `hv-issues-label` failure (exit 1), print the error inline and continue with remaining issues — do not abort.

On **No**: print *"Labeling skipped. Issues are captured in BACKLOG.md but not marked upstream."* and continue to Step 8.

**Loop mode:** auto-picking `Yes` is **forbidden** here. This is a manual gate — externally-visible state requires user confirmation. In loop mode, surface the AskUserQuestion and pause the loop until the user resolves it. This matches the `/hv-ship` Step 6a pattern: loop mode never auto-picks acceptance-of-risk answers.

## Step 8 — Compact Report

```
Captured <N> issues:
- [ID1] Title 1 (GH #42 → in-progress)
- [ID2] Title 2 (GL #7 → in-progress)
Skipped <K> issues (already imported).
```

When the label step was skipped (user picked "No" or fallback defaulted to skip), replace `→ in-progress` with `→ not labeled` for each pick.

When repos were skipped in Step 3 (unknown provider or missing CLI), append a `Skipped repos:` section listing each with its reason.

## Rules

- Issues already in BACKLOG.md or ARCHIVE.md are never re-imported. Index by `GH: #N` / `GL: #N` via `hv-issues-imported`. The triple `(provider, repo, issue_number)` is the uniqueness key.
- Label application is always behind the manual gate (Step 7). No `autonomy.level` value bypasses it.
- Loop mode auto-picks routine routing answers (which repo(s) to pull from, which issues to capture) but never the label-application gate.
- This skill writes to `.hv/BACKLOG.md` (gitignored runtime) — no commits are produced. Captured items move forward via `/hv-work` like any other item.
- The `GH: #N` cross-reference on the BACKLOG entry is the signal `hv-ship-body` uses to emit `Closes #N` in PR bodies (F12). Include it exactly.
- `issues.providers.github` / `issues.providers.gitlab` config flags gate provider access per-type. When a flag is `false`, that provider's repos are skipped silently in Step 3 without invoking the CLI.

## References

| Reference | Purpose |
|---|---|
| `references/banner-preamble.md` | Banner-print rule. |
| `references/manual-gates.md` | Step 7 callout shape and gate inventory. |
| `references/authoring-conventions.md` | Loop-mode routing auto-pick rule #5; AskUserQuestion option-list ceiling (4 max). |
| `references/ask-user-question-fallback.md` | Plain-text fallback shape and default-rule selection. |
| `references/umbrella-mode.md` | `.hv/repos.json` resolution; `Repos:` field semantics; `--repo` plumbing. |
