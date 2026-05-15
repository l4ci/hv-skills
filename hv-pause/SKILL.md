---
name: hv-pause
description: Gracefully pause mid-session — writes a handoff note (current hypothesis, next planned step, mid-edit files, uncommitted work strategy) to .hv/handoff/<branch>.md so /hv-next in a fresh session can pick up with full context, not just git state. Use when the session is approaching a context limit, you need to hand off, or you want to stop a long /hv-work cycle cleanly.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  💤  hv-pause  ·  write handoff note for clean pause
  triggers: "pause", "hand off"  ·  pairs: hv-next, hv-learn
════════════════════════════════════════════════════════════════════════
```

# hv-pause — Graceful Session Pause

`/hv-next` reads and deletes the handoff note on the next session.

## When to Use

- Context window is filling up and you want to stop cleanly
- You have to step away mid-`/hv-work` or mid-`/hv-debug` cycle
- Work will continue in a new session; git commits alone won't carry the intent

## When NOT to Use

- Work is actually complete → `/hv-ship`
- You can finish in this session → just finish
- No active branch / no `/hv-work` running → nothing to hand off

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** Follow the canonical pattern in `references/task-list-init.md` — load `TaskCreate` via `ToolSearch select:TaskCreate,TaskUpdate` if needed, then create one task per phase below.

Phases:

1. *Snapshot context* — current hypothesis, next planned step, mid-edit files captured (Step 2)
2. *Compose handoff* — narrative drafted for `/hv-next` to surface on resume (Step 3)
3. *Write to .hv/handoff/* — file persisted under the active branch's name (Step 4)
4. *Report* — compact handoff summary printed (Step 5)

## Step 2 — Resolve the Pause Set

Determine the set of `(branch, repo)` entries to pause. The set has size 1 for single-repo cycles or scoped umbrella pauses; size ≥ 2 when one `/hv-work` wave fanned out across sub-repos and the user wants to pause it as one logical unit.

1. Read `.hv/status.json` and find active streams whose `branch` matches the current branch.
2. **Exactly one match** — pause set is that single `(branch, repo)` entry (`repo` may be `null` for non-umbrella entries).
3. **Multiple matches** (a multi-repo `/hv-work` wave). Run `.hv/bin/hv-resolve-repo` from the current cwd:
   - **cwd resolves to a registered sub-repo** — pause set is the single matching `(branch, repo)` entry. The user explicitly scoped to one repo by `cd`-ing there; the other entries stay active.
   - **cwd doesn't resolve** (umbrella root or outside any sub-repo) — pause set is **all** matching entries, treated as one logical wave. Do not raise an `AskUserQuestion` — entries from a single `/hv-work` wave are paused together.
4. **No match** — fall back to `git rev-parse --abbrev-ref HEAD` for the branch and pause set is `[(branch, null)]` (covers running `/hv-pause` before any `/hv-work` registered status).
5. If the resolved branch is the project base (run `.hv/bin/hv-guard-feature-branch <branch>` and check exit 1), tell the user there's no feature work to pause and stop.

Steps 3–6 below operate on the pause set: single-entry sets keep today's behavior byte-for-byte; multi-entry wave sets loop the per-repo work and emit a single combined confirmation in Step 6.

## Step 3 — Handle Uncommitted Work

For each `(branch, repo)` in the pause set, resolve the working directory:

- `repo == null` → run from current cwd.
- `repo != null` → use the sub-repo's absolute path (`.hv/bin/hv-resolve-repos <repo>` returns it).

Run the status check in each working directory:

```bash
git -C <path> status --porcelain
```

For a single-entry set this is identical to today's `git status --porcelain` from cwd.

- **All entries clean** → continue to Step 4 with `clean tree` artifact for every entry.
- **Any entry dirty** → ask once via `AskUserQuestion`:
  - **Header:** `"Uncommitted"`
  - **Question (single-entry set):** *"N uncommitted files on `<branch>`. How should I handle them?"*
  - **Question (wave set):** *"Uncommitted files on `<branch>` in `<repo-a>`, `<repo-c>`. How should I handle them?"*
  - **Options** (single-select):
    1. "WIP commit (Recommended)" — *"`git add -A && git commit -m 'wip: pause before context cutoff'` — keeps changes on the branch."*
    2. "Stash" — *"`git stash push -u -m 'hv-pause <branch>'` — keeps changes out of history."*
    3. "Leave in place" — *"No action; the handoff will note that the tree is dirty."*
  - Plain-text fallback: *"Wrap them in a `wip:` commit, stash them, or leave them in place?"*

Apply the chosen disposition **only to the dirty entries** (use `git -C <path> ...` per repo). Record the per-entry artifact (commit hash, stash ref, `dirty tree`, or `clean tree`) for Step 4.

## Step 4 — Write the Handoff Note

```bash
mkdir -p .hv/handoff
```

Resolve milestone context first — pass the captured item IDs to `.hv/bin/hv-find-milestone-for-items <ID> [<ID>...]` to read their `Milestone:` tags. If the helper prints one or more milestones, include them in the **Working on** block below. If it prints nothing, fall back to `.hv/bin/hv-vision-active` — and if exactly one active milestone is listed, include that. Multi-active milestones with mixed-tagged items: list whichever milestone matches the items being paused.

**Loop over the pause set — one handoff file per `(branch, repo)` entry.** Resolve each entry's write path via `.hv/bin/hv-resolve-handoff --write ${REPO:+--repo "$REPO"} "$BRANCH"`; the helper owns the canonical encoding (single-repo and `<branch>@<repo>` umbrella variants).

For wave sets, every entry shares the **Items**, **Milestone**, **Stage**, **Next planned step**, and **Current hypothesis** content — only `Repo:` and the per-repo `Uncommitted work` artifact differ. Don't merge them into one combined file: `/hv-next`'s lookup is keyed on `(branch, repo)`, so per-entry files keep that path symmetric and survive partial cleanup (one repo abandoned, others resumed).

Compose the note from the template at `references/handoff-template.md` — fill each section from the current session, omit sections that don't apply, but don't manufacture content. The four sections in the template are exactly what `/hv-next` consumes.

Use `Write` for each note (always overwrite — one handoff per `(branch, repo)` pair). Durable learnings (gotchas, dead ends) belong in `/hv-learn` via the Step 6 nudge, not the handoff.

## Step 5 — Pin Status

Loop over the pause set:

```bash
# Make sure status.json has each entry so /hv-next finds them
.hv/bin/hv-status-add --if-absent [--repo <repo>] <branch> <item-ids> [worktree-path]
```

Pass `--repo <repo>` for entries with a non-null `repo`; omit it for legacy / single-repo entries. Uniqueness is `(branch, repo)`, so threading `--repo` matters when two sub-repos share a branch name.

Idempotent — `--if-absent` skips the write if the entry already exists, preserving the original `startedAt` so "time in flight" stays accurate. The handoff note carries the pause timestamp separately.

## Step 5.5 — Surface Auto:Loop Decisions

`/hv-pause` is a terminal path — the user is about to leave the session. Per the F19 terminal-path-only convention (mirrored in `/hv-next` empty-backlog and `/hv-work` guard-fail), surface any `[Auto:Loop]` decisions logged during this loop session so the user can articulate `Forbids/Permits` and remove the `<!-- [Auto:Loop] -->` footers in `DECISIONS.md` before the session ends:

Surface any `[Auto:Loop]` decisions per `references/terminal-loop-surface.md` (silent when empty). Print the surface verbatim above the Step 6 confirm block.

## Step 6 — Confirm

One compact block. For single-entry pause sets:

```
Paused `hv/fix-B07-timer-badge` (web) — handoff saved.

