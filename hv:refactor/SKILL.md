---
name: hv:refactor
description: Run a full architectural refactor cycle — explores the codebase for friction, categorizes dependencies, designs competing approaches for structural changes, then fixes everything with parallel subagents. Use when you want to find and fix architectural issues.
user-invocable: true
---

# hv:refactor

Run a full architectural refactor cycle on the current codebase.

## Configuration

Before starting, read `.hv/config.json` if it exists. It contains:

```json
{
  "models": {
    "orchestrator": "opus",
    "worker": "sonnet"
  },
  "refactor": {
    "confirmBeforeExecute": true
  }
}
```

- Use `orchestrator` for exploration, design, and verification agents (Agent `model` parameter)
- Use `worker` for implementation subagents (Agent `model` parameter)
- `confirmBeforeExecute` — when `true` (default), pause for user approval before executing fixes. Set `false` for full autonomy.

If `.hv/config.json` doesn't exist, default to `opus`/`sonnet` and `confirmBeforeExecute: true`.

## Flow

1. **Orchestrator** explores for friction
2. **Triage** — categorize dependencies, classify as simple or structural
3. **Present candidates** — show the user what was found *(checkpoint if confirmBeforeExecute)*
4. **Design competing approaches** — for structural changes only, spawn parallel design agents
5. **User picks approach** *(checkpoint if confirmBeforeExecute)*
6. **Parallel worker subagents** implement every fix
7. **Orchestrator** verifies all changes
8. **Handle failures** — re-fix and re-verify
9. **Commit** everything

## Dependency Categories

When assessing each friction point, classify its dependencies into one of four categories. This classification drives the fix strategy.

### 1. In-process

Pure computation, in-memory state, no I/O. Always fixable — just merge the modules and test directly.

### 2. Local-substitutable

Dependencies that have local test stand-ins (e.g., PGLite for Postgres, in-memory filesystem). Fixable if the test substitute exists. The deepened module is tested with the local stand-in running in the test suite.

### 3. Remote but owned (Ports & Adapters)

Your own services across a network boundary (microservices, internal APIs). Define a port (interface) at the module boundary. The deep module owns the logic; the transport is injected. Tests use an in-memory adapter, production uses the real HTTP/gRPC/queue adapter.

### 4. True external (Mock)

Third-party services (Stripe, Twilio, etc.) you don't control. Mock at the boundary. The module takes the external dependency as an injected port, and tests provide a mock implementation.

## Step 0 — Guard: Clean Working Tree

Check for uncommitted changes: `git status --porcelain`

- If the output is empty → proceed
- If there are uncommitted changes → **stop and warn the user**:
  *"You have uncommitted changes. Stash them (`git stash`) or commit them before running /hv:refactor, so the refactor happens on a clean base."*
  Do not proceed until the working tree is clean.

## Step 1 — Explore with Orchestrator

Dispatch an exploration agent using the configured **orchestrator** model. Pass it the full context of what was already fixed in prior rounds (if any — check recent commits). The agent explores organically, reads files in full, follows seams, and reports every friction point with file name, line numbers, and why it matters.

Prompt template for the exploration agent:
```
Explore [PROJECT] at [PATH]. Navigate organically — read files in full,
follow every interesting seam. Look for:
- Modules so shallow the interface is nearly as complex as the implementation
- Concepts co-owned across multiple files that should live in one place
- Silent failure modes — errors logged but not propagated or shown to users
- State split across types and hard to reason about
- Untested seams or code paths that can only fail in production
- Implicit assumptions baked into data transformations
- Anything requiring 3+ files to understand one concept
- Tightly-coupled modules creating integration risk at their seams

[If prior rounds exist]: Do NOT re-surface already-fixed issues: [list them].

For every friction point report: file, approximate lines, what the friction
is, why it matters, and which dependencies are involved (pure in-process,
local-substitutable, remote-but-owned, or true external).

Be thorough — this is looking for things a first pass might miss.
```

## Step 2 — Triage, Categorize & Classify

After the exploration agent returns, process each friction point:

1. **Assign a dependency category** (in-process / local-substitutable / ports & adapters / true external)
2. **Classify as simple or structural:**
   - **Simple** — the fix is obvious and self-contained (surface an error, propagate a value, consolidate duplicated logic, add a missing return). No design choices involved.
   - **Structural** — the fix reshapes a module boundary, merges tightly-coupled modules, changes ownership of a concept, or introduces a new interface. Multiple valid approaches exist.
3. **Group into independent fix batches:**
   - **Independent files** → parallel agents
   - **Same file** → single agent handles all changes to that file
   - **Sequential dependency** (fix A must land before fix B can reference it) → note the order, run sequentially after the first batch

## Step 3 — Present Candidates

Present a numbered list of all friction points. For each, show:

- **Cluster**: which files/modules are involved
- **Classification**: simple or structural
- **Dependency category**: which of the 4 categories applies
- **Why it matters**: the concrete risk or cost of leaving it

If `confirmBeforeExecute` is `true`: ask the user which items to proceed with (all, a subset, or none). Wait for confirmation before continuing.

If `confirmBeforeExecute` is `false`: present the list for visibility, then proceed immediately with all items.

## Step 4 — Design Competing Approaches (Structural Only)

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

If `confirmBeforeExecute` is `true`: ask the user which approach to use (or accept the recommendation). Wait for confirmation.

If `confirmBeforeExecute` is `false`: use the recommended approach and proceed.

**Simple** friction points skip this step entirely — they go straight to Step 5.

## Step 5 — Fix with Parallel Worker Agents

Dispatch all independent fixes in parallel using the configured **worker** model. Each agent gets:
- Exact files to read and modify
- Precise description of the friction and the chosen approach
- For structural changes: the selected interface design from Step 4
- Dependency category and how deps should be handled
- Constraint: read the file first, minimal diff, no unrelated changes
- Return: short summary of what changed

For each agent brief:
- Include the relevant code snippet showing the problem
- Include the replacement code or a precise description of it
- Name every line number so the agent doesn't have to hunt

Don't announce the dispatch — just do it. After parallel batch completes, dispatch any sequential agents that depended on the first batch.

## Step 6 — Verify with Orchestrator

Dispatch a single verification agent using the configured **orchestrator** model. For each fix, it reads the modified file and reports:
- **PASS** — change is correct and complete
- **FAIL** — something is wrong (with exact finding)
- **CONCERN** — works but has a side effect worth knowing

The verification agent must read actual file content, not trust the fix summaries. Don't relay individual PASS verdicts to the user — only surface FAILs and CONCERNs.

## Step 7 — Handle Failures

If any fix got **FAIL**:
- Read the verification finding
- Dispatch a new worker agent with the corrected brief
- Re-verify with orchestrator
- Only mention persistent failures to the user (ones that don't resolve after retry)

If any fix got **CONCERN**:
- Assess whether it blocks commit
- Fix if blocking, note if informational — surface informational concerns briefly at the end, not inline during verification

## Step 8 — Commit

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

## Step 9 — Report to User

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
