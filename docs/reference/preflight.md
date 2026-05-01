# Preflight reference

Every skill calls `.hv/bin/hv-preflight` first. Here's what its exit codes mean and how skills should react.

## Exit codes

| Code | Meaning | User state | Skill should |
|------|---------|------------|--------------|
| `0`  | Clean — `.hv/` exists, all required data files and helpers are present and current. | Fully initialized. | Proceed silently. |
| `2`  | Uninitialized — `.hv/` is missing, or one of the required data files (see below) is absent. | Project has not opted into hv-skills yet. | Tell the user they need to run `/hv-init` first, then **stop**. Do not auto-init — installation requires user consent. |
| `3`  | Stale install — `.hv/` exists, but one or more helper binaries under `.hv/bin/` are missing (e.g. plugin upgraded, helpers haven't been re-copied). | Project is initialized but its helpers are outdated. | Invoke `hv-init` via the `Skill` tool to refresh, then continue from where preflight ran. |

## Standard handling

Every default skill follows this pattern:

```bash
.hv/bin/hv-preflight
```

- exit `0` → continue silently
- exit `2` → surface the missing-init message and stop (the user has not opted in)
- exit `3` → invoke `hv-init` via the `Skill` tool, then resume the calling skill

## Variants

- **Observe-only skills** — `/hv-resume`, `/hv-pause`, `/hv-next`. These read state and route; they shouldn't auto-init for `2`. On exit `2`, surface a brief "nothing to show — `/hv-init` first" message and stop. On exit `3`, refresh via `hv-init` (helpers may be needed for the read).
- **`/hv-config`** — on exit `2`, the user clearly wants to configure the project, so invoke `hv-init` (which writes the initial config interactively) then stop. On exit `3`, refresh and continue.
- **`/hv-update`** — checks `gh` is on `PATH` *before* preflight; the GitHub-release check is the primary purpose, and a missing `gh` should fail fast before touching `.hv/`.
- **`/hv-init`** — the bootstrapper itself; it doesn't run preflight.

## What hv-preflight checks

Required data files under `.hv/`:

- `DECISIONS.md`
- `TODO.md`
- `KNOWLEDGE.md`
- `MILESTONES.md`
- `counters.json`
- `config.json`
- `status.json`

Required helpers under `.hv/bin/`: every `hv-*` script alongside `hv-preflight` in the source `bin/` (auto-discovered, minus `hv-preflight` itself), plus `hvlib.py`.

Source of truth: [`bin/hv-preflight`](../../bin/hv-preflight).
