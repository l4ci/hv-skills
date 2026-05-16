# Learning

`/hv-learn` pulls durable knowledge out of a session and writes it to
`KNOWLEDGE.md` so future runs don't rediscover the same gotchas.

## /hv-learn

`/hv-learn` scans the current session, extracts non-obvious knowledge, groups
the entries by topic, and writes them to [`.hv/KNOWLEDGE.md`](../reference/hv-folder.md). After writing, it
updates the managed `hv-knowledge` block in `CLAUDE.md` so the topic list stays
in sync. [`/hv-work`](running-work.md) reads that index to decide when the current task should
consult `KNOWLEDGE.md`.

## What gets captured (and what doesn't)

**Captured:**

- Gotchas: non-obvious failure modes
- Conventions: project-specific patterns that aren't obvious from reading code
- Constraints: invariants, compatibility rules
- Debugging insights: root causes for bugs that took effort to track down
- Decisions with rationale
- Tool quirks

**Not captured:**

- Things already documented in code or README
- Transient session state
- Obvious facts derivable from the codebase
- Restatements of framework docs
- Personal preferences

## How `KNOWLEDGE.md` is organized

Entries are grouped under short topic headings such as `Build & Tooling`,
`Testing`, or `Networking`. Within each topic, the newest bullets sit at the
top. New entries carry an HTML-comment date stamp (`<!-- YYYY-MM-DD -->`) so
you can tell at a glance how fresh a piece of knowledge is.

## Promotion lifecycle

`KNOWLEDGE.md` bullets carry a tier — `provisional`, `confirmed`, or `deprecated` — tracked in a sidecar (`.hv/knowledge-tier.json`) along with a hit counter. Tiers separate "we wrote this down once" from "we've validated this repeatedly in real cycles."

| Tier | Meaning |
|------|---------|
| `provisional` | Default for new bullets. Same advisory weight as before, but not yet load-bearing. |
| `confirmed` | Promoted after `learn.promoteThreshold` clean hits (default 3) or manually via `/hv-learn --promote`. |
| `deprecated` | Manually marked stale via `/hv-learn --deprecate`, or auto-flagged for review when a contradiction lands. |

### Hit tracking

Every time [`/hv-work`](running-work.md) or `/hv-review` consults a bullet and the consuming step actually uses it (not just reads past it), the bullet's hit counter increments via `bin/hv-knowledge-hit`. Hits accumulate across sessions — the counter is durable.

At the `learn.promoteThreshold` mark, a `provisional` bullet auto-promotes to `confirmed`. Two skip conditions: the bullet already has a pending contradiction (auto-promotion stays blocked until you resolve it), or the threshold is `0` (in which case `provisional` is bypassed entirely on insert — a config choice, not a normal mode).

