# Decisions

Boundary decisions that shape this project. Each entry is a commitment, not a preference — re-read before proposing changes that touch its area.

Format per entry: **the decision**, *why*, then **forbids** / **permits** so the line is unambiguous when applied to a concrete change.

---

## Skills are self-contained

Every skill carries its own rules inline. There is no central contract or reference file that skills point to.

*Why.* `GUIDE.md` was tried as a contributor-internals contract and removed in `[T04]` — every cross-reference into it was already mirrored inline at the call site, so the file was vestigial pointer-chasing. Centralized contracts also rot: the rule says one thing, the inlined copy says another, and readers split on which is authoritative.

**Forbids.** A new shared `*.md` at repo root that documents rules consumed by 2+ skills. Re-introducing `See GUIDE.md § X` style cross-refs. Asking a contributor to chase a link to find what a skill actually does.

**Permits.** Repeating the same imperative rule verbatim in N skills (redundancy is cheaper than scattered authority). A shared file *only* when N≥3 skills need the same long rule and the rule is too long to repeat — and even then, prefer inlining.

## docs/ is consumer-facing only

Everything under `docs/` is written for people who *use* hv-skills. Contributor and contract content lives in the skill that owns it (each `hv-*/SKILL.md`), not in a parallel reference file at repo root.

*Why.* Mixing audiences in one tree confuses both — consumers wade through internals they don't need, contributors find the actual rule has been softened for non-contributors. Splitting by audience keeps each surface coherent.

**Forbids.** Internals or skill-authoring guidance under `docs/`. A `docs/contributing/` subtree. Cross-refs from a `docs/` page to a contributor file.

**Permits.** `docs/reference/` for user-callable surfaces (CLI helpers, slash-command index, `.hv/` folder layout). Cross-refs from `docs/` to other `docs/` pages or to `README.md`.

## Git is the source of truth; status.json is a cache

`.hv/status.json` records active work streams, but git (`git branch`, `git worktree list`, `git log`) is authoritative. When the two disagree, git wins.

*Why.* Sessions crash, terminals close, manual `git` operations happen outside any skill. A persistent cache that claims authority would lock the project into stale state. Reconciliation against git on every read keeps the workflow self-healing.

**Forbids.** Skills that act on `status.json` without first reconciling against git. Helpers that mutate `status.json` from a stale read. Treating a missing branch as "still active" because the JSON says so.

**Permits.** `status.json` as a fast-path index — `hv-reconcile` validates and auto-cleans on every `/hv-next` invocation, so reads can trust the cache *after* reconciliation.

## Data files are never overwritten by /hv-init

Re-running `/hv-init` on an existing project refreshes helpers in `.hv/bin/` but never overwrites `TODO.md`, `KNOWLEDGE.md`, `MILESTONES.md`, `counters.json`, `status.json`, or `config.json`. Schema migrations (the STALE path) ask only for *missing* keys and merge the answer into the existing file.

*Why.* `/hv-init` runs again on every plugin upgrade. If it overwrote data, every upgrade would silently destroy work. The asymmetry (helpers refresh, data persists) is what makes upgrades safe.

**Forbids.** A migration that re-prompts for keys the user already answered. A bootstrap step that truncates a data file because the schema changed. Replacing `config.json` wholesale on a STALE detection.

**Permits.** Adding new helpers to `.hv/bin/` without asking. Migrating new schema keys via the STALE path, asking only for what's genuinely new.

## Atomic per-task commits

Every `[B##]`, `[F##]`, or `[T##]` resolves in exactly one commit. `/hv-work` dispatches one worker per task; the worker commits itself with a message naming the ID. Orchestrator verifies the commit, then moves on.

*Why.* Atomic commits give clean reverts, clean review boundaries, and a one-to-one mapping between backlog and history. Bundled commits hide the work and make later forensics impossible.

**Forbids.** A single commit covering 2+ unrelated TODO entries. "Cleanup" or "misc" commits that don't reference an ID. Squashing per-task commits at merge.

**Permits.** A `chore:` or `refactor:` commit that touches multiple files but addresses a *single* concern (the T02 GUIDE.md trim was one commit; the T04 GUIDE.md removal was one commit). Sweep commits for tool-generated siblings (Godot `.gd.uid`, etc.) outside the per-task model.

## .hv/ is gitignored by default

`/hv-init` adds `.hv/` to `.gitignore` automatically. The backlog is local-to-machine. Sharing state with collaborators is an explicit, opt-in commit, not the default.

*Why.* Two reasons. First, the backlog often contains in-flight thinking, sensitive context, or hypotheses you wouldn't want in PR diffs. Second, syncing `.hv/` across machines races (two `hv-status-add` calls concurrently mutating the same JSON) — and there's no need for it; the canonical state is git.

**Forbids.** Committing `.hv/` by default. A skill that assumes `.hv/` is checked in. A teamwork pattern that requires multiple humans to share `status.json`.

**Permits.** A solo developer choosing to commit `.hv/` deliberately to sync across their own machines. Per-project overrides via `.gitignore` if a team genuinely wants shared milestones (rare, ergonomically painful).

## Milestones are excluded from time-based archival

`hv-archive-old`, `hv-complete`, and `hv-reconcile` ignore `.hv/milestones/`. Milestones move through `planned` / `active` / `shipped` / `archived` via explicit `hv-vision-status` calls, never by elapsed time.

*Why.* Items and milestones have different lifecycles. An item is short-lived (capture → work → ship → archive); a milestone is strategic and survives across many items, branches, and sessions. Unifying their archival rules would either prematurely retire active milestones or leave dead items uncollected.

**Forbids.** A future helper that "archives old milestones" by date. A `## Completed` flow for milestones. Re-using `hv-archive-old` to sweep `.hv/milestones/`.

**Permits.** Manual retirement (`hv-vision-status MNN archived` for abandoned work, `hv-vision-status MNN shipped` for completed work). Querying `hv-vision-active` to scope `/hv-next` to in-flight strategy.
