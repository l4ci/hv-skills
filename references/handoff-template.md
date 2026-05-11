# Handoff note template

Used by `/hv-pause` (writes the note) and `/hv-next` (reads it). Both skills point here so the template lives in one place.

Fill each section from the current session — omit sections that don't apply, but don't manufacture content. The four sections below are exactly what `/hv-next` consumes; anything else (commit log, files mid-edit, gotchas, dead ends) belongs elsewhere (`git log`, `git status`, `/hv-learn`).

## Template

```markdown
# Handoff — <branch>

<!-- Paused YYYY-MM-DD HH:MM UTC -->

## Working on

- **Repo:** web                              <!-- omit when single-repo / no umbrella scope -->
- **Items:** [B07], [F03]
- **Milestone:** M01 — Auth foundation  <!-- omit if no active milestone or items aren't tagged -->
- **Stage:** <e.g., "mid-hypothesis verification for B07", "implementing wave 2 of 3">

## Next planned step

<one or two sentences — the concrete action /hv-next should dispatch. Not a summary; a directive.>

## Current hypothesis (if debugging)

<the causal claim under test, with the verification probe that was about to run>

## Uncommitted work

<one of: "clean tree" / "stashed as `stash@{0}` — message: hv-pause <branch>" / "wip commit `a1b2c3d`" / "dirty tree — see `git status`">
```
