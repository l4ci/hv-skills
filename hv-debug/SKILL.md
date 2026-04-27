---
name: hv-debug
description: Systematic root-cause investigation for a bug — reads the TODO entry + detail file, consults KNOWLEDGE.md, reproduces, hypothesizes, verifies, fixes with one atomic commit, and nudges /hv-learn. Use on "debug [B07]", "why is X broken", "investigate the crash", when a bug needs a proper cycle rather than a /hv-go shot.
user-invocable: true
---

```
════════════════════════════════════════════════════════════════════════
  🟥  hv-debug  ·  systematic root-cause investigation
  triggers: "debug [B07]", "why is X broken"  ·  pairs: hv-learn
════════════════════════════════════════════════════════════════════════
```

# hv-debug — Systematic Bug Cycle

Full reproduce → hypothesize → verify → fix cycle for a single bug. Anchors to a `[B##]` ID so the fix commit closes the backlog entry and the learning gets routed back to `KNOWLEDGE.md`.

## Configuration

Read `.hv/config.json`:

- `models.orchestrator` — model for hypothesis + verification (default `opus`)
- `models.worker` — model for the fix agent (default `sonnet`)
- `work.isolation` — `"branch"` (default) or `"worktree"`
- `autonomy.level` — `"off"` (default), `"auto"`, or `"loop"`. Controls whether Step 11 (Next move) and Step 12 (Learn) ask vs. invoke directly. See `GUIDE.md` § Autonomy.

## When to Use

- You have a bug ID (`[B07]`) or a reproducer and want a proper cycle
- Previous attempts failed or the symptom isn't obvious
- The bug might produce a durable learning for `KNOWLEDGE.md`

## When NOT to Use

- Trivial fix with an obvious one-liner → `/hv-go`
- Multiple items in one pass → `/hv-work`
- You don't have a reproducer and the bug isn't captured → `/hv-capture` first

## Flow

```
Resolve bug → Consult knowledge → Reproduce → Hypothesize → Verify → Fix → Commit → Learn nudge
```

## Step 1 — Preflight & Guard

```bash
.hv/bin/hv-preflight
```

If the helper is absent or exits non-zero, invoke `hv-init` via the `Skill` tool, then continue. See GUIDE.md § Preflight for exit codes.

```bash
.hv/bin/hv-guard-clean "/hv-debug"
```

Non-zero = stop.

## Step 2 — Resolve the Bug

If the user named a `[B##]`:

- Read that line from `.hv/TODO.md`
- If `Detail:` points at `.hv/bugs/B##.md`, read the detail file too

If the user described a symptom without an ID, invoke `hv-capture` via the `Skill` tool first so the bug gets logged — then resume here with the new ID.

## Step 3 — Consult KNOWLEDGE.md

Read the `hv-knowledge` block in `CLAUDE.md` for the current topic list. Pull topics that plausibly touch the symptom (e.g., `Networking`, `Persistence`, `Concurrency`):

```bash
.hv/bin/hv-knowledge-query "Topic A" "Topic B"
```

Carry any bullets that look relevant into Step 5's hypothesis brief. Skip silently if nothing fits.

## Step 4 — Branch or Worktree

Pick a descriptive name (e.g., `hv/fix-B07-timer-badge`).

**Branch:**

```bash
git checkout -b <branch-name>
.hv/bin/hv-status-add <branch> <ID>
```

**Worktree:**

```bash
git branch <branch-name>
git worktree add .claude/worktrees/<branch-name> <branch-name>
.hv/bin/hv-status-add <branch> <ID> .claude/worktrees/<branch-name>
```

## Step 5 — Reproduce

Reproducing before hypothesizing is non-negotiable. Options:

1. **Run the bug's test** — if one exists, capture the failure output
2. **Write a failing test** — preferred when a test doesn't exist; lives in the test suite
3. **Manual repro** — build/run the app and observe, only if no test path is possible

Don't proceed to Step 6 without a concrete failure signal — an error message, a wrong value, a stack trace.

If you can't reproduce, surface that to the user: *"Can't reproduce — need [X] from you (repro steps, environment, seed data)."* Stop and wait.

## Step 6 — Hypothesize (orchestrator)

