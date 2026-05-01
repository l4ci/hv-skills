# Learning

`/hv-learn` distills durable knowledge from a session into `KNOWLEDGE.md` so
future runs don't rediscover the same gotchas.

## /hv-learn

`/hv-learn` scans the current session, extracts non-obvious knowledge, groups
the entries by topic, and writes them to `.hv/KNOWLEDGE.md`. After writing, it
updates the managed `hv-knowledge` block in `CLAUDE.md` so the topic list stays
in sync — `/hv-work` reads that index to know when the current task should
consult `KNOWLEDGE.md`.

## What gets captured (and what doesn't)

**Captured:**

- Gotchas — non-obvious failure modes
- Conventions — project-specific patterns that aren't obvious from reading code
- Constraints — invariants, compatibility rules
- Debugging insights — root causes for hard-won bugs
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

## When to invoke

Invoke `/hv-learn` after a session that surfaced real discoveries: two or more
gotchas resolved in a cycle, a broad change touching many files, or a hard bug
whose root cause wasn't obvious. Skip it for single-item fixes and mechanical
changes where nothing worth re-using was learned.

Skills nudge or auto-invoke `/hv-learn` depending on your
[autonomy](autonomy.md) level — at lower autonomy levels you get a prompt; at
higher levels the skill runs automatically at the end of a work cycle.

## Verification

`learn.verify` in `.hv/config.json` controls a second-opinion pass. When set to
`true`, `/hv-learn` dispatches a fresh Opus subagent that reads only the updated
`KNOWLEDGE.md` diff — no session context — and judges each new bullet on four
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
