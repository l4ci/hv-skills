# Authoring conventions

These conventions constrain how new hv-skills (or new behavior in existing skills) are authored. Skill authors consult this reference when writing or modifying any `hv-*/SKILL.md` file. `hv-init/SKILL.md` cites this page; no other skill currently does, but new authoring rules land here, not inline.

Cited by `hv-init/SKILL.md` (the canonical entry point for the convention set).

## Skills are self-contained — no shared contract file

Each skill owns its rules inline. A "shared contract" reference file (an old `GUIDE.md` was one) is a smell when every rule has a single owner. Audit the cross-refs before retaining a shared file: if each rule is already mirrored inline at the call site (preflight 3-exit codes, plain-text fallback, autonomy off/auto/loop dispatch, learn trigger thresholds, etc.), the central file is vestigial pointer-chasing. Build a shared file only when N≥3 callers need the same long rule verbatim.

## Imperative rules in autonomy-aware steps must live inline at every dispatch point

Steps that branch on `autonomy.level` (off/auto/loop) and dispatch the next skill via `Skill` ("no prompt, no confirmation, no 'want me to' question") must repeat the directive verbatim alongside each `Skill`-tool invocation. Readers don't chase cross-refs to a single source of truth, and the harness drifts toward asking when only the rule's name is at the dispatch site. Redundancy is cheaper than scattered authority.

## Don't ask what the code can answer

Before a skill calls `AskUserQuestion`, check whether the answer is derivable from the codebase, git history, or `.hv/` state — `grep`, `Read`, `git log`, `BACKLOG.md`, `KNOWLEDGE.md`, `status.json`, helper output. If it is, derive the answer (with a one-line note inline about what was found and where) and skip the question. `AskUserQuestion` is for genuine ambiguity — open requirements, opposing reasonable interpretations, the user's risk tolerance on a destructive op — not a forced-yes ritual confirming state the skill could discover.

Codified from grill-with-docs (2026-05-10): *"If a question can be answered by exploring the codebase, explore the codebase instead."* Companion to the *AskUserQuestion option list capped at 4* rule (`KNOWLEDGE.md`, 2026-05-08) — that one constrains the option list when asking is the right move; this one constrains whether to ask at all.

## Surface multi-step skill progress with TaskCreate

Skills with three or more distinct phases must declare a visible task list at the end of Step 1 via `TaskCreate`, then mark each phase `in_progress` when starting it and `completed` when its observable outcome lands. The user sees a checklist instead of unannotated bash output; the agent stays oriented across long cycles. Without this, every multi-step run looks identical in the transcript to a single-step nudge — progress is invisible until the final report.

The block lives at the end of Step 1's body, never as a new `Step 1.5`. The decimal-step rule (`KNOWLEDGE.md` / `DECISIONS.md`, 2026-05-08) reserves `.5/.6/.7` slots for sequential additions; this convention is content within Step 1, not a new step. On hosts where `TaskCreate` is not loaded (non-Claude-Code platforms), the boilerplate self-skips silently — loading is conditional on `ToolSearch select:TaskCreate,TaskUpdate`.

Per-site shape (adapt phase list per skill):

> **Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="<phase 1 name>", description="<phase 1 outcome>")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases get `completed` with the no-op reason in the description.
>
> Phases:
>
> 1. *<phase title>* — *<one-line outcome>*
> 2. *<phase title>* — *<one-line outcome>*
> *(skill-specific list — 3 to 7+ phases)*

**Observable outcome** is the detection predicate that says a phase is done. It must be mechanically verifiable, not subjective. Verifiable shapes:

- A file exists at a named path — `[ -f .hv/plans/M01-S01.md ]`.
- A command exits 0 — a helper returns success, a test passes, `hv-knowledge-merge` writes successfully.
- A managed-block marker is present in a tracked file — `grep -q '<!-- hv-knowledge-end -->' CLAUDE.md`.
- A status entry was added or removed — `.hv/status.json` lists / no longer lists the branch.
- A commit landed — `git log --oneline -1 | grep -q <ID>`.
- A user picked a recorded answer in `AskUserQuestion` — the chosen label is the outcome marker (e.g. *"user picked 'Write it' on the confirmation gate"*).

Subjective phrases — *"looks good"*, *"feels done"*, *"is satisfied"*, *"the situation is clear"* — don't qualify. When a phase genuinely produces a subjective state (a UX flow approval, a design pick), name the user action or recorded decision that captures the approval rather than the inner state. Skill authors picking a phase outcome should ask: *"what would I `grep` or `[ ]` test for, from the next session, to know this phase finished?"* If the answer is "nothing concrete", the phase is too vague to track.

