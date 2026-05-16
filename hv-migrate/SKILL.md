---
name: hv-migrate
description: One-shot codemod for v3 → v4 upgrades. Versioned arg required — `/hv-migrate v4`. Rewrites references to 8 commands cut by M01 (across BACKLOG, plans, designs, handoffs, qa, milestones, KNOWLEDGE, DECISIONS, project CLAUDE.md), migrates `.hv/CONTEXT.md` terms into `.hv/KNOWLEDGE.md` (## Glossary) via `hv-glossary-write --batch`, and removes stale `.hv/bin/hv-context-*` files left behind. `--dry-run` is default; `--apply` writes; `--verbose` adds per-file diffs. Idempotent — a clean second `--apply` rewrites zero files. Refuses on uncommitted changes outside `.hv/`, pre-3.0 project version, umbrella projects (F21), or when run inside an existing backup directory. Use on "migrate to v4", "/hv-migrate v4", upgrading hv-skills from 3.x to 4.0.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🪄  hv-migrate  ·  one-shot codemod for hv-skills major-version cuts
  triggers: "migrate to v4", "/hv-migrate v4"  ·  pairs: hv-init, hv-learn
════════════════════════════════════════════════════════════════════════
```

# hv-migrate — v3 → v4 Codemod

`/hv-migrate v4` is the v4.0 safety net. Without it, a project upgrading from v3.x carries dangling references to 8 commands that no longer exist (`/hv-c`, `/hv-assume`, `/hv-rm`, `/hv-undo`, `/hv-context`, `/hv-docs`, `/hv-issues`, `/hv-map`) plus a `.hv/CONTEXT.md` whose helpers have been renamed. One invocation rewrites everything `bin/hv-migrate` can resolve unambiguously and prints a manual-review list for what it can't.

## When to Use

- Upgrading a project from hv-skills 3.x to 4.0.
- After a fresh `hv-skills` install on a project that was using a pre-4.0 plugin.
- Whenever `cat .hv/config.json | jq .version` reports a pre-4.0 string and you've also bumped the plugin to 4.0+.

## When NOT to Use

- The project is already on v4.0 — re-running is a noop, but there's no reason to run.
- The project is a fresh `/hv-init` on a 4.0 plugin — nothing to migrate.
- The project is in umbrella mode (`.hv/repos.json` registers sub-repos). v4.0 GA refuses; umbrella support comes with F21.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Parse args* — resolve the version arg + `--dry-run`/`--apply`/`--verbose` (Step 2)
2. *Dry-run preview* — show the user exactly what would change (Step 3)
3. *Confirm + apply* — gate the destructive write through `AskUserQuestion` (Step 4)
4. *Report* — summarize the result, surface backup path + manual-review list (Step 5)

## Step 2 — Parse Args

The `args` value passed at invocation is the user's literal arg string after `/hv-migrate`. Required: the version selector (e.g., `v4`). Optional: `--apply`, `--verbose`, `--dry-run`.

Pass-through to the helper unchanged. The helper validates the version string itself and rejects unknown versions with a clear error (exit 2).

| Arg | Effect |
|---|---|
| `v4` (positional) | Run the v4 codemod. The only accepted version at hv-skills 4.0. |
| `--dry-run` | Default. Show the plan; write nothing. |
| `--apply` | Write the plan. Required for any disk mutation. |
| `--verbose` | Add per-file unified diffs to the summary. |

If the user types `/hv-migrate` with no version, the helper exits 2 with a usage hint — surface that verbatim and stop.

## Step 3 — Dry-Run Preview

Run the helper in dry-run mode regardless of which flags the user passed:

```bash
.hv/bin/hv-migrate v4 [--verbose]
```

The output names every file that would be rewritten, how many references in each, the CONTEXT.md migration plan, the list of stale `.hv/bin/hv-*` files to remove, and any manual-review items (ambiguous `/hv-issues` and `/hv-map` occurrences).

If the helper refuses on a safety precondition (exit 1) — uncommitted non-`.hv/` changes, pre-3.0 version, umbrella project, or running inside a backup directory — surface the helper's stderr verbatim and stop. The user resolves the precondition (commit, run `/hv-init`, switch to single-repo mode) and re-invokes `/hv-migrate v4` themselves.

If the helper reports `noop: project is already on v4`, print one line — *"Already on v4. Nothing to migrate."* — and exit.

## Step 4 — Confirm + Apply

If the user's original args already included `--apply`, skip the confirmation gate and run the apply pass directly:

```bash
.hv/bin/hv-migrate v4 --apply [--verbose]
```

Otherwise, use the `AskUserQuestion` tool with the dry-run summary in front of the user:

- **Header:** `"Apply"`
- **Question:** *"Apply the rewrites above? Files are backed up to `.hv/migrate-backup/<timestamp>/` before any write."*
- **Options** (single-select):
  1. `"Apply (Recommended)"` — runs `.hv/bin/hv-migrate v4 --apply`.
  2. `"Apply + verbose diffs"` — runs `.hv/bin/hv-migrate v4 --apply --verbose`.
  3. `"Cancel"` — print *"Cancelled — no changes written."* and exit.

Plain-text fallback: *"Apply the rewrites above? (yes/no)"* — `yes` runs `--apply`; anything else cancels. See `references/ask-user-question-fallback.md`.

## Step 5 — Report

Helper stdout carries the structured summary already; pass it through. If `--apply` produced manual-review items, repeat them once at the end with the suggested next step:

> *"Manual-review items above are ambiguous: `/hv-issues` could be `--from-github` or `--from-gitlab`; `/hv-map` could be `/hv-init --map` (first-run scaffolding) or simply removed. Resolve each by hand."*

If the helper migrated terms from `.hv/CONTEXT.md`, suggest one verification step:

> *"Verify `.hv/KNOWLEDGE.md` (## Glossary) carries every migrated term as expected. The original `.hv/CONTEXT.md` is preserved under `.hv/migrate-backup/<timestamp>/`."*

Skip silently when there's nothing to surface beyond the helper's output.

## Rules

- **No noise.** Report results, not process. Don't narrate the steps.
- **Helper owns refusal.** The skill never decides whether to migrate — it surfaces the helper's verdict. Safety preconditions live in one place.
- **Backups before writes.** `--apply` ALWAYS writes a timestamped backup tree before mutating anything. The user owns cleanup of `.hv/migrate-backup/` over time.
- **One major version per release.** v4.0 carries `v4`; future majors add their own arg. The codemod for cuts is not a multi-version dispatcher — it's specific to the cuts of one release.

## References

- [`banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`ask-user-question-fallback.md`](../references/ask-user-question-fallback.md) — Plain-text fallback shape for AskUserQuestion-less hosts.
