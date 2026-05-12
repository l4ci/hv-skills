# Subagent Dispatch Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a cross-skill "dispatch heavy work to subagents" convention via one new reference doc, one citation in `references/authoring-conventions.md`, and three SKILL.md retrofits (`hv-next`, `hv-vision`, `hv-debug`) that serve as worked examples.

**Architecture:** No new helpers, no `bin/` additions, no `.hv/` writes, no `models.*` schema changes. The change is prose: one reference file + one conventions edit + three skill source edits. Each retrofit applies the cost/benefit rule per step rather than blanket-dispatching, so the orchestrator keeps doing cheap work directly and dispatches only when the rule triggers.

**Tech Stack:** Markdown (SKILL.md files, references/*.md), bash smoke tests via `test/runner.sh`, grep-based verification for prose edits.

---

## File Structure

**Create:**
- `references/subagent-dispatch.md` — the six-section rulebook
- `test/sections/21_dispatch_discipline.sh` — smoke section that greps the four authored artifacts for required markers

**Modify:**
- `references/authoring-conventions.md` — append one numbered rule citing the new reference
- `hv-next/SKILL.md` — Steps 2, 3, 4, 6 retrofit (single parallel wave)
- `hv-vision/SKILL.md` — Step 2 (context bundle worker) and Step 4 (research fan-out)
- `hv-debug/SKILL.md` — Step 5 (reproduce worker, conditional) and Step 7 (verify worker, conditional)

**Not touched:** `bin/`, `.hv/`, any other `hv-*/SKILL.md`, `test/runner.sh`, existing smoke sections.

---

## Task 1: Write the dispatch reference doc

**Files:**
- Create: `references/subagent-dispatch.md`

- [ ] **Step 1: Write the failing smoke test**

Create `test/sections/21_dispatch_discipline.sh` with the reference-file checks. The runner discovers sections by glob, so this file becomes active the moment it lands. Initial content (the file is appended to in later tasks):

```bash
echo "subagent-dispatch reference"
# Reference file must exist with all six sections.
[ -f references/subagent-dispatch.md ] || fail "references/subagent-dispatch.md not created"

# Six required section headings.
grep -q "^## When to dispatch" references/subagent-dispatch.md || fail "section 'When to dispatch' missing"
grep -q "^## Small-brief template" references/subagent-dispatch.md || fail "section 'Small-brief template' missing"
grep -q "^## Return-shape contract" references/subagent-dispatch.md || fail "section 'Return-shape contract' missing"
grep -q "^## Model tier per work type" references/subagent-dispatch.md || fail "section 'Model tier per work type' missing"
grep -q "^## Parallel fan-out pattern" references/subagent-dispatch.md || fail "section 'Parallel fan-out pattern' missing"
grep -q "^## What stays on the orchestrator" references/subagent-dispatch.md || fail "section 'What stays on the orchestrator' missing"

# Worktree-isolation cross-reference must be inline (not just a link).
grep -q "DECISIONS.md" references/subagent-dispatch.md || fail "reference must cite .hv/DECISIONS.md worktree-isolation rule"

# No TBD/TODO leftovers.
! grep -qiE "(TBD|TODO|FIXME|XXX)" references/subagent-dispatch.md || fail "reference contains placeholders"

pass "subagent-dispatch reference has all six sections and no placeholders"
```

- [ ] **Step 2: Run the smoke section to verify it fails**

Run: `bash test/runner.sh 21`
Expected: FAIL — `references/subagent-dispatch.md` does not yet exist.

- [ ] **Step 3: Write the reference doc**

Create `references/subagent-dispatch.md`:

```markdown
# Subagent dispatch discipline

Cross-skill rulebook for when and how skills push work into subagents instead of doing it on the orchestrator's main thread. The orchestrator is a dispatcher + synthesizer; reads, scans, summaries, and serial queries belong elsewhere.

Cited by `references/authoring-conventions.md`. Companion to the worktree-isolation rule in `.hv/DECISIONS.md` (the 2026-05-02 entry on `work.isolation` for ≥2 commit-producing parallel workers).

## When to dispatch

Cost/benefit rule, not a vibe.

**Dispatch when:**

- Read-heavy exploration — ≥3 file reads or greps in one step
- Independent parallel work — N items, same operation, no shared mutable state
- Context-polluting tool output — long logs, large diffs, multi-page query results
- Fan-out research — multiple angles on the same question

**Do not dispatch when:**

- ≤2 small reads
- Work depends on context the orchestrator has already loaded
- Step is interactive (`AskUserQuestion`, plain-text fallback, Socratic discovery)
- The brief itself would cost more tokens than the work

## Small-brief template

Briefs say what the orchestrator needs back, not what the orchestrator already knows.

- **Goal** — 1 sentence
- **Inputs** — paths / IDs only, never pasted content
- **Constraints** — relevant forbids + hard boundaries from `.hv/DECISIONS.md`
- **Return shape** — exact structure expected back
- **Word budget** — default ≤200 words

## Return-shape contract

Subagents return synthesis, not transcripts. Structured shape: `findings · decisions · open questions`. The caller treats the return as the source of truth; the worker's working memory is discarded.

## Model tier per work type

- `haiku` — mechanical: parse JSON, count items, format markdown, run a known query and relay its output
- `sonnet` — routine reasoning: summarize a file, classify items, search and synthesize
- `opus` — judgment: verification, design selection, hypothesis evaluation

Read `models.*` from `.hv/config.json` when the skill exposes the keys (`models.orchestrator`, `models.worker`). Haiku usage is opportunistic — declared inline in the brief, not in config.

## Parallel fan-out pattern

When dispatching N independent subagents:

- Issue all `Agent` tool calls in a **single assistant turn** (one message, multiple tool-use blocks) so they run concurrently.
- Independence requirement: no shared mutable state between workers. File disjointness is mandatory; for commit-producing waves the worktree-isolation rule from `.hv/DECISIONS.md` (2026-05-02) applies — under `work.isolation == "branch"`, ≥2 commit-producing parallel workers in one wave is forbidden because they race the shared `.git/index`.
- Aggregation: the orchestrator collects returns and merges per the return-shape contract above. Workers never communicate with each other; the orchestrator is the only synthesizer.

Read-only workers (research, summary, query relays) are exempt from the worktree-isolation guard — they don't touch `.git/`. The guard fires only when ≥2 workers in a single wave are instructed to stage and commit.

## What stays on the orchestrator

- **Decisions** — which approach, which file, which next step.
- **User interaction** — `AskUserQuestion`, plain-text fallback, Socratic flows.
- **Atomic disk writes** — when ordering or all-or-nothing matters.
- **Verification of subagent output** — confirm the return shape, sanity-check claims, reconcile contradictions.

The orchestrator is dispatcher + synthesizer. Never reader-of-everything.
```

- [ ] **Step 4: Run the smoke section to verify it passes**

Run: `bash test/runner.sh 21`
Expected: PASS — all six section greps succeed; no placeholders found.

- [ ] **Step 5: Commit**

```bash
git add references/subagent-dispatch.md test/sections/21_dispatch_discipline.sh
git commit -m "feat(reference): add subagent-dispatch discipline rulebook"
```

---

## Task 2: Cite the reference from authoring-conventions

**Files:**
- Modify: `references/authoring-conventions.md` (append a new section after the existing conventions)
- Modify: `test/sections/21_dispatch_discipline.sh` (append the citation check)

- [ ] **Step 1: Extend the smoke section with the citation check**

Append to `test/sections/21_dispatch_discipline.sh`:

```bash
echo "authoring-conventions citation"
grep -q "^## Dispatch heavy work to subagents" references/authoring-conventions.md \
  || fail "authoring-conventions.md missing 'Dispatch heavy work to subagents' rule"
grep -q "references/subagent-dispatch.md" references/authoring-conventions.md \
  || fail "authoring-conventions.md missing cross-reference to subagent-dispatch.md"
pass "authoring-conventions cites subagent-dispatch reference"
```

- [ ] **Step 2: Run the smoke section to verify it fails**

Run: `bash test/runner.sh 21`
Expected: FAIL — `references/authoring-conventions.md` has no "Dispatch heavy work to subagents" section yet.

- [ ] **Step 3: Append the new convention rule**

Append to `references/authoring-conventions.md` (placement: at end of file, matching the existing trailing-rule pattern):

```markdown

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
```

- [ ] **Step 4: Run the smoke section to verify it passes**

Run: `bash test/runner.sh 21`
Expected: PASS — both reference-doc checks and the new citation checks pass.

- [ ] **Step 5: Commit**

```bash
git add references/authoring-conventions.md test/sections/21_dispatch_discipline.sh
git commit -m "docs(conventions): cite subagent-dispatch discipline rule"
```

---

## Task 3: Retrofit hv-next (Steps 2-6 → one parallel wave)

**Files:**
- Modify: `hv-next/SKILL.md` — replace the per-step bash blocks in Steps 2-6 with a single parallel-wave dispatch block that lives at the top of Step 2
- Modify: `test/sections/21_dispatch_discipline.sh` (append the hv-next retrofit check)

**Context for the implementer:** Steps 2-6 today are sequential bash invocations with some tool-call parallelism (e.g., per-milestone `hv-todo-by-milestone` calls already run in parallel via a single tool-call batch). The retrofit goes one level further: rather than the orchestrator parsing each helper's output, the orchestrator dispatches four subagents (Workers A-D) that run the helpers, parse the output, and return distilled synthesis. The downstream Steps 5-8 still run on the orchestrator and consume the workers' merged synthesis.

- [ ] **Step 1: Extend the smoke section with the hv-next retrofit check**

Append to `test/sections/21_dispatch_discipline.sh`:

```bash
echo "hv-next dispatch wave"
grep -q "Worker A.*reconcile" hv-next/SKILL.md || fail "hv-next missing Worker A (reconcile)"
grep -q "Worker B.*archive" hv-next/SKILL.md || fail "hv-next missing Worker B (archive)"
grep -q "Worker C.*milestone" hv-next/SKILL.md || fail "hv-next missing Worker C (milestone)"
grep -q "Worker D.*relevance" hv-next/SKILL.md || fail "hv-next missing Worker D (relevance)"
grep -q "single parallel wave" hv-next/SKILL.md || fail "hv-next missing 'single parallel wave' phrasing"
grep -q "references/subagent-dispatch.md" hv-next/SKILL.md || fail "hv-next missing reference cite"
pass "hv-next retrofitted with parallel dispatch wave"
```

- [ ] **Step 2: Run the smoke section to verify it fails**

Run: `bash test/runner.sh 21`
Expected: FAIL — `hv-next/SKILL.md` does not yet describe Workers A-D.

- [ ] **Step 3: Edit hv-next/SKILL.md — replace the head of Step 2**

In `hv-next/SKILL.md`, replace the current Step 2 opening (the `.hv/bin/hv-reconcile` block through the `needsAction` description) with a parallel-wave introduction. Insert the new dispatch block immediately after the `## Step 2 — Reconcile Active Work` heading, before the existing handoff-reading paragraphs (which stay):

```markdown
## Step 2 — Reconcile Active Work

**Dispatch the Steps 2-6 read-heavy work as a single parallel wave.** Per `references/subagent-dispatch.md`, the reconcile + archive + per-milestone summary + relevance-query work is four independent operations on disjoint inputs. The orchestrator dispatches four workers in one tool-call batch and merges their returns before Step 5's backlog presentation.

| Worker | Model | Inputs | Returns |
|--------|-------|--------|---------|
| **A — Reconcile** | sonnet | `status.json`, git refs | `{still-active, done, drift}` from `.hv/bin/hv-reconcile` output |
| **B — Archive scan** | haiku | `TODO.md`, `archive.ttl` config | List of completion-dated entries past TTL (runs `.hv/bin/hv-archive-old 5`, returns count + IDs moved) |
| **C — Milestones** | sonnet | `MILESTONES.md`, `.hv/milestones/M*.md`, active IDs from `hv-vision-active` | `milestone → remaining map` (per active milestone: ID set from `hv-todo-by-milestone`, slice summary) |
| **D — Relevance** | sonnet | Top-N candidate IDs from current `TODO.md` sorted by `hv-backlog`, plus topic strings from each candidate | Relevance map: `{candidate ID → matching knowledge bullets, decisions, context terms}` via the canonical K+D query pattern (`references/knowledge-consult.md`) |

Each brief uses the small-brief template from the reference: Goal · Inputs (paths/IDs only) · Constraints (cite the worktree-isolation rule when commit-producing waves are involved, though this wave is read-only) · Return shape (the table above) · Word budget ≤200 words.

Aggregate the four returns into the working state used by Steps 3-6: drift IDs feed the "[ID] looks shipped on <hash>" lines below; archive output is silent (already moved); milestone map feeds the Step 5 header and the Step 6 milestone-bias check; relevance map feeds the Step 6 Suggested Next reasoning.
```

Then preserve the existing Step 2 content (handoff reading, loop-mode routing, AskUserQuestion flow, plain-text fallback) below this new dispatch block — that content stays on the orchestrator because it's interactive (per the reference's "What stays on the orchestrator" section). The handoff-reading paragraph that already says "Issue the resolve+read pairs in parallel" stays unchanged.

