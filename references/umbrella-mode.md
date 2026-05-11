# Umbrella mode

Used by `/hv-work` Step 4.5, `/hv-capture` Step 4.6, `/hv-spike` Step 2.5, `/hv-refactor` Step 1.5 umbrella fanout, and indirectly by every skill that branches on umbrella mode. The reference covers the canonical mechanics; skill-local carriers (per-step routing, `--repo` plumbing into specific helpers, dispatch shape) stay inline at each call site.

An umbrella project hosts shared `.hv/` coordinator state at its root, while git history and code live in registered sub-repos under it. The umbrella root has no `.git/` of its own; each sub-repo has its own.

## When umbrella mode is on

Umbrella mode is in effect when `.hv/repos.json` registers ≥1 sub-repo. The config flag `umbrella.enabled` in `.hv/config.json` is informational — data is the truth.

```bash
.hv/bin/hv-umbrella-on            # prints "yes" or "no"; always exits 0
.hv/bin/hv-umbrella-on <dir>      # optional cwd-already-known callers (e.g. captured before any `cd`)
```

## The registry — `.hv/repos.json`

Each entry has a `name` and a `path` (relative to the umbrella root). The canonical Python loader is `hvlib.load_repos()` — in-process callers should prefer it over re-parsing the JSON.

## The `Repos:` field on TODO items

Captured items carry the affected sub-repo(s) so `/hv-work` can route the wave correctly. Single-repo items use one name; multi-repo items use a comma-separated list:

```
- [ ] [F07] add auth endpoint  Created: 2026-05-11  Repos: api
- [ ] [F08] cross-cut error type  Created: 2026-05-11  Repos: web, api
```

Parse the field with the canonical helper (which uses `hvlib.parse_todo_fields` under the hood):

```bash
.hv/bin/hv-todo-field <ID> repos
```

Under umbrella mode, items lacking `Repos:` cannot be routed by `/hv-work` — see *Walk-up convenience* below for the single-repo exception, and `/hv-capture` Step 4.6 for how items get tagged at capture time.

## Resolution helpers

All three resolvers honor the resolve contract: exit 1 (not 0) on no-match.

- `.hv/bin/hv-resolve-repo` — resolve cwd → sub-repo name. **Exits 0** with the name on stdout when cwd is inside a registered sub-repo (including its Layout B worktree); **exit 1** otherwise.
- `.hv/bin/hv-resolve-repos "<csv>"` — validate every name in a comma-separated list. **Exits 0** with a JSON array `[{name, path}, …]` when all names resolve; **exit 1** with the missing names on stderr if any fail; exit 2 on usage error.
- `.hv/bin/hv-resolve-umbrella` — walk up from cwd to find the umbrella `.hv/`. **Exits 0** with the umbrella path on stdout; **exit 1** if no umbrella is reachable; **exit 2** when a stray `.hv/` inside a registered sub-repo masks the umbrella.
- `hvlib.load_repos()` — in-process equivalent for Python callers; returns `{name: absolute_path, …}`.

(Compare to `hv-status-repo-for` and similar lookups, which exit 0 on no-match per the lookup contract — do not blur the distinction.)

## Walk-up convenience

When `/hv-work` is invoked from a cwd that resolves via `hv-resolve-repo`, the resolved sub-repo defaults as the wave's scope for items lacking explicit `Repos:`. This is the single-repo cwd convenience only — it does not generalize.

Multi-repo items always need the captured `Repos:` field. There is no cwd default for them, because cwd resolves to at most one sub-repo.

## Branch creation

Three patterns, all driven from the umbrella root (the orchestrator stays there so it can read/write `.hv/`); workers `cd` into the sub-repo path before any git operation.

**Single sub-repo (branch isolation):**

```bash
(cd <repo> && git checkout -b <branch>)
.hv/bin/hv-status-add --repo <repo> <branch> <ID>[,<ID>...]
```

**Multiple sub-repos (branch isolation):**

```bash
.hv/bin/hv-multi-branch-create --branch <branch> --repos "<csv>"
.hv/bin/hv-status-add-multi --branch <branch> --items <ID>[,<ID>...] --repos "<csv>"
```

`hv-multi-branch-create` is atomic: a precheck collides ALL repos if the branch exists in ANY one, before any branch is written.

**Single sub-repo with worktree (Layout B):**

```bash
(cd <repo> && git branch <branch>)
WT=$(.hv/bin/hv-worktree-path --repo <repo> <branch>)
git -C <repo> worktree add "$WT" <branch>
.hv/bin/hv-status-add --repo <repo> <branch> <ID>[,<ID>...] "$WT"
```

`hv-worktree-path` produces the canonical Layout B path `<umbrella>/.claude/worktrees/<repo>/<branch>` — use it for all three of `worktree add`, `hv-status-add`, and later `hv-worktree-clear`.

For the broader picture of when to use branch vs worktree isolation, see `references/isolation-patterns.md`.

## Status registration

- `hv-status-add [--if-absent] [--repo <name>] <branch> <ID>[,<ID>...] [worktree-path]` — uniqueness key becomes `(branch, repo)` when `--repo` is set.
- `hv-status-add-multi [--if-absent] --branch <name> --items <ids-csv> --repos <repos-csv> [--worktrees <paths-csv>]` — writes one entry per `(branch, repo)` pair. `--worktrees` is optional; if given, its length must equal `--repos`.
- `hv-status-remove [--repo <name>] <branch>` — in umbrella mode, **pass `--repo`** or umbrella-tagged entries leak. Without `--repo`, only legacy entries (repo: null/missing) are removed; umbrella entries are preserved.

## Merge / PR with `--repo`

```bash
echo "<merge message>" | .hv/bin/hv-merge --repo <repo> <branch>
echo "<body>"          | .hv/bin/hv-pr    --repo <repo> <branch> "<title>"
```

Each operates within the sub-repo's `.git/`. Without `--repo`, both helpers hit the umbrella-cwd guard (`hv-require-git-context`) and refuse to run — there's no `.git/` at the umbrella root to merge into.

## What this reference does NOT cover

- **Isolation patterns** (branch vs worktree, the decision table, the isolation guard) — see `references/isolation-patterns.md`.
- **Multi-repo parallelism safety** — `references/isolation-patterns.md` covers the rule (cross-repo parallel workers are safe by construction because each sub-repo has its own `.git/index`).
- **`hv-capture`'s `Repos:` tagging interaction** — how items acquire their `Repos:` field at capture time (cwd inference, AskUserQuestion shape, loop-mode auto-pick) is per-skill carrier semantics; see `/hv-capture` Step 4.6 inline.
