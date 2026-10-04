# Project check reference

Skills no longer run a preflight step. Every `hv` verb that needs `.hv/` exits `3` when it cannot find one, so a skill that touches a project learns about a missing init from the verb itself. `hv init check` is the explicit check, for the few places that want one up front and for scripts. Before a [parallel round](../usage/parallel-rounds.md), `hv doctor` checks the machine instead of the project.

## `hv init check`

```bash
hv init check
hv init check --json
```

| Exit | Meaning | What to do |
|------|---------|------------|
| `0` | `.hv/` and its core files are present. | Proceed. |
| `1` | Not initialized: `.hv/` or one of the core files is missing. `--json` lists every missing path in `data.missing`. | Tell the user to run `hv init`, then **stop**. Never auto-init: initialization needs the user's consent. |

`hv init check` acts on the working directory (after `-C`) with no walk-up, so it also runs where there is no `.hv/` yet.

Core files it checks under `.hv/`:

- `DECISIONS.md`
- `BACKLOG.md`
- `KNOWLEDGE.md`
- `MILESTONES.md`
- `counters.json`
- `config.json`
- `status.json`

Advisory findings come back as `warnings`, never as a failure: an umbrella flag that disagrees with the registry, and version drift between the project's stamped `hv.version` (the old `hvSkills.version` is read as a fallback until `hv init` / `hv config fill` moves it) and the installed binary (`hv version --drift` reports the same thing on its own).

## `hv doctor`

`hv init check` asks whether the project is set up. `hv doctor` asks whether the machine can run a round: git, the terminal host, the tracker login, accounts, the orchestrator hooks, `hv` itself and Codex.

```bash
hv doctor
hv doctor --json
```

It is read-only, spends no usage quota, and runs without `.hv/` (it falls back to default config). Each check reports `pass`, `fail` or `skip`. A `fail` carries a `hint` with the one command or edit that fixes it, and `detail` says what was found (`herdr 0.8.2, need 0.9.x`).

| Exit | Meaning | What to do |
|------|---------|------------|
| `0` | Every check passed or was skipped. | Proceed. |
| `1` | At least one check failed. `--json` gives the same `data`, with `ok: false`. | Run each failed check's `hint`, then run `hv doctor` again. |

A missing tool is a failed check, never exit 5.

The checks, in the order they run:

| Check | Passes when | Skipped when |
|-------|-------------|--------------|
| `git` | git is on `PATH` and `.worktrees/` is gitignored | never |
| `host` | the host `work.dispatch` names is usable: herdr on `PATH` and 0.9.x, or tmux on `PATH` | `work.dispatch` is neither `herdr` nor `tmux` |
| `tracker` | `gh` or `glab` is on `PATH` and logged in for the project's provider | the project has no remote |
| `accounts` | every account in `work.accounts` has a `configDir` with a credentials file | no accounts configured |
| `hook` | herdr's agent integration is installed for each configured account (`herdr integration install claude`) | the host is not herdr, or no account is configured |
| `statusline` | the effective statusline runs `hv statusline dump` | the orchestrator hooks are not installed (opt-in) |
| `stop-hook` | a Stop and a SessionStart hook installed by `hv hook install` exist and their command resolves | the orchestrator hooks are not installed (opt-in) |
| `switch` | with `orchestrator.switchOnUsage` on: two or more accounts have a `configDir` and the Stop hook is installed | `orchestrator.switchOnUsage` is off |
| `skills` | every installed skills root (user and project, Claude and Codex) matches the binary's skill set, has no missing or edited files, and no `hv-skills@` plugin is still installed | no root has a `.hv-manifest.json` (run `hv skills install`) |
| `codex` | `codex` is 0.159.x, and each Codex slot home is logged in and has the herdr integration | `codex` is not on `PATH` and no slot has a home |

The two hook checks are opt-in. Until something `hv hook install` writes is present, they skip and do not fail a project that never installed the hooks. Once it is, a partial or broken install fails. `skills` follows the same rule: it skips until `hv skills install` has written a manifest.

See [unattended rounds](../usage/unattended-rounds.md) for the hooks and [parallel rounds](../usage/parallel-rounds.md) for what a round does after a clean `hv doctor`.

## Missing `.hv/` from any other verb

Exit `3` (`resolution`), with a message naming the missing root. Skills surface it the same way as above: point the user at `hv init` and stop.

| Skill or verb | When `.hv/` is missing |
|-------|------------------------|
| `/hv-work` (no argument) | Surface *"Nothing tracked yet. Run `hv init` then `/hv-capture`."* and stop. |
| `/hv-pause` | Surface *"Nothing to pause. Run `hv init` first."* and stop. |
| `hv update` | Not affected: it runs without a project. |
| `hv init` | Is the bootstrapper itself. |

All exit codes: [`hv` verb reference](cli-helpers.md#conventions).
