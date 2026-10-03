# Umbrella mode

Used by `/hv-work` Step 4.5, `/hv-capture` Step 4.6, `/hv-spike` Step 2.5, `/hv-refactor` Step 1.5 umbrella fanout, and indirectly by every skill that branches on umbrella mode. The reference covers the canonical mechanics; skill-local carriers (per-step routing, `--repo` plumbing into specific verbs, dispatch shape) stay inline at each call site.

An umbrella project hosts shared `.hv/` coordinator state at its root, while git history and code live in registered sub-repos under it. The umbrella root has no `.git/` of its own; each sub-repo has its own.

## When umbrella mode is on

Umbrella mode is in effect when `.hv/repos.json` registers ≥1 sub-repo. The config flag `umbrella.enabled` in `.hv/config.json` is informational — data is the truth.

```bash
hv repo umbrella             # exit 0 = umbrella, exit 1 = not (data.umbrella under --json)
hv repo umbrella -C <dir>    # callers that already know the directory (e.g. captured before any `cd`)
```

## The registry — `.hv/repos.json`

Each entry has a `name` and a `path` (relative to the umbrella root). Read it through `hv repo resolve` (below) rather than re-parsing the JSON.

## The `Repos:` field on TODO items

Captured items carry the affected sub-repo(s) so `/hv-work` can route the wave correctly. Single-repo items use one name; multi-repo items use a comma-separated list:

```
- [ ] [F07] add auth endpoint  Created: 2026-05-11  Repos: api
- [ ] [F08] cross-cut error type  Created: 2026-05-11  Repos: web, api
```

Parse the field with the canonical field reader:

```bash
hv item field get <ID> --name repos
```

Under umbrella mode, items lacking `Repos:` cannot be routed by `/hv-work` — see *Walk-up convenience* below for the single-repo exception, and `/hv-capture` Step 4.6 for how items get tagged at capture time.

## Resolution verbs

Both resolvers exit 3 (`resolution`), not 0, on no-match.

- `hv repo which` — resolve cwd → sub-repo. **Exits 0** with the name on stdout (`data.name` and the absolute `data.path` under `--json`) when cwd is inside a registered sub-repo (including its Layout B worktree); **exit 3** otherwise, including when a stray `.hv/` inside a registered sub-repo masks the umbrella (the message names it).
- `hv repo resolve <name>…` — validate every name, one positional each. **Exits 0** with `data.repos: [{name, path}, …]` (absolute paths) under `--json` when all names resolve; **exit 3** naming every missing one if any fail.

Every `hv` verb finds the umbrella root itself by walking up to the nearest `.hv/`; there is no separate umbrella-root lookup.

(Compare to `hv status show <branch>`, which returns `active: false` with exit 0 on no-match — do not blur the distinction.)

## Walk-up convenience

When `/hv-work` is invoked from a cwd that resolves via `hv repo which`, the resolved sub-repo defaults as the wave's scope for items lacking explicit `Repos:`. This is the single-repo cwd convenience only — it does not generalize.

Multi-repo items always need the captured `Repos:` field. There is no cwd default for them, because cwd resolves to at most one sub-repo.

## Branch creation

Three patterns, all driven from the umbrella root (the orchestrator stays there so it can read/write `.hv/`); workers `cd` into the sub-repo path before any git operation.

**Single sub-repo (branch isolation):**

```bash
(cd <repo> && git checkout -b <branch>)
hv status add <branch> --items <ID>[,<ID>...] --repo <repo>
```

**Multiple sub-repos (branch isolation):**

```bash
hv git branch <branch> --repos <csv>
hv status add <branch> --items <ID>[,<ID>...] --repos <csv>
```

`hv git branch` is atomic: a precheck refuses (exit 4) for ALL repos if the branch exists in ANY one, before any branch is written. Its `--repos` takes no spaces after commas, so drop them from the `Repos:` value first.

**Single sub-repo with worktree (Layout B):**

```bash
(cd <repo> && git branch <branch>)
WT=$(hv git worktree-path <branch> --repo <repo>)
git -C <repo> worktree add "$WT" <branch>
hv status add <branch> --items <ID>[,<ID>...] --worktree "$WT" --repo <repo>
```

`hv git worktree-path` produces the canonical Layout B path `<umbrella>/.claude/worktrees/<repo>/<branch>` — use it for both `worktree add` and `hv status add`. `hv ship merge` and `hv ship pr` remove that worktree themselves before they integrate the branch.

For the broader picture of when to use branch vs worktree isolation, see `references/isolation-patterns.md`.

## Status registration

- `hv status add <branch> --items <ids-csv> [--worktree <path>] [--repo <name>] [--if-absent]` — uniqueness key becomes `(branch, repo)` when `--repo` is set. An unregistered `--repo` exits 3.
- `hv status add <branch> --items <ids-csv> --repos <repos-csv> [--worktrees <paths-csv>] [--if-absent]` — writes one entry per `(branch, repo)` pair. `--worktrees` is optional; if given, its length must equal `--repos` (else exit 2). `--repo` and `--repos` together exit 2.
- `hv status rm <branch> [--repo <name>]` — in umbrella mode, **pass `--repo`** or umbrella-tagged entries leak. Without `--repo`, only legacy entries (repo: null/missing) are removed; umbrella entries are preserved. It also deletes the branch's handoff note.

## Merge / PR with `--repo`

```bash
echo "<merge message>" | hv ship merge <branch> --body-file - --repo <repo>
echo "<body>"          | hv ship pr    <branch> --title "<title>" --body-file - --repo <repo>
```

Each operates within the sub-repo's `.git/`. At the umbrella root without `--repo`, both exit 2 — there's no `.git/` at the umbrella root to merge into.

## Issue mode in an umbrella

**Issue mode** (`backlog.backend: "issues"`; `references/issue-mode.md`, *Umbrella*) puts each sub-repo's items on that sub-repo's own tracker, so `.hv/BACKLOG.md` and `Repos:` tagging by `/hv-capture` Step 4.6 change shape:

- **One repo per item.** Capture needs a target: `--repos <name>` or a cwd inside a sub-repo. A multi-repo item is refused; capture one item per repo and link them with `Related:` (qualified refs allowed). `Repos` cannot be changed on an existing item.
- **Qualified IDs.** `<repo>#<n>` and `<repo>:<ID>` always resolve; a bare `F42` / `#42` resolves only when exactly one sub-repo has it, else exit 2 listing the candidates. Created IDs come back qualified; `hv backlog list` shows them as `<repo>:<ID>`.
- **`--repo` plumbing.** `hv ship pr ... --items ... --repo <repo>` (falls back to the cwd's sub-repo), `hv ship pr-merge <pr> --repo <repo>` (required at the umbrella root), and `hv release milestone-check|notes --from issues|close-milestone ... --repo <repo>` (required at the umbrella root, exit 2 without).

## What this reference does NOT cover

- **Isolation patterns** (branch vs worktree, the decision table, the isolation guard) — see `references/isolation-patterns.md`.
- **Multi-repo parallelism safety** — `references/isolation-patterns.md` covers the rule (cross-repo parallel workers are safe by construction because each sub-repo has its own `.git/index`).
- **`hv-capture`'s `Repos:` tagging interaction** — how items acquire their `Repos:` field at capture time (cwd inference, AskUserQuestion shape, loop-mode auto-pick) is per-skill carrier semantics; see `/hv-capture` Step 4.6 inline.
