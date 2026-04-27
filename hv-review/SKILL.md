---
name: hv-review
description: Staff-engineer review of a feature branch before merge or PR — reads commits, diff, referenced item IDs, and matching KNOWLEDGE.md topics; dispatches an Opus reviewer that checks intent match, convention compliance, and quality. Returns PASS / CONCERNS / FAIL. Use on "review this", "check before I ship", "look over the branch", or implicitly from /hv-ship.
user-invocable: true
---

```
════════════════════════════════════════════════════════════════════════
  🟧  hv-review  ·  staff-engineer review of a branch
  triggers: "review this", "check before ship"  ·  pairs: hv-ship
════════════════════════════════════════════════════════════════════════
```

# hv-review — Pre-Merge Review

Read-only staff-engineer review of a feature branch against its original intent, project conventions, and obvious quality issues. No mutations, no commits — just a verdict.

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

If the helper is absent or exits non-zero, invoke `hv-init` via the `Skill` tool, then continue. See GUIDE.md § Preflight for exit codes.

## Step 2 — Scope the Review

```bash
.hv/bin/hv-review-scope <branch>
```

If the user didn't name a branch, default to the current one. `hv-review-scope` emits JSON with:

- `branch`, `base`, `commitCount`
- `commits` — array of `{hash, subject}`
- `touchedFiles` — paths changed vs base
- `referencedIds` — `[B##]`/`[F##]`/`[T##]` found in commit messages
- `intents` — matched TODO entries for each referenced ID

If `commitCount` is 0, stop and tell the user.

## Step 3 — Consult KNOWLEDGE.md

Read the `hv-knowledge` block in `CLAUDE.md` to see available topics. Pick topics that plausibly touch the changed areas based on `touchedFiles` and commit subjects — infer liberally (e.g., a file under `Networking/` → the `Networking` topic).

```bash
.hv/bin/hv-knowledge-query "Topic A" "Topic B"
```

Carry the relevant bullets into the reviewer brief.

## Step 4 — Capture the Diff

The reviewer needs concrete diff content, not just file names. For each touched file (up to ~8 — more than that, ask the user which to focus on):

```bash
git diff <base>...<branch> -- <file>
```

Keep a per-file diff map in memory for the reviewer brief.

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

**Diff by file:**
<file>
```diff
<diff content>
```
...

**Evaluate on three axes. For each, return PASS / CONCERN / FAIL with evidence.**

1. **Intent match** — does the diff deliver what the TODO entries promise? Anything missing, anything scope-creeping?
2. **Convention compliance** — does the diff respect the bullets from KNOWLEDGE.md? Any regressions on captured gotchas?
3. **Obvious quality** — dead code, error swallowing, untested new branches, security smells, API contract breaks, performance cliffs. Not a full code review; focus on things the user would regret after merge.

Return verdict as three labeled sections. Be specific: file:line for every concern. Rank concerns by severity.

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

- **PASS** — tell the user *"Ready to ship. Run `/hv-ship`."* Stop.
- **CONCERNS** — if invoked from `/hv-ship`, return the verdict to the caller (it owns the decision). If invoked standalone, use `AskUserQuestion`:
  - **Header:** `"Concerns"`
  - **Question:** *"Review surfaced N concerns on `<branch>`. How should I proceed?"*
  - **Options** (single-select):
    1. "Address via `/hv-work` (Recommended)" — *"Route the concerns to `/hv-work` as a fix list."*
    2. "Ship anyway" — *"Hand off to `/hv-ship` with the concerns acknowledged."*
    3. "Stop" — *"Leave it; rerun `/hv-review` later if you want another pass."*
  - Plain-text fallback: *"Address now, proceed anyway, or stop?"*
- **FAIL** — tell the user it would regress. Suggest fixing via `/hv-work` or `/hv-debug`. Don't route to `/hv-ship`.

## Rules

- **Read-only.** Never edit, commit, or stage. The verdict is the entire product.
- **Evidence over opinion.** Every concern must cite file:line or commit hash.
- **Scope is bounded.** Only the diff against the base is reviewed — don't wander into unchanged code.
- **Call it honestly.** If conventions were violated but the user has a good reason, the reviewer still reports CONCERN — the user decides what to do.
- **Don't re-run on a passed branch.** If the same scope was just reviewed in the session and came back PASS, skip Step 5 and report the cached verdict.
