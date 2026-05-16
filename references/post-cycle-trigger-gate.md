# Post-cycle trigger gate

Used by `/hv-work` Step 13 (Learn) + Step 13.6 (Docs After-Work), `/hv-ship` Step 8.5 (Learn) + Step 8.6 (Docs After-Work) + Step D-A1 (Docs Mode Trigger Gate). Four sites share the same trigger condition byte-for-byte — extracted here so the rule has a single source of truth.

## The condition

A post-cycle nudge or auto-dispatch fires when **at least one** of:

- **2+ items resolved** in the cycle (counted by closed `[B##]`/`[F##]`/`[T##]` IDs across that cycle's commits).
- **≥5 files touched** in the cycle (counted by the cycle's diff against its base — for `/hv-ship`, use the scope JSON's `touchedFiles` field).
- A **hard bug** that took 2 or more debug cycles to root-cause (signaled by 2+ `/hv-debug` invocations within the same `/hv-work` session, or by the bug carrying a `Detail:` pointer to a `.hv/bugs/<id>.md` file with 2 or more hypothesis entries).

## When the gate does NOT fire

- Single-item fixes — one `[B##]`/`[F##]`/`[T##]` resolved, fewer than 5 files touched, no debug-cycle escalation.
- Pure mechanical changes — bulk rename, dependency bump, formatting sweep, generated-file refresh. The diff size doesn't capture intent; an author can use judgment to skip the nudge when there's clearly nothing durable to learn or document.
- The same nudge has already fired in the current session for the current trigger (don't repeat).

## Why a gate at all

The downstream nudges (Learn, Docs After-Work) cost user attention or token budget. Firing them on every single-item fix trains the user to dismiss the nudge, which loses the signal when something genuinely worth capturing happens. The thresholds are calibrated so that a cycle big enough to trip any one of them is plausibly worth a post-cycle pass.

## Autonomy interaction

The gate is the precondition for dispatch; it is **not** the autonomy-aware imperative itself. Each call site keeps its inline `autonomy.level` branch — *"off"* nudges, *"auto"/"loop"* auto-dispatches via `Skill` — verbatim at the dispatch point, per `references/authoring-conventions.md` rule *"Imperative rules in autonomy-aware steps must live inline at every dispatch point"*. This reference defines WHEN to dispatch; the dispatch instruction itself stays at the call site.

## See also

- `references/authoring-conventions.md` — the inline-at-dispatch-point rule that constrains how each site cites this trigger.
- `references/manual-gates.md` — for the orthogonal *"always manual, never auto-invoked"* gates (`/hv-decide`, `/hv-learn` Step 8.5/8.6, `/hv-ship` Step 6a, `/hv-release` Step 8/9). Those are separate from this trigger — they fire even when the trigger does, and never auto-pick.
