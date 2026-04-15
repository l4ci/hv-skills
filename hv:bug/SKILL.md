---
name: hv:bug
description: Add a bug report to the project's TODO.md with automatic context gathering, priority assignment (P0/P1/P2), and auto-incrementing ID [B-N]. Use when the user wants to capture a bug, defect, or broken behavior for later fixing.
user-invocable: true
---

# hv:bug — Capture a Bug

Quick-capture a bug into `.hv/TODO.md` with just enough context to diagnose and fix it later.

## Step 1 — Ensure .hv/ Exists

Check if `.hv/TODO.md` exists. If not, run `/hv:init` first, then continue.

## Step 2 — Understand the Bug

The user will provide a keyword, short phrase, or longer description. From what they give you, gather **just enough context** to reproduce and fix it later. Ask 2–4 quick questions — no more. Pick from:

- What's the expected vs. actual behavior? (if not obvious)
- How do you trigger it? (steps or conditions)
- Does it happen every time or intermittently?
- Which view/screen/component is affected?
- Any error messages or console output?

**Skip questions the user already answered.** If the user gave a detailed report, you may not need to ask anything. The goal is enough to reproduce, not a full investigation.

## Step 3 — Assign Priority

Assign one of:

| Tag | Meaning |
|-----|---------|
| `[P0]` | Blocks usage — crash, data loss, can't complete core workflow, security issue |
| `[P1]` | Degrades experience — wrong behavior, broken feature, ugly but usable, workaround exists |
| `[P2]` | Minor annoyance — cosmetic glitch, edge case, slightly wrong state, user unlikely to notice |

## Step 4 — Write the Entry

1. Read `.hv/counters.json`, increment `bugs` by 1, write it back
2. Use the new counter value as N in `[B-N]`
3. Add the bug to `## Bugs` in `.hv/TODO.md`

Format:
```markdown
- **[B-N] [Priority] Short title.** One to three sentences of context — what happens, when it happens, what should happen instead. Just enough to reproduce and remember what this was about. Related: [F-2], [T-1]
```

The `Related:` suffix is optional — only add it when the bug clearly relates to an existing item (caused by a feature, blocks a todo, duplicates another bug). Scan `## Bugs`, `## Features`, and `## Todos` in `.hv/TODO.md` and also `.hv/ARCHIVE.md` (if it exists) for obvious connections before writing the entry. Archived items are still valid link targets. Don't force links that aren't there.

Example:
```markdown
- **[B-5] [P1] Timer badge shows stale duration after pause.** When you pause a running timer and reopen the panel 5+ minutes later, the menubar badge still shows the duration from when it was paused, not the current elapsed. Refreshes correctly after any interaction. Likely a timer invalidation issue in MenuBarManager. Related: [F-3]
```

## Rules

- **Never remove or reorder existing entries** — append only
- **Don't investigate the bug now** — just capture it
- **One entry per invocation** — if the user mentions multiple bugs, add the first and tell them to run `/hv:bug` again for the rest
- **Confirm what you wrote** — show the user the exact line you added
- **Always increment the counter** — even if you're unsure, the ID must be unique
