# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B01] [P1] `/hv-capture` Step 7 auto-dispatches `/hv-brainstorm` on `autonomy=auto`, conflating capture with planning.** Capture should be pure intake; auto-invoking brainstorm pulls the user into design exploration mid-brain-dump. Worse, the escalation is inverted: `auto` proactively brainstorms, `loop` skips entirely. Fix: Step 7 prints the nudge line in all modes (off/auto/loop) and never invokes the Skill tool. Move autonomous advancement to `/hv-next` where "advance without asking" semantics belong. Related: [F01], [F03]
- ~~**[T105] Close pre-existing drift in the hvlib exports sentinel.** ~13 names helpers already import via `from hvlib import …` are missing from `test/sections/44_hvlib_exports.sh` NAMES (bump_hit, load_sidecar, save_tier_sidecar, …); reconcile the list per the file's own maintenance rule. Surfaced by refactor round 6. Detail: `.hv/tasks/T105.md` Since: bf49f02~~ Done 2026-06-11 [`81918ff`]
- ~~**[T108] Refresh stale smoke-section filenames in skill-owned content.** Round 6 renumbered test/sections; `.hv/KNOWLEDGE.md` still references `39_preamble.sh` and `37_migrate.sh` (now `42_`/`39_`) and `.hv/designs/F25.md` references `40_hvlib_exports.sh` (now `44_`). Amend via `hv-knowledge-amend`/the design helpers — not by hand. Related: [T105] Since: bf49f02~~ Done 2026-06-11 [`1ce63fd`]
- ~~**[T106] Decide filterMineOnly semantics: author vs assignee.** `hv-issues-list --mine` passes `--author @me` (authored-by), but pre-round-6 docs described the flag as "assigned to me" — if assignee was the intent, swap to `--assignee @me` in both provider branches of `bin/hv-issues-list` and realign docs. Also: old glab treats `@me` as a literal username and silently returns `[]` — add a doc caveat or version guard. Subsystem: hv-capture Since: bf49f02~~ Done 2026-06-11 [`4a2e075`]
- ~~**[T107] Remove dead `sep` in hvlib_section.append_to_section.** Same dead-code pattern round 6 removed from `replace_section` survives at ~line 93 of `bin/hvlib_section.py` — a `sep` variable is computed but never used; delete it and re-run the section's smoke assertions. Since: bf49f02~~ Done 2026-06-11 [`ded3008`]
