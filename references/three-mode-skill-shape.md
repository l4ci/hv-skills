# Three-mode skill shape

Used by `/hv-docs` and `/hv-map` — the pair of skills that maintain a curated artifact (public user guide vs. internal subsystem map) over the project's lifetime through three modes: a one-time scaffold, incremental updates after work cycles, and on-demand reorganization.

The pair shares the **mode skeleton** but diverges on every axis where the artifact's audience and lifecycle dictate different defaults. Future three-mode skills (a hypothetical `/hv-architecture` or `/hv-changelog` would fit) should match the skeleton and choose deliberately from {public/internal, gated/auto, scaffolded/always-on} — not invent a fourth mode shape.

## The skeleton

Every three-mode skill in this family has:

1. **First-run mode** — interactive scaffold of the canonical artifact. Skill detects an empty/missing target (`<docs.path>/` absent or empty; `.hv/map/` empty), inspects the project to form a hypothesis, proposes a structure, and writes only after explicit user approval (`AskUserQuestion` with a `(Recommended)` option). Never auto-scaffolds.
2. **After-work mode** — auto-invoked from `/hv-work` (and possibly `/hv-debug`, `/hv-go`, `/hv-ship`) post-cycle. Reads what changed in the cycle, maps changes to entries in the artifact, and either proposes edits behind an approval gate or writes them directly — the gate strength is the design pick (see divergences).
3. **Audit/restructure mode** — interactive on-demand reorganization. Surfaces staleness, duplicates, and broken references, proposes merges/archives/fixes, applies only on user confirmation. Mode-name varies (`restructure` vs `consolidate`) — keep the name that fits the artifact's domain rather than forcing alignment.

All three modes regenerate a managed CLAUDE.md block via an index helper after writing, so read-side skills (the orchestrators) consult an always-on summary.

## Intentional divergences

The two current implementations diverge by design on every operational axis:

| Aspect | `/hv-docs` | `/hv-map` |
|---|---|---|
| Artifact root | `<docs.path>/` — typically `docs/` at repo root | `.hv/map/` — internal, gitignored |
| Audience | end users (humans) | AI assistants + contributors curious about subsystems |
| Mode-3 name | `restructure` (audit + reorganize the IA) | `consolidate` (merge stale/duplicate entries) |
| After-work approval gate | propose-mode by default (`docs.autoCreate: false`); auto-write opt-in | auto-write into the cycle's commit |
| After-work trigger gate | post-cycle trigger condition (2+ items / ≥5 files / hard bug) — see `references/post-cycle-trigger-gate.md` | none — runs whenever the cycle's commits touched files in a known subsystem |
| First-run opt-in for after-work | flips `docs.afterWork: true` on scaffold approval | always on (no flag) |
| Authoring tier | Tier S (banner preamble, `TaskCreate` phase list, integer Step headers) | Tier C (terse — inline mode-numbered lists, no banner, no `TaskCreate`) — see `references/authoring-conventions.md` *"Forbids: Adding the block to single-phase or trivial skills (Tier C)"* |
| Commit ownership | own commit (`docs:` prefix) | ride-along with the cycle's final commit |

These divergences are **not bugs to file**. The artifact's audience determines the gate strength (public docs need user approval per batch; internal maps don't); the artifact's lifecycle determines the trigger (docs respond to user-facing surface changes; maps respond to any touched file in a subsystem); the authoring tier is a deliberate Tier S vs. Tier C call codified in `references/authoring-conventions.md`.

## When the skeleton applies (and when it doesn't)

A new skill belongs in this family when its purpose is **continuous curation of a single artifact across the project's lifetime**, not single-shot transformation. Litmus:

- The artifact has a first-time-empty state that needs interactive scaffolding (rules out skills that always have a starting corpus).
- The artifact accumulates entries over the cycle history, not from a one-time import.
- The artifact periodically needs maintenance (stale entries, duplicates, broken links) — not just "append-only growth".

Skills that import / generate / one-shot transform (e.g., `/hv-release` cuts a tag; `/hv-spike` runs a single experiment) don't fit even if they touch persistent files.

## See also

- `references/post-cycle-trigger-gate.md` — the shared `2+/5+/hard-bug` trigger used by `/hv-docs` after-work (and by `/hv-work` and `/hv-ship` for the post-cycle `/hv-learn` and `/hv-docs` dispatches).
- `references/authoring-conventions.md` — the Tier S/C distinction that explains why `/hv-map` is terse and `/hv-docs` is verbose.
- `references/persistence-skills.md` — the persistence trio (`/hv-context`, `/hv-learn`, `/hv-decide`) shares a different spine. Persistence skills capture one entry at a time; three-mode skills curate a body of entries over time. The two families don't overlap.
