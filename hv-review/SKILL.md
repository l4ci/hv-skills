---
name: hv-review
description: Staff-engineer review of a feature branch before merge or PR — reads commits, diff, referenced item IDs, and matching KNOWLEDGE.md topics; dispatches an Opus reviewer that checks intent match, convention compliance, and quality. Returns PASS / CONCERNS / FAIL. Use on "review this", "check before I ship", "look over the branch", or implicitly from /hv-ship.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🔍  hv-review  ·  staff-engineer review of a branch
  triggers: "review this", "check before ship"  ·  pairs: hv-ship
════════════════════════════════════════════════════════════════════════
```

# hv-review — Pre-Merge Review

## Configuration

Read `.hv/config.json`:

- `models.orchestrator` — model for the reviewer (default `opus`)

## When to Use

- Before merging or opening a PR — typically invoked from `/hv-ship`
- *"Review this branch"*, *"Second-opinion this"*, *"Look over what I've got"*
- After manual commits to a branch you want validated before integrating

## When NOT to Use

- Code is still in flight → finish implementing via `/hv-work`
- You want to change code based on the review → `/hv-refactor` or a fresh `/hv-work` run
- Nothing committed yet → there's nothing to review
- You want product-level evidence (does it actually work? perf budgets met? a11y clean? smoke tests green?) → `/hv-qa run`. `/hv-review` reasons from commits and diff; it does not run the product.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Read commits and items* — branch range walked, referenced item IDs collected (Step 2)
2. *Resolve plans* — milestone-keyed `.hv/plans/<milestone>-<ID>.md` located for each referenced item (Step 3)
3. *Capture context* — diff, KNOWLEDGE / DECISIONS topics, scaffolding pre-scan (Steps 4, 5, 6)
4. *Stage 1 — Spec compliance* — diff evaluated against `PLAN.md` outcomes; short-circuit on FAIL (Step 7)
5. *Stage 2 — Code quality* — staff-engineer review, gated on Stage 1 PASS or CONCERNS (Step 8)
6. *Verdict* — combined PASS / CONCERNS / FAIL with structured findings (Step 9)
7. *Knowledge lifecycle* — register hits on consumed bullets via hv-knowledge-hit (Step 4)

**Stage opt-out (power users).** When invoked with `--stage spec`, run only Stage 1 (Steps 2, 3, 5, 7) and skip Step 8. When invoked with `--stage quality`, skip Steps 3 and 7 and run only Stage 2 — the legacy single-pass behavior. No `--stage` arg = run both stages with short-circuit gating (the default).

## Step 2 — Scope the Review

```bash
.hv/bin/hv-review-scope <branch>
```

**Umbrella mode.** When the branch lives in a sub-repo, pass `--repo <name>` so git ops resolve there: `.hv/bin/hv-review-scope --repo <name> <branch>`. Determine `<name>` from the active stream's `repo` field in `.hv/status.json` (single match), or from `hv-resolve-repo` if invoked from inside the sub-repo's worktree. `BACKLOG.md` / `ARCHIVE.md` lookups stay umbrella-flat — `hv-review-scope` reads them from the umbrella's `.hv/`, so no repo flag is needed for intent matching.

If the user didn't name a branch, default to the current one. `hv-review-scope` emits JSON with:

- `branch`, `base`, `commitCount`
- `commits` — array of `{hash, subject}`
- `touchedFiles` — paths changed vs base
- `referencedIds` — `[B##]`/`[F##]`/`[T##]` found in commit messages
- `intents` — matched TODO entries for each referenced ID

If `commitCount` is 0, stop and tell the user.

## Step 3 — Resolve Plans for Referenced Items

For each `intent` in the scope JSON's `intents` array, resolve its milestone-keyed plan if one exists. The plan content is Stage 1's input alongside the diff.

```bash
# For each <ID> in referencedIds:
MILESTONE=$(.hv/bin/hv-todo-field <ID> milestone)
[ -n "$MILESTONE" ] && .hv/bin/hv-plan-show "${MILESTONE}-<ID>" 2>/dev/null
```

Issue the `hv-todo-field` and `hv-plan-show` calls in parallel — one pair per `referencedId` — and collect a `plans` map: `{ID -> plan-content-or-empty}`. Untagged items (no `Milestone:` field) and items with no plan file produce empty entries — those items don't contribute to Stage 1.

**No-plan fallback.** If every entry in `plans` is empty (no referenced item has a plan file), Stage 1 cannot run as a meaningful spec check. Print one informational line — *"No plans found for referenced items; skipping Stage 1 (spec compliance). Running Stage 2 only."* — and proceed directly to Step 4 (effectively `--stage quality` behavior). The user may have skipped `/hv-plan` for this branch (e.g. `/hv-go` shortcut); that's legitimate, not an error.

When `--stage quality` is set, skip this step entirely — Stage 1 won't run.

## Step 4 — Consult KNOWLEDGE & DECISIONS

Apply the canonical K+D query pattern (`references/knowledge-consult.md`) with topics that plausibly touch the changed areas based on `touchedFiles` and commit subjects — infer liberally (e.g., a file under `Networking/` → the `Networking` topic).

Carry KNOWLEDGE bullets into the reviewer brief. Pass DECISIONS entries under a `**Hard boundaries:**` section — the reviewer must **FAIL** if the diff violates any boundary, even if the change looks otherwise good.

**Register hits on consumed bullets (F03 lifecycle).** For every bullet `hv-knowledge-query` returned that gets carried into the reviewer brief's `**Relevant project conventions (from KNOWLEDGE.md):**` section, call `.hv/bin/hv-knowledge-hit --topic <T> --title <S>` once. The helper increments the hit counter; provisional bullets auto-promote to confirmed once they reach `learn.promoteThreshold` (default 3) hits without a pending contradiction. Issue the hit calls as parallel tool calls in a single batch — they're independent and bash-bound. Bullets returned by the query but pruned from the brief (the reviewer didn't need them) don't earn a hit. Silent on success.

## Step 5 — Capture the Diff

The reviewer needs concrete diff content, not just file names. For each touched file (up to 8; with 9 or more, ask the user which to focus on):

```bash
git diff <base>...<branch> -- <file>
```

**Issue all the per-file `git diff` calls in parallel** — they're independent and serial calls add up fast on bigger branches. Keep a per-file diff map in memory for the reviewer brief.

## Step 6 — Pre-flight Scaffolding Scan

Multi-task feature branches sometimes ship comments that referenced earlier task numbers ("Umbrella behavior is added in Task 7 — for now --repo is parsed but ignored") even after the referenced task completed. Before dispatching the reviewer, run a deterministic diff scan:

```bash
.hv/bin/hv-review-scaffolding [--repo <name>] <base> <branch>
```

Empty stdout → no candidates, skip ahead to Step 7. Non-empty stdout → carry the matches forward as `**Possible stale scaffolding:**` evidence in the Stage 2 reviewer brief (Step 8). Do not auto-FAIL — the reviewer judges each match as real scaffolding or legitimate prose. The helper surfaces; the reviewer decides.

## Step 7 — Stage 1: Dispatch Spec-Compliance Reviewer

Skip this step entirely when `--stage quality` is set, OR when Step 3's `plans` map is empty (no-plan fallback already printed).

Dispatch a focused spec-compliance reviewer using the **orchestrator** model. Stage 1 has a narrow input: the diff + the resolved `PLAN.md` content per referenced item. KNOWLEDGE / DECISIONS / scaffolding stay out of this brief — Stage 1 answers *"does the diff fulfill what the plan promised?"* and nothing else. Shorter brief, smaller token budget, faster verdict.

Brief template:

```
Stage 1 / 2 — spec compliance review of `<branch>` against base `<base>`.

You evaluate ONE question: does the diff fulfill the outcomes promised by the plan(s)?

You do NOT evaluate code quality, style, conventions, security, or scaffolding —
that's Stage 2's job. Even if you notice issues there, do NOT flag them.

**Commits:**
<hash> <subject>
<hash> <subject>
...

**Items being resolved (with plans):**

### [F03] Quick-switch projects
**Intent (from BACKLOG.md):** "<full intent line>"

**Plan outcomes (from .hv/plans/M01-F03.md):**
<plan content>

### [B07] Timer badge shows stale duration
**Intent:** "<full intent line>"

**Plan outcomes (from .hv/plans/M01-B07.md):**
<plan content>

(Omit a plan section for items without plans — note them as "no plan; skipped from spec check.")

**Diff by file:**
<file>
```diff
<diff content>
```
...

**Evaluate per item:**
For each item with a plan, return PASS / CONCERN / FAIL with evidence:
- **PASS** — every outcome in the plan is fulfilled by the diff. Cite the diff line(s) for each.
- **CONCERN** — most outcomes fulfilled, but one or more partially met (stub, incomplete coverage, missing test for a named outcome). Cite the gap.
- **FAIL** — at least one plan outcome is missing entirely OR the diff went off-target (touched files not implied by the plan, scope creep into unrelated areas). Cite the missed outcome AND the off-target evidence.

**Final verdict** (last line, all caps): SPEC-PASS | SPEC-CONCERNS | SPEC-FAIL
- SPEC-PASS — every plan-bearing item delivered what its plan promised
- SPEC-CONCERNS — works, but plan-vs-diff gaps surfaced
- SPEC-FAIL — at least one plan outcome went un-fulfilled or the diff went off-target
```

**Parse the verdict** from the last all-caps line. Three routes:

| Verdict | Route |
|---------|-------|
| `SPEC-PASS` | Continue to Step 8 (Stage 2). Carry the per-item evidence forward into the final report. |
| `SPEC-CONCERNS` | Continue to Step 8 (Stage 2). The combined verdict in Step 9 may still be CONCERNS or FAIL depending on Stage 2's findings — Stage 1 concerns alone don't decide the merge. |
| `SPEC-FAIL` | **Short-circuit.** Skip Step 8 entirely. Jump to Step 9 to emit a Stage-1-only verdict block. Stage 2 doesn't run — no point burning a deeper review on a diff that doesn't match intent. |

When `--stage spec` is set, always jump to Step 9 after Stage 1 (no Stage 2 regardless of verdict).

## Step 8 — Stage 2: Dispatch Code-Quality Reviewer

Skip this step entirely when `--stage spec` is set, OR when Stage 1 returned `SPEC-FAIL` (short-circuit applied in Step 7).

Dispatch a single code-quality reviewer using the **orchestrator** model. Stage 2 owns code quality, conventions, stale scaffolding, and silent-failure detection. Intent / spec compliance lives in Stage 1 and is NOT re-evaluated here — the brief tells the reviewer to skip it.

**Use Variant A when Stage 1 ran (SPEC-PASS or SPEC-CONCERNS). Use Variant B when Stage 1 was skipped (no-plan fallback or `--stage quality`).**

### Variant A — Stage 2 with Stage 1 (Stage 1 ran with SPEC-PASS or SPEC-CONCERNS)

```
Stage 2 / 2 — code-quality review of `<branch>` against base `<base>`.

Stage 1 (spec compliance) already evaluated whether the diff fulfills the
promised plan outcomes — DO NOT re-evaluate intent here. Stage 1's verdict
is provided for context but is not your concern. Focus on quality:
conventions, edge cases, security smells, performance cliffs, stale
scaffolding, silent failures.

**Stage 1 verdict (context — do not re-evaluate):**
<SPEC-PASS or SPEC-CONCERNS — paste the Stage 1 evidence block verbatim>

**Commits:**
<hash> <subject>
<hash> <subject>
...

**Items being resolved:**
- [B07] Timer badge shows stale duration — "<full intent line from TODO>"
- [F03] Quick-switch projects — "<full intent line from TODO>"

**Relevant project conventions (from KNOWLEDGE.md):**
- <bullet 1>
- <bullet 2>

**Hard boundaries (from DECISIONS.md):**
<entries from hv-decisions-query, if any — full rule + forbids/permits>

**Possible stale scaffolding (deterministic pre-flight grep):**
<file:line>: <matched line text>
<file:line>: <matched line text>
...

(Omit this section entirely when Step 6 produced no matches.)

**Diff by file:**
<file>
```diff
<diff content>
```
...

**Evaluate on the rubric below. For each item, return PASS / CONCERN / FAIL with evidence.**

1. **Convention compliance** — does the diff respect the bullets from KNOWLEDGE.md? Any regressions on captured gotchas?
2. **Obvious quality** — dead code, error swallowing, untested new branches, security smells, API contract breaks, performance cliffs. Not a full code review; focus on things the user would regret after merge.
3. **Stale scaffolding** — for each entry in `**Possible stale scaffolding:**`, judge whether the matched line is a leftover *Task N* / *placeholder* / *not yet wired* / *added later* / *in flight* annotation that should have been removed once the corresponding work landed. Flag as CONCERN with the file:line if it reads like leftover scaffolding; PASS-and-skip if it's legitimate prose (e.g., a markdown placeholder section, a docstring describing user-visible "in flight" semantics, an enum value named `placeholder`, or a `Task <N>` mention in a per-task brief or test name). Many matches will be benign — the helper surfaces candidates, not verdicts.
4. **Silent failure check** — for every verification claim in the diff (new test, smoke section, assertion, helper-output check), apply the four-question rubric: (a) what does this verify concretely? (b) is the asserted-on shape the same shape the real consumer reads? (c) was the new code path actually exercised? (d) if you deleted the new code, would the assertion still pass? If any answer is *no* or *unclear*, flag the claim as `SILENT-FAIL` with file:line and a one-sentence explanation. Treat `SILENT-FAIL` flags as CONCERNS in the verdict — they don't break the build alone, but the user sees them before merging. Full rubric and patterns in `references/silent-failure-hunter.md`.
- **Decision violations.** Compare the diff against the `**Hard boundaries:**` block above. Any forbidden pattern present in the diff = FAIL.

Return verdict as labeled sections. Be specific: file:line for every concern. Rank concerns by severity.

**Final verdict** (on the last line, all caps): QUALITY-PASS | QUALITY-CONCERNS | QUALITY-FAIL
- QUALITY-PASS — no concerns worth surfacing
- QUALITY-CONCERNS — works, but surfaces should be flagged before merge
- QUALITY-FAIL — merge would regress behavior, violate a hard boundary, or break a convention
```

### Variant B — Stage 2 standalone (Stage 1 was skipped via no-plan fallback or `--stage quality`)

```
Stage 2 / 2 — code-quality review of `<branch>` against base `<base>`.

Stage 1 (spec compliance) was skipped for this review. Evaluate intent
match as the first rubric item, then assess quality: conventions, edge
cases, security smells, performance cliffs, stale scaffolding, silent
failures.

**Commits:**
<hash> <subject>
<hash> <subject>
...

**Items being resolved:**
- [B07] Timer badge shows stale duration — "<full intent line from TODO>"
- [F03] Quick-switch projects — "<full intent line from TODO>"

**Relevant project conventions (from KNOWLEDGE.md):**
- <bullet 1>
- <bullet 2>

**Hard boundaries (from DECISIONS.md):**
<entries from hv-decisions-query, if any — full rule + forbids/permits>

**Possible stale scaffolding (deterministic pre-flight grep):**
<file:line>: <matched line text>
<file:line>: <matched line text>
...

(Omit this section entirely when Step 6 produced no matches.)

**Diff by file:**
<file>
```diff
<diff content>
```
...

**Evaluate on the rubric below. For each item, return PASS / CONCERN / FAIL with evidence.**

1. **Intent match** — does the diff deliver what the TODO entries promise? Anything missing, anything scope-creeping?
2. **Convention compliance** — does the diff respect the bullets from KNOWLEDGE.md? Any regressions on captured gotchas?
3. **Obvious quality** — dead code, error swallowing, untested new branches, security smells, API contract breaks, performance cliffs. Not a full code review; focus on things the user would regret after merge.
4. **Stale scaffolding** — for each entry in `**Possible stale scaffolding:**`, judge whether the matched line is a leftover *Task N* / *placeholder* / *not yet wired* / *added later* / *in flight* annotation that should have been removed once the corresponding work landed. Flag as CONCERN with the file:line if it reads like leftover scaffolding; PASS-and-skip if it's legitimate prose (e.g., a markdown placeholder section, a docstring describing user-visible "in flight" semantics, an enum value named `placeholder`, or a `Task <N>` mention in a per-task brief or test name). Many matches will be benign — the helper surfaces candidates, not verdicts.
5. **Silent failure check** — for every verification claim in the diff (new test, smoke section, assertion, helper-output check), apply the four-question rubric: (a) what does this verify concretely? (b) is the asserted-on shape the same shape the real consumer reads? (c) was the new code path actually exercised? (d) if you deleted the new code, would the assertion still pass? If any answer is *no* or *unclear*, flag the claim as `SILENT-FAIL` with file:line and a one-sentence explanation. Treat `SILENT-FAIL` flags as CONCERNS in the verdict — they don't break the build alone, but the user sees them before merging. Full rubric and patterns in `references/silent-failure-hunter.md`.
- **Decision violations.** Compare the diff against the `**Hard boundaries:**` block above. Any forbidden pattern present in the diff = FAIL.

Return verdict as labeled sections. Be specific: file:line for every concern. Rank concerns by severity.

**Final verdict** (on the last line, all caps): QUALITY-PASS | QUALITY-CONCERNS | QUALITY-FAIL
- QUALITY-PASS — no concerns worth surfacing
- QUALITY-CONCERNS — works, but surfaces should be flagged before merge
- QUALITY-FAIL — merge would regress behavior, violate a hard boundary, or break a convention
```

## Step 9 — Combine Verdicts and Relay

Compute the combined verdict from Stage 1's `SPEC-*` and Stage 2's `QUALITY-*` outputs. Worst-of mapping — FAIL beats CONCERNS beats PASS:

| Stage 1 | Stage 2 | Combined |
|---------|---------|----------|
| SPEC-FAIL | (skipped — short-circuit) | **FAIL** |
| SPEC-PASS | QUALITY-PASS | **PASS** |
| SPEC-PASS | QUALITY-CONCERNS | **CONCERNS** |
| SPEC-PASS | QUALITY-FAIL | **FAIL** |
| SPEC-CONCERNS | QUALITY-PASS | **CONCERNS** |
| SPEC-CONCERNS | QUALITY-CONCERNS | **CONCERNS** |
| SPEC-CONCERNS | QUALITY-FAIL | **FAIL** |

When a single stage ran (`--stage spec` / `--stage quality` / no-plan fallback), strip the prefix from that stage's verdict: `SPEC-PASS` → `PASS`, `QUALITY-CONCERNS` → `CONCERNS`, etc.

Present both stages' outputs **verbatim** (or nearly so — trim only restatements). Stage 1 first, then Stage 2, then the combined verdict. Don't summarize away the evidence; specifics are the point. When Stage 2 was short-circuited, mark it `Skipped (Stage 1 returned SPEC-FAIL)` in the output block.

Structure:

```
Review: `hv/foo` → main (3 commits, 5 files)

## Stage 1 — Spec Compliance — SPEC-PASS

### [F03] Quick-switch projects — PASS
<evidence: each plan outcome ↔ diff line(s)>

### [B07] Timer badge — PASS
<evidence>

## Stage 2 — Code Quality — QUALITY-CONCERNS

### 1. Convention compliance — CONCERN
- src/Foo.swift:42 — uses raw URLSession; KNOWLEDGE says all network calls go through NetworkClient
- ...

### 2. Obvious quality — PASS
<evidence>

### 3. Stale scaffolding — PASS
<evidence>

### 4. Silent failure check — PASS
<evidence>

Verdict: CONCERNS
```

Short-circuit variant (Stage 1 returned SPEC-FAIL):

```
Review: `hv/foo` → main (3 commits, 5 files)

## Stage 1 — Spec Compliance — SPEC-FAIL

### [F03] Quick-switch projects — FAIL
- .hv/plans/M01-F03.md outcome "Cmd+Tab overlay on the project picker" was not fulfilled — diff adds the overlay but doesn't wire the Cmd+Tab keybinding.
- diff went off-target into src/Settings.swift (not implied by the plan).

## Stage 2 — Code Quality — Skipped (Stage 1 returned SPEC-FAIL)

Verdict: FAIL
```

Single-stage variant (Stage 1 skipped via no-plan fallback or `--stage quality`):

```
Review: `hv/foo` → main (3 commits, 5 files)

## Stage 1 — Spec Compliance — Skipped (no plans found for referenced items)

## Stage 2 — Code Quality — QUALITY-PASS

### 0. Intent match — PASS
<evidence (legacy fallback when Stage 1 didn't run)>

### 1. Convention compliance — PASS
...

Verdict: PASS
```

## Step 10 — Route Based on Verdict

The verdict is the entire product — return it and stop. Never ask a follow-up; the caller (the user, or `/hv-ship` when invoked) owns what happens next.

When invoked from `/hv-ship`, return the verdict; the parent runs consumer routing per `references/review-verdict-routing.md`. When invoked standalone, relay the verdict to the user using the *Producer-side relay* table in the reference — short summary:

- **PASS** — *"Ready to ship. Run `/hv-ship`."*
- **CONCERNS** — print the concerns inline (already done in Step 6), then suggest *"Address via `/hv-work` and rerun `/hv-review`, or accept and ship via `/hv-ship`."*
- **FAIL** — tell the user the merge would regress. Suggest fixing via `/hv-work` or `/hv-debug`. Don't route to `/hv-ship`.

## Rules

- **Read-only.** Never edit, commit, or stage. The verdict is the entire product.
- **Evidence over opinion.** Every concern must cite file:line or commit hash.
- **Scope is bounded.** Only the diff against the base is reviewed — don't wander into unchanged code.
- **Call it honestly.** If conventions were violated but the user has a good reason, the reviewer still reports CONCERN — the user decides what to do.
- **Don't re-run on a passed branch.** If the same scope was just reviewed in the session and came back PASS, skip Steps 7 and 8 and report the cached verdict.
- **Stage gating: see Step 9 worst-of table.** SPEC-FAIL short-circuits Stage 2; otherwise both stages run and Step 9 combines worst-of.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`references/knowledge-consult.md`](../references/knowledge-consult.md) — Canonical K+D query pattern (`hv-knowledge-query` + `hv-decisions-query`) used by every cycle-starting skill.
- [`references/review-verdict-routing.md`](../references/review-verdict-routing.md) — PASS / CONCERNS / FAIL routing for `/hv-review` consumers.
