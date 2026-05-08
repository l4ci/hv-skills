# Consolidate /hv-status, /hv-resume, /hv-next — Design

**Item:** [F26]
**Date:** 2026-05-08
**Status:** Approved (brainstorm)

## Goal

Reduce hv-skills' three "project state" commands (`/hv-status`, `/hv-resume`, `/hv-next`) to one (`/hv-next`) by hard-deleting the other two and folding `/hv-resume`'s handoff-detection behavior into `/hv-next`'s existing per-stream resolution step.

## Background

hv-skills today exposes three slash-commands that all surface some variant of "project state":

| Command | Lines | Behavior |
|---------|------:|----------|
| `/hv-status` | 51 | Read-only one-shot summary: backlog counts, active streams, recent completions, knowledge-topic count, archive size. No git, no questions, no routing. |
| `/hv-resume` | 168 | Post-`/clear` reorientation: reconciles `status.json` against git, reads `.hv/handoff/<branch>[@<repo>].md` notes from `/hv-pause`, surfaces Stage/Next/Hypothesis inline, asks per-stream what to do (resume / ship / abandon / leave), routes via the `Skill` tool. |
| `/hv-next` | 193 | Backlog review: reconciles, archives old completions, prints sorted backlog tables, suggests highest-priority next item, dispatches `/hv-work`. Already runs per-stream resolution in Step 2 when active streams exist. |

The three are not three skins on the same logic — they have meaningfully different mutation profiles, question patterns, and output shapes. But the user-facing distinction is muddied: `/hv-next` already handles active streams, and the only behavior unique to `/hv-resume` is *reading the handoff note and surfacing its content inline*. `/hv-status`'s quiet glance was never adopted in practice — the user reports defaulting to `/hv-next` for "what's open" instead.

The original capture for [F26] named three options:

- (a) Collapse to one command with flags (`/hv-state --read-only`, `--resume`, `--suggest`)
- (b) Sharpen docstrings + banners; keep three commands
- (c) Keep distinct but cross-reference in each banner

The brainstorm rejected all three in favor of a fourth direction (d): **hard-delete the two unused/redundant commands and absorb their distinguishing behavior into `/hv-next`**.

## Decision

Hard-merge into `/hv-next`:

1. **Delete `hv-status/` folder entirely.** Its quiet-glance behavior is not preserved as a flag or mode — `/hv-next`'s full output stands as the only state-view command.
2. **Delete `hv-resume/` folder entirely.** Its handoff-detection + per-stream-with-handoff routing folds into `/hv-next` Step 2.
3. **Bump version to `2.0.0`.** Removing user-invocable slash-commands is a breaking change for published consumers; semver major is required.

No deprecation stubs, no silent aliases, no flag survivors. Anyone typing `/hv-status` or `/hv-resume` after the update sees Claude Code's "unknown command" error — the CHANGELOG migration note is the only forewarning, which is acceptable for a 2.0.0 line.

## Scope

### Removed

- `hv-status/SKILL.md` and the entire `hv-status/` folder
- `hv-resume/SKILL.md` and the entire `hv-resume/` folder
- Both entries in `plugin.json`'s `commands` section
- `docs/usage/...` references that point at the deleted skills (most cross-reference from `pausing-and-resuming.md` and `next-and-status.md`)

### Modified

- **`hv-next/SKILL.md`** absorbs three pieces from `/hv-resume`:
  - Step 2 (Reconcile Active Work) gets a sub-step: for each entry in `needsAction`, resolve the handoff path (`.hv/handoff/<branch>@<repo>.md` when `repo` is non-null, else `.hv/handoff/<branch>.md`) and read it if present. The handoff content (`Stage`, `Next planned step`, `Current hypothesis`) is captured per-stream alongside the existing `branch`, `items`, `hasCommits`, `worktree` fields.
  - The per-stream `AskUserQuestion` gets a fourth state for "handoff present":
    | State | Recommended | Other options |
    |-------|-------------|---------------|
    | Handoff note present | "Resume with `/hv-work` (consumes the note)" | "Leave handoff for later" / "Abandon branch" |
    | (existing arms unchanged) | | |
  - Resolution-routing extends: "Resume with `/hv-work`" on a handoff stream consumes the handoff (`rm -f` the path), passes the handoff content into the dispatched `/hv-work` brief; "Leave handoff for later" preserves the file.
