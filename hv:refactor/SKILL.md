---
name: hv:refactor
description: Run a full architectural refactor cycle — opus explores the codebase for friction, parallel sonnet subagents implement every fix, opus verifies, then commit. Use when you want to find and fix architectural issues in one shot.
user-invocable: true
---

# hv:refactor

Run a full architectural refactor cycle on the current codebase:
1. **Opus** explores for friction
2. **Parallel sonnet subagents** implement every fix
3. **Opus** verifies all changes
4. **Commit** everything

## Step 1 — Explore with Opus

Dispatch an opus exploration agent. Pass it the full context of what was already fixed in prior rounds (if any — check recent commits). The agent explores organically, reads files in full, follows seams, and reports every friction point with file name, line numbers, and why it matters.

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

[If prior rounds exist]: Do NOT re-surface already-fixed issues: [list them].

Report every friction point with: file, approximate lines, what the friction
is, and why it matters. Be thorough — this is looking for things a first pass
might miss.
```

## Step 2 — Triage and Group

After the exploration agent returns, read all friction points and group them into independent fix batches. Each batch = one agent, one file or tightly-related set of files. Fixes that touch the same file must go to the same agent or be sequenced.

Rules for grouping:
- **Independent files** → parallel agents
- **Same file** → single agent handles all changes to that file
- **Sequential dependency** (fix A must land before fix B can reference it) → note the order, run sequentially after the first batch

## Step 3 — Fix with Parallel Sonnet Agents

Dispatch all independent fixes in parallel. Each agent gets:
- Exact files to read and modify
- Precise description of the bug/friction
- Exact fix to implement (no ambiguity)
- Constraint: read the file first, minimal diff, no unrelated changes
- Return: short summary of what changed

For each agent brief:
- Include the relevant code snippet showing the problem
- Include the replacement code or a precise description of it
- Name every line number so the agent doesn't have to hunt

After parallel batch completes, dispatch any sequential agents that depended on the first batch.

## Step 4 — Verify with Opus

Dispatch a single opus verification agent. For each fix, it reads the modified file and reports:
- **PASS** — change is correct and complete
- **FAIL** — something is wrong (with exact finding)
- **CONCERN** — works but has a side effect worth knowing

The verification agent must read actual file content, not trust the fix summaries.

## Step 5 — Handle Failures

If any fix got **FAIL**:
- Read the opus finding
- Dispatch a new sonnet agent with the corrected brief
- Re-verify with opus

If any fix got **CONCERN**:
- Assess whether it blocks commit
- Fix if blocking, note if informational

## Step 6 — Commit

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

## Key Principles

- **Opus for judgment, sonnet for execution.** Exploration and verification require deep reasoning; implementation is precise execution of a known fix.
- **Parallel by default.** Independent fixes always run in parallel. Sequential only when there's a real dependency.
- **Minimal diffs.** Each fix touches only what's necessary. No reformatting, no unrelated cleanup.
- **Read before edit.** Every agent reads the target file before making changes.
- **Verify before commit.** Never commit without opus sign-off.
- **Commit once** per run (not per fix) unless fixes are truly independent milestones.