Also remove from Step 4 the paragraph that begins `Carry the per-milestone ID set forward. Step 3 (...), Step 4 (...), and Step 5's hv-backlog can also share the same parallel batch` — that tool-call-batch optimization is superseded by the worker wave at the top of Step 2 (the orchestrator no longer runs those Bash calls directly). Replace with: *"The per-milestone ID set arrives from Worker C; Step 5's `hv-backlog` runs on the orchestrator after the wave returns, since its output is presented verbatim and doesn't benefit from worker synthesis."*

- [ ] **Step 4: Run the smoke section to verify it passes**

Run: `bash test/runner.sh 21`
Expected: PASS — the four worker grep lines all match.

- [ ] **Step 5: Run the full smoke suite to verify no regression**

Run: `bash test/runner.sh`
Expected: All sections pass. (The existing hv-next behavior tests — sections that exercise `hv-reconcile`, `hv-archive-old`, etc. — should be unaffected because the helpers themselves are unchanged.)

- [ ] **Step 6: Commit**

```bash
git add hv-next/SKILL.md test/sections/21_dispatch_discipline.sh
git commit -m "feat(hv-next): dispatch Steps 2-6 read work as parallel worker wave"
```

---

## Task 4: Retrofit hv-vision (Step 2 + Step 4)

