# Debugging

`/hv-debug` is for real bugs that need a systematic cycle — reproduce, hypothesize, verify, fix. If the root cause is already obvious and the fix is mechanical, reach for `/hv-go` or `/hv-work` instead.

## /hv-debug

Invoke with a bug ID: `/hv-debug B07`.

The skill reads the `[B07]` entry in `TODO.md` and any associated detail file, consults `KNOWLEDGE.md` for topics that match the bug's area, then works through a fixed cycle:

1. **Reproduce** — runs the bug's existing test or writes a minimal failing reproducer.
2. **Hypothesize** — the orchestrator model proposes a root cause based on the reproduction and project context.
3. **Verify** — the hypothesis is tested (log inspection, targeted reads, narrow experiment) before any code changes.
4. **Fix** — the worker model applies the fix. The reproducer must pass before the commit lands.
5. **Commit** — a single atomic commit tagged `fix: … [B07]` so `/hv-ship` can close the loop.

If the root cause was non-obvious — required extra verification rounds, contradicted the initial hypothesis, or touched a known-tricky subsystem — the skill nudges you to run `/hv-learn` so the insight lands in `KNOWLEDGE.md`.

`/hv-debug` uses the same isolation mode (`branch` or `worktree`) and model configuration as `/hv-work`. It refuses to start on a dirty working tree — stash or commit first.

## The cycle

Here is what the session looks like from the outside:

**Invoke**
```
/hv-debug B07
```

**Reproduce phase** — the skill runs the relevant test or writes a new failing one. You see something like:
```
Reproducer: tests/test_parser.py::test_empty_input  FAILED
```

**Hypothesis phase** — after reproduction the orchestrator surfaces a root cause candidate:
```
Hypothesis: empty-string input bypasses the null-guard on line 42 because
  the guard tests `if not value` rather than `if value is None`.
```

**Verify phase** — before touching code, the skill confirms the hypothesis holds (targeted read, probe, or narrow experiment). You see a short verification note:
```
Verified: `not ""` evaluates True — guard never fires for empty string.
```

**Fix and commit** — the worker model applies the minimal change, the reproducer is re-run, and the fix lands:
```
fix: guard against empty-string input in parser [B07]
```

If the root cause surprised you, the skill ends with a nudge:
```
Root cause was non-obvious. Consider running /hv-learn to capture this.
```

## When to use /hv-debug vs /hv-go vs /hv-work

Use `/hv-debug` when you don't yet know the root cause and need the reproduce → hypothesize → verify loop. The systematic cycle is the point.

Use `/hv-go` or `/hv-work` when:

- The root cause is already clear and the fix is a small, mechanical change.
- The item is a feature or task, not a bug.
- You want lighter-weight dispatch without the hypothesis machinery.

See [running work](running-work.md) for a full comparison of `/hv-go` and `/hv-work`.

## Competing hypotheses

The `debug.competingHypotheses` config option (default `false`) controls whether `/hv-debug` generates one hypothesis or fans out three parallel agents, each attacking the bug from a different angle (recent changes, data shape, concurrency/lifecycle).

| Value | Behavior |
|-------|----------|
| `false` (default) | Single hypothesis agent. Cheaper and faster; fine for most bugs where one angle is obviously primary. |
| `true` | Three parallel hypothesis agents. Better framing diversity on hard bugs where the right angle isn't obvious upfront. Costs roughly 3× the orchestrator budget at the hypothesis step; latency stays similar because the agents run concurrently. |

Turn it on when you have a class of bugs that consistently take multiple cycles to resolve. Keep it off when most bugs are single-cause and you don't want to pay for diversity you won't use.

See [configuration](configuration.md) for how to set this option.
