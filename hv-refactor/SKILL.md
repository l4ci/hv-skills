---
name: hv-refactor
description: Run a full architectural refactor cycle — explores the codebase for friction, categorizes dependencies, designs competing approaches for structural changes, then fixes everything with parallel subagents. Use when you want to find and fix architectural issues.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  🧱  hv-refactor  ·  full architectural refactor cycle
  triggers: "refactor", "clean architecture"  ·  pairs: hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-refactor

## Configuration

Read `.hv/config.json`:

- `models.orchestrator` — exploration, design, and verification (default `opus`)
- `models.worker` — implementation subagents (default `sonnet`)
- `refactor.confirmBeforeExecute` — pause for user approval before executing fixes (default `true`; `false` for full autonomy)

## Args

- `--here` — skip Step 1.5 (umbrella scope detection); run the single-repo flow in cwd. Used internally by Step 1.5's fanout dispatch — each sub-agent invokes `/hv-refactor --here` after `cd`-ing into its target. Single-repo projects (umbrella.enabled false or unset) ignore the flag — the flow is identical with or without it.

## Flow

Explore → Triage → Present *(checkpoint)* → Design competing approaches *(checkpoint)* → Fix in parallel → Verify → Re-fix on failures → Commit → Report

## Dependency Categories

Every friction point gets one category — it drives the fix strategy:

1. **In-process** — pure computation, in-memory state, no I/O. Merge modules, test directly.
2. **Local-substitutable** — has a local test stand-in (PGLite for Postgres, in-memory FS). Test with the stand-in in the suite.
3. **Ports & Adapters** — your services across a network boundary (microservices, internal APIs). Define a port at the module boundary; deep module owns logic, transport is injected. Tests use an in-memory adapter; production uses the real one.
4. **True external** — third-party services (Stripe, Twilio) you don't control. Mock at the boundary; tests provide the mock, production uses the real implementation.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

The `hv-guard-clean` call moved from this step into Step 1.5's branches — fanout sub-agents run their own guard-cleans against their target trees, so the umbrella-level guard isn't needed (and would falsely fail when the umbrella is not a git repo).

## Step 1.5 — Umbrella Scope (skip if `--here` was passed)

Skip this step entirely if EITHER:
- `--here` was passed to this invocation
- `umbrella.enabled` is false in `.hv/config.json`

In that case, run `hv-guard-clean` and proceed to Step 2 (single-repo flow):

```bash
.hv/bin/hv-guard-clean "/hv-refactor"
```

Otherwise, list refactor targets:

```bash
.hv/bin/hv-refactor-targets
```

Output JSON:

```json
{
  "umbrella": {"hasCode": true|false},
  "subRepos": [{"name": "<name>", "path": "<abs-path>"}, ...]
}
```

If `subRepos` is empty (umbrella mode is on but no sub-repos are registered), proceed to Step 2 with the single-repo flow — the umbrella's tree is the only target.

Otherwise, ask the user which scope to refactor via `AskUserQuestion`:

- **Header:** `"Refactor scope"`
- **Question:** *"Umbrella mode is on with N sub-repo(s): `<comma-separated names>`. Where should this refactor cycle run?"*
- **Options** (single-select), conditional on `umbrella.hasCode`:
  - When `hasCode == true`:
    1. *"All sub-repos + umbrella (Recommended)"* — *"N+1 parallel cycles, one per sub-repo plus one for the umbrella's own tree."*
    2. *"All sub-repos only"* — *"N parallel cycles. Skip the umbrella's own tree."*
    3. *"Umbrella only"* — *"Refactor the umbrella's tree only; skip sub-repos."*
    4. *"Pick a subset"* — *"Multi-select which sub-repos to include."*
  - When `hasCode == false`:
    1. *"All sub-repos (Recommended)"* — *"N parallel cycles, one per sub-repo."*
    2. *"Pick a subset"* — *"Multi-select which sub-repos to include."*
    3. *"Umbrella only"* — *"Refactor the umbrella's tree only (no code detected — likely no findings)."*

Plain-text fallback: pick the Recommended option for the relevant `hasCode` state.

**Loop mode:** if `autonomy.level == "loop"`, auto-pick the Recommended scope option without invoking AskUserQuestion. With `hasCode == true`, that's *"All sub-repos + umbrella (Recommended)"* — fan out to N+1 parallel cycles. With `hasCode == false`, that's *"All sub-repos (Recommended)"* — fan out to N parallel cycles. The "Pick a subset" follow-up never fires under loop. Per the `hv-init` authoring convention "routine routing/tagging auto-picks Recommended in loop mode."

If the user picks **"Pick a subset"**, follow up with a multiSelect:

