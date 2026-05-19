# Persistence-trio umbrella scoping

Governs how KNOWLEDGE.md, DECISIONS.md, and the Glossary topic behave in umbrella projects (a root repo containing multiple registered sub-repos). Shipped in **F21**. Hard boundary set in `.hv/DECISIONS.md` under *"Persistence-trio scoping under umbrella mode"* — this reference describes the model; it does not re-decide it.

## The model

**KNOWLEDGE.md — hybrid.** Two files coexist:

- `.hv/KNOWLEDGE.md` — umbrella file. Cross-repo learnings and umbrella Glossary terms. Always present.
- `.hv/knowledge/<name>/KNOWLEDGE.md` — per-sub-repo file. Repo-local learnings and per-sub-repo Glossary terms. Created on first write or by `/hv-init` during umbrella setup.

Learnings that apply across repos land in the umbrella file. Learnings specific to one repo (e.g., *"the `web` sub-repo's Postgres pool config differs from `api`'s"*) land in that repo's file.

**DECISIONS.md — umbrella-only.** A single `.hv/DECISIONS.md` at the umbrella root. Never split per-sub-repo. Hard boundaries are inherently cross-repo; a forbid in one repo applies everywhere. If a "decision" is truly repo-local, it is a learning — capture it with `/hv-learn` instead.

**Glossary — follows KNOWLEDGE's hybrid scoping.** The `## Glossary` topic in each KNOWLEDGE.md file holds term entries for that file's scope. Umbrella Glossary = cross-repo vocabulary; per-sub-repo Glossary = repo-local terminology. Glossary is **special-cased to skip the F03 tier lifecycle** — terms are canonical from the moment they are written, not probationary.

## Scope resolution

Resolution priority (highest first):

1. **`--repo umbrella|<name>`** explicit flag — always wins.
2. **cwd auto-resolve** — if the working directory is inside a registered sub-repo, that sub-repo is selected. At the umbrella root, skills ask once via `AskUserQuestion` (umbrella-shared vs. a specific sub-repo).
3. **Single-repo projects** — always resolve to `umbrella`; behavior is byte-identical to pre-F21.

The shared resolver is `bin/hv-knowledge-scope.sh` (`hv_resolve_knowledge_scope`). The `hvlib` wrappers are `resolve_knowledge_target(repo)` and `resolve_tier_sidecar(repo)`.

## Reader semantics

`hv-knowledge-query` and `hv-glossary-read` are **hybrid readers** when the resolved scope is a sub-repo: they read both `.hv/KNOWLEDGE.md` (umbrella) and `.hv/knowledge/<name>/KNOWLEDGE.md` (sub-repo), emitting a `> from: <path>` provenance line before each block so output stays traceable. When the scope is umbrella (root or explicit `--repo umbrella`), only the umbrella file is read.

`hv-knowledge-amend` refuses an ambiguous `(topic, fragment)` hit that matches entries in both the umbrella and a sub-repo file. The caller must pass `--repo` to disambiguate.

## Tier sidecars

Each KNOWLEDGE.md file has its own tier sidecar:

- `.hv/knowledge-tier.json` — umbrella
- `.hv/knowledge/<name>/knowledge-tier.json` — per sub-repo

Each sidecar tracks only the bullets in its own file. The Glossary topic in either file is exempt from tier tracking (terms are canonical, not probationary).

## CLAUDE.md managed block

Each sub-repo's CLAUDE.md receives a `hv-managed-block knowledge --repo <name>` block listing **umbrella topics ∪ that sub-repo's own topics**. A reader inside the sub-repo therefore sees the full relevant topic index without needing to open umbrella-root files.

Umbrella-root CLAUDE.md (if present) lists umbrella topics only — per-sub-repo topics stay in their own CLAUDE.md blocks.

Single-repo projects: the managed block is unchanged from pre-F21 (umbrella file only).

## Migration

`/hv-migrate v4` migrates legacy per-sub-repo context files:

- Each `.hv/contexts/<name>/CONTEXT.md` → written into `.hv/knowledge/<name>/KNOWLEDGE.md`'s Glossary via `hv-glossary-import --repo <name>`.
- Umbrella-root `.hv/CONTEXT.md` → written into the umbrella KNOWLEDGE.md's Glossary.
- Original files backed up under `.hv/migrate-backup/` before removal.
- Existing umbrella `.hv/KNOWLEDGE.md` content is left untouched — those learnings were already umbrella-shared.

## Governed by

`.hv/DECISIONS.md` — *"Persistence-trio scoping under umbrella mode"* (Architecture). That entry records the forbids and permits; this file describes the shipped implementation. Any change to the scoping model requires revisiting that decision first.
