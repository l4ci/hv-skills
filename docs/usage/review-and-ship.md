# Review and ship

`/hv-ship` integrates completed work into main, gated by `/hv-review` by default.

## /hv-review

`/hv-review` is a staff-engineer-level read of a feature branch before it leaves your machine. It is **read-only**: no commits, no mutations. The skill scopes the branch (commits, touched files, referenced item IDs), pulls relevant topics from [`KNOWLEDGE.md`](learning.md), and runs a two-stage review with short-circuit gating.

### Stage 1 — spec compliance

Stage 1 answers exactly one question: *"does the diff fulfill the outcomes promised by the plan?"* The reviewer reads only the diff plus the resolved `.hv/plans/<key>.md` content for each referenced item — no `KNOWLEDGE.md`, no `DECISIONS.md`, no convention checks. Tighter brief, faster verdict.

Stage 1 verdict prefixes:

| Verdict | Meaning |
|---------|---------|
| `SPEC-PASS` | Diff fulfills the plan's promised outcomes. |
| `SPEC-CONCERNS` | Partial fulfillment or scope drift, not blocking. |
| `SPEC-FAIL` | Diff doesn't deliver what was promised. Stage 2 short-circuits — no point quality-reviewing work that doesn't meet spec. |

**No-plan fallback.** If no referenced item has a plan file (common when `/hv-go` was used), Stage 1 can't run as a meaningful spec check. The skill prints one informational line and proceeds directly to Stage 2, which then absorbs intent-match as its first rubric item.

### Stage 2 — code quality

Stage 2 owns conventions, edge cases, security smells, performance cliffs, stale scaffolding, decision violations, and silent-failure detection. Stage 1's verdict is provided as context but is NOT re-evaluated here — Stage 2 explicitly skips intent matching when Stage 1 ran.

Rubric items:

- **Convention compliance** against captured `KNOWLEDGE.md` topics.
- **Decision violations** — any forbidden pattern from `DECISIONS.md` present in the diff = `FAIL`.
- **Stale scaffolding** — leftover *Task N* / *placeholder* / *in-flight* annotations that should have been removed once the corresponding work landed.
- **Silent-failure hunter** — for every verification claim in the diff (new test, smoke section, assertion, helper-output check), apply a four-question rubric: *(a)* what does this verify concretely? *(b)* is the asserted-on shape the same shape the real consumer reads? *(c)* was the new code path actually exercised? *(d)* if you deleted the new code, would the assertion still pass? If any answer is *no* or *unclear*, the claim is flagged `SILENT-FAIL` with file:line. Flags surface as CONCERNS — they don't break the build alone, but you see them before merging.

Stage 2 verdicts use the `QUALITY-` prefix (`QUALITY-PASS`, `QUALITY-CONCERNS`, `QUALITY-FAIL`).

### Combined verdict

The final line of the report is the combined verdict — `PASS` / `CONCERNS` / `FAIL` — with file:line evidence where applicable. When only one stage ran (no-plan fallback or stage opt-out), the verdict strips the prefix.

| Verdict | Meaning |
|---------|---------|
| `PASS` | Both stages clean. |
| `CONCERNS` | Issues found, but not blocking. You can proceed or fix first. |
| `FAIL` | Either stage produced a `FAIL`; integration is blocked. |

### Stage opt-out

To run only one stage:

```
/hv-review --stage spec      # only Stage 1
/hv-review --stage quality   # only Stage 2, legacy single-pass behavior
/hv-review                   # both stages with short-circuit gating (default)
```

You can run `/hv-review` at any time on a branch, not only before shipping.

## /hv-ship

`/hv-ship` bundles a completed feature branch into main. Typical usage after finishing work:

```
/hv-ship
```

**Default flow:** [preflight](../reference/preflight.md) → `/hv-review` (if `ship.review` is `true`) → second-opinion gate (if `ship.secondOpinion` is `true`) → `/hv-qa` gate (if `ship.qa` is `true`) → build PR body → open PR or merge → close resolved items.

The review gate behaves as follows:

- `FAIL` blocks integration; fix the branch and rerun `/hv-ship`.
- `CONCERNS` surfaces to you; you can proceed or address it first.
- `PASS` lets integration run automatically.

### Second-opinion gate (opt-in)

When `ship.secondOpinion: true` and `/hv-review` returned `PASS`, `/hv-ship` dispatches a fresh subagent with **no prior conversation context** and gives it only the diff plus the stated goal. `/hv-review` shares the project's context (conventions, `KNOWLEDGE.md`, plan) with the work it produced — a reviewer with that context normalizes blind spots. A reviewer without it must reason from the diff alone, catching what the contextualized reviewer let pass.

