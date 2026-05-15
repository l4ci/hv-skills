---
name: hv-capture
description: Capture bugs, features, and tasks into BACKLOG.md without executing them. Classifies each item, assigns priority/size, mints zero-padded IDs ([B01], [F01], [T01]). Use when the user brain-dumps work, says "capture", "add to backlog", "note this bug", "/hv-capture", "/hv-c", or describes a problem without asking for an immediate fix. Records only — for an immediate fix use /hv-go; for items already in BACKLOG use /hv-work.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  📥  hv-capture  ·  capture work items into .hv/BACKLOG.md
  triggers: "capture", "log bug"  ·  pairs: hv-go, hv-next
════════════════════════════════════════════════════════════════════════
```

# hv-capture — Capture Work Items

Quick-capture bugs, features, and tasks into `.hv/BACKLOG.md` with just enough context to act on them later. Handles multiple items and mixed types in one pass.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Mode / dispatch* — single brain-dump or per-item parsing path resolved (Step 2)
2. *Classify* — type (bug / feature / task), priority, size assigned (Step 3)
3. *Dedupe* — existing TODO entries scanned for overlap (Step 4)
4. *Append* — entries written to `BACKLOG.md` with milestone + repo tags (Steps 5–6)
5. *Report* — compact summary printed (Step 7)

## Step 2 — Parse & Classify

The user will provide a keyword, short phrase, or longer description — possibly covering multiple issues or mixing bugs with feature requests and tasks.

**Split the input into distinct items.** Each item is a separate concern that would get its own ID. Clues that you're looking at multiple items:

- Separate sentences about unrelated problems
- "Also…", "and another thing…", "plus…"
- A list (numbered, bulleted, or comma-separated)
- Mixed language: some items describe broken behavior (→ bug), some describe desired behavior that doesn't exist yet (→ feature), some describe chores or maintenance (→ task)

**Classify each item:**

| Goes to | When the item describes… |
|---------|--------------------------|
| `## Bugs` | Broken behavior — something that worked and stopped, or doesn't work as expected |
| `## Features` | New or enhanced behavior — something that doesn't exist yet but should |
| `## Tasks` | Chores and maintenance — refactoring, dependency updates, docs, CI, cleanup |

## Step 3 — Gather Context

For each item, gather **just enough context** to make it actionable later. Ask 2–4 quick questions total across all items — not per item.

**Caller caps.** If the invoking args carry a speed-path signal from an upstream skill (e.g., a `(hv-go — cap clarification at 1-2 questions)` prefix), respect it — usually 1-2 questions max, often zero. `/hv-go` prioritizes speed over thoroughness; honoring the cap is what keeps that contract.

Pick from:

**For bugs:**
- What's the expected vs. actual behavior? (if not obvious)
- How do you trigger it? (steps or conditions)
- Does it happen every time or intermittently?
- Which view/screen/component is affected?
- Any error messages or console output?

**For features:**
- What's the user-facing behavior? (if not obvious)
- Which part of the app does this touch?
- Is there an existing workaround?
- What triggers the need for this?

**For tasks:**
- What's the goal or desired outcome? (if not obvious)
- Which area of the codebase does this touch?
- Is there a deadline or dependency?
- Any relevant context (error output, PR link, conversation reference)?

**Skip questions the user already answered.** If the input is detailed enough, you may not need to ask anything.

## Step 4 — Assign Priority / Size

For **bugs**, assign one of:

| Tag | Meaning |
|-----|---------|
| `[P0]` | Blocks usage — crash, data loss, can't complete core workflow, security issue |
| `[P1]` | Degrades experience — wrong behavior, broken feature, ugly but usable, workaround exists |
| `[P2]` | Minor annoyance — cosmetic glitch, edge case, slightly wrong state, user unlikely to notice |

For **features**, assign one of:

| Tag | Meaning |
|-----|---------|
| `[Major]` | Large scope — new screens, significant rework, breaks existing patterns, multi-day effort |
| `[Minor]` | Contained change — new option, small UI addition, touches 1–3 files, hours of work |
| `[Cosmetic]` | Visual polish — spacing, color, label tweak, animation refinement, minutes of work |

**Tasks** get no priority or size tag.

## Step 4.5 — Tag Active Milestone (when applicable)

Use the milestone-tagging UX pattern in `references/milestone-tagging.md`. The pattern covers: the `hv-vision-active` gate, the one-active vs multiple-active question shapes (verbatim AskUserQuestion text), caller-cap handling for the `/hv-go` speed path, loop-mode auto-pick semantics, plain-text fallback, and the outcome mapping.

Carry the chosen milestone(s) as a comma-separated list into Step 6's `Milestone:` suffix on the TODO entry. If the user picked the "leave untagged" option (or skipped the question), omit the suffix.

## Step 4.6 — Tag Sub-Repo (when umbrella mode is on)

