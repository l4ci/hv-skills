---
name: hv-migrate
description: One-shot migrations. `/hv-migrate v4` is the v3 → v4 codemod (versioned arg required): it rewrites references to the 8 commands cut by M01, moves `.hv/CONTEXT.md` terms (and each sub-repo's legacy context file in umbrella projects) into `## Glossary` in KNOWLEDGE.md via `hv glossary import`, and removes stale context scripts, with a backup under `.hv/migrate-backup/` first. `/hv-migrate issues [--dry-run|--apply] [--limit N]` moves a file backlog onto the GitHub/GitLab issue tracker (resumable, never flips `backlog.backend`). `--dry-run` is default, `--apply` writes, `--verbose` adds per-file diffs; reruns are idempotent. Refuses on uncommitted changes outside `.hv/` or a pre-3.0 project. Use on "migrate to v4", "/hv-migrate v4", upgrading from 3.x to 4.0, "migrate backlog to issues", "/hv-migrate issues".
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🪄  hv-migrate  ·  one-shot codemod for hv-skills major-version cuts
  triggers: "migrate to v4", "/hv-migrate issues"  ·  pairs: hv-init, hv-learn
════════════════════════════════════════════════════════════════════════
```

# hv-migrate — v3 → v4 Codemod

`/hv-migrate v4` is the v4.0 safety net. Without it, a project upgrading from v3.x carries dangling references to 8 commands that no longer exist (`/hv-c`, `/hv-assume`, `/hv-rm`, `/hv-undo`, `/hv-context`, `/hv-docs`, `/hv-issues`, `/hv-map`) plus a `.hv/CONTEXT.md` whose helpers have been renamed. One invocation rewrites everything `hv migrate v4` can resolve unambiguously and prints a manual-review list for what it can't.

## When to Use

- Upgrading a project from hv-skills 3.x to 4.0.
- After a fresh `hv-skills` install on a project that was using a pre-4.0 plugin.
- Whenever `hv config show version` (the legacy top-level stamp) reports a pre-4.0 string and you've also bumped the plugin to 4.0+.

## When NOT to Use

- The project is already on v4.0 — re-running is a noop, but there's no reason to run.
- The project is a fresh `/hv-init` on a 4.0 plugin — nothing to migrate.
- The project is in umbrella mode (`.hv/repos.json` registers sub-repos). Umbrella projects are supported — each sub-repo's `.hv/contexts/<name>/CONTEXT.md` migrates into its own `.hv/knowledge/<name>/KNOWLEDGE.md` Glossary.

## Step 1 — Task List

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Parse args* — resolve the version arg + `--dry-run`/`--apply`/`--verbose` (Step 2)
2. *Dry-run preview* — show the user exactly what would change (Step 3)
3. *Confirm + apply* — gate the destructive write through `AskUserQuestion` (Step 4)
4. *Report* — summarize the result, surface backup path + manual-review list (Step 5)

## Step 2 — Parse Args

The `args` value passed at invocation is the user's literal arg string after `/hv-migrate`. Required: the target (`v4` or `issues`; `issues` follows the section at the end). Optional: `--apply`, `--verbose`, `--dry-run`.

Pass `--apply` and `--verbose` through to `hv migrate`; `--dry-run` is the skill's default and is never passed (`hv` has no such flag). `hv migrate` validates the target itself and rejects unknown versions with a clear error (exit 2).

| Arg | Effect |
|---|---|
| `v4` (positional) | Run the v4 codemod. The only accepted version at hv-skills 4.0. |
| `--dry-run` | Default. Show the plan; write nothing. |
| `--apply` | Write the plan. Required for any disk mutation. |
| `--verbose` | Add per-file unified diffs to the summary. |

If the user types `/hv-migrate` with no version, `hv migrate` exits 2 with a usage hint — surface that verbatim and stop.

## Step 3 — Dry-Run Preview

Run the preview (no `--apply`) regardless of which flags the user passed:

```bash
hv migrate v4 [--verbose]
```

The output names every file that would be rewritten, how many references in each, the CONTEXT.md migration plan, the legacy context scripts to remove, and any manual-review items (ambiguous `/hv-issues` and `/hv-map` occurrences).

If it refuses on a safety precondition (exit 4) — uncommitted non-`.hv/` changes, pre-3.0 version, or running inside a backup directory — surface its stderr verbatim and stop. Exit 3 (no readable `.hv/config.json` version) means run `/hv-init` first; exit 5 means `git` is missing or this is not a git repo. The user resolves the precondition (commit or run `/hv-init`) and re-invokes `/hv-migrate v4` themselves.

If it reports `noop: project is already on v4`, print one line — *"Already on v4. Nothing to migrate."* — and exit.

## Step 4 — Confirm + Apply

If the user's original args already included `--apply`, skip the confirmation gate and run the apply pass directly:

```bash
hv migrate v4 --apply [--verbose]
```

Otherwise, use the `AskUserQuestion` tool with the dry-run summary in front of the user:

- **Header:** `"Apply"`
- **Question:** *"Apply the rewrites above? Files are backed up to `.hv/migrate-backup/<timestamp>/` before any write."*
- **Options** (single-select):
  1. `"Apply (Recommended)"` — runs `hv migrate v4 --apply`.
  2. `"Apply + verbose diffs"` — runs `hv migrate v4 --apply --verbose`.
  3. `"Cancel"` — print *"Cancelled — no changes written."* and exit.

Plain-text fallback: *"Apply the rewrites above? (yes/no)"* — `yes` runs `--apply`; anything else cancels. See `references/ask-user-question-fallback.md`.

Exit 4 during `--apply` can come after writing started: a CONTEXT glossary import failed (`data.blockedBy: glossary-import`, `data.changed: true`). Surface the message verbatim (it names the backup path the original was kept at), tell the user to resolve the conflict and re-run, and stop.

## Step 5 — Report

`hv migrate` stdout carries the summary already; pass it through. If `--apply` produced manual-review items, repeat them once at the end with the suggested next step:

> *"Manual-review items above are ambiguous: `/hv-issues` could be `--from-github` or `--from-gitlab`; `/hv-map` could be `/hv-init --map` (first-run scaffolding) or simply removed. Resolve each by hand."*

If it migrated terms from `.hv/CONTEXT.md`, suggest one verification step:

> *"Verify `.hv/KNOWLEDGE.md` (## Glossary) carries every migrated term as expected. The original `.hv/CONTEXT.md` is preserved under `.hv/migrate-backup/<timestamp>/`."*

Skip silently when there's nothing to surface beyond its output.

## Target: `issues` — file backlog → issue tracker

`/hv-migrate issues [--dry-run|--apply] [--limit N]` moves a file-backend project onto GitHub/GitLab issues via `hv migrate issues`. Skip Steps 2-5 above (they are the v4 codemod). Refuses umbrella mode (exit 4): migrate each sub-repo separately. Exit 3 means `.hv/BACKLOG.md` is missing. Needs `gh`/`glab` authenticated (exit 5 otherwise).

1. **Dry run** (default; no tracker writes):

   ```bash
   hv migrate issues
   ```

   Read the planned operations and the would-be map (placeholder numbers). Check the item count against `hv backlog list`: open Bugs/Features/Tasks and planned/active milestones migrate; completed items, `ARCHIVE.md` and shipped/archived milestones stay in the files as history (after the flip `hv milestone list` shows only planned and active milestones). `Related:` IDs of completed items are dropped from the field and listed in the issue body; `Since:` is kept. Surface any `warning:` lines.

2. **Confirm** with `AskUserQuestion` (header `"Apply"`; options `"Apply (Recommended)"`, `"Apply 10 items first (--limit 10)"`, `"Cancel"`), or skip when the args include `--apply`. This creates real issues and cannot be undone by `hv`.

3. **Apply** (resumable):

   ```bash
   hv migrate issues --apply [--limit N]
   ```

   Writes are paced by `issues.bulkPaceMs`. Exit 6 (rate-limited): the map is saved; tell the user to wait, then re-run the same command; do not loop. Exit 5 (tracker or auth failure): the map is saved too; report the `N of M migrated` message and stop. Re-running a finished migration makes no tracker calls. Notes, slice plans and `Related:` rewrites happen only after every item exists; the frozen banner on `.hv/BACKLOG.md` appears only when the migration is complete.

4. **Flip.** `--apply` never changes the backend. When it prints `Next: /hv-config backlog.backend=issues`, offer to run exactly that.

5. **Check after the flip:**
   - `hv backlog list` shows the same open items.
   - `hv milestone list` shows the milestones with their statuses.
   - A migrated design or plan reads back: `hv design show <ID>` / `hv plan show <key>`.
   - Commit `.hv/issue-map.json` (old ID → new ID and URL). `hv` does not resolve old IDs through it.

See `docs/usage/issue-backend.md`.

## Rules

- **No noise.** Report results, not process. Don't narrate the steps.
- **`hv` owns refusal.** The skill never decides whether to migrate — it surfaces the verb's verdict. Safety preconditions live in one place.
- **Backups before writes.** `--apply` ALWAYS writes a timestamped backup tree before mutating anything. The user owns cleanup of `.hv/migrate-backup/` over time.
- **One major version per release.** v4.0 carries `v4`; future majors add their own arg. The codemod for cuts is not a multi-version dispatcher — it's specific to the cuts of one release.

## References

- [`banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`issue-mode.md`](../references/issue-mode.md) — How issue mode differs from file mode.
- [`ask-user-question-fallback.md`](../references/ask-user-question-fallback.md) — Plain-text fallback shape for AskUserQuestion-less hosts.
