# Decisions

`.hv/DECISIONS.md` records hard boundaries the project has committed to. It sits alongside `.hv/KNOWLEDGE.md`, but the two play different roles. Knowledge is passive: gotchas and conventions to remember if relevant. Decisions are commitments with forbids and permits that future work must respect.

## Decisions vs learnings

| | Knowledge (`/hv-learn`) | Decisions (`/hv-decide`) |
|---|---|---|
| Voice | "remember this if relevant" | "this is committed, do not violate" |
| Structure | one-liner per bullet | rule + *why* + **forbids** + **permits** |
| Capture | auto in `auto`/`loop` mode | always manual, always confirmation-gated |
| Reaction at consult | advisory; informs the approach | hard constraint; violations FAIL |
| When to use | "we discovered that the API returns 200 on auth failure" | "we will never store session tokens client-side" |

When unsure, try articulating **forbids** and **permits**. If you can't, it's a learning. If you can, it's a decision.

## Capturing a decision

Run `/hv-decide` when you've reached a commitment. The skill drafts a four-part entry (rule, why, forbids, permits) from conversation context, classifies it by topic, and asks for confirmation before writing. Nothing is written without your "Write it" answer, even in `autonomy.level: loop`.

If you can't articulate forbids or permits, the skill suggests [`/hv-learn`](learning.md) instead and stops. It does not auto-invoke `/hv-learn`; you re-run it yourself.

The skill also runs a three-gate pre-write check: a candidate must be (a) hard to reverse, where undoing it would mean coordinated edits across many files, retraining habits, or migrating data; (b) surprising without context, where a future contributor wouldn't infer the rule from existing patterns alone; and (c) the result of a real trade-off, where genuine alternatives existed and the project deliberately didn't pick them. If any gate fails, the skill suggests `/hv-learn` (or "leave it inline at the call site") and stops without writing. The gates apply across the default, `--from-learning`, and `--from-spike` modes; all routes through `/hv-decide` go through the same filter.

## Promoting a learning or spike into a decision

When a `KNOWLEDGE.md` learning has hardened into a commitment, or a [`/hv-spike`](spikes.md) concluded with a verdict the project is committing to, you can seed the decision draft from the source artifact instead of retyping:

| Flag | Source | Pre-fills |
|------|--------|-----------|
| `/hv-decide --from-learning <topic>` | A bullet under `<topic>` in `.hv/KNOWLEDGE.md` (the skill picks the bullet: auto when there's only one, picker when there are several) | Rule from the bullet; Why cites the topic + date stamp |
| `/hv-decide --from-spike <name>` | `.hv/spikes/<name>.md`: question, decision, recommended approach | Rule keyed off the verdict (`viable` → "use it", `not viable` → "do not use it", `depends-on-X` → "use only when X"); Why summarizes the question + findings |

Both flags only seed `Rule` and `Why`. You still articulate `Forbids` and `Permits`; that's what makes the entry a decision rather than a learning. The Step 5 confirmation gate still runs; nothing is written until you approve.

`inconclusive` spikes can't be promoted, since the verdict isn't a commitment yet. Add findings on the spike branch, re-run `/hv-spike done <name>`, then come back.

`/hv-spike`'s Finish mode also nudges this flow automatically: when a spike concludes `viable`, `not viable`, or `depends-on-X`, the skill asks whether to promote the finding and dispatches `/hv-decide --from-spike <name>` if you say yes. See [spikes](spikes.md) for the full Finish-mode flow.

## Where decisions are consulted

| Skill | When |
|---|---|
| `/hv-work` | Step 4 plan phase. Workers receive matching entries as a `**Hard boundaries:**` block; orchestrator FAILs the plan if it would violate. |
| `/hv-debug` | Pre-hypothesis. Boundaries can rule out fix directions before cycles are wasted. |
| `/hv-plan` | Plan-write phase. Boundaries become hard constraints in the plan's design. |
| `/hv-refactor` | Design phase. Designs that violate a boundary are disqualified before approach selection. |
| `/hv-review` | Review checklist. Reviewer FAILs on any forbidden pattern in the diff. |
| `/hv-vision` | Milestone planning. Boundaries constrain what milestones can promise. |

`/hv-spike` and [`/hv-ship`](review-and-ship.md) do not consult. Spikes are throwaway by definition, and ship only bundles (review already covers it).

## Suggest nudges

[`/hv-work`](running-work.md) and [`/hv-debug`](debugging.md) end with an optional nudge: *"Did this cycle codify any boundaries? Run `/hv-decide` to lock them in."* The nudge fires regardless of [`autonomy.level`](autonomy.md), since decisions are your call.

## File location

`.hv/DECISIONS.md` is tracked by default, so decisions travel with the repo alongside `KNOWLEDGE.md` and `BACKLOG.md`. To keep decisions private, add `.hv/DECISIONS.md` to `.gitignore`.

## See also

- [`/hv-decide` skill](../../hv-decide/SKILL.md) for the capture flow itself
- [Knowledge index](../reference/cli-helpers.md#knowledge-and-vision-indexes) for the parallel pattern used by `/hv-learn`
- Sibling persistence skill: [`docs/usage/learning.md`](learning.md) — covers both topic-bullet learnings and `--term <name>` Glossary capture (folded from the former `/hv-context` in v4.0)
