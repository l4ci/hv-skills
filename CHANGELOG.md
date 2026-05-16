# Changelog

## v4.0.0 — unreleased

**The Loop, simplified.** Breaking removal of `/hv-context` plus seven other skills folded into composite surfaces (full announcement lands with M01's marketing pass — F20). This stub captures the F18 fold; subsequent F19/F21/F22 commits will extend the v4.0 entry as they ship.

## Breaking

- **`/hv-context` removed.** The skill is folded into `/hv-learn --term <name>` ([F18]). Domain terms now live as nested-bullet entries under a pinned `## Glossary` topic in `.hv/KNOWLEDGE.md` instead of a separate `.hv/CONTEXT.md` file. The capture surface — `--def`, `--alias`, `--not`, `--touch` — is preserved on the flag. Existing projects use `/hv-migrate v4` ([F19], in progress) to port `.hv/CONTEXT.md` into the new Glossary topic; new projects start with the pinned topic via `/hv-init`. Helpers renamed: `bin/hv-context-add → bin/hv-glossary-write`, `bin/hv-context-query → bin/hv-glossary-read`. Removed: `bin/hv-context-index`, `bin/hv-context-map`, `hv-context/` skill folder, the `<!-- hv-context-start -->` block in `CLAUDE.md`. Umbrella-mode per-sub-repo Glossary is deferred to F21.

## New

- **`/hv-learn --term <name>`** ([F18]) — captures a domain term into the `## Glossary` topic of `.hv/KNOWLEDGE.md` with the same flag shape the old `/hv-context` used. Conflict-gated: refuses on alias collision with another term in the Glossary.
- **`hv-glossary-write --batch <manifest>`** ([F18 T9]) — atomic multi-term import from a tab-separated manifest (`term \t def \t aliases \t nots`). The whole batch is validated against existing entries AND intra-batch uniqueness before any write; on alias collision the entire batch is refused (exit 3) with a multi-line conflict summary. F19's codemod consumes this.
- **Pinned `## Glossary` topic in fresh `KNOWLEDGE.md`** ([F18 T3]) — `bin/hv-bootstrap` writes the topic header on `/hv-init` so single-repo projects start with a Glossary destination.

## Stats

Pending — F19/F20/F21/F22 still to ship.

## v3.4.0 — 2026-05-15

Skill audit pass — checklist gate keeps version-file drift from sneaking past releases, plus seven skill descriptions get explicit triggers and the macOS smoke flake is fixed.

## New

- **Per-project release checklist gate at Step 1.5** of `/hv-release` (`fe15afc`). Walks `.hv/RELEASE.md` (override via `release.checklistPath`) — each `- [ ]` line is a gate the skill asks about before bumping the version. Items ending in `(manual)` always interject even under `autonomy.level: auto`/`loop`. Designed to catch drift like the `marketplace.json` version gap surfaced by the audit — by adding an item, not by patching the skill.

## Fixed

- Stale `/hv-resume` reference in `hv-pause/SKILL.md` (folded into `/hv-next` back in v2.1.0 / F26), `marketplace.json` versions stuck at `2.0.0` while `plugin.json` was `3.3.0`, and five skill descriptions (`hv-learn`, `hv-capture`, `hv-qa`, `hv-rm`, `hv-undo`) that lacked explicit "Use when..." trigger phrasing for the Skills router (`22940d3`).
- Two pre-existing smoke flakes (`98e6b2c`): macOS `$TMP` from `mktemp -d` returning `/var/folders/...` while helpers using `pwd -P` returned `/private/var/folders/...` (broke section 15 walk-up); and section 21's `set -e + pipefail` silently killing the runner when a grep matched nothing instead of reaching the `|| fail` diagnostic. The second fix surfaced unrelated `[F32]` drift — `bin/hv-auto-decisions-since` exists but no skill invokes it; tracked separately.

## Changed

- `CLAUDE.md` template grew an `hv-qa` managed block from the rollout in `v3.3.0` (`bed82d8`).

## Documentation

- `docs/usage/configuration.md` gained a `release.checklistPath` section, `docs/usage/review-and-ship.md` gained a "Release checklist" section, and `docs/reference/slash-commands.md`'s `/hv-release` description picked up the gate (`e9e6131`).

## Stats

5 commits, 14 files changed, +125 −19 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v3.3.0...v3.4.0

## v3.3.0 — 2026-05-15

**hv-qa: product-level QA gate, plus user-guide catch-up on F02–F08.**

## New

- add /hv-qa skill for product-level testing (qa) (`5a250db`)

## Fixed

- hvlib resolve_plugin_root validates CLAUDE_PLUGIN_ROOT name [B05] (bin) (`b521f7e`)
- cross-platform mtime in 01_status.sh (test) (`7125c52`)
- hv-todo-field accepts 'title' field [B04] (bin) (`d1c0572`)

## Changed

- humanizer pass — strip AI-flavored tells from fresh sections (docs) (`06d2eab`)
- route hv-status-remove through hv-resolve-handoff, refresh references README (`c4263ef`)
- consolidate boilerplate citations, document missing helpers, add hv-map banner (`13fd598`)
- single source of truth for TODO field names in hvlib (`bd89910`)

## Documentation

- sync user guide with /hv-qa rollout + F02/F03/F04/F07/F08 (`a90896c`)

## Stats

9 commits, 48 files changed, +849 −109 lines

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v3.2.0...v3.3.0

## v3.2.0 — 2026-05-15

**v3.2.0 — Knowledge promotion lifecycle, two-stage review, debug Iron Law**

## New

- **Knowledge promotion lifecycle ([F03]).** Bullets now carry tier sidecars (provisional → confirmed via hit-count threshold, configurable via `learn.promoteThreshold`). New helpers: `hv-knowledge-tier`, `hv-knowledge-hit`, `hv-knowledge-migrate`, `hv-knowledge-merge` (sidecar-init), `hv-knowledge-query` (tier-aware), `hv-knowledge-contradiction` (pending-demotion queue). `/hv-learn` gained manual flags + contradiction queue; `/hv-work` and `/hv-review` track hits on consumed bullets.
- **Two-stage `/hv-review` ([F07] + [F08]).** Spec-compliance pass first, then code-quality pass. `silent-failure-hunter` rubric added to `/hv-review` and `/hv-ship`.
- **Second-opinion gate before merge in `/hv-ship` ([F04]).**
- **Iron Law hard stop in `/hv-debug` ([F02]).** `/hv-debug` now bails after 3 failed fixes via the new `hv-debug-counter` helper.
- **Static SKILL.md validator + GitHub Actions workflow ([F06]).**
- **Manual `/hv-docs` routes to after-work flow ([F09]).** Re-invoking `/hv-docs` when docs exist and `docs.afterWork` is on now checks docs against recent changes instead of no-op'ing. Step A1 trigger gate is bypassed on manual entry.

## Fixed

- Sweep `&` from `TaskCreate` payloads and codify the rule ([T01]).
- Case-insensitive grep for fresh-context framing in smoke ([F04]).
- `/hv-capture` brainstorm nudge: always nudge, never auto-dispatch ([B01]).

## Changed

- Cleaned review/ship surface friction post-F04/F07/F08.
- Indexed `Architecture` and `Build & Tooling` topics in CLAUDE.md.
- Removed obsolete `docs/superpowers/` plans and specs.

## Documentation

- Restructured README around five lanes; split install + architecture into own pages.
- Added hv-skills logo to header.

## Stats

30 commits, 46 files changed, +2381 −7082 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v3.1.0...v3.2.0

## v3.1.0 — 2026-05-13

Adds `/hv-undo` for guided rollback of the last `/hv-work` cycle, `/hv-issues` for syncing GitHub/GitLab issues into `BACKLOG.md` with round-trip closing, and the `--auto-loop` dispatch chain that runs Major + Milestone-tagged items autonomously through brainstorm → plan → work in loop mode.

## New

**`/hv-undo` — guided cycle rollback.** Resets the last `/hv-work` merge commit on the base branch and restores TODO entries via the new `hv-uncomplete` helper. Direct-merge cycles only (MVP); refuses on cycles with post-merge commits unless `--allow-post-merge` is passed. Dry-run preview by default; the slash command always asks before applying.

**`/hv-issues` — pull upstream issues into BACKLOG.md.** Lists open GitHub or GitLab issues via a multiSelect picker, mints IDs, writes detail files, and appends entries carrying `GH: #N` or `GL: #N` cross-references. Five new helpers back the flow: `hv-issues-provider` (detect host), `hv-issues-list` (read), `hv-issues-imported` (dedupe), `hv-issues-label` (manual-gated `in-progress` upstream), `hv-issues-close` (round-trip closing).
- `/hv-ship` auto-closes upstream issues on PR merge (`Closes #N` in body) and direct-push (manual gate).
- `/hv-rm` de-tags the upstream label before removing an imported item (manual gate).

**`--auto-loop` dispatch chain.** `/hv-brainstorm --auto-loop` and `/hv-work` Step 2/4 now wire together so loop-mode automation runs Major + Milestone-tagged items through research → plan → work without user gates between phases. `/hv-next` defers its design-nudge to the chain instead of interrupting it.

**F75 self-prompting hardening.** Promoted five sets of authoring rules from `KNOWLEDGE.md` into canonical inline references across `/hv-work` (7 worker/parallelism gotchas), `/hv-plan` (3 plan-author gotchas), `/hv-learn` (`KNOWLEDGE.md` bullet schema), `/hv-init` (5 authoring conventions), and `/hv-decide` (source-prefill semantic-gap principle).

## Changed

- Executable mode set on the new `hv-undo` / `hv-uncomplete` helpers.
- `CLAUDE.md` `hv-decisions` managed block refreshed (Documentation topic added).

## Documentation

- README slim-down + two new walkthroughs (`docs/walkthroughs/{greenfield,brownfield}-*.md`) + `docs/how-it-works.md` for the system mermaid + humanizer pass across all docs.
- User guide for `/hv-undo`; skill table and index entries refreshed.
- `--auto-loop` chain reflected in usage docs and the loop-dispatch reference.
- `/hv-issues` user reference, README entry, and manual-gates inventory.

## Stats

32 commits, 61 files changed, +3518 −506 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v3.0.0...v3.1.0

## Unreleased

## v3.0.0 — 2026-05-12

v3.0.0 reorganizes runtime data files: TODO.md → BACKLOG.md and the MILESTONES.md heading flips to `# Milestones`. Both auto-migrate on `/hv-init`; downstream users re-run init and continue. Also: subagent dispatch discipline gets a rulebook, /hv-init shows installed version on startup, /hv-next surfaces empty active milestones, and docs gain stateDiagram / flowchart / sequence visualizations.

## Breaking

- **Renamed `.hv/TODO.md` → `.hv/BACKLOG.md`** [F71]. The file holds typed work items plus recent completions across an entire project — it's a backlog, not a personal todo list. Helpers, smoke, SKILL.md files, and docs all flip in lockstep.

  **Migration for end-users:** re-run `/hv-init` in any existing project. `hv-bootstrap` auto-renames legacy `.hv/TODO.md` → `.hv/BACKLOG.md` on first run (idempotent — exit 0 on rename action OR no-op). A one-cycle reader fallback in `bin/hvlib.py` keeps projects working until they re-init; the fallback is silent and intended for removal in the next release.

- **MILESTONES.md H1 is now `# Milestones`** [F72]. Filename, sibling directory `.hv/milestones/`, and the file's H1 now all align on "milestones"; the vision paragraph is the file's intro preamble, not its primary content. Helpers, smoke fixtures, SKILL.md prose, and docs all flip in lockstep.

  **Migration for end-users:** re-run `/hv-init` in any existing project. `hv-bootstrap` auto-rewrites `# Vision` H1s to `# Milestones` on first run, preserving body content byte-for-byte; idempotent on re-run.

## New

- **Subagent dispatch discipline** [F73] — `/hv-next` Step 2–6 reads dispatch as a parallel worker wave; `/hv-vision` dispatches context-bundle + research workers; `/hv-debug` conditionally dispatches reproduce (Step 5) + verify (Step 7) workers. Authoring rulebook added under `references/subagent-dispatch.md`. Reduces orchestrator-side read pressure on cycle entry.
- **`/hv-init` Step 5 shows installed version + freshness hint** [F70] — Reuses `hv-update-check`'s plugin-cache resolution to print the version string at init time so users see what shipped.
- **`/hv-next` surfaces empty active milestones** [B25] — When an active milestone has zero captured items, the skill flags it inline instead of silently falling through to the general backlog. New helper `bin/hv-vision-empty-active` lists empty active milestone IDs.
- **`hv-bootstrap` seeds MILESTONES.md with `# Milestones` H1 + in-place migration** [F72/T1] — the implementation backing the breaking change above.

## Fixed

- `/hv-c` suppresses its own banner so only `/hv-capture`'s shows [T72]
- Smoke staleness fixture lives under `## Tasks` with canonical bullet [B27]
- `parse_todo_fields` fixture includes the `Captured` field [B26]

## Changed

- **Reference-extraction sweep** [T65] — `/hv-work` Step 4 loop-mode plan-dispatch, Step 5 isolation-guard rationale, `/hv-debug` Step 6 hypothesize + Step 7.5 escalate, `/hv-refactor` Step 2 exploration + Step 5 competing-design — moved to shared `references/<topic>.md` files; SKILL.md files shrink in lockstep.
- Bundled cleanup post-F71 (5 follow-up items)
- `bin/hv-vision-empty-active` marked executable [B25]
- `.claude/` harness state directory is gitignored

## Documentation

- **Lifecycle diagrams** [F74] — stateDiagram of session lifecycle, flowchart of `/hv-next` decision flow, sequence diagram of `/hv-work` lifecycle.
- Reframe MILESTONES.md prose as the milestone overview with vision intro paragraph [F72/T3]
- CLAUDE.md note on smoke cadence — full suite at ship/review, structural checks per task
- Subagent-dispatch discipline plan + spec [F73]
- /hv-init Step 5 reuse-of-hv-update-check note [F70]
- cli-helpers + vision usage cover `hv-vision-empty-active` [B25]
- List `/hv-brainstorm` under "Plan & build" (CLAUDE.md skills block)

## Stats

39 commits, 86 files changed, +1660 −414 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v2.3.1...v3.0.0

## v2.3.1 — 2026-05-12

Patch fix restoring /hv-brainstorm and /hv-context slash commands missing from v2.3.0's plugin manifest.

## Fixed

- Register `hv-brainstorm` and `hv-context` in `.claude-plugin/plugin.json` — both shipped in v2.3.0 with `SKILL.md` present on disk but unregistered, so Claude Code never loaded the slash commands. Also adds `/hv-brainstorm` to the canonical `bin/hv-skills-index` heredoc body, and re-syncs `CLAUDE.md` managed blocks (the stale skills block still referenced retired `/hv-status` + `/hv-resume`; map and context blocks were absent). (`4a21ee0`)

## Documentation

- README workflow diagram updated to include `/hv-brainstorm`, `/hv-context`, and `/hv-map`. (`ad6e148`)

## Stats

2 commits, 4 files changed, +38 −4 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v2.3.0...v2.3.1

## v2.3.0 — 2026-05-12

New skill `/hv-brainstorm` for per-item design exploration, plus a sweep of helper classification headers across the `bin/` surface.

## Highlights

- **New skill: `/hv-brainstorm`** — Socratic per-item design exploration before `/hv-plan`. Walks the user through 2-3 approaches with tradeoffs, builds a sectioned design artifact at `.hv/designs/<ID>.md`, hands off to `/hv-plan` as soft input. `/hv-capture` and `/hv-next` nudge for `[Major]` features and `[P0]` bugs without an existing design. `/hv-go` and loop autonomy intentionally skip brainstorm (speed-path / throughput). [F67]
- **4 new helpers** under `bin/hv-design-*` (add / show / rm / list) — siblings of `hv-plan-*` adapted for the simpler per-item artifact path.
- **Shared design-exploration reference** at `references/design-exploration.md` — extracts the Socratic + 2-3-approaches + sectioned-design choreography used by both `/hv-vision` (project scope) and `/hv-brainstorm` (item scope), with a 10-axis divergence table that prevents future "fix" attempts on intentional scope differences.

## Changed

- **Helper classification-header sweep** — 72 `bin/` helpers gained explicit Writer / Resolve / Lookup / Validator / Atomic-merge classification lines per the 2026-05-12 mutator-helpers decision. Lookups [T71a, 17], Writers [T71b, 19], Resolve+Validator+Atomic-merge [T71c, 17], Tool helpers [T71d, 19]. Clears the case-by-case ambiguity on exit-code semantics.
- **AskUserQuestion pattern audit across hv-* skills** [T63] — fixed over-4-option lists and missing plain-text fallbacks.
- **Plugin-source resolver centralization** [T66, T70] — `hv-preflight` and other drift-checking helpers now use the canonical `hv-resolve-plugin-root`; classification labels harmonized.
- **Milestone parsing centralized in `bin/hvlib.py`** — deduped upsert + restored `hv-staleness` handling.
- **`/hv-plan` reads design artifacts** [F67-T2] — `hv-plan-add --design <path>` flag; plan frontmatter carries the design pointer for traceability.

## Fixed

- **`hv-init` plugin-source resolver** [T69] — replaced `ls | sort | tail` with a glob loop to handle non-numeric directory names safely.

## Documentation

- **`/hv-brainstorm` user guide** at `docs/usage/brainstorm.md`; helper rows in `docs/reference/cli-helpers.md`; README features cell + skills row.

## Stats

16 commits · 97 files · +860 / −126 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v2.2.0...v2.3.0

## v2.2.0 — 2026-05-12

Loop-mode improvements, smoke-test conventions, and a sweep of skill-prose hygiene — `/hv-config` gains a positional-args shortcut, `/hv-init` consolidates its greenfield prompts, and a `## References` index lands on every SKILL.md alongside a new `references/README.md`.

## New

- smoke section asserts bin/ executable mode is 100755 [F66] (test) (`c7f0f38`)
- smoke section detects SKILL.md vs helper docstring drift [F65] (test) (`c44abb9`)
- preamble convention scan in test/lib.sh [F62] (test) (`f1c0a3c`)
- combine Step 1 + 1.5 into one AUQ for non-git umbrella greenfield [F58] (hv-init) (`d7266bc`)
- add README.md index mapping references to consumers [F61] (references) (`acfe2f0`)
- add ## References index section to every SKILL.md [F59] (skills) (`36ac537`)
- positional-args shortcut for one-key edits [F57] (hv-config) (`cd96acb`)
- tombstone consumed item plans at Step 9.5 [F54] (hv-work) (`11afbb5`)
- cycle-counter + Step 7.5 fresh-context retry hand-off [F56] (hv-debug) (`d7716f0`)
- walk up from cwd before BASH_SOURCE[1] [F42] (self-locate) (`648b1cc`)
- execute project CI-shape gates in Step 7 verifier [B21] (refactor) (`d7df0ba`)
- auto-split oversized KNOWLEDGE.md topics in auto/loop mode [F52] (hv-learn) (`6d62267`)

## Fixed

- hv-preflight cache-fallback glob loop instead of pipeline [B24] (`4e8fa7e`)
- hv-preflight compares against upstream plugin bin/ to detect drift [B24] (`9bbee52`)
- section 01 must not shadow runner-level $TMP [B22] (smoke) (`d2b4834`)
- tailored greenfield message points at baseline commit [B20] (guard) (`7a726ba`)
- name hv-multi-branch-create in SKILL.md [B18] (hv-work) (`db41d31`)

## Changed

- split oversize topics into faceted sub-topics [B23] (knowledge) (`b6bed2e`)

## Documentation

- note auto-tombstone of item plans after /hv-work [F54] (plans) (`11955df`)
- name vertical slicing as a Step 4 rule [F53] (hv-plan) (`8f9e724`)
- document Step 7.5 escalation [F56] (hv-debug) (`8fe5d8a`)
- refresh hv-skills slash-command index (claude-md) (`ff014e2`)

## Stats

23 commits, 47 files changed, +747 −114 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v2.1.0...v2.2.0

## v2.1.0 — 2026-05-11

A substantial release bundling the never-tagged v2.0.0 work (breaking removal of `/hv-status` + `/hv-resume`) with major new features — `/hv-context` (project domain glossary), `/hv-map` (subsystem index for context-scaling), loop-mode auto-picks, TaskCreate progress checklists across 17 skills, and a large references/ extraction sweep.

## Breaking

- **`/hv-status` and `/hv-resume` removed — folded into `/hv-next`** ([F26]). Run `/hv-next` for backlog review + handoff detection in one command. CHANGELOG had a `v2.0.0` section for this work but no tag was ever cut; it ships in `v2.1.0`.

## New

- **`/hv-context` — project-level domain glossary** ([F38]) — capture and refine terms in `.hv/CONTEXT.md`, with umbrella support across sub-repos. Skill consulted from `/hv-vision`, `/hv-work`, `/hv-debug`, `/hv-capture`. New `hv-context-*` helpers (`add`, `index`, `query`, `map`) and scaffolding via `/hv-init`.
- **`/hv-map` — subsystem index for context-scaling** — `.hv/MAP.md` + `.hv/map/` per-subsystem files with first-run, after-work, and consolidate modes. Auto-invoked from `/hv-work`, `/hv-debug`, `/hv-go`. Includes `hv-map-index`, `hv-map-query`, `hv-map-stats` helpers and stale-entry detection.
- **`/hv-rm` — backlog item removal** ([F36]) — slash command + `bin/hv-rm` helper for clean TODO removal with handoff-note sweep.
- **`/hv-plan --auto-loop` mode** ([F32]) — auto-planning for loop sessions, with `[Auto:Loop]` decision surfacing on terminal paths and a `hv-loop-stamp` tracker.
- **Loop-mode auto-picks across skills** ([F33]) — `/hv-refactor`, `/hv-ship`, `/hv-next`, `/hv-capture` auto-pick the Recommended option in loop mode; codified as an `/hv-init` authoring convention.
- **TaskCreate progress checklists in 17 skills** ([F37]) — visible per-phase progress for `/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-release`, `/hv-docs`, `/hv-refactor`, `/hv-learn`, `/hv-decide`, `/hv-spike`, `/hv-vision`, `/hv-capture`, `/hv-next`, `/hv-pause`, `/hv-review`, `/hv-plan`, `/hv-config`, `/hv-rm`; plus the convention itself in `/hv-init`.
- **Helper extraction sweep** ([F44]–[F50]) — inline shell replaced with dedicated `bin/` helpers: `hv-knowledge-merge`/`amend`, `hv-plan-rename-check`, `hv-find-milestone-for-items`, `hv-config-set`, `hv-guard-feature-branch`, `hv-resolve-handoff`, `hv-stale-summary`.
- **`/hv-work` rename + link-sweep collision detection at plan time** ([F27]).
- **`/hv-decide` source-prefill modes — `--from-learning`, `--from-spike`** ([F22]).
- **`/hv-learn` nudges `/runlog-author` for external-dep learnings** ([F21]).
- **`/hv-spike` nudges `/hv-decide` on viable / not-viable finish** ([F20]).
- **Backlog `--grep <pattern>` filter** ([F25]).
- **Release-flow polish** ([F17] [F19] [F23]) — release-pending nudge in post-ship + terminal paths, large-push gate, `docs.afterWork` hook, autonomy-aware `/hv-init` handoff after plugin upgrade, version-drift nudge in preflight.
- **Pre-flight scaffolding scan for stale `Task-N` comments** ([T25]).
- **Three-gate pre-write trigger for `/hv-decide`** ([F39]).
- **Structural-triple uncertainty heuristic + `/hv-assume` pre-flight in loop-mode auto-plan dispatch** ([F34]).

## Fixed

- `/hv-rm` phase-list Step references aligned with body ([B17]).
- `hv-umbrella-on` detects umbrella from `repos.json` instead of config flag ([B15]).
- `/hv-next` frontmatter triggers aligned with banner ([B14]).
- Handoff note swept on remove ([B13]).
- Plugin-path resolver finds Claude Code cache layout ([B12]).
- Cross-file alias collision scan for companion `CONTEXT.md` ([F43]).
- Multiple `[F38]` polish fixes — umbrella detection, sub-repo resolve, abbreviation periods preserved at sentence cut, spec entry shape, empty placeholder strip.
- `hv-staleness` uses `>=` so `--days 0` lists all entries.

## Changed

- **References extraction sweep** ([T19] [T28]–[T60]) — substantial prose moved from SKILL.md files into `references/` and `docs/reference/`: umbrella mode, isolation patterns, authoring conventions, config options, context-load protocol, knowledge-consult, manual gates, review-verdict routing, merge-strategy gate, banner preamble, ask-user-question fallback, persistence-trio spine, three-mode skill shape, detail files, milestone tagging, handoff template, source prefill, release hosts, update verdicts, observable outcomes, TaskCreate convention, plus iterate-loop and silence-fallback semantics. SKILL.md files now cite these references instead of repeating prose.
- **`hvlib` consolidation + cap-check helper** — multiple architectural-improvement rollups consolidating pure-function helpers in `hvlib`.
- **Smoke test split into runner + per-section files** ([T24]).
- **Strict `--repo` extraction in 7 multi-flag helpers** ([F29]).
- **`hv-resolve-umbrella` and `hv-self-locate.sh` delegate walk-up to `hv-walk-up`** ([F30]).
- Various executable-bit fixes for new helpers in tracked mode.

## Documentation

- User-facing docs sweep — `/hv-context` usage + reference, `/hv-rm` usage page, autonomy loop-mode docs, F37 progress-checklist visibility notes, F35 orchestrator-model contract, CHANGELOG 2.0.0 breaking-removal section.
- Numeric cutoffs replace vague adjectives across skills ([T52]).
- Vague exploration prompts in `/hv-refactor` replaced with prioritization + stop condition ([T53]).
- Iterate-loop semantics defined for `/hv-plan` Step 5 ([T54]).
- Silence fallback defined for `/hv-spike` verbal-summary step ([T55]).

## Stats

267 commits, 177 files changed, +15688 −4275 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.16.0...v2.1.0

## v2.0.0 — 2026-05-08

Hard-merge of `/hv-status` and `/hv-resume` into `/hv-next`. Single state-view entry point.

## Breaking

- `/hv-status` and `/hv-resume` are removed in favor of `/hv-next`. `/hv-next` now reads `/hv-pause` handoff notes for active streams and surfaces `Stage` / `Next planned step` / `Current hypothesis` inline alongside each stream — replacing the post-`/clear` `/hv-resume` flow. The lightweight glance from `/hv-status` is no longer offered as a separate command. Update muscle memory: anywhere you typed `/hv-status` or `/hv-resume`, type `/hv-next` instead. [F26]

## Changed

- `bin/hv-skills-index` heredoc body drops `/hv-status` and `/hv-resume` from the "Capture & pick" group. Existing projects must re-run `/hv-init` to refresh the managed `<!-- hv-skills-start -->` block in `CLAUDE.md`. [F26]
- `docs/usage/next-and-status.md` is renamed to `docs/usage/picking-work.md` and rewritten to reflect the one-command world. [F26]

## Removed

- `hv-status/SKILL.md` and the `hv-status/` folder. [F26]
- `hv-resume/SKILL.md` and the `hv-resume/` folder. [F26]

## v1.16.0 — 2026-05-08

Knowledge-loop intelligence (stats + upstream-issue suggestion), `/hv-docs` after-work hook, and a 4-round architectural refactor centered on a sourceable umbrella resolver.

## New

- wire `/hv-docs` after-work into `/hv-work` + `/hv-ship` behind `docs.afterWork` gate [F15] (`ef938f8`)
- `/hv-learn` suggests filing an upstream `hv-skills` issue when a learning surfaces a tool gap [F14] (`754b3de`)
- `hv-knowledge-stats` + fat-topic nudge in `/hv-learn` [F13] (`3bfd8fe`)
- write-only workers + orchestrator-side commits as `/hv-work`'s default [F11] (`b6bb138`)
- `hv-reconcile` scans commit history for TODO.md drift [F09] (`84a2c3c`)
- `hv-self-locate.sh` — sourceable umbrella resolver, threaded through 25 state-only helpers [F10] (`5762b68`, `d16372b`)
- umbrella-aware cwd guards on `hv-base-branch` / `hv-merge` / `hv-pr` / `hv-ship-body` / `hv-review-scope` [B02] (`e6fd4f6`)
- `hv-ship-body` emits `Closes #N` from GH refs in TODO bodies [F12] (`d253140`)

## Fixed

- `hv-vision-index` counts only planned milestones in the elif body [B10] (`f8c39bc`)
- `/hv-config` Step 3 picklist chunked into category + key stages [B11] (`4764342`)
- `/hv-init` umbrella plain-text fallback now defaults to No, not Yes [T11] (`8ee7b7b`)
- `chmod +x` in the git index for 9 helpers that were tracked as 100644 [B09] (`fc47e87`)
- `hv-reconcile` tolerates upfront `hv-base-branch` failure [B02] (`c693ef5`)
- `hv-complete` recognises scoped `refactor(scope):` subjects [B04] (`f8bcd47`)
- `hv-next-id` self-heals against TODO / ARCHIVE drift [B03] (`5340bdd`)

## Changed

Four-round architectural refactor (`hv-refactor` rounds 1-4 + post-F11 alignment): tightened helper boundaries, removed redundant cwd assumptions, collapsed duplicated logic, and synced surrounding skills.

- 5 + 4 + 6 + 8 architectural improvements across rounds 1-4 (`39e2e77`, `984c717`, `bb51256`, `b4d6a87`)
- 3 architectural alignments after F11 [post-merge] (`7611eaf`)
- `.hv/DECISIONS.md` cleared + redundant `KNOWLEDGE.md` entries swept (`0a3f76c`)
- CLAUDE.md vision block refreshed after M03 shipped (`f35c11e`)

## Documentation

- post-round-4 sync (worktree-path helper, `reconcile noBase`, smoke count) (`a2413e5`)
- inline cross-project rules from `.hv/` into SKILL.md prose [T12][T13][T14][T15][T16] (`6c50ec5`)
- codify opt-in-flag rule in `hv-init` + `hv-config` SKILL.md (`10287e7`)

## Stats

26 commits, 72 files changed, +1781 −535 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.15.1...v1.16.0

## v1.15.1 — 2026-05-05

Umbrella-aware tooling fixes — hv-guard-clean / hv-spike-add now handle umbrella-cwd properly, and hv-preflight no longer false-positive-flags sourced shell libraries on every release run.

## Fixed

- treat sourced shell libs as files, not executables (hv-preflight) (`007a473`)
- umbrella-aware tooling for hv-guard-clean and hv-spike-add (bin) (`322cc0d`)

## Stats

2 commits, 3 files changed, +100 −10 lines

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.15.0...v1.15.1

## v1.15.0 — 2026-05-03

Multi-repo dispatch lands as one cohesive feature surface across 6 helpers and 4 skills, with `/hv-pause` now treating multi-repo waves as one logical handoff and a small refactor consolidating Repos: CSV validation.

## New

- **Multi-repo dispatch foundation (M03-S01).** A single backlog item with `Repos: a, b` now produces commits on `hv/<branch>` in every named sub-repo via one `/hv-work` invocation. Adds four new helpers (`hv-resolve-repos`, `hv-multi-branch-create`, `hv-status-add-multi`, plus `hvlib.parse_repos_csv`) and threads the multi-repo list through `hv-capture`, `hv-plan`, `hv-assume`, and `hv-work`. Single-repo path stays byte-identical.
- `hv-pause` treats multi-repo waves as one logical pause set — no per-repo `AskUserQuestion`; one handoff file per `(branch, repo)`; combined wave confirmation. `cd` into a sub-repo to scope the pause to that one entry. ([F08], `7f5c242`)

## Changed

- consolidate Repos: CSV validation into hvlib (`192ff27`)
- mark M01/M02 shipped, activate M03 (`8914492`)

## Documentation

- humanize README and docs/ prose (`17c3979`)

## Stats

10 commits, 33 files changed, +703 −263 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.14.0...v1.15.0

## v1.14.0 — 2026-05-03

**Umbrella mode V1 (M02) substantively shipped: every read-side helper, plus `/hv-plan`, `/hv-spike`, `/hv-pause`, `/hv-assume`, `/hv-refactor` now route work to the resolved sub-repo. Single-repo behavior is unchanged.**

## New

Closes the M02 follow-up wave so the umbrella surface lands end-to-end across plan, spike, pause/resume, assume, and refactor. Items can carry a `Repos:` tag to route work to a registered sub-repo; helpers gain `--repo <name>` for direct calls.

- `/hv-refactor` umbrella-aware fanout: asks which scope (all sub-repos, all + umbrella, umbrella only, subset) and dispatches parallel sub-agents per target (`3534415`).
- `/hv-pause` handoff filenames key on `(branch, repo)` — `<branch>@<repo>.md` instead of `<branch>.md` so two sub-repos sharing a branch name don't clobber each other's notes (`de650e3`). `/hv-resume` reads the umbrella-keyed path with legacy fallback.
- `/hv-spike --repo` runs the spike branch in the resolved sub-repo; spike file stays at the umbrella with a `repo:` frontmatter line (`973aba8`).
- `/hv-plan --repo` records the target sub-repo in plan frontmatter (`c2c0915`).
- `/hv-assume` peek displays the resolved sub-repo for items with `Repos:` (`56bc0d4`).

## Changed

- Architectural sweep: 11 improvements covering the umbrella read-side (`hv-base-branch` walk-up, `hv-review-scope --repo`, `hv-status-add/-remove --repo`, `hv-summary` / `hv-backlog` repo display, `hv-preflight` validates `repos.json`), plus umbrella-aware threading through `/hv-work`, `/hv-ship`, `/hv-debug` call sites (`d9afb4b`).
- Architectural sweep: 5 improvements to release helpers (`hv-release-bump-version --dry-run`, `parse_toml_version` lifted to `hvlib`) and one default flip — `docs.autoCreate: true → false` for fresh `/hv-init` runs, pending the M01-S03 LLM safety review (existing configs unaffected) (`3c1bc02`).

## Documentation

- Umbrella-mode guide refresh: `docs/usage/umbrella-mode.md` rewritten for the shipped surface, dropping all "S01/S02" hedging; new "Per-skill behavior" section listing the umbrella behavior of every affected skill plus the helper `--repo` matrix (`0feaf8c`).
- README updated: features grid gains an Umbrella mode row; config example shows `umbrella` and `docs` keys with `autoCreate: false`; architecture tree notes `repos.json` and `(branch, repo)` keying.
- Skills surface in `docs/usage/`: prose-only umbrella documentation in `/hv-go`, `/hv-review`, `/hv-status` (`1f719c2`).
- Earlier in the cycle: README quickstart + getting-started Path A and Path B walkthroughs got fleshed out (`d7442b8`, `475a394`); `/hv-decide`, `/hv-docs`, `/hv-release` surfaced in the README diagram and reference (`4cd20a7`).

## Stats

12 commits, 44 files changed, +1347 −308 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.13.0...v1.14.0

## v1.13.0 — 2026-05-02

**Umbrella Mode V1 — coordinate backlog and work across multiple sub-repos from a single `.hv/`.**

## New

- **Umbrella Mode foundation (M02-S01)** — opt-in detection, sub-repo registry (`.hv/repos.json`), and resolvers so a single `.hv/` can coordinate work across multiple repos. Adds `hv-umbrella-init`, `hv-resolve-umbrella`, `hv-resolve-repo` helpers; `hv-bootstrap` seeds an empty registry; `hv-init` Step 1.5 prompts for umbrella opt-in; `hv-config` exposes a toggle.
- **Umbrella Mode command awareness (M02-S02)** — `--repo` flag plumbed through `hv-status-add`, `hv-status-remove`, `hv-merge`, `hv-pr`, `hv-worktree-clear`, and `hv-reconcile` (per-entry git scoping). `/hv-capture` Step 4.6 tags items with their target repo; `/hv-work` creates branches in the right sub-repo with isolation guards.

## Changed

- Refreshed CLAUDE.md managed blocks (decisions index, vision index — M02 marked active).
- Fixed exec bit on `hv-resolve-repo`.

## Documentation

- New umbrella-mode user-guide page.

## Stats

24 commits, 18 files changed, +946 −46 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.12.2...v1.13.0

## v1.12.2 — 2026-05-02

Single bugfix surfaced one release after `/hv-release` shipped.

## Fixed

- **`bin/hv-skills-index` now lists `/hv-release` under Maintenance** (`b7ea9f8`). The helper has a hand-curated body (intentionally not auto-derived from `plugin.json` so the editorial categorization survives), and the F03 integration worker brief covered `plugin.json` + `slash-commands.md` + `cli-helpers.md` + `README.md` but missed this helper. Re-running `hv-skills-index` regenerates the managed `<!-- hv-skills -->` block in `CLAUDE.md`.

Users on v1.12.0 / v1.12.1 saw a stale skills index; v1.12.2 corrects it. Captured the gap as a Skill Authoring learning so the next worker brief catches it.

## Stats

1 commit · 2 files · +2 / −2 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.12.1...v1.12.2

## v1.12.1 — 2026-05-02

Two follow-up improvements to `/hv-release` surfaced while dogfooding it for the v1.12.0 cut.

## Changed

- **Step 1 unpushed HEAD** — `autonomy: auto`/`loop` now silently runs `git push` and continues; `autonomy: off` prompts via `AskUserQuestion` (`Push and continue (Recommended)` / `Abort`). Removes the ceremonial "go push, then re-run me" friction — a release intends to ship the local commits.
- **Step 6 dense-bucket compaction** — when a bucket has 3+ entries on the same theme, the orchestrator collapses them into a single summary line plus 1-2 highlight bullets (the merge commit, a follow-up fix). Buckets with fewer than 3 entries stay raw. The helper still emits raw categorization; editorial collapse is the skill's job.

## Stats

1 commit · 1 file · +12 / −1 lines.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.12.0...v1.12.1

## v1.12.0 — 2026-05-02

## Highlights

- **New skill: `/hv-release`** — cuts a release end-to-end. Bumps the project version (`major`/`minor`/`patch` or explicit semver), generates categorized release notes from commits since the last tag, prepends a section to `CHANGELOG.md` (creating it if absent), creates an annotated git tag, pushes commit + tag, and publishes a release on GitHub or GitLab when origin is set. Auto-detects the version source across `.claude-plugin/plugin.json`, `package.json`, `pyproject.toml`, `Cargo.toml`, and plain `VERSION` / `version.txt`; honors a `release.versionFile` override in `.hv/config.json`.
- **5 new bin helpers**, each small / atomic / stdlib-only:
  - `hv-release-detect-version` — emit `{file, version, kind}` JSON
  - `hv-release-bump-version` — apply a semver bump (or explicit version) in-place via atomic write
  - `hv-release-changelog-from-commits` — categorize commits in a git range by Conventional Commits prefix; detects `BREAKING CHANGE:` footer
  - `hv-release-update-changelog` — prepend a release section to `CHANGELOG.md` (creates the file with `# Changelog` header if absent); idempotent — refuses if the version section already exists
  - `hv-release-detect-host` — classify origin URL as `github` / `github-enterprise` / `gitlab` / `gitlab-self-hosted` / `none`
- **22 new smoke assertions** cover every helper across each version-file kind, all semver bump rules, full bucket categorization including BREAKING CHANGE, idempotent CHANGELOG prepend, and host detection over SSH/HTTPS variants.

## Configuration

New keys under `release.*` in `.hv/config.json` (all optional):

| Key | Default | Notes |
|---|---|---|
| `release.versionFile` | (auto-detect) | Explicit path override |
| `release.changelogPath` | `CHANGELOG.md` | Project-root relative |
| `release.tagPrefix` | `v` | Set to `""` for unprefixed tags |
| `release.draft` | `false` | Pass `--draft` to `gh` / `glab` |
| `release.requireCleanTree` | `true` | Set `false` to allow dirty releases (testing only) |

## Stats

9 commits · 11 files · +1,130 / −1 lines · all smoke tests pass.

**Full changelog:** https://github.com/l4ci/hv-skills/compare/v1.11.0...v1.12.0

