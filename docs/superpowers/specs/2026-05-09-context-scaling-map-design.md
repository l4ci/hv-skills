# Context-scaling map: keeping growing projects legible to AI

**Status:** Draft, awaiting user review
**Date:** 2026-05-09
**Owner:** hv-skills

## Problem

As any project grows, the AI's session context becomes the binding constraint. Source trees expand, KNOWLEDGE.md fills up, TODO grows, and the always-on preamble that orients the AI either bloats or omits things it would actually need. Without explicit structure, AI either reads too much (slow, expensive, distracted) or too little (drifts, repeats mistakes, can't find the right entry points).

hv-skills already solves the *knowledge* side: KNOWLEDGE.md / DECISIONS.md / MILESTONES.md are topic-indexed, with per-topic queries (`hv-knowledge-query`, `hv-decisions-query`, `hv-todo-by-milestone`) and a thin always-on index in CLAUDE.md. The gap is the *code/architecture* side and a unifying *hygiene* policy that keeps all three lists from accreting indefinitely.

## Goal

Add a "project map" of subsystems alongside the existing knowledge artifacts, plus a shared hygiene policy across MAP / KNOWLEDGE / TODO so the always-on context stays roughly flat as the project grows. AI navigates by name through cheap on-demand queries; growth lands in queryable bodies, not the always-on header.

## Non-goals

- No AST/parser-based entry-point extraction. Entry points are plain `file:line` strings the AI maintains alongside its work.
- No embeddings, no semantic search. The query is by name, period.
- No git hooks, no schedulers, no daemons. All updates ride along with `/hv-work` cycles, exactly like `/hv-learn` and `/hv-docs` already do.
- No cross-project map sharing.
- No auto-summarization of source files. Waypoints are AI-curated narratives, not generated abstracts.

## Design

### Three coordinated layers

**1. Map layer**

- `.hv/MAP.md` — thin index, one line per subsystem (mirrors KNOWLEDGE.md root).
- `.hv/map/<subsystem>.md` — per-subsystem detail files, AI-proposed names, free-form taxonomy with a soft cap (default 20).
- A managed block in `CLAUDE.md` (`## Project Map`) lists subsystems with one-line summaries; this is what stays always-on.

**2. Retrieval layer (no new mechanism)**

- AI consults the always-on `## Project Map` block to find the relevant subsystem, then pulls the body with `hv-map-query <name>`.
- `/hv-work`, `/hv-debug`, `/hv-plan`, `/hv-go` reach for it when their target intersects a listed subsystem.
- Same shape as the existing KNOWLEDGE flow — no new behaviour to teach.

**3. Hygiene layer (uniform across MAP / KNOWLEDGE / TODO)**

- **Timestamps drive staleness flags.** `/hv-status`, `/hv-next`, `/hv-resume` print a one-line `Stale candidates:` row from `hv-staleness`. Never blocks output.
- **Soft caps** raise a one-line warning at `/hv-work` start when any of MAP / KNOWLEDGE / TODO crosses a threshold (e.g. ≥20 subsystems). Never blocks work.
- **`/hv-map` consolidation skill** runs deep cleanup on demand: review index, propose merges and archives, regenerate the CLAUDE.md block. Extends to KNOWLEDGE and TODO suggestions in `consolidate` mode.

### Detail file shape

Bounded by convention: ~200 lines, 5 sections, frontmatter + markdown.

```markdown
---
subsystem: capture
summary: Captures bugs/features/tasks into TODO.md without executing
touched: 2026-05-09
created: 2026-03-12
related-topics: [Skill Authoring, Build & Tooling]
related-items: [F12, B08]
---

## Purpose
One paragraph max.

## Entry points
- bin/hv-append:42 — appends a row to TODO.md
- hv-capture/SKILL.md — orchestration logic

## Key files / dirs
- hv-capture/, hv-c/, bin/hv-next-id

## Conventions specific here
- IDs are zero-padded ([B07], not [B7]).

## Notes / gotchas
- Don't re-mint IDs for archived items.
```

The index in `MAP.md` and the CLAUDE.md block are derived from `summary:` lines — that is what stays always-on.

