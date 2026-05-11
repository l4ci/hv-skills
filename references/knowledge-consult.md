# Knowledge & decisions consult

Used by `/hv-debug` Step 3+3.5, `/hv-refactor` (umbrella-fanout context-collect step), `/hv-review` Step 3, and indirectly by `references/context-load-protocol.md` (which composes this pattern into a wider load list for `/hv-assume`, `/hv-plan`, `/hv-vision`, `/hv-work`).

The pattern is one pair of helper calls plus carrier semantics. Skills point here so the call-site logic lives in one place.

## Helpers

```bash
.hv/bin/hv-knowledge-query "Topic A" "Topic B"
.hv/bin/hv-decisions-query "Topic A" "Topic B"
```

Topic selection: read the `hv-knowledge` and `hv-decisions` managed blocks in `CLAUDE.md`, infer which topics plausibly touch the work (e.g., a backend refactor might pull `Architecture`), and pass those names as arguments. Pass several when in doubt — both helpers filter, so extras cost nothing.

Both helpers are lookups: they exit 0 with empty stdout when no topic matches. Do not wrap them with `2>/dev/null` or treat empty output as failure — that hides real errors and contradicts the lookup-vs-resolve contract in `.hv/DECISIONS.md`.

## Parallelism

The two queries are independent and disk-bound. When the calling skill issues both (almost always together), dispatch them as parallel tool calls in the same response.

## Carrier semantics

The two helpers return different *kinds* of content and the calling skill must handle them differently.

**KNOWLEDGE bullets are gotchas / hints.** Surface relevant ones into whatever brief the calling skill is building — debug hypothesis, reviewer brief, refactor sub-agent prompt, worker brief. The label varies per skill; the role is the same: prior-art that informs but does not constrain.

**DECISIONS entries are hard boundaries.** Pass the FULL entry to the consumer — rule, *Why*, **Forbids**, **Permits** — not just the title. The calling skill MUST treat them as constraints, not suggestions. If the planned action would violate a decision, stop and surface to the user before proceeding. Do not paper over a violation by rewording or scoping it away.

## Skip silently on empty

Either helper can legitimately return no rows. That is not an error; it means no topic in the registry matched the arguments. Carry only what matched into the downstream brief — do not insert empty headings, placeholder "(none)" lines, or apology prose.

A caller MAY add carrier-specific failure semantics on top — for example, "if my brief explicitly asserts that topic X is registered and the lookup returns empty, surface to the user." That logic belongs in the calling skill, not in this reference and not in the helpers.

## What this reference does NOT cover

- **Full pre-planning context load.** This is the K+D *query* pattern only. The composed load (TODO entry, plan, milestone, git history, plus K+D) lives in `references/context-load-protocol.md`, which cites this file for the K+D subset.
- **`.hv/CONTEXT.md` vocabulary lookup.** That's `hv-context-query`, a separate registry used by different call sites for different reasons (project terminology, not gotchas or boundaries).
- **MILESTONES.md grep'ing.** Patterns like `hv-plan`'s `--auto-loop` milestone-resolution grep are planning shortcuts, not context-consults, and are out of scope here.
