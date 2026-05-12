# Detail files

Used by `/hv-capture` Step 5. Single-consumer extraction — the reference exists for hv-capture's readability. Future skills that capture-then-extract bulky content would cite the same pattern.

When a captured item's raw input is bulky enough to bloat the TODO entry beyond ~3 sentences, the extra content lives in `.hv/<bugs|features|tasks>/<id>.md` and the TODO entry carries a `Detail:` pointer.

## When this fires

If any item's input contains bulky raw data that would push the TODO entry past ~3 sentences — crash dumps, stack traces, log output, specs, checklists, config snippets, long reproduction steps. Skip entirely for items that fit comfortably in 1–3 sentences. Most entries won't need a detail file.

## The detail-file shape

```markdown
# {ID}: Short title

> Related TODO entry: `[{ID}]` in `.hv/BACKLOG.md`

## Summary

{The same 1–3 sentence summary that goes into BACKLOG.md}

## Detail

{Full user input — crash dump, stack trace, logs, specs, checklists, etc. Preserved verbatim or lightly formatted for readability.}
```

## Ordering

1. Get the ID first via `.hv/bin/hv-next-id <bugs|features|tasks>`.
2. Write the detail file at `.hv/<kind>/{ID}.md` using the shape above.
3. Append the TODO entry (hv-capture Step 6) with a `Detail:` reference pointing at the file path.

## The Detail: reference

Appended to the TODO bullet after the summary, before `Related:` / `Milestone:` / `Repos:`. Format:

```
Detail: .hv/<kind>/{ID}.md
```

## What this reference does NOT cover

- **The BACKLOG-entry write itself** — see hv-capture Step 6 inline.
- **Milestone tagging** — see `references/milestone-tagging.md`.
- **Sub-repo tagging** — see hv-capture Step 4.6 inline / `references/umbrella-mode.md`.
