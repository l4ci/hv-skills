# Capturing work

`/hv-capture` records bugs, features, and tasks into `TODO.md` with auto-classification and auto-assigned IDs. Paste a raw description, structured notes, or a mixed list and it sorts the rest out.

## /hv-capture

```
/hv-capture "the sidebar flickers on hover"
```

That single line logs a bug entry:

```markdown
- **[B03] [P2] Sidebar flickers on hover.** ...
```

Each item gets a zero-padded, auto-incrementing ID (`[B##]` for bugs, `[F##]` for features, `[T##]` for tasks). The skill asks a few quick questions to gather context, then assigns:

- **Bugs** — priority `[P0]`, `[P1]`, or `[P2]`
- **Features** — size `[Major]`, `[Minor]`, or `[Cosmetic]`
- **Tasks** — no tag

## Mixed input — bugs, features, and tasks in one message

You don't need to file items one at a time. Describe everything at once and `/hv-capture` splits it into distinct entries routed to the correct section.

Telling `/hv-capture` *"the sidebar flickers on hover, also we should add keyboard shortcuts, and update the linter config"* produces:

```markdown
## Bugs
- **[B03] [P2] Sidebar flickers on hover.** ...

## Features
- **[F04] [Minor] Keyboard shortcuts for top actions.** ...

## Tasks
- **[T06] Update linter config for new rules.** ...
```

Each item gets its own ID type, section, and classification, regardless of how they arrived in a single message. Items created in the same batch can reference each other with `Related:` links.

## Detail files for large input

When an item's input is too large for a TODO entry — crash dumps, specs, logs, long checklists — `/hv-capture` creates a detail file and links to it from the main entry:

```markdown
- **[B07] [P0] App crashes on launch after iOS 18.2 update.** EXC_BAD_ACCESS in CoreData stack during migration. Detail: `.hv/bugs/B07.md` Related: [F12]
```

Detail files land in type-specific subdirectories:

| Type | Directory | Example |
|------|-----------|---------|
| Bug | `.hv/bugs/` | `.hv/bugs/B07.md` |
| Feature | `.hv/features/` | `.hv/features/F08.md` |
| Task | `.hv/tasks/` | `.hv/tasks/T09.md` |

Most entries won't need a detail file — they're only created when the input would bloat the TODO entry beyond a few sentences.

## Related items

Any item can carry a `Related:` suffix linking it to other items:

```markdown
- **[B05] [P1] Timer badge stale after pause.** Description... Related: [F03]
```

Links are optional. `/hv-next` infers the reverse link automatically, so you don't need to add it to both sides. When linked items form clusters, `/hv-next` suggests tackling them together (see [reviewing and picking work](next-and-status.md)).

`/hv-capture` scans both `TODO.md` and `ARCHIVE.md` for connections, so a new bug can link back to a completed feature.

## /hv-c — keystroke-saving alias

`/hv-c` is a shortcut for `/hv-capture`. Identical behavior, fewer characters. Use it when you're capturing frequently and want to stay in flow.

## What /hv-capture is not

`/hv-capture` is a pure recording tool. It classifies and files. It does not act, does not validate the item, and does not deduplicate against existing entries. If you want to implement something immediately after capturing it, use [/hv-go](running-work.md) instead. If you want to pick up an already-filed item and implement it, use [/hv-work](running-work.md).
