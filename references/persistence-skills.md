# Persistence skills

Used by `/hv-learn` and `/hv-decide` — the duo that writes durable project state into `.hv/<FILE>.md` and re-renders a managed block in `CLAUDE.md` so read-side skills (`/hv-work`, `/hv-debug`, `/hv-plan`, `/hv-refactor`, `/hv-review`, `/hv-vision`) can consult it.

`/hv-learn` carries two modes — passive learnings written as bullets under topic headings in `.hv/KNOWLEDGE.md`, and term entries written as nested-bullets under the pinned `## Glossary` topic of the same file (via the `--term <name>` flag). `/hv-context` was folded into `/hv-learn --term` in v4.0; both modes share the same writer-skill surface.

The two skills share one **contract** but different **gate strengths**. New persistence skills should match the contract; their gate strength is a design pick, not a free-form decision.

## The contract

Every persistence skill (and `/hv-learn`'s `--term` mode) follows:

1. **Initializes a TaskCreate phase list** at the start (Step 1; see `references/authoring-conventions.md` rule *"Surface multi-step skill progress with TaskCreate"*). Phase count and names are skill-specific; the boilerplate shell is shared.
2. **Identifies a candidate** (learning / term / decision) from arguments, conversation context, or a source artifact. The shape of this step is intentionally skill-local.
3. **Classifies into a section heading** — by topic for both `/hv-learn` topic bullets and `/hv-decide`; by term name for `/hv-learn --term` (the term entry lands under the fixed `## Glossary` topic). Topic-keyed branches share the alphabetical-with-pinning rule below.
4. **Merges via a writer verb** that owns insertion, deduplication, and the date stamp:
   - `/hv-learn` (topic bullets) → `hv knowledge add`
   - `/hv-learn --term` → `hv glossary write`
   - `/hv-decide` → `Edit` directly on `.hv/DECISIONS.md` (no verb today)
5. **Regenerates the managed CLAUDE.md block** (in `AGENTS.md` when that file exists) via `hv block`. The block is the always-on signal to read-side skills:
   - `/hv-learn` (both modes) → `hv block knowledge` (`--term` runs it internally via `hv glossary write`; Glossary surfaces as a topic name in the Knowledge index automatically)
   - `/hv-decide` → `hv block decisions`
6. **Confirms via a compact block** — *"Captured `<artifact>` into `.hv/<FILE>.md`… Updated CLAUDE.md `<block>` block."* Match the shape; don't recap the plan.

The duo does **not** commit. `.hv/KNOWLEDGE.md`, `.hv/DECISIONS.md`, and `CLAUDE.md` are all tracked under the partial-ignore model, so the duo leaves three working-tree diffs and lets the caller (the user, or a parent `/hv-work` cycle) commit them as one summary. Aligning here matters — the duo is dispatched in sequence under `autonomy.level: loop`, so a per-skill commit would fragment what should be one summary commit.

## Topic-classification rule (hv-learn topic bullets ↔ hv-decide)

Both topic-keyed branches share:

- **Reuse existing `## Topic` headings** when they fit. Create a new topic only if nothing fits.
- **Reuse topic names across the two files** where overlap exists (`Architecture`, `Testing`, `Build & Tooling`, etc.) so a single topic name maps to both `KNOWLEDGE.md` and `DECISIONS.md`.
- **Order new topics alphabetically**, with the exception that `Architecture`, `Build & Tooling`, and `Glossary` may be pinned near the top of `KNOWLEDGE.md`.
- **Coarser is better than per-entry.** Don't mint a topic per bullet (`/hv-learn`) or per rule (`/hv-decide`).

`/hv-learn --term` is term-keyed and always writes to the fixed `## Glossary` topic — the topic-classification rule does not apply.

## Intentional divergences

The gate strengths are by design. The active/passive distinction lives here:

| Aspect | `/hv-learn --term` | `/hv-learn` (topic bullet) | `/hv-decide` |
|---|---|---|---|
| Capture trigger | explicit `--term <name>` (or auto from definitional signals like *"by X I mean..."*) | auto in `auto`/`loop`, nudge in `off` | always manual |
| Confirmation gate | conditional (only on existing-term conflict — alias collision is the gate; same-name updates are silent) | **none** — Step 4 explicitly auto-writes | **manual gate**, always |
| Verifier | none | Opus on by default (`learn.verify`) | none |
| Source-prefill flags | `--def`, `--alias`, `--not`, `--touch` | none | `--from-learning`, `--from-spike` |
| Public-artifact follow-ups | none | Step 8.5 (hv-skills issue), Step 8.6 (runlog) | none |
| Active vs passive | vocabulary (low-risk additive) | passive ("remember if relevant") | active commitment (forbids + permits) |

A future skill author looking at this table should read it as: **these are not bugs to file**. The gate-strength column encodes the project's policy on what costs the user *must* approve. `/hv-decide` always asks because writing a forbids/permits constrains future work; `/hv-learn` topic bullets never ask because passive content is cheap to amend; `/hv-learn --term` only asks on alias collision because adding a fresh term is additive.

If a new persistence skill needs a different gate, choose deliberately from {none, conditional, manual}; don't invent a fourth shape.

## What this reference does NOT cover

- **The user-facing distinction.** `docs/usage/learning.md` and `docs/usage/decisions.md` explain the duo to users — terminology + gotchas vs. boundaries. This reference is for skill authors.
- **Manual gates inventory.** The list of always-manual sites across all skills (not just this duo) lives in `references/manual-gates.md`.
- **TaskCreate phase boilerplate.** The cross-cutting authoring rule lives in `references/authoring-conventions.md` rule *"Surface multi-step skill progress with TaskCreate"*.
- **Knowledge & decisions consult.** The read-side pattern (verbs, carrier semantics, parallelism) lives in `references/knowledge-consult.md`.
- **Umbrella-mode scoping.** The model is in *Umbrella scoping* below.

## Umbrella scoping

How KNOWLEDGE.md, DECISIONS.md and the Glossary behave in an umbrella project (a root repo with registered sub-repos). Shipped in **F21**. The hard boundary is `.hv/DECISIONS.md` *"Persistence-trio scoping under umbrella mode"* (Architecture); this section describes the model and does not re-decide it. Changing the model means revisiting that decision first.

**KNOWLEDGE.md is hybrid.** `.hv/KNOWLEDGE.md` (always present) holds cross-repo learnings and umbrella Glossary terms. `.hv/knowledge/<name>/KNOWLEDGE.md` (created on first write or by `/hv-init` umbrella setup) holds that sub-repo's learnings and Glossary terms. Learnings that apply across repos go in the umbrella file; one-repo learnings (*"`web`'s Postgres pool config differs from `api`'s"*) go in that repo's file.

**DECISIONS.md is umbrella-only.** One `.hv/DECISIONS.md` at the umbrella root, never split per sub-repo: hard boundaries are cross-repo. A truly repo-local "decision" is a learning; use `/hv-learn`.

**Glossary follows KNOWLEDGE's scoping.** The `## Glossary` topic in each file holds that scope's terms. Glossary skips the F03 tier lifecycle: terms are canonical when written, not probationary.

**Scope resolution**, highest priority first:

1. `--repo umbrella|<name>` always wins.
2. cwd inside a registered sub-repo selects that sub-repo. At the umbrella root, skills ask once via `AskUserQuestion` (umbrella-shared vs a specific sub-repo).
3. Single-repo projects always resolve to `umbrella`, byte-identical to pre-F21.

The scoped `hv knowledge` and `hv glossary` verbs resolve the target file and tier sidecar from the global `--repo` flag or the cwd.

**Readers are hybrid** when the scope is a sub-repo: `hv knowledge query` and `hv glossary read` read both the umbrella and the sub-repo file, with a `> from: <path>` provenance line before each block. At umbrella scope (root or `--repo umbrella`) only the umbrella file is read. `hv knowledge amend` refuses an ambiguous `(topic, fragment)` that matches entries in both files; pass `--repo` to disambiguate.

**Tier sidecars** are per file: `.hv/knowledge-tier.json` (umbrella) and `.hv/knowledge/<name>/knowledge-tier.json`, each tracking only its own bullets. Glossary is exempt in both.

**CLAUDE.md managed block.** A sub-repo's CLAUDE.md (or AGENTS.md when present) gets `hv block knowledge --repo <name>`, listing umbrella topics plus that sub-repo's own, so a reader in the sub-repo sees the full topic index. The umbrella-root file lists umbrella topics only. Single-repo projects are unchanged.

**Migration.** `/hv-migrate v4` writes each `.hv/contexts/<name>/CONTEXT.md` into `.hv/knowledge/<name>/KNOWLEDGE.md`'s Glossary via `hv glossary import --repo <name>`, and the umbrella-root `.hv/CONTEXT.md` into the umbrella Glossary. Originals are backed up under `.hv/migrate-backup/`. Existing umbrella KNOWLEDGE content is untouched.
