---
name: hv-debug
description: Systematic root-cause investigation for a bug — reads the TODO entry + detail file, consults KNOWLEDGE.md, reproduces, hypothesizes, verifies, fixes with one atomic commit, and nudges /hv-learn. Use on "debug [B07]", "why is X broken", "investigate the crash", when a bug needs a proper cycle rather than a /hv-go shot.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🐛  hv-debug  ·  systematic root-cause investigation
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
- `autonomy.level` — `"off"` (default), `"auto"`, or `"loop"`. Controls whether Step 11 (Next move) and Step 12 (Learn) ask vs. invoke directly.
- `debug.competingHypotheses` — `false` (default) or `true`. When `true`, Step 6 fans out 3 parallel hypothesis agents from different angles instead of dispatching one.

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

See `docs/reference/preflight.md` for exit-code handling.

```bash
.hv/bin/hv-guard-clean "/hv-debug"
```

Non-zero = stop.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Reproduce", description="Reliably trigger the failure")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (no smoke regressions) get `completed` with the no-op reason in the description.

Phases:

1. *Preflight & guard* — clean tree, bug ID resolved (Step 1)
2. *Read item & knowledge* — TODO entry + KNOWLEDGE.md cross-ref loaded (Steps 2–3)
3. *Reproduce* — failure triggers reliably from a known input (Step 4)
4. *Hypothesize & verify* — claim is testable; evidence supports or refutes (Steps 5–6)
5. *Fix & commit* — minimal diff, atomic commit with `[B##]` footer (Steps 7–9)
6. *Smoke / regression* — no untouched-area breakage; existing tests pass (Step 10)
7. *Learn nudge* — autonomy-aware learn/decide nudges (Steps 11–12.5)

## Step 2 — Resolve the Bug

If the user named a `[B##]`:

- Read that line from `.hv/TODO.md`
- If `Detail:` points at `.hv/bugs/B##.md`, read the detail file too

If the user described a symptom without an ID, invoke `hv-capture` via the `Skill` tool first so the bug gets logged — then resume here with the new ID.

## Step 3 — Consult KNOWLEDGE & DECISIONS

Apply the canonical K+D query pattern (`references/knowledge-consult.md`) with topics that plausibly touch the symptom (e.g., `Networking`, `Persistence`, `Concurrency`, `Architecture`, `Testing`).

Carry KNOWLEDGE bullets into Step 5's hypothesis brief. Carry DECISIONS entries into Step 6's hypothesis brief under a `**Hard boundaries:**` block — boundaries may rule out an entire fix direction before cycles are wasted.

## Step 3.5 — Vocabulary & soft-cap checks

```bash
.hv/bin/hv-context-query "<terms from the bug report or the failing component>"
```

Carry any matched terms into Step 6's hypothesis brief — canonical definitions help align bug-report phrasing to existing components.

- **Soft-cap check.** Run `.hv/bin/hv-map-cap-check` — emits a one-line nudge to stderr if the subsystem count is at or above the configured soft cap. Never blocks.

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

Read `debug.competingHypotheses` from `.hv/config.json` (default `false`).

Brief template (both modes use this):

```
Investigate [B##]: <title>.

**Symptom:**
<reproducer output, stack trace, or observed vs expected>

**Entry point(s):**
<file paths + line numbers you suspect are involved>

**Relevant knowledge:**
<bullets from hv-knowledge-query, if any>
<entries from hv-decisions-query, if any — boundaries that rule out fix directions>
<terms from hv-context-query, if any — definitions to align bug-report phrasing to canonical names; flag drift between the report's wording and the term's definition since misnamed components are a frequent root cause of misattributed bugs>

[FRAMING — competing mode only: insert one lens prompt below]

Read the code organically. Do not propose a fix yet.

Return: ranked list of 2-3 hypotheses, each with
  - the causal chain (what triggers what)
  - the file:line evidence
  - a concrete verification probe (code to read, a print statement to add, a test to run)
```

### Single hypothesis (default)

Dispatch one orchestrator-model agent with no FRAMING line. Pick the top hypothesis; verify both if the top two are close.

### Competing hypotheses (`debug.competingHypotheses: true`)

Dispatch **3 parallel orchestrator-model agents** in one tool-call batch. Each gets a different framing lens:

- **Recent-changes lens:** *"Start from recent commits — run `git log --oneline -20 -- <suspect paths>`. The bug likely correlates with something that changed; frame hypotheses around what was modified and why."*
- **Data-shape lens:** *"Start from the values flowing through the suspect path. The bug likely arises when a value violates an implicit contract — null/empty, off-by-one, wrong type, stale cache, malformed upstream input. Trace data, not code."*
- **Concurrency / lifecycle lens:** *"Start from timing and ordering. Likely a race window, ordering assumption, partial state, double-fire, listener registered twice, async resolution out of order, or a reference held past its lifetime. Look for state, not logic."*

After all three return: deduplicate (same root cause from different angles → one hypothesis, keep sharper wording), pick the strongest regardless of lens (verify both if the top two are close), discard weak ones silently — don't relay every angle's output.

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

