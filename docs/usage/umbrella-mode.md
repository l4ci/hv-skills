# Umbrella mode

Umbrella mode lets a single hv-skills coordinator span several independent git repositories that live side by side under one parent folder. Knowledge, decisions, vision, and the backlog live once at the umbrella; each sub-repo keeps its own history, branches, and remotes.

If you're using single-repo mode, this page doesn't apply to you. Single-repo behavior is unchanged.

## When to use it

Use umbrella mode when you maintain a small fleet of related repositories (say `~/projects/myorg/` containing `web/`, `api/`, and `shared/`) and you want one coordinator (one `KNOWLEDGE.md`, one `DECISIONS.md`, one `MILESTONES.md`, one backlog) instead of forking them into N copies. The typical signal: "I keep cross-pasting the same gotcha into three repos' notes."

## When NOT to use it

- **Single-repo project.** Don't enable. The single-repo path stays simpler and faster.
- **Monorepo.** Don't enable. A monorepo is one git repo; umbrella mode is for *multiple* repos under a parent.
- **Casually-grouped unrelated repos.** If the repos under your folder don't share knowledge, decisions, or planning concerns, umbrella mode adds bookkeeping for nothing.

## How it differs from single-repo

| Aspect | Single-repo | Umbrella |
|--------|-------------|----------|
| `.hv/` location | Repo root | Umbrella root (one level up from sub-repos) |
| Where helpers run git ops | The repo | The sub-repo for the current item (resolved via `Repos:` tag or `--repo` flag) |
| Worktree path | `<repo>/.claude/worktrees/<branch>` | `<umbrella>/.claude/worktrees/<repo>/<branch>` (Layout B) |
| `TODO.md`, `ARCHIVE.md`, `KNOWLEDGE.md`, `DECISIONS.md`, `MILESTONES.md` | Per-repo | Shared at the umbrella |
| `status.json` entries | Keyed by `branch` | Keyed by `(branch, repo)` |
| `.hv/handoff/<branch>.md` | One per branch | `.hv/handoff/<branch>@<repo>.md` (one per branch+repo) |
| Sub-repo git histories | n/a | Independent — no submodules, no version pinning |

Single-repo behavior is **completely unchanged**. Umbrella-aware helpers gate on `umbrella.enabled === true` in `.hv/config.json`. Without that flag, every skill behaves exactly as it did before.

## Enabling it

1. `cd` to the umbrella folder, the parent that contains your sub-repos as immediate children.
2. Run `/hv-init`.
3. When `/hv-init` detects two or more immediate git children, it offers umbrella mode via `AskUserQuestion`, listing the children it found.
4. Accept. `/hv-init` calls `hv-umbrella-init`, which writes `.hv/repos.json` with the repos you chose and sets `umbrella.enabled: true` in `.hv/config.json`. If the umbrella itself is a git repo, `.gitignore` gains a `# ── hv umbrella ──` block listing `.claude/`, `.hv/`, and each registered sub-repo.

The result looks like:

```
myorg/                 # umbrella root
├── .hv/               # shared coordinator state
│   ├── repos.json
│   ├── KNOWLEDGE.md
│   ├── DECISIONS.md
│   └── …
├── .claude/           # worktrees land here (Layout B)
├── web/               # registered sub-repo (independent git)
├── api/               # registered sub-repo (independent git)
└── shared/            # registered sub-repo (independent git)
```

To opt back out, run `/hv-config`, pick the umbrella row, and toggle off. The registry file is left intact — entries in `.hv/repos.json` remain on disk, helpers just stop consulting them until you toggle umbrella mode back on.

## The registry — `.hv/repos.json`

The registry is a single JSON file at the umbrella's `.hv/repos.json`:

```json
{
  "repos": [
    { "name": "api", "path": "./api" },
    { "name": "web", "path": "./web" }
  ]
}
```

- `name` is the sub-repo's basename and the value `/hv-capture` accepts in the `Repos:` field on items.
- `path` is relative to the umbrella root. Helpers canonicalize each entry via `realpath` at lookup time, so symlinked sub-repo paths resolve correctly.
- Entries are sorted alphabetically for stable diffs.
- No SHAs, no version pins. Sub-repos are **independent git repositories**. See `.hv/DECISIONS.md` (Architecture, "Umbrella mode does not use git submodules") for the rationale.

To edit the registry today, re-run `/hv-init` from the umbrella. `hv-umbrella-init` is idempotent: a second run with the same selection is a no-op; a run with new names adds them; names you omit but were previously registered are kept (with a warning). A first-class registry editor in `/hv-config` is planned.

## Resolvers — `hv-resolve-umbrella` and `hv-resolve-repo`

Two small helpers in `.hv/bin/` answer the two questions every umbrella-aware skill asks: *"where is the umbrella?"* and *"which sub-repo am I in?"*

`hv-resolve-umbrella` walks up from the current directory, prints the umbrella root on stdout, and exits:

| Exit | Meaning |
|------|---------|
| `0` | Found. Umbrella path on stdout. |
| `1` | No `.hv/` found in any ancestor. Stderr: `no umbrella .hv/ found`. |
| `2` | A stray `.hv/` was found *inside* a registered sub-repo, masking the umbrella. Stderr: `stray .hv/ inside registered sub-repo <name> — masking umbrella`. |

