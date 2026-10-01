# Issue mode

Applies when `backlog.backend` is `"issues"` in `.hv/config.json` (check: `python3 -m hvlib_backend is-issues` exits 0; helpers already branch on it). The tracker (GitHub or GitLab) is the backlog; `.hv/BACKLOG.md` and `.hv/<kind>/` detail files are not used. File mode is unchanged and every skill keeps its file-mode steps. This page lists only where issue mode differs.

## IDs

An ID is the type letter plus the issue number: `#42` is `F42` (feature), `B42` (bug) or `T42` (task); helpers also take `42`. The letter must match the issue's type label.

## Helper map

| Need | Helper |
|------|--------|
| Capture an item | `hv-item-create <bugs\|features\|tasks> --title T [--tag TAG] [--desc D] [--body-file F] [--field Name=Value]...` |
| Take an item (lock) | `hv-item-claim <ref> --as <claim-id>`; the claim-id is the work branch name |
| Give it back | `hv-item-release <ref> --as <claim-id>` |
| Specified well enough? | `hv-item-ready <ref>` (prints one reason per line when not) |
| Workflow label | `hv-item-state <ref> in-progress\|needs-review\|changes-requested\|none` |
| Proof rows | `hv-proof-add <ID> --check <name> --result PASS\|FAIL --evidence <text> [--sha <commit>]` (stored in the item's proof note) |
| Design / plan artifact | `hv-design-add` / `hv-plan-add` create it, `hv-design-put <ID> --body-file F\|-` / `hv-plan-put <key> --body-file F\|-` fill it, `hv-design-show` / `hv-plan-show` read it; raw access: `hv-item-note <ref> --kind proof\|design\|plan (--body-file F\|- \| --show \| --rm)`. Slice plans stay files. |
| Question, answer, decision, feedback | `hv-item-comment <ref> --kind question\|answer\|decision\|feedback --body-file F\|-` |
| Open the PR / MR | `hv-pr --closes <ID[,ID...]> <branch> "<title>"` (body on stdin) |
| What needs review | `hv-review-queue` (JSON: `needs-review` items with the open PRs / MRs whose body closes them) |
| Merge a reviewed PR / MR | `hv-pr-merge <pr> [--items <ID[,ID...]>]` (checks proof first, then merges and closes what the host left open; exit 5 = not merged, an item unproven) |
| Close | `hv-complete <ID> [commit-hash] [--reason done\|handed-off\|blocked\|dropped] [--note <text>]`; reopen with `hv-uncomplete` |

**Post every `AskUserQuestion` answer that changes an item's direction** as a `decision` (or `answer`) comment with `hv-item-comment`, so later sessions, which share no memory with this one, see why the item took its shape.

## State labels

One of `in-progress`, `needs-review`, `changes-requested` at a time, cleared on close.

- `hv-item-claim` sets `in-progress` (and assigns the user).
- `hv-item-state <ref> needs-review` after the PR / MR is open.
- A reviewer sets `changes-requested` (`/hv-review --queue`, or `hv-pr-merge` for an unproven item); the next `/hv-work` claim returns it to `in-progress`.

## PR flow

`/hv-work`, `/hv-debug` and `/hv-ship` in issue mode always open a PR / MR, whatever `work.mergeStrategy` says (it is treated as `pr`). `hv-pr --closes <IDs>` appends one `Closes #<n>` line per item, so the tracker closes the issues when the PR merges. The claim stays until then: do not call `hv-item-release` after opening the PR.

**Merging belongs to `/hv-review --queue`.** It lists the queue with `hv-review-queue`, reviews each PR / MR, and merges PASSes with `hv-pr-merge <pr>`. It checks proof before merging: an open linked item with no proof blocks the merge (the item becomes `changes-requested` with a feedback comment, exit 5), because a merge into the default branch lets the host close the issue and skip the gate. After a merge, the host closes the linked issues itself when the PR targets the default branch; for any other base `hv-pr-merge` closes them with `hv-complete` semantics (reason done, merge sha). `/hv-work` and `/hv-ship` never merge in issue mode and never call `hv-complete` for a `done` close: the merge closes the issue.

`hv-complete` is still how to close an item with `--reason handed-off|blocked|dropped`. Reasons: `done` closes as completed; `dropped` and `handed-off` close as not planned (comment carries reason and note); `blocked` keeps the issue open with the `blocked` label.

## Milestones and release

A milestone is a native tracker milestone `MNN — <title>` plus a tracking issue labelled `milestone-tracker` and `status:<status>`; its body is the milestone plan. Slice plans are `plan:SNN` notes on that issue. `/hv-vision` writes them via `hv-vision-add` / `hv-vision-put` / `hv-vision-status`, `/hv-plan` via `hv-plan-add` / `hv-plan-put`. `/hv-release --milestone MNN` gates on `hv-release-milestone-check`, drafts notes with `hv-release-notes-from-issues`, and after the tag closes out with `hv-release-close-milestone`. Exit codes: `1` usage or unknown milestone, `2` backend unavailable or file mode, `3` tracker unavailable, `4` rate-limited; `hv-release-milestone-check` also exits `6` when blocked.

## Resuming an item

A fresh session has only the tracker. Load an item's context before working it:

1. `hv-todo-field --dump <ID>`: the issue body and fields.
2. `hv-item-note <ID> --kind design --show` and `--kind plan --show`: the design and plan notes (empty when absent).
3. The comments (questions, answers, decisions, feedback, claim history):
   - GitHub: `hv-tracker-call -- issue view <n> --comments`
   - GitLab: `hv-tracker-call -- issue view <n> --comments --output json`

Treat `decision` comments as binding and `feedback` comments (from review) as the to-do list for a `changes-requested` item.

## Umbrella

With `.hv/repos.json` registering sub-repos (`references/umbrella-mode.md`), `UmbrellaIssueBackend` keeps each sub-repo's items on that sub-repo's own tracker. The provider is auto-detected from each origin, so GitHub and GitLab can mix.

- **Reads merge** into one backlog; bullets carry `Repos: <name>` and `hv-backlog` shows qualified IDs `<repo>:<ID>`. Known limitation: its Clusters section keys on plain IDs.
- **Refs.** `<repo>#<n>` and `<repo>:<ID>` always resolve. A bare `F42` / `#42` resolves only when exactly one sub-repo has it; otherwise exit 1 lists the candidates. `hv-item-create` returns qualified IDs.
- **Capture** needs a target repo (`--field Repos=<name>` or cwd inside a sub-repo). Multi-repo items are refused: capture one per repo and link with `Related:`. `Repos` is immutable on an existing item.
- **Milestones.** The tracking issue and slice plans live in the home repo (`issues.homeRepo`, default the first registered sub-repo). A sub-repo's native milestone `MNN — <title>` is created when an item there is first assigned to MNN. Milestone reads report `shipped` only once every sub-repo's native milestone MNN is closed.
- **Release runs per sub-repo.** `hv-release-milestone-check`, `hv-release-notes-from-issues` and `hv-release-close-milestone` take `--repo <name>`, required here (exit 1 without).
- **Review.** `hv-review-queue` spans all sub-repos (entries carry `repo`, IDs qualified). `hv-pr --repo <name> --closes ...` falls back to the cwd's sub-repo; `hv-pr-merge --repo <name>` is required.

## Exit codes

Shared by the `hv-item-*`, `hv-pr` and `hv-tracker-call` helpers:

- `3` tracker unavailable (CLI missing, not authenticated, provider unknown): stop and report; do not fall back to files.
- `4` rate-limited: stop and report; never retry in a loop.
- `5` claim lost (`hv-item-claim`: another worker holds the item): drop that item and pick another. `hv-pr-merge`: merged, but a linked item has no proof and stays open: report it.
