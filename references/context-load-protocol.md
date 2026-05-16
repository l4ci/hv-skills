# Context-load protocol

Used by `/hv-work` (Step 4 for the normal flow, Preview Mode Step 2 for the peek), `/hv-plan` Step 3, and `/hv-vision` Step 2 — the silent context load that runs before the skill proposes anything to the user. The goal: read everything that informs the planned action in parallel, form a picture, then act.

## The canonical reads

Run as a checklist. Items are ordered by broadening scope (target item → plan → milestone → repo-wide). Skip an item when its precondition doesn't apply — that's not a failure, that's the protocol.

- **The target item entry** in `.hv/BACKLOG.md` (when a specific backlog ID is the target) and its overflow detail file at `.hv/<bugs|features|tasks>/<id>.md` if one exists.
- **The plan file** at `.hv/plans/<key>.md` if one exists for this work. Use:

  ```
  .hv/bin/hv-plan-show <key>
  ```

  Absent file → empty stdout, not an error. Treat empty as "no plan yet".

- **The milestone file** at `.hv/milestones/<MID>.md` if the work is milestone-scoped.
- **Items scoped to the milestone** via:

  ```
  .hv/bin/hv-todo-by-milestone <MID>
  ```

  Used by `/hv-plan` and `/hv-vision` to see siblings under the same milestone.

- **KNOWLEDGE + DECISIONS** — see `references/knowledge-consult.md` for the canonical query pattern. Pass the topic names inferred from the work area.
- **Recent git history**:

  ```
  git log --oneline -20
  ```

  Plus `git log --oneline -- <path>` for any probable target file.

## Issue in parallel

All reads in the list above are independent. The calling skill MUST issue them as parallel tool calls in a single response — load latency dominates this step, and serial reads make the skill feel slow without any benefit. Workers reading this reference should treat sequential reads as a planning failure.

A recent path-encoding helper audit confirmed why: when load steps drift between skills, the "shared protocol" rots. Parallelism keeps the reads visibly shaped the same across consumers, which keeps the contract honest.

## Skill-specific extras

Each calling skill adds its own reads inline. The protocol lists only the common subset. Concretely:

- `/hv-vision` Step 2 adds `.hv/MILESTONES.md`, every `.hv/milestones/M*.md`, glossary terms from `.hv/KNOWLEDGE.md` `## Glossary` (via `hv-glossary-read`), and stack files (`README.md`, `package.json`, `Cargo.toml`, `pyproject.toml`, etc.) — domain-shape reads that other skills don't need.
- `/hv-work` Preview Mode Step 2 adds Repos: parsing for umbrella items (resolves via `.hv/bin/hv-resolve-repos` when umbrella mode is on).
- `/hv-plan` Step 3 adds `.hv/bin/hv-plan-list <MID>` to see existing plans under the milestone.

## What to do with the loaded context

Read for picture, don't dump. The user did not invoke the skill to receive a context dump — they invoked it for the skill's actual deliverable (a peek, a plan, a milestone, a work cycle). Carry what's relevant into the next step; discard the rest silently.

If a skill finds itself wanting to recite the loaded context back at the user, that's a signal the load was the wrong shape, not that the user needs the recital.

## Lookup, not resolve

Reads in this list are lookups. Empty stdout from `hv-plan-show`, `hv-todo-by-milestone`, or a missing detail file is the answer, not a failure. Do not wrap these calls in `2>/dev/null` or fallbacks — the helpers exit 0 with empty output when there's nothing to return.

## What this reference does NOT cover

- **K+D query mechanics** — those live in `references/knowledge-consult.md`. This reference cites that one for the K+D portion; it does not redefine the query pattern.
- **`--auto-loop` pipeline grep'ing** — used by `/hv-plan --auto-loop` to resolve open questions against existing commitments. That's a separate auto-resolution pattern, not part of the silent pre-planning load.
- **`/hv-debug`, `/hv-refactor`, `/hv-review` context loads** — those consume only `references/knowledge-consult.md`, not the full protocol. Their inputs are different (a bug ID, a diff range, a feature branch), so they don't load TODO entries / plans / milestones the same way.