Stage: mid-hypothesis verification for [B07]
Next: run the verification probe in MenuBarManager.swift:54
Uncommitted: wip commit a1b2c3d

Resume with `/hv-next` in a fresh session.
```

The `(web)` suffix is shown only in umbrella mode (when `<repo>` is non-null); single-repo cycles drop it and just print the branch.

For wave pause sets (≥ 2 entries from one `/hv-work` wave):

```
Paused `hv/api-refactor` across web, api — 2 handoffs saved.

Stage: implementing wave 2 of 3
Next: thread the new repo arg through hv-status-add-multi
Uncommitted:
  - web: wip commit a1b2c3d
  - api: clean tree

Resume with `/hv-next` in a fresh session.
```

Stage / Next / Hypothesis are shared across the wave; Uncommitted is per-repo because each sub-repo's working tree is independent.

**Learn nudge (conditional).** Pausing = context loss. If the session uncovered a durable gotcha (typical signals: a hypothesis that contradicted initial assumptions, a non-obvious root cause, a tool quirk you'll hit again), suggest one line:

*"Run `/hv-learn` now to preserve session insights durably — handoff captures intent, not learnings."*

Skip if nothing non-obvious surfaced or `/hv-learn` already ran this session. Don't block the pause — the nudge is advisory.

## Rules

- **Write what you know, not what you wish you knew.** The handoff is a snapshot of orchestrator state, not a task spec.
- **One note per `(branch, repo)`.** Overwrite on re-pause; don't accumulate stale notes.
- **Multi-repo waves are one logical pause.** When `status.json` holds multiple `(branch, repo)` entries from one `/hv-work` wave, `/hv-pause` treats them as a single unit by default — no `AskUserQuestion` to pick one repo. Scope the pause to a single sub-repo by `cd`-ing into it before invoking `/hv-pause`; cwd resolves to that repo and the other entries stay active.
- **Umbrella handoff filenames key on `(branch, repo)`.** Two sub-repos sharing a branch name get separate handoff files at `.hv/handoff/<branch>@<repo>.md`; single-repo cycles keep `.hv/handoff/<branch>.md` unchanged.
- **Never commit `.hv/handoff/`.** `.hv/` is gitignored, so this is automatic — but don't add an exception.
- **`/hv-next` owns cleanup.** Once `/hv-next` has read and routed, it deletes the note. Don't self-delete here.
- **No mutation beyond the handoff + optional wip/stash.** This skill's job is capture, not integration.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`references/handoff-template.md`](../references/handoff-template.md) — Handoff-note template written by `/hv-pause` and read by `/hv-next`.