**Forbids.**
- Adding the block to single-phase or trivial skills (Tier C: `hv-assume`, `hv-go`, `hv-c`, `hv-update`, `hv-map`) — the checklist UX is overhead when there's nothing to tick off.
- Placing it as a new `Step 1.5` — the decimal-step rule reserves those slots; this is content within Step 1.
- Cross-skill alignment of phase names — each skill's phase list reflects its own structure; phrasing is local to the SKILL.md.
- Calling `TaskCreate` from inside subagent dispatches — the orchestrator owns the task list; workers focus on their assigned tasks and report back.

**Permits.**
- Per-site phase counts from 3 to 7+ — the rule fires at "multi-step", not a fixed number. Use phase boundaries that match the skill's natural structure, not the integer step count.
- Per-site boilerplate prose variations — this is a cross-cutting autonomy-shaped rule; per the 2026-05-09 `KNOWLEDGE.md` entry on cross-cutting prose, byte-equivalent repetition of the shell across 18 sites is acceptable when phase lists dominate.
- Phases that absorb decimal sub-steps (e.g. `/hv-work` 13.5/13.7 fold into one "post-cycle nudges" phase) — phase boundaries are coarser than step boundaries by design.
- Tracking spawned waves as nested tasks via `addBlocks`/`addBlockedBy` when a skill orchestrates parallel work — `/hv-work` may use this for its dispatched waves.

Codified from F37 (2026-05-10): rolled out across Tier S/A/B SKILL.md files (hv-init + 17 others). Tier C skills stay untouched. Companion to the *AskUserQuestion option list capped at 4* rule (`KNOWLEDGE.md`, 2026-05-08): both make the host's UI primitives load-bearing for skill UX.

## Routine routing/tagging auto-picks Recommended in loop mode

When `autonomy.level == "loop"`, AskUserQuestion calls that present a single clear `(Recommended)` option for **routine routing or tagging** must silently auto-pick the Recommended option without invoking AskUserQuestion. The host's question UI never fires; the skill proceeds as if the user picked the Recommended answer.

This is what makes loop mode actually loop — a single "Tag with M01?" or "Resume vs ship?" prompt mid-queue stalls every subsequent item until the user types an answer. Loop mode's contract is "drain the queue until empty / guard / interrupt"; intermediate routine prompts violate it.

Routine = the kind of question where the Recommended option is the obvious right answer, not a design pick. Examples: milestone tagging (`/hv-capture` Step 4.5), sub-repo tagging (`/hv-capture` Step 4.6), reconcile resolution (`/hv-next` Step 2 — resume / ship / leave), CONCERNS routing (`/hv-ship` Step 3 — "Address via /hv-work"), refactor scope and candidate gates.

**Forbids.** Auto-picking on:
- **Design decisions with open questions** — competing approaches, version-bump escalation, novel pattern choice. These belong to F32 (loop-mode auto-planning, with `[Auto:Loop]` decision logging). A `(Recommended)` flag on a design pick is a *suggestion*, not a routine answer; the loop must surface them.
- **Manual gates that are never auto-invoked regardless of autonomy** — `/hv-decide` approvals, `/hv-learn` Step 8.5 issue filing, `/hv-learn` Step 9 runlog filing, `/hv-ship` Step 5 PR strategy, `/hv-release` push/publish gates. These have explicit `**Manual gate — ...**` callouts in their SKILL.md. Loop mode honors the gate — it does not auto-pick.
- **Config-flip questions** — `/hv-init` initial setup, `/hv-config` edits, `/hv-docs` after-work-mode opt-in. These flip user-preference flags; the opt-in-defaults-to-`false` rule (below) requires explicit user approval, not loop-mode synthesis.

**Permits.**
- Routine routing/tagging with one clear Recommended option (the use cases listed above and any future analogue).
- Sites that already implement the pattern explicitly (`/hv-next` Step 7 work-on-suggested-item, `/hv-update` Step 4 re-init) — same shape, already inline; new sites follow their lead.
- Per-site phrasing variations — each site's loop branch states the auto-pick locally because the autonomy-rule-must-live-inline convention (above) forbids cross-refs to a single source of truth.

The dispatch site should add a short loop branch alongside the existing `"off"` AskUserQuestion arm. Pattern (adapt phrasing per site):

> **Loop mode:** when `autonomy.level == "loop"`, silently auto-pick the Recommended option without invoking AskUserQuestion — `<one-line summary of what gets dispatched>`.

Codified after F33 caught loop-mode discontinuity from `/hv-capture` milestone tagging and `/hv-next` reconcile gates breaking the `/hv-work` → `/hv-learn` → `/hv-next` → `/hv-work` chain.

