---
name: hv:learn
description: Extract durable learnings from the current session — gotchas, conventions, non-obvious constraints, hard-won debugging insights — and store them in .hv/KNOWLEDGE.md grouped by topic. Updates CLAUDE.md with a topic index so future /hv:work runs can consult relevant knowledge. Use when the user says "capture what we learned", "save this learning", "/hv:learn", or when wrapping up a session with notable discoveries.
user-invocable: true
---

# hv:learn — Capture Session Learnings

Distill durable knowledge from the current session into `.hv/KNOWLEDGE.md`, organized by topic, so it's available to future work.

## Step 1 — Ensure .hv/ Exists

Check if `.hv/KNOWLEDGE.md` exists. If not, run `/hv:init` first, then continue. `/hv:init` creates the file and the CLAUDE.md pointer.

## Step 2 — Scan the Session for Learnings

Review the current conversation for knowledge that would be useful in future sessions. A learning is worth capturing if it would save a future `/hv:work` run from re-discovering it.

**Capture:**

- **Gotchas** — non-obvious failure modes, subtle bugs, footguns (e.g., "this API returns 200 on auth failure", "SwiftData @Query rebuilds on every view init")
- **Conventions** — project-specific patterns that aren't obvious from reading code (e.g., "all network calls go through NetworkClient, never URLSession directly")
- **Constraints** — invariants, compatibility requirements, deploy-time rules (e.g., "schema migrations must be backward-compatible for 2 versions")
- **Debugging insights** — root causes for hard-won bugs (e.g., "flaky test X was caused by timezone-dependent date formatting, not concurrency")
- **Decisions with rationale** — why we chose X over Y, so nobody reopens the debate (e.g., "we use Core Data over SwiftData because SwiftData lacks CloudKit sharing in iOS 17")
- **Tool quirks** — build, test, or tooling behavior that trips people up

**Skip:**

- Things already documented in the code or README
- Transient state (what was in-progress, what the user was working on today)
- Obvious facts derivable from reading the codebase
- Restatements of framework docs — link out instead
- Personal preferences that belong in user memory, not project knowledge

If you find nothing worth capturing, say so and stop. Don't manufacture learnings.

## Step 3 — Classify by Topic

Group each learning under a short, stable topic heading. Prefer existing topics over new ones — open `.hv/KNOWLEDGE.md` first and reuse its headings when they fit.

Good topic examples (keep them short and scoped):

- `Build & Tooling`
- `Testing`
- `Data Layer` / `Persistence` / `Networking`
- `Auth`
- `Architecture`
- `Performance`
- `Third-Party APIs`
- `Deployment`

Create a new topic only if nothing existing fits. Don't create a topic per learning.

## Step 4 — Auto-Write

Skip approval prompts. Proceed directly to Step 5 (merge into `KNOWLEDGE.md`) and Step 6 (update `CLAUDE.md`).

Verification is **opt-in**. Read `.hv/config.json` — if `learn.verify` is `true`, run Step 7 (Opus verifier). Otherwise skip to Step 9. Default is `false` because the writer already follows strict rules; the verifier is a second-opinion pass for teams that want extra rigor.

## Step 5 — Merge into KNOWLEDGE.md

`.hv/KNOWLEDGE.md` is organized as:

```markdown
# Knowledge

Durable learnings captured from sessions. Grouped by topic. Newest entries at the top of each section.

## <Topic A>
- <learning> <!-- 2026-04-18 -->
- <older learning>

## <Topic B>
- <learning>
```

**Merge rules:**

