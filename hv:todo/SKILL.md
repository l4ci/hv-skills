---
name: hv:todo
description: Add a general task or chore to the project's TODO.md with auto-incrementing ID [T01]. Use for tasks that aren't bugs or features — refactoring, documentation, dependency updates, CI fixes, research, cleanup, or anything that needs doing.
user-invocable: true
---

# hv:todo — Capture a Task

Quick-capture a general task into the project's TODO.md. For bugs use `/hv:bug`, for features use `/hv:feature`.

## Step 1 — Ensure .hv/ Exists

Check if `.hv/TODO.md` exists. If not, run `/hv:init` first, then continue.

## Step 2 — Understand the Task

The user will provide a keyword, short phrase, or longer description. From what they give you, gather **just enough context** to act on it later. Ask 1–3 quick questions — no more. Pick from:

- What's the goal or desired outcome? (if not obvious)
- Which area of the codebase does this touch?
- Is there a deadline or dependency?
- Any relevant context (error output, PR link, conversation reference)?

**Skip questions the user already answered.** Most tasks need minimal context — a sentence or two is often enough.

## Step 3 — Handle Large Input

If the user's input contains bulky data (migration checklists, dependency audit output, long research notes, CI logs, config dumps, etc.) that would bloat the TODO entry beyond ~2 sentences:

1. Create the directory `.hv/todos/` if it doesn't exist
2. Write a detail file `.hv/todos/T{NN}.md` (using the same zero-padded ID) with this format:

```markdown
# T{NN}: Short title

> Related TODO entry: `[T{NN}]` in `.hv/TODO.md`

## Summary

{The same 1–2 sentence summary that goes into TODO.md}

## Detail

{Full user input — checklist, logs, research notes, config, etc. Preserved verbatim or lightly formatted for readability.}
```

3. In the TODO.md entry, append a `Detail:` reference pointing to the file (see format below)

**Skip this step entirely if the input fits comfortably in 1–2 sentences.** Most todos won't need a detail file — only create one when there's genuinely bulky data that would be lost by summarizing.

## Step 4 — Write the Entry

1. Read `.hv/counters.json`, increment `todos` by 1, write it back
2. Zero-pad the counter to at least 2 digits: 1→`01`, 9→`09`, 10→`10`, 100→`100`
3. Add the task to `## Todos` in `.hv/TODO.md`

Format (without detail file):
```markdown
- **[T01] Short title.** One to two sentences of context — what needs to happen and why. Related: [F01], [B02]
```

Format (with detail file):
```markdown
- **[T01] Short title.** One to two sentences of context — what needs to happen and why. Detail: `.hv/todos/T01.md` Related: [F01], [B02]
```

The `Related:` suffix is optional — only add it when the task clearly relates to an existing item (blocks a feature, required before a bug fix, depends on another todo). Scan `## Bugs`, `## Features`, and `## Todos` in `.hv/TODO.md` and also `.hv/ARCHIVE.md` (if it exists) for obvious connections before writing the entry. Archived items are still valid link targets. Don't force links that aren't there.

Example (without detail file):
```markdown
- **[T02] Update Swift toolchain to 6.2.** Current project uses 5.10. Needed before adopting typed throws and the new concurrency features in the next milestone. Related: [F04]
```

Example (with detail file):
```markdown
- **[T09] Audit and update all deprecated API calls.** 23 deprecation warnings after Xcode 16 update, mostly UIKit lifecycle methods. Detail: `.hv/todos/T09.md` Related: [B03]
```

## Rules

- **Never remove or reorder existing entries** — append only
- **Keep it brief** — todos are often self-explanatory
- **One entry per invocation** — if the user mentions multiple tasks, add the first and tell them to run `/hv:todo` again for the rest
- **Confirm what you wrote** — show the user the exact line you added
- **Always increment the counter** — even if you're unsure, the ID must be unique