- **Header:** `"Sub-repos"`, `multiSelect: true`
- **Question:** *"Which sub-repos to refactor?"*
- **Options:** up to 4 sub-repos by name (alphabetical); if more than 4, list top 4 alphabetically and ask the user to name the rest in free text.

### Branch — "Umbrella only"

Run `hv-guard-clean` against the umbrella's tree if you skipped it earlier. Then proceed to Step 2 (single-repo flow). The umbrella's `.git/` (if it has one) receives the commit; if the umbrella isn't a git repo, hv-guard-clean exits 2 and this step stops.

### Branch — fanout (any other scope: "All sub-repos", "All + umbrella", "Pick a subset")

Build the target list. For each target, you'll dispatch one sub-agent via `Agent` IN A SINGLE MESSAGE (parallel).

**Collect umbrella context for the sub-agents.** KNOWLEDGE.md and DECISIONS.md live only at the umbrella; sub-agents need their content embedded so they respect cross-repo conventions and decisions. Query the topics that may apply across the targets:

```bash
.hv/bin/hv-knowledge-query "<all topic names>"
.hv/bin/hv-decisions-query "<all topic names>"
```

If unsure which topics apply, pass every topic from each file (read the `## Topic` headings and pass all of them). Capture the output as `KNOWLEDGE_BLOB` and `DECISIONS_BLOB` for embedding.

**Dispatch sub-agents.** For each target (each chosen sub-repo, plus optionally the umbrella when "All + umbrella" was picked), build a single Agent call with this prompt template:

```
You are a /hv-refactor sub-agent operating on a single repo within an umbrella project. Run a focused refactor cycle for THIS REPO ONLY.

Repo: <name>
Path: <abs-path>
Umbrella: <umbrella-abs-path>

## Your steps

1. cd <abs-path>

2. Run `.hv/bin/hv-guard-clean` from this repo's bin path (it lives at <umbrella-abs-path>/.hv/bin/hv-guard-clean — call it as `<umbrella-abs-path>/.hv/bin/hv-guard-clean`). If the repo isn't a git repo or has uncommitted changes, stop and report "no changes" back.

3. Run a focused refactor cycle equivalent to /hv-refactor's Steps 2-9 on THIS REPO:
   a. Dispatch an exploration agent (orchestrator model: <orchestrator from config>) to explore THIS REPO ONLY for friction. Do not walk into the umbrella or other sub-repos.
   b. Triage findings; classify simple vs structural; categorize dependencies (in-process / local-substitutable / ports-and-adapters / true-external).
   c. For structural items, design competing approaches if the umbrella's `.hv/config.json` has `refactor.confirmBeforeExecute: true`; otherwise pick the recommended approach and proceed (the config file lives at the umbrella, not here — read `<umbrella-abs-path>/.hv/config.json`).
   d. Dispatch parallel worker agents (worker model: <worker from config>) for the fixes. File-disjoint fixes run in parallel; same-file fixes go to one worker; sequential dependencies serialize.
   e. Verify with a single verification agent (orchestrator model). Re-fix any FAIL verdicts.
   f. Commit in this repo's `.git/`. One commit for the cycle. Stage modified files explicitly (no `git add -A`).

4. Do NOT:
   - Run `hv-refactor-reset` — the umbrella orchestrator does that once at the end.
   - Modify the umbrella's `.hv/`, `.claude*/`, or any other sub-repo.
   - Push or create PRs.

## Context for THIS sub-cycle

### Umbrella KNOWLEDGE.md (relevant topics)

<KNOWLEDGE_BLOB>

### Umbrella DECISIONS.md (full)

<DECISIONS_BLOB>

## Return

A compact summary in EXACTLY this format:

repo: <name>
commit: <short hash, or "no changes" if the cycle found nothing to commit>
items: <N>
- <one-line item description 1>
- <one-line item description 2>
...
```

The orchestrator and worker model names embedded in the prompt come from the umbrella's `.hv/config.json` `models.orchestrator` / `models.worker` (defaults `opus` / `sonnet`).

**Wait for all sub-agents to complete**, then aggregate.

### After fanout returns

1. Aggregate the per-repo summaries into a single umbrella-level report.
2. Run `.hv/bin/hv-refactor-reset` ONCE.
3. Print the aggregated report. Format:

```
Umbrella refactor cycle — N targets

repo: web (commit a1b2c3d, 4 items)
  - <item 1>
  - <item 2>
  ...

repo: api (commit e4f5g6h, 2 items)
  - <item 1>
  - <item 2>

repo: <umbrella-name> (no changes)

(Counter reset.)
```

For sub-repos that returned "no changes", skip the bullet list — just note the result.

**EXIT** — skip Steps 2-10 (those are the single-repo flow that umbrella fanout has already delegated to sub-agents).

## Step 2 — Explore with Orchestrator

