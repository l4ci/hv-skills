# Milestone tagging

Used by `/hv-capture` Step 4.5. Single-consumer extraction — the reference exists for hv-capture's readability, not for cross-skill sharing. Future skills that capture-then-tag items would cite the same pattern.

When `/hv-capture` produces new TODO items and there's at least one active milestone, the items get tagged into the active milestone via an `AskUserQuestion` flow.

## Gate

```bash
.hv/bin/hv-vision-active
```

- If the helper prints nothing, no milestones are active — skip this step entirely.
- If exactly one milestone is active, ask the obvious-default question (below).
- If multiple milestones are active, ask the multi-active question (no auto-default).

## One active milestone

- **Header:** `"Milestone"`
- **Question:** *"Tag these items with `<MID> — <title>`?"* (using the active milestone's title from its frontmatter `title:`)
- **Options** (single-select):
  1. *"Yes — tag all (Recommended)"*
  2. *"No — leave untagged"*
  3. *"Different milestone"* (free text — accepts any existing `M\d+`)

## Multiple active milestones

- **Header:** `"Milestone"`
- **Question:** *"Tag these items with which milestone?"*
- **Options** (single-select):
  1. One option per active milestone, labelled `<MID> — <title>` (title from each milestone file's frontmatter; mark the first listed `(Recommended)`)
  2. *"None / unrelated — leave untagged"*
  3. *"Different milestone"* (free text — accepts any existing `M\d+`)

## Caller cap (hv-go speed path)

When the invoking args carry the `(hv-go — cap clarification at 1-2 questions)` prefix:

- With one active milestone: auto-tag without asking — the speed path uses the obvious answer.
- With multiple active milestones: the cap is **exempt for this single question** — silently skipping would orphan items from every milestone view, which is worse than spending one question. Ask the multi-active question above; it counts toward the cap budget, so spend remaining clarification budget carefully (often zero further questions).

## Loop mode

When `autonomy.level == "loop"`:

- With one active milestone: auto-pick *"Yes — tag all (Recommended)"* without invoking AskUserQuestion.
- With multiple active milestones: auto-pick the first-listed milestone (the option marked `(Recommended)`).

Honors the `hv-init` authoring convention "routine routing/tagging auto-picks Recommended in loop mode" — see `references/authoring-conventions.md` rule #5.

## Plain-text fallback

Ask *"Tag with M01?"* once. If the reply is ambiguous, default to leaving the items untagged. Under-tagging is recoverable; mis-tagging clutters the milestone view.

## Outcome

Carry the chosen milestone(s) as a comma-separated list (`"M01"` or `"M01, M03"`) into hv-capture's Step 6 `Milestone:` suffix on the TODO entry. If *"No — leave untagged"* was picked, omit the suffix entirely.

## What this reference does NOT cover

- **Sub-repo tagging (`Repos:`)** — see hv-capture Step 4.6 inline / `references/umbrella-mode.md` for the registry context.
- **Detail-file extraction for bulky items** — see `references/detail-files.md`.
- **The TODO-entry write itself** — see hv-capture Step 6 inline.
