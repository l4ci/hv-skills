# hv-skills Guide

Contributor reference for hv-skills internals — preflight semantics, inter-skill contracts, host fallbacks, and the design rationale behind helpers and state. End-user documentation lives in [`docs/`](docs/).

## Preflight

Every non-init skill runs `.hv/bin/hv-preflight` in its Step 1 to verify the project state before doing any work. The helper is deliberately small — it only checks that `.hv/` is initialized and all expected helpers are present — and exits with one of three codes:

| Exit | Meaning | What the caller does |
|------|---------|----------------------|
| `0` | Fully initialized; all helpers present | Continue |
| `2` | Uninitialized — `.hv/` or a core data file is missing | Skills that mutate state (`/hv-capture`, `/hv-work`, etc.) auto-invoke `hv-init` via the `Skill` tool; skills that only observe (`/hv-pause`, `/hv-resume`) tell the user to run `/hv-init` first and stop |
| `3` | Partial install — data files are fine but one or more helpers are missing (typically after a plugin upgrade) | Re-invoke `hv-init` to refresh `.hv/bin/`; data files are preserved |

If the helper itself is absent, the skill treats that as exit 2 — a fresh project has never installed hv-skills. Standardizing on this one helper means a partial install self-heals the same way from every skill, instead of each skill picking a different sentinel file and a different fallback behavior.

## Host Question Conventions

Every skill that needs user input calls Claude Code's `AskUserQuestion` tool. Other hosts (Gemini CLI, some Copilot builds) may not provide an equivalent, or the tool call itself may fail.

When that happens, the skill falls back to plain text using the wording in its `Plain-text fallback:` line. A fallback **never loops**: ask once, either act on the reply or pick the Recommended interpretation and continue. Skills never stall on a missing tool, and they don't walk the user through the same decision twice.

The fallback always offers the same semantic choices as the `AskUserQuestion` options — only the surface changes.

## Branching template

Each autonomy-aware step in a skill branches on `.hv/config.json`'s `autonomy.level`:

- `"off"` (default) — surface the decision to the user. Usually a one-line nudge naming the next skill; an `AskUserQuestion` when more than one path is reasonable (e.g. `/hv-debug` Step 11).
- `"auto"` or `"loop"` — **invoke the next skill via the `Skill` tool. No prompt. No confirmation. No "want me to…" question. No alternatives offered.** Pass any context the next skill needs in the brief, then dispatch.

**Forbidden under `auto`/`loop`.** The user opted in by setting the level — every confirmation question undoes that. Specifically don't:

- Ask *"Want me to invoke `/hv-learn` now?"* or *"Run `/hv-refactor`?"*
- Offer alternatives like *"…or push to origin first?"* or *"…or just stop here?"*
- Justify holding off ("conversation is long", "user might prefer X", "verifier dispatch is expensive") — those are exactly the rationalizations the autonomy setting is meant to bypass. If the trigger fires, dispatch.
- Insert a "checkpoint" the spec doesn't call for. The spec's checkpoints are the destination skill's own gates (`learn.verify`, `ship.review`, `refactor.confirmBeforeExecute`) — those still fire. Adding a meta-checkpoint above them is the failure mode this rule prevents.

Loop-continuation steps run only when `level == "loop"`; skip for `"off"` and `"auto"`. The destination skill's own gates still fire under autonomy regardless of level.

## Learn Trigger

`/hv-work` Step 13 and `/hv-ship` Step 8.5 share one trigger condition — capture learnings when at least one is true:

- 2+ items resolved in the cycle
- ≥5 files touched
- A hard bug that took multiple debug cycles to land

Skip for single-item fixes, pure mechanical work, and dependency bumps. Don't fire if `/hv-learn` already ran this session.

`/hv-debug` Step 12 uses a different signal (root cause was non-obvious from reading the code alone) and stays inline; this section covers `/hv-work` and `/hv-ship` only.

## Active-state model

hv-skills tracks two distinct kinds of "active" — they are deliberately not merged.

- **Item-level active** — `.hv/status.json`, populated by `hv-status-add` / `hv-status-remove`. Short-lived, tied to a git branch or worktree, exists only while a `/hv-work` or `/hv-debug` cycle is in flight. Drives `/hv-resume`, `/hv-status`, and `/hv-pause`'s reconciliation against `git branch` / `git worktree list`.
- **Milestone-level active** — the `status:` field in the frontmatter of `.hv/milestones/MNN.md` (one of `planned` / `active` / `shipped` / `archived`), queried by `hv-vision-active` and `hv-vision-list`. Long-lived and strategic — a milestone stays `active` across many sessions, branches, and items.

A new helper that needs to check "active" must decide which sense it means and consult the right source. The two concepts are independent: an item can be in flight under no active milestone (`status.json` populated, no milestone tag), and a milestone can be `active` with nothing currently in flight against it (`hv-vision-active` returns it, `status.json` empty). Don't reach for whichever one is closer at hand — pick the source that matches the question being asked.

## Milestones are excluded from archival

`hv-archive-old`, `hv-complete`, and `hv-reconcile` deliberately ignore `.hv/milestones/`. Milestones use the `planned` / `active` / `shipped` / `archived` status flow on the per-milestone detail file, not the `## Completed` section in `TODO.md`. A milestone is never "archived old" by elapsed time; retirement is explicit via `hv-vision-status MNN archived` (work abandoned) or `hv-vision-status MNN shipped` (work completed). The two lifecycles are separate and shouldn't be unified.

## Helpers

### Why helpers matter

Every skill step that would otherwise chain several tool calls (read file → compute → write file, or run several `git` queries and parse them) becomes one subprocess with structured output. This reduces context token consumption on each invocation and keeps the SKILL.md files focused on *what* to do rather than *how* to parse JSON or regex Markdown. The full helper catalogue lives in [`docs/reference/cli-helpers.md`](docs/reference/cli-helpers.md); this section is the rationale, not the index.

### Resolving the source bin/

`/hv-init` copies helpers from the installed plugin, trying these paths in order:

1. `$CLAUDE_PLUGIN_ROOT/bin/` — set by Claude Code when the skill runs from an installed plugin
2. `~/.claude/plugins/*/hv-skills/bin/`, `~/.claude/plugins/hv-skills/bin/` — standard plugin install locations
3. `~/.agents/skills/hv-skills/bin/`, `~/.agents/skills/bin/` — stow-based install locations
4. Repo-local `bin/` if the skill is running from a cloned repo

If none of these resolve, `/hv-init` exits with a clear error. The scripts themselves are verified by `test/smoke.sh` in the repo — run it if you suspect a helper is misbehaving.

## Dependency Categories (used by /hv-refactor)

When assessing each friction point, `/hv-refactor` classifies its dependencies into one of four categories. The classification drives the fix strategy.

### 1. In-process

Pure computation, in-memory state, no I/O. Always fixable — merge the modules and test directly.

### 2. Local-substitutable

Dependencies that have local test stand-ins (e.g., PGLite for Postgres, in-memory filesystem). Fixable if the test substitute exists. The deepened module is tested with the local stand-in running in the test suite.

### 3. Remote but owned (Ports & Adapters)

Your own services across a network boundary (microservices, internal APIs). Define a port (interface) at the module boundary. The deep module owns the logic; the transport is injected. Tests use an in-memory adapter, production uses the real HTTP/gRPC/queue adapter.

### 4. True external (Mock)

Third-party services (Stripe, Twilio, etc.) you don't control. Mock at the boundary. The module takes the external dependency as an injected port; tests provide a mock implementation.