**Files:**
- Modify: `hv-vision/SKILL.md` — Step 2 (single haiku worker for context bundling) and Step 4 (fan-out research workers)
- Modify: `test/sections/21_dispatch_discipline.sh` (append the hv-vision retrofit check)

**Context for the implementer:** Step 2 already issues the context reads as parallel tool calls, but the orchestrator parses and retains them all. The retrofit hands the same reads to a haiku worker that returns a compact snapshot, so the orchestrator carries the synthesis (1-2 paragraphs) instead of the raw text of every file. Step 4 today runs 2-4 `WebSearch` calls in parallel on the orchestrator; the retrofit dispatches one sonnet worker per research angle, each owning its searches and returning a ≤200-word synthesis.

- [ ] **Step 1: Extend the smoke section with the hv-vision retrofit check**

Append to `test/sections/21_dispatch_discipline.sh`:

```bash
echo "hv-vision dispatch retrofits"
grep -q "context-bundle worker" hv-vision/SKILL.md || fail "hv-vision Step 2 missing context-bundle worker"
grep -q "haiku" hv-vision/SKILL.md || fail "hv-vision Step 2 missing haiku tier"
grep -q "research worker" hv-vision/SKILL.md || fail "hv-vision Step 4 missing research worker dispatch"
grep -q "per angle" hv-vision/SKILL.md || fail "hv-vision Step 4 missing per-angle fan-out"
grep -q "references/subagent-dispatch.md" hv-vision/SKILL.md || fail "hv-vision missing reference cite"
pass "hv-vision retrofitted with context-bundle + research fan-out workers"
```

