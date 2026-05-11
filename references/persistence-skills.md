# Persistence skills

Used by `/hv-context`, `/hv-learn`, and `/hv-decide` — the trio that writes durable project state into `.hv/<FILE>.md` and re-renders a managed block in `CLAUDE.md` so read-side skills (`/hv-work`, `/hv-debug`, `/hv-plan`, `/hv-refactor`, `/hv-review`, `/hv-vision`) can consult it.

The trio shares one **contract** but three **gate strengths**. New persistence skills should match the contract; their gate strength is a design pick, not a free-form decision.

## The contract

Every persistence skill in the trio:

1. **Preflights** via `.hv/bin/hv-preflight` (Step 1) — see `docs/reference/preflight.md`.
2. **Initializes a TaskCreate phase list** at the end of Step 1 — see `references/authoring-conventions.md` rule *"Surface multi-step skill progress with TaskCreate"*. Phase count and names are skill-specific; the boilerplate shell is shared.
3. **Identifies a candidate** (term / learning / decision) from arguments, conversation context, or a source artifact. The shape of this step is intentionally skill-local.
4. **Classifies into a section heading** — by topic (hv-learn, hv-decide) or by term name (hv-context). Topic-keyed skills share the alphabetical-with-pinning rule below.
5. **Merges via a writer helper** that owns insertion, deduplication, and the date stamp:
   - `/hv-context` → `bin/hv-context-add`
   - `/hv-learn` → `bin/hv-knowledge-merge`
   - `/hv-decide` → `Edit` directly on `.hv/DECISIONS.md` (no helper today)
6. **Regenerates the managed CLAUDE.md block** via an index helper. The block is the always-on signal to read-side skills:
   - `/hv-context` → `bin/hv-context-index` (run internally by `hv-context-add`)
   - `/hv-learn` → `bin/hv-knowledge-index`
   - `/hv-decide` → `bin/hv-decisions-index`
7. **Confirms via a compact block** — *"Captured `<artifact>` into `.hv/<FILE>.md`… Updated CLAUDE.md `<block>` block."* Match the shape; don't recap the plan.

The trio does **not** commit. `.hv/` is gitignored, so the only tracked write is `CLAUDE.md`; the trio leaves it as a working-tree diff and lets the caller (the user, or a parent `/hv-work` cycle) commit. Aligning here matters — the trio is dispatched in sequence under `autonomy.level: loop`, so a per-skill commit would fragment what should be one summary commit.

## Topic-classification rule (hv-learn ↔ hv-decide)

Both topic-keyed siblings share:

- **Reuse existing `## Topic` headings** when they fit. Create a new topic only if nothing fits.
- **Reuse topic names across the two files** where overlap exists (`Architecture`, `Testing`, `Build & Tooling`, etc.) so a single topic name maps to both `KNOWLEDGE.md` and `DECISIONS.md`.
- **Order new topics alphabetically**, with the exception that `Architecture` and `Build & Tooling` may be pinned near the top of either file.
- **Coarser is better than per-entry.** Don't mint a topic per bullet (`/hv-learn`) or per rule (`/hv-decide`).

`/hv-context` is term-keyed, not topic-keyed — this rule does not apply.

## Intentional divergences

The three gate strengths are by design. The active/passive distinction lives here:

| Aspect | `/hv-context` | `/hv-learn` | `/hv-decide` |
|---|---|---|---|
| Capture trigger | explicit signal at the call site | auto in `auto`/`loop`, nudge in `off` | always manual |
| Confirmation gate | conditional (only on existing-term conflict) | **none** — Step 4 explicitly auto-writes | **manual gate**, always |
| Verifier | none | Opus on by default (`learn.verify`) | none |
| Source-prefill flags | one-shot positional args | none | `--from-learning`, `--from-spike` |
| Public-artifact follow-ups | none | Step 8.5 (hv-skills issue), Step 8.6 (runlog) | none |
| Active vs passive | vocabulary (low-risk additive) | passive ("remember if relevant") | active commitment (forbids + permits) |

A future skill author looking at this table should read it as: **these are not bugs to file**. The gate-strength column encodes the project's policy on what costs the user *must* approve. `/hv-decide` always asks because writing a forbids/permits constrains future work; `/hv-learn` never asks because a passive bullet is cheap to amend; `/hv-context` only asks on conflict because adding a fresh term is additive.

If a new persistence skill needs a different gate, choose deliberately from {none, conditional, manual}; don't invent a fourth shape.

## What this reference does NOT cover

- **The user-facing distinction.** `docs/usage/context.md`, `docs/usage/learning.md`, and `docs/usage/decisions.md` explain the trio to users — vocabulary vs. gotchas vs. boundaries. This reference is for skill authors.
- **Manual gates inventory.** The list of always-manual sites across all skills (not just this trio) lives in `references/manual-gates.md`.
- **TaskCreate phase boilerplate.** The cross-cutting authoring rule lives in `references/authoring-conventions.md` rule *"Surface multi-step skill progress with TaskCreate"*.
- **Knowledge & decisions consult.** The read-side pattern (helpers, carrier semantics, parallelism) lives in `references/knowledge-consult.md`.
- **`/hv-context` target-file resolution in umbrella mode.** Skill-local; see `references/context-umbrella-scoping.md`.
