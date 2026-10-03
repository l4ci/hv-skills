# Project check reference

Skills no longer run a preflight step. Every `hv` verb that needs `.hv/` exits `3` when it cannot find one, so a skill that touches a project learns about a missing init from the verb itself. `hv init check` is the explicit check, for the few places that want one up front and for scripts.

## `hv init check`

```bash
hv init check
hv init check --json
```

| Exit | Meaning | What to do |
|------|---------|------------|
| `0` | `.hv/` and its core files are present. | Proceed. |
| `1` | Not initialized: `.hv/` or one of the core files is missing. `--json` lists every missing path in `data.missing`. | Tell the user to run `/hv-init`, then **stop**. Never auto-init: initialization needs the user's consent. |

`hv init check` acts on the working directory (after `-C`) with no walk-up, so it also runs where there is no `.hv/` yet.

Core files it checks under `.hv/`:

- `DECISIONS.md`
- `BACKLOG.md`
- `KNOWLEDGE.md`
- `MILESTONES.md`
- `counters.json`
- `config.json`
- `status.json`

Advisory findings come back as `warnings`, never as a failure: an umbrella flag that disagrees with the registry, and version drift between the project's stamped `hvSkills.version` and the installed binary (`hv version --drift` reports the same thing on its own).

## Missing `.hv/` from any other verb

Exit `3` (`resolution`), with a message naming the missing root. Skills surface it the same way as above: point the user at `/hv-init` and stop.

| Skill | When `.hv/` is missing |
|-------|------------------------|
| `/hv-next` | Surface *"Nothing tracked yet. Run `/hv-init` then `/hv-capture`."* and stop. |
| `/hv-pause` | Surface *"Nothing to pause. `/hv-init` the project first."* and stop. |
| `/hv-config` | Hand off to `/hv-init`, which writes the initial config interactively. |
| `/hv-update` | Not affected: it checks `gh` on `PATH`, then calls `hv update`, which runs without a project. |
| `/hv-init` | Is the bootstrapper itself; it runs `hv init`. |

All exit codes: [`hv` verb reference](cli-helpers.md#conventions).
