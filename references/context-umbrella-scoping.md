# `/hv-context` target-file resolution (umbrella mode)

Used by `/hv-context` Step 2 to resolve the target glossary file before calling `bin/hv-context-add`. The skill's prose cites this reference; the rules below live here so the call site stays short.

`/hv-context` is the only persistence-trio skill whose target file changes under umbrella mode — `.hv/KNOWLEDGE.md` and `.hv/DECISIONS.md` are always umbrella-shared, while glossaries split per-sub-repo so each project speaks its own vocabulary. See `references/persistence-skills.md` for the trio overview and `references/umbrella-mode.md` for the general umbrella mechanics.

## Resolution table

Target file resolution mirrors `bin/hv-context-add` defaults:

| Invocation | Target file |
|---|---|
| `--repo umbrella` | `.hv/CONTEXT.md` |
| `--repo <name>` | `.hv/contexts/<name>/CONTEXT.md` |
| `--repo` omitted, cwd inside a registered sub-repo (resolved via `hv-resolve-repo`) | that sub-repo's `.hv/contexts/<name>/CONTEXT.md` |
| `--repo` omitted, cwd at umbrella root | ask once via `AskUserQuestion` — *"Capture this as an umbrella-shared term, or scope to a sub-repo?"* Options: *Umbrella-shared (Recommended)*, one option per registered sub-repo. |

## Single-repo behavior

When `umbrella.enabled` is false (or `.hv/repos.json` lists no sub-repos), `/hv-context` always writes to `.hv/CONTEXT.md`. The `--repo` flag is silently ignored in single-repo mode — `hv-context-add` accepts the flag for forward-compat and behaves as if it were omitted.

## Why ask at the umbrella root

The cwd heuristic resolves to exactly one sub-repo inside any registered path. At the umbrella root, cwd resolves to nothing, and the term's scope (umbrella-shared vs. sub-repo-local) is a genuine choice — neither option is the obvious default. Loop-mode auto-pick rules (`references/authoring-conventions.md` rule *"Routine routing/tagging auto-picks Recommended in loop mode"*) do apply here: a single `(Recommended)` option for *Umbrella-shared* lets the loop drain past the prompt without stalling.

## See also

- `references/umbrella-mode.md` — general umbrella mechanics, sub-repo registry, resolution helpers.
- `references/persistence-skills.md` — the trio contract; explains why only `/hv-context` has this routing.
- `docs/reference/context-md.md` — `CONTEXT.md` file format and `bin/hv-context-add` flag reference.
