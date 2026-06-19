# TODO

## Bugs

## Features

## Tasks
- **[T109] hv-knowledge-query silently returns empty on partial topic names.** Topic args must be the exact `## ` heading; a partial/mistyped name returns empty with exit 0, indistinguishable from 'no learnings exist'. Substring-match or warn/exit non-zero instead. Detail: `.hv/tasks/T109.md` GH: #16 Subsystem: knowledge Since: 85620c6
- **[T110] No amend helper exists for design artifacts.** .hv/designs/*.md only has add/show/rm/list (hv-design-add refuses on existing files), so 'amend via helpers' cannot be honored for designs. Add a design-amend verb or a generic hv-artifact-amend lib. Detail: `.hv/tasks/T110.md` GH: #17 Since: 85620c6
- **[T111] hv-knowledge-hit races on knowledge-tier.json.tmp under parallel batching.** Concurrent calls race on the shared .tmp rename (FileNotFoundError), yet /hv-work Step 4 suggests a parallel batch. Make it parallel-safe (per-process tmp name or file lock) or fix the skill text. Detail: `.hv/tasks/T111.md` GH: #18 Related: [T109] Since: 85620c6
- **[T112] Backlog drift detection misses items shipped without the [ID] in the commit.** Items captured from a code snapshot (Since: <hash>) get silently shipped by later refactor commits lacking the [ID]; drift only matches IDs in commit messages. Detect when the described change already exists in the tree (symbol-level grep of named identifiers). Detail: `.hv/tasks/T112.md` GH: #19

## Completed
- ~~**[B01] [P1] `/hv-capture` Step 7 auto-dispatches `/hv-brainstorm` on `autonomy=auto`, conflating capture with planning.** Capture should be pure intake; auto-invoking brainstorm pulls the user into design exploration mid-brain-dump. Worse, the escalation is inverted: `auto` proactively brainstorms, `loop` skips entirely. Fix: Step 7 prints the nudge line in all modes (off/auto/loop) and never invokes the Skill tool. Move autonomous advancement to `/hv-next` where "advance without asking" semantics belong. Related: [F01], [F03]
- ~~**[T105] Close pre-existing drift in the hvlib exports sentinel.** ~13 names helpers already import via `from hvlib import …` are missing from `test/sections/44_hvlib_exports.sh` NAMES (bump_hit, load_sidecar, save_tier_sidecar, …); reconcile the list per the file's own maintenance rule. Surfaced by refactor round 6. Detail: `.hv/tasks/T105.md` Since: bf49f02~~ Done 2026-06-11 [`81918ff`]
- ~~**[T108] Refresh stale smoke-section filenames in skill-owned content.** Round 6 renumbered test/sections; `.hv/KNOWLEDGE.md` still references `39_preamble.sh` and `37_migrate.sh` (now `42_`/`39_`) and `.hv/designs/F25.md` references `40_hvlib_exports.sh` (now `44_`). Amend via `hv-knowledge-amend`/the design helpers — not by hand. Related: [T105] Since: bf49f02~~ Done 2026-06-11 [`1ce63fd`]
- ~~**[T106] Decide filterMineOnly semantics: author vs assignee.** `hv-issues-list --mine` passes `--author @me` (authored-by), but pre-round-6 docs described the flag as "assigned to me" — if assignee was the intent, swap to `--assignee @me` in both provider branches of `bin/hv-issues-list` and realign docs. Also: old glab treats `@me` as a literal username and silently returns `[]` — add a doc caveat or version guard. Subsystem: hv-capture Since: bf49f02~~ Done 2026-06-11 [`4a2e075`]
- ~~**[T107] Remove dead `sep` in hvlib_section.append_to_section.** Same dead-code pattern round 6 removed from `replace_section` survives at ~line 93 of `bin/hvlib_section.py` — a `sep` variable is computed but never used; delete it and re-run the section's smoke assertions. Since: bf49f02~~ Done 2026-06-11 [`ded3008`]