- [ ] **Step 2: Run the smoke section to verify it fails**

Run: `bash test/runner.sh 21`
Expected: FAIL — `hv-vision/SKILL.md` does not yet describe the workers.

- [ ] **Step 3: Edit hv-vision/SKILL.md — Step 2 (context bundle)**

In `hv-vision/SKILL.md`, replace the last paragraph of Step 2 (the one beginning `**Issue these as parallel tool calls in a single response**`) with:

```markdown
**Dispatch a context-bundle worker** rather than issuing the reads on the orchestrator. Per `references/subagent-dispatch.md`, this step is read-heavy (≥3 file reads — `.hv/MILESTONES.md`, every `.hv/milestones/M*.md`, `.hv/TODO.md`, `.hv/CONTEXT.md` query results, plus the root stack file) and the orchestrator only needs synthesis to do Step 3, not the raw text.

Brief (haiku tier — this is mechanical aggregation):

- **Goal:** Return a compact snapshot of the project's vision state.
- **Inputs:** `.hv/MILESTONES.md`, `.hv/milestones/M*.md`, `.hv/TODO.md`, `README.md` (or whichever stack file exists), plus the output of `.hv/bin/hv-knowledge-query`, `.hv/bin/hv-decisions-query`, and `.hv/bin/hv-context-query` for vision-relevant topics (the orchestrator selects topics from the user's framing).
- **Constraints:** Surface any DECISIONS conflict explicitly in the snapshot — committed boundaries that constrain milestone proposals must be visible to the orchestrator before Step 3.
- **Return shape:** `{vision-paragraph, existing-milestones[], gaps[], hard-boundaries[], context-terms[]}` — bullets, not paragraphs, ≤200 words total.
- **Word budget:** ≤200 words.

The orchestrator uses the snapshot to ground the Step 3 framing paragraph. Definitional signals from the user (*"by X I mean…"*) still trigger inline `hv-context-add` writes on the orchestrator — that's a write, which stays per the reference.
```

