# Parallel rounds

A round is one orchestrator session plus two to five workers, each a standing agent in
its own git worktree and herdr workspace, each holding one GitHub issue at a time. Workers
implement, verify and open a PR; they never merge. The orchestrator assigns issues, relays
decisions, merges PRs and re-verifies on `main` after every merge.

The orchestrator runs the `hv-orchestrate` skill, which holds the judgment (which issues,
how to read a stuck worker, what to escalate, when to merge). The mechanics are `hv round`
verbs, so a round never polls in the orchestrator's context. A worker reads
`references/worker-contract.md`; `hv round assign` points it there. This file adds only what
is specific to hv-skills.

## The round flow

| Step | Verb | What it does |
|---|---|---|
| Check | `hv doctor` | git, host, tracker auth, accounts, herdr hooks, `hv` version; each failure carries its fix |
| Start | `hv round start` | takes the repo's orchestrator lease, provisions slots, lists ready candidates |
| Pick | `hv round candidates` | the open items that pass the criteria, dependency and overlap checks |
| Assign | `hv round assign <ID>` | claims the item, marks it in progress, cuts `<agent>/<issue>-<slug>`, starts the worker with a signed pointer brief |
| Wait | `hv round wait` | blocks until one slot needs the orchestrator, then returns it; never poll |
| Look | `hv round status`, `hv round reconcile` | the round's rows and drift; `reconcile --apply` repairs what is safe |
| Ask | `hv round escalate send`, `escalate check` | puts a question to the maintainer on the issue or PR thread and reads the answer |
| Merge | `hv worker gate <slot> --base <branch>` | verifies on the merged tree, merges on a pass; a manual gate (B1) refuses without the maintainer's answer |
| Clean | `hv reap` | lists, then with `--apply` removes, what no live slot owns; never kills a running agent |
| End | `hv round wind-down` | re-verifies the base, parks every slot, releases the lease |

Each verb's arguments, data and exit codes are in `docs/design/5.0-verb-contract.md`.

## The gate

Both, before every PR, from inside your worktree:

```sh
python3 test/validate-skills.py      # under a second
bash test/smoke.sh                   # ~75 s on main; sequential by design
```

Read the final `All smoke tests passed.` line, not a pipe's exit code. If the suite fails,
run it on `origin/main` in a throwaway worktree before triaging your branch
(`.hv/KNOWLEDGE.md`, "Pre-existing smoke failures"). Smoke sections are sourced by
`test/runner.sh`, never executable alone. New sections take the number your dispatch assigns;
do not pick one yourself, siblings are numbering theirs at the same time.

