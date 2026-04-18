---
name: hv:learn
description: Extract durable session learnings (gotchas, conventions, constraints) into .hv/KNOWLEDGE.md grouped by topic, and update the CLAUDE.md topic index. Opus verification is opt-in via learn.verify in config.json.
user-invocable: true
---

# hv:learn — Capture Session Learnings

Distill durable knowledge from the current session into `.hv/KNOWLEDGE.md`, organized by topic, so it's available to future work.

## Step 1 — Ensure .hv/ Exists

If `.hv/KNOWLEDGE.md` is missing, invoke `/hv:init` first.

## Step 2 — Scan the Session for Learnings

A learning is worth capturing if it would save a future `/hv:work` run from re-discovering it.

**Capture:**

- **Gotchas** — non-obvious failure modes, footguns (e.g., "this API returns 200 on auth failure")
- **Conventions** — project-specific patterns not obvious from the code (e.g., "all network calls go through NetworkClient")
- **Constraints** — invariants, compatibility rules (e.g., "schema migrations must be backward-compatible for 2 versions")
- **Debugging insights** — root causes for hard-won bugs
- **Decisions with rationale** — why we chose X over Y
- **Tool quirks** — build/test behavior that trips people up

**Skip:** things documented in code or README, transient session state, obvious facts, restatements of framework docs, personal preferences.

If nothing is worth capturing, say so and stop. Don't manufacture learnings.

## Step 3 — Classify by Topic

Open `.hv/KNOWLEDGE.md` first and reuse existing `## Topic` headings when they fit. Create a new topic only if nothing fits. Good topic examples: `Build & Tooling`, `Testing`, `Networking`, `Persistence`, `Auth`, `Architecture`, `Performance`, `Third-Party APIs`, `Deployment`.

Don't create a topic per learning.

## Step 4 — Auto-Write

Skip approval prompts. Proceed to Step 5 (merge into `KNOWLEDGE.md`) and Step 6 (update `CLAUDE.md`).

Verification is **opt-in**. Read `.hv/config.json` — if `learn.verify` is `true`, run Step 7. Otherwise skip to Step 8.

## Step 5 — Merge into KNOWLEDGE.md

`.hv/KNOWLEDGE.md` is organized as:

```markdown
# Knowledge

## <Topic>
- <learning> <!-- 2026-04-18 -->
- <older learning>
```

**Merge rules:**

- Preserve existing topics — never rewrite sections you didn't change
- Insert new bullets at the top of their topic (newest first)
- Stamp new bullets with today's absolute date as an HTML comment: `<!-- YYYY-MM-DD -->`
- One line per bullet; use a sub-bullet only if longer context is essential
- **Deduplicate:** skip restatements, or replace the older entry with the sharper wording
- New topics go alphabetically, except `Build & Tooling` and `Architecture` may be pinned near the top

Use `Edit` for surgical updates, not `Write`.

## Step 6 — Update CLAUDE.md Topic Index

```bash
.hv/bin/hv-knowledge-index
```

Reads `.hv/KNOWLEDGE.md`, extracts `## Topic` headings in order, and updates the managed `<!-- hv:knowledge:start -->` block in `CLAUDE.md`. Creates or appends as needed; never touches other content. `/hv:work` reads this block to know when to consult `KNOWLEDGE.md`.

## Step 7 — Opus Verification (opt-in)

Only run if `learn.verify` is `true`. Follow the brief in `hv-learn/verifier.md` — it contains the dispatch instructions, the verifier prompt, and the verdict-application rules. Apply the verdict, then continue to Step 8.

## Step 8 — Confirm

Tell the user, in one compact block, what was captured:

```
Captured 3 learnings into .hv/KNOWLEDGE.md:
  Testing (2 new)
  Networking (1 new)

Updated CLAUDE.md topic index — /hv:work will consult these on relevant tasks.
```

If verification ran and passed, add a middle line: `Opus verification: PASS — all entries durable, sharp, correctly categorized.` If it returned `PASS_WITH_NOTES`, replace that line with a one-liner naming what was adjusted. If it failed, say so and stop.

## Key Principles

- **Durable, not ephemeral.** If it only matters this week, it's a TODO. Use `/hv:capture`.
- **Preserve existing structure.** Edit surgically; never regenerate the whole file.
- **Sharp and short.** One sentence with a concrete claim. If you need a paragraph, link to code instead.
- **Today's date.** Always stamp with the absolute current date.