Dispatch a hypothesis agent with the **orchestrator** model. Brief contains:

```
Investigate [B##]: <title>.

**Symptom:**
<reproducer output, stack trace, or observed vs expected>

**Entry point(s):**
<file paths + line numbers you suspect are involved>

**Relevant knowledge:**
<bullets from hv-knowledge-query, if any>

Read the code organically. Do not propose a fix yet.

Return: ranked list of 2-3 hypotheses, each with
  - the causal chain (what triggers what)
  - the file:line evidence
  - a concrete verification probe (code to read, a print statement to add, a test to run)
```

Pick the top hypothesis. If the top two are close, verify both.

## Step 7 — Verify

Run the verification probe from Step 6 — read the specific code, add a temporary trace, or run the targeted test. Confirm the hypothesis before touching production code.

If verification fails → the hypothesis is wrong. Go back to Step 6 with the new evidence. Don't fix-and-pray.

## Step 8 — Fix (worker)

Dispatch a fix agent with the **worker** model. Brief contains:

```
Fix [B##]: <title>.

**Root cause (verified):**
<one-sentence causal claim>

**Files:**
- Modify: <paths with line numbers>

**Change:**
<precise description of the minimal edit — exact code where possible>

**Constraints:**
- Minimal diff. No unrelated cleanup.
- Preserve behavior for callers not affected by the bug.
- Read the file before editing.

**Commit with message:**
fix: <short imperative> [B##]

<optional body with the root cause in 1-2 sentences>
```

The worker reads, edits, stages, and commits in one pass. Standard `/hv-work` rules apply.

## Step 9 — Verify the Fix

Re-run the reproducer from Step 5. It must now pass (or the symptom must be gone). If the regression test is new, confirm it's in the suite and runs under the default test command.

If the fix doesn't hold → back to Step 6. Don't commit a partial fix.

## Step 10 — Mark Complete

```bash
.hv/bin/hv-complete <ID> <commit-hash>
.hv/bin/hv-status-remove <branch>
```

## Step 11 — Report

One compact block:

```
Fixed [B07] Timer badge shows stale duration — commit a1b2c3d on `hv/fix-B07-timer-badge`.

Root cause: MenuBarManager held an invalidated timer ref after pause; the next tick no-op'd without resetting the badge.

Fix: reset badge to `--:--` in `pause()` before invalidating.
```

Branch on `autonomy.level`:

- `"off"` (default) — use `AskUserQuestion`:
  - **Header:** `"Next"`
  - **Question:** *"Fix for [B##] is committed. What's next?"*
  - **Options** (single-select):
    1. "Ship via `/hv-ship` (Recommended)" — *"Run the review gate and integrate."*
    2. "Keep working on the branch" — *"Stay on the branch to add more fixes."*
    3. "Stop here" — *"Leave the branch; come back later."*

  Plain-text fallback: *"Merge now with `/hv-ship`, or keep it on the branch for more work?"*

- `"auto"` or `"loop"` — invoke `hv-ship` via the `Skill` tool with the current branch. No prompt. The Recommended path is always ship; autonomy just commits to it. (`ship.review` still governs whether `/hv-ship` runs the review gate.)

## Step 12 — Learn (Nudge or Auto-Invoke)

Trigger condition (same in all modes): the root cause was **not obvious from reading the code alone** — required verification, contradicted an initial hypothesis, or touched a known-tricky subsystem. Skip for trivial fixes (typo, obvious off-by-one).

When triggered, branch on `autonomy.level`:

- `"off"` (default) — print one line: *"Capture this gotcha? Run `/hv-learn` to save the root cause before context fades."*
- `"auto"` or `"loop"` — invoke `hv-learn` via the `Skill` tool. Pass a brief naming the bug ID, root cause, and the subsystem so the captured entry lands in the right topic.

## Key Principles

- **Reproduce before hypothesizing, verify before fixing.** No fix-and-pray.
- **Hypothesis is a claim, not a description.** "X causes Y because Z" — testable.
- **One fix, one commit.** Scope creep in debug commits masks the root cause later.
- **The ID closes the loop.** The commit message carries `[B##]`; `hv-complete` moves the entry.
- **Learn the non-obvious.** If this bug surprised you, it'll surprise the next person.
