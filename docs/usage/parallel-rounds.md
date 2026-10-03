# Parallel rounds

A round is one orchestrator session plus two to five workers, each a standing agent in
its own git worktree and herdr workspace, each holding one GitHub issue at a time. Workers
implement, verify and open a PR; they never merge. The orchestrator assigns issues, relays
decisions, merges PRs and re-verifies on `main` after every merge.

The standing worker contract is the `orchestrate-herdr` skill's `references/worker.md`
(on this machine:
`/home/vo/.claude-work/plugins/synced/20a2b42b-2da4-4892-8aa3-286c686ead4d_db9298e1-7194-4cd2-a1b8-483e198e1e2b/stray/skills/orchestrate-herdr/references/worker.md`).
Read it in full before the issue. This file adds only what is specific to hv-skills.

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

Slots are provisioned once and reused. Every worktree lives in the project root under
`.worktrees/<agent>` (gitignored by `/hv-init`), so herdr groups the workspaces under the
project and `/hv-work`'s `hv worker pool` (`.worktrees/<slot>`) shares the same root.
Provision a slot with:

```sh
herdr worktree create --path .worktrees/<agent> ...   # from the project root
git worktree add .worktrees/<agent> park/<agent>      # or, without herdr
```

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
