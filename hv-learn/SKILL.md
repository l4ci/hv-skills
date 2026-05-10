---
name: hv-learn
description: Extract durable session learnings (gotchas, conventions, constraints) into .hv/KNOWLEDGE.md grouped by topic, and update the CLAUDE.md topic index. Opus verification is on by default via learn.verify in config.json; set to false for fast/cheap mode.
user-invocable: true
---

**Print the banner below (including the code fences) to the user verbatim before any other action. Skip if dispatched as a subagent.**

```
════════════════════════════════════════════════════════════════════════
  🧠  hv-learn  ·  extract session learnings to KNOWLEDGE.md
  triggers: "learn this", "save gotcha"  ·  pairs: hv-debug, hv-pause
════════════════════════════════════════════════════════════════════════
```

# hv-learn — Capture Session Learnings

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Scan session", description="Inspect transcript and recent commits for durable learnings")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (no learnings found, verifier disabled by config) get `completed` with the no-op reason in the description.

Phases:

1. *Scan session* — transcript + recent commits sifted for durable gotchas (Step 2)
2. *Classify topic* — each candidate matched to a `KNOWLEDGE.md` topic (Steps 3–4)
3. *Merge into KNOWLEDGE.md* — entries appended under topic headings (Step 5)
4. *Update CLAUDE.md index* — `hv-knowledge-index` regenerates the managed block (Step 6)
5. *Verify (Opus)* — optional cold pass when `learn.verify: true` (Steps 7–8)

## Step 2 — Scan the Session for Learnings

A learning is worth capturing if it would save a future `/hv-work` run from re-discovering it.

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

Verification is **on by default**. Read `.hv/config.json` — if `learn.verify` is `true` (default) or unset, run Step 7. Set `learn.verify: false` to skip it.

## Step 5 — Merge into KNOWLEDGE.md

Topics that grow past 25 bullets or 10 KB get a one-line size-nudge in Step 8 (`hv-knowledge-stats`-driven). It is informational only — the merge always proceeds.

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

Reads `.hv/KNOWLEDGE.md`, extracts `## Topic` headings in order, and updates the managed `<!-- hv-knowledge-start -->` block in `CLAUDE.md`. Creates or appends as needed; never touches other content. `/hv-work` reads this block to know when to consult `KNOWLEDGE.md`.

## Step 7 — Opus Verification (default)

Run unless `learn.verify` is explicitly `false`. Follow the brief in `hv-learn/verifier.md` — it contains the dispatch instructions, the verifier prompt, and the verdict-application rules. Apply the verdict, then continue to Step 8.

## Step 8 — Confirm

Tell the user, in one compact block, what was captured:

```
Captured 3 learnings into .hv/KNOWLEDGE.md:
  Testing (2 new)
  Networking (1 new)

Updated CLAUDE.md topic index — /hv-work will consult these on relevant tasks.
```

**Topic-size nudge.** Run `.hv/bin/hv-knowledge-stats` and check the JSON. If any topic has `bullets >= 25` OR `bytes >= 10240`, append a single nudge line per offender to the confirm output:

```
Note: `<topic>` is large (<bullets> bullets, <bytes-as-KB-rounded-1dp> KB). Consider splitting it (e.g. `<topic>: <facet-A>` + `<topic>: <facet-B>`) to reduce per-query cost in /hv-work, /hv-debug, /hv-go, /hv-plan.
```

Format KB as `{bytes/1024:.1f}` (e.g. `9.8 KB` for 9876 bytes). Do not auto-split. Splitting is editorial; the user accepts or declines.

If verification ran and passed, add a middle line: `Opus verification: PASS — all entries durable, sharp, correctly categorized.` If it returned `PASS_WITH_NOTES`, replace that line with a one-liner naming what was adjusted. If it failed, say so and stop.

## Step 8.5 — Suggest hv-skills issue (when applicable)

This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. Filing a public issue is high-stakes; the user presses the button.

**Trigger heuristic.** Scan the just-captured bullets for any of:

- A skill slash-command name: `/hv-init`, `/hv-config`, `/hv-capture`, `/hv-c`, `/hv-go`, `/hv-vision`, `/hv-next`, `/hv-pause`, `/hv-plan`, `/hv-spike`, `/hv-assume`, `/hv-work`, `/hv-debug`, `/hv-decide`, `/hv-review`, `/hv-ship`, `/hv-learn`, `/hv-docs`, `/hv-refactor`, `/hv-update`, `/hv-release`.
- A hv-skills helper path: `bin/hv-*` or `.hv/bin/hv-*` (regex `\b(?:\.hv/)?bin/hv-[a-z-]+`).
- An `.hv/` artifact path: `.hv/TODO.md`, `.hv/KNOWLEDGE.md`, `.hv/DECISIONS.md`, `.hv/MILESTONES.md`, `.hv/status.json`, `.hv/config.json`, `.hv/handoff/`, `.hv/plans/`, `.hv/spikes/`, `.hv/bugs/`, `.hv/features/`, `.hv/tasks/`, `.hv/milestones/`.

If no bullet matches any of those, skip the step silently.

**Ask before filing.** When at least one bullet matches, use `AskUserQuestion`:

- Header: `"Upstream"`
- Question: *"This learning touches hv-skills behavior. File an issue on the hv-skills repo?"*
- Options (single-select):
  1. `"File a hv-skills issue (Recommended)"` — *"Pre-fill title + body and run `bin/hv-issue-suggest` to open the issue."*
  2. `"Skip"` — *"No upstream issue; the local KNOWLEDGE bullet stands on its own."*

