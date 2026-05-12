---
name: hv-context
description: Capture or refine a domain term in .hv/CONTEXT.md — the project's canonical glossary. Use on "save X as Y", "let's call this X", "by Y I mean…", "add X to context", or to refine an existing term. Distinct from /hv-learn (passive gotchas) and /hv-decide (hard boundaries) — CONTEXT.md is the project's vocabulary, consulted before answering or brainstorming so terms stay consistent.
user-invocable: true
---

**Print the banner below verbatim before any other action — skip if dispatched as a subagent.** See `references/banner-preamble.md`.

```
════════════════════════════════════════════════════════════════════════
  📖  hv-context  ·  capture or refine domain terms in CONTEXT.md
  triggers: "save X as Y", "by X I mean…"  ·  pairs: hv-vision, hv-capture
════════════════════════════════════════════════════════════════════════
```

# hv-context — Capture Project Terminology

Add or refine an entry in `.hv/CONTEXT.md` so future work uses the same canonical name and definition. Terminology drift is silent — sharpening a term once saves every future cycle from re-deciding what it means.

## Step 1 — Preflight

```bash
.hv/bin/hv-preflight
```

See `docs/reference/preflight.md` for exit-code handling.

**Initialize task list.** When `TaskCreate` is loaded (load via `ToolSearch select:TaskCreate,TaskUpdate` if not), create one task per phase below — e.g. `TaskCreate(subject="Resolve term + definition", description="Surface the term name and a one-paragraph definition")`. Mark each `in_progress` when starting and `completed` when its observable outcome lands; short-circuited phases (no existing term, single-repo mode skipping the umbrella ask) get `completed` with the no-op reason in the description.

Phases:

1. *Resolve* — term name + definition + optional aliases/nots resolved (Step 2)
2. *Check for conflicts* — existing entry surveyed; user picks keep/replace/merge if found (Step 3)
3. *Write* — `bin/hv-context-add` writes the entry (Step 4)
4. *Index* — `hv-context-add` regenerates the CLAUDE.md block (and `CONTEXT-MAP.md` in umbrella mode) (Step 4 cont.)
5. *Confirm* — compact captured-block report (Step 5)

## Step 2 — Resolve Term and Definition

The argument forms determine whether `Step 2` asks any questions:

- **One-shot, fully-specified:** `/hv-context backlog "the canonical project queue (.hv/TODO.md)" --alias "task list,todo list" [--not "session state"] [--repo umbrella|<name>]` — skip to Step 3 with the values from args.
- **Term + definition only:** `/hv-context <term> "<definition>"` — proceed to Step 3 with no aliases/nots; skip the optional-fields prompt.
- **Term only:** `/hv-context <term>` — ask for definition via `AskUserQuestion`; skip aliases/nots unless the user volunteers them.
- **No args:** ask for term and definition in two single-question turns. **Don't ask what the codebase already implies** — skip aliases/nots prompts unless context (`KNOWLEDGE.md` topics, recent commits, current `## Project Context` block in `CLAUDE.md`) makes a candidate alias obvious; even then, propose inline rather than blocking on a question.

In umbrella mode, the target file depends on `--repo` and cwd — see `references/context-umbrella-scoping.md` for the resolution table. Single-repo mode always writes to `.hv/CONTEXT.md` and ignores `--repo`.

## Step 3 — Check for Conflicts

Run `.hv/bin/hv-context-query <term>` to see whether the term already exists. If it does, surface the existing entry and ask the user via `AskUserQuestion`:

- **Header:** `"Term"`
- **Question:** *"Term `<term>` already exists. What should we do?"*
- **Options** (single-select):
  1. *"Replace definition, union aliases (Recommended)"* — *"Replace the definition with your new wording, merge new aliases into the existing list, preserve the original date stamp."*
  2. *"Replace definition + bump date (`--touch`)"* — *"Same as above but mark the entry as freshly refined."*
  3. *"Cancel"* — *"Skip — nothing is written."*

Show the existing entry inline above the question.

If the term doesn't exist, also check for **alias collisions** by scanning the `## Project Context` block in `CLAUDE.md` for any of the new aliases. If one matches another term's alias, surface the collision and stop — `hv-context-add` will refuse with exit 4 anyway, but a pre-check is friendlier:

> *"Alias `<x>` is already an alias of term `<other-term>`. Either pick a different alias, or refine the existing term instead — what would you like to do?"*

(`AskUserQuestion`: *Use a different alias*, *Refine `<other-term>` instead*, *Cancel*.)

## Step 4 — Write and Index

Invoke `bin/hv-context-add` with the resolved arguments. Example calls:

**Single-repo, new term:**
```bash
.hv/bin/hv-context-add backlog \
  --def "The canonical project queue (.hv/TODO.md). Items are zero-padded IDs ([B01]/[F01]/[T01])." \
  --alias "task list,todo list"
```

**Umbrella, sub-repo:**
```bash
.hv/bin/hv-context-add agent-loop \
  --def "The repeating prompt-stage loop in repo-a." \
  --repo repo-a
```

**Update existing, bump date:**
```bash
.hv/bin/hv-context-add backlog \
  --def "<refined definition>" \
  --alias "queue" \
  --touch
```

`hv-context-add` regenerates the `## Project Context` managed block (and `.hv/CONTEXT-MAP.md` in umbrella mode) before exiting.

## Step 5 — Confirm

Tell the user, in one compact block, what was captured:

```
Captured "<term>" into .hv/CONTEXT.md.
  aliases: <a, b>     (or "none" if empty)
  nots:    <x, y>     (or omit the line if empty)

Updated CLAUDE.md ## Project Context block.
```

In umbrella mode, prepend the target file: *"Captured into .hv/contexts/repo-a/CONTEXT.md."*

## Key Principles

- **Explicit signal only.** Never infer a write from implicit term usage — only when the user clearly defines or refines a term. The signal phrases are listed in the spec; this skill is the deliberate entry point for everything else.
- **Don't ask what the code can answer.** Aliases, nots, target file — derive from args, cwd, and `hv-resolve-repo` before asking. Ask only when ambiguous.
- **One sentence's-worth of definition is fine.** The first sentence becomes the gloss in the CLAUDE.md block; longer definitions stay in CONTEXT.md but the gloss must stand alone.
- **Aliases are user-stated only.** Don't propose aliases the user didn't ask for. Conflict-call-out (during a `/hv-work` cycle) can suggest "you used X — CONTEXT calls this Y" but only `/hv-context` writes them.
- **No verifier.** Manual confirmation is the verification.
- **Sibling persistence skills.** `/hv-context`, `/hv-learn`, and `/hv-decide` share one contract (persist + index `CLAUDE.md` + confirm) and intentionally diverge on gate strength — see `references/persistence-skills.md`.

## References

- [`references/banner-preamble.md`](../references/banner-preamble.md) — Banner-print rule shared by every skill.
- [`references/context-umbrella-scoping.md`](../references/context-umbrella-scoping.md) — Umbrella-mode resolution for the `/hv-context` artifact.
- [`references/persistence-skills.md`](../references/persistence-skills.md) — Shared spine and divergence axes for the persistence trio (`/hv-context`, `/hv-learn`, `/hv-decide`).
