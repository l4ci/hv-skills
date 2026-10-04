# Parallel rounds

A round is one orchestrator session plus two to five workers. Each worker is a standing agent in
its own git worktree and terminal tab (herdr or tmux), or an in-harness subagent when there is no
terminal host ([solo mode](#solo-mode)). Each holds one GitHub issue at a time. Workers implement,
verify and open a PR; they never merge. The orchestrator assigns issues, relays decisions, merges
PRs and re-verifies the base branch after every merge.

The orchestrator runs the `hv-orchestrate` skill, which holds the judgment: which issues, how to
read a stuck worker, what to escalate, when to merge. The mechanics are `hv round` verbs, so a round
never polls inside the orchestrator's context. A worker reads
[`references/worker-contract.md`](../../references/worker-contract.md); `hv round assign` points it there.

This page covers what a round does and how to run one. Running a round on hv itself, with its
gate and repo rules, is in [contributing: rounds](../contributing/rounds.md).

## Round or `/hv-work`

| | [`/hv-work`](running-work.md) | A round |
|---|---|---|
| Sessions | one, with subagents it launches per task | an orchestrator plus standing workers |
| Isolation | a branch or one worktree per cycle | one worktree per worker, reused across issues |
| Unit of work | an item or a batch you pick | one issue at a time per worker |
| Who merges | the session, or a PR you open | the orchestrator, after its own gate |
| Runs unattended | until the context fills | for hours, across restarts ([unattended rounds](unattended-rounds.md)) |
| Setup | none | a host, optionally several accounts, `hv doctor` |

Use `/hv-work` for a handful of items you are watching. Use a round when you have a queue of
well-specified issues that don't touch the same files and you want them merged without you steering
each one. If you run several `/hv-work` sessions by hand today, see [parallel work](parallel-work.md);
a round is the same idea with the assignment, waiting and merging done by verbs.

## Setup

1. **A host** for the workers' tabs: herdr (pinned to 0.9.x) or tmux. Set
   `work.dispatch` to `herdr` or `tmux`, or leave it unset and let `hv round start` detect one from
   where it runs (herdr inside a herdr pane, tmux inside tmux). With neither it falls back to
   [solo mode](#solo-mode).
2. **A tracker.** Rounds take GitHub issues (`gh`) or GitLab issues (`glab`), authenticated.
3. **Accounts, if you have more than one.** `work.accounts` maps slots to separate
   `CLAUDE_CONFIG_DIR`s, so workers draw on different usage limits and `hv round assign` can avoid a
   cooling account. The entries are paths on your machine, so they go in `.hv/config.local.json`
   (per developer, gitignored, merged over `.hv/config.json`), not in the tracked file.
   `hv config set` writes the tracked file, so edit this one by hand:

   ```json
   {
     "work": {
       "accounts": [
         { "name": "a", "configDir": "/path/to/claude-a" },
         { "name": "b", "configDir": "/path/to/claude-b" }
       ]
     }
   }
   ```

   `hv worker account list` then shows each account with its usage verdict.

4. **Issues a worker can pick up.** A candidate needs acceptance criteria or a design or plan note,
   closed dependencies and no file overlap with work in flight (see [Picking issues](#picking-issues)).
5. **Preflight.** `hv doctor` checks all of the above and names the fix for each failure. See
   [doctor and reap](doctor-and-reap.md).

For a round that must survive the orchestrator's context filling or a usage limit, also install the
hooks and run the orchestrator under `hv keepalive run`:
[unattended rounds](unattended-rounds.md). For Codex workers: [Codex workers](codex-workers.md).

## Your first round

```sh
hv doctor                                  # fix every fail it reports
hv round start --slots 2                   # take the lease, make two slots, list candidates
hv round assign 59 --body-file notes.md    # first idle slot takes issue 59; repeat for a second issue
hv round wait                              # blocks until a worker is done, blocked or dead
hv worker gate ben --base main             # verify on the merged tree, merge on a pass
hv round wind-down                         # re-verify main, park the slots, release the lease
hv reap --apply                            # delete the merged branches and leftovers
```

`hv round wait` returns the slot that needs you, so loop `wait` and `gate` (and `assign` for the next
issue) until the queue is empty. Replace `ben` with the slot `wait` named. Preview `hv reap` without
`--apply` first. The sections below cover each step.

## The round flow

| Step | Verb | What it does |
|---|---|---|
| Check | `hv doctor` | git, host, tracker auth, accounts, herdr hooks, `hv` version, Codex; each failure carries its fix |
| Start | `hv round start` | takes the repo's orchestrator lease, provisions slots, lists ready candidates |
| Pick | `hv round candidates` | the open items that pass the criteria, dependency and overlap checks |
| Assign | `hv round assign <ID>` | claims the item, marks it in progress, cuts `<agent>/<issue>-<slug>`, starts the worker with a signed pointer brief |
| Wait | `hv round wait` | blocks until one slot needs the orchestrator, then returns it; never poll |
| Look | `hv round status`, `hv round reconcile` | the round's rows and drift; `reconcile --apply` repairs what is safe |
| Ask | `hv round escalate send`, `hv round escalate check` | puts a question to the maintainer on the issue or PR thread and reads the answer |
| Merge | `hv worker gate <slot> --base <branch>` | verifies on the merged tree, merges on a pass; a [merge approval](#merge-approval) policy can require a human first |
| Clean | `hv reap` | lists, then with `--apply` removes, what no live slot owns; never kills a running agent |
| End | `hv round wind-down` | re-verifies the base, parks every slot, releases the lease |

Each verb's arguments, data and exit codes are in `docs/design/5.0-verb-contract.md`. Every verb
takes `--json` for a machine-readable envelope.

## Starting a round

`hv round start` takes the orchestrator lease, provisions the roster slots and lists the
candidates; it starts no agent.

```sh
hv round start --slots 3                    # scope from round.scope (default milestone)
hv round start --scope slate --items 12,13  # only these issues
hv round candidates                         # re-read the board with readiness checks
```

- **One orchestrator per repo.** A second `start` is refused (exit 4) and names the holder. A lease
  whose holder is gone is stale: `hv round reconcile` reports it and `hv round start` reclaims it.
  How the lease is stored and who counts as the holder: [lease internals](#internals).
- **Slots** are the first `--slots` names of `round.roster` (default `ben`, `dana`, `nia`, `kit`),
  each `.worktrees/<agent>` on `park/<agent>`. Slots are provisioned once and reused; a healthy
  existing slot is left alone. The worktrees live in the project root under `.worktrees/`, which
  `hv init` adds to `.gitignore`.
- **Scope** is which issues the round may take: `slate` (only `--items`), `milestone` (the open
  items of the active milestones) or `next` (the same, then the next planned milestone whose
  dependencies shipped). Assign refuses anything outside it. See
  [round keys](configuration.md#round-keys).

### Picking issues

Candidates carry three checks:

- `criteria`: acceptance criteria, or a design or plan note.
- `dependencies`: every `## Depends on` reference is closed. One that cannot be looked up fails the
  check, so fix the issue text.
- `overlap`: no shared file with an in-flight slot, from a `## Files` section or the paths the issue
  text names plus the slot's real changes.

The overlap check cannot see files an issue will create, paths nobody wrote down, two issues editing
the same function, generated files every issue touches (list those in `round.sharedPaths`), renames,
or another machine's round. Read two issues' bodies before you run them side by side.

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

- **Tier.** `--tier light|standard|heavy` picks the worker's model tier (default `round.tier`); a
  tier above the default needs `--tier-reason`. The tier and its model are recorded on the slot,
  shown by `hv round status`, and named in the brief with the tier table for the worker's own
  subagents. See [round keys](configuration.md#round-keys).
- **Kind.** `--kind codex` starts a Codex worker instead of a Claude one; see
  [Codex workers](codex-workers.md).
- **Overlap.** `--accept-overlap` skips the file-overlap check only. Say which PR merges first in
  the second worker's brief.
- **Failure.** A failure before dispatch undoes the claim and state; one at or after dispatch keeps
  them, and repeating the call resumes.

## Waiting on workers

`hv round wait [<slot>...] [--timeout <s>]` blocks until a worker needs attention and prints
the slot and its state as JSON, so the orchestrator never polls in its own context. It
classifies with the same rules as `hv worker poll` (sentinels, `limited`, `dead`, then the
host's status) and writes nothing. With no slot named it watches every slot that has a
session and whose recorded state is not `idle`; `hv worker dispatch` arms a slot.

- **herdr**: pinned to **0.9.x** (built against 0.9.3, socket protocol 22); another minor
  exits 5. One `events.subscribe` over `HERDR_SOCKET_PATH` carries a
  `pane.agent_status_changed` subscription per watched pane, so N slots cost one
  connection.
- **tmux**: no event stream and no agent status, so the verb re-captures the panes every
  `--settle` seconds (default 5) inside its own process.
- **Timeout** exits 1 with `data.timedOut: true` and every slot's state; it is an answer,
  not a fault. `--timeout` defaults to 0, which waits indefinitely.
- **Long waits in Claude Code** hit the Bash tool's timeout; see [internals](#internals).

## Asking the maintainer

A worker or the orchestrator that needs a human decision does not guess. `hv round escalate send`
posts the question on the issue or PR thread and raises a host notification; `hv round escalate check`
reads the answers back.

```sh
hv round escalate send 59 --slot ben --title "Keep the old flag?" --body-file question.md
hv round escalate send 61 --pr --title "Merge approval: PR #61" --body-file ask.md
hv round escalate check
```

An escalation has a deadline when you pass `--timeout <s>`; past it the entry counts as timed out.
A slot waiting on an open escalation is never reported `stalled`. Under solo mode the comment is the
only channel, because there is no host to notify.

## Merge approval

`hv worker gate <slot> --base <branch>` is the one merge path in a round. It checks the branch is
fresh, the PR is the worker's and provenance holds, then re-runs
`refactor.verifyCommands` on the merged tree and merges on a pass.

Whether a human also has to say yes is `ship.mergeApproval`:

| Value | Behavior |
|---|---|
| `none` (default) | The gate merges once its own checks pass. |
| `all` | Every merge needs a human. |
| `paths` | Only a merge that changes a file matching `ship.mergeApprovalPaths` does. |

```sh
hv config set ship.mergeApproval paths
hv config set ship.mergeApprovalPaths '["migrations", "*.lock"]'
```

When the policy covers a merge and no approval is on record, the gate exits 4 and merges nothing
(`verdict: approval-required`, with the matching files for `paths`). There are two ways to clear it:

- **Ask on the thread.** Add `--escalate`: the gate posts the request on the PR (or on the slot's
  issue when it has no PR) and exits 4 with the escalation id in `data`. Keep working other slots. Run
  `hv round escalate check`; once the reply is in, re-run the gate with `--approval <id>`. A reply
  approves when its first word is `approve`, `approved`, `yes` or `lgtm`, or its first two are `ship it`.
  Anything else holds the merge (`approval declined`) and the slot waits for you.
- **Answer at the keyboard.** Re-run with `--confirm --confirm-note "<the answer, quoted>"`.

`--approval`, `--escalate` and `--confirm` are mutually exclusive. An approval belongs to the thread,
not to a commit: pushes after the answer are covered, though freshness and provenance are re-checked
every time. Each approval is appended to `.hv/gate-audit.jsonl`. This policy holds at every
`autonomy.level`; see [manual gates](../../references/manual-gates.md) and
[configuration](configuration.md#shipmergeapproval-and-shipmergeapprovalpaths).

`hv worker gate <slot> --check-only` judges freshness, PR identity and provenance and merges nothing.

## Moving an issue that is assigned

```sh
hv round return ben --reason "wrong premise" --note-file next.md   # the worker's own verb
hv round transfer 59 --to dana --note-file next.md                 # orchestrator: to a slot
hv round transfer 59 --to human                                    # orchestrator: to the human
hv round reclaim ben                                               # orchestrator: dead or stalled slot
```

All three free the slot the same way: dirty paths are committed by name as
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
  `hv reap` reclaims `dead` slots only, never `stalled` ones: a worker in a long test run makes no
  commits and looks stalled, and an unattended `reap --apply` would kill it.

`hv round status` lists the round's slots with host, PR and drift. `hv round reconcile` reports
drift between the registry, the host, git and the forge, including `stalled` (never repaired),
`lease-stale` and `claim-mismatch`; `--apply` makes the safe repairs, and never edits the tracker.

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
`drift` count says what `hv round reconcile` and `hv reap` still have to do. After a round, run
`hv reap` ([doctor and reap](doctor-and-reap.md)).

## Solo mode

`hv round start` resolves the round's host once and records it in `.hv/workers.json`. With
`work.dispatch` unset or `subagent` it is herdr inside a herdr pane (`HERDR_ENV=1`), tmux
inside tmux (`TMUX` set), and otherwise **solo**. An explicit `herdr` or `tmux` is used as
set and fails when unavailable; solo is never a fallback from it.

Under solo, each worker is a Claude `Agent` subagent the orchestrator launches in the slot's
`.worktrees/<agent>` checkout. `hv round assign` returns the brief and the worktree instead
of starting a pane, `hv round report <slot> --state ...` records what the subagent said,
and `hv round wait` reads the registry without blocking. The pane verbs (`hv worker
dispatch`, `hv worker poll`, `hv worker session`) refuse. The registry holds what tab mode writes (minus the
pane fields), so `hv round reconcile`, the gate and the merge policy work unchanged.

**Every solo worker shares the orchestrator's session limit.** The subagents run on the
orchestrator's own account, rate window and context, so one usage limit stops every
worker and the orchestrator together, and every result lands in the orchestrator's
context. Keep solo rounds small (two or three slots) and the results short. Solo runs
Claude workers only: a Codex subagent cannot be given a working directory.

## Maintainer answers typed into a pane

A worker's question reaches you on the thread or in its pane. Prefix a direct answer with `m:` to make
it citable without a confirmation round-trip. The prefix is imitable, so a prefixed line that
contradicts the last signed orchestrator message still gets one confirmation.

## Internals

**The lease.** It is `<git-common-dir>/hv/round-lease.json`, so every worktree of the repo shares it.
The holder is the nearest non-shell ancestor of `hv` (in Claude Code, the `claude` process) plus its
start time. Pass `--holder-pid` where that cannot be read. A lease whose holder is gone is stale.

**Long waits in Claude Code.** The Bash tool kills a command at its `timeout`, which defaults to 2
minutes (`BASH_DEFAULT_TIMEOUT_MS`) and is capped at 10 minutes (`BASH_MAX_TIMEOUT_MS`). Either:

- raise the cap in `settings.json` under `env` (for example `"BASH_MAX_TIMEOUT_MS": "3600000"`) and
  pass a matching `timeout` on the Bash call; or
- loop on a finite `hv round wait --timeout` shorter than the cap.

## See also

- [Unattended rounds](unattended-rounds.md): hooks, keepalive, usage limits and account switching.
- [Doctor and reap](doctor-and-reap.md): the preflight checks and what cleanup removes.
- [Codex workers](codex-workers.md): `--kind codex`.
- [Parallel work](parallel-work.md): several `/hv-work` sessions without an orchestrator.
- [Autonomy levels](autonomy.md): how far skills chain on their own, a different axis from `round.scope`.
- [Contributing: rounds](../contributing/rounds.md): this repo's gate, repo rules and roster.
