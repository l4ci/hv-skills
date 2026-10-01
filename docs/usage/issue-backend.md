# Issue backend

With `backlog.backend: "issues"` the tracker (GitHub or GitLab) is the backlog. `.hv/BACKLOG.md` and the `.hv/<kind>/` detail files are not used; items, milestones and design/plan artifacts live on the tracker. File mode is the default and is unchanged. Skills keep their file-mode steps and branch on the backend; the issue-mode differences are listed in `references/issue-mode.md`.

## Setup

1. Install and authenticate the CLI for your host: `gh auth status` (GitHub) or `glab auth status` (GitLab). With no CLI or no auth, helpers exit 3 and do not fall back to files.
2. Set the backend: `/hv-config backlog.backend=issues`.
3. Optional keys (all in `.hv/config.json`, full list in [Configuration](configuration.md#issues-backend-keys)):

| Key | Default | Use |
|-----|---------|-----|
| `issues.provider` | `"auto"` | `"auto"` detects from `origin`; or `"github"` / `"gitlab"`. |
| `issues.labels.*` | `in-progress`, `needs-review`, `changes-requested`, `released`, `not-planned`, `blocked`, `milestone-tracker`, `type:bug` / `type:feature` / `type:task`, prefix `p`, prefix `size:` | Rename any label role. |
| `issues.autoCreateLabel` | `true` | Create a missing label on first use. When off, a missing label is an error. |
| `issues.homeRepo` | `""` | Umbrella only: sub-repo holding milestone tracking issues; empty is the first registered sub-repo. |
| `issues.bulkPaceMs` | `1000` | Pause between writes in `hv-migrate-issues`. |
| `issues.retryWaitSeconds` | `60` | Wait before retrying a failed tracker call. |

## How items map to issues

An ID is the type letter plus the issue number: `#42` is `F42`, `B42` or `T42`. The letter must match the issue's type label.

- **Labels** carry type (`type:bug`), priority (`p0`..) and, for features, size (`size:Major`).
- **Body** holds the description and a fields block (`Related`, `Milestone`, `Repos`, ...).
- **Notes** are marker comments on the issue, edited in place: `proof`, `design`, `plan`. Read them with `hv-item-note <ID> --kind design --show`, `hv-design-show`, `hv-plan-show`.
- **Comments** record `question`, `answer`, `decision` and `feedback`. Decisions are binding for later sessions.

### Claim lock and state labels

`hv-item-claim <ref> --as <claim-id>` takes an item: claim comment, `in-progress` label, assignee. The earliest unreleased claim wins; a loser gets exit 5 and picks another item. State labels are one of `in-progress`, `needs-review`, `changes-requested` at a time, cleared on close.

### Review and close

`/hv-work`, `/hv-debug` and `/hv-ship` always open a PR / MR in issue mode and never merge. `hv-pr --closes <IDs>` adds `Closes #<n>` lines. `/hv-review --queue` lists `needs-review` items with their PRs (`hv-review-queue`), reviews them and merges with `hv-pr-merge`. Proof comes first: an open linked item with no proof blocks the merge, becomes `changes-requested` and gets a feedback comment (exit 5). Proof rows are added with `hv-proof-add` into the item's proof note.

`hv-complete <ID> --reason handed-off|blocked|dropped` closes without a merge: `dropped` and `handed-off` close as not planned; `blocked` keeps the issue open with the `blocked` label.

## Milestones and release

A milestone is a native tracker milestone `MNN — <title>` plus a tracking issue labelled `milestone-tracker` and `status:<status>`. The issue body is the milestone plan; slice plans are `plan:SNN` notes on it. `/hv-vision` and `/hv-plan` write them through the same helpers as file mode.

`/hv-release --milestone MNN` gates on `hv-release-milestone-check` (exit 6 when blocked), drafts notes with `hv-release-notes-from-issues`, and after the tag runs `hv-release-close-milestone`.

## Umbrella mode

Each sub-repo's items stay on that sub-repo's own tracker; the provider is detected per origin, so GitHub and GitLab can mix. Reads merge into one backlog with qualified IDs `<repo>:<ID>`. `<repo>#<n>` always resolves; a bare `F42` resolves only when exactly one sub-repo has it. Capture needs a target repo (`--field Repos=<name>` or cwd in a sub-repo); multi-repo items are refused, so capture one per repo and link with `Related:`. Milestone tracking issues live in `issues.homeRepo`. Release helpers take `--repo <name>` (required). See [Umbrella mode](umbrella-mode.md).

## Rate limits

Exit 3 means the tracker is unavailable; exit 4 means rate-limited. Both stop the run and report. Helpers never retry in a loop; wait, then re-run.

## Migrating a file backlog

```
/hv-migrate issues            # dry run: planned operations and would-be map
/hv-migrate issues --apply    # create everything
/hv-config backlog.backend=issues
```

Open items, their detail files, proof rows, design and plan artifacts, and planned/active milestones with their slice plans move to the tracker. Completed items, `ARCHIVE.md` and shipped milestones stay in the files. `Related:` fields and old IDs in migrated text are rewritten to the new IDs after every item exists.

The run is resumable: `.hv/issue-map.json` records each old ID, its new ID and URL. Commit it. A rate limit (exit 4) stops the run with the map saved; wait and re-run. `--limit N` creates at most N items per run. Writes are paced by `issues.bulkPaceMs`.

`--apply` never changes `backlog.backend`. When everything is migrated it adds a "Frozen" banner to `.hv/BACKLOG.md` and prints `Next: /hv-config backlog.backend=issues`. Old IDs are not resolved through the map after the flip; an old `F82` and a new issue `F82` can both exist. Umbrella projects migrate each sub-repo separately.
