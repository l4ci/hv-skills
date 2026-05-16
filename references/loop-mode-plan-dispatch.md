# Loop-mode auto-dispatch chain & rename-collision detection

Shared reference for `/hv-work` Step 4 *Plan Tasks* details that are dense and self-contained: the loop-mode auto-dispatch chain (B28 design pre-flight, F34 uncertainty pre-flight, F35 orchestrator-model contract, F32 auto-plan) plus the wave-planning *Detect rename + link-sweep collisions* rule. The SKILL.md keeps the plan-as-artifact gate and the per-step decomposition list inline; this file holds the longer choreography.

## Design pre-flight (B28, loop mode only)

Before the uncertainty pre-flight, `/hv-work` checks for a design artifact at `.hv/designs/<itemId>.md`. When absent for a Major + Milestone-tagged item, dispatch `/hv-brainstorm --auto-loop <itemId>` via the `Skill` tool — no prompt, no confirmation. The dispatched skill auto-resolves design questions via the same pipeline shape `/hv-plan --auto-loop` uses (Local-first against `DECISIONS.md` / `KNOWLEDGE.md` / `CONTEXT.md` / `MILESTONES.md` → Bounded web when `loop.webResearch == true` → Placeholder fallback for the unresolved), logs fresh picks via `hv-auto-decision-log`, and writes the design with `auto: true` frontmatter.

When the design already exists (auto-written or manually authored), this step is a no-op — loop calls are idempotent and never replace existing designs.

The design feeds the downstream `/hv-plan --auto-loop` directly: `/hv-plan` Step 3 already loads `.hv/designs/<itemId>.md` as soft input. The plan inherits the design's chosen approach instead of re-resolving it, and the open questions / assumptions land in the plan's frontmatter pointer (`design: .hv/designs/<itemId>.md`).

## Loop-mode auto-plan dispatch

When no plan exists AND `autonomy.level == "loop"` AND the item is **Major** AND the item is **Milestone-tagged** (a plan key exists), `/hv-work` does **not** stop the loop on the missing plan. After the design pre-flight (above) and the uncertainty pre-flight (below) complete, dispatch `/hv-plan --auto-loop <milestone>-<itemId>` via the `Skill` tool — no prompt, no confirmation, no "want me to" question. When the dispatched plan run returns, `/hv-work` re-runs the plan-as-artifact check (the file now exists) and uses the auto-written plan as the orchestrator's plan. Off and auto modes never auto-dispatch — they fall through to the manual decomposition.

## Uncertainty pre-flight (F34, loop mode only)

Before the auto-plan dispatch, `/hv-work` runs:

```bash
.hv/bin/hv-uncertain <itemId>
```

The helper applies a structural-triple heuristic — fires "uncertain" when the item is Major AND any of: (a) no detail file at `.hv/<bugs|features|tasks>/<itemId>.md`, (b) brief contains 2+ question marks or explicit uncertainty markers (`TBD`, `unclear`, `unsure`, `open question`, `heuristic TBD`), or (c) brief contains zero backtick-delimited code spans (no concrete identifier anchors → unknown surface). Exit 0 = uncertain (with reasons on stdout); exit 1 = certain; exit 2 = error.

When uncertain, **run the `/hv-work` Preview Mode procedure inline** with `<itemId>` as the target — no prompt, no confirmation. The peek prints to chat and lands in the orchestrator's session context, where the subsequent `/hv-plan --auto-loop` reads it. After the peek returns, proceed with the `/hv-plan --auto-loop` dispatch as normal. When certain, skip the peek and dispatch `/hv-plan --auto-loop` directly.

## Orchestrator-model contract (F35)

The two dispatched skills — `/hv-brainstorm --auto-loop` and `/hv-plan --auto-loop` — are invoked via the `Skill` tool, which loads each inline in the current session. The Preview Mode peek (when uncertain) runs inline inside `/hv-work`'s own session — no dispatch, no Skill call. Since `/hv-work` itself runs in the orchestrator session under `models.orchestrator`, both the dispatched skills AND the inline peek benefit from orchestrator-grade judgment. If a future change moves any of the dispatched skills to `Agent`-based dispatch, the call site must explicitly pass `model: orchestrator` (read from `.hv/config.json`) to preserve this guarantee.

## Detect rename + link-sweep collisions

Before grouping into waves, scan task pairs for the pattern *Task A renames a file (`git mv old new` or equivalent), Task B edits files that link to `old`*. The collision is on **shared written files** — when the link-sweep enumerates the renamed file itself or other files the rename task already edits, both tasks race on the index even when their stated mandates appear disjoint. Resolve at plan time by one of:

- **Merge** rename + link-sweep into one task (preferred when they're one logical change — one commit, atomic revert).
- **Split ownership cleanly**: rename task owns the file move plus edits to the renamed file's own content; link-sweep task owns link updates in all *other* files. No file appears in both tasks' modified-file sets.
- **Serialize across waves**: rename in wave N, link-sweep in wave N+1, so the sweep operates on settled paths.

For every rename, derive the incoming-link file set with `.hv/bin/hv-plan-rename-check <old-name> [<scope>...]` (wraps `git grep -l`); the plan author's enumeration is a hint, the helper is ground truth. Re-run the same check at verify time (Step 7) to catch files the plan missed.

## Cited by

- `/hv-work` Step 4 — *Plan Tasks*