- Preserve existing topics — never rewrite a section you didn't change
- Insert new bullets at the top of their topic (newest first)
- Append the capture date as an HTML comment: `<!-- YYYY-MM-DD -->` (use today's absolute date)
- Keep bullets one line each when possible; if longer context is needed, use a sub-bullet
- **Deduplicate:** if a bullet restates an existing one, skip it or replace the older entry with the sharper wording
- New topics go in alphabetical order relative to existing ones, except you can pin `Build & Tooling` and `Architecture` near the top if they exist

Use `Edit` for surgical updates, not `Write` (don't clobber unrelated sections).

## Step 6 — Update CLAUDE.md Topic Index

Delegate to the helper — it reads `.hv/KNOWLEDGE.md`, extracts `## Topic` headings in order, and updates the managed `<!-- hv:knowledge:start -->` block in `CLAUDE.md`. Creates `CLAUDE.md` if missing, updates the block in place if present, appends if `CLAUDE.md` exists without a block. Never touches other content.

```bash
.hv/bin/hv-knowledge-index
```

`/hv:work` reads this block to know when to consult `KNOWLEDGE.md`.

## Step 7 — Opus Verification (opt-in)

**Only run this step if `learn.verify` in `.hv/config.json` is `true`.** Otherwise skip to Step 9.

Dispatch a **single verifier subagent** using the `Agent` tool with `model: "opus"` and `subagent_type: "general-purpose"`. The verifier does a cold read of the written files and returns a verdict — don't pre-bias it with your own notes.

**Brief:**

```
You are the hv:learn verifier. Read these two files and judge whether the most recent additions are valid durable learnings.

Files:
- .hv/KNOWLEDGE.md  (entries stamped <!-- YYYY-MM-DD --> with today's date are the new ones)
- CLAUDE.md         (the block between <!-- hv:knowledge:start --> and <!-- hv:knowledge:end -->)

Today's date: <absolute date — e.g. 2026-04-18>

For each new entry, judge:
1. **Durable** — will this still matter in 6 months, or is it ephemeral session state?
2. **Sharp** — concrete claim in one sentence, not vague advice?
3. **Non-obvious** — not something any reader would derive from the code or framework docs?
4. **Correctly topic-ed** — does the bullet sit under the right heading?
5. **Not duplicated** — does it restate an existing bullet in the same topic?

Also verify structural integrity:
- KNOWLEDGE.md headings are well-formed (`## Topic`)
- CLAUDE.md managed block is intact, topic list matches KNOWLEDGE.md headings in order
- No accidental deletions of existing content

Return in this exact shape, ≤150 words total:

VERDICT: PASS | PASS_WITH_NOTES | FAIL
SUMMARY: <one sentence>
ENTRIES:
  - "<first 8 words of bullet>" — OK | weak: <reason> | duplicate of "<other>" | wrong topic (suggest: <topic>)
  - ...
STRUCTURE: OK | <what's broken>
```

## Step 8 — Apply Verifier Feedback (opt-in)

**Only run this step if Step 7 ran.** Otherwise skip to Step 9.

Act on the verdict before reporting to the user:

- **PASS** → proceed to Step 9.
- **PASS_WITH_NOTES** → for each flagged entry, use `Edit` to fix the specific issue (reword weak bullets, remove duplicates, move wrong-topic bullets). Don't re-invoke the verifier — the notes are advisory, not a gate.
- **FAIL** → revert the new entries you added in Steps 5–6 (use `Edit` to remove them), and tell the user exactly which learnings were rejected and why. Stop.
- **STRUCTURE broken** → fix the specific structural issue flagged, regardless of the main verdict.

## Step 9 — Confirm

Tell the user, in one compact block, what was captured.

**If verification was skipped (default):**

```
Captured 3 learnings into .hv/KNOWLEDGE.md:
  Testing (2 new)
  Networking (1 new)

Updated CLAUDE.md topic index — /hv:work will consult these on relevant tasks.
```

**If verification ran and passed:**

```
Captured 3 learnings into .hv/KNOWLEDGE.md:
  Testing (2 new)
  Networking (1 new)

Opus verification: PASS — all entries durable, sharp, correctly categorized.
Updated CLAUDE.md topic index — /hv:work will consult these on relevant tasks.
```

If the verdict was `PASS_WITH_NOTES`, replace the middle line with a one-liner naming what was adjusted. If `FAIL`, say so and stop.

## Key Principles

- **Durable, not ephemeral.** If it only matters this week, it's a TODO, not a learning. Use `/hv:capture`.
- **Auto-write, verify-after.** No approval prompt. Opus reviews the written result and reports the verdict.
- **One topic, many bullets.** Don't shatter related learnings across topics.
- **Preserve existing structure.** Edit surgically; never regenerate the whole file.
- **Sharp and short.** A learning is one sentence with a concrete claim. If you need a paragraph, you probably need a link to code instead.
- **Today's date.** Always stamp with the absolute current date, never "today" or "this week".
