# Three-mode skill shape

Used by `/hv-ship` (Docs Mode, accessed via `--docs`) and `/hv-qa` — the pair of patterns that maintain a curated artifact (public user guide vs. per-target QA strategy) over the project's lifetime through three modes: a one-time scaffold, incremental updates or executions, and on-demand reorganization.

The pair shares the **mode skeleton** but diverges on every axis where the artifact's audience and lifecycle dictate different defaults. Future three-mode patterns (a hypothetical `/hv-architecture` or `/hv-changelog` would fit) should match the skeleton and choose deliberately from {public/internal, gated/auto, scaffolded/always-on} — not invent a fourth mode shape.

## The skeleton

Every three-mode skill in this family has:

1. **First-run mode** — interactive scaffold of the canonical artifact. Skill detects an empty/missing target (`<docs.path>/` absent or empty; `.hv/qa/<target>.md` missing), inspects the project to form a hypothesis, proposes a structure, and writes only after explicit user approval (`AskUserQuestion` with a `(Recommended)` option). Never auto-scaffolds.
2. **After-work / run mode** — for Docs Mode, auto-invoked from `/hv-work` (and `/hv-ship`) post-cycle when the cycle's diff touches user-facing surface; reads what changed, maps changes to entries in the artifact, and either proposes edits behind an approval gate or writes them directly. For `/hv-qa`, `run` mode executes the strategy declared in `.hv/qa/<target>.md` and emits a verdict; it does not edit the artifact itself.
3. **Audit/restructure mode** — interactive on-demand reorganization. Surfaces staleness, duplicates, broken commands, and dead strategies; proposes merges, archives, or fixes; applies only on user confirmation.

Both modes regenerate a managed CLAUDE.md block via an index helper after writing, so read-side skills consult an always-on summary.

## Intentional divergences

The two current implementations diverge by design on every operational axis:

| Aspect | Docs Mode (`/hv-ship --docs`) | `/hv-qa` |
|---|---|---|
| Artifact root | `<docs.path>/` — typically `docs/` at repo root | `.hv/qa/<target>.md` — per-target strategy files (umbrella: `<target>` is a registered repo name; single-repo: user-named surface like `web`, `api`, `cli`) |
| Audience | end users (humans) | AI runners + contributors triaging findings |
| Mode-3 name | `restructure` (audit + reorganize the IA) | `restructure` (re-probe surfaces, retire dead strategies, fix broken commands) |
| Mode-2 nature | edits the artifact (after-work) | executes against the artifact (`run` — emits a verdict, does not edit) |
| After-work approval gate | propose-mode by default (`docs.autoCreate: false`); auto-write opt-in | not applicable — `run` reads strategy, executes, scores; no artifact edits |
| Trigger gate | post-cycle trigger condition — see `references/post-cycle-trigger-gate.md` | gated by `ship.qa: true` from `/hv-ship`; also runs on demand from the user |
| First-run opt-in for downstream automation | flips `docs.afterWork: true` on scaffold approval | opt-in via `ship.qa: true` and `qa.afterWork: true` |
| Authoring tier | Tier S (banner preamble, `TaskCreate` phase list, integer Step headers) | Tier S (banner preamble, mode-bracketed step structure) |
| Commit ownership | Docs Mode: own commit (`docs:` prefix) when run inline from `/hv-ship` Step 8.6 or manually via `/hv-ship --docs` | no commits — `/hv-qa` is read-only on the codebase |

These divergences are **not bugs to file**. The artifact's audience determines the gate strength (public docs need user approval per batch; QA strategy files are AI-runner-facing); the artifact's lifecycle determines whether mode 2 edits or executes; the authoring tier is a deliberate Tier S call codified in `references/authoring-conventions.md`.

## When the skeleton applies (and when it doesn't)

A new skill belongs in this family when its purpose is **continuous curation of a single artifact across the project's lifetime**, not single-shot transformation. Litmus:

- The artifact has a first-time-empty state that needs interactive scaffolding (rules out skills that always have a starting corpus).
- The artifact accumulates entries over the cycle history, not from a one-time import.
- The artifact periodically needs maintenance (stale entries, duplicates, broken links) — not just "append-only growth".

Skills that import / generate / one-shot transform (e.g., `/hv-release` cuts a tag; `/hv-spike` runs a single experiment) don't fit even if they touch persistent files.

## See also

- `references/post-cycle-trigger-gate.md` — the shared `2+/5+/hard-bug` trigger used by Docs Mode after-work (and by `/hv-work` and `/hv-ship` for the post-cycle `/hv-learn` and `/hv-ship --docs` dispatches).
- `references/authoring-conventions.md` — the Tier S/C distinction that explains the authoring tier picks above.
- `references/persistence-skills.md` — the persistence duo (`/hv-learn` for topic bullets and `--term` Glossary entries, plus `/hv-decide`) shares a different spine. Persistence skills capture one entry at a time; three-mode skills curate a body of entries over time. The two families don't overlap.