See [`learn.promoteThreshold`](configuration.md#learnpromotethreshold) for tuning.

### Contradiction queue

When `/hv-work` or `/hv-review` consumes a `confirmed` bullet and observes behavior that contradicts it (the rule said X, the code or test shows ¬X), the bullet lands in `.hv/knowledge-contradictions.json` rather than getting silently demoted. Mid-cycle is the wrong moment to commit to a demotion — the contradiction might be the bug under investigation, not a stale truth.

`/hv-learn` reads the queue at the start of a session and prompts for each pending entry:

1. *Demote (Recommended)* — flips the bullet to `deprecated`.
2. *Keep — false positive* — leaves the tier unchanged.

Either choice clears the entry from the queue.

### Manual lifecycle flags

Three explicit flags bypass the heuristic flow when you already know what you want:

- `/hv-learn --promote <topic> "<title>"` — sets the bullet to `confirmed` without waiting for hits. Use for a brand-new lesson you trust on the strength of the session that produced it.
- `/hv-learn --deprecate <topic> "<title>"` — marks `deprecated`. Manual deprecations do NOT touch the contradiction queue — that queue is for heuristic candidates only.
- `/hv-learn --amend <topic> "<title>"` — rewrites the body of one bullet while preserving its tier and hits. Use when you want sharper wording without resetting the validation history.

All three operate on `(topic, title)` pairs. The tier sidecar is the source of truth for the lifecycle state; `KNOWLEDGE.md` itself stays human-readable without tier annotations.

## When to invoke

Invoke `/hv-learn` after a session that surfaced discoveries: two or more
gotchas resolved in a cycle, a broad change touching many files, or a hard bug
whose root cause wasn't obvious. Skip it for single-item fixes and mechanical
changes where nothing worth re-using was learned.

Skills nudge or auto-invoke `/hv-learn` depending on your
[autonomy](autonomy.md) level. At lower autonomy levels you get a prompt; at
higher levels the skill runs automatically at the end of a work cycle.

## Verification

`learn.verify` in `.hv/config.json` controls a second-opinion pass. When set to
`true`, `/hv-learn` dispatches a fresh Opus subagent that reads only the updated
`KNOWLEDGE.md` diff (no session context) and judges each new bullet on four
criteria: durable (not ephemeral), sharp (concrete claim, not vague), correctly
topic'd, and non-duplicate. The verifier can demote weak entries, sharpen vague
wording, re-file wrong-topic bullets, or delete restatements of existing
knowledge.

| Value | Behavior |
|-------|----------|
| `true` | After writing, run the verifier. Catches weak, duplicate, or wrong-topic entries before they accrete. Adds one Opus roundtrip per `/hv-learn` call. |
| `false` | Skip the verifier. `/hv-learn` writes and reports immediately. Faster and cheaper. |

See [configuration](configuration.md) for the full `learn.verify` setting.

## CLAUDE.md integration

`/hv-learn` keeps the managed `hv-knowledge` block in `CLAUDE.md` in sync with
the topic headings in `KNOWLEDGE.md`. Each time `/hv-learn` runs it rewrites
that block to reflect the current topic list. `/hv-work` reads this index at the
start of a task to decide whether the task at hand warrants consulting
`KNOWLEDGE.md` before planning begins.

## Cross-skill: external dependencies feed runlog

When a captured bullet is about an external dependency (a third-party API quirk, a library bug, or a protocol gotcha), `/hv-learn` asks once whether to also contribute the finding to [runlog.org](https://runlog.org) via `/runlog-author`. Trigger heuristic: the bullet's topic begins with `Third-Party`, `Networking`, `Auth`, `Persistence`, or `Deployment`, OR the body mentions a recognizable protocol (OAuth, JWT, WebSocket, gRPC, REST, S3, ...), an external HTTP status (401, 403, 429, 500-504), or a brand/library name (anthropic, openai, redis, postgres, kafka, stripe, aws, cloudflare, ...). If nothing matches, the step is silent.

The nudge is always manual. `/hv-learn` never auto-files to runlog regardless of [autonomy](autonomy.md) level, since the contribution is a public artifact. Pick "Run /runlog-author" and the runlog skill drives its local Ed25519-signed verifier loop and submission; pick "Skip" and the bullet stays local. If the runlog plugin isn't installed, `/hv-learn` surfaces a one-line note and moves on without blocking.

This is independent of the `hv-skills` upstream-issue suggestion (which fires for *internal* tool quirks). A bullet can match neither, one, or both. When it matches both, `/hv-learn` asks them in sequence, since they route to different upstreams.

## Knowledge vs decisions

If you find yourself wanting to write *"we will never X"* or *"X is forbidden in
this codebase,"* that belongs in a [decision](decisions.md). Knowledge is
advisory ("remember this if relevant"). Decisions are hard boundaries that FAIL
review when violated. Use `/hv-decide` for the latter. It captures
rule + why + forbids + permits and is consulted as a constraint by `/hv-work`,
[`/hv-debug`](debugging.md), [`/hv-plan`](vision-and-plans.md), [`/hv-refactor`](../reference/slash-commands.md#hv-refactor), [`/hv-review`](review-and-ship.md), and [`/hv-vision`](vision-and-plans.md).

## See also

- Sibling persistence skill: [`docs/usage/decisions.md`](decisions.md)
