---
name: hv-capture
description: Capture bugs, features, and tasks into the project's TODO.md. Automatically classifies each item, assigns priority/size, and routes to the correct section with zero-padded auto-incrementing IDs ([B01], [F01], [T01]). Use when the user wants to capture any work item — bugs, features, tasks, or a mix.
user-invocable: true
---

# hv-capture — Capture Work Items

Quick-capture bugs, features, and tasks into `.hv/TODO.md` with just enough context to act on them later. Handles multiple items and mixed types in one pass.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

If the helper is absent or exits non-zero, invoke `hv-init` via the `Skill` tool, then continue. See GUIDE.md § Preflight for exit codes.

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

If **multiple** milestones are active, show them as options instead of yes/no:

- One option per active milestone (mark the first listed `(Recommended)`)
- *"No — leave untagged"*
- *"Different milestone"* (free text)

Plain-text fallback: ask *"Tag with M01?"* once. If the reply is ambiguous, default to leaving untagged — under-tagging is recoverable; mis-tagging clutters the milestone view.

**Caller cap:** if the invoking args carry the `(hv-go — cap clarification at 1-2 questions)` prefix and there's exactly one active milestone, **auto-tag without asking** — the speed path uses the obvious answer. With multiple active milestones, skip the question entirely (don't tag anything; the user can edit later).

Carry the chosen milestone(s) as a comma-separated list (`"M01"` or `"M01, M03"`) into Step 6's `Milestone:` suffix. If "No — leave untagged" was picked, omit the suffix entirely.

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

- Bug: `- **[$ID] [Priority] Short title.** What happens, when, what should happen instead. Related: [F02], [T01] Milestone: M01`
- Feature: `- **[$ID] [Size] Short title.** What it does, where it lives, why it matters. Related: [B01], [T03] Milestone: M02`
- Task: `- **[$ID] Short title.** What needs to happen and why. Related: [F01], [B02] Milestone: M01, M03`

With detail file, insert `Detail: \`.hv/{type}/{ID}.md\`` before `Related:`.

**Field order:** title.description. then any combination of `Detail:`, `Related:`, and `Milestone:`. Each is independently optional. `Related:` is for cross-item links; `Milestone:` is for milestone tagging from Step 4.5.

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
- **Split mixed input** — route each item to the correct section with the correct ID type
- **One set of questions for all items** — don't interrogate the user per-item
- **Honor caller caps** — when invoked from a speed-path skill like `/hv-go`, respect the question cap signaled in the invoking args
- **Confirm what you wrote** — show the user every entry you added, grouped by section
- **Always increment counters** — even if you're unsure, every ID must be unique