- [ ] **Step 4: Edit hv-vision/SKILL.md — Step 4 (research fan-out)**

In `hv-vision/SKILL.md`, replace the second paragraph of Step 4 (the one beginning `Run 2-4 searches max — depth over breadth.`) with:

```markdown
**Dispatch one research worker per angle** rather than running `WebSearch` calls on the orchestrator. Per `references/subagent-dispatch.md`, multi-angle research is fan-out work — angles are independent by definition, and each one produces its own block of `WebSearch` / `WebFetch` output that the orchestrator doesn't need to retain after synthesis.

The orchestrator decomposes the framing from Step 3 into 3-5 research angles (by judgment, not a fixed count) — typically: competitive landscape, technical feasibility, user-need patterns, adjacent prior art. Dispatch one sonnet worker per angle in a single tool-call batch.

Per-worker brief:

- **Goal:** Return actionable findings on `<angle>` relevant to the project's framing.
- **Inputs:** The framing summary from Step 3 (one paragraph), the angle name, and the project's apparent type.
- **Constraints:** Findings must be **actionable** — *"pitfall to avoid in M01"*, *"pattern worth borrowing"*, *"competitor's mistake"*. Generic observations get cut. Cite sources.
- **Return shape:** 3-5 findings, each: `{finding (one sentence), citation (URL + title), so-what (why it matters for milestone design)}`.
- **Word budget:** ≤200 words per worker.

After all workers return, the orchestrator merges to 3-5 concrete findings total (deduplicate across angles, keep the sharpest framing). Present inline with citations as the existing prose specifies. If an angle yields nothing useful, say so and move on.

Findings that contradict the user's current framing get held for Step 5 Challenge — that's the highest-yield input.
```

- [ ] **Step 5: Run the smoke section to verify it passes**

Run: `bash test/runner.sh 21`
Expected: PASS — hv-vision worker greps match.

- [ ] **Step 6: Run the full smoke suite to verify no regression**

Run: `bash test/runner.sh`
Expected: All sections pass. (Section 12 — hv-vision — should still pass; its tests exercise helper behavior, not SKILL.md text.)

- [ ] **Step 7: Commit**

```bash
git add hv-vision/SKILL.md test/sections/21_dispatch_discipline.sh
git commit -m "feat(hv-vision): dispatch context bundle (Step 2) + research angles (Step 4) to workers"
```

---

## Task 5: Retrofit hv-debug (Step 5 + Step 7)

**Files:**
- Modify: `hv-debug/SKILL.md` — Step 5 (conditional reproduce dispatch) and Step 7 (conditional verify dispatch)
- Modify: `test/sections/21_dispatch_discipline.sh` (append the hv-debug retrofit check)

**Context for the implementer:** Unlike hv-next and hv-vision Step 4, dispatch in hv-debug is **conditional** on the cost/benefit rule. Cheap repros (run an existing test, capture a 10-line stack trace) and trivial verifications (read two lines of code) stay on the orchestrator — the brief would cost more than the work. The retrofit defines the criteria for when to dispatch, not a blanket rule. Step 6 (Hypothesize) already uses dispatch via `competingHypotheses` and is left untouched.

