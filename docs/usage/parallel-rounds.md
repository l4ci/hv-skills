# Parallel rounds

A round is one orchestrator session plus two to four workers, each a standing agent in
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
`test/runner.sh`, never executable alone. New sections take the number the dispatch
assigns; `50` and `51` are claimed by the current round.

There are no servers and no ports in this repo. The full suite is cheap enough that the
worker gate and the orchestrator's merge gate are the same commands.

## Repo rules that bind workers

- Edit canonical sources only: `bin/`, `hv-*/SKILL.md`, `references/`, `docs/`, `test/`.
  `.hv/bin/` is a gitignored mirror; never edit it, never commit it.
- Never hand-edit tracked `.hv/` content. The backlog row for your issue is updated by the
  orchestrator at merge time.
- Before touching a helper, pull the matching `.hv/KNOWLEDGE.md` topics with
  `.hv/bin/hv-knowledge-query "<exact ## heading>"` (if `.hv/bin` is missing in your
  worktree, run `bin/hv-knowledge-query`). The topics that bite most: *Architecture: Helper
  conventions & invariants*, *Architecture: Module extraction & migration safety*, *Build &
  Tooling: Smoke testing*.
- New `bin/` files need `chmod +x`, the `hv-preamble.sh` sourcing line, and a header comment
  sharing a key term with the SKILL.md that calls them (smoke section 29 checks this).
- Config keys are documented in five places at once: `docs/reference/config-options.md`,
  `docs/usage/configuration.md`, `hv-config/SKILL.md`, `hv-init/SKILL.md`,
  `bin/hv-config-schema-check`. Touch only the lines about your key; a sibling may be adding
  another key in the same files.
- Stage explicit paths. Commit messages: imperative subject under 72 chars, body says why,
  no `Co-Authored-By` trailer.
- The PR body carries an `## Approvals` section citing the channel of every decision you
  acted on, and labels your own calls as unratified. Reference the issue so it closes on
  merge, unless the PR is a partial slice.

## Roster

Slots are provisioned once and reused. Workspace ids are re-derived from
`herdr workspace list` at the start of each round; the label is the handle.

| name | kind | worktree | parking branch | account (`CLAUDE_CONFIG_DIR`) |
|---|---|---|---|---|
| ben  | claude | `~/.herdr/worktrees/hv-skills/ben`  | `park/ben`  | `/home/vo/.claude-work` |
| dana | claude | `~/.herdr/worktrees/hv-skills/dana` | `park/dana` | `/home/vo/.claude-personal` |
| nia  | claude | `~/.herdr/worktrees/hv-skills/nia`  | `park/nia`  | `/home/vo/.claude-work` |
| kit  | claude | `~/.herdr/worktrees/hv-skills/kit`  | `park/kit`  | `/home/vo/.claude-personal` |

Model per dispatch is the orchestrator's call (`-- --model <m>` after `agent start`);
default Sonnet, Opus for multi-helper features.

## Maintainer answers typed into a pane

Prefix a direct answer with `m:` to make it citable without a confirmation round-trip. The
prefix is imitable, so a prefixed line that contradicts the last signed orchestrator
message still gets one confirmation.
