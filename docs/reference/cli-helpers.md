# CLI helpers

`.hv/bin/` contains bash scripts you can call directly when scripting against
the backlog or extending hv-skills. The helpers are small and idempotent, and
use `python3` where JSON parsing is needed. `/hv-init` refreshes them every
time you rerun it. They evolve with hv-skills and are not a stable API.

## Quick reference

| Script | What it does | Example |
|---|---|---|
| `hv-next-id` | Increment counter, return zero-padded ID | `.hv/bin/hv-next-id bugs` → `B07` |
| `hv-append` | Append entry to a section in BACKLOG.md | `.hv/bin/hv-append "## Bugs" "- **[B07] [P1] Title.** Desc."` |
| `hv-complete` | Move item to `## Completed` with strikethrough | `.hv/bin/hv-complete B07 a1b2c3d` |
| `hv-uncomplete` | Restore a completed item back to its active type section; inverse of `hv-complete`; idempotent no-op when already active; rewinds `counters.json#since_refactor` for non-`refactor:` commits | `.hv/bin/hv-uncomplete B07` |
| `hv-undo` | Reset the last `/hv-work` merge commit on the base branch and restore each TODO via `hv-uncomplete`; direct-merge cycles only; refuses on post-merge commits unless `--allow-post-merge` is passed | `.hv/bin/hv-undo [--dry-run] [--allow-post-merge]` |
| `hv-archive-old` | Move `## Completed` items older than N days to `ARCHIVE.md` | `.hv/bin/hv-archive-old 5` |
| `hv-rm` | Remove backlog item(s) — strips TODO entry, Related cross-refs, detail/plan files; refuses if active in `status.json` unless `--force` | `.hv/bin/hv-rm [--force] [--scrub-archive] B07,F03` |
| `hv-todo-by-milestone` | Print IDs of TODO items tagged with a milestone | `.hv/bin/hv-todo-by-milestone M01` |
| `hv-todo-field` | Extract a single field (`detail`/`related`/`milestone`/`repos`) from the TODO bullet of an item ID | `.hv/bin/hv-todo-field B07 detail` |
| `hv-find-milestone-for-items` | Lookup the milestones tagged on a list of TODO item IDs; prints unique sorted M-IDs (one per line); always exits 0 | `.hv/bin/hv-find-milestone-for-items B07 F03` |
| `hv-plan-rename-check` | List files that reference `<old-name>` (wraps `git grep -l`); used at plan + verify time for rename + link-sweep collision detection; always exits 0 | `.hv/bin/hv-plan-rename-check OldName.swift` |
| `hv-uncertain` | Determine whether an item warrants `/hv-work --preview` before `/hv-plan` in loop mode; exits 0 (uncertain, reasons on stdout) or 1 (certain) | `.hv/bin/hv-uncertain B07` |
| `hv-status-add` | Register an active work entry (idempotent on `(branch, repo)`) | `.hv/bin/hv-status-add [--repo <name>] hv/foo B01,F02 [worktree]` |
| `hv-status-remove` | Clear an active entry by branch (or `(branch, repo)` in umbrella mode) | `.hv/bin/hv-status-remove [--repo <name>] hv/foo` |
| `hv-status-repo-for` | Print the repo name for the active stream matching a branch (umbrella mode); empty when not found; always exits 0 | `.hv/bin/hv-status-repo-for hv/foo` |
| `hv-loop-stamp` | Read/write the `loopStartedAt` ISO timestamp in `status.json`; subcommands: `start` (first-write-only), `clear`, `read` | `.hv/bin/hv-loop-stamp start` |
| `hv-reconcile` | Validate `status.json` vs git, auto-clean stale entries, emit JSON (entries flag `noBase: true` for the umbrella cwd when umbrella has no base branch) | `.hv/bin/hv-reconcile` |
| `hv-debug-counter` | Manage the persistent fix-attempt counter for `/hv-debug` Iron Law; subcommands: `init`, `record-attempt`, `fail`, `pass`, `show`, `summary`, `clear`, `inc-cycle` | `.hv/bin/hv-debug-counter show` |
| `hv-todo-drift` | Walk git log per registered sub-repo for [ID] tags, cross-reference TODO open items, emit JSON of IDs that shipped but stayed open | `.hv/bin/hv-todo-drift` |
| `hv-summary` | Compact project state: backlog counts, active work, recent completions | `.hv/bin/hv-summary` |
| `hv-knowledge-index` | Regenerate the managed `hv-knowledge` block in `CLAUDE.md` | `.hv/bin/hv-knowledge-index` |
| `hv-knowledge-query` | Print selected topic sections from `KNOWLEDGE.md` | `.hv/bin/hv-knowledge-query "Testing" "Networking"` |
| `hv-knowledge-merge` | Insert a `**Title** — body` bullet under `## <topic>` in `.hv/KNOWLEDGE.md`; atomic dedup by (topic, title) | `printf '%s' "$BODY" \| .hv/bin/hv-knowledge-merge --topic Testing --title "Mock TLS handshake"` |
| `hv-knowledge-amend` | Append text after the trailing `<!-- date -->` comment of a bullet matched by (topic, fragment) | `.hv/bin/hv-knowledge-amend --topic Testing --fragment "TLS handshake" --append "Upstream: hv-skills#42"` |
| `hv-knowledge-stats` | JSON: bullet count + section bytes per `## Topic` in `KNOWLEDGE.md`. `/hv-learn` uses it to nudge when a topic crosses 25 bullets or 10 KB | `.hv/bin/hv-knowledge-stats` |
| `hv-knowledge-tier` | F03 per-bullet `{tier, hits, lastSeen}` state manager in `.hv/knowledge-tier.json`; subcommands: `--get`, `--set`, `--init`, `--inc`, `--list` | `.hv/bin/hv-knowledge-tier --list --tier provisional` |
| `hv-knowledge-hit` | Register a hit on a queried KNOWLEDGE bullet; auto-promotes `provisional → confirmed` when hits reach threshold (default 3); skips promotion if a contradiction is pending | `.hv/bin/hv-knowledge-hit --topic Testing --title "Mock TLS handshake"` |
| `hv-knowledge-migrate` | One-shot migration: stamp every existing titled KNOWLEDGE bullet as `provisional` in the F03 sidecar; idempotent no-op on re-run | `.hv/bin/hv-knowledge-migrate` |
| `hv-knowledge-contradiction` | Manage the pending-contradictions queue at `.hv/knowledge-contradictions.json`; gates auto-promotion when a correction overlaps a queried bullet | `.hv/bin/hv-knowledge-contradiction --list` |
| `hv-config-set` | Set a single value in `.hv/config.json` at a dotted key path; preserves other keys, writes atomically (resolve; JSON-parse value, fallback to string) | `.hv/bin/hv-config-set docs.afterWork true` |
| `hv-decisions-index` | Regenerate the managed `hv-decisions` block in `CLAUDE.md` | `.hv/bin/hv-decisions-index` |
| `hv-decisions-query` | Print selected topic sections from `DECISIONS.md` | `.hv/bin/hv-decisions-query "Architecture" "Testing"` |
| `hv-auto-decision-log` | Append an `[Auto:Loop]` entry to `DECISIONS.md` under a topic; idempotent on `(topic, rule-title)` | `.hv/bin/hv-auto-decision-log "Architecture" "no direct DB writes" "keeps layer clean"` |
| `hv-auto-decisions-since` | Print a markdown summary of `[Auto:Loop]` decisions logged since `loopStartedAt` in `status.json`; empty when none match | `.hv/bin/hv-auto-decisions-since` |
| `hv-section-query <key> <topic>...` | Generic section query — print `## <topic>` bodies from `KNOWLEDGE.md`, `DECISIONS.md`, or `CONTEXT.md`; backing helper for the typed `*-query` wrappers | `.hv/bin/hv-section-query knowledge "Testing"` |
| `hv-skills-index` | Regenerate the managed `<!-- hv-skills-start -->` block in `CLAUDE.md` with the canonical slash-command index (static body, idempotent) | `.hv/bin/hv-skills-index` |
| `hv-context-query` | Print matching `## <term>` sections from `CONTEXT.md` (umbrella-aware: returns union of umbrella-shared + active sub-repo) | `.hv/bin/hv-context-query backlog session` |
| `hv-context-index` | Regenerate the managed `hv-context` block in `CLAUDE.md` | `.hv/bin/hv-context-index` |
| `hv-context-add` | Insert or update a term in `CONTEXT.md`; re-renders body alphabetically; exit 3 on alias collision, exit 4 on umbrella resolution failure | `.hv/bin/hv-context-add backlog --def "the canonical queue" --alias "todo list"` |
| `hv-context-map` | Regenerate `.hv/CONTEXT-MAP.md` pointer index (umbrella only) | `.hv/bin/hv-context-map` |
| `hv-map-query` | Print selected subsystem detail file bodies from `.hv/map/` | `.hv/bin/hv-map-query capture work` |
| `hv-map-index` | Regenerate the managed `hv-map` block in `CLAUDE.md` from `.hv/map/<name>.md` frontmatter `summary:` | `.hv/bin/hv-map-index` |
| `hv-map-stats` | JSON: per-subsystem bytes, last-touched, entry-point counts, broken `file:line` refs | `.hv/bin/hv-map-stats` |
| `hv-map-cap-check` | Emit a one-line nudge to stderr when subsystem count meets or exceeds the soft cap; silent below; always exits 0 (advisory, not a gate) | `.hv/bin/hv-map-cap-check` |
| `hv-staleness` | List stale entries across MAP/KNOWLEDGE/TODO past a days threshold | `.hv/bin/hv-staleness map --days 90` |
| `hv-stale-summary` | One-line summary wrapping hv-staleness × 3 (map/knowledge/todo); zero-kinds suppressed | `.hv/bin/hv-stale-summary --days 90` |
| `hv-managed-block <key> [--body-stdin]` | Regenerate the managed `<!-- hv-<key>-start -->...<!-- hv-<key>-end -->` block in `CLAUDE.md`; keys: `knowledge`, `decisions`, `vision`, `context`, `map`, `skills` (`vision`, `map`, and `skills` are `--body-stdin` only) | `.hv/bin/hv-managed-block knowledge` |
| `hv-fm-list <dir> <field1> [<field2> ...]` | Generic frontmatter extractor; emits JSON | `.hv/bin/hv-fm-list .hv/milestones id title status` |
| `hv-vision-add` | Mint a milestone ID and append overview to `MILESTONES.md` | `.hv/bin/hv-vision-add "Auth foundation" "OAuth + sessions." "M00,M02"` |
| `hv-vision-status` | Set a milestone's status to `planned`, `active`, `shipped`, or `archived` | `.hv/bin/hv-vision-status M01 active` |
| `hv-vision-active` | Print active milestone IDs, one per line | `.hv/bin/hv-vision-active` |
| `hv-vision-list` | JSON: every milestone with id, title, status, depends, ready | `.hv/bin/hv-vision-list` |
| `hv-vision-index` | Regenerate `## Active milestones` in `MILESTONES.md` and the vision block in `CLAUDE.md` | `.hv/bin/hv-vision-index` |
| `hv-vision-empty-active` | Print active milestone IDs with 0 open items, one per line | `.hv/bin/hv-vision-empty-active` |
| `hv-design-add` | Writer: create `.hv/designs/<ID>.md` from an item ID (`[BFT]\d{2,}`); exit 1 on bad ID or conflict | `.hv/bin/hv-design-add F12 "Archive command"` |
| `hv-design-show` | Resolve: print a design file's contents; exit 1 when design ID not found | `.hv/bin/hv-design-show F12` |
| `hv-design-rm` | Writer: remove `.hv/designs/<ID>.md`; exit 1 when design ID not found | `.hv/bin/hv-design-rm F12` |
| `hv-design-list` | Lookup: JSON of every design with id, title, status, created; always exits 0 | `.hv/bin/hv-design-list` |
| `hv-plan-add` | Writer: create a plan file; mints next slice number when called with `slice`; accepts `--design <path>` to record a design artifact pointer in frontmatter | `.hv/bin/hv-plan-add [--design <path>] M01 slice "Auth foundation"` |
| `hv-plan-list` | JSON: every plan with key, milestone, unit, title, status, created | `.hv/bin/hv-plan-list M01` |
| `hv-plan-show` | Print a plan file's contents | `.hv/bin/hv-plan-show M01-S01` |
| `hv-plan-rm` | Delete a plan file | `.hv/bin/hv-plan-rm M01-S01` |
| `hv-spike-add` | Create `spike/<name>` branch and `.hv/spikes/<name>.md` stub | `.hv/bin/hv-spike-add sse-feasibility "Can SSE work over our nginx?"` |
| `hv-spike-list` | JSON: every spike with name, branch, status, created, branchExists | `.hv/bin/hv-spike-list` |
| `hv-spike-finish` | Flip a spike's status to `done` and stamp the date | `.hv/bin/hv-spike-finish sse-feasibility` |
| `hv-base-branch` | Print the resolved base branch (`main`, `master`, `trunk`, or `origin/HEAD`) | `.hv/bin/hv-base-branch` |
| `hv-worktree-clear` | Remove a non-main worktree that has `<branch>` checked out; silent if none | `.hv/bin/hv-worktree-clear [--repo <name>] hv/foo` |
| `hv-worktree-path` | Print the canonical Layout B worktree path for a sub-repo branch (`<umbrella>/.claude/worktrees/<repo>/<branch>`) | `.hv/bin/hv-worktree-path --repo web hv/foo` |
| `hv-merge` | Cleanup worktree, merge `--no-ff`, delete branch — msg on stdin | `echo "merge: ..." \| .hv/bin/hv-merge [--repo <name>] hv/foo` |
| `hv-pr` | Cleanup worktree, push, `gh pr create` — body on stdin | `printf '%s' "$BODY" \| .hv/bin/hv-pr [--repo <name>] hv/foo "title"` |
| `hv-ship-body` | Build PR body (Summary + Items resolved) for a branch | `.hv/bin/hv-ship-body hv/foo` |
| `hv-review-scope` | JSON: commits, touched files, referenced IDs, matched TODO entries | `.hv/bin/hv-review-scope [--repo <name>] hv/foo` |
| `hv-review-scaffolding` | Surface stale per-task scaffolding text in the branch diff (Task N, placeholder, in flight, added later, not yet wired); empty stdout = no matches | `.hv/bin/hv-review-scaffolding [--repo <name>] [<base> [<branch>]]` |
| `hv-second-opinion-brief` | Build an adversarial fresh-eyes brief (goal + commits + diff) for a branch, formatted for a no-prior-context subagent to find blind spots | `.hv/bin/hv-second-opinion-brief hv/foo` |
| `hv-preflight` | Verify `.hv/` is initialized and all helpers are present. Exit 0/2/3 | `.hv/bin/hv-preflight` |
| `hv-update-check` | JSON: install type, current/latest version, status, update command | `.hv/bin/hv-update-check` |
| `hv-version-check` | Compare `.hv/config.json#hvSkills.version` with the currently-installed plugin version; nudge or JSON | `.hv/bin/hv-version-check` |
| `hv-resolve-plugin-root` | Resolve the installed hv-skills plugin root (default `<kind>\|<root>`; `--root-only`; `--bin`) | `.hv/bin/hv-resolve-plugin-root --root-only` |
| `hv-issue-suggest` | Open an upstream hv-skills issue via `gh` (or print a manual-fallback URL); reads body from stdin | `printf '%s' "$BODY" \| .hv/bin/hv-issue-suggest --title "Title"` |
| `hv-issues-provider` | Print the issue-tracking provider for cwd (or `--repo <name>`) — `github` / `gitlab` / `unknown` — based on the origin URL; always exits 0 | `.hv/bin/hv-issues-provider` |
| `hv-issues-list` | List open upstream issues (GH via `gh`, GL via `glab`) as normalized JSON; exit 0 with `[]` when none; exit 1 when the matching CLI is missing or unauthed | `.hv/bin/hv-issues-list [--repo <name>] [--label <name>] [--limit <N>]` |
| `hv-issues-imported` | Index every `GH:`/`GL:` cross-reference across `BACKLOG.md`, `ARCHIVE.md`, and per-item detail files as JSON; multi-repo items emit one entry per `Repos:` member; always exits 0 | `.hv/bin/hv-issues-imported` |
| `hv-issues-label` | Apply or remove a label on an upstream issue (GH/GL); idempotent on the already-present / already-absent transitions; auto-creates the label when `issues.autoCreateLabel` is true | `.hv/bin/hv-issues-label apply --issue 42 --label in-progress` |
| `hv-issues-close` | Close an upstream issue and post a tracking comment naming the shipping commit; called by `/hv-ship` on the direct-push path after explicit user opt-in | `.hv/bin/hv-issues-close --issue 42 --commit a1b2c3d` |
| `hv-refactor-age` | JSON: non-refactor features/bugs since last `refactor:` commit | `.hv/bin/hv-refactor-age` |
| `hv-refactor-reset` | Zero `counters.json#since_refactor` (called by `/hv-refactor` after commit) | `.hv/bin/hv-refactor-reset` |
| `hv-refactor-targets` | JSON: umbrella mode flag + `hasCode` for the umbrella + every registered sub-repo's name and abs path. Used by `/hv-refactor` Step 1.5 to ask the user which scope to refactor | `.hv/bin/hv-refactor-targets` |
| `hv-backlog` | Render pre-sorted backlog tables (In Progress / Bugs / Features / Tasks); `--grep <pattern>` filters by substring | `.hv/bin/hv-backlog --grep dashboard` |
| `hv-guard-clean` | Exit non-zero if git tree is dirty or not a repo | `.hv/bin/hv-guard-clean /hv-work` |
| `hv-guard-feature-branch` | Refuse to operate on the project's base branch (main/master/trunk/configured); exit 1 with stderr on the base, exit 0 on a feature branch | `.hv/bin/hv-guard-feature-branch` |
| `hv-require-git-context` | Preflight: exit 1 with a friendly error if cwd is an umbrella root with no git context; silent on pass | `.hv/bin/hv-require-git-context hv-merge --repo-flag-supported` |
| `hv-bootstrap` | Seed `.hv/` directories and data files (run during `/hv-init` only) | `<source-bin>/hv-bootstrap` |
| `hv-umbrella-init` | Bootstrap an umbrella registry: scan child git repos, register a chosen subset (via stdin), write `.hv/repos.json` and append umbrella `.gitignore` lines | `echo "all" \| <source-bin>/hv-umbrella-init` |
| `hv-resolve-umbrella` | Walk up from cwd to find the umbrella's `.hv/`; detect masking by stray `.hv/` inside a registered sub-repo | `.hv/bin/hv-resolve-umbrella` |
| `hv-resolve-repo` | Identify which registered sub-repo cwd belongs to (incl. Layout B worktrees) | `.hv/bin/hv-resolve-repo` |
| `hv-resolve-repo-path` | Resolve a registered sub-repo name → absolute path via `.hv/repos.json`; symmetric counterpart to `hv-resolve-repo` | `.hv/bin/hv-resolve-repo-path web` |
| `hv-resolve-handoff` | Resolve handoff-note path with umbrella-vs-flat fallback (lookup; empty stdout when no handoff). Default reads the filesystem; `--write` emits the canonical write path without probing | `.hv/bin/hv-resolve-handoff --repo web hv/feature-x` |
| `hv-umbrella-on` | Print `yes` if umbrella mode is active (`.hv/repos.json` registers ≥1 sub-repo), `no` otherwise; always exits 0 | `.hv/bin/hv-umbrella-on` |
| `hv-walk-up` | Walk up from an anchor directory to find a marker (default `.hv/`) and print the containing directory's absolute path; `--detect-masking` checks for stray sub-repo `.hv/` | `.hv/bin/hv-walk-up --marker .hv --detect-masking` |
| `hv-release-detect-version` | Auto-detect the version file and emit current version as JSON | `.hv/bin/hv-release-detect-version` |
| `hv-release-bump-version` | Apply a semver bump (patch/minor/major or explicit) to a version file in-place | `.hv/bin/hv-release-bump-version plugin.json plugin-json minor` |
| `hv-release-changelog-from-commits` | Categorize commits in a git range by Conventional Commits prefix → markdown | `.hv/bin/hv-release-changelog-from-commits v1.0.0..HEAD` |
| `hv-release-update-changelog` | Prepend a release section to CHANGELOG.md, creating it if absent (idempotent) | `.hv/bin/hv-release-update-changelog 1.2.0 notes.md` |
| `hv-release-detect-host` | Detect remote hosting kind (github / gitlab / -enterprise / -self-hosted / none) | `.hv/bin/hv-release-detect-host` |
| `hv-release-pending` | Emit JSON `{lastTag, commits, days, thresholdCommits, thresholdDays, shouldNudge, reason}` for "is it time to /hv-release?" gating | `.hv/bin/hv-release-pending` |
| `hv-qa-index` | Regenerate the managed `<!-- hv-qa-start -->` block in `CLAUDE.md` from `summary:` frontmatter of every `.hv/qa/<target>.md` | `.hv/bin/hv-qa-index` |
| `hv-qa-query` | Print the body (minus frontmatter) of named QA target files from `.hv/qa/`; missing targets are silent; always exits 0 | `.hv/bin/hv-qa-query hv-skills` |