Use the umbrella-mode gate from `references/umbrella-mode.md` — when `hv-umbrella-on` returns `yes` AND `.hv/repos.json` registers ≥1 sub-repo (the registry is the truth, not the config flag), ask which sub-repo(s) each item belongs to. Otherwise skip this step silently.

The question shape:

- **Header:** `"Repos"`
- **Question:** *"Which sub-repo(s) does this item belong to?"* (include the item's short title for context)
- **multiSelect:** `true`
- **Options** (one per registered repo + an explicit untag option):
  - One option per `name` in `.hv/repos.json` (mark the most likely match `(Recommended)` if the item's text mentions a repo name)
  - *"None / unsure — leave untagged"* (last option)

Multi-select means the user can pick one sub-repo (single-repo item), two or more (multi-repo item — `/hv-work` will create the same branch in each via `bin/hv-multi-branch-create`, see `references/umbrella-mode.md` *Branch creation*), or just *"None / unsure"* to leave the item untagged. If the user picks *"None / unsure"* alongside concrete repo names, treat the concrete picks as authoritative.

Plain-text fallback: ask once. If the reply is ambiguous, default to leaving the item untagged — `/hv-work` will then refuse to dispatch the item with a clear error pointing back to `/hv-capture`.

**Caller cap:** if invoked with the `(hv-go — cap clarification at 1-2 questions)` prefix and there's exactly one registered repo, auto-tag without asking. With ≥2 registered repos, the cap is exempt for this single question — silently skipping would force `/hv-work` to bail later.

**Loop mode:** if `autonomy.level == "loop"`, auto-pick the `(Recommended)` sub-repo option when one is flagged (item text mentions a repo name). If no option carries `(Recommended)` (item is ambiguous about sub-repo), fall through to AskUserQuestion or the caller-cap path; this is exactly the kind of ambiguity that should surface. Honors the authoring convention "routine routing/tagging auto-picks Recommended in loop mode" (see `references/authoring-conventions.md` rule #5).

Carry the chosen sub-repo name(s) as a comma-separated string into Step 6's `Repos:` suffix on the TODO entry. If only *"None / unsure"* was picked (or nothing was picked), omit the suffix.

## Step 5 — Handle Large Input

Use the detail-files pattern in `references/detail-files.md` when an item's input is bulky enough to bloat the TODO entry beyond ~3 sentences (crash dumps, stack traces, logs, specs, checklists, config snippets, long reproduction steps). The reference covers the markdown template, the ordering (get ID → write detail file → append TODO entry with `Detail:` reference), and the `Detail:` reference format.

Skip this step entirely for items that fit comfortably in 1–3 sentences. Most entries won't need a detail file.

## Step 6 — Write All Entries

**Consult `## Project Context`.** Before composing the bullet, scan the always-on `## Project Context` block. If the user's phrasing maps to a canonical term (or one of its aliases), use the canonical name in the captured bullet so the backlog stays consistent with the rest of the project's vocabulary. If the captured idea introduces a *new* domain concept the user names explicitly, suggest `/hv-context <term>` after the capture commits — never auto-invoke.

For each item, get the next ID and append the entry in a single command:

```bash
ID=$(.hv/bin/hv-next-id bugs) && .hv/bin/hv-append "## Bugs" "- **[$ID] [P1] Short title.** Description. Related: [F02]"
```

Change the type (`bugs`, `features`, `tasks`), section (`## Bugs`, `## Features`, `## Tasks`), and entry content for each item.

**Entry formats:**

- Bug: `- **[$ID] [Priority] Short title.** What happens, when, what should happen instead. Related: [F02], [T01] Milestone: M01 Repos: web`
- Feature: `- **[$ID] [Size] Short title.** What it does, where it lives, why it matters. Related: [B01], [T03] Milestone: M02 Repos: api`
- Task: `- **[$ID] Short title.** What needs to happen and why. Related: [F01], [B02] Milestone: M01, M03 Repos: web`

With detail file, insert `Detail: \`.hv/{type}/{ID}.md\`` before `Related:`.

**Field order:** title.description. then any combination of `Detail:`, `Related:`, `Milestone:`, `Repos:`, and `Subsystem:` (optional). Each is independently optional. `Related:` is for cross-item links; `Milestone:` is for milestone tagging from Step 4.5; `Repos:` is for sub-repo tagging from Step 4.6 (umbrella mode only — comma-separated list of registered sub-repos; a single name is the common case, two or more turns the item into a multi-repo dispatch via `/hv-work`); `Subsystem:` is the project-map subsystem this item belongs to.

**Subsystem inference (optional).** Scan filenames and skill references in the user's text against the entries in `.hv/map/` (or the `## Project Map` block in CLAUDE.md). If a match is clear — e.g. the user mentions `hv-work`, `bin/hv-staleness`, or `hv-map` — append `Subsystem: <name>` (the closest map entry name) to the captured row. If no confident match exists, omit the field entirely. **Never block or delay capture for a missing Subsystem.** The field is a soft hint for map hygiene, not a required tag.

Example:
```
Before: - **[B07] [P1] Title.** Description. Milestone: M01 Captured: 2026-05-09
After:  - **[B07] [P1] Title.** Description. Milestone: M01 Subsystem: capture Captured: 2026-05-09
```

The `Related:` suffix is optional — only add it when an item clearly relates to an existing entry. **Items created in the same batch can reference each other.** Scan `## Bugs`, `## Features`, and `## Tasks` in `.hv/BACKLOG.md` and also `.hv/ARCHIVE.md` (if it exists) for obvious connections before writing. Don't force links that aren't there.

### Examples

Single bug:
```markdown
- **[B05] [P1] Timer badge shows stale duration after pause.** When you pause a running timer and reopen the panel 5+ minutes later, the menubar badge still shows the duration from when it was paused, not the current elapsed. Refreshes correctly after any interaction. Likely a timer invalidation issue in MenuBarManager. Related: [F03]
```

Single feature:
```markdown
- **[F03] [Minor] Quick-switch between recent projects.** Cmd+Tab-style overlay that shows the 3 most recent projects for fast switching without opening the project picker. Useful for consultants bouncing between clients throughout the day. Related: [B05]
```

Single task:
```markdown
- **[T02] Update Swift toolchain to 6.2.** Current project uses 5.10. Needed before adopting typed throws and the new concurrency features in the next milestone. Related: [F04]
```

Bug with detail file:
```markdown
- **[B07] [P0] App crashes on launch after iOS 18.2 update.** EXC_BAD_ACCESS in CoreData stack during migration. Affects all users on 18.2+, 100% repro rate. Detail: `.hv/bugs/B07.md` Related: [F12]
```

Feature tagged with the active milestone:
```markdown
- **[F08] [Minor] OAuth token rotation.** Refresh tokens 5 minutes before expiry; transparent retry on 401. Milestone: M01
```

Feature tagged with sub-repo (umbrella mode):
```markdown
- **[F09] [Minor] Sticky header on scroll.** Keep the top nav fixed when the user scrolls past 100px. Milestone: M02 Repos: web
```

Mixed input — user says *"the sidebar flickers on hover, also we should add keyboard shortcuts for the top 5 actions, and update the linter config to enable the new rules"*:
```markdown
## Bugs
- **[B03] [P2] Sidebar flickers on hover.** Hover state causes a visible flicker, likely a re-render or transition conflict in the sidebar component.

## Features
- **[F04] [Minor] Keyboard shortcuts for top actions.** Add keyboard shortcuts for the 5 most-used actions to speed up power-user workflows.

## Tasks
- **[T06] Update linter config for new rules.** Enable the recently added lint rules in the project config. Related: [B03]
```

## Step 7 — Brainstorm Nudge

Fires only when the captured batch includes at least one `[Major]` feature OR one `[P0]` bug. Skip silently for `[Minor]` / `[Cosmetic]` features and `[P1]` / `[P2]` bugs — design exploration is a poor fit for small contained work.

Append one line to the capture report for each qualifying ID, in every autonomy mode (`off` / `auto` / `loop`):

> *"Run `/hv-brainstorm [ID]` before `/hv-plan` to negotiate the design."*

Place this line after any existing post-capture nudges (e.g., release-pending), separated by one blank line.

**Never invoke `/hv-brainstorm` from this skill.** Capture is pure intake; pulling the user into design exploration mid-brain-dump conflates two phases the workflow keeps separate. Autonomous advancement lives where "advance without asking" semantics belong: `/hv-next` Step 6 auto-dispatches `/hv-brainstorm` for the suggested item in `auto` mode, and `/hv-work` Step 4 auto-dispatches `/hv-brainstorm --auto-loop` for Major + Milestone-tagged items without a design in `loop` mode. The nudge line above is the bridge to either path.

## Rules

- **Never remove or reorder existing entries** — append only
- **Don't investigate now** — just capture
- **Confirm what you wrote** — show the user every entry you added, grouped by section
- **Always increment counters** — even if you're unsure, every ID must be unique

## References

| Reference | Purpose |
|-----------|---------|
| [`authoring-conventions.md`](../references/authoring-conventions.md) | Authoring rules shared across SKILL.md files (loop-mode auto-picks, mirror-step threshold). |
| [`banner-preamble.md`](../references/banner-preamble.md) | Banner-print rule shared by every skill. |
| [`detail-files.md`](../references/detail-files.md) | Detail-file template used when an item's input exceeds 3 sentences. |
| [`milestone-tagging.md`](../references/milestone-tagging.md) | Milestone-tagging UX pattern used by capture/go skills. |
| [`umbrella-mode.md`](../references/umbrella-mode.md) | Umbrella-mode helpers, registry shape, and `Repos:` field semantics. |
