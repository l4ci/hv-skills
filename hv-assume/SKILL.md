---
name: hv-assume
description: Print the orchestrator's intended approach for an item, slice, or milestone — files it would touch, files it would create, tests it would add, assumptions it's making, known unknowns it would resolve mid-flight. Read-only; writes nothing. Use before /hv-work to verify alignment, especially on size-M+ items where corrections after the fact are expensive.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🔮  hv-assume  ·  peek the orchestrator's intended approach
  triggers: "assume B07", "peek M01-S01"  ·  pairs: hv-plan, hv-work
════════════════════════════════════════════════════════════════════════
```

# hv-assume — Approach Peek (Read-Only)

**No writes. No commits. No tool calls beyond reads.**

**Orchestrator-model contract (loop mode).** When `/hv-work` invokes this skill in loop mode (via the F34 uncertainty pre-flight in `/hv-work` Step 4), the dispatch is via the `Skill` tool — the peek runs inline in `/hv-work`'s session and inherits its model. Since `/hv-work` runs under `models.orchestrator` (per `.hv/config.json`, default `opus`), the loop-mode peek benefits from orchestrator-grade design judgment. If a future change moves the dispatch to the `Agent` tool, the call site MUST explicitly pass `model: orchestrator` to preserve this. Manual invocations from `/hv-next` or the user's prompt are unconstrained — the user is in the loop and can correct any peek that under-performs.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

## Step 2 — Resolve Target

The user names a target:

- **A backlog item:** `B07`, `F03`, `T11`
- **A plan key:** `M01-S01`, `M01-B07`
- **A milestone:** `M01` — peek the *next* unplanned slice or first ready slice

If the target is ambiguous, ask once. Do not auto-pick.

## Step 3 — Load Context Silently

Apply the canonical pre-planning context-load protocol (`references/context-load-protocol.md`) — it lists the common reads (TODO entry, plan, milestone, K+D queries, recent git history) and the K+D query mechanics it cites. For this skill, the reads also include:

- For backlog-item targets: parse the entry's `Repos:` field (the value after `Repos:` up to the next field name — `Detail:`, `Related:`, `Milestone:` — or end-of-line). If umbrella mode is on (`.hv/config.json` `umbrella.enabled` is true OR `.hv/repos.json` exists with entries) AND the item carries a `Repos:` value, resolve it to absolute sub-repo path(s) via `.hv/bin/hv-resolve-repos` (or `parse_repos_csv` + `load_repos()` for in-process callers — same registry). Multi-repo items resolve to a list; keep all entries for the peek render. Skip resolution for slice / milestone targets (umbrella-flat per M02 acceptance).

**Issue these as parallel tool calls in a single response** — they're independent.

If `hv-decisions-query` returns matched entries, surface them in the peek under "Hard boundaries to respect" (between "Files I'd create" and "Tests I'd add") — one line each: `- <decision title> — <one-line summary>`. The user's job during review is to spot whether the planned approach conflicts with any of these; if it does, they push back before code lands. Omit the section entirely if nothing matched.

If a plan exists at `.hv/plans/<key>.md`, the peek largely restates it (plus any updates from recent context). If no plan exists, the peek is your own decomposition — and the user should consider running `/hv-plan` instead of `/hv-work` if alignment matters.

## Step 4 — Produce the Peek

Print this structure to chat. **Nothing else** — no preamble, no recap of what context you read.

```
Peek for <target>:

Approach
  <one paragraph — the shape of what I'd do and why this over alternatives>

Repo
  <name> (<absolute-sub-repo-path>)        # omit when single-repo or no Repos: tag
  <name2> (<absolute-sub-repo-path-2>)     # one line per repo for multi-repo items

Files I'd touch
  - <path>  — <reason>
  - <path>  — <reason>

Files I'd create
  - <path>  — <reason>

Hard boundaries to respect
  - <decision title>  — <one-line summary>
  - <decision title>  — <one-line summary>

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

Omit `Hard boundaries to respect` if no DECISIONS topics matched.

Omit `Repo` entirely when umbrella mode is off, the target is a slice / milestone (umbrella-flat per M02 acceptance), or the item has no `Repos:` tag (single-repo projects under umbrella mode also skip). When present, render as `<name> (<absolute-path>)` resolved via `.hv/repos.json`. Multi-repo items render one indented line per resolved sub-repo under the `Repo` heading — so the user can verify every dispatch target before `/hv-work` runs.

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
