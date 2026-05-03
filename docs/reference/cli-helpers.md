# CLI helpers

`.hv/bin/` contains bash scripts you can call directly when scripting against
the backlog or extending hv-skills. The helpers are small and idempotent, and
use `python3` where JSON parsing is needed. `/hv-init` refreshes them every
time you rerun it. They evolve with hv-skills and are not a stable API.

## Quick reference

| Script | What it does | Example |
|---|---|---|
| `hv-next-id` | Increment counter, return zero-padded ID | `.hv/bin/hv-next-id bugs` → `B07` |
| `hv-append` | Append entry to a section in TODO.md | `.hv/bin/hv-append "## Bugs" "- **[B07] [P1] Title.** Desc."` |
| `hv-complete` | Move item to `## Completed` with strikethrough | `.hv/bin/hv-complete B07 a1b2c3d` |
| `hv-archive-old` | Move `## Completed` items older than N days to `ARCHIVE.md` | `.hv/bin/hv-archive-old 5` |
| `hv-todo-by-milestone` | Print IDs of TODO items tagged with a milestone | `.hv/bin/hv-todo-by-milestone M01` |
| `hv-status-add` | Register an active work entry (idempotent on `(branch, repo)`) | `.hv/bin/hv-status-add [--repo <name>] hv/foo B01,F02 [worktree]` |
| `hv-status-remove` | Clear an active entry by branch (or `(branch, repo)` in umbrella mode) | `.hv/bin/hv-status-remove [--repo <name>] hv/foo` |
| `hv-reconcile` | Validate `status.json` vs git, auto-clean stale entries, emit JSON | `.hv/bin/hv-reconcile` |
| `hv-summary` | Compact project state: backlog counts, active work, recent completions | `.hv/bin/hv-summary` |
| `hv-knowledge-index` | Regenerate the managed `hv-knowledge` block in `CLAUDE.md` | `.hv/bin/hv-knowledge-index` |
| `hv-knowledge-query` | Print selected topic sections from `KNOWLEDGE.md` | `.hv/bin/hv-knowledge-query "Testing" "Networking"` |
| `hv-decisions-index` | Regenerate the managed `hv-decisions` block in `CLAUDE.md` | `.hv/bin/hv-decisions-index` |
| `hv-decisions-query` | Print selected topic sections from `DECISIONS.md` | `.hv/bin/hv-decisions-query "Architecture" "Testing"` |
| `hv-managed-block <key> [--body-stdin]` | Regenerate the managed `<!-- hv-<key>-start -->...<!-- hv-<key>-end -->` block in `CLAUDE.md`; keys: `knowledge`, `decisions`, `vision` (`vision` is `--body-stdin` only) | `.hv/bin/hv-managed-block knowledge` |
| `hv-fm-list <dir> <field1> [<field2> ...]` | Generic frontmatter extractor; emits JSON | `.hv/bin/hv-fm-list .hv/milestones id title status` |
| `hv-vision-add` | Mint a milestone ID and append overview to `MILESTONES.md` | `.hv/bin/hv-vision-add "Auth foundation" "OAuth + sessions." "M00,M02"` |
| `hv-vision-status` | Set a milestone's status to `planned`, `active`, `shipped`, or `archived` | `.hv/bin/hv-vision-status M01 active` |
| `hv-vision-active` | Print active milestone IDs, one per line | `.hv/bin/hv-vision-active` |
| `hv-vision-list` | JSON: every milestone with id, title, status, depends, ready | `.hv/bin/hv-vision-list` |
| `hv-vision-index` | Regenerate `## Active milestones` in `MILESTONES.md` and the vision block in `CLAUDE.md` | `.hv/bin/hv-vision-index` |
| `hv-plan-add` | Create a plan file; mints next slice number when called with `slice` | `.hv/bin/hv-plan-add M01 slice "Auth foundation"` |
| `hv-plan-list` | JSON: every plan with key, milestone, unit, title, status, created | `.hv/bin/hv-plan-list M01` |
| `hv-plan-show` | Print a plan file's contents | `.hv/bin/hv-plan-show M01-S01` |
| `hv-plan-rm` | Delete a plan file | `.hv/bin/hv-plan-rm M01-S01` |
| `hv-spike-add` | Create `spike/<name>` branch and `.hv/spikes/<name>.md` stub | `.hv/bin/hv-spike-add sse-feasibility "Can SSE work over our nginx?"` |
| `hv-spike-list` | JSON: every spike with name, branch, status, created, branchExists | `.hv/bin/hv-spike-list` |
| `hv-spike-finish` | Flip a spike's status to `done` and stamp the date | `.hv/bin/hv-spike-finish sse-feasibility` |
| `hv-base-branch` | Print the resolved base branch (`main`, `master`, `trunk`, or `origin/HEAD`) | `.hv/bin/hv-base-branch` |
| `hv-worktree-clear` | Remove a non-main worktree that has `<branch>` checked out; silent if none | `.hv/bin/hv-worktree-clear [--repo <name>] hv/foo` |
| `hv-merge` | Cleanup worktree, merge `--no-ff`, delete branch — msg on stdin | `echo "merge: ..." \| .hv/bin/hv-merge [--repo <name>] hv/foo` |
| `hv-pr` | Cleanup worktree, push, `gh pr create` — body on stdin | `printf '%s' "$BODY" \| .hv/bin/hv-pr [--repo <name>] hv/foo "title"` |
| `hv-ship-body` | Build PR body (Summary + Items resolved) for a branch | `.hv/bin/hv-ship-body hv/foo` |
| `hv-review-scope` | JSON: commits, touched files, referenced IDs, matched TODO entries | `.hv/bin/hv-review-scope [--repo <name>] hv/foo` |
| `hv-preflight` | Verify `.hv/` is initialized and all helpers are present. Exit 0/2/3 | `.hv/bin/hv-preflight` |
| `hv-update-check` | JSON: install type, current/latest version, status, update command | `.hv/bin/hv-update-check` |
| `hv-refactor-age` | JSON: non-refactor features/bugs since last `refactor:` commit | `.hv/bin/hv-refactor-age` |
| `hv-refactor-reset` | Zero `counters.json#since_refactor` (called by `/hv-refactor` after commit) | `.hv/bin/hv-refactor-reset` |
| `hv-refactor-targets` | JSON: umbrella mode flag + `hasCode` for the umbrella + every registered sub-repo's name and abs path. Used by `/hv-refactor` Step 1.5 to ask the user which scope to refactor | `.hv/bin/hv-refactor-targets` |
| `hv-backlog` | Render pre-sorted backlog tables (In Progress / Bugs / Features / Tasks) | `.hv/bin/hv-backlog` |
| `hv-guard-clean` | Exit non-zero if git tree is dirty or not a repo | `.hv/bin/hv-guard-clean /hv-work` |
| `hv-bootstrap` | Seed `.hv/` directories and data files (run during `/hv-init` only) | `<source-bin>/hv-bootstrap` |
| `hv-umbrella-init` | Bootstrap an umbrella registry: scan child git repos, register a chosen subset (via stdin), write `.hv/repos.json` and append umbrella `.gitignore` lines | `echo "all" \| <source-bin>/hv-umbrella-init` |
| `hv-resolve-umbrella` | Walk up from cwd to find the umbrella's `.hv/`; detect masking by stray `.hv/` inside a registered sub-repo | `.hv/bin/hv-resolve-umbrella` |
| `hv-resolve-repo` | Identify which registered sub-repo cwd belongs to (incl. Layout B worktrees) | `.hv/bin/hv-resolve-repo` |
| `hv-release-detect-version` | Auto-detect the version file and emit current version as JSON | `.hv/bin/hv-release-detect-version` |
| `hv-release-bump-version` | Apply a semver bump (patch/minor/major or explicit) to a version file in-place | `.hv/bin/hv-release-bump-version plugin.json plugin-json minor` |
| `hv-release-changelog-from-commits` | Categorize commits in a git range by Conventional Commits prefix → markdown | `.hv/bin/hv-release-changelog-from-commits v1.0.0..HEAD` |
| `hv-release-update-changelog` | Prepend a release section to CHANGELOG.md, creating it if absent (idempotent) | `.hv/bin/hv-release-update-changelog 1.2.0 notes.md` |
| `hv-release-detect-host` | Detect remote hosting kind (github / gitlab / -enterprise / -self-hosted / none) | `.hv/bin/hv-release-detect-host` |

