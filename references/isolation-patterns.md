# Isolation patterns

Used by `/hv-work` Step 5 (the single primary consumer today). The reference enumerates the 4 isolation patterns + the umbrella-mode worktree variant, plus the isolation-guard contract that fires when ≥2 commit-producing parallel workers race on a shared `.git/index`.

`/hv-work` isolates each cycle from main by creating a feature branch or a separate worktree; the choice depends on `work.isolation` in `.hv/config.json` (`"branch"` or `"worktree"`).

## Decision table

| Scope | Isolation | Pattern |
|---|---|---|
| Single-repo | branch | `git checkout -b <branch>` + `hv-status-add <branch> <items>` |
| Single-repo | worktree | `git branch <branch>` + `git worktree add .claude/worktrees/<branch>` + `hv-status-add <branch> <items> <path>` |
| Umbrella (sub-repo) | branch | `(cd <repo> && git checkout -b <branch>)` + `hv-status-add --repo <repo> <branch> <items>` |
| Umbrella (sub-repo) | worktree (Layout B) | `(cd <repo> && git branch <branch>)`, `hv-worktree-path --repo <repo> <branch>`, `git -C <repo> worktree add "$WT" <branch>`, `hv-status-add --repo <repo> <branch> <items> "$WT"` |
| Umbrella (multi-repo) | branch | `hv-multi-branch-create --branch <branch> --repos "<csv>"` + `hv-status-add-multi --branch <branch> --items <ids-csv> --repos "<csv>"` |

`hv-multi-branch-create` precheck collides ALL repos if the branch exists in ANY one — no partial creation. Multi-repo workers are safe under either isolation mode (see *Cross-repo parallelism* below).

## Per-pattern code

The table is the contract; these are the invocations spelled out for the worker brief.

**Single-repo, branch:**

```bash
git checkout -b <branch>
.hv/bin/hv-status-add <branch> <ID>[,<ID>...]
```

**Single-repo, worktree:**

```bash
git branch <branch>
git worktree add .claude/worktrees/<branch> <branch>
.hv/bin/hv-status-add <branch> <ID>[,<ID>...] .claude/worktrees/<branch>
```

**Umbrella sub-repo, Layout B worktree:**

```bash
(cd <repo> && git branch <branch>)
WT=$(.hv/bin/hv-worktree-path --repo <repo> <branch>)
git -C <repo> worktree add "$WT" <branch>
.hv/bin/hv-status-add --repo <repo> <branch> <ID>[,<ID>...] "$WT"
```

Full umbrella branch-creation ceremony (single + multi) lives in `references/umbrella-mode.md`; do not duplicate it here.

## Isolation guard — when it fires

Under the F11 default (write-only workers, orchestrator commits), the guard is defense-in-depth — workers don't write index entries, so the race condition that motivated the guard is contained at the architectural level. The guard still fires fatally when:

- `≥2` commit-producing parallel workers are dispatched, AND
- `work.isolation == "branch"`, AND
- they share one `.git/index` (i.e. they target the same sub-repo, or no umbrella).

The 2026-05-02 DECISIONS entry (*Isolation guard for parallel branch-isolated commit-producing workers*) is the canonical statement — rule, *Why*, **Forbids**, **Permits**. Consult that entry before relaxing or reshaping the guard.

## Cross-repo parallelism is safe by construction

Multi-repo workers under branch isolation are safe because each sub-repo has its own `.git/index`. Two workers committing simultaneously into `web/.git` and `api/.git` cannot race the way two workers committing into a single `.git/index` can. The guard scopes to within-one-repo by design — it intentionally does NOT block cross-repo parallel commits.

This is why multi-repo waves dispatched by `/hv-work` (one branch, N sub-repos, M workers) run in parallel under either isolation mode without further accommodation.

## Umbrella mechanics

This reference covers only the isolation-and-worktree-creation aspects of umbrella mode. The broader umbrella concept — the registry (`.hv/repos.json`), resolution helpers (`hv-resolve-repo`, `hv-resolve-repos`, `hv-resolve-umbrella`), the `Repos:` field on TODO items, walk-up convenience, merge/PR `--repo` plumbing — lives in `references/umbrella-mode.md`. Cite it from call sites that need both halves.

## What this reference does NOT cover

- **The umbrella-mode concept, registry, and helpers** — see `references/umbrella-mode.md`.
- **Worker dispatch under each isolation mode** (Skill-tool shape, parallel batching, worker-brief construction) — see `/hv-work` Step 6 inline.
- **The full F11 write-only-workers default** (why workers don't commit, how the orchestrator collects diffs and commits) — see `KNOWLEDGE.md` 2026-05-07 entry.
