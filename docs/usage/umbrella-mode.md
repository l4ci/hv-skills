# Umbrella mode

Umbrella mode lets a single hv-skills coordinator span several independent git repositories that live side by side under one parent folder. Knowledge, decisions, vision, and the backlog live once at the umbrella; each sub-repo keeps its own history, branches, and remotes.

If you're using single-repo mode, this page doesn't apply to you. No action needed — single-repo behavior is unchanged.

## When to use it

Use umbrella mode when you maintain a small fleet of related repositories — `~/projects/myorg/` containing `web/`, `api/`, and `shared/`, for example — and you want one coordinator (one `KNOWLEDGE.md`, one `DECISIONS.md`, one `MILESTONES.md`, one backlog) instead of forking them into N copies. The typical signal is "I keep cross-pasting the same gotcha into three repos' notes."

## When NOT to use it

- **Single-repo project.** Don't enable. The single-repo path stays simpler and faster.
- **Monorepo.** Don't enable. A monorepo is one git repo; umbrella mode is for *multiple* repos under a parent.
- **Casually-grouped unrelated repos.** If the repos under your folder don't share knowledge, decisions, or planning concerns, umbrella mode adds bookkeeping for nothing.

## How it differs from single-repo

| Aspect | Single-repo | Umbrella |
|--------|-------------|----------|
| `.hv/` location | Repo root | Umbrella root (one level up from sub-repos) |
| Where helpers run git ops | The repo | The sub-repo for the current item (S02+) |
| Worktree path | `<repo>/.claude/worktrees/<branch>` | `<umbrella>/.claude/worktrees/<repo>/<branch>` (Layout B) |
| Knowledge / decisions / vision | Per-repo | Shared at the umbrella |
| Sub-repo git histories | n/a | Independent — no submodules, no version pinning |

Single-repo behavior is **completely unchanged**. Umbrella-aware helpers gate on `umbrella.enabled === true` in `.hv/config.json`; without that flag, every skill behaves exactly as it did before.

## Enabling it

1. `cd` to the umbrella folder — the parent that contains your sub-repos as immediate children.
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
├── .claude/           # worktrees land here in S02 (Layout B)
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

- `name` is the sub-repo's basename and the value `/hv-capture` will accept in S02's `Repos:` field.
- `path` is relative to the umbrella root. Helpers canonicalize each entry via `realpath` at lookup time, so symlinked sub-repo paths resolve correctly.
- Entries are sorted alphabetically for stable diffs.
- No SHAs, no version pins. Sub-repos are **independent git repositories** — see `.hv/DECISIONS.md` (Architecture — "Umbrella mode does not use git submodules") for the rationale.

To edit the registry in S01, re-run `/hv-init` from the umbrella. `hv-umbrella-init` is idempotent: a second run with the same selection is a no-op; a run with new names adds them; names you omit but were previously registered are kept (with a warning). A first-class registry editor in `/hv-config` is planned for S03.

## Resolvers — `hv-resolve-umbrella` and `hv-resolve-repo`

Two small helpers in `.hv/bin/` answer the two questions every umbrella-aware skill asks: *"where is the umbrella?"* and *"which sub-repo am I in?"*.

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

## Worktrees in umbrella mode (preview)

In S02, when `/hv-work` lands umbrella support, worktrees will use **Layout B**:

```
<umbrella>/.claude/worktrees/<repo>/<branch>
```

A single discovery point at the umbrella — `<umbrella>/.claude/worktrees/` — holds every active worktree across every sub-repo, grouped by repo. No `.gitignore` edits in the sub-repos.

This isn't implemented yet. Single-repo mode keeps `<repo>/.claude/worktrees/<branch>` and is unaffected.

## What's NOT in this release

S01 ships the foundation only. The following land later:

- `/hv-capture` doesn't yet ask `Repos:` — coming in S02.
- `/hv-work` doesn't yet route a session to a sub-repo — coming in S02.
- `status.json` doesn't yet key in-flight work by repo — coming in S02.
- Multi-repo features (one item touching N sub-repos at once, linked PRs) — M03.
- A registry editor in `/hv-config` (add/remove repos without re-running `/hv-init`) — S03.

For now: items continue to work as today, and the resolvers are available for any helper that wants to be umbrella-aware.

## Footguns

- **Don't create `.hv/` inside a registered sub-repo.** It will mask the umbrella. `hv-resolve-umbrella` detects this and exits 2 with a `masking` message.
- **Never add a sub-repo as a git submodule of the umbrella.** Sub-repos must remain independent — see `.hv/DECISIONS.md` (Architecture).
- **Symlinked sub-repo paths work,** because walk-up uses `pwd -P`. The path actually written into `.hv/repos.json` is the canonical (physical) one, not the user-given symlink.

## See also

- `.hv/DECISIONS.md` (Architecture — "Umbrella mode does not use git submodules")
- [The `.hv/` folder](../reference/hv-folder.md) — what `/hv-init` writes
- [Vision and plans](vision-and-plans.md) — how M02 fits the milestone roadmap