### New helpers in `bin/`

| Helper | Mirrors | What it does |
|---|---|---|
| `hv-map-query <name>...` | `hv-knowledge-query` | Read named detail file(s); used by AI on demand. |
| `hv-map-index` | `hv-knowledge-index` | Regenerate `MAP.md` index + the CLAUDE.md `## Project Map` managed block from frontmatter. Idempotent. |
| `hv-map-stats` | `hv-knowledge-stats` | Counts, sizes, last-touched per subsystem. Drives soft-cap warnings. Includes a quick `file:line` existence check on entry points; broken refs surface as staleness, not errors. |
| `hv-staleness <kind>` | (new, shared) | Scans MAP / KNOWLEDGE / TODO timestamps, prints stale candidates. Used by `/hv-status`, `/hv-next`, `/hv-resume`. Falls back to git mtime when frontmatter `touched:` is missing. |

No new state machinery. Timestamps live in frontmatter and are bumped by the AI's commit, the same way `/hv-learn` already mutates KNOWLEDGE.md.

### New skill: `/hv-map`

Three modes (mirrors `/hv-docs`):

1. **first-run** — scaffold `.hv/MAP.md` and propose initial subsystems based on directory structure, existing KNOWLEDGE topics, and recent commits.
2. **after-work** — invoked from end of `/hv-work` (and `/hv-debug`, `/hv-go`) when a touched subsystem's waypoint needs an update or doesn't yet exist. Adds/updates one waypoint, bumps `touched:`, regenerates index.
3. **consolidate** — review mode. Lists stale, dormant, or near-duplicate subsystems; proposes merges and archives. Extends to KNOWLEDGE ("topic X has 1 entry from 8 months ago — fold into Y?") and TODO ("item Z idle 90+ days — archive?"). Never auto-merges; user confirms.

### Touchpoints in existing skills

- **`/hv-init`** — seeds `.hv/MAP.md`, the CLAUDE.md `## Project Map` managed block, and an empty `.hv/map/`.
- **`/hv-work`** — start: emit soft-cap warning if any of MAP / KNOWLEDGE / TODO crosses threshold. End: invoke `/hv-map after-work` for touched subsystems (analogous to existing `/hv-learn` and `/hv-docs` post-cycle calls).
- **`/hv-debug`, `/hv-go`** — same end-of-cycle hook.
- **`/hv-status`, `/hv-next`, `/hv-resume`** — print a `Stale candidates:` line driven by `hv-staleness`. One line, never blocks output.
- **`/hv-capture`** — optional `Subsystem:` field. Inferred from filenames in the user's text or proposed during capture; user can ignore. Helps `/hv-work` know which waypoint to consult without a content scan.

### Always-on context impact

The CLAUDE.md addition is a single managed block of the same shape as the existing `## Project Knowledge` and `## Project Decisions` blocks:

```markdown
## Project Map

Subsystems live in `.hv/MAP.md` (detail in `.hv/map/<name>.md`). Pull with `.hv/bin/hv-map-query <name>`.

- **capture** — captures bugs/features/tasks into TODO.md
- **plan** — implementation plans before execution
- **work** — orchestrator-driven parallel execution
- ... (≤20 lines under soft cap)
```

Always-on cost: ~1 line per subsystem. Detail bodies stay queryable, never auto-loaded. The block hides itself when `.hv/map/` is empty (same conditional pattern as `## Project Vision`).

## Lifecycle of a waypoint

```
/hv-init                   → empty .hv/MAP.md, .hv/map/, CLAUDE.md block seeded
/hv-vision (or first work) → /hv-map first-run proposes initial subsystems
/hv-work cycle             → start: soft-cap warning if any list over threshold
                             plan : consult MAP.md index, hv-map-query <name> as needed
                             end  : /hv-map after-work for touched subsystems
                                    → bumps touched:, refines summary, appends new entry points
                                    → if no existing fit & under cap: propose new subsystem
                                    → if over cap: queue a consolidation note, don't block
/hv-status, /hv-next       → surface stale candidates via hv-staleness
/hv-resume                 → same
/hv-map consolidate        → manual deep cleanup: merge, archive, regenerate
```

