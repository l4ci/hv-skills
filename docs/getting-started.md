# Getting started

Install hv-skills and run your first capture → work → ship cycle in about five minutes.

## Install

```bash
npx skills add l4ci/hv-skills
```

For other install methods (Claude Code plugin marketplace, GNU Stow, local clone), see [install alternatives](install.md).

## Initialize the project

Run `/hv-init` once at the project root. It asks five questions (models, isolation, merge
strategy, quality gates, autonomy level) with Recommended defaults highlighted. Accept the
defaults unless you have a reason not to.

Two settings worth a second of thought:

- **Isolation.** `branch` is fine for solo work. Switch to `worktree` if you want `main`
  untouched while agents run, or if you plan to run parallel `/hv-work` sessions.
- **Merge strategy.** `direct` for fast iteration. `pr` if your team requires GitHub review.

To change any setting later, run `/hv-config`. Don't hand-edit the JSON files.

## Worked examples

Two end-to-end walkthroughs carry one concrete project from brief to shipped milestone:

- [Greenfield: from a brief to a shipped milestone](walkthroughs/greenfield-from-brief.md) — empty repo plus a one-page brief, walked through `/hv-vision`, `/hv-plan`, `/hv-work`, `/hv-debug`, `/hv-ship`, `/hv-learn`.
- [Brownfield: dropping hv-skills into an existing project](walkthroughs/brownfield-existing-project.md) — established codebase with open GitHub issues and a mental bug list, walked through `/hv-map`, `/hv-issues`, `/hv-capture`, then a P0 cycle and a debug cycle.

Pick whichever matches where your project is today and follow it skill-by-skill.

## Where to go next

**Capture and backlog**
- [Capturing work](usage/capturing-work.md)
- [Picking work](usage/picking-work.md)

**Execution**
- [Running work](usage/running-work.md)
- [Debugging](usage/debugging.md)
- [Pausing and resuming](usage/pausing-and-resuming.md)

**Shipping**
- [Review and ship](usage/review-and-ship.md)
- [Learning and KNOWLEDGE.md](usage/learning.md)
- [Decisions and DECISIONS.md](usage/decisions.md)

**Vision and planning**
- [Vision and plans](usage/vision-and-plans.md)
- [Spikes](usage/spikes.md)

**Reference**
- [Configuration](usage/configuration.md)
- [Autonomy levels](usage/autonomy.md)
