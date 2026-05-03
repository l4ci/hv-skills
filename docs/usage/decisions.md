# Decisions

`.hv/DECISIONS.md` records hard boundaries the project has committed to. It sits alongside `.hv/KNOWLEDGE.md`, but the two play different roles. Knowledge is passive: gotchas, conventions, things to remember if relevant. Decisions are active commitments with concrete forbids and permits that future work must respect.

## Decisions vs learnings

| | Knowledge (`/hv-learn`) | Decisions (`/hv-decide`) |
|---|---|---|
| Voice | "remember this if relevant" | "this is committed, do not violate" |
| Structure | one-liner per bullet | rule + *why* + **forbids** + **permits** |
| Capture | auto in `auto`/`loop` mode | always manual, always confirmation-gated |
| Reaction at consult | advisory; informs the approach | hard constraint; violations FAIL |
| When to use | "we discovered that the API returns 200 on auth failure" | "we will never store session tokens client-side" |

If you're unsure: try articulating **forbids** and **permits**. If you can't, it's a learning. If you can, it's a decision.

## Capturing a decision

Run `/hv-decide` when you've reached a commitment. The skill drafts a four-part entry (rule, why, forbids, permits) from conversation context, classifies it by topic, and asks for explicit confirmation before writing. Nothing is written without your "Write it" answer, even in `autonomy.level: loop`.

If you can't articulate forbids or permits, the skill suggests `/hv-learn` instead and stops. It does not auto-invoke `/hv-learn`; you re-run it yourself.

## Where decisions are consulted

| Skill | When |
|---|---|
| `/hv-work` | Step 4 plan phase. Workers receive matching entries as a `**Hard boundaries:**` block; orchestrator FAILs the plan if it would violate. |
| `/hv-debug` | Pre-hypothesis. Boundaries can rule out fix directions before cycles are wasted. |
| `/hv-plan` | Plan-write phase. Boundaries become hard constraints in the plan's design. |
| `/hv-refactor` | Design phase. Designs that violate a boundary are disqualified before approach selection. |
| `/hv-review` | Review checklist. Reviewer FAILs on any forbidden pattern in the diff. |
| `/hv-vision` | Milestone planning. Boundaries constrain what milestones can promise. |

`/hv-spike` and `/hv-ship` do not consult. Spikes are throwaway by definition, and ship only bundles (review already covers it).

## Suggest nudges

`/hv-work` and `/hv-debug` end with an optional nudge: *"Did this cycle codify any boundaries? Run `/hv-decide` to lock them in."* The nudge fires regardless of `autonomy.level`, since decisions are always your call.

## File location and gitignore

`.hv/DECISIONS.md` lives under `.hv/`, which is gitignored by default (consistent with the rest of the local backlog). If your team wants shared decisions, edit `.gitignore` to include `!.hv/DECISIONS.md`.

## See also

- [`/hv-decide` skill](../../hv-decide/SKILL.md) for the capture flow itself
- [Knowledge index](../reference/cli-helpers.md#knowledge-and-vision-indexes) for the parallel pattern used by `/hv-learn`