## Failure modes & mitigations

| Failure | Mitigation |
|---|---|
| AI forgets to update a waypoint after a cycle. | Git mtime is the fallback signal for staleness. `hv-staleness` uses `frontmatter.touched OR git-log-1`. Worst case is a stale flag, not silent rot. |
| AI proposes too many subsystems (drift). | Soft cap raises a one-line warning at `/hv-work` start. Hard cap not enforced — caps don't block work. `/hv-map consolidate` is the cleanup channel. |
| Entry-point line numbers drift after refactors. | `hv-map-stats` includes a quick `file:line` existence check; broken refs surface as staleness rather than crash. AI fixes them next time the area is touched. |
| Two `/hv-work` branches both edit the same waypoint. | Standard git merge. Bodies are bounded (~200 lines, 5 sections); frontmatter ordering is canonical so timestamp lines diff cleanly. |
| MAP and KNOWLEDGE describe the same thing twice. | Cross-link via `related-topics:` frontmatter, don't duplicate. `/hv-map consolidate` runs a near-duplicate pass against KNOWLEDGE topic titles + first 200 chars and flags overlap. |
| Corrupted / malformed detail file. | Helpers skip with a stderr warning and continue — never crash a `/hv-work` cycle over a stray file. |
| Project doesn't fit "subsystem" thinking (small repo, single-purpose). | MAP scales to zero gracefully. Empty `.hv/map/` hides the CLAUDE.md block. No forced ceremony for tiny projects. |

## Testing strategy

**Smoke tests (end-to-end fixtures, mirrors existing `test/` shape):**

- `/hv-init` on empty repo → asserts `.hv/MAP.md`, `.hv/map/`, CLAUDE.md managed block exist.
- `/hv-map first-run` on a fixture with KNOWLEDGE topics + multi-dir layout → asserts ≥1 subsystem proposed, detail files written, frontmatter valid.
- Simulated `/hv-work` cycle on a fixture touching subsystem X → asserts `touched:` bumped on X's detail file, commit includes that change, no other waypoints touched.
- Soft-cap fixture with 21 prefab subsystems → asserts warning emitted at `/hv-work` start, exit code unchanged (warning, not error).
- Stale fixture (3 detail files dated 200 days ago) → asserts `/hv-status` shows them in `Stale candidates:`.
- `/hv-map consolidate` on overlap fixture (two subsystems with near-identical purpose) → asserts merge proposal, no automatic merge without confirmation.

**Helper unit tests:**

- `hv-map-query foo` returns body for existing; missing-name behaviour mirrors `hv-knowledge-query` exactly.
- `hv-map-index` is idempotent: run twice on same input → byte-identical output.
- `hv-map-stats` JSON output: counts, sizes, last-touched per subsystem; broken `file:line` entries flagged.
- `hv-staleness map --days 90` lists detail files with `touched:` older than 90 days; `--days 0` lists all.
- CLAUDE.md managed-block roundtrip: regenerate with no source changes → no diff. Add a subsystem → exactly the new line appears, nothing else moves.
- Failure inputs: missing `touched:` falls back to git mtime; corrupted YAML → skipped with stderr warning, helper exits 0.

## Open questions

- Default soft-cap threshold. Proposed 20 for subsystems; KNOWLEDGE topics and TODO items may want different defaults — pick during implementation.
- Default staleness thresholds per kind (MAP / KNOWLEDGE / TODO). Likely surface them as `config.json` keys with sensible defaults (e.g. 90 / 120 / 60 days).
- Whether `/hv-capture` should *prompt* for `Subsystem:` or only *infer + suggest*. Default: infer + suggest, never block capture.
- Whether `/hv-map after-work` runs unconditionally or only when a heuristic (changed file count, line delta) suggests a waypoint update is warranted. Default: heuristic, with a flag to force.

## Rollout

The system is additive. Existing skills keep working unchanged; new behaviour activates only when `.hv/MAP.md` exists. `/hv-init` seeds it on new projects; existing projects opt in by running `/hv-map first-run`.