Returns `PASS` / `CONCERNS` / `FAIL` and routes through the same verdict logic as `/hv-review`. Skipped if the user already accepted CONCERNS in Step 3 (no value in re-litigating). Opt-in because it adds one fresh-context roundtrip per ship and most cycles don't need it. Enable when shipping release tooling, security paths, or data migrations. See [`ship.secondOpinion`](configuration.md#shipsecondopinion).

### QA gate (opt-in)

When `ship.qa: true`, `/hv-ship` invokes [`/hv-qa run`](qa.md) between review and the merge step. `/hv-review` and the second-opinion gate answer *"does the diff make sense"*; `/hv-qa` answers *"does the product actually work"* by executing the per-target strategy in `.hv/qa/<target>.md` (Playwright, smoke, lighthouse, axe, ZAP, contract tests).

Verdict routes per `qa.gate`:

| `qa.gate` | `PASS` | `CONCERNS` | `FAIL` |
|---|---|---|---|
| `"advisory"` (default) | continue silently | surface findings, continue | surface findings, continue (advisory means advisory) |
| `"blocking"` | continue silently | branch on autonomy level | stop the ship |

`INFRA-FAIL` (dev server / creds / binary missing) is always advisory regardless of `qa.gate`. See [product QA](qa.md) for the full strategy file format.

Use `/hv-ship` to integrate finished work. Finish the implementation cycle in [`/hv-work`](running-work.md) first; don't call `/hv-ship` mid-implementation.

## Direct merge vs GitHub PR

`work.mergeStrategy` in `.hv/config.json` controls how the branch is integrated:

| Strategy | How it works | When to use |
|----------|-------------|-------------|
| `"direct"` | Merges to main and deletes the branch locally. | Solo work, fast iteration. |
| `"pr"` | Pushes the branch and opens a GitHub PR with a generated body. | Team work, required code review. |

The PR body is built from commit subjects, the list of resolved item IDs, and a short test plan derived from the touched areas.

See [configuration](configuration.md) for the full `work` block.

## What `ship.review` controls

`ship.review` in `.hv/config.json` decides whether `/hv-ship` runs `/hv-review` before integrating:

| Value | Behavior |
|-------|---------|
| `true` (default) | `/hv-review` runs first. `FAIL` blocks, `CONCERNS` surface but you can proceed, `PASS` flows through. |
| `false` | Skips the review pass. Integration runs immediately. Use when you have already reviewed manually and want to skip the second pass. |

The review gate is independent of the autonomy level. Under `autonomy: "loop"`, a `FAIL` verdict still halts the chain until you fix the branch.

See [configuration](configuration.md) for the full `ship` block.

## Release nudges

Once you've accumulated commits since the last release tag, [`/hv-next`](picking-work.md) (on terminal paths, when you stop without entering `/hv-work`) and `/hv-ship` (in its post-ship report) surface a one-line reminder:

```
5 commits since v1.16.0; consider /hv-release.
```

The nudge fires when EITHER `release.nudgeAfterCommits` (default 10) OR `release.nudgeAfterDays` (default 14) is reached; see [configuration](configuration.md#releasenudgeaftercommits). It's informational; no skill is auto-invoked. The first release is always your call (no nudge fires while no tag exists).

## Release checklist

`/hv-release` walks a per-project checklist (`.hv/RELEASE.md` by default) as a preflight gate at Step 1.5 — before the version bump, before any writes. Each `- [ ]` line is one gate. Released-once-forgotten-forever drift like a sibling version file going stale, a missing CHANGELOG humanization pass, or an infra rollout step nobody owns ends up here — the skill itself stays generic.

```markdown
# Release Checklist

- [ ] `.claude-plugin/marketplace.json` versions match the new `plugin.json` version
- [ ] CI is green on the release branch
- [ ] Migration notes for users on the prior version are written
- [ ] Push staging migration (manual)
```

For each gate the skill asks: *Yes, continue* / *Fix now and continue* / *Skip this item* / *Abort release*. Skipped items show up in the post-release summary so the release record stays honest. Items ending in `(manual)` always interject even under `autonomy.level: auto` or `loop` — useful for sensitive gates that should not auto-acknowledge.

When the file is absent, the skill offers to scaffold a starter under `autonomy.level: off`, or silently skips the gate under `auto`/`loop` (don't interrupt unattended runs). See [`release.checklistPath`](configuration.md#releasechecklistpath) to override the path.

The file is gitignored by default — each contributor maintains their own. If you want a shared checklist, drop `.hv/` (or just `.hv/RELEASE.md`) from `.gitignore` and commit it like any other source file.