- **`hv-next/SKILL.md` banner** — triggers extend to include `/hv-resume`'s former triggers (*"where was I"*, *"pick up"*, *"resume"*) and `/hv-status`'s (*"status"*, *"summary"*). The `pairs:` line is updated.
- **`hv-next/SKILL.md` description** — frontmatter description gains a clause naming the absorbed behavior so future invocations match those triggers.
- **`bin/hv-skills-index`** — the hand-curated heredoc body (per the 2026-05-02 KNOWLEDGE rule about its non-derivability) drops the `/hv-status` and `/hv-resume` lines; the "Capture & pick" group keeps only `/hv-next`.
- **`hv-pause/SKILL.md`** — banner's `pairs:` line currently reads `pairs: hv-resume, hv-learn`; becomes `pairs: hv-next, hv-learn`. Any prose mentioning `/hv-resume` as the consumer of handoff notes updates to `/hv-next`.
- **`README.md`** — slash-command index table drops the two rows; mermaid diagram and prose mentions of `/hv-status` and `/hv-resume` get updated or pruned.
- **`docs/reference/slash-commands.md`** — drops the `## /hv-status` and `## /hv-resume` sections; `## /hv-next` description gets updated to mention handoff-detection.
- **`docs/usage/pausing-and-resuming.md`** — substantially rewritten. The "/hv-resume" section becomes "/hv-next reading a handoff note" with the same flow described under the surviving command.
- **`docs/usage/next-and-status.md`** — likely renamed (or its prose collapsed) since `/hv-status` no longer exists; if kept, retitled.
- **`.hv/KNOWLEDGE.md` and `.hv/DECISIONS.md`** — entries that mention `/hv-resume` or `/hv-status` by name get updated to `/hv-next` where the rule still applies. Most rules are about behavior (handoff handling, terminal-path nudges), not the dead skill name; mechanical grep-and-replace.
- **`bin/hv-reconcile`** — no schema change; the JSON output already carries `repo`, which is what the new handoff path resolution keys on. The reconciler stays unchanged; the consumer (`/hv-next`) does the path resolution and read.
- **`CHANGELOG.md`** — `2.0.0` section is prepended with a `### Breaking` block calling out the removal and pointing at the new flow.
- **`.claude-plugin/plugin.json`** — version bump to `2.0.0`; commands list trimmed.
- **`hv-skills/.hv/...`** — no `.hv/` runtime changes (it's gitignored regardless).

### Out of scope

- **No `/hv-state` umbrella with flags.** F26's option (a) is rejected; one command, no flags.
- **No `/hv-next --quiet` survivor for `/hv-status`.** F26's option (b) partial fallback is rejected; the quiet glance disappears.
- **No deprecation stubs.** F26's option (c) is rejected; redirects, aliases, and "deprecated — forwarding" prints are all out.
- **No banner-cross-reference scheme.** With one command, there's nothing to cross-reference.
- **No re-implementation of `/hv-resume`'s logic in a helper.** The handoff read happens inline in `/hv-next` Step 2's prose, mirroring how `/hv-resume` does it today (path resolution + `cat`). No new `bin/` helper.

## Migration

Users on 1.x who run `/hv-update` get pointed at 2.0.0. After updating and re-running `/hv-init`:

- `/hv-status` → unknown command → user runs `/hv-next` and sees the same backlog view (richer than the old `/hv-status` glance, but at no extra cost)
- `/hv-resume` → unknown command → user runs `/hv-next`, which detects active streams (with handoff notes if present) and behaves identically to the old `/hv-resume` flow

The 2.0.0 release-notes paragraph in `CHANGELOG.md` is the migration document. Sample shape:

> **Breaking**: `/hv-status` and `/hv-resume` removed in favor of `/hv-next`. `/hv-next` now reads `/hv-pause` handoff notes for active streams and surfaces Stage/Next/Hypothesis inline, replacing the post-`/clear` `/hv-resume` flow. The lightweight glance from `/hv-status` is no longer offered as a separate command — `/hv-next` is the single state-view entry point. Update muscle memory: anywhere you typed `/hv-status` or `/hv-resume`, type `/hv-next` instead.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------:|-------:|------------|
| Existing user types `/hv-status` post-update, sees "unknown command" | High | Low | CHANGELOG migration paragraph; one-time annoyance, then recalibration |
| Plugin cache holds stale `hv-status` / `hv-resume` SKILL.md files between `git pull` and `/hv-init` re-run | Medium | Low | Standard 2.0.0 update flow re-populates the cache; "bumpy first update" is the expected shape |
| Loop-mode (`autonomy.level: loop`) chain breaks because `/hv-resume` was a transition point | Low | Medium | `/hv-next` is the loop seam today; `/hv-resume` is invoked manually post-`/clear`, not from inside a loop. No loop-chain change. |
| Missed cross-reference in a SKILL.md `pairs:` line, KNOWLEDGE bullet, or doc page leaves a dead `/hv-resume` mention | Medium | Low | Implementation plan must include a grep sweep for `/hv-resume`, `/hv-status`, `hv-resume`, `hv-status` across `**/*.md`, `**/*.json`, `bin/*` and update or remove every hit |
| `/hv-next` becomes too long after absorbing `/hv-resume`'s logic (currently 193 lines; expected to land around 240-260) | Low | Low | Mirror-step threshold in KNOWLEDGE says 3 instances of a logical block is the noise floor for factoring — we're staying inside one skill, not hitting that threshold. Length is fine. |
| The handoff-read sub-step in Step 2 quietly fails (file missing, malformed) and `/hv-next` errors out | Low | Medium | Mirror `/hv-resume`'s existing read pattern (`[ -f "$HANDOFF" ] && cat "$HANDOFF"`); silent on missing, no error on malformed (the file is human-written prose, parsing is best-effort) |

## Open questions

1. **Banner emoji for the merged `/hv-next`.** Today: `📊` for `/hv-status`, `🔄` for `/hv-resume`, `👉` for `/hv-next`. Keep `👉`? Switch to `🔄`? — Not load-bearing; the implementation plan can pick. Default: keep `👉`.
2. **`docs/usage/next-and-status.md` filename.** With `/hv-status` gone, the filename becomes misleading. Rename to `picking-work.md`? Merge into `running-work.md`? — Decide in the plan; doesn't affect skill behavior.
3. **`/hv-pause`'s mention of `/hv-resume`.** Currently `/hv-pause`'s description says *"so /hv-resume in a fresh session can pick up"*. Update to `/hv-next` mechanically. Confirm wording in plan.

## Acceptance

After implementation:

- `hv-status/` and `hv-resume/` directories do not exist on `main`.
- `plugin.json` lists no `hv-status` or `hv-resume` command.
- `/hv-next` invoked in a fresh session that has an active stream + handoff note surfaces Stage/Next/Hypothesis inline (verified manually with `/hv-pause` → `/clear` → `/hv-next`).
- `bin/hv-skills-index` regenerated; `<!-- hv-skills-start -->` block in `CLAUDE.md` reflects the new shape.
- Smoke tests pass.
- `git grep -E '/hv-(status|resume)\b'` returns hits ONLY in `CHANGELOG.md` (the breaking-change note) and historical files under `docs/superpowers/plans/`, `docs/superpowers/specs/`, `.hv/handoff/` (which is gitignored anyway).
- Version in `plugin.json` and `.claude-plugin/plugin.json` is `2.0.0`.
- A new entry in `CHANGELOG.md` under `## 2.0.0` calls out the breaking change with the migration paragraph.

## Next step

User reviews this spec; on approval, hand off to `superpowers:writing-plans` to author the implementation plan at `docs/superpowers/plans/2026-05-08-consolidate-status-resume-next-plan.md`.

`/hv-plan` is *not* the right authoring path here: `bin/hv-plan-add` enforces an `M\d{2,}` milestone prefix on plan keys, and F26 carries no `Milestone:` tag (no milestones are currently active). Tagging F26 to a fabricated milestone solely to satisfy the helper would invert the artifact's purpose. The existing repo pattern — captured in the 2026-05-01 KNOWLEDGE entry on plan-as-artifact and exemplified by `docs/superpowers/plans/2026-05-01-hv-decide.md` — puts non-milestone plans under `docs/superpowers/plans/` and points `/hv-work` at them via the brief's `**Plan:**` line. F26 follows that pattern.

When the plan is written, the natural execution call is:

```
/hv-work execute the plan at docs/superpowers/plans/2026-05-08-consolidate-status-resume-next-plan.md
```

`/hv-work` Step 4's plan-as-artifact check reads the plan and uses its task decomposition as worker briefs.