Plain-text fallback: *"File a hv-skills issue?"* — honor yes/no.

**File the issue.** When the user picks "File":

1. Compose title from the matching bullet's first sentence (truncate at the first period or 80 chars).
2. Compose body — use this template, substituting in real values:
   ```
   ## What happened
   <bullet text, verbatim>

   ## Expected
   <one-sentence inversion of the gotcha — what should have happened>

   ## Context
   - hv-skills version: <read from .claude-plugin/plugin.json or plugin.json — `"version": "X.Y.Z"`>
   - Captured topic: <KNOWLEDGE.md topic name>
   - Date: <today, YYYY-MM-DD>
   ```
3. Run the helper:
   ```bash
   printf '%s' "$BODY" | .hv/bin/hv-issue-suggest --title "$TITLE"
   ```
   - On exit 0 (gh available, issue filed): parse `url` and `number` from the JSON output.
   - On exit 1 (manual fallback printed): show the helper's stdout to the user, then prompt once: *"Paste the issue number when you've filed it manually (or 'skip' to skip):"* Read the user's reply; if a number, use it; if "skip" or empty, abandon the tracking step.

4. **Append the upstream marker to the bullet** in `.hv/KNOWLEDGE.md`. Use `Edit` to change the bullet's trailing comment from:
   ```
   - <bullet text> <!-- 2026-05-07 -->
   ```
   to:
   ```
   - <bullet text> <!-- 2026-05-07 --> Upstream: hv-skills#<N>
   ```
   Match the bullet exactly (including the date stamp) so the edit is unique.

5. Add a final line to the Step 8 confirm output:
   ```
   Filed hv-skills#<N> for the <topic> bullet — https://github.com/l4ci/hv-skills/issues/<N>
   ```

## Step 8.6 — Suggest runlog entry (when applicable)

This step is **always manual** — never auto-invoked, regardless of `autonomy.level`. Filing to a public registry is high-stakes; the user presses the button. Mirrors Step 8.5's shape but for the *inverse* signal: external dependencies (third-party APIs, libraries, protocols, OSS quirks), not hv-skills internals.

**Trigger heuristic.** Scan the just-captured bullets for ANY of (literal union, not all):

- The bullet's topic heading begins with one of these external-prone prefixes (case-insensitive): `Third-Party`, `Networking`, `Auth`, `Persistence`, `Deployment`.
- The bullet body matches a protocol/transport token (case-insensitive, word-bounded): `OAuth`, `OIDC`, `JWT`, `SAML`, `WebSocket`, `SSE`, `gRPC`, `GraphQL`, `REST`, `HTTP/[12]`, `TLS`, `DNS`, `IMAP`, `SMTP`, `WebRTC`, `MQTT`, `AMQP`, `S3`.
- The bullet body contains a surfaced external HTTP status code (word-bounded): `401`, `403`, `429`, `500`, `502`, `503`, `504`.
- The bullet body names a third-party brand or library (case-insensitive, word-bounded): `anthropic`, `openai`, `claude`, `gpt`, `redis`, `postgres(?:ql)?`, `mysql`, `mongodb`, `elasticsearch`, `kafka`, `rabbitmq`, `stripe`, `twilio`, `sendgrid`, `cloudflare`, `aws`, `gcp`, `azure`, `terraform`, `kubernetes`, `docker`, `nginx`, `apache`, `envoy`.

If no bullet matches any signal, skip the step silently. Match the union, not the intersection — one signal is enough to surface the prompt.

**Mutual exclusivity with Step 8.5.** Step 8.5 (hv-skills issue) and Step 8.6 (runlog) are independent — a bullet can match neither, one, or both. When a bullet matches both, run Step 8.5 first and let Step 8.6 ask afterward; they route to different upstreams and shouldn't bundle.

**Ask before dispatching.** When at least one bullet matches, use `AskUserQuestion`:

- Header: `"Runlog"`
- Question: *"This learning is about an external dependency. Contribute it to runlog.org via `/runlog-author`?"*
- Options (single-select):
  1. `"Run /runlog-author (Recommended)"` — *"Hand the matching bullet(s) to the runlog skill — drives the local Ed25519 verifier loop, then `runlog_submit`."*
  2. `"Skip"` — *"No upstream contribution; the local KNOWLEDGE bullet stands on its own."*

Plain-text fallback: *"Author a runlog entry?"* — honor yes/no.

**Route the answer.**

- **Run /runlog-author** — invoke the `runlog:runlog-author` skill via the `Skill` tool, naming the matching bullet(s) and the topic(s) in the brief so runlog-author has the right context. If the `Skill` tool errors that the skill is unknown (the runlog plugin isn't installed), surface one line — *"`/runlog-author` is not installed; install the runlog plugin to contribute back."* — and continue. Don't block /hv-learn on a missing peer skill.
- **Skip** — print one line — *"Run `/runlog-author` later if you change your mind."* — and continue.

When the dispatch ran, append one line to the Step 8 confirm output:

```
Ran /runlog-author for the <topic> bullet.
```

## Key Principles

- **Durable, not ephemeral.** If it only matters this week, it's a TODO. Use `/hv-capture`.
- **Preserve existing structure.** Edit surgically; never regenerate the whole file.
- **Sharp and short.** One sentence with a concrete claim. If you need a paragraph, link to code instead.
- **Today's date.** Always stamp with the absolute current date.
