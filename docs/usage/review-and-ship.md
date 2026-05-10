# Review and ship

`/hv-ship` integrates completed work into main, gated by `/hv-review` by default.

## /hv-review

`/hv-review` is a staff-engineer-level read of a feature branch before it leaves your machine. It is **read-only**: no commits, no mutations.

The skill scopes the branch (commits, touched files, referenced item IDs), pulls relevant topics from [`KNOWLEDGE.md`](learning.md), and evaluates the diff on three axes:

- **Intent match** — does the diff deliver what the work items promised?
- **Convention compliance** — does it respect captured gotchas and project rules?
- **Obvious quality** — dead code, swallowed errors, untested branches, security smells, contract breaks.

It returns one of three verdicts, with file:line evidence where applicable:

| Verdict | Meaning |
|---------|---------|
| `PASS` | Diff is clean on all three axes. |
| `CONCERNS` | Issues found, but not blocking. You can proceed or fix first. |
| `FAIL` | Something must be addressed before integration. |

You can run `/hv-review` at any time on a branch, not only before shipping:

```
/hv-review
```

## /hv-ship

`/hv-ship` bundles a completed feature branch into main. Typical usage after finishing work:

```
/hv-ship
```

**Default flow:** [preflight](../reference/preflight.md) → review (if `ship.review` is `true`) → build PR body → open PR or merge → close resolved items.

The review gate behaves as follows:

- `FAIL` blocks integration; fix the branch and rerun `/hv-ship`.
- `CONCERNS` surfaces to you; you can proceed or address it first.
- `PASS` lets integration run automatically.

Use `/hv-ship` to integrate finished work. Complete the implementation cycle in [`/hv-work`](running-work.md) first; don't call `/hv-ship` mid-implementation.

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

The review gate is independent of the autonomy level. Even under `autonomy: "loop"`, a `FAIL` verdict halts the chain until you fix the branch.

See [configuration](configuration.md) for the full `ship` block.

## Release nudges

When you've accumulated commits since the last release tag, [`/hv-next`](picking-work.md) (on terminal paths — when you stop without entering `/hv-work`) and `/hv-ship` (in its post-ship report) surface a one-line reminder:

```
5 commits since v1.16.0; consider /hv-release.
```

The nudge fires when EITHER `release.nudgeAfterCommits` (default 10) OR `release.nudgeAfterDays` (default 14) is reached — see [configuration](configuration.md#releasenudgeaftercommits). It's informational; no skill is auto-invoked. The first release is always your call (no nudge fires while no tag exists).
