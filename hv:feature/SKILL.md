---
name: hv:feature
description: Add a feature idea to the project's TODO.md with automatic context gathering, size categorization (Major/Minor/Cosmetic), and auto-incrementing ID [F-N]. Use when the user wants to capture a feature idea, enhancement, or improvement for later.
user-invocable: true
---

# hv:feature — Capture a Feature

Quick-capture a feature idea into the project's TODO.md with just enough context to pick it up later.

## Step 1 — Ensure .hv/ Exists

Check if `.hv/TODO.md` exists. If not, run `/hv:init` first, then continue.

## Step 2 — Understand the Feature

The user will provide a keyword, short phrase, or longer description. From what they give you, gather **just enough context** to make the item actionable later. Ask 2–4 quick questions — no more. Pick from:

- What's the user-facing behavior? (if not obvious)
- Which part of the app does this touch?
- Is there an existing workaround?
- What triggers the need for this?

**Skip questions the user already answered.** If the user gave a detailed description, you may not need to ask anything. The goal is a memory-jogger paragraph, not a spec.

## Step 3 — Categorize Size

Assign one of:

| Tag | Meaning |
|-----|---------|
| `[Major]` | Large scope — new screens, significant rework, breaks existing patterns, multi-day effort |
| `[Minor]` | Contained change — new option, small UI addition, touches 1–3 files, hours of work |
| `[Cosmetic]` | Visual polish — spacing, color, label tweak, animation refinement, minutes of work |

## Step 4 — Write the Entry

1. Read `.hv/counters.json`, increment `features` by 1, write it back
2. Use the new counter value as N in `[F-N]`
3. Add the feature to `## Features` in `.hv/TODO.md`

Format:
```markdown
- **[F-N] [Size] Short title.** One to three sentences of context — what it does, where it lives, why it matters. Just enough to remember what this was about. Related: [B-1], [T-3]
```

The `Related:` suffix is optional — only add it when the feature clearly relates to an existing item (fixes a bug, depends on a todo, extends another feature). Scan `## Bugs`, `## Features`, and `## Todos` in `.hv/TODO.md` and also `.hv/ARCHIVE.md` (if it exists) for obvious connections before writing the entry. Archived items are still valid link targets. Don't force links that aren't there.

Example:
```markdown
- **[F-3] [Minor] Quick-switch between recent projects.** Cmd+Tab-style overlay that shows the 3 most recent projects for fast switching without opening the project picker. Useful for consultants bouncing between clients throughout the day. Related: [B-5]
```

## Rules

- **Never remove or reorder existing entries** — append only
- **Don't write a spec** — write a memory jogger
- **One entry per invocation** — if the user mentions multiple features, add the first and tell them to run `/hv:feature` again for the rest
- **Confirm what you wrote** — show the user the exact line you added
- **Always increment the counter** — even if you're unsure, the ID must be unique
