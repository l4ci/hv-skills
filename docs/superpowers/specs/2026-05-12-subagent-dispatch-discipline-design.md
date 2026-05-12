# Subagent dispatch discipline across hv-skills

**Status:** Draft, awaiting user review
**Date:** 2026-05-12
**Owner:** hv-skills
**Tracking item:** _(to be captured into TODO.md after spec approval)_
**Related:** `references/authoring-conventions.md`, `.hv/DECISIONS.md` (worktree-isolation rule)

## Problem

Across the hv-skills suite, two skills (`hv-work`, `hv-refactor`) use parallel subagents heavily. A handful (`hv-review`, `hv-debug`, `hv-ship`) dispatch a single subagent. The remaining skills — `hv-next`, `hv-vision`, `hv-debug` (in its read-heavy steps), `hv-learn`, `hv-docs`, `hv-map`, `hv-plan`, `hv-brainstorm`, `hv-context`, `hv-decide` — do nearly all work on the orchestrator's main thread.

The result is three symptoms:

- **Context bloat.** Mid-`/hv-next` or post-`/hv-vision`, the main thread carries file dumps, search results, milestone details, and query output that the orchestrator only needed in order to *decide*, not to *retain*.
- **Wall-clock slowness.** Independent operations (per-active-item reconciliation, per-milestone summarization, multi-angle research) run serially when they could fan out.
- **Wrong model on cheap work.** The orchestrator runs at `models.orchestrator` (default `opus`) and does mechanical scans, parses, and queries that haiku could handle.

The root cause is uniform: **the orchestrator is the only worker.** Reads, scans, summaries, and serial queries all live on the main thread because no convention says otherwise.

## Goal

Establish a **dispatch discipline** as a first-class authoring convention: a reference doc + an authoring-conventions citation + three retrofitted skills as worked examples. Future skill authoring inherits the discipline; the three exemplars show what compliance looks like.

The discipline addresses all three symptoms by routing work to the right place:

- Bulky reads / context-polluting tool output → subagent (isolation)
- Independent N-item operations → parallel subagent fan-out (concurrency)
- Mechanical work → haiku-tier subagent (cost)
- Decisions, user interaction, atomic writes, verification → orchestrator (unchanged)

## Non-goals

- No mechanical enforcement (no linter, no test). Same as every other authoring convention in this repo.
- No new `bin/` helpers. Dispatch is a model-side activity; shell helpers cannot invoke the Agent tool.
- No `.hv/` writes. `.hv/` is regenerated runtime; canonical changes live in skill source.
- No retrofit of the remaining main-thread skills (`hv-learn`, `hv-docs`, `hv-map`, `hv-ship`, `hv-plan`, `hv-brainstorm`, `hv-context`, `hv-decide`, plus the unretrofitted steps of `hv-next` and `hv-vision`). They are retrofitted on their next routine edit or in a follow-up cycle.
- No changes to `hv-work` or `hv-refactor`. Already heavy subagent users; not the target.
- No changes to the `models.*` config schema. Existing `orchestrator` / `worker` knobs cover most cases; haiku usage is opportunistic per skill, not a new config field.
- No external dependency on `superpowers:dispatching-parallel-agents`. The dispatch reference is self-contained so hv-skills authors don't context-switch across ecosystems.

## Design

### Artifacts produced

1. **New reference:** `references/subagent-dispatch.md` — the cross-skill rulebook (six sections, described below).
2. **Authoring-conventions update:** one numbered rule in `references/authoring-conventions.md` pointing skill authors at the new reference and stating the dispatch threshold.
3. **Three skill retrofits:** `hv-next/SKILL.md`, `hv-vision/SKILL.md`, `hv-debug/SKILL.md` — each gains specific dispatch points described below.

No new skill. No `bin/` additions. No `.hv/` edits.

### `references/subagent-dispatch.md` — the rulebook

Six sections, each short and rule-shaped to match the tone of existing references in this folder.

**1. When to dispatch.** Cost/benefit rule, not a vibe.

Dispatch when:
- Read-heavy exploration (≥3 file reads or greps in one step)
- Independent parallel work (N items, same operation)
- Context-polluting tool output (long logs, large diffs, multi-page query results)
- Fan-out research (multiple angles on the same question)