- [ ] **Step 1: Extend the smoke section with the hv-debug retrofit check**

Append to `test/sections/21_dispatch_discipline.sh`:

```bash
echo "hv-debug dispatch retrofits"
grep -q "reproduce worker" hv-debug/SKILL.md || fail "hv-debug Step 5 missing reproduce worker"
grep -q "verification worker" hv-debug/SKILL.md || fail "hv-debug Step 7 missing verification worker"
# Conditional language must be explicit — these are not blanket dispatches.
grep -q -i "when the repro is heavy" hv-debug/SKILL.md || fail "hv-debug Step 5 missing conditional dispatch criteria"
grep -q -i "when verification.*requires.*file reads" hv-debug/SKILL.md || fail "hv-debug Step 7 missing conditional dispatch criteria"
grep -q "references/subagent-dispatch.md" hv-debug/SKILL.md || fail "hv-debug missing reference cite"
pass "hv-debug retrofitted with conditional reproduce + verify workers"
```

- [ ] **Step 2: Run the smoke section to verify it fails**

Run: `bash test/runner.sh 21`
Expected: FAIL — neither Step 5 nor Step 7 yet describes workers.

- [ ] **Step 3: Edit hv-debug/SKILL.md — Step 5 (conditional reproduce worker)**

In `hv-debug/SKILL.md`, after the existing Step 5 list (options 1-3) and before the "Don't proceed to Step 6 without a concrete failure signal" line, insert:

```markdown
**Dispatch a reproduce worker when the repro is heavy** — multi-MB output, multiple manual setup steps, or generating a failing test from scratch. Per `references/subagent-dispatch.md`, cheap repros (running an existing test that prints a 10-line stack trace, observing a single error in the dev server) stay on the orchestrator because the brief would cost more than the work.

When the dispatch criterion fires, brief one sonnet worker:

- **Goal:** Reproduce `[B##]` and return a concrete failure signal.
- **Inputs:** The bug ID, the symptom description from the TODO entry, suspected file paths, the repro path (which option from 1-3 above).
- **Constraints:** Return a structured verdict; do not propose a fix.
- **Return shape:** `{reproduced: bool, observed-vs-expected, relevant-log-excerpts (≤30 lines, the load-bearing ones)}`.
- **Word budget:** ≤200 words plus the log excerpts.

The orchestrator uses the worker's verdict as the Step 6 brief's **Symptom:** field. The full log stays in the worker's context, not the orchestrator's.
```

- [ ] **Step 4: Edit hv-debug/SKILL.md — Step 7 (conditional verification worker)**

In `hv-debug/SKILL.md`, after the existing Step 7 body (the two paragraphs about running the verification probe and fix-and-pray) and before Step 7.5, insert:

```markdown
**Dispatch a verification worker when verification itself requires file reads, searches across the codebase, or running a non-trivial test.** Per `references/subagent-dispatch.md`, single-line verifications (read one specific line and confirm a value) stay on the orchestrator because the brief would cost more than the read.

When the dispatch criterion fires, brief one worker. Model tier follows the verification shape:

- **opus** when the verdict requires judgment — *"does this code actually implement the claimed invariant?"*, *"is this contract upheld under the race window?"*.
- **sonnet** when verification is pattern-matching across reads — *"does this symbol appear in any of these N files with the expected shape?"*.

Brief:

- **Goal:** Verify hypothesis `<hypothesis statement from Step 6>`.
- **Inputs:** The hypothesis, the specific verification probe (code paths to read, test to run, trace to inspect), the file:line evidence from Step 6.
- **Constraints:** Return a verdict, not a fix. If verification fails, surface the new evidence that disproves the hypothesis.
- **Return shape:** `{verdict: confirmed|disproved|inconclusive, evidence-citations[]: {file, line, snippet}, new-evidence (if disproved): what the worker found that contradicts the hypothesis}`.
- **Word budget:** ≤200 words.

If the verdict is `disproved`, the orchestrator returns to Step 6 with the new evidence (which re-runs the cycle-counter check and routes to Step 7.5 on the 3rd cycle) — the existing behavior is unchanged; the worker is the new input source.
```

- [ ] **Step 5: Run the smoke section to verify it passes**

Run: `bash test/runner.sh 21`
Expected: PASS — both Step 5 and Step 7 retrofit greps match, including the conditional-dispatch language.

- [ ] **Step 6: Run the full smoke suite to verify no regression**

Run: `bash test/runner.sh`
Expected: All sections pass.

- [ ] **Step 7: Commit**

```bash
git add hv-debug/SKILL.md test/sections/21_dispatch_discipline.sh
git commit -m "feat(hv-debug): conditionally dispatch reproduce (Step 5) + verify (Step 7) to workers"
```

---

## Task 6: Final cross-cutting smoke + spec coverage check

**Files:**
- No edits in this task; verification only.

- [ ] **Step 1: Run the full smoke suite**

Run: `bash test/runner.sh`
Expected: All sections pass, including the new section 21.

- [ ] **Step 2: Verify spec acceptance criteria 1-7 from the design doc**

Read `docs/superpowers/specs/2026-05-12-subagent-dispatch-discipline-design.md` lines under "## Acceptance criteria" (numbered 1-7) and confirm each is satisfied:

1. Six sections in `references/subagent-dispatch.md`: `grep -c '^## ' references/subagent-dispatch.md` → expect 6
2. Authoring-conventions rule: `grep -q '## Dispatch heavy work to subagents' references/authoring-conventions.md`
3. hv-next four workers: smoke section 21 already covers this
4. hv-vision Step 4 fan-out + Step 2 bundle: smoke covers this
5. hv-debug Step 5 + Step 7 workers: smoke covers this
6. No changes to `bin/`, `.hv/`, `models.*`: `git diff --name-only main..HEAD | grep -E '^(bin/|.hv/)'` → empty; `git diff main..HEAD -- '*config*'` → no `models.*` changes
7. Coverage table in spec maps every rule to an exemplar: already written into the spec at design time; no implementation action.

- [ ] **Step 3: Sanity check — read each retrofitted skill end-to-end**

For each of `hv-next/SKILL.md`, `hv-vision/SKILL.md`, `hv-debug/SKILL.md`, read the modified file top to bottom and confirm:

- The new dispatch block reads cleanly in context (no broken transitions).
- Pre-existing parallel-tool-call language hasn't been left as a contradiction (e.g., the old "Issue these as parallel tool calls" paragraph in hv-vision Step 2 must be gone, replaced by the worker dispatch).
- The Step ordering and decimal-step numbering rules (per `references/authoring-conventions.md`) are preserved — no new decimal steps introduced.

- [ ] **Step 4: Final commit (if any cleanup edits were needed in Step 3)**

If Step 3 surfaced any cleanup edits, apply them and commit:

```bash
git add hv-*/SKILL.md
git commit -m "polish(skills): smooth dispatch-retrofit transitions"
```

If no cleanup needed, skip this step.

---

## Self-review notes

**Spec coverage:** All seven acceptance criteria from the design doc map to specific tasks above (Task 1 → criterion 1; Task 2 → criterion 2; Task 3 → criterion 3; Task 4 → criterion 4; Task 5 → criterion 5; Task 6 → criteria 6 and 7).

**Placeholder scan:** No TBD/TODO in any task body. Every step has either a concrete file path + content or a concrete command + expected output.

**Type consistency:** Worker labels (A/B/C/D) used in hv-next match across the design doc, the plan, and the smoke greps. Return-shape strings (`{still-active, done, drift}`, `{reproduced, observed-vs-expected, ...}`, etc.) match the design doc.

**Dispatch nuance:** hv-debug retrofits are explicitly conditional (Task 5 smokes test for "when the repro is heavy" / "when verification ... requires file reads") because cheap repros and trivial verifications shouldn't dispatch. This matches the cost/benefit rule in the reference.

**Independence:** Tasks 3, 4, 5 are independent — they edit disjoint files (`hv-next/`, `hv-vision/`, `hv-debug/`). If executed via subagent-driven development or `/hv-work`, they can run in parallel under worktree isolation per the `.hv/DECISIONS.md` 2026-05-02 rule. Tasks 1 and 2 are sequential dependencies (Task 2's smoke test assumes Task 1's reference file exists).