**Do NOT run `git add` or `git commit`.** Write the change to files only — orchestrator commits in Step 8.5.

**Suggested commit message:** fix: <short imperative> [B##]

<optional body with the root cause in 1-2 sentences>
```

The worker reads and edits in one pass. Orchestrator stages and commits in Step 8.5 — same write-only pattern as `/hv-work` Step 6 (default since F11). Hv-debug is single-worker by design, so the file-disjointness and parallel-commit concerns from `/hv-work` don't apply, but using one shared pattern keeps brief templates consistent across skills.

## Step 8.5 — Commit (orchestrator)

Stage exactly the files named in the worker's brief and commit with the suggested message:

```bash
git add <files-from-brief>
git commit -m "fix: <short imperative> [B##]"
```

One commit for the bug. Don't `git add -A` — sweep risk if any sibling artifacts crept in. If the toolchain produced legitimate sibling files (e.g. Godot `.gd.uid`), follow the same sweep pattern as `/hv-work` Step 8.5: a separate `chore:` commit, not the same atomic unit as the fix.

## Step 9 — Verify the Fix

Re-run the reproducer from Step 5. It must now pass (or the symptom must be gone). If the regression test is new, confirm it's in the suite and runs under the default test command.

If the fix doesn't hold → back to Step 6. Don't commit a partial fix.

## Step 10 — Mark Complete

```bash
.hv/bin/hv-complete <ID> <commit-hash>
```

**Single-repo:**

```bash
.hv/bin/hv-status-remove <branch>
```

**Umbrella mode** (when `umbrella.enabled` is true and the active entry has a non-null `repo`, derive it from `.hv/status.json` as `/hv-ship` does in its Step 2):

```bash
.hv/bin/hv-status-remove --repo <repo> <branch>
```

Without `--repo`, the helper preserves umbrella-tagged entries (only legacy `repo: null` rows are removed) — so umbrella sessions MUST pass `--repo` here or the active entry leaks into the next `/hv-next`.

## Step 11 — Report

One compact block:

```
Fixed [B07] Timer badge shows stale duration — commit a1b2c3d on `hv/fix-B07-timer-badge`.

Root cause: MenuBarManager held an invalidated timer ref after pause; the next tick no-op'd without resetting the badge.

Fix: reset badge to `--:--` in `pause()` before invalidating.
```

Branch on `autonomy.level`:

- `"off"` (default) — `AskUserQuestion`:
  - **Header:** `"Next"`
  - **Question:** *"Fix for [B##] is committed. What's next?"*
  - **Options** (single-select):
    1. "Ship via `/hv-ship` (Recommended)" — *"Run the review gate and integrate."*
    2. "Keep working on the branch" — *"Stay on the branch to add more fixes."*
    3. "Stop here" — *"Leave the branch; come back later."*
  - Plain-text fallback: *"Merge now with `/hv-ship`, or keep it on the branch for more work?"*
- `"auto"` or `"loop"` — **dispatch `hv-ship` via `Skill` with the current branch immediately — no prompt, no confirmation.** (`ship.review` still governs the review gate.)

## Step 12 — Learn (Nudge or Auto-Invoke)

Trigger: the root cause was **not obvious from reading the code alone** — required verification, contradicted an initial hypothesis, or touched a known-tricky subsystem. Skip for trivial fixes (typo, obvious off-by-one).

Branch on `autonomy.level`:

- `"off"` — nudge *"Capture this gotcha? Run `/hv-learn` to save the root cause before context fades."*
- `"auto"` or `"loop"` — **dispatch `hv-learn` via `Skill` immediately — no prompt, no confirmation.** Pass a brief naming the bug ID, root cause, and subsystem so the captured entry lands in the right topic.

If the bug was rooted in hv-skills behavior (touched `bin/hv-*`, `hv-*/SKILL.md`, or `.hv/`), `/hv-learn`'s Step 8.5 will offer to file an upstream issue against `l4ci/hv-skills`.

- **Update project map.** Invoke `/hv-map after-work` if the fix touched files belonging to a known subsystem.

## Step 12.5 — Decide (Nudge Only)

If the fix codified a constraint (e.g., "never use timer-X here", "this surface only goes through controller-Y"), surface a one-liner. **Always nudge — never auto-invoke**, regardless of `autonomy.level`. Skip trivial fixes (single-line edit, obvious typo). Don't repeat in the session.

> *"Did this fix lock in a boundary worth preserving? Run `/hv-decide` to capture it as a hard constraint."*

## Key Principles

- **Reproduce before hypothesizing, verify before fixing.** No fix-and-pray.
- **Hypothesis is a claim, not a description.** "X causes Y because Z" — testable.
- **One fix, one commit.** Scope creep in debug commits masks the root cause later.
- **The ID closes the loop.** The commit message carries `[B##]`; `hv-complete` moves the entry.
- **Learn the non-obvious.** If this bug surprised you, it'll surprise the next person.