Dispatch an exploration agent using the configured **orchestrator** model. Pass it the full context of what was already fixed in prior rounds (if any — check recent commits). The agent explores organically, reads files in full, follows seams, and reports every friction point with file name, line numbers, and why it matters.

Prompt template for the exploration agent:
```
Explore [PROJECT] at [PATH]. Navigate organically — read files in full,
follow every interesting seam. Look for:
- Shallow modules where the interface is nearly as complex as the impl
- Concepts co-owned across multiple files that should live in one place
- Silent failures — errors logged but not propagated or surfaced
- State split across types in ways hard to reason about
- Implicit assumptions baked into data transformations
- Anything requiring 3+ files to understand one concept
- Tightly-coupled modules with integration risk at their seams

[If prior rounds exist]: Do NOT re-surface already-fixed issues: [list them].

For every friction point report: file, approximate lines, the friction,
why it matters, and the dependency category (in-process,
local-substitutable, ports-and-adapters, or true external).

Be thorough — this is looking for things a first pass might miss.
```

## Step 3 — Triage, Categorize & Classify

After the exploration agent returns, process each friction point:

1. **Assign a dependency category** (in-process / local-substitutable / ports & adapters / true external)
2. **Classify as simple or structural:**
   - **Simple** — the fix is obvious and self-contained (surface an error, propagate a value, consolidate duplicated logic, add a missing return). No design choices involved.
   - **Structural** — the fix reshapes a module boundary, merges tightly-coupled modules, changes ownership of a concept, or introduces a new interface. Multiple valid approaches exist.
3. **Group into independent fix batches:**
   - **Independent files** → parallel agents
   - **Same file** → single agent handles all changes to that file
   - **Sequential dependency** (fix A must land before fix B can reference it) → note the order, run sequentially after the first batch

## Step 4 — Present Candidates

Present a numbered list of all friction points. For each, show:

- **Cluster**: which files/modules are involved
- **Classification**: simple or structural
- **Dependency category**: which of the 4 categories applies
- **Why it matters**: the concrete risk or cost of leaving it

If `confirmBeforeExecute` is `true`, gate with `AskUserQuestion`:

- **Header:** `"Candidates"`
- **Question:** *"Found N friction points. Which should I fix?"*
- **Options** (single-select):
  1. "Fix all N (Recommended)" — *"Proceed with every candidate in parallel."*
  2. "Pick a subset" — *"Choose which items to include; the rest are skipped."*
  3. "Stop" — *"No changes; surface the list and exit."*

If the user picks "Pick a subset", follow up with a second `AskUserQuestion`:

- **Header:** `"Subset"`, `multiSelect: true`
- **Question:** *"Select the items to fix."*
- **Options:** up to 4 candidates by label (e.g., `"SessionOrchestrator error propagation"`). If more than 4, list top 4 by impact and ask the user to name the rest in free text.

Plain-text fallback: *"Proceed with all, a subset, or none?"*

**Loop mode:** if `autonomy.level == "loop"` AND `confirmBeforeExecute == true`, auto-pick *"Fix all N (Recommended)"* without invoking AskUserQuestion — proceed with every candidate in parallel. The "Pick a subset" follow-up never fires under loop. Per the `hv-init` authoring convention "routine routing/tagging auto-picks Recommended in loop mode." When `confirmBeforeExecute == false` the gate is already skipped (existing behavior in the next paragraph), so this auto-pick is conditional on the gate firing in the first place.

If `confirmBeforeExecute` is `false`: present the list for visibility, then proceed immediately with all items.

## Step 5 — Design Competing Approaches (Structural Only)

**Consult decisions before designing.** Pull relevant boundary entries:

```bash
.hv/bin/hv-decisions-query <topics…>
```

Any approach that violates a decision is disqualified before the design phase. If every generated approach would violate, **stop and surface to the user** — refactors must not silently work around committed boundaries. Refactors are exactly when boundaries matter most.