## ID and counter helpers

`hv-next-id <namespace>` reads `.hv/counters.json`, increments the counter for
the given namespace, writes it back, and prints the zero-padded ID (e.g. `B07`,
`F03`, `T12`). It is safe to call concurrently; the write is atomic via a temp
file. Every skill that mints a new backlog item calls this first.

`counters.json` lives at `.hv/counters.json` and is never overwritten by
`/hv-init`. Add namespaces freely; the file grows as you use new ones.

## Backlog manipulation

`hv-append` inserts a formatted entry under the matching `##` section heading in
[`BACKLOG.md`](hv-folder.md). `hv-complete` rewrites an open item as a struck-through `~~line~~`
and moves it under `## Completed`, stamping it with the supplied git SHA.
`hv-archive-old` sweeps `## Completed` entries older than N days into
`ARCHIVE.md` to keep the working file short. `hv-todo-by-milestone` lets you
filter the backlog by milestone tag; see also [Knowledge and vision
indexes](#knowledge-and-vision-indexes) where milestone state lives.

`hv-todo-field` extracts a single named field (`detail`, `related`, `milestone`, or `repos`) from the TODO bullet of a given item ID. It replaces the ad-hoc `grep | sed` chains that skill prose previously inlined for that purpose.

`hv-find-milestone-for-items` answers the inverse of `hv-todo-by-milestone`: given a list of item IDs, it prints the milestone tags those items carry in BACKLOG.md (unique, numerically sorted, open sections only — completed/archived items don't surface). Always exits 0; an unknown ID or untagged item is a silent skip, not an error.

`hv-plan-rename-check` wraps `git grep -l "<old-name>" [-- <scope>...]` so `/hv-work` Step 4 #3 ("Detect rename + link-sweep collisions") can name the check at both plan time and verify time. Always exits 0; no matches, no repo, and out-of-scope inputs are all silent. The pathspec scope is passed through to git grep, so `*.md`-style globs work.

`hv-uncertain` evaluates whether a backlog item warrants a `/hv-work --preview` pass before `/hv-plan` runs in loop mode. Exit 0 means the item is uncertain (reasons on stdout); exit 1 means it is clear enough to proceed directly to planning.

`hv-uncomplete` is the inverse of `hv-complete`: it lifts a struck-through entry out of `## Completed` (or `ARCHIVE.md`) and restores it to its original type section. Calling it on an ID that is already active is a silent no-op. On the completed→active transition it also rewinds `counters.json#since_refactor` for items whose resolved commit subject did not start with `refactor:`, mirroring `hv-complete`'s accounting. Used by `hv-undo` during cycle rollback; safe to call directly for one-off restorations.

`hv-undo` is the CLI entry point for the [`/hv-undo`](slash-commands.md#hv-undo) skill. It resets the last `/hv-work` merge commit on the base branch and restores each TODO via `hv-uncomplete`, all in one transaction. Direct-merge cycles only (MVP); refuses on cycles with post-merge commits unless `--allow-post-merge` is passed, and refuses on a dirty tree (exit 2). Defaults to a dry-run preview; the slash command always asks before applying.

## Status and reconciliation

`hv-status-add` writes a branch record into `.hv/status.json` so the project knows a piece of work is in flight. It is idempotent: calling it twice for the same branch is safe. `hv-status-remove` drops the record when work merges or is abandoned.

`hv-reconcile` cross-checks every entry in `status.json` against live git state and removes records whose branches no longer exist. It emits a JSON summary that skills use to avoid acting on stale context. `hv-summary` prints a human-readable snapshot of the same data: backlog counts, what's actively in progress, and recent completions. Its JSON output also includes a `todoDrift` array — IDs that appear in commit subjects (e.g. `[B07]`) but are still listed as open in `BACKLOG.md`, with the most recent commit hash for each. [`/hv-next`](../usage/picking-work.md) Step 2 surfaces this so users can `hv-complete` an entry that already shipped.

In umbrella mode, every status helper accepts `--repo <name>` to scope the entry to a registered sub-repo. `hv-status-add` keys uniqueness on `(branch, repo)`, so the same branch name can exist independently across multiple sub-repos. `hv-status-remove` without `--repo` removes only legacy entries (where `repo` is null or missing); add `--repo <name>` to remove an umbrella-tagged entry. `hv-reconcile` reads `.hv/repos.json` and validates each entry against its scoped sub-repo's `.git/`, with base-branch resolution per repo.

In umbrella mode the umbrella tree itself often has no base branch (it's a coordinator, not a working repo). When that happens, `hv-reconcile` skips `commitCount` for umbrella-cwd entries and stamps each with `noBase: true`. Skill flows that recommend Ship vs Resume vs Abandon should treat `noBase: true` as "indeterminate" rather than zero commits.

`hv-status-repo-for` is a lightweight lookup: given a branch name it prints the `repo` field from the matching active stream entry (umbrella mode), or an empty string when the branch is not active or the project is single-repo. It always exits 0, so skill prose can call it without error handling.

`hv-loop-stamp` manages the `loopStartedAt` ISO timestamp in `status.json` that loop-mode skills use to scope auto-logged decisions to the current session. `start` writes the timestamp once (no-op if already set), `clear` removes it, and `read` prints the stored value (or empty stdout when unset).

## Knowledge, vision, and decisions indexes

`hv-knowledge-index` and `hv-knowledge-query` operate on `.hv/KNOWLEDGE.md`. `hv-knowledge-index` regenerates the `<!-- hv-knowledge-start -->` block in `CLAUDE.md` so the agent always sees an up-to-date topic list. `hv-knowledge-query` pulls specific topic sections out of `KNOWLEDGE.md` by name, useful when scripting post-session summaries.

`hv-knowledge-merge` adds a new bullet to `.hv/KNOWLEDGE.md` under an existing topic, with the schema `- **<Title>** — <body> <!-- YYYY-MM-DD -->`. Dedup is exact (case-insensitive) title match within the topic; calling the helper twice with the same `--topic` + `--title` is a silent no-op (idempotent). The body comes via `--body <text>` or stdin. Creating a new `## <Topic>` heading is the caller's job; the helper requires the topic to already exist.

`hv-knowledge-amend` mutates an existing bullet in place, appending text after the trailing `<!-- date -->` comment. The bullet is found by case-sensitive fragment match within the named topic, so pick a distinctive substring (typically a word or phrase from the body) so the match is unique. Used by `/hv-learn` Step 8.5 to attach the `Upstream: hv-skills#<N>` marker after filing an upstream issue.

`hv-knowledge-stats` reports the bullet count and byte size of each topic in `KNOWLEDGE.md` as JSON. [`/hv-learn`](../usage/learning.md) Step 8 calls it after merging new bullets and prints a one-line nudge per topic that crosses 25 bullets or 10 KB, so editorial splits stay user-driven.

`hv-decisions-index` and `hv-decisions-query` operate on `.hv/DECISIONS.md`
identically. The file structure, marker shape, and query semantics all mirror
the knowledge helpers. The distinction is semantic: decisions are *active*
hard boundaries (committed via `/hv-decide` with mandatory forbids/permits),
while knowledge is *passive* gotchas captured by `/hv-learn`. See
[Decisions](../usage/decisions.md) for when to use which.

`hv-auto-decision-log` writes an `[Auto:Loop]` entry into `DECISIONS.md` under a named topic. It is idempotent on `(topic, rule-title)` — calling it twice with the same arguments yields one entry. Used by loop-mode skills to record provisional decisions that still need user articulation of Forbids/Permits.

`hv-auto-decisions-since` reads the `loopStartedAt` timestamp from `status.json` and prints a markdown summary of every `[Auto:Loop]` decision whose footer date falls on or after that date. It exits 0 with empty stdout when no entries match; terminal-path skills (`/hv-ship`, `/hv-pause`) use it to surface unresolved provisional decisions before closing out a loop session.

`hv-section-query` is the shared backing helper for `hv-knowledge-query`, `hv-decisions-query`, and `hv-context-query`. Pass a key (`knowledge`, `decisions`, or `context`) and one or more topic names; it prints the matching `## <topic>` section bodies from the corresponding file. The typed wrappers are preferred for human use; `hv-section-query` is useful when scripting against multiple files in one call.

`hv-skills-index` regenerates the `<!-- hv-skills-start -->` block in `CLAUDE.md` with the canonical slash-command index. The body is static and identical across every hv-skills project, so reruns are always idempotent. Called by `/hv-init` and `/hv-update`; you rarely need to invoke it directly.

`hv-context-query` and `hv-context-index` operate on `.hv/CONTEXT.md` — the domain glossary written by [`/hv-context`](slash-commands.md#hv-context). In umbrella mode, `hv-context-query` returns the union of umbrella-shared and active-sub-repo terms (sub-repo entries win on name collision). `hv-context-index` regenerates the `<!-- hv-context-start -->` block in `CLAUDE.md`; when called from inside a sub-repo it includes a `### <repo>` sub-heading for sub-repo-scoped terms after the umbrella-shared block. `hv-context-add` is the write path: it inserts or updates a term, re-renders the file body alphabetically, and exits 3 on alias collision or 4 on umbrella resolution failure. `hv-context-map` regenerates `.hv/CONTEXT-MAP.md` (umbrella only). See [capturing terminology](../usage/context.md) and the [CONTEXT.md format reference](context-md.md).

The vision group manages milestones in `.hv/milestones/`. `hv-vision-add` mints the next `MNN` ID, creates the milestone file, and appends its overview line to `MILESTONES.md`. `hv-vision-status` updates both the file's frontmatter and the overview line atomically. `hv-vision-active`, `hv-vision-list`, `hv-vision-index`, and `hv-vision-empty-active` let you query and refresh milestone state. `hv-vision-index` also regenerates the `<!-- hv-vision-start -->` block injected into `CLAUDE.md`. `hv-vision-empty-active` prints active milestone IDs that have zero open TODO items, one per line; empty stdout is a valid answer and the helper always exits 0.

`hv-todo-by-milestone` is covered in [Backlog manipulation](#backlog-manipulation).

## Design helpers

Designs live at `.hv/designs/<ID>.md` and are per-item: the ID must match `[BFT]\d{2,}` (e.g. `B07`, `F12`, `T11`). Milestone (`M01`) and slice (`S01`) IDs are rejected; project-level exploration belongs to `/hv-vision`, slice planning belongs to `/hv-plan`.

`hv-design-add` is the writer: it mints `.hv/designs/<ID>.md` with frontmatter (`id`, `title`, `status: draft`, `created`) and five empty sections (Goal, Design, Approaches considered, Open questions, Assumptions). It exits 1 on a bad ID or a pre-existing artifact. `hv-design-show` prints the file's contents and exits 1 when the artifact is missing. `hv-design-rm` deletes the file and exits 1 when the artifact is missing. `hv-design-list` returns JSON for every design with `id`, `title`, `status`, `created` — always exits 0, useful for dashboards and post-cycle audits.

See [Brainstorming a design](../usage/brainstorm.md) for the user-facing flow these helpers back.

## Plan and spike helpers

Plans live at `.hv/plans/<milestone>-<unit>.md`. `hv-plan-add` creates a plan
file; passing `slice` as the unit makes it auto-increment the slice number
(`S01`, `S02`, …). The optional `--design <path>` flag records a `design:` pointer
in the plan's frontmatter when a `.hv/designs/<ID>.md` artifact exists for the item;
the path must start with `.hv/designs/` and the file must exist or the helper
exits 1. `hv-plan-list` returns JSON you can pipe into other tools.
`hv-plan-show` and `hv-plan-rm` are straightforward read/delete operations.

Spikes live at `.hv/spikes/<name>.md` with a matching `spike/<name>` git branch.
`hv-spike-add` creates both in one call. `hv-spike-finish` closes the spike and
records the finish date. `hv-spike-list` returns JSON with a `branchExists` field
so you can detect spikes whose branches were already deleted.

## Merge and PR helpers

`hv-merge` handles the full merge ceremony for a worktree branch: it removes the worktree, merges `--no-ff` into the current branch, and deletes the source branch. The commit message is read from stdin, so you can compose it before calling the helper. `hv-pr` does the equivalent for pull-request workflows: remove the worktree, push the branch, and call `gh pr create` with a body read from stdin.

`hv-ship-body` builds a standardised PR body for a branch by scanning its
commits for referenced IDs and matching them against open TODO entries.
`hv-review-scope` emits a richer JSON payload (commits, touched files,
referenced IDs, and matched TODO entries) that the [`/hv-review`](../usage/review-and-ship.md) skill consumes.
`hv-review-scaffolding` complements `hv-review-scope` with a deterministic regex sweep over the diff between base and branch, surfacing candidate stale scaffolding comments as `<file>:<line>:<text>` for the reviewer to judge.

All four helpers (`hv-merge`, `hv-pr`, `hv-review-scope`, `hv-review-scaffolding`) accept `--repo <name>` in umbrella mode to target a registered sub-repo's `.git/`. Without the flag they operate on cwd's git tree as before.

## Diagnostics

[`hv-preflight`](preflight.md) verifies that `.hv/` is initialised and every expected helper is
present. It exits `0` on success, `2` if the folder is missing, and `3` if
helpers are incomplete. Useful as a guard at the top of scripts.

`hv-update-check` queries the hv-skills GitHub releases and returns JSON with
the current and latest version, install type, and the command to upgrade.
`/hv-init`'s Step 5 confirm reads the same JSON to append a one-line version +
freshness hint to the init summary (`current` → `(latest)`, `behind` →
`→ <latest> available — run /hv-update`, `ahead`/`unknown` fall back to a
version-only line).

`hv-version-check` is the local sibling: it compares `.hv/config.json#hvSkills.version` (stamped at `/hv-init` time) with the currently-installed plugin's version. On drift it prints a one-line nudge; with `--json` it always emits `{stamped, installed, status}`. `bin/hv-preflight` calls it informationally on every preflight, so any skill that runs preflight surfaces the nudge to the user when the project's helpers have fallen behind the plugin. Distinct from `hv-update-check` — that one needs the network and compares installed vs latest GitHub release.

`hv-refactor-age` reads `counters.json#since_refactor` and returns JSON with
the number of features and bugs completed since the last refactor cycle.
`/hv-refactor` uses this to decide whether a pass is overdue. The counter is
maintained imperatively: `hv-complete` increments it on every active→completed
transition whose resolved commit's subject does not start with `refactor:`,
and `hv-refactor-reset` zeros it after a `/hv-refactor` cycle commits.
`hv-refactor-targets` enumerates refactor targets (the umbrella's `hasCode` flag plus every registered sub-repo) so `/hv-refactor` Step 1.5 can ask which scope to fan out across.

`hv-map-cap-check` is an advisory nudge: it emits a one-line message to stderr when the project map's subsystem count meets or exceeds the soft cap (see `.hv/config.json#map.softCapSubsystems`), and stays silent below. It always exits 0, never a gate, only a hint. `/hv-debug`, `/hv-go`, and `/hv-work` call it post-cycle so users see "you might want to `/hv-map consolidate`" without ever being blocked.

`hv-backlog` renders the full BACKLOG.md as sorted Markdown tables (In Progress,
Bugs, Features, Tasks). Handy for a quick terminal overview or piping into
other scripts. Pass `--grep <pattern>` to filter Bugs / Features / Tasks rows
by case-insensitive substring against each item's bullet line (matches across
ID, title, description, and `Related:` tags). The In Progress section is
state and is never filtered; the Clusters section keeps clusters whose any
member matched, preserving all member IDs for context.

`hv-guard-clean` exits non-zero when the git working tree is dirty or the
current directory is not inside a git repository. Skills call it as a safety
check before making commits. On a fresh repo with no commits yet, a dirty tree
produces a tailored message naming the `chore: import initial files` baseline
commit pattern instead of the generic stash-or-commit hint.

`hv-require-git-context` is a companion preflight for umbrella-mode tools: if cwd is an umbrella root that has no `.git/` of its own, it exits 1 with a friendly error pointing the user to a sub-repo. Pass `--repo-flag-supported` when the calling tool has a `--repo` option to name in the error message. The helper is a no-op (silent exit 0) when cwd already has git context.

## Upstream issue helper

`hv-issue-suggest` opens an issue against the hv-skills upstream repo when a learning or debug session surfaced a gotcha rooted in hv-skills behavior. The helper reads its body from stdin, takes a `--title` flag, and pre-fills the `gh issue create` call. If `gh` is missing or unauthed, it prints a manual-fallback block (URL + title + body) and exits 1 so the caller can show it to the user.

The upstream repo defaults to `l4ci/hv-skills`; pass `--upstream-repo <owner/repo>` (or set the `HV_UPSTREAM_REPO` env var) to target a fork. `/hv-learn` Step 8.5 uses this helper after the user explicitly opts in — filing a public issue is always a manual user-volition gate, never auto-invoked.

## Issue tracker sync (`/hv-capture --from-github` / `--from-gitlab`)

Distinct from the upstream-issue helper above. These five helpers back the project-level [`/hv-capture --from-github` / `--from-gitlab`](slash-commands.md#hv-capture---from-github----from-gitlab) flow that pulls open GitHub/GitLab issues into `BACKLOG.md` with round-trip closing via `/hv-ship`. They all accept `--repo <name>` in umbrella mode to scope the call to a registered sub-repo.

`hv-issues-provider` detects whether the active git origin points at GitHub or GitLab, printing `github`, `gitlab`, or `unknown`. The match is hostname-based (`github*` → github, `gitlab*` → gitlab), so self-hosted and enterprise instances resolve correctly. Always exits 0 — `unknown` is a valid result, not an error.

`hv-issues-list` is the read path: it shells out to `gh issue list --state open` or `glab issue list --opened`, normalizes the output, and emits a uniform JSON array regardless of provider. Optional `--label <name>` and `--limit <N>` flags pass through to the underlying CLI. An empty result (`[]`) and a missing CLI are distinguished: empty list exits 0, but a missing or unauthed `gh`/`glab` exits 1 with a stderr message — skills should treat exit 1 as "fix your setup," not "nothing to do."

`hv-issues-imported` is the dedupe index: it scans `BACKLOG.md`, `ARCHIVE.md`, and every per-item detail file under `.hv/bugs/`, `.hv/features/`, `.hv/tasks/` for `GH: #N` or `GL: #N` cross-references and emits JSON tagged with provider, issue number, item ID, and the resolved `Repos:` value (multi-repo items emit one entry per sub-repo). `/hv-capture --from-github` / `--from-gitlab` subtracts this set from `hv-issues-list` output so already-imported issues are never re-offered.

`hv-issues-label` is the writer for upstream labeling — typically `in-progress` after import so collaborators see the issue is claimed. `apply` and `remove` are both idempotent (no-op on the already-present / already-absent transitions). When `issues.autoCreateLabel` is true in `.hv/config.json` (default), it creates the label upstream if absent rather than failing.

`hv-issues-close` is the round-trip closer: given an issue number and the shipping commit SHA, it closes the upstream issue and posts a tracking comment naming the commit. Called by `/hv-ship` on the direct-push path after explicit user opt-in; the PR path relies on `Closes #N` lines in the body to auto-close on merge instead. Exit 0 on successful close or already-closed (no-op); exit 1 on bad inputs or auth/CLI failure.

## Umbrella mode helpers

When `umbrella.enabled` is true in `.hv/config.json`, the umbrella's `.hv/` coordinates work across multiple sub-repos registered in `.hv/repos.json`. Three helpers manage that registry and the cwd-to-sub-repo resolution.

`hv-umbrella-init` runs once during [`/hv-init`](slash-commands.md#hv-init) Step 1.5 (see [Umbrella mode](../usage/umbrella-mode.md) for the user-facing flow). It scans immediate children for `<child>/.git/`, reads one line of stdin (`all` / `none` / comma-separated names) to pick a subset, writes `.hv/repos.json`, and, if the umbrella is itself a git repo, appends `.claude/`, `.hv/`, and `/<repo>/` lines to the umbrella's `.gitignore` under a `# ── hv umbrella ──` header.

`hv-resolve-umbrella` walks up from cwd to find the umbrella's `.hv/`. It also detects a footgun: a stray `.hv/` directory inside a registered sub-repo (e.g., from a misplaced `/hv-init` from inside the sub-repo). It exits 2 with a `masking` message in that case. `hv-resolve-repo` identifies which registered sub-repo cwd belongs to, working transparently from a Layout B worktree at `<umbrella>/.claude/worktrees/<repo>/<branch>/` via `git rev-parse --git-common-dir`.

`hv-resolve-repo-path` is the symmetric counterpart: given a registered sub-repo *name*, it returns the absolute path from `.hv/repos.json`. It replaces the inline Python heredocs that `hv-merge`, `hv-pr`, `hv-spike-add`, and `hv-review-scope` previously duplicated for the same lookup. Exits 1 with a friendly error if the registry is empty or the name is not registered.

`hv-umbrella-on` prints `yes` when umbrella mode is in effect (`.hv/repos.json` registers at least one sub-repo) and `no` otherwise. It always exits 0 and treats any read error as `no`. Accepts an optional `<dir>` argument for callers that already know the umbrella root path. Use it instead of inspecting `config.json` — the repos.json registry is the authoritative source of truth.

`hv-walk-up` walks up from an anchor directory looking for a marker (default `.hv/`) and prints the absolute path of the directory that contains it. Pass `--detect-masking` to additionally check whether the found marker is a stray `.hv/` inside a registered sub-repo that masks an umbrella further up the tree (exits 2 in that case). Most callers should source `hv-self-locate.sh` instead, which combines the walk-up with the `HV_ORIG_PWD` export; `hv-walk-up` is exposed for scripts that need the raw walk-up primitive.

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
2. Writes initial data files (skipping any that already exist): `BACKLOG.md`,
   `KNOWLEDGE.md`, `DECISIONS.md`, `MILESTONES.md`, `counters.json`,
   `status.json`.
3. Appends a `.hv/` entry to `.gitignore` if one is not already present.

It does **not** copy helper scripts; that is `/hv-init`'s job. It is called by
`/hv-init` from the hv-skills *source* `bin/`, not from `.hv/bin/` itself, and
it never overwrites files that already exist. You do not normally need to call
this directly. Rerun `/hv-init` if you want to refresh the installation.
