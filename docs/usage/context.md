# Capturing terminology — `/hv-context` and `CONTEXT.md`

`.hv/CONTEXT.md` is the project's canonical glossary — one entry per domain term, with a definition, optional aliases, and optional "not" clarifications. The AI consults it before answering or brainstorming so terms stay consistent across cycles, and flags inline when your wording conflicts with the canonical name or its meaning.

This is distinct from:

- **`.hv/KNOWLEDGE.md`** (`/hv-learn`) — passive *gotchas, conventions, constraints*. What you wish you'd known.
- **`.hv/DECISIONS.md`** (`/hv-decide`) — active *boundaries with forbids/permits*. What the project has committed to.
- **`.hv/MAP.md`** (`/hv-map`) — *subsystems*. Where things live.
- **`.hv/CONTEXT.md`** — *vocabulary*. What things are called.

## Capturing a term

`/hv-context` is the deliberate entry point. Useful invocation forms:

```text
/hv-context backlog "the canonical project queue (.hv/TODO.md). Items are zero-padded IDs."
/hv-context backlog "<def>" --alias "task list,todo list"
/hv-context backlog "<refined def>" --touch
/hv-context agent-loop "<def>" --repo repo-a       # umbrella sub-repo
/hv-context session "<def>" --repo umbrella        # umbrella shared
```

The skill also writes inline during normal conversation when you produce an unambiguous definitional signal:

- *"let's call this X"* / *"the canonical name for this is X"*
- *"by X I mean Y"* / *"X means Y"* / *"X is our term for Y"*
- *"refine X — it should mean Y"* (existing term update)
- Direct command: *"save X as Y"* / *"add X to context"*

If your wording is ambiguous (you mention a term but don't define it), the skill won't write; it may ask once for clarification. There is no end-of-session sweep — terms not captured at the moment they resolve are captured later via explicit `/hv-context` invocations.

## Conflict call-out

When the AI sees you using a term that conflicts with `CONTEXT.md`, it flags the conflict inline:

- **Synonym** — *"You said 'task list' — this project's CONTEXT calls this **backlog**. Want me to use that going forward, or run `/hv-context` to update the canonical name?"*
- **Drift** — *"You're using **decision** to mean a soft preference. CONTEXT defines **decision** as a hard boundary captured in DECISIONS.md. Did you mean a learning, or run `/hv-context` to refine the term?"*

These are one-line interruptions, not blocking. You answer in flow.

## Aliases and "not" clarifications

Aliases are user-stated synonyms — informal phrasings that map to the canonical term. They drive synonym detection. Add them when:

- The term has a common informal name you want flagged ("task list" → **backlog**).
- A previous name was deprecated and you want to map old usages to the new term.

Don't fabricate aliases. If you didn't ever call it that, don't list it.

The optional `**Not:**` line distinguishes the term from a near-miss concept that is *not* the term. Use it sparingly — only when the contrast is load-bearing.

## Umbrella mode

In umbrella projects, glossaries split:

- `.hv/CONTEXT.md` — terms shared across all sub-repos (cross-cutting domain concepts).
- `.hv/contexts/<repo>/CONTEXT.md` — terms scoped to one sub-repo.
- `.hv/CONTEXT-MAP.md` — auto-generated pointer index.

`/hv-context` resolves the target file from your cwd: inside a sub-repo it writes there; at the umbrella root it asks once whether the term is umbrella-shared. Override with `--repo umbrella` or `--repo <name>`. See `docs/usage/umbrella-mode.md` for more.

## See also

- File format reference: [`docs/reference/context-md.md`](../reference/context-md.md)
- Helper reference: [`docs/reference/cli-helpers.md`](../reference/cli-helpers.md)
- Sibling skills: [`docs/usage/learning.md`](learning.md), [`docs/usage/decisions.md`](decisions.md)
