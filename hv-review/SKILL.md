---
name: hv-review
description: Staff-engineer review of a feature branch before merge or PR — reads commits, diff, referenced item IDs, and matching KNOWLEDGE.md topics; dispatches an Opus reviewer that checks intent match, convention compliance, and quality. Returns PASS / CONCERNS / FAIL. Use on "review this", "check before I ship", "look over the branch", or implicitly from /hv-ship.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  🔍  hv-review  ·  staff-engineer review of a branch
  triggers: "review this", "check before ship"  ·  pairs: hv-ship
════════════════════════════════════════════════════════════════════════
```

# hv-review — Pre-Merge Review

## Configuration

Read `.hv/config.json`:

- `models.orchestrator` — model for the reviewer (default `opus`)

## When to Use

- Before merging or opening a PR — typically invoked from `/hv-ship`
- *"Review this branch"*, *"Second-opinion this"*, *"Look over what I've got"*
- After manual commits to a branch you want validated before integrating

## When NOT to Use

- Code is still in flight → finish implementing via `/hv-work`
- You want to change code based on the review → `/hv-refactor` or a fresh `/hv-work` run
- Nothing committed yet → there's nothing to review

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Read commits & items", description="Walk branch range and resolve referenced TODO IDs")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (no items resolved, no convention overlap) get `completed` with the no-op reason in the description.

Phases:

1. *Read commits & items* — branch range walked, referenced item IDs collected (Step 2)
2. *Intent match* — diff vs item titles and detail files compared (Step 3)
3. *Convention check* — `KNOWLEDGE.md`/`DECISIONS.md` topics consulted for overlap (Step 4)
4. *Quality pass* — staff-engineer review of the diff at large (Step 5)
5. *Verdict* — PASS / CONCERNS / FAIL with structured findings (Step 6)

## Step 2 — Scope the Review

```bash
.hv/bin/hv-review-scope <branch>
```

**Umbrella mode.** When the branch lives in a sub-repo, pass `--repo <name>` so git ops resolve there: `.hv/bin/hv-review-scope --repo <name> <branch>`. Determine `<name>` from the active stream's `repo` field in `.hv/status.json` (single match), or from `hv-resolve-repo` if invoked from inside the sub-repo's worktree. `TODO.md` / `ARCHIVE.md` lookups stay umbrella-flat — `hv-review-scope` reads them from the umbrella's `.hv/`, so no repo flag is needed for intent matching.

If the user didn't name a branch, default to the current one. `hv-review-scope` emits JSON with:

- `branch`, `base`, `commitCount`
- `commits` — array of `{hash, subject}`
- `touchedFiles` — paths changed vs base
- `referencedIds` — `[B##]`/`[F##]`/`[T##]` found in commit messages
- `intents` — matched TODO entries for each referenced ID

If `commitCount` is 0, stop and tell the user.

## Step 3 — Consult KNOWLEDGE & DECISIONS

Apply the canonical K+D query pattern (`references/knowledge-consult.md`) with topics that plausibly touch the changed areas based on `touchedFiles` and commit subjects — infer liberally (e.g., a file under `Networking/` → the `Networking` topic).

Carry KNOWLEDGE bullets into the reviewer brief. Pass DECISIONS entries under a `**Hard boundaries:**` section — the reviewer must **FAIL** if the diff violates any boundary, even if the change looks otherwise good.

## Step 4 — Capture the Diff

The reviewer needs concrete diff content, not just file names. For each touched file (up to 8; with 9 or more, ask the user which to focus on):

```bash
git diff <base>...<branch> -- <file>
```

**Issue all the per-file `git diff` calls in parallel** — they're independent and serial calls add up fast on bigger branches. Keep a per-file diff map in memory for the reviewer brief.

## Step 4.5 — Pre-flight Scaffolding Scan

Multi-task feature branches sometimes ship comments that referenced earlier task numbers ("Umbrella behavior is added in Task 7 — for now --repo is parsed but ignored") even after the referenced task completed. Before dispatching the reviewer, run a deterministic diff scan:

```bash
.hv/bin/hv-review-scaffolding [--repo <name>] <base> <branch>
```

Empty stdout → no candidates, skip ahead to Step 5. Non-empty stdout → carry the matches forward as `**Possible stale scaffolding:**` evidence in the reviewer brief (Step 5). Do not auto-FAIL — the reviewer judges each match as real scaffolding or legitimate prose. The helper surfaces; the reviewer decides.

## Step 5 — Dispatch the Reviewer

Dispatch a single review agent using the **orchestrator** model. Brief template:

```
Review the feature branch `<branch>` against base `<base>` before merge.

**Commits:**
<hash> <subject>
<hash> <subject>
...

**Items being resolved:**
- [B07] Timer badge shows stale duration — "<full intent line from TODO>"
- [F03] Quick-switch projects — "<full intent line from TODO>"

**Relevant project conventions (from KNOWLEDGE.md):**
- <bullet 1>
- <bullet 2>

**Hard boundaries (from DECISIONS.md):**
<entries from hv-decisions-query, if any — full rule + forbids/permits>

**Possible stale scaffolding (deterministic pre-flight grep):**
<file:line>: <matched line text>
<file:line>: <matched line text>
...

(Omit this section entirely when Step 4.5 produced no matches.)

**Diff by file:**
<file>
```diff
<diff content>
```
...

**Evaluate on the rubric below. For each item, return PASS / CONCERN / FAIL with evidence.**

1. **Intent match** — does the diff deliver what the TODO entries promise? Anything missing, anything scope-creeping?
2. **Convention compliance** — does the diff respect the bullets from KNOWLEDGE.md? Any regressions on captured gotchas?
3. **Obvious quality** — dead code, error swallowing, untested new branches, security smells, API contract breaks, performance cliffs. Not a full code review; focus on things the user would regret after merge.
4. **Stale scaffolding** — for each entry in `**Possible stale scaffolding:**`, judge whether the matched line is a leftover *Task N* / *placeholder* / *not yet wired* / *added later* / *in flight* annotation that should have been removed once the corresponding work landed. Flag as CONCERN with the file:line if it reads like leftover scaffolding; PASS-and-skip if it's legitimate prose (e.g., a markdown placeholder section, a docstring describing user-visible "in flight" semantics, an enum value named `placeholder`, or a `Task <N>` mention in a per-task brief or test name). Many matches will be benign — the helper surfaces candidates, not verdicts.
- **Decision violations.** Compare the diff against the `**Hard boundaries:**` block above. Any forbidden pattern present in the diff = FAIL.

Return verdict as labeled sections. Be specific: file:line for every concern. Rank concerns by severity.

**Final verdict** (on the last line, all caps): PASS | CONCERNS | FAIL
- PASS — no concerns worth surfacing
- CONCERNS — works, but surfaces should be flagged before merge
- FAIL — merge would regress behavior, break intent, or violate a project convention
```

## Step 6 — Relay the Verdict

Present the reviewer's output **verbatim** (or nearly so — trim only restatements). Don't summarize away the evidence; specifics are the point.

Structure:

```
Review: `hv/foo` → main (3 commits, 5 files)

### 1. Intent match — PASS
<evidence>

### 2. Convention compliance — CONCERN
- src/Foo.swift:42 — uses raw URLSession; KNOWLEDGE says all network calls go through NetworkClient
- ...

### 3. Obvious quality — PASS
<evidence>

Verdict: CONCERNS
```

## Step 7 — Route Based on Verdict

The verdict is the entire product — return it and stop. Never ask a follow-up; the caller (the user, or `/hv-ship` when invoked) owns what happens next.

When invoked from `/hv-ship`, return the verdict; the parent runs consumer routing per `references/review-verdict-routing.md`. When invoked standalone, relay the verdict to the user using the *Producer-side relay* table in the reference — short summary:

- **PASS** — *"Ready to ship. Run `/hv-ship`."*
- **CONCERNS** — print the concerns inline (already done in Step 6), then suggest *"Address via `/hv-work` and rerun `/hv-review`, or accept and ship via `/hv-ship`."*
- **FAIL** — tell the user the merge would regress. Suggest fixing via `/hv-work` or `/hv-debug`. Don't route to `/hv-ship`.

## Rules

- **Read-only.** Never edit, commit, or stage. The verdict is the entire product.
- **Evidence over opinion.** Every concern must cite file:line or commit hash.
- **Scope is bounded.** Only the diff against the base is reviewed — don't wander into unchanged code.
- **Call it honestly.** If conventions were violated but the user has a good reason, the reviewer still reports CONCERN — the user decides what to do.
- **Don't re-run on a passed branch.** If the same scope was just reviewed in the session and came back PASS, skip Step 5 and report the cached verdict.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`references/knowledge-consult.md`](../references/knowledge-consult.md) — Canonical K+D query pattern (`hv-knowledge-query` + `hv-decisions-query`) used by every cycle-starting skill.
- [`references/review-verdict-routing.md`](../references/review-verdict-routing.md) — PASS / CONCERNS / FAIL routing for `/hv-review` consumers.