## User-volition gates enforced at exactly one point

Manual confirmation gates (`/hv-decide`'s manual-only contract, the public-artifact gate in `/hv-learn` Step 8.5, etc.) must be enforced at exactly ONE point in a skill, never propagated across orchestrator + called skill. The gate is architecture-enforced — only the owning skill can ask the question, and no other skill dispatches the gated skill via `Skill`. Putting a confirmation check in a skill that other skills can invoke breaks the contract under autonomy.

## Stage features across slices using pass-through stubs

Multi-slice features ship the SHAPE early via pass-through stubs that explicitly name the future-slice wiring point (e.g. *"Layer-1 filter is a pass-through stub; `bin/hv-docs-filter` lands in M01-S03"*). This signals what consumers should NOT rely on yet. **Companion rule:** when the milestone flips to `shipped`, sweep all `M0X-S0Y` slice references — they were placeholders and become stale after merge.

## Helper-centric V2-surface extension

When scaling a feature surface from "single X" to "list of X" (e.g. one repo → many) across N skills, push parsing/validation/dispatch into `bin/` helpers and confine each SKILL.md edit to a single guard paragraph: *"if the value resolves to ≥2 entries, call helper-X; otherwise unchanged."* Single-X path stays byte-identical, multi-X complexity lives in code (exercised by smoke), per-skill prose stays ≤15 lines.

## Opt-in feature flags default to `false`

When adding a new boolean config flag whose purpose is to enable additional skill behavior or auto-invocation:

- **Default `false`** in both the FRESH write block and the STALE migration's setdefault.
- **Never silently flip to `true`** anywhere — not on first detection, not on first invocation, not via cwd-inferred heuristics.
- The owning skill flips the flag to `true` only via explicit user approval: first-run scaffold approval (the user opted in by approving), or `AskUserQuestion` on existing state with default "Leave off".
- `/hv-config` edits the flag explicitly (the flag is never read-only).
- **Exempt:** standard-on settings with opt-out semantics (e.g. `learn.verify: true`, `ship.review: true`) — these are not opt-in flags. Mode switches inside an already-enabled feature (e.g. `docs.autoCreate: false→true`) are also exempt.

Codified after F15 introduced `docs.afterWork`. Without this rule, opt-in flags drift toward auto-flip-on-first-detect, which makes them on-by-default in practice — defeating the opt-in semantics. Mirror reminder lives in `hv-config/SKILL.md`.

## Dispatch heavy work to subagents

Skills MUST consult `references/subagent-dispatch.md` for any step involving ≥3 file reads, repeated independent operations on N items, long tool output, or fan-out research. Orchestrator-only work (decisions, user interaction, atomic writes, verification of subagent output) is exempt — it stays on the main thread.

The reference defines the cost/benefit threshold, the small-brief template, the return-shape contract, the model-tier mapping (haiku / sonnet / opus), the parallel fan-out pattern (single-turn dispatch, worktree-isolation cross-cite), and the orchestrator's remaining responsibilities.

Three retrofitted skills illustrate compliance:

- `hv-next` — Steps 2/3/4/6 dispatch as a single parallel wave (reconcile + archive + per-milestone summary + relevance queries) so the backlog rendering in Step 5 receives synthesis instead of raw helper output.
- `hv-vision` — Step 2 bundles all context reads into one haiku worker that returns a compact snapshot; Step 4 fans out N parallel research workers (one per angle) instead of serial `WebSearch` calls on the orchestrator.
- `hv-debug` — Step 5 dispatches reproduction to a sonnet worker when the repro is heavy (multi-MB output, multi-step manual setup, writing a failing test from scratch); Step 7 dispatches verification to a worker (model tier depends on whether the verdict requires judgment or pattern-matching). Cheap repros and single-line verifications stay inline.

A skill author asking "what does compliance look like?" can read any one of the three retrofits and find a concrete answer for every rule in the reference. New skills follow the same pattern.

**Forbids.** Dispatching for ≤2 small reads, for orchestrator-already-loaded context, for interactive steps, or when the brief would cost more tokens than the work. Cross-worker communication. Returning full transcripts instead of synthesis. Calling out to `superpowers:dispatching-parallel-agents` or other external skills — the hv-skills dispatch discipline is self-contained.

**Permits.** Mixed tiers in a single wave (one haiku worker alongside three sonnet workers in the same turn). Opportunistic haiku usage declared inline in the brief without a config flag. Per-skill judgment on which steps trip the threshold — the rule sets a floor, not a ceiling.
