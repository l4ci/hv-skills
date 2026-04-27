---
name: hv-assume
description: Print the orchestrator's intended approach for an item, slice, or milestone — files it would touch, files it would create, tests it would add, assumptions it's making, known unknowns it would resolve mid-flight. Read-only; writes nothing. Use before /hv-work to verify alignment, especially on size-M+ items where corrections after the fact are expensive.
user-invocable: true
---

```
════════════════════════════════════════════════════════════════════════
  🟪  hv-assume  ·  peek the orchestrator's intended approach
  triggers: "assume B07", "peek M01-S01"  ·  pairs: hv-plan, hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-assume — Approach Peek (Read-Only)

Print what `/hv-work` would do *before it does it*. Surface assumptions, intended file changes, and known unknowns so the user can correct course before code lands. **No writes. No commits. No tool calls beyond reads.**

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

If the helper is absent or exits non-zero, invoke `hv-init` via the `Skill` tool, then continue.

## Step 2 — Resolve Target

The user names a target:

- **A backlog item:** `B07`, `F03`, `T11`
- **A plan key:** `M01-S01`, `M01-B07`
- **A milestone:** `M01` — peek the *next* unplanned slice or first ready slice

If the target is ambiguous, ask once. Do not auto-pick.

## Step 3 — Load Context Silently

- The item entry in `.hv/TODO.md` (and the overflow file at `.hv/<bugs|features|tasks>/<id>.md` if it exists)
- The plan file at `.hv/plans/<key>.md` if one exists
- Milestone context at `.hv/milestones/<MID>.md` if applicable
- Relevant `KNOWLEDGE.md` topics via `.hv/bin/hv-knowledge-query <topics…>`
- Recent git history: `git log --oneline -20`
- Recent commits touching probable target files: `git log --oneline -- <path>`

If a plan exists at `.hv/plans/<key>.md`, the peek largely restates it (plus any updates from recent context). If no plan exists, the peek is your own decomposition — and the user should consider running `/hv-plan` instead of `/hv-work` if alignment matters.

## Step 4 — Produce the Peek

Print this structure to chat. **Nothing else** — no preamble, no recap of what context you read.

```
Peek for <target>:

Approach
  <one paragraph — the shape of what I'd do and why this over alternatives>

Files I'd touch
  - <path>  — <reason>
  - <path>  — <reason>

Files I'd create
  - <path>  — <reason>

Tests I'd add
  - <test name or location>  — <what it verifies>

Assumptions I'm making
  - <named assumption that, if wrong, changes the approach>
  - <named assumption that, if wrong, changes the approach>

Known unknowns
  - <thing I'd resolve mid-flight>  (will pause if unresolvable)
  - <thing I'd resolve mid-flight>  (will pause if unresolvable)

If any of this is wrong, push back before /hv-work runs.
```

Be specific. *"I'd touch the auth code"* is useless — cite paths. If you don't know the path well enough to cite it, say so under Known unknowns.

## Step 5 — Stop

Do **not** auto-invoke `/hv-work`, write a plan, or take any action. The point of this skill is the gate.

The user reviews and either:

- Says *"go"* — they invoke `/hv-work <target>` themselves
- Pushes back — they redirect, you restate the peek with corrections
- Asks for a written plan — offer `/hv-plan <target>`

## Key Principles

- **Pure read.** No writes, no commits, no helper calls beyond reads.
- **Be specific.** Generic peeks are useless. Cite paths, test names, function names.
- **Name assumptions.** The whole skill's value is making implicit choices visible.
- **Stop after the peek.** No auto-continuation; the user's pushback is the point.
- **Plan beats peek for high-stakes work.** Offer `/hv-plan` if the user wants something durable rather than ephemeral.