The Go gate is `go vet ./...` and `go test -race -timeout 30m ./...` (the default 10m timeout can
be hit on a loaded box, #120). Most of `cmd/hv`'s time is the `TestFrozen*` scenario suites: each
scenario runs the Go binary and compares what it did with its record in `cmd/hv/testdata/frozen/`.
A deliberate behaviour change updates the record with
`go test ./cmd/hv -run '^TestFrozen<Suite>$' -update-frozen`; say why in the PR, since the jsonl
diff is the review.

There are no servers and no ports in this repo. The full suite is cheap enough that the
worker gate and the orchestrator's merge gate are the same commands.

## Repo rules that bind workers

- Edit canonical sources only: `cmd/`, `internal/`, `hv-*/SKILL.md`, `references/`, `docs/`, `test/`.
- Never hand-edit tracked `.hv/` content. The backlog row for your issue is updated by the
  orchestrator at merge time.
- Before touching a verb, pull the matching `.hv/KNOWLEDGE.md` topics with
  `hv knowledge query "<exact ## heading>"`. The topics that bite most: *Architecture: Helper
  conventions & invariants*, *Architecture: Module extraction & migration safety*, *Build &
  Tooling: Smoke testing*.
- A new verb needs a contract entry in `docs/design/5.0-verb-contract.md` and a smoke section.
- Config keys are documented in five places at once: `docs/reference/config-options.md`,
  `docs/usage/configuration.md`, `hv-config/SKILL.md`, `hv-init/SKILL.md`,
  `internal/config/schema.go`. Touch only the lines about your key; a sibling may be adding
  another key in the same files.
- Stage explicit paths. Commit messages: imperative subject under 72 chars, body says why,
  no `Co-Authored-By` trailer.
- The PR body carries an `## Approvals` section citing the channel of every decision you
  acted on, and labels your own calls as unratified. Reference the issue so it closes on
  merge, unless the PR is a partial slice.

## Tracker CLI gotchas

On this repo `gh issue view <N> --comments` and `gh pr edit` fail with a Projects-classic
GraphQL deprecation error. Read an issue with `gh issue view <N> --json title,body,comments`
(the brief says `--comments`; use this instead), and edit a PR body through the REST API:

```sh
gh api -X PATCH repos/<owner>/<repo>/pulls/<N> -F body=@body.md
```

## Starting a round

`hv round start` takes the orchestrator lease, provisions the roster slots and lists the
candidates; it starts no agent.

```sh
hv round start --slots 3                    # scope from round.scope (default milestone)
hv round start --scope slate --items 12,13  # only these issues
hv round candidates                         # re-read the board with readiness checks
```

- **One orchestrator per repo.** The lease is `<git-common-dir>/hv/round-lease.json`, so
  every worktree of the repo shares it. A second `start` is refused (exit 4) and names the
  holder. The holder is the nearest non-shell ancestor of `hv` (in Claude Code, the `claude`
  process) plus its start time; pass `--holder-pid` where that cannot be read. A lease whose
  holder is gone is stale: `hv round reconcile` reports it (`lease-stale`) and `hv round start`
  reclaims it.
- **Slots** are the first `--slots` names of `round.roster`, each `.worktrees/<agent>` on
  `park/<agent>`. A healthy existing slot is left alone.
- **Candidates** carry three checks: `criteria` (acceptance criteria or a design/plan note),
  `dependencies` (every `## Depends on` reference is closed; one that cannot be looked up
  fails the check, so fix the issue text) and `overlap` (no shared file with an in-flight
  slot, from a `## Files` section or the paths the issue text names plus the slot's real
  changes). The overlap check cannot see files an issue will create, paths nobody wrote down,
  two issues editing the same function, generated files every issue touches (list those in
  `round.sharedPaths`), renames, or another machine's round.

## Assigning an issue

```sh
hv round assign 59 --check-only             # readiness only; exit 1 when not ready
hv round assign 59 --agent ben --body-file decisions.md --siblings 58,60,62
```

Without `--agent` the first idle roster slot takes it. Assign refuses (exit 4, `blockedBy`)
with `no round`, `out of scope`, `not ready`, `overlap`, `claimed`, `slot busy`,
`no free slot` or `brief missing`, and marks nothing in those cases. When it goes through it
claims the item (`<agent>@<round>`), sets it in progress with a comment, cuts the slot's
branch `<agent>/<issue>-<slug>`, picks the account and dispatches a short signed brief: a
pointer to the standing contract (`round.brief`, else `references/worker-contract.md`), the
issue to read and dispute, the siblings and the decisions from `--body-file`.
`--tier light|standard|heavy` picks the worker's model tier (default `round.tier`); a tier above the default needs `--tier-reason`. The tier and its model are recorded on the slot, shown by `hv round status`, and named in the brief with the tier table for the worker's own subagents. `--kind codex` resolves the model but exits 71 until Codex workers land (E1).
`--accept-overlap` skips the file-overlap check only. A failure before dispatch undoes the
claim and state; one at or after dispatch keeps them, and repeating the call resumes.

## Winding down

```sh
hv round wind-down                # verify the base, park every slot, release the lease
hv round wind-down --no-verify
```

Run it from the orchestrator that holds the lease, with the base checked out and clean in
the project root. It re-verifies the base (`refactor.verifyCommands`), then parks every
roster slot on `park/<agent>` and releases the claims, then releases the lease. A red base
(`verify-failed`, exit 1) keeps the lease. A slot with uncommitted changes or commits not on
the base is reported as `retained` and left alone (`holds-work`, exit 4); the other slots are
parked anyway, so fix the slot and run it again. It deletes no branch and clears no label: the
`drift` count says what `hv round reconcile` and `hv reap` still have to do.

## Moving an issue that is assigned

```sh
hv round return ben --reason "wrong premise" --note-file next.md   # the worker's own verb
hv round transfer 59 --to dana --note-file next.md                 # orchestrator: to a slot
hv round transfer 59 --to human                                    # orchestrator: to the human
hv round reclaim ben                                               # orchestrator: dead or stalled slot
```

All three free the slot the same way (`Park`): dirty paths are committed by name as
`wip: parked from <slot> (hv round <verb>)`, the work branch is pushed to `origin` (no force)
and only then is the worktree switched to `park/<agent>`. A failed push or a rejected commit
leaves the slot as found (exit 5), so the branch is never the only copy of the work. Each
posts a handoff comment on the issue (branch, head, state, reason, your `--note-file`) ending
in `<!-- hv:handoff <slot>@<round> -->`.

- **return** releases the claim and the in-progress label, so `candidates` lists the issue
  again; the branch stays and an open PR stays open. Run it inside the slot's worktree, or as
  the lease holder. An `assign` after a return starts fresh; `transfer` is the verb that
  continues a pushed branch.
- **transfer to a slot** checks the pushed branch out in the receiver's worktree and
  dispatches it with a brief that names the handoff; the in-progress label stays on. **To
  `human`** labels the issue `needs-human` (`issues.labels.needsHuman`), claims nothing and
  dispatches nothing; `candidates` skips it until the human clears the label.
- **reclaim** works on a slot that is `dead` or `stalled` (no commit, edit or state change for
  `round.stallMinutes`, default 30, `0` is off). A healthy slot needs `--force`; a live pane is
  killed first, and with no host to ask it is refused as `live agent`. It does not reassign.
  `hv reap` may reclaim `dead` slots only, never `stalled` ones: a worker in a long test run
  makes no commits and looks stalled, and an unattended `reap --apply` would kill it.
- `hv round reconcile` reports `stalled` (never repaired) and `claim-mismatch` (`--apply`
  clears a registry `claimId` whose claim is gone; the tracker is never edited).

## Waiting on workers

`hv round wait [<slot>...] [--timeout <s>]` blocks until a worker needs attention and prints
the slot and its state as JSON, so the orchestrator never polls in its own context. It
classifies with the same rules as `hv worker poll` (sentinels, `limited`, `dead`, then the
host's status) and writes nothing. With no slot named it watches every slot that has a
session and whose recorded state is not `idle`; `worker dispatch` arms a slot.

- **herdr**: pinned to **0.9.x** (built against 0.9.3, socket protocol 22); another minor
  exits 5. One `events.subscribe` over `HERDR_SOCKET_PATH` carries a
  `pane.agent_status_changed` subscription per watched pane, so N slots cost one
  connection. The CLI's `herdr agent wait` takes one target, so waiting on the first of N
  slots would mean N child processes.
- **tmux**: no event stream and no agent status, so the verb re-captures the panes every
  `--settle` seconds (default 5) inside its own process.
- **Timeout** exits 1 with `data.timedOut: true` and every slot's state; it is an answer,
  not a fault. `--timeout` defaults to 0, which waits indefinitely.
- **Long waits in Claude Code**: the Bash tool kills a command at its `timeout`, which
  defaults to 2 minutes (`BASH_DEFAULT_TIMEOUT_MS`) and is capped at 10 minutes
  (`BASH_MAX_TIMEOUT_MS`). Raise the cap in `settings.json` under `env` (for example
  `"BASH_MAX_TIMEOUT_MS": "3600000"`) and pass a matching `timeout` on the Bash call, or
  loop on a finite `--timeout` shorter than the cap.

## Roster

Slots are provisioned once and reused. `hv round start` creates any missing slot at
`.worktrees/<agent>` on `park/<agent>` and leaves healthy ones alone. Every worktree lives in
the project root under `.worktrees/<agent>` (gitignored by `/hv-init`), and `hv worker pool`
shares the same root. `round.roster` sets the names; the default is `ben`, `dana`, `nia`, `kit`.

### Grouping a slot under the project in herdr

herdr groups a slot under the project only when its workspace is a **linked worktree
workspace** of the project's primary workspace. A workspace made with plain
`herdr workspace create`, or a worktree moved with `git worktree move`, is not linked and
shows up as a separate project. `hv round start` makes the worktree with git and calls no
herdr, and `hv worker dispatch` opens its tabs in the orchestrator's own workspace, so
neither is affected. This matters for a standing agent you run in its own herdr workspace.

Provision such a slot from the primary workspace:

```sh
herdr worktree create --workspace "$HERDR_WORKSPACE_ID" --path .worktrees/<agent> \
  --branch park/<agent> --base main --label <agent> --no-focus
```

To link an existing unlinked slot in place, leaving the agent running:

```sh
herdr worktree open --workspace <primary id> --path .worktrees/<agent>
herdr workspace rename <id> <agent>
```

The maintainer checked both in the herdr sidebar (round 4, #79).

Tools that walk the tree without reading `.gitignore` see a second copy of every file
under `.worktrees/`; none of this repo's verbs or tests do (smoke section 70 pins it).

Workspace ids are re-derived from
`herdr workspace list` at the start of each round; the label is the handle.

| name | kind | worktree | parking branch | account (`CLAUDE_CONFIG_DIR`) |
|---|---|---|---|---|
| ben  | claude | `.worktrees/ben`  | `park/ben`  | `/home/vo/.claude-work` |
| dana | claude | `.worktrees/dana` | `park/dana` | `/home/vo/.claude-personal` |
| nia  | claude | `.worktrees/nia`  | `park/nia`  | `/home/vo/.claude-work` |
| kit  | claude | `.worktrees/kit`  | `park/kit`  | `/home/vo/.claude-personal` |
| finn | claude | `.worktrees/finn` | `park/finn` | `/home/vo/.claude-personal` |

Model per dispatch is the orchestrator's call (`-- --model <m>` after `agent start`);
default Sonnet, Opus for multi-helper features.

## Maintainer answers typed into a pane

Prefix a direct answer with `m:` to make it citable without a confirmation round-trip. The
prefix is imitable, so a prefixed line that contradicts the last signed orchestrator
message still gets one confirmation.