For each **structural** friction point, spawn 3+ sub-agents in parallel using the configured **orchestrator** model. Each agent gets the same technical brief (file paths, coupling details, dependency category, what's being hidden) but a different design constraint:

- **Agent 1**: "Minimize the interface — aim for 1-3 entry points max"
- **Agent 2**: "Maximize flexibility — support many use cases and extension"
- **Agent 3**: "Optimize for the most common caller — make the default case trivial"
- **Agent 4** (if a remote dependency is involved): "Design around the ports & adapters pattern"

Each sub-agent outputs:

1. Interface signature (types, methods, params)
2. Usage example showing how callers use it
3. What complexity it hides internally
4. Dependency strategy (how deps are handled per the category)
5. Trade-offs

Present designs sequentially, then compare them in prose. Give an opinionated recommendation: which design is strongest and why. If elements from different designs combine well, propose a hybrid.

If `confirmBeforeExecute` is `true`, gate with `AskUserQuestion` per structural friction point (batch up to 4 in one call):

- **Header:** short name of the friction point (≤12 chars, e.g., `"Ring buffer"`)
- **Question:** *"Which design should I use for `<friction point>`?"*
- **Options** (single-select, up to 4): one per competing design. Mark your recommended design `(Recommended)`. Label each with the design's constraint (e.g., `"Minimal interface (Recommended)"`, `"Max flexibility"`, `"Caller-optimized"`, `"Ports & adapters"`).

Use the `preview` field on each option to show the interface signature + usage example — this is exactly the case that's worth a side-by-side comparison.

Plain-text fallback: *"Which approach for `<friction point>`? (design 1 / 2 / 3 / 4)"*

If `confirmBeforeExecute` is `false`: use the recommended approach and proceed.

**Simple** friction points skip this step entirely — they go straight to Step 6.

## Step 6 — Fix with Parallel Worker Agents

Dispatch all independent fixes in parallel using the configured **worker** model. Each agent gets:
- Exact files to read and modify
- Precise description of the friction and the chosen approach
- For structural changes: the selected interface design from Step 5
- Dependency category and how deps should be handled
- Constraint: read the file first, minimal diff, no unrelated changes
- Return: short summary of what changed

For each agent brief:
- Include the relevant code snippet showing the problem
- Include the replacement code or a precise description of it
- Name every line number so the agent doesn't have to hunt

Don't announce the dispatch — just do it. After parallel batch completes, dispatch any sequential agents that depended on the first batch.

## Step 7 — Verify with Orchestrator

Dispatch a single verification agent using the configured **orchestrator** model. For each fix, it reads the modified file and reports:
- **PASS** — change is correct and complete
- **FAIL** — something is wrong (with exact finding)
- **CONCERN** — works but has a side effect worth knowing

The verification agent must read actual file content, not trust the fix summaries. Don't relay individual PASS verdicts to the user — only surface FAILs and CONCERNs.

## Step 8 — Handle Failures

If any fix got **FAIL**:
- Read the verification finding
- Dispatch a new worker agent with the corrected brief
- Re-verify with orchestrator
- Only mention persistent failures to the user (ones that don't resolve after retry)

If any fix got **CONCERN**:
- Assess whether it blocks commit
- Fix if blocking, note if informational — surface informational concerns briefly at the end, not inline during verification

## Step 9 — Commit

After all fixes pass verification, commit everything:

```bash
# Stage all modified files explicitly (never git add -A)
git add [file1] [file2] ...

# Commit with a message that lists all fixes
git commit -m "refactor: [N] architectural improvements

[one line per fix, e.g.:]
- SessionOrchestrator: surface autosave errors to lastError
- RingBuffer: write() returns overflow count (@discardableResult)
- SpeakerReconciler: returned embeddings use EMA values
..."
```

If the project uses a build tool to regenerate project files (e.g. `xcodegen generate` for XcodeGen projects), run it before committing if any files were added or deleted.

After the commit lands, zero the refactor-pressure counter so the next cycle starts fresh:

```bash
.hv/bin/hv-refactor-reset
```

## Step 10 — Report to User

After commit, give one compact summary. Example:

```
Refactored 4 items — commit d7e8f9a

- SessionOrchestrator: surface autosave errors to lastError
- RingBuffer: write() returns overflow count
- SpeakerReconciler: returned embeddings use EMA values
- TimerManager: consolidated 3 timer sources into one
```

If any CONCERNs surfaced during verification, append them briefly:

```
Note: RingBuffer overflow count changes the return type — callers using `_ = write()` are fine, but check any that inspect the return.
```

Don't recap the exploration findings, the design alternatives, or the verification pass/fail log. The user can read the diff.

## Key Principles

- **No noise.** Don't narrate steps that produced no output or found nothing. Don't echo back what you're about to do before doing it. Report results, not process.
- **Orchestrator for judgment, worker for execution.** Models are configured in `.hv/config.json` (default: opus/sonnet). Exploration, design, and verification require deep reasoning; implementation is precise execution of a known fix.
- **Categorize before fixing.** Every friction point gets a dependency category and a simple/structural classification. This prevents over-engineering simple fixes and under-designing structural ones.
- **Compete on structural changes.** When multiple valid approaches exist, design them in parallel and pick the strongest. Don't commit to the first idea.
- **Parallel by default.** Independent fixes always run in parallel. Sequential only when there's a real dependency.
- **Minimal diffs.** Each fix touches only what's necessary. No reformatting, no unrelated cleanup.
- **Read before edit.** Every agent reads the target file before making changes.
- **Verify before commit.** Never commit without orchestrator sign-off.
- **Commit once** per run (not per fix) unless fixes are truly independent milestones.
