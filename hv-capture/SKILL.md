---
name: hv-capture
description: Capture bugs, features, and tasks into TODO.md without executing them. Classifies each item, assigns priority/size, mints zero-padded IDs ([B01], [F01], [T01]). Records only — for an immediate fix use /hv-go; for items already in TODO use /hv-work.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  📥  hv-capture  ·  capture work items into .hv/TODO.md
  triggers: "capture", "log bug"  ·  pairs: hv-go, hv-next
════════════════════════════════════════════════════════════════════════
```

# hv-capture — Capture Work Items

Quick-capture bugs, features, and tasks into `.hv/TODO.md` with just enough context to act on them later. Handles multiple items and mixed types in one pass.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

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

```bash
.hv/bin/hv-vision-active
```

If the helper prints nothing, no milestones are active — skip this step entirely.

If exactly **one** milestone is active and there's no caller cap signaling speed, ask once:

- **Header:** `"Milestone"`
- **Question:** *"Tag these items with `<MID> — <title>`?"* (the active milestone's title)
- **Options** (single-select):
  1. *"Yes — tag all (Recommended)"*
  2. *"No — leave untagged"*
  3. *"Different milestone"* (free text — accept any `M\d+` value that exists)

If **multiple** milestones are active, always ask via `AskUserQuestion` — there's no obvious default to auto-pick:

- **Header:** `"Milestone"`
- **Question:** *"Tag these items with which milestone?"*
- **Options** (single-select):
  1. One option per active milestone, labelled `<MID> — <title>` (title from each milestone file's frontmatter `title:`; mark the first listed `(Recommended)`)
  2. *"None / unrelated — leave untagged"*
  3. *"Different milestone"* (free text — accept any `M\d+` value that exists)

Plain-text fallback: ask *"Tag with M01?"* once. If the reply is ambiguous, default to leaving untagged — under-tagging is recoverable; mis-tagging clutters the milestone view.

**Caller cap:** if the invoking args carry the `(hv-go — cap clarification at 1-2 questions)` prefix and there's exactly one active milestone, **auto-tag without asking** — the speed path uses the obvious answer. With multiple active milestones, the cap is **exempt for this single question** — silently skipping the tag would orphan items from every milestone view, which is worse than spending one question. Ask the multi-active question above; this counts toward the cap, so spend remaining clarification budget carefully (often zero further questions).

**Loop mode:** if `autonomy.level == "loop"`, auto-pick the Recommended milestone option without invoking AskUserQuestion. With one active milestone, that's *"Yes — tag all (Recommended)"* — tag the items with the active milestone. With multiple active milestones, that's the first-listed milestone (the option marked `(Recommended)` above). Loop mode treats milestone tagging as routine; the user's queue is the active milestone work, so tagging items into it is the obvious answer. This honors the `hv-init` authoring convention "routine routing/tagging auto-picks Recommended in loop mode."

Carry the chosen milestone(s) as a comma-separated list (`"M01"` or `"M01, M03"`) into Step 6's `Milestone:` suffix. If "No — leave untagged" was picked, omit the suffix entirely.

## Step 4.6 — Tag Sub-Repo (when umbrella mode is on)

If umbrella mode is enabled AND there's at least one registered sub-repo, ask the user which sub-repo each item belongs to. Otherwise skip this step silently.

**Gate check:**

```bash
if [ "$(.hv/bin/hv-umbrella-on)" = "yes" ]; then
  PYTHONPATH=.hv/bin python3 -c "
from hvlib import load_repos
import sys; sys.exit(0 if load_repos() else 1)
"
else
  exit 1
fi
```

If exit code is non-zero, skip Step 4.6 entirely. Move on to Step 5.

**When umbrella mode is on with registered repos**, use a single `AskUserQuestion` per captured item (or one batched call if all items share the same answer is obvious — e.g., the user said *"fix the navbar in web"*; you can pre-answer with `"web"` and skip the question). Otherwise:

- **Header:** `"Repos"`
- **Question:** *"Which sub-repo(s) does this item belong to?"* (include the item's short title for context)
- **multiSelect:** `true`
- **Options** (one per registered repo, plus the explicit untag option):
  - One option per `name` in `.hv/repos.json` (mark the most likely match `(Recommended)` if the item's text mentions a repo name)
  - *"None / unsure — leave untagged"* (last option)

Multi-select means the user can pick exactly one sub-repo (single-repo item), two or more (multi-repo item — `/hv-work` will create the same branch in each via `bin/hv-multi-branch-create`), or just *"None / unsure"* to leave the item untagged. If the user picks *"None / unsure"* alongside concrete repo names, treat the concrete picks as authoritative and ignore the untag option.

Plain-text fallback: ask once. If the reply is ambiguous, default to leaving the item untagged. (`/hv-work` will then refuse to dispatch the item with a clear error pointing back to `/hv-capture`.)

**Caller cap:** if the invoking args carry the `(hv-go — cap clarification at 1-2 questions)` prefix and there's exactly one registered repo, **auto-tag without asking** — the speed path uses the obvious answer. With ≥2 registered repos, the cap is **exempt for this single question** — silently skipping the tag would force `/hv-work` to bail later, which is worse than spending one question.

**Loop mode:** if `autonomy.level == "loop"`, auto-pick the Recommended sub-repo option when one option is marked `(Recommended)` (i.e., the item's text mentions a repo name and the option list flagged the obvious match). If no option carries `(Recommended)` — the item is ambiguous about which sub-repo it targets — fall through to AskUserQuestion or the Caller-cap path; this is exactly the kind of ambiguity that should surface, not be silently routed.

Carry the chosen sub-repo name(s) as a comma-separated string (e.g. `"web"` or `"web, api"`) into Step 6's `Repos:` suffix. If only *"None / unsure"* was picked (or nothing was picked), omit the suffix entirely.

## Step 5 — Handle Large Input

If any item's input contains bulky raw data (crash dumps, stack traces, log output, specs, checklists, config snippets, long reproduction steps, etc.) that would bloat the TODO entry beyond ~3 sentences:

1. Get the ID first (Step 6 command), then write a detail file using that ID:

```markdown
# {ID}: Short title

> Related TODO entry: `[{ID}]` in `.hv/TODO.md`

## Summary

{The same 1–3 sentence summary that goes into TODO.md}

## Detail

{Full user input — crash dump, stack trace, logs, specs, checklists, etc. Preserved verbatim or lightly formatted for readability.}
```

2. In the TODO.md entry, append a `Detail:` reference pointing to the file (see format below)

**Skip this step entirely for items that fit comfortably in 1–3 sentences.** Most entries won't need a detail file.

## Step 6 — Write All Entries

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

The `Related:` suffix is optional — only add it when an item clearly relates to an existing entry. **Items created in the same batch can reference each other.** Scan `## Bugs`, `## Features`, and `## Tasks` in `.hv/TODO.md` and also `.hv/ARCHIVE.md` (if it exists) for obvious connections before writing. Don't force links that aren't there.

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

## Rules

- **Never remove or reorder existing entries** — append only
- **Don't investigate now** — just capture
- **Confirm what you wrote** — show the user every entry you added, grouped by section
- **Always increment counters** — even if you're unsure, every ID must be unique