The walk-up uses `pwd -P` (the physical path), so symlinked sub-repo paths resolve to the correct umbrella.

`hv-resolve-repo` answers the second question. From any cwd inside a registered sub-repo (including a Layout B worktree), it prints the registered name on stdout. It uses `git rev-parse --git-common-dir` to find the sub-repo root even from inside a worktree, then matches against canonicalized entries in `.hv/repos.json`.

| Exit | Meaning |
|------|---------|
| `0` | Inside a registered sub-repo. Name on stdout. |
| `1` | Not inside a registered sub-repo. Stderr: `not inside a registered sub-repo`. |

Both helpers are short bash + a small python heredoc; you can read them directly under `.hv/bin/`.

## Worktree layout

Umbrella worktrees use **Layout B**:

```
<umbrella>/.claude/worktrees/<repo>/<branch>
```

A single discovery point at the umbrella, `<umbrella>/.claude/worktrees/`, holds every active worktree across every sub-repo, grouped by repo. No `.gitignore` edits in the sub-repos. Single-repo mode keeps `<repo>/.claude/worktrees/<branch>` and is unaffected. To resolve the canonical Layout B path for a `(repo, branch)` pair without hand-encoding it, call `.hv/bin/hv-worktree-path --repo <name> <branch>`.

## Per-skill behavior

Most skills delegate umbrella resolution to underlying helpers and stay umbrella-flat at the prose level. The user-visible surface:

- **`/hv-capture`** asks for `Repos:` when umbrella mode is on, accepting one or more registered names. Items can also be untagged (umbrella-flat, appropriate for cross-cutting tasks).
- **`/hv-work`** reads `Repos:` from the item and runs the orchestrator + workers against the resolved sub-repo's `.git/`. The atomic commits land in that sub-repo's history; `status.json` records the entry as `(branch, repo)`.
- **`/hv-go`** is a pass-through; `/hv-capture` and `/hv-work` handle umbrella resolution under it.
- **`/hv-pause`** writes its handoff to `.hv/handoff/<branch>@<repo>.md` (instead of `<branch>.md`) so two sub-repos sharing a branch name don't clobber each other's notes. The body gains a `Repo: <name>` line. `/hv-resume` reads the umbrella-keyed path first and falls back to the legacy `<branch>.md` form for streams that predate the change.
- **`/hv-plan`** records the target sub-repo in plan frontmatter (`repo: <name>`) when invoked with `--repo` or when the item carries `Repos:`. Slice and milestone plans stay umbrella-flat.
- **`/hv-spike`** runs the spike branch in the resolved sub-repo (`spike/<name>` lives in that repo's `.git/`); the spike file stays at `<umbrella>/.hv/spikes/<name>.md` with a `repo: <name>` frontmatter line.
- **`/hv-assume`** displays the resolved sub-repo for items with `Repos:` in its peek output.
- **`/hv-debug`** routes its single fix-commit to the sub-repo resolved from the bug's `Repos:` tag.
- **`/hv-review`** scopes its branch inspection to the sub-repo via `hv-review-scope --repo <name>`; `TODO.md` and `ARCHIVE.md` lookups stay at the umbrella.
- **`/hv-ship`** threads `--repo` through `hv-merge` / `hv-pr` so the merge or PR runs in the correct sub-repo.
- **`/hv-status`** displays each in-progress entry with an inline `(repo: <name>)` suffix; `hv-backlog`'s In Progress table gains a `Repo` column when any active entry is umbrella-tagged.
- **`/hv-refactor`** asks which scope to refactor (all sub-repos, all sub-repos plus the umbrella, the umbrella only, or a subset), then dispatches parallel sub-agents, each running a focused single-repo cycle in its target's `.git/`. The umbrella orchestrator aggregates per-repo summaries and resets the refactor counter once at the end.

The `--repo <name>` flag is also exposed on the underlying helpers when you call them directly: `hv-status-add`, `hv-status-remove`, `hv-review-scope`, `hv-merge`, `hv-pr`, `hv-plan-add`, `hv-spike-add`, `hv-worktree-clear`, `hv-worktree-path`. Without the flag, helpers operate on the cwd's git tree as in single-repo mode.

## What's not yet in umbrella mode

- **Multi-repo items.** One TODO item that fans out to commits in N sub-repos at once (with linked PRs) is on the M03 roadmap. Today, `Repos:` resolves to a single sub-repo per item.
- **Registry editor in `/hv-config`.** Add/remove repos without re-running `/hv-init`. Planned.

## Footguns

- **Don't create `.hv/` inside a registered sub-repo.** It will mask the umbrella. `hv-resolve-umbrella` detects this and exits 2 with a `masking` message.
- **Never add a sub-repo as a git submodule of the umbrella.** Sub-repos must remain independent. See `.hv/DECISIONS.md` (Architecture).
- **Symlinked sub-repo paths work,** because walk-up uses `pwd -P`. The path actually written into `.hv/repos.json` is the canonical (physical) one, not the user-given symlink.

## See also

- `.hv/DECISIONS.md` (Architecture, "Umbrella mode does not use git submodules")
- [The `.hv/` folder](../reference/hv-folder.md) — what `/hv-init` writes
- [Vision and plans](vision-and-plans.md) — how M02 fits the milestone roadmap