Do *not* dispatch when:
- ≤2 small reads
- Work depends on context the orchestrator has already loaded
- Step is interactive (AskUserQuestion, plain-text fallback, Socratic discovery)
- The brief itself would cost more tokens than the work

**2. Small-brief template.** Prescribed shape:

- **Goal** — 1 sentence
- **Inputs** — paths / IDs only, never pasted content
- **Constraints** — relevant forbids + hard boundaries from `.hv/DECISIONS.md`
- **Return shape** — exact structure expected back
- **Word budget** — default ≤200 words

The point: briefs say what the orchestrator needs back, not what the orchestrator already knows.

**3. Return-shape contract.** Subagents return synthesis, not transcripts. Structured shape: `findings · decisions · open questions`. The caller treats the return as the source of truth; the worker's working memory is discarded.

**4. Model tier per work type.**

- `haiku` — mechanical: parse JSON, count items, format markdown, run a known query and relay its output
- `sonnet` — routine reasoning: summarize a file, classify items, search and synthesize
- `opus` — judgment: verification, design selection, hypothesis evaluation

Read `models.*` from `.hv/config.json` when present (skills that already have `models.orchestrator` / `models.worker` configured use those). Haiku usage is opportunistic — declared inline in the brief, not in config.

**5. Parallel fan-out pattern.** When dispatching N independent subagents:

- Issue all Agent tool calls in a **single assistant turn** (one message, multiple tool-use blocks) so they run concurrently.
- Independence requirement: no shared mutable state between workers. File disjointness; for commit-producing waves, the worktree-isolation rule from `.hv/DECISIONS.md` applies (cite inline so authors don't have to chase it).
- Aggregation: the orchestrator collects returns and merges per the synthesis contract. Workers never communicate with each other.

**6. What stays on the orchestrator.**

- Decisions (which approach, which file, which next step)
- User interaction (AskUserQuestion, plain-text fallback, Socratic flows)
- Atomic disk writes (when ordering or all-or-nothing matters)
- Verification of subagent output

The orchestrator is dispatcher + synthesizer. Never reader-of-everything.

### Authoring-conventions citation

`references/authoring-conventions.md` gains one numbered rule (placement matches existing numbering in that file):

> **Rule N — Dispatch heavy work to subagents.** Skills MUST consult `references/subagent-dispatch.md` for any step involving ≥3 file reads, repeated independent operations, or long tool output. Orchestrator-only work (decisions, user interaction, atomic writes, verification) is exempt. Three retrofitted skills illustrate the pattern: `hv-next` (parallel reconcile + archive + milestone + relevance), `hv-vision` (research fan-out + context bundling), `hv-debug` (reproduction + verification isolation).

### Retrofit: `hv-next`

Currently the orchestrator serially: reconciles each active item against git → scans TODO.md for archivable entries → reads each active milestone detail file → runs knowledge/decisions/context queries for candidate items. All four are independent.

Retrofit dispatches them as a **single parallel wave** (one assistant turn, four Agent calls):

- **Worker A (sonnet):** reconcile active items → returns `{still-active, done, drift}`
- **Worker B (haiku):** archive scan → returns list of completion-dated entries past TTL
- **Worker C (sonnet):** per-active-milestone slice summary → returns `milestone → remaining map`
- **Worker D (sonnet):** knowledge/decisions/context queries for top-N candidates → returns relevance map

The orchestrator merges, presents the sorted backlog (Step 5), and runs Suggest Next (Step 6). Steps 1, 7, 8 stay on the orchestrator (preflight, interactive confirm, release nudge).

### Retrofit: `hv-vision`

Two dispatch points:

**Step 4 (Web Research) — fan-out.** Research angles are independent by definition. The orchestrator decomposes the vision frame into N angles (competitive landscape, technical feasibility, user-need patterns, adjacent prior art — typically 3-5, by orchestrator judgment) and dispatches N research workers (sonnet) in a single parallel turn, each returning ≤200-word synthesis. The orchestrator merges before Step 5 Challenge (which stays on the orchestrator — judgment work, opus-grade).

**Step 2 (Load Context Silently) — single subagent.** Currently the orchestrator reads `.hv/MILESTONES.md`, active milestone detail files, `MAP.md`, and relevant decisions. Bundle into one haiku worker that returns a compact context snapshot. Small win, but free — the orchestrator stops carrying the full text of files it only needed to summarize.

Steps 1, 3, 5, 6, 7, 8, 9 unchanged.

### Retrofit: `hv-debug`

Two dispatch points; Step 6 left alone because it already has `competingHypotheses: true` for parallel hypothesizing.

**Step 5 (Reproduce) — single worker.** Dispatch a sonnet worker that runs the reproduction commands, captures output, and returns `{reproduced: bool, observed-vs-expected, relevant-log-excerpts}`. Keeps multi-MB logs out of orchestrator context — the orchestrator gets the verdict and citations, not the raw stream.

**Step 7 (Verify) — single worker.** When a hypothesis requires file reads or searches to confirm, dispatch a verification worker. Model tier follows the verification shape: opus when the verdict requires judgment (e.g., does this code actually implement the claimed invariant?), sonnet when verification is pattern-matching across reads. Returns `{verdict, evidence-citations}`.

Step 8 (Fix) already uses a worker per `models.worker`; no change there.

### Coverage check — exemplars vs. rules

| Rule in reference | Exemplar that demonstrates it |
|---|---|
| Parallel fan-out | `hv-next` (4 workers, one turn), `hv-vision` Step 4 (N research workers) |
| Context-isolation | `hv-debug` Step 5 (logs), `hv-vision` Step 2 (file dumps) |
| Verification subagent | `hv-debug` Step 7 |
| Haiku tier | `hv-next` Worker B (archive scan), `hv-vision` Step 2 (context bundle) |
| Sonnet tier | `hv-next` Workers A/C/D, `hv-vision` Step 4 workers, `hv-debug` Step 5 |
| Opus tier | `hv-debug` Step 7 |
| Small-brief template | All retrofits use the prescribed shape |
| Return-shape contract | `hv-next` (4 specified return shapes), `hv-debug` Step 5 `{reproduced, observed-vs-expected, excerpts}`, Step 7 `{verdict, evidence-citations}` |
| What stays on orchestrator | `hv-next` Steps 5-8, `hv-vision` Steps 3/5/9, `hv-debug` Step 6 |

A skill author asking "what does compliance look like?" can read any one of the three retrofits and find a concrete answer for every rule.

## Risks

- **Convention without enforcement.** The discipline is reference + exemplar, no linter. Mitigation: the three retrofits make the right pattern the path of least resistance; future skill authors crib from them. This is the same enforcement model every other hv-skills authoring convention uses.
- **Over-dispatch.** Authors might dispatch for cases the cost/benefit rule excludes. Mitigation: the rule's "do not dispatch when" list is explicit and short.
- **Brief drift.** Briefs might balloon as authors paste context for safety. Mitigation: the small-brief template + the word budget make minimalism the default; reviewers can flag long briefs the way they flag long commits.
- **Reference rot.** Like any authoring convention, the reference might fall out of sync with practice. Mitigation: the retrofits act as living examples — if they drift, the gap is visible.

## Open questions

None at design time. Implementation may surface specifics about:

- Whether `hv-vision` Step 2's context-bundle worker should be optional under autonomy `off` mode (the worker's overhead may exceed the savings on small projects). Defer to implementation; the rule allows skipping when "the brief itself would cost more than the work".
- Whether `hv-debug` Step 5 reproduction worker needs a max-output cap to prevent the worker itself from blowing context. Defer to implementation; likely a brief-level constraint.

## Acceptance criteria

1. `references/subagent-dispatch.md` exists with all six sections described above.
2. `references/authoring-conventions.md` has one new numbered rule citing the reference.
3. `hv-next/SKILL.md` dispatches Steps 2/3/4/6 work as a single parallel wave with the four worker briefs specified.
4. `hv-vision/SKILL.md` Step 4 fans out to N research workers; Step 2 uses a single context-bundle worker.
5. `hv-debug/SKILL.md` Step 5 dispatches reproduction to a worker; Step 7 dispatches verification to a worker.
6. No changes to `bin/`, `.hv/`, or `models.*` schema.
7. The coverage table in this spec maps every rule to at least one exemplar.
