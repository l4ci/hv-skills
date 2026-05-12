# Loop-mode plan dispatch & rename-collision detection

Shared reference for `/hv-work` Step 4 *Plan Tasks* details that are dense and self-contained: the loop-mode auto-plan dispatch trio (auto-plan, F34 uncertainty pre-flight, F35 orchestrator-model contract) plus the wave-planning *Detect rename + link-sweep collisions* rule. The SKILL.md keeps the plan-as-artifact gate and the per-step decomposition list inline; this file holds the longer choreography.

## Loop-mode auto-plan dispatch

When no plan exists AND `autonomy.level == "loop"` AND the item is **Major** AND the item is **Milestone-tagged** (a plan key exists), `/hv-work` does **not** stop the loop on the missing plan. Instead, it runs the uncertainty pre-flight described next, then dispatches `/hv-plan --auto-loop <milestone>-<itemId>` via the `Skill` tool — no prompt, no confirmation, no "want me to" question. When the dispatched plan run returns, `/hv-work` re-runs the plan-as-artifact check (the file now exists) and uses the auto-written plan as the orchestrator's plan. Off and auto modes never auto-dispatch — they fall through to the manual decomposition.

## Uncertainty pre-flight (F34, loop mode only)

Before the auto-plan dispatch, `/hv-work` runs:

```bash
.hv/bin/hv-uncertain <itemId>
```

The helper applies a structural-triple heuristic — fires "uncertain" when the item is Major AND any of: (a) no detail file at `.hv/<bugs|features|tasks>/<itemId>.md`, (b) brief contains 2+ question marks or explicit uncertainty markers (`TBD`, `unclear`, `unsure`, `open question`, `heuristic TBD`), or (c) brief contains zero backtick-delimited code spans (no concrete identifier anchors → unknown surface). Exit 0 = uncertain (with reasons on stdout); exit 1 = certain; exit 2 = error.

When uncertain, **dispatch `/hv-assume <itemId>` via the `Skill` tool first** — no prompt, no confirmation. Its peek prints to chat and lands in the orchestrator's session context, where the subsequent `/hv-plan --auto-loop` reads it. After the peek returns, proceed with the `/hv-plan --auto-loop` dispatch as normal. When certain, skip the peek and dispatch `/hv-plan --auto-loop` directly.

## Orchestrator-model contract (F35)

Both `/hv-assume` (when dispatched) and `/hv-plan --auto-loop` are invoked via the `Skill` tool, which loads the dispatched skill inline in the current session. Since `/hv-work` itself runs in the orchestrator session under `models.orchestrator`, the dispatched skills inherit the orchestrator model — the peek and plan benefit from orchestrator-grade design judgment. If a future change moves either skill to `Agent`-based dispatch, the call site must explicitly pass `model: orchestrator` (read from `.hv/config.json`) to preserve this guarantee.

## Detect rename + link-sweep collisions

Before grouping into waves, scan task pairs for the pattern *Task A renames a file (`git mv old new` or equivalent), Task B edits files that link to `old`*. The collision is on **shared written files** — when the link-sweep enumerates the renamed file itself or other files the rename task already edits, both tasks race on the index even when their stated mandates appear disjoint. Resolve at plan time by one of:

- **Merge** rename + link-sweep into one task (preferred when they're one logical change — one commit, atomic revert).
- **Split ownership cleanly**: rename task owns the file move plus edits to the renamed file's own content; link-sweep task owns link updates in all *other* files. No file appears in both tasks' modified-file sets.
- **Serialize across waves**: rename in wave N, link-sweep in wave N+1, so the sweep operates on settled paths.

For every rename, derive the incoming-link file set with `.hv/bin/hv-plan-rename-check <old-name> [<scope>...]` (wraps `git grep -l`); the plan author's enumeration is a hint, the helper is ground truth. Re-run the same check at verify time (Step 7) to catch files the plan missed.

## Cited by

- `/hv-work` Step 4 — *Plan Tasks*
