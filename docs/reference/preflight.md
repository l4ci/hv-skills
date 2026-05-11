# Preflight reference

Every skill calls `.hv/bin/hv-preflight` first. Here's what its exit codes mean and how skills should react.

## Exit codes

| Code | Meaning | User state | Skill should |
|------|---------|------------|--------------|
| `0`  | Clean — `.hv/` exists, all required data files and helpers are present and current. | Fully initialized. | Proceed silently. |
| `2`  | Uninitialized — `.hv/` is missing, or one of the required data files (see below) is absent. | Project has not opted into hv-skills yet. | Tell the user they need to run `/hv-init` first, then **stop**. Do not auto-init; installation requires user consent. |
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

Three skills have skill-specific exit-2 behavior; their preflight step omits exit-code prose because the variant is captured here.

| Skill | On exit `2` | On exit `3` |
|-------|------------|------------|
| `/hv-next` | Surface *"Nothing tracked yet — run `/hv-init` then `/hv-capture`."* and stop. | Refresh via `hv-init` (helpers may be needed for the read). |
| `/hv-pause` | Surface *"Nothing to pause — `/hv-init` the project first."* and stop. | Refresh via `hv-init`. |
| `/hv-config` | Invoke `hv-init` via the `Skill` tool, then stop — init writes the initial config interactively, so this skill has nothing to do afterward. | Refresh via `hv-init` and continue. |

Two more skills are structural variants:

- **`/hv-update`** checks `gh` is on `PATH` *before* preflight; the GitHub-release check is the primary purpose, and a missing `gh` should fail fast before touching `.hv/`.
- **`/hv-init`** is the bootstrapper itself; it doesn't run preflight.

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

Skill authors: see Variants table above before writing inline exit-2 prose in a SKILL.md — if the skill is a variant, the cite is enough.