## ID and counter helpers

`hv-next-id <namespace>` reads `.hv/counters.json`, increments the counter for
the given namespace, writes it back, and prints the zero-padded ID (e.g. `B07`,
`F03`, `T12`). It is safe to call concurrently; the write is atomic via a temp
file. Every skill that mints a new backlog item calls this first.

`counters.json` lives at `.hv/counters.json` and is never overwritten by
`/hv-init`. Add namespaces freely; the file grows as you use new ones.

## Backlog manipulation

`hv-append` inserts a formatted entry under the matching `##` section heading in
`TODO.md`. `hv-complete` rewrites an open item as a struck-through `~~line~~`
and moves it under `## Completed`, stamping it with the supplied git SHA.
`hv-archive-old` sweeps `## Completed` entries older than N days into
`ARCHIVE.md` to keep the working file short. `hv-todo-by-milestone` lets you
filter the backlog by milestone tag; see also [Knowledge and vision
indexes](#knowledge-and-vision-indexes) where milestone state lives.

## Status and reconciliation

`hv-status-add` writes a branch record into `.hv/status.json` so the project
knows a piece of work is in flight. It is idempotent: calling it twice for the
same branch is safe. `hv-status-remove` drops the record when work merges or is
abandoned.

`hv-reconcile` cross-checks every entry in `status.json` against live git state
and removes records whose branches no longer exist. It emits a JSON summary that
skills use to avoid acting on stale context. `hv-summary` prints a human-readable
snapshot of the same data: backlog counts, what's actively in progress, and the
most recent completions.

In umbrella mode, every status helper accepts `--repo <name>` to scope the entry to a registered sub-repo. `hv-status-add` keys uniqueness on `(branch, repo)`, so the same branch name can exist independently across multiple sub-repos. `hv-status-remove` without `--repo` removes only legacy entries (where `repo` is null or missing); add `--repo <name>` to remove an umbrella-tagged entry. `hv-reconcile` reads `.hv/repos.json` and validates each entry against its scoped sub-repo's `.git/`, with base-branch resolution per repo.

## Knowledge, vision, and decisions indexes

`hv-knowledge-index` and `hv-knowledge-query` operate on `.hv/KNOWLEDGE.md`.
`hv-knowledge-index` regenerates the `<!-- hv-knowledge-start -->` block in
`CLAUDE.md` so the agent always sees an up-to-date topic list. `hv-knowledge-query`
pulls specific topic sections out of `KNOWLEDGE.md` by name, which is useful
when scripting post-session summaries.

`hv-decisions-index` and `hv-decisions-query` operate on `.hv/DECISIONS.md`
identically. The file structure, marker shape, and query semantics all mirror
the knowledge helpers. The distinction is semantic: decisions are *active*
hard boundaries (committed via `/hv-decide` with mandatory forbids/permits),
while knowledge is *passive* gotchas captured by `/hv-learn`. See
[Decisions](../usage/decisions.md) for when to use which.

The vision group manages milestones in `.hv/milestones/`. `hv-vision-add` mints
the next `MNN` ID, creates the milestone file, and appends its overview line to
`MILESTONES.md`. `hv-vision-status` updates both the file's frontmatter and the
overview line atomically. `hv-vision-active`, `hv-vision-list`, and
`hv-vision-index` let you query and refresh milestone state. `hv-vision-index`
also regenerates the `<!-- hv-vision-start -->` block injected into `CLAUDE.md`.

`hv-todo-by-milestone` is covered in [Backlog manipulation](#backlog-manipulation).

## Plan and spike helpers

Plans live at `.hv/plans/<milestone>-<unit>.md`. `hv-plan-add` creates a plan
file; passing `slice` as the unit makes it auto-increment the slice number
(`S01`, `S02`, …). `hv-plan-list` returns JSON you can pipe into other tools.
`hv-plan-show` and `hv-plan-rm` are straightforward read/delete operations.

Spikes live at `.hv/spikes/<name>.md` with a matching `spike/<name>` git branch.
`hv-spike-add` creates both in one call. `hv-spike-finish` closes the spike and
records the finish date. `hv-spike-list` returns JSON with a `branchExists` field
so you can detect spikes whose branches were already deleted.

## Merge and PR helpers

`hv-merge` handles the full merge ceremony for a worktree branch: it removes the
worktree, merges `--no-ff` into the current branch, and deletes the source
branch. The commit message is read from stdin, so you can compose it before
calling the helper. `hv-pr` does the equivalent for pull-request workflows:
remove the worktree, push the branch, and call `gh pr create` with a body
read from stdin.

`hv-ship-body` builds a standardised PR body for a branch by scanning its
commits for referenced IDs and matching them against open TODO entries.
`hv-review-scope` emits a richer JSON payload (commits, touched files,
referenced IDs, and matched TODO entries) that the `/hv-review` skill consumes.

All three helpers (`hv-merge`, `hv-pr`, `hv-review-scope`) accept `--repo <name>` in umbrella mode to target a registered sub-repo's `.git/`. Without the flag they operate on cwd's git tree as before.

## Diagnostics

`hv-preflight` verifies that `.hv/` is initialised and every expected helper is
present. It exits `0` on success, `2` if the folder is missing, and `3` if
helpers are incomplete. Useful as a guard at the top of scripts.

`hv-update-check` queries the hv-skills GitHub releases and returns JSON with
the current and latest version, install type, and the command to upgrade.

`hv-refactor-age` reads `counters.json#since_refactor` and returns JSON with
the number of features and bugs completed since the last refactor cycle.
`/hv-refactor` uses this to decide whether a pass is overdue. The counter is
maintained imperatively: `hv-complete` increments it on every active→completed
transition whose resolved commit's subject does not start with `refactor:`,
and `hv-refactor-reset` zeros it after a `/hv-refactor` cycle commits.
`hv-refactor-targets` enumerates refactor targets (the umbrella's `hasCode` flag plus every registered sub-repo) so `/hv-refactor` Step 1.5 can ask which scope to fan out across.

`hv-backlog` renders the full TODO.md as sorted Markdown tables (In Progress,
Bugs, Features, Tasks). Handy for a quick terminal overview or piping into
other scripts.

`hv-guard-clean` exits non-zero when the git working tree is dirty or the
current directory is not inside a git repository. Skills call it as a safety
check before making commits.

## Umbrella mode helpers

When `umbrella.enabled` is true in `.hv/config.json`, the umbrella's `.hv/` coordinates work across multiple sub-repos registered in `.hv/repos.json`. Three helpers manage that registry and the cwd-to-sub-repo resolution.

`hv-umbrella-init` runs once during `/hv-init` Step 1.5 (see [Umbrella mode](../usage/umbrella-mode.md) for the user-facing flow). It scans immediate children for `<child>/.git/`, reads one line of stdin (`all` / `none` / comma-separated names) to pick a subset, writes `.hv/repos.json`, and, if the umbrella is itself a git repo, appends `.claude/`, `.hv/`, and `/<repo>/` lines to the umbrella's `.gitignore` under a `# ── hv umbrella ──` header.

`hv-resolve-umbrella` walks up from cwd to find the umbrella's `.hv/`. It also detects a footgun: a stray `.hv/` directory inside a registered sub-repo (e.g., from a misplaced `/hv-init` from inside the sub-repo). It exits 2 with a `masking` message in that case. `hv-resolve-repo` identifies which registered sub-repo cwd belongs to, working transparently from a Layout B worktree at `<umbrella>/.claude/worktrees/<repo>/<branch>/` via `git rev-parse --git-common-dir`.

### hv-resolve-repos

Resolve a comma-separated `Repos:` list into a JSON array of `{name, path}` entries. Used by multi-repo dispatch helpers to validate and locate every named sub-repo in one call.

    hv-resolve-repos "<repos-csv>"

Exits 0 with JSON on stdout, 1 if any name is not registered in `.hv/repos.json` (stderr names the missing sub-repo). Single names and empty input are valid; the result is a list whose length matches the input.

### hv-multi-branch-create

Atomically create the same branch in every named sub-repo. Used by `/hv-work` when an item's `Repos:` field names two or more sub-repos.

    hv-multi-branch-create --branch <name> --repos <repos-csv>

Two phases. Phase 1 precheck: scans every named repo for `refs/heads/<branch>`; if any has it, exits 1 listing the colliding repo names on stderr — *no repos are modified*. Phase 2 create: runs `git branch <name>` (no checkout) in each repo. Unregistered repo names are rejected via `hv-resolve-repos` (exit 1, missing names on stderr).

### hv-status-add-multi

Register one `status.json` entry per `(branch, repo)` pair for a multi-repo `/hv-work` wave. Loops `hv-status-add --repo <r>` once per name in `--repos`.

    hv-status-add-multi [--if-absent] --branch <name> --items <ids-csv> --repos <repos-csv> [--worktrees <paths-csv>]

`--worktrees` is optional; when given, its comma-list MUST match the length of `--repos` (paired by index). Unregistered repo names are rejected up front via `hv-resolve-repos` (no partial writes). `--if-absent` is forwarded to each underlying `hv-status-add` call.

## Bootstrap (run during /hv-init only)

`hv-bootstrap` seeds the `.hv/` folder structure. Concretely it:

1. Creates subdirectories: `.hv/bin/`, `.hv/bugs/`, `.hv/features/`, `.hv/tasks/`,
   `.hv/milestones/`, `.hv/plans/`, `.hv/spikes/`.
2. Writes initial data files (skipping any that already exist): `TODO.md`,
   `KNOWLEDGE.md`, `DECISIONS.md`, `MILESTONES.md`, `counters.json`,
   `status.json`.
3. Appends a `.hv/` entry to `.gitignore` if one is not already present.

It does **not** copy helper scripts; that is `/hv-init`'s job. It is called by
`/hv-init` from the hv-skills *source* `bin/`, not from `.hv/bin/` itself, and
it never overwrites files that already exist. You do not normally need to call
this directly. Rerun `/hv-init` if you want to refresh the installation.
